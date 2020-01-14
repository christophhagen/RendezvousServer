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
        let user = try authenticateDevice(user: bundle.publicKey,
                                          device: bundle.deviceKey,
                                          token: bundle.authToken)
        
        // Check that all topic keys have valid signatures
        let userKey = try user.publicKey.toPublicKey()
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
            decrementRemainingTopicKeys(for: device.deviceKey)
        }
        // Send the key to the client
        return try topicKey.serializedData()
    }
    
}
