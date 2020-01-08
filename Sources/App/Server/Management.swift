//
//  Management.swift
//  App
//
//  Created by Christoph on 05.01.20.
//

import Foundation
import Vapor

/**
 The `Management` class handles all request related to user and device management, as well as adminstrative tasks.
 */
final class Management {
    
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
    static let publicKeyLength = 64
    
    // MARK: Private variables
    
    /// The administrator authentication token (16 byte).
    private var adminToken: Data
    
    /// The users currently registered with the server.
    private var internalUsers = [PublicKey : RV_InternalUser]()
    
    /// The users which are allowed to register on the server, with their pins, the remaining tries, and the time until which they can register.
    private var usersAllowedToRegister: [String : RV_AllowedUser]
    
    /// The delegate which handles file operations
    var delegate: ManagementDelegate! = nil
    
    // MARK: Saving and loading
    
    /**
     Create an empty management instance.
     - Note: The admin authentication token will be set to all zeros.
     */
    init() {
        self.adminToken = Data(repeating: 0, count: Management.authTokenLength)
        self.usersAllowedToRegister = [:]
        self.internalUsers = [:]
    }
    
    /**
     Create a management instance.
     - Parameter data: The data stored on disk.
     - Parameter delegate: The delegate which handles file operations.
     */
    convenience init(storedData data: Data) throws {
        do {
            let object = try RV_ManagementData(serializedData: data)
            self.init(object: object)
        } catch {
            throw ServerError.invalidManagementData
        }
    }
    
    /**
     Create a management instance from a protobuf object.
     - Parameter object: The protobuf object containing the data
     - Parameter delegate: The delegate which handles file operations.
     */
    private init(object: RV_ManagementData) {
        self.adminToken = object.adminToken
        self.usersAllowedToRegister = object.allowedUsers
        self.internalUsers = [:]
        object.internalUsers.forEach { internalUsers[$0.publicKey] = $0 }
    }
    
    /// Serialize the management data for storage on disk.
    private var data: Data {
        let object = RV_ManagementData.with {
            $0.adminToken = adminToken
            $0.internalUsers = Array(internalUsers.values)
            $0.allowedUsers = usersAllowedToRegister
        }
        
        // Protobuf serialization should never fail, since it is correctly setup.
        return try! object.serializedData()
    }
    
    private func didChangeData() {
        delegate.management(shouldPersistData: data)
    }
    
    // MARK: Admin management
    
    /**
     Check that the admin credentials are valid.
     - Parameter request: The received request.
     - Throws: `RendezvousError` errors
     - Note: Possible errors:
     - `parameterMissingInRequest`, if the request doesn't contain an authentication token.
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
     - Parameter request: The received request.
     - Returns: The new admin token.
     */
    func updateAdminAuthToken(_ request: Request) throws -> Data {
        try checkAdminAccess(request)
        adminToken = makeAuthToken()
        didChangeData()
        return adminToken
    }
    
    // MARK: User management requests
    
    /**
     Allow a user to register on the server.
     - Parameter request: The received request.
     - Returns: The serialized data of the user (`RV_InternalUser`)
     - Throws: `RendezvousError` errors
     - Note: Possible errors:
     - `parameterMissingInRequest`, if the request doesn't contain an authentication token.
     - `authenticationFailed`, if the admin token is invalid.
     - `userAlreadyExists`, if the user is already registered.
     */
    func allowUser(_ request: Request) throws -> Data {
        try checkAdminAccess(request)
        
        // Extract the user and check that it doesn't exist yet
        let name = try request.user()
        guard !internalUsers.values.contains(where: { $0.name == name }) else {
            throw RendezvousError.userAlreadyExists
        }
        
        // Create the user with a random pin and the expiry date
        let user = RV_AllowedUser.with {
            $0.name = name
            $0.pin =  UInt32.random(in: 0..<Management.pinMaximum)
            $0.expiry = timeInSeconds() + Management.pinExpiryInterval
            $0.numberOfTries = Management.pinAllowedTries
        }
        
        // Store the user
        usersAllowedToRegister[name] = user
        didChangeData()
        
        // Return the pin, expiry and username in the response
        return try! user.serializedData()
    }
    
    /**
    Handle a request to create a new user.
     - Parameter request: The received request.
     - Returns: The registered user data (`RV_InternalUser`)
     - Throws: `RendezvousError` and `ServerError` errors
     - Note: Possible errors:
     - `RendezvousError.parameterMissingInRequest`, if the pin, username or public key are missing.
     - `RendezvousError.authenticationFailed`, if the pin or username is invalid.
     - `ServerError.deletionFailed`, if an existing folder could not be deleted
     - `ServerError.folderCreationFailed`, if the user folder couldn't be created.
     */
    func registerUser(_ request: Request) throws -> Data {
        // Extract the user and pin and check that it can register
        let name = try request.user()
        let pin = try request.pin()
        guard canRegister(user: name, pin: pin) else {
            throw RendezvousError.authenticationFailed
        }
        
        let publicKey = try request.key()
        let user = RV_InternalUser.with {
            $0.authToken = makeAuthToken()
            $0.name = name
            $0.publicKey = publicKey
        }
        
        // Create the file structure for the user
        try delegate.management(created: name)
        
        // Add the user
        internalUsers[publicKey] = user
        
        // Remove the user from the pending users.
        usersAllowedToRegister[name] = nil
        didChangeData()
        
        // Return the user data, so the client gets the authentication token.
        return try! user.serializedData()
    }
    
    /**
     Handle a request to delete an existing user.
     - Parameter request: The received request.
     - Throws: `RendezvousError` and `ServerError` errors
     - Note: Possible errors:
     - `RendezvousError.parameterMissingInRequest`, if the username or public key are missing.
     - `RendezvousError.authenticationFailed`, if the username or auth token are invalid.
     - `ServerError.deletionFailed`, if the user folder could not be deleted.
     */
    func deleteUser(_ request: Request) throws {
        // Check authentication
        let authToken = try request.authToken()
        let publicKey = try request.key()
        guard let user = internalUsers[publicKey],
            constantTimeCompare(user.authToken, authToken) else {
                throw RendezvousError.authenticationFailed
        }
        
        // Delete the user data
        try delegate.management(deleted: user.name)

        // Delete the user
        internalUsers[publicKey] = nil
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
        guard user.expiry < timeInSeconds() else {
            usersAllowedToRegister[name] = nil
            didChangeData()
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
            return false
        }
        // Decrease the number of allowed guesses
        usersAllowedToRegister[name]!.numberOfTries -= 1
        return false
    }

    /**
     Create a new random authentication token.
     - Returns: The binary token.
     */
    private func makeAuthToken() -> Data {
        return randomBytes(count: Management.authTokenLength)
    }

}
