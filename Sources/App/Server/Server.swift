//
//  Server.swift
//  App
//
//  Created by Christoph on 05.01.20.
//

import Foundation
import Vapor
import CryptoKit25519

/**
 The `Server` class handles all request related to user and device management, as well as adminstrative tasks.
 */
final class Server: Logger {
    
    // MARK: Constants
    
    /// The time interval after which pins expire (in seconds)
    static let pinExpiryInterval: UInt32 = 60 * 60 * 32 * 7
    
    /// The number of times a pin can be wrong before blocking the registration
    static let pinAllowedTries: UInt32 = 3
    
    /// The maximum value for the pin
    static let pinMaximum: UInt32 = 100000
    
    /// The maximum allowed characters for user names
    static let maximumNameLength = 32
    
    /// The number of bytes for an authentication token
    static let authTokenLength = 16
    
    /// The length of a topic id
    static let topicIdLength = 12
    
    /// The length of a message id
    static let messageIdLength = 12
    
    /// The length of an app id
    static let appIdLength = 10
    
    /// The maximum length of message metadata
    static let maximumMetadataLength = 100
    
    // MARK: Private variables
    
    /// The interface with the file system
    let storage: Storage
    
    /// The administrator authentication token (16 byte).
    var adminToken: Data
    
    /// The users currently registered with the server.
    private var internalUsers = [Data : RV_InternalUser]()
    
    /// The authentication tokens for all internal devices.
    private var authTokens: [Data : Data]
    
    /// The tokens to authenticate the messages to the notification servers
    private var notificationTokens: [Data : Data]
    
    /// The data to send to each internal device.
    private var deviceData: [Data : RV_DeviceDownload]
    
    /// The data last sent to each internal device (in case of delivery failure)
    private var oldDeviceData: [Data : RV_DeviceDownload]
    
    /// The info about all topics currently available on the server
    private var topics: [Data : RV_TopicState]
    
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
        self.adminToken = Data(repeating: 0, count: Server.authTokenLength)
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
     - Parameter delegate: The delegate which handles file operations.
     */
    private init(object: RV_ManagementData, storage: Storage, development: Bool, serveStaticFiles: Bool) {
        self.adminToken = object.adminToken
        self.usersAllowedToRegister = object.allowedUsers
        self.internalUsers = [:]
        self.authTokens = [:]
        self.notificationTokens = [:]
        self.deviceData = [:]
        self.oldDeviceData = [:]
        self.topics = [:]
        
        self.defaultNotificationServer = URL(string: object.notificationServer)!
        self.isDevelopmentServer = development
        self.shouldServeStaticFiles = serveStaticFiles
        self.storage = storage
        
        object.internalUsers.forEach { internalUsers[$0.publicKey] = $0 }
        object.authTokens.forEach { authTokens[$0.deviceKey] = $0.authToken }
        #warning("TODO: Load/add device data, notification tokens and topics")
    }
    
    /// Serialize the management data for storage on disk.
    private var data: Data {
        let object = RV_ManagementData.with { item in
            item.adminToken = adminToken
            item.internalUsers = Array(internalUsers.values)
            item.allowedUsers = usersAllowedToRegister
            item.authTokens = authTokens.map { (key, token) in
                RV_ManagementData.AuthToken.with {
                    $0.deviceKey = key
                    $0.authToken = token
                }
            }
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
        self.adminToken = Data(repeating: 0, count: Server.authTokenLength)
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
    func authenticateDevice(user: Data, device: Data, token: Data) throws -> RV_InternalUser {
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
    func authenticate(device: Data, token: Data) throws {
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
    
    func userExists(_ user: Data) -> Bool {
        internalUsers[user] != nil
    }
    
    func user(with publicKey: Data) -> RV_InternalUser? {
        internalUsers[publicKey]
    }
    
    func userDevices(_ user: Data, app: Data) -> [RV_InternalUser.Device]? {
        internalUsers[user]?.devices.filter { $0.application == app }
    }
    
    func add(topic: RV_Topic) {
        topics[topic.topicID] = .with {
            $0.info = topic
            $0.chain = .with { chain in
                chain.nextChainIndex = 0
                chain.output = topic.topicID
            }
        }
    }
    
    func update(chain: RV_TopicState.ChainState, for topic: Data) {
        topics[topic]?.chain = chain
    }
    
    func topic(id: Data) -> RV_TopicState? {
        return topics[id]
    }
    
    func add(topicMessage: RV_DeviceDownload.Message, for device: Data, of user: Data) {
        deviceData[device]!.messages.append(topicMessage)
        push(topicMessage: topicMessage, to: device, of: user)
    }

    func add(topicUpdate: RV_Topic, for device: Data, of user: Data) {
        deviceData[device]!.topicUpdates.append(topicUpdate)
        push(topicUpdate: topicUpdate, to: device, of: user)
    }
    
    func add(topicKeyMessages messages: [RV_TopicKeyMessage], for device: Data) {
        deviceData[device]!.topicKeyMessages.append(contentsOf: messages)
    }
    
    func set(remainingTopicKeys count: UInt32, for device: Data) {
        deviceData[device]!.remainingTopicKeys = count
    }
    
    func set(remainingPreKeys count: UInt32, for device: Data) {
        deviceData[device]!.remainingPreKeys = count
    }
    
    func set(authToken: Data, for device: Data) {
        authTokens[device] = authToken
    }
    
    func set(userInfo: RV_InternalUser) {
        internalUsers[userInfo.publicKey] = userInfo
    }
    
    func decrementRemainingTopicKeys(for device: Data) {
        deviceData[device]!.remainingTopicKeys -= 1
    }
    
    func deviceExists(_ device: Data) -> Bool {
        authTokens[device] != nil
    }
    
    // MARK: Push
    
    func notificationServer(for user: Data) -> URL {
        let server = internalUsers[user]!.notificationServer
        guard server != "" else {
            return defaultNotificationServer
        }
        // Urls are validated when user data is changed
        return URL(string: server)!
    }
    
    func add(notificationToken: Data, for device: Data) {
        notificationTokens[device] = notificationToken
    }
    
    func notificationToken(for device: Data) -> Data? {
        notificationTokens[device]
    }
    
    func getAndClearDeviceData(_ device: Data) -> RV_DeviceDownload {
        let data = deviceData[device]!
        deviceData[device] = .with {
            $0.remainingPreKeys = data.remainingPreKeys
            $0.remainingTopicKeys = data.remainingTopicKeys
        }
        oldDeviceData[device] = data
        return data
    }
    
    func oldDeviceData(_ device: Data) -> RV_DeviceDownload {
        oldDeviceData[device]!
    }
    
    func createDeviceData(for device: Data) {
        deviceData[device] = .init()
        oldDeviceData[device] = .init()
    }
    
    func createDeviceData(for device: Data, remainingPreKeys: UInt32, remainingTopicKeys: UInt32) {
        deviceData[device] = .with {
            $0.remainingPreKeys = remainingPreKeys
            $0.remainingTopicKeys = remainingTopicKeys
        }
        oldDeviceData[device] = .init()
    }
    
    func delete(device: Data) {
        authTokens[device] = nil
        deviceData[device] = nil
    }
    
    func delete(user: Data) {
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
        return randomBytes(count: Server.authTokenLength)
    }

}
