//
//  TopicKeys.swift
//  App
//
//  Created by Christoph on 14.01.20.
//

import Foundation
import Vapor

extension Server {
    
    /**
     Add topic keys encrypted with unique device prekeys.
     */
    func addTopicKeys(_ request: Request) throws {
        let data = try request.body()
        let bundle = try RV_TopicKeyBundle(validRequest: data)
        
        // Check if authentication is valid
        let user = try authenticateUser(bundle.publicKey,
                                        device: bundle.deviceKey,
                                        token: bundle.authToken)
        
        // Check that all topic keys have valid signatures
        let userKey = try user.publicKey.toPublicKey()
        for key in bundle.topicKeys {
            guard userKey.isValidSignature(key.signature, for: key.signatureKey + key.encryptionKey) else {
                throw RendezvousError.invalidKeyUpload
            }
        }
        
        // Check that each receiver device is present in the list of messages
        let receivers = Set(user.devices(for: bundle.application))
            .subtracting([bundle.deviceKey])
        guard Set(bundle.messages.map { $0.deviceKey }) == receivers else {
            throw RendezvousError.invalidKeyUpload
        }
        
        // Check that each receiver will get all topic key messages
        let keys = Set(bundle.topicKeys.map { $0.signatureKey })
        for receiver in bundle.messages {
            guard Set(receiver.messages.map { $0.topicKey.signatureKey }) == keys else {
                throw RendezvousError.invalidKeyUpload
            }
        }

        // Store the topic keys
        let count = try storage.store(topicKeys: bundle.topicKeys, for: bundle.application, of: user.publicKey)
        
        // Store the topic messages and update the topic key count
        for list in bundle.messages {
            add(topicKeyMessages: list.messages, for: list.deviceKey)
            set(remainingTopicKeys: count, for: list.deviceKey)
        }
        
        // Also update count for uploading device
        set(remainingTopicKeys: count, for: bundle.deviceKey)
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
        - The app id
     */
    func getTopicKey(_ request: Request) throws -> Data {
        let userKey = try request.userPublicKey()
        let deviceKey = try request.devicePublicKey()
        let authToken = try request.authToken()
        let receiver = try request.receiverPublicKey()
        let appId = try request.appId()
        
        // Check if authentication is valid
        let user = try authenticateUser(userKey, device: deviceKey, token: authToken)
        #warning("Add rate limit for topic key requests.")
        
        // Get a topic key
        let topicKey = try storage.getTopicKey(for: appId, of: receiver)
        
        // Decrease the available count
        for device in user.devices {
            decrementRemainingTopicKeys(for: device.deviceKey)
        }
        // Send the key to the client
        return try topicKey.serializedData()
    }
    
    /**
     Get topic keys for multiple users.
     
     - Parameter request: The received POST request.
     - Returns: The key serialized in an `RV_TopicKeyResponse`
     - Throws: `RendezvousError`, `ServerError`, `BinaryEncodingError`
     
     - Note: The request must contain a valid `RV_TopicKeyRequest` in the HTTP body.
     
     - Note: Possible errors:
         - `RendezvousError.invalidRequest`, if the body is not a valid request.
         - `RendezvousError.authenticationFailed`, if the user or device doesn't exist, or the token is invalid.
         - `BinaryEncodingError`, if the serialization fails.
     */
    func getTopicKeys(_ request: Request) throws -> Data {
        let body = try request.body()
        let request = try RV_TopicKeyRequest(validRequest: body)
        
        // Check if authentication is valid
        try authenticateUser(request.publicKey, device: request.deviceKey, token: request.authToken)
        
        // Chech that all users exist before messing with keys
        try request.users.forEach { userKey in
            if !self.userExists(userKey){
                throw RendezvousError.resourceNotAvailable
            }
        }
        
        let keys = request.users.compactMap { userKey -> RV_TopicKeyResponse.User? in
           // Get a topic key
            guard let topicKey = try? storage.getTopicKey(for: request.application, of: userKey) else {
                return nil
            }
            
            // Decrease the available count
            self.user(with: userKey)!.devices.forEach {
                decrementRemainingTopicKeys(for: $0.deviceKey)
            }
            return .with {
                $0.publicKey = userKey
                $0.topicKey = topicKey
            }
        }
        
        let response = RV_TopicKeyResponse.with {
            $0.users = keys
        }
        return try response.serializedData()
    }
    
}
