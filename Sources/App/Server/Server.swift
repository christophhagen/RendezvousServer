//
//  Server.swift
//  App
//
//  Created by Christoph on 05.01.20.
//

import Foundation
import Vapor
import CryptoKit25519

/// - Note: Whenever one of the typealiases below is used in the code,
/// then the data is assumed to be of correct form.

/// The public identity key of a device
typealias DeviceKey = Data

/// The public identity key of a user
typealias UserKey = Data

/// The id of a topic
typealias TopicID = Data

/// The id of a message
typealias MessageID = Data

/// An authentication token
typealias AuthToken = Data

/**
 The `Server` class handles all request related to user and device management, as well as adminstrative tasks.
 */
final class Server: Logger {
    
    // MARK: Constants
    
    
    
    // MARK: Private variables
    
    /// The interface with the file system
    let storage: Storage
    
    /// The administrator authentication token (16 byte).
    var adminToken: Data
    
    /// The users currently registered with the server.
    private var internalUsers = [UserKey : RV_InternalUser]()
    
    /// The authentication tokens for all internal devices.
    private var authTokens: [DeviceKey : AuthToken]
    
    /// The tokens to authenticate the messages to the notification servers
    private var notificationTokens: [DeviceKey : Data]
    
    /// The data to send to each internal device.
    private var deviceData: [DeviceKey : RV_DeviceDownload]
    
    /// The data last sent to each internal device (in case of delivery failure)
    private var oldDeviceData: [DeviceKey : RV_DeviceDownload]
    
    /// The info about all topics currently available on the server
    private var topics: [TopicID : RV_TopicState]
    
    /// The users which are allowed to register on the server, with their pins, the remaining tries, and the time until which they can register.
    private var usersAllowedToRegister: [String : RV_AllowedUser]
    
    /// The notification server to use for push notifications if the user doesn't specify an alternative.
    let defaultNotificationServer: URL
    
    /// Indicate if this server is used for development
    let isDevelopmentServer: Bool
    
    /// Indicate if static file serving should be handled.
    let shouldServeStaticFiles: Bool
    
    /// The delegate which handles file operations
    //weak var delegate: UserManagementDelegate! = nil
    
    // MARK: Saving and loading
    
    convenience init(config: Config) throws {
        let storage = Storage(baseURL: config.baseDirectory)
        
        if let data = try storage.managementData() {
            try self.init(
                storedData: data,
                storage: storage,
                development: config.isDevelopmentServer,
                serveStaticFiles: config.shouldServeStaticFiles)
        } else {
            Server.log(info: "No management data to load.")
            self.init(
                storage: storage,
                development: config.isDevelopmentServer,
                serveStaticFiles: config.shouldServeStaticFiles,
                notificationServer: config.notificationServer)
        }

        if isDevelopmentServer {
            log(info: "Development mode enabled")
        }
        log(info: "Static file serving: \(shouldServeStaticFiles)")
    }
    /**
     Create an empty management instance.
     - Note: The admin authentication token will be set to all zeros.
     */
    private init(storage: Storage, development: Bool, serveStaticFiles: Bool, notificationServer: URL) {
        self.adminToken = Data(repeating: 0, count: Constants.authTokenLength)
        self.usersAllowedToRegister = [:]
        self.internalUsers = [:]
        self.authTokens = [:]
        self.notificationTokens = [:]
        self.deviceData = [:]
        self.oldDeviceData = [:]
        self.topics = [:]
        
        self.defaultNotificationServer = notificationServer
        self.isDevelopmentServer = development
        self.shouldServeStaticFiles = serveStaticFiles
        self.storage = storage
    }
    
    /**
     Create a management instance.
     - Parameter data: The data stored on disk.
     - Parameter delegate: The delegate which handles file operations.
     */
    private convenience init(storedData data: Data, storage: Storage, development: Bool, serveStaticFiles: Bool) throws {
        do {
            let object = try RV_ManagementData(serializedData: data)
            self.init(object: object, storage: storage, development: development, serveStaticFiles: serveStaticFiles)
        } catch {
            throw ServerError.invalidManagementData
        }
    }
    
