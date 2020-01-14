//
//  Users.swift
//  App
//
//  Created by Christoph on 14.01.20.
//

import Foundation
import Vapor

extension Server {
    
    /**
     Handle a request to create a new user.
     
     - Parameter request: The received request.
     - Throws: `RendezvousError` and `ServerError` errors
     
     - Note: Possible errors:
        - `RendezvousError.invalidRequest`, if the pin, username or public key are missing.
        - `RendezvousError.authenticationFailed`, if the pin or username is invalid.
        - `ServerError.deletionFailed`, if an existing folder could not be deleted
        - `ServerError.folderCreationFailed`, if the user folder couldn't be created.
     - Note: The request must contain the pin given to the user in the HTTP headers
     - Note: The request must contain a protobuf object of type `RV_InternalUser` (with no devices) in the HTTP body.
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
        set(userInfo: user)
        
        // Remove the user from the pending users.
        remove(allowedUser: user.name)
        
        didChangeData()
        log(debug: "Registered user '\(user.name)'")
    }
       
    /**
     Register a user with a device, prekeys, and topic keys.
     
     - Parameter request: The received POST request.
     - Returns: The authentication token for the device.
     - Throws: `RendezvousError`, `ServerError`, `BinaryEncodingError`
     
     - Note: The request must contain a `RV_RegistrationBundle` in the HTTP body.
     
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
        let userKey = try userKeyData.toPublicKey()
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
        set(userInfo: bundle.info)
        
        // Remove the user from the pending users.
        remove(allowedUser: bundle.info.name)
        
        // Create an authentication token
        let authToken = makeAuthToken()
        set(authToken: authToken, for: deviceKey)
        
        // Initialize the device data with the key counts
        createDeviceData(for: deviceKey, remainingPreKeys: preKeyCount, remainingTopicKeys: topicKeyCount)
        
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
        guard let user = user(with: userInfo.publicKey) else {
            throw RendezvousError.authenticationFailed
        }
        
        // Check that the request is fresh and valid.
        try userInfo.isFreshAndSigned()
        
        // Delete the user data
        try storage.deleteData(forUser: userInfo.publicKey)
        
        // Delete the user
        delete(user: userInfo.publicKey)
        
        // Delete all of the users devices
        for device in user.devices {
            delete(device: device.deviceKey)
        }
        didChangeData()
    }
    
}
