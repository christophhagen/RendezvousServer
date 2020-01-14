//
//  Topics.swift
//  App
//
//  Created by Christoph on 14.01.20.
//

import Foundation
import Vapor
import Ed25519

extension Server {
    
    /**
     Create a new topic.
     
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
            guard userExists(key),
                let receiverKey = try? Ed25519.PublicKey(rawRepresentation: key),
                receiverKey.isValidSignature(message.receiverKey.signature, for: message.receiverTopicKey) else {
                    throw RendezvousError.invalidSignature
            }
        }
        
        // Create the topic folder
        
        // Add the topic message to each device download bundle (except the sending device)
        for message in topic.members + topic.readers {
            for device in userDevices(message.receiverKey.publicKey)! {
                guard device.deviceKey != deviceKey else { continue }
                add(topicUpdate: topic, for: device.deviceKey)
            }
        }
    }
}