    /**
     Create a management instance from a protobuf object.
     
     - Parameter object: The protobuf object containing the data
     */
    private init(object: RV_ManagementData, storage: Storage, development: Bool, serveStaticFiles: Bool) {
        self.adminToken = object.adminToken
        self.usersAllowedToRegister = object.allowedUsers
        self.internalUsers = object.internalUsers.dict { $0.publicKey }
        self.authTokens = object.authTokens.reduce(into: [:]) { $0[$1.key] = $1.value }
        self.notificationTokens = object.notificationTokens.dict { ($0.key, $0.value) }
        self.deviceData = object.deviceData.dict { ($0.deviceKey, $0.data) }
        self.oldDeviceData = object.oldDeviceData.dict { ($0.deviceKey, $0.data) }
        self.topics = object.topics.dict { $0.info.topicID }
        
        guard let url = URL(string: object.notificationServer) else {
            fatalError("Invalid notification server: \(object.notificationServer)")
        }
        self.defaultNotificationServer = url
        self.isDevelopmentServer = development
        self.shouldServeStaticFiles = serveStaticFiles
        self.storage = storage
    }
    
    /// Serialize the management data for storage on disk.
    private var data: Data {
        let object = RV_ManagementData.with { item in
            item.adminToken = adminToken
            item.allowedUsers = usersAllowedToRegister
            item.internalUsers = Array(internalUsers.values)
            item.authTokens = authTokens.map(RV_ManagementData.KeyValuePair.from)
            item.notificationTokens = notificationTokens.map(RV_ManagementData.KeyValuePair.from)
            item.deviceData = deviceData.map(RV_ManagementData.DeviceData.from)
            item.oldDeviceData = oldDeviceData.map(RV_ManagementData.DeviceData.from)
            item.topics = Array(topics.values)
            
            item.notificationServer = defaultNotificationServer.absoluteString
        }
        
        // Protobuf serialization should never fail, since it is correctly setup.
        return try! object.serializedData()
    }
    
    func didChangeData() {
        do {
            try storage.store(managementData: data)
        } catch {
            log(error: "Failed to store management data: \(error)")
        }
    }
    
    func reset() throws {
        log(warning: "Deleting all server data")
        try storage.deleteAllData()
        self.adminToken = Data(repeating: 0, count: Constants.authTokenLength)
        self.usersAllowedToRegister = [:]
        self.internalUsers = [:]
        self.authTokens = [:]
        self.deviceData = [:]
        self.oldDeviceData = [:]
    }
    
    /**
     Check the authentication of a device from a user.
     
     - Parameter user: The received user public key
     - Parameter device: The received device public key
     - Parameter token: The received authentication token
     - Returns: The information about the user.
     - Throws: `RendezvousError.authenticationFailed`, if the user or device doesn't exist, or the token is invalid
     */
    @discardableResult
    func authenticateUser(_ user: UserKey, device: DeviceKey, token: AuthToken) throws -> RV_InternalUser {
        // Check if authentication is valid
        guard let user = internalUsers[user],
            user.devices.contains(where: {$0.deviceKey == device}),
            let deviceToken = authTokens[device],
            constantTimeCompare(deviceToken, token) else {
                throw RendezvousError.authenticationFailed
        }
        return user
    }

    /**
    Check the authentication of a device.
    
    - Parameter device: The received device public key
    - Parameter token: The received authentication token
    - Throws: `RendezvousError.authenticationFailed`, if the device doesn't exist, or the token is invalid
    */
    func authenticateDevice(_ device: DeviceKey, token: AuthToken) throws {
        // Check if authentication is valid
        guard let deviceToken = authTokens[device],
            constantTimeCompare(deviceToken, token) else {
                throw RendezvousError.authenticationFailed
        }
    }

    // MARK: Internal state
    
