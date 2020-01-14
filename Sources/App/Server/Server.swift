//
//  Server.swift
//  App
//
//  Created by Christoph on 05.01.20.
//

import Foundation
import Vapor
import Ed25519

/**
 The `Server` class handles all request related to user and device management, as well as adminstrative tasks.
 */
final class Server: Logger {
    
    // MARK: Constants
    
    /// The time interval after which pins expire (in seconds)
    private static let pinExpiryInterval: UInt32 = 60 * 60 * 32 * 7
    
    /// The number of times a pin can be wrong before blocking the registration
    private static let pinAllowedTries: UInt32 = 3
    
    /// The maximum value for the pin
    static let pinMaximum: UInt32 = 100000
    
    /// The maximum allowed characters for user names
    static let maximumNameLength = 32
    
    /// The number of bytes for an authentication token
    static let authTokenLength = 16
    
    /// The length of public keys in bytes.
    static let publicKeyLength = 32
    
    // MARK: Private variables
    
    /// The interface with the file system
    private let storage: Storage
    
    /// The administrator authentication token (16 byte).
    private var adminToken: Data
    
    /// The users currently registered with the server.
    private var internalUsers = [Data : RV_InternalUser]()
    
    /// The authentication tokens for all internal devices.
    private var authTokens: [Data : Data]
    
    /// The data to send to each internal device.
    private var deviceData: [Data : RV_DeviceDownload]
    
