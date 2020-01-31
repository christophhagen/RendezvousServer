//
//  Topics.swift
//  App
//
//  Created by Christoph on 14.01.20.
//

import Foundation
import Vapor
import CryptoKit25519

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
        - The app id for which the topic is posted.
     
     - Note: The HTTP body must contain the topic update serialized in an `RV_Topic`
     */
    func createTopic(_ request: Request) throws {
        let data = try request.body()
        let userKey = try request.userPublicKey()
        let deviceKey = try request.devicePublicKey()
        let authToken = try request.authToken()
        let topic = try RV_Topic(validRequest: data)
        
        // Check if authentication is valid
        _ = try authenticateUser(userKey, device: deviceKey, token: authToken)
        
        // Check that the topic fulfills basic criteria
        guard topic.indexOfMessageCreator < topic.members.count,
            topic.topicID.count == Server.topicIdLength else {
                throw RendezvousError.invalidRequest
        }
        let admin = topic.members[Int(topic.indexOfMessageCreator)]
        guard topic.creationTime == topic.timestamp,
            admin.hasInfo, admin.role == .admin,
            admin.info.userKey == userKey else {
            throw RendezvousError.invalidRequest
        }
        
        // Check that the topic doesn't exist yet, and that the topic request is valid
        guard !storage.exists(topic: topic.topicID) else {
            throw RendezvousError.resourceAlreadyExists
        }
        try topic.isFreshAndSigned()
        
        // Check that all topic keys in the distribution messages have valid signatures,
        // and that all receivers are known.
        let members: [Data] = try topic.members.map { member in
            guard member.hasInfo else {
                throw RendezvousError.invalidRequest
            }
            if case .UNRECOGNIZED(_) = member.role {
                throw RendezvousError.invalidRequest
            }
            let key = member.info.userKey
            guard userExists(key),
                let receiverKey = try? key.toPublicKey(),
                receiverKey.isValidSignature(member.info.signature, for: member.signatureKey + member.info.encryptionKey) else {
                    throw RendezvousError.invalidSignature
            }
            return key
        }
        
        // Create the topic folder
        try storage.create(topic: topic.topicID)
        
        // Add the topic globally
        add(topic: topic)
        
        // Add the topic message to each device download bundle (except the sending device)
        members.forEach { member in
            for device in userDevices(member, app: topic.application)! {
                guard device.deviceKey != deviceKey else { continue }
                add(topicUpdate: topic, for: device.deviceKey, of: member)
            }
        }
    }
}