    /**
     Check if a user is allowed to register.
     
     - Parameter name: The username
     - Parameter pin: The random pin of the user, handed out by the administrator.
     - Returns: `true`, if the user is allowed to register.
     - Note: Removes users which enter the pin wrong too often, or when the pin is expired.
     */
    func canRegister(user name: String, pin: UInt32) -> Bool {
        // Check that name is among those allowed to register
        guard let user = usersAllowedToRegister[name] else {
            return false
        }
        
        // If pin is expired, block registration
        guard user.expiry > timeInSeconds() else {
            usersAllowedToRegister[name] = nil
            didChangeData()
            log(info: "User '\(name)': Pin expired")
            return false
        }
        
        // If pin is valid, do nothing
        if user.pin == pin {
            return true
        }
        
        // If all tries are used, block registration
        guard user.numberOfTries > 0 else {
            usersAllowedToRegister[name] = nil
            didChangeData()
            log(info: "User '\(name)': Too many wrong pin entries")
            return false
        }
        // Decrease the number of allowed guesses
        usersAllowedToRegister[name]!.numberOfTries -= 1
        log(info: "User '\(name)': Wrong pin entry (\(usersAllowedToRegister[name]!.numberOfTries) tries left)")
        return false
    }
    
    /// Check that the notification server has a valid url
    func isValid(notificationServer: String) throws {
        if notificationServer != "", URL(string: notificationServer) == nil {
            throw RendezvousError.invalidRequest
        }
    }
    
    func allow(user: RV_AllowedUser) {
        usersAllowedToRegister[user.name] = user
    }
    
    func userExists(_ user: String) -> Bool {
        internalUsers.values.contains { $0.name == user }
    }
    
    func userExists(_ user: UserKey) -> Bool {
        internalUsers[user] != nil
    }
    
    func user(with publicKey: UserKey) -> RV_InternalUser? {
        internalUsers[publicKey]
    }
    
    func userDevices(_ user: UserKey, app: String) -> [RV_InternalUser.Device]? {
        internalUsers[user]?.devices.filter { $0.application == app }
    }
    
    func add(topic: RV_Topic) {
        topics[topic.topicID] = .with {
            $0.info = topic
            $0.chain = .with { chain in
                chain.chainIndex = 0
                chain.output = topic.topicID
            }
        }
    }
    
    func update(chain: RV_TopicState.ChainState, for topic: TopicID) {
        topics[topic]?.chain = chain
    }
    
    func topic(id: Data) -> RV_TopicState? {
        return topics[id]
    }
    
    func add(topicMessage: RV_DeviceDownload.Message, for device: DeviceKey, of user: UserKey) {
        deviceData[device]!.messages.append(topicMessage)
        push(topicMessage: topicMessage, to: device, of: user)
    }

    func add(topicUpdate: RV_Topic, for device: DeviceKey, of user: UserKey) {
        deviceData[device]!.topicUpdates.append(topicUpdate)
        push(topicUpdate: topicUpdate, to: device, of: user)
    }
    
    func add(topicKeyMessages messages: [RV_TopicKeyMessage], for device: DeviceKey) {
        deviceData[device]!.topicKeyMessages.append(contentsOf: messages)
    }
    
    private func add(deliveryReceipts receipts: [TopicID : UInt32], from sender: UserKey, to device: DeviceKey) -> RV_DeviceDownload.Receipt {
        var data = deviceData[device]!
        defer { deviceData[device] = data }
        guard let index = data.receipts.firstIndex(where: { $0.sender == sender }) else {
            // No sender yet, simply add all topics
            let receipt = RV_DeviceDownload.Receipt.with {
                $0.sender = sender
                $0.receipts = receipts.map { topic, chainIndex in
                    .with { r in
                        r.id = topic
                        r.index = chainIndex
                    }
                }
            }
            data.receipts.append(receipt)
            return receipt
        }

        // Only return all receipts which are actually new for the device
        return .with {
            $0.sender = sender
            $0.receipts = receipts.compactMap { (topic, chainIndex) in
                let r = RV_DeviceDownload.Receipt.TopicReceipt.with {
                    $0.id = topic
                    $0.index = chainIndex
                }
                
                // Check if a previous receipt exists for the topic
                guard let i = data.receipts[index].receipts.firstIndex(where: { $0.id == topic }) else {
                    data.receipts[index].receipts.append(r)
                    return r
                }
                // Check if the receipt needs to be updated
                let oldIndex = data.receipts[index].receipts[i].index
                guard chainIndex > oldIndex else {
                    return nil
                }
                data.receipts[index].receipts[i] = r
                return r
            }
        }
    }
    