    /// The users which are allowed to register on the server, with their pins, the remaining tries, and the time until which they can register.
    private var usersAllowedToRegister: [String : RV_AllowedUser]
    
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
                serveStaticFiles: config.shouldServeStaticFiles)
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
    private init(storage: Storage, development: Bool, serveStaticFiles: Bool) {
        self.adminToken = Data(repeating: 0, count: Server.authTokenLength)
        self.usersAllowedToRegister = [:]
        self.internalUsers = [:]
        self.authTokens = [:]
        self.deviceData = [:]
        
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
        self.deviceData = [:]
        self.isDevelopmentServer = development
        self.shouldServeStaticFiles = serveStaticFiles
        self.storage = storage
        
        object.internalUsers.forEach { internalUsers[$0.publicKey] = $0 }
        object.authTokens.forEach { authTokens[$0.deviceKey] = $0.authToken }
        #warning("TODO: Load/add device data")
        
        
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
    
    private func didChangeData() {
        do {
            try storage.store(managementData: data)
        } catch {
            log(error: "Failed to store management data: \(error)")
        }
    }
    
    // MARK: Admin management
    
    /**
     Check that the admin credentials are valid.
     
     - The request must contain the current admin token in the request header.
     
     - Parameter request: The received request.
     - Throws: `RendezvousError` errors
     - Note: Possible errors:
     - `invalidRequest`, if the request doesn't contain an authentication token.
     - `authenticationFailed`, if the admin token is invalid.
     */
    private func checkAdminAccess(_ request: Request) throws {
        // Check authentication
        let authToken = try request.authToken()
        guard constantTimeCompare(authToken, adminToken) else {
            throw RendezvousError.authenticationFailed
        }
    }
    
    /**
     Update the authentication token of the admin.
     
     The request must contain in the HTTP headers:
     - The authentication token of the admin.
     
     - Parameter request: The received request.
     - Returns: The new admin token.
     */
    func updateAdminAuthToken(_ request: Request) throws -> Data {
        try checkAdminAccess(request)
        adminToken = makeAuthToken()
        log(info: "Admin authentication token changed")
        didChangeData()
        return adminToken
    }
    
    /**
     Delete all server data.
     */
    func deleteAllServerData(_ request: Request) throws {
        try checkAdminAccess(request)
        try reset()
    }
    
    func reset() throws {
        log(warning: "Deleting all server data")
        try storage.deleteAllData()
        self.adminToken = Data(repeating: 0, count: Server.authTokenLength)
        self.usersAllowedToRegister = [:]
        self.internalUsers = [:]
        self.authTokens = [:]
        self.deviceData = [:]
    }
    
    /**
     Allow a user to register on the server.
     
     - Note: The request must contain in the HTTP headers:
        - The authentication token of the admin.
        - The name of the user to register.
     
     - Parameter request: The received request.
     - Returns: The serialized data of the user (`RV_AllowedUser`)
     - Throws: `RendezvousError` errors, `ServerError` errors
     
     - Note: Possible errors:
        - `RendezvousError.invalidRequest`, if the request doesn't contain an authentication token.
        - `RendezvousError.authenticationFailed`, if the admin token is invalid.
        - `RendezvousError.userOrDeviceAlreadyExists`, if the user is already registered.
        - `BinaryEncodingError`, if the response protobuf couldn't be serialized
     */
    func allowUser(_ request: Request) throws -> Data {
        try checkAdminAccess(request)
        
        // Extract the user and check that it doesn't exist yet
        let name = try request.user()
        guard !internalUsers.values.contains(where: { $0.name == name }) else {
            throw RendezvousError.resourceAlreadyExists
        }
        
        // Create the user with a random pin and the expiry date
        let user = RV_AllowedUser.with {
            $0.name = name
            $0.pin =  UInt32.random(in: 0..<Server.pinMaximum)
            $0.expiry = timeInSeconds() + Server.pinExpiryInterval
            $0.numberOfTries = Server.pinAllowedTries
        }
        
        // Store the user
        usersAllowedToRegister[name] = user
        didChangeData()
        log(debug: "Allowed user '\(user.name)' to register.")
        
        // Return the pin, expiry and username in the response
        return try user.serializedData()
    }
    
    // MARK: Users
    
    /**
     Check the authentication of a device from a user.
     
     - Parameter user: The received user public key
     - Parameter device: The received device public key
     - Parameter token: The received authentication token
     - Returns: The information about the user.
     - Throws: `RendezvousError.authenticationFailed`, if the user or device doesn't exist, or the token is invalid
     */
    private func authenticateDevice(user: Data, device: Data, token: Data) throws -> RV_InternalUser {
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
    Handle a request to create a new user.
     
     - Parameter request: The received request.
     - Throws: `RendezvousError` and `ServerError` errors
     
     - Note: Possible errors:
        - `RendezvousError.invalidRequest`, if the pin, username or public key are missing.
        - `RendezvousError.authenticationFailed`, if the pin or username is invalid.
        - `ServerError.deletionFailed`, if an existing folder could not be deleted
        - `ServerError.folderCreationFailed`, if the user folder couldn't be created.
     - Note: The request must contain in the HTTP headers:
        - The pin given to the user.
     - Note: The request must contain in the HTTP body:
        - A protobuf object of type `RV_InternalUser`, with no devices..
     */
    func registerUser(_ request: Request) throws {
        // Get the data from the request.
        let data = try request.body()
        let user = try RV_InternalUser(validRequest: data)
        
        // Extract the user pin and check that it can register
        let pin = try request.pin()
        guard canRegister(user: user.name, pin: pin) else {
            throw RendezvousError.authenticationFailed
        }
        
        // Check that no device is present
        guard user.devices.count == 0 else {
            throw RendezvousError.invalidRequest
        }
        
        // Check that the request is fresh.
        try user.isFreshAndSigned()
        
        
        // Create the file structure for the user
        try storage.create(user: user.publicKey)
        
        // Add the user
        internalUsers[user.publicKey] = user
        
        // Remove the user from the pending users.
        usersAllowedToRegister[user.name] = nil
        didChangeData()
        log(debug: "Registered user '\(user.name)'")
    }
    
    /**
     Register a user with a device, prekeys, and topic keys.
     
     - Parameter request: The received POST request.
     - Returns: The authentication token for the device.
     - Throws: `RendezvousError`, `ServerError`, `BinaryEncodingError`
     
     - Note: The request must contain a `RV_RegistrationBundle` in the HTTP body.
     - Note: The request must contain
     
     - Note: Possible errors:
        - `RendezvousError.invalidRequest`, if the data is corrupt, or the device count is not 1
        - `RendezvousError.authenticationFailed`, if the user or pin is invalid
        - `RendezvousError.invalidSignature`, if the user info, a prekey or a topic key have an invalid signature.
        - `RendezvousError.requestOutdated`, if the timestamp of the user info is not fresh.
        - `RendezvousError.invalidKeyUpload`, if a prekey public key doesn't match the device
        - `BinaryEncodingError`, if the protobuf operations produce an error.
        - `ServerError.deletionFailed`, if an existing user folder could not be deleted
        - `ServerError.folderCreationFailed`, if the user folder couldn't be created.
        - `ServerError.fileWriteFailed`, if the prekey or topic key data could not be written.
     */
    func registerUserWithDeviceAndKeys(_ request: Request) throws -> Data {
        // Get the data from the request.
        let data = try request.body()
        let bundle = try RV_RegistrationBundle(validRequest: data)
        
        // Extract the user pin and check that it can register
        guard canRegister(user: bundle.info.name, pin: bundle.pin) else {
            throw RendezvousError.authenticationFailed
        }
        let userKeyData = bundle.info.publicKey
        
        // Check that one device is present
        guard bundle.info.devices.count == 1 else {
            throw RendezvousError.invalidRequest
        }
        let deviceKey = bundle.info.devices[0].deviceKey
        
        // Check that the user info is fresh.
        try bundle.info.isFreshAndSigned()
        
        // Check the signature for each prekey
        try bundle.preKeys.forEach {
            try $0.verifySignature()
            guard $0.publicKey == deviceKey else {
                throw RendezvousError.invalidKeyUpload
            }
        }
        
        // Check that all topic keys have valid signatures
        let userKey = try Ed25519.PublicKey(rawRepresentation: userKeyData)
        for key in bundle.topicKeys {
            guard userKey.isValidSignature(key.signature, for: key.publicKey) else {
                throw RendezvousError.invalidSignature
            }
        }
        
        // Create the file structure for the user
        try storage.create(user: bundle.info.publicKey)
        
        // Add the prekeys to the device
        let preKeyCount = try storage.store(
            preKeys: bundle.preKeys,
            for: deviceKey,
            of: userKeyData)
        
        // Store the topic keys
        let topicKeyCount = try storage.store(topicKeys: bundle.topicKeys, for: userKeyData)
        
        // Add the user
        internalUsers[userKeyData] = bundle.info
        
        // Remove the user from the pending users.
        usersAllowedToRegister[bundle.info.name] = nil
        
        // Create an authentication token
        let authToken = makeAuthToken()
        authTokens[deviceKey] = authToken
 
        // Initialize the device data with the key counts
        deviceData[deviceKey] = .with {
            $0.remainingPreKeys = preKeyCount
            $0.remainingTopicKeys = topicKeyCount
        }

        didChangeData()
        log(debug: "Registered user '\(bundle.info.name)' with device and keys")
        
        // Return the authentication token
        return authToken
    }
    
    /**
     Get the current info about an internal user.
     
     - Parameter request: The received GET request.
     - Returns: A serialized `RV_InternalUser` object.
     - Throws: `RendezvousError` errors, `ServerError` errors
     
     - Note: Possible errors:
        - `RendezvousError.invalidRequest`, if any header is missing or invalid.
        - `RendezvousError.authenticationFailed`, if the user or device doesn't exist, or the token is invalid.
        - `BinaryEncodingError`, if the user info serialization fails.
     
     - Note: The request must contain in the HTTP headers:
        - The public key of the user.
        - The public key of the device.
        - The authentication token of the device.
     */
    func userInfo(_ request: Request) throws -> Data {
        // Get the request data
        let userKey = try request.userPublicKey()
        let deviceKey = try request.devicePublicKey()
        let authToken = try request.authToken()
        
        // Check if authentication is valid
        let user = try authenticateDevice(user: userKey, device: deviceKey, token: authToken)
        
        // Send the current user info
        return try user.serializedData()
    }
    
    /**
     Handle a request to delete an existing user.
     
     The request must contain in the HTTP body:
     - A protobuf object of type `RV_InternalUser`
     
     - Parameter request: The received request.
     - Throws: `RendezvousError` and `ServerError` errors
     - Note: Possible errors:
     - `RendezvousError.invalidRequest`, if the request data is malformed or missing.
     - `RendezvousError.authenticationFailed`, if the user doesn't exist.
     - `RendezvousError.invalidSignature`, if the signature doesn't match the data.
     - `RendezvousError.requestOutdated`, if the timestamp of the request is not fresh.
     - `ServerError.deletionFailed`, if the user folder could not be deleted.
     - `BinaryEncodingError`, if the internal protobuf handling for signature verification fails.
     */
    func deleteUser(_ request: Request) throws {
        // Get the deletion request
        let data = try request.body()
        let userInfo = try RV_InternalUser(validRequest: data)
        
        // Check that the user exists.
        guard let user = internalUsers[userInfo.publicKey] else {
            throw RendezvousError.authenticationFailed
        }
        
        // Check that the request is fresh and valid.
        try userInfo.isFreshAndSigned()
        
        // Delete the user data
        try storage.deleteData(forUser: userInfo.publicKey)

        // Delete the user
        internalUsers[userInfo.publicKey] = nil
        
        // Delete all of the users devices
        for device in user.devices {
            authTokens[device.deviceKey] = nil
            deviceData[device.deviceKey] = nil
        }
        didChangeData()
    }
    
    // MARK: Internal state
    
    /**
     Check if a user is allowed to register.
     - Parameter name: The username
     - Parameter pin: The random pin of the user, handed out by the administrator.
     - Returns: `true`, if the user is allowed to register.
     - Note: Removes users which enter the pin wrong too often, or when the pin is expired.
     */
    private func canRegister(user name: String, pin: UInt32) -> Bool {
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
    
    // MARK: Devices
    
    /**
     Register a new device for a user.
     
     - Parameter request: The received POST request.
     - Returns: The authentication token for the device.
     - Throws: `RendezvousError`, `BinaryEncodingError`
     
     - Note: The request must contain in the HTTP body:
        - A protobuf object of type `RV_InternalUser`, with only the new device added.
     
     - Note: Possible errors:
        - `RendezvousError.invalidRequest`, if the body data is missing or not a valid protobuf object
        - `RendezvousError.authenticationFailed`, if the user public key doesn't exist.
        - `RendezvousError.userOrDeviceAlreadyExists`, if a device with the same public key already exists.
        - `RendezvousError.invalidSignature`, if the signature doesn’t match the public key.
        - `RendezvousError.requestOutdated`, if the timestamp of the request is not fresh.
        - `BinaryEncodingError`, if the protobuf operations produce an error.
     */
    func registerDevice(_ request: Request) throws -> Data {
        // Get the data from the request.
        let data = try request.body()
        let userInfo = try RV_InternalUser(validRequest: data)
        
        // Check that the user exists
        guard let oldInfo = internalUsers[userInfo.publicKey] else {
            throw RendezvousError.authenticationFailed
        }
        
        // Check that at least one device is present
        guard userInfo.devices.count == oldInfo.devices.count + 1 else {
            throw RendezvousError.invalidRequest
        }
        
        // Check that the request is fresh.
        try userInfo.isFreshAndSigned()
        
        // Check that the info is newer
        guard userInfo.timestamp >= oldInfo.timestamp else {
            throw RendezvousError.requestOutdated
        }
        
        // Check that no other data was modified
        var oldDevices = userInfo.devices
        let newDevice = oldDevices.popLast()!
        guard userInfo.creationTime == oldInfo.creationTime,
            userInfo.name == oldInfo.name,
            oldDevices == oldInfo.devices else {
                throw RendezvousError.invalidRequest
        }

        // Check that the device doesn't exist yet.
        guard authTokens[newDevice.deviceKey] == nil else {
            throw RendezvousError.resourceAlreadyExists
        }
        
        // Create an authentication token
        let authToken = makeAuthToken()
        authTokens[newDevice.deviceKey] = authToken
        
        // Write the new info
        internalUsers[userInfo.publicKey] = userInfo
        
        // Initialize the device data
        deviceData[newDevice.deviceKey] = .init()
        
        log(info: "User '\(userInfo.name)': New device registered")
        #warning("Invalidate topic keys")
        // Return the authentication token
        return authToken
    }
    
    /**
     Remove a device from a user.
     
     - Parameter request: The received POST request.
     - Throws: `RendezvousError` and `BinaryEncodingError` errors
     
     - Note: The request must contain in the HTTP body:
        - A protobuf object of type `RV_InternalUser`, with only the device removed.
     
     - Note: Possible errors:
        - `RendezvousError.invalidRequest`, if the request data is malformed or missing.
        - `RendezvousError.authenticationFailed`, if the user doesn't exist.
        - `RendezvousError.invalidSignature`, if the signature doesn't match the data.
        - `RendezvousError.requestOutdated`, if the timestamp of the request is not fresh.
        - `BinaryEncodingError`, if the internal protobuf handling for signature verification fails.
     */
    func deleteDevice(_ request: Request) throws {
        // Get the data from the request.
        let data = try request.body()
        let userInfo = try RV_InternalUser(validRequest: data)
        
        // Check that the user exists
        guard let oldInfo = internalUsers[userInfo.publicKey] else {
            throw RendezvousError.authenticationFailed
        }
        
        // Check that one device was removed.
        guard userInfo.devices.count == oldInfo.devices.count - 1 else {
            throw RendezvousError.invalidRequest
        }
        
        // Check that the request is fresh.
        try userInfo.isFreshAndSigned()
        
        // Check that the info is newer
        guard userInfo.timestamp > oldInfo.timestamp else {
            throw RendezvousError.requestOutdated
        }
        
        // Check that no other data was modified
        var newDevices = oldInfo.devices
        let index = oldInfo.devices.firstIndex { !userInfo.devices.contains($0) }!
        let oldDevice = newDevices.remove(at: index)
        guard userInfo.creationTime == oldInfo.creationTime,
            userInfo.name == oldInfo.name,
            newDevices == userInfo.devices else {
                throw RendezvousError.invalidRequest
        }

        // Remove the authentication token and device data
        authTokens[oldDevice.deviceKey] = nil
        deviceData[oldDevice.deviceKey] = nil
        
        // Write the new info
        internalUsers[userInfo.publicKey] = userInfo
        
        log(info: "User '\(userInfo.name)': Device deleted")
        #warning("TODO: Remove device data, topic messages and prekeys from storage")
    }
    
    // MARK: Device PreKeys
    
    /**
     Add new prekeys for a device.
     
     
     - Parameter request: The received request.
     - Throws: `RendezvousError`, `ServerError`, `BinaryEncodingError`
     
     - Note: The request must contain a `RV_DevicePrekeyUploadRequest` in the HTTP body.
     
     - Note: Possible errors:
        - `RendezvousError.invalidRequest`, if no body data was provided, or the request data is invalid.
        - `RendezvousError.authenticationFailed`, if the user or device doesn't exist, or the auth token is invalid.
        - `RendezvousError.invalidKeyUpload`, if the signature or public key for a prekey is invalid.
        - `BinaryEncodingError`, if the prekey serialization fails, or if the existing data is not a valid protobuf.
        - `ServerError.fileWriteFailed`, if the prekey data could not be written.
        - `ServerError.fileReadFailed`, if the file could not be read.
     */
    func addDevicePreKeys(_ request: Request) throws {
        // Get the request data
        let data = try request.body()
        let preKeyRequest = try RV_DevicePrekeyUploadRequest(validRequest: data)
        
        // Check if authentication is valid
        _ = try authenticateDevice(user: preKeyRequest.publicKey,
                                   device: preKeyRequest.deviceKey,
                                   token: preKeyRequest.authToken)
        
        // Check the signature for each prekey
        try preKeyRequest.preKeys.forEach {
            try $0.verifySignature()
            guard $0.publicKey == preKeyRequest.deviceKey else {
                throw RendezvousError.invalidKeyUpload
            }
        }
        
        // Add the prekeys to the device
        let count = try storage.store(
            preKeys: preKeyRequest.preKeys,
            for: preKeyRequest.deviceKey,
            of: preKeyRequest.publicKey)
        
        // Update the remaining count
        deviceData[preKeyRequest.deviceKey]!.remainingPreKeys = count
    }
    
    /**
     Get prekeys for all devices of a user, to create new topic keys.
     
     - Parameter request: The received GET request.
     - Returns: The available keys serialized in an `RV_DevicePreKeyBundle`
     - Throws: `RendezvousError`, `ServerError`, `BinaryEncodingError`
     
     - Note: Possible errors:
        - `RendezvousError.invalidRequest`, if any header is missing or invalid.
        - `RendezvousError.authenticationFailed`, if the user or device doesn't exist, or the token is invalid.
        - `ServerError.fileReadFailed`, if the prekey file for a device could not be read.
        - `BinaryEncodingError`, if the prekey data for a device is not a valid protobuf, or if the prekey serialization fails.
        - `ServerError.fileWriteFailed`, if the prekey data for a device could not be written.
        - `ServerError.deletionFailed`, if the prekey data for a device could not be deleted.
     
     - Note: The request must contain in the HTTP headers:
        - The public key of the user.
        - The public key of the device.
        - The authentication token of the device.
        - The number of keys to get for each device.
     */
    func getDevicePreKeys(_ request: Request) throws -> Data {
        let userKey = try request.userPublicKey()
        let deviceKey = try request.devicePublicKey()
        let authToken = try request.authToken()
        let count = try request.count()
        
        // Check if authentication is valid
        let user = try authenticateDevice(user: userKey, device: deviceKey, token: authToken)
        
        #warning("TODO: Exclude prekeys from requesting device")
        // Get the available device keys and return them
        let devices = user.devices.map { $0.deviceKey }
        let keys = try storage.get(preKeys: count, for: devices, of: userKey)
        
        // Update the remaining count
        for device in keys.devices {
            deviceData[device.deviceKey]!.remainingPreKeys = device.remainingKeys
        }
        
        // Return the data to send to the client
        return try keys.serializedData()
    }
    
    // MARK: Topic Keys
    
    /**
     Add topic keys encrypted with unique device prekeys.
     */
    func addTopicKeys(_ request: Request) throws {
        let data = try request.body()
        let bundle = try RV_TopicKeyBundle(validRequest: data)
        
        // Check if authentication is valid
        let user = try authenticateDevice(user: bundle.publicKey,
                                          device: bundle.deviceKey,
                                          token: bundle.authToken)
        
        // Check that all topic keys have valid signatures
        let userKey = try Ed25519.PublicKey(rawRepresentation: user.publicKey)
        for key in bundle.topicKeys {
            guard userKey.isValidSignature(key.signature, for: key.publicKey) else {
                throw RendezvousError.invalidKeyUpload
            }
        }
        // Check that each receiver device is present in the list of messages
        let receivers = Set(user.devices.map { $0.deviceKey }).subtracting([bundle.deviceKey])
        guard Set(bundle.messages.map { $0.deviceKey }) == receivers else {
            throw RendezvousError.invalidKeyUpload
        }
        
        // Check that each receiver will get all topic key messages
        let keys = Set(bundle.topicKeys.map { $0.publicKey })
        for receiver in bundle.messages {
            guard Set(receiver.messages.map { $0.topicKey.publicKey }) == keys else {
                throw RendezvousError.invalidKeyUpload
            }
        }

        // Store the topic keys
        let count = try storage.store(topicKeys: bundle.topicKeys, for: user.publicKey)
        
        // Store the topic messages and update the topic key count
        for list in bundle.messages {
            deviceData[list.deviceKey]!.topicKeyMessages.append(contentsOf: list.messages)
            deviceData[list.deviceKey]!.remainingTopicKeys = count
        }
        
        // Also update count for uploading device
        deviceData[bundle.deviceKey]!.remainingTopicKeys = count
    }
    
    /**
     Download a topic key for topic creation.
     
     - Parameter request: The received GET request.
     - Returns: The key serialized in an `RV_TopicKey`
     - Throws: `RendezvousError`, `ServerError`, `BinaryEncodingError`
     
     - Note: Possible errors:
        - `RendezvousError.invalidRequest`, if any header is missing or invalid.
        - `RendezvousError.authenticationFailed`, if the user or device doesn't exist, or the token is invalid.
        - `RendezvousError.resourceNotAvailable`, if no topic key exists.
        - `ServerError.fileWriteFailed`, if the topic key file could not be written.
        - `ServerError.deletionFailed`, if the topic key file could not be deleted
        - `ServerError.fileReadFailed`, if the topic key file could not be read.
        - `BinaryEncodingError`, if the topic key data is not a valid protobuf, or if the serialization fails.
    
     - Note: The request must contain in the HTTP headers:
        - The public key of the user.
        - The public key of the device.
        - The authentication token of the device.
        - The public key of the user for which a key is requested.
     */
    func getTopicKey(_ request: Request) throws -> Data {
        let userKey = try request.userPublicKey()
        let deviceKey = try request.devicePublicKey()
        let authToken = try request.authToken()
        let receiver = try request.receiverPublicKey()
        
        // Check if authentication is valid
        let user = try authenticateDevice(user: userKey, device: deviceKey, token: authToken)
        #warning("Add rate limit for topic key requests.")
        
        // Get a topic key
        let topicKey = try storage.getTopicKey(of: receiver)
        
        // Decrease the available count
        for device in user.devices {
            deviceData[device.deviceKey]!.remainingTopicKeys -= 1
        }
        // Send the key to the client
        return try topicKey.serializedData()
    }
    
    // MARK: Topics
    
    /**
     Create a new topic..
     
     - Parameter request: The received POST request.
     - Throws: `RendezvousError`, `ServerError`, `BinaryEncodingError`
     
     - Note: Possible errors:
        - `RendezvousError.invalidRequest`, if any header is invalid, or if any timestamps or public keys don't match.
        - `RendezvousError.authenticationFailed`, if the user or device doesn't exist, or the token is invalid.
        - `RendezvousError.invalidSignature`, if any signature is invalid.
        - `RendezvousError.requestOutdated`, if the timestamp of the request is not fresh.
        - `RendezvousError.resourceNotAvailable`, if no topic key exists.
        - `ServerError.fileWriteFailed`, if the topic key file could not be written.
        - `ServerError.deletionFailed`, if the topic key file could not be deleted
        - `ServerError.fileReadFailed`, if the topic key file could not be read.
        - `BinaryEncodingError`, if the topic key data is not a valid protobuf, or if the serialization fails.
    
     - Note: The request must contain in the HTTP headers:
        - The public key of the user.
        - The public key of the device.
        - The authentication token of the device.
     - Note: The HTTP body must contain the topic update serialized in an `RV_Topic`
     
     */
    func createTopic(_ request: Request) throws {
        let data = try request.body()
        let userKey = try request.userPublicKey()
        let deviceKey = try request.devicePublicKey()
        let authToken = try request.authToken()
        let topic = try RV_Topic(validRequest: data)
        
        // Check if authentication is valid
        let user = try authenticateDevice(user: userKey, device: deviceKey, token: authToken)
        
        // Check that the creation time matches the timestamp (for topic creation)
        guard topic.hasCreatorKey,
            topic.creationTime == topic.timestamp,
            topic.creatorKey.publicKey == userKey else {
            throw RendezvousError.invalidRequest
        }
        
        // Check that the topic key signature is valid
        let creatorKey = try! Ed25519.PublicKey(rawRepresentation: user.publicKey)
        guard creatorKey.isValidSignature(topic.creatorKey.signature, for: topic.publicKey) else {
            throw RendezvousError.invalidSignature
        }
        
        // Check that the topic request is valid
        try topic.isFreshAndSigned()
        
        // Check that all topic keys in the distribution messages have valid signatures,
        // and that all receivers are known.
        for message in topic.members + topic.readers {
            let key = message.receiverKey.publicKey
            guard internalUsers[key] != nil,
                let receiverKey = try? Ed25519.PublicKey(rawRepresentation: key),
                receiverKey.isValidSignature(message.receiverKey.signature, for: message.receiverTopicKey) else {
                    throw RendezvousError.invalidSignature
            }
        }
        
        // Create the topic folder
        
        // Add the topic message to each device download bundle (except the sending device)
        for message in topic.members + topic.readers {
            for device in internalUsers[message.receiverKey.publicKey]!.devices {
                guard device.deviceKey != deviceKey else { continue }
                deviceData[device.deviceKey]!.topicUpdates.append(topic)
            }
        }
    }
    
    // MARK: Helper functions
    
    /**
     Create a new random authentication token.
     - Returns: The binary token.
     */
    private func makeAuthToken() -> Data {
        return randomBytes(count: Server.authTokenLength)
    }

}