    func send(deliveryReceipts receipts: [TopicID : UInt32], to user: UserKey, from sender: UserKey, in app: String) {
        guard let devices = self.userDevices(user, app: app) else {
            return
        }
        #warning("Prevent multiple receipts from devices of the same user")
        for device in devices.filter({ $0.isActive }) {
            // Add the receipts to device bundle
            let newReceipts = add(deliveryReceipts: receipts, from: sender, to: device.deviceKey)
            // Send the notification
            push(receipts: newReceipts, to: device.deviceKey, of: user)
        }
        
    }
    
    func set(remainingTopicKeys count: UInt32, for device: DeviceKey) {
        deviceData[device]!.remainingTopicKeys = count
    }
    
    func set(remainingPreKeys count: UInt32, for device: DeviceKey) {
        deviceData[device]!.remainingPreKeys = count
    }
    
    func set(authToken: AuthToken, for device: DeviceKey) {
        authTokens[device] = authToken
    }
    
    func set(userInfo: RV_InternalUser) {
        internalUsers[userInfo.publicKey] = userInfo
    }
    
    func decrementRemainingTopicKeys(for device: DeviceKey) {
        deviceData[device]!.remainingTopicKeys -= 1
    }
    
    func deviceExists(_ device: DeviceKey) -> Bool {
        authTokens[device] != nil
    }
    
    // MARK: Push
    
    func notificationServer(for user: UserKey) -> URL {
        let server = internalUsers[user]!.notificationServer
        guard server != "" else {
            return defaultNotificationServer
        }
        // Urls are validated when user data is changed
        return URL(string: server)!
    }
    
    func add(notificationToken: Data, for device: DeviceKey) {
        notificationTokens[device] = notificationToken
    }
    
    func notificationToken(for device: DeviceKey) -> Data? {
        notificationTokens[device]
    }
    
    func getAndClearDeviceData(_ device: DeviceKey) -> RV_DeviceDownload {
        let data = deviceData[device]!
        deviceData[device] = .with {
            $0.remainingPreKeys = data.remainingPreKeys
            $0.remainingTopicKeys = data.remainingTopicKeys
        }
        oldDeviceData[device] = data
        return data
    }
    
    func oldDeviceData(_ device: DeviceKey) -> RV_DeviceDownload {
        oldDeviceData[device]!
    }
    
    func createDeviceData(for device: DeviceKey) {
        deviceData[device] = .init()
        oldDeviceData[device] = .init()
    }
    
    func createDeviceData(for device: DeviceKey, remainingPreKeys: UInt32, remainingTopicKeys: UInt32) {
        deviceData[device] = .with {
            $0.remainingPreKeys = remainingPreKeys
            $0.remainingTopicKeys = remainingTopicKeys
        }
        oldDeviceData[device] = .init()
    }
    
    func delete(device: DeviceKey) {
        authTokens[device] = nil
        deviceData[device] = nil
    }
    
    func delete(user: UserKey) {
        internalUsers[user] = nil
    }
    
    func remove(allowedUser: String) {
        usersAllowedToRegister[allowedUser] = nil
    }
    
    // MARK: Helper functions
    
    /**
     Create a new random authentication token.
     - Returns: The binary token.
     */
    func makeAuthToken() -> Data {
        return randomBytes(count: Constants.authTokenLength)
    }

}

extension Array {
    
    func dict<Key>(_ assigningKeys: (Element) -> Key) -> [Key : Element] {
        return reduce(into: [:]) { $0[assigningKeys($1)] = $1 }
    }
    
    func dict<Key,Value>(_ assigningKeysAndValues: (Element) -> (Key, Value)) -> [Key : Value] {
        return reduce(into: [:]) { result, element in
            let (key, value) = assigningKeysAndValues(element)
            result[key] = value
        }
    }
}
