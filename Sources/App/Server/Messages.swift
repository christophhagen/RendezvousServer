//
//  Messages.swift
//  App
//
//  Created by Christoph on 15.01.20.
//

import Foundation
import Vapor
import Crypto

extension Server {
    
    /**
     Add a message to a topic.
     
     - Parameter request: The received POST request.
     - Returns: The `RV_TopicState.ChainState` after the message.
     
     - Throws: `RendezvousError`, `BinaryEncodingError`, `ServerError`, `CryptoError`
     
     - Note: The request must contain a valid `RV_TopicMessageUpload` in the HTTP body.
     - Note: Possible errors:
        - `RendezvousError.invalidRequest`, if:
            - Te request in not a valid protobuf
            - The message id or metadata have invalid length
            - The index of the member is invalid
            - The hash of the file doesn't match the message
            - The signature key is invalid
        - `RendezvousError.authenticationFailed`, if the device doesn’t exist, the token is invalid, or the user has no write permissions.
        - `RendezvousError.resourceNotAvailable`, if the topic doesn't exist.
        - `RendezvousError.resourceAlreadyExists`, if the message already exists
        - `RendezvousError.invalidSignature`, if the signature is invalid
        - `BinaryEncodingError`, if protobuf encoding fails.
        - `BinaryDecodingError` if protobuf decoding fails.
        - `ServerError.fileWriteFailed`, if the message data could not be written.
        - `ServerError.fileReadFailed`, if the file could not be read.
        - `CryptoError`, if the hash for the next output could not be calculated
     */
    func addMessage(_ request: Request) throws -> Data {
        let data = try request.body()
        let upload = try RV_TopicUpdateUpload(validRequest: data)
        
        // Check the length of relevant fields
        guard upload.update.metadata.count < Constants.maximumMetadataLength else {
            log(debug: "Metadata too long \(upload.update.metadata)")
            throw RendezvousError.invalidRequest
        }
        
        // Check the files in the bundle
        try upload.update.files.forEach { file in
            guard file.id.count == Constants.messageIdLength,
                file.tag.count == Constants.tagLength,
                file.hash.count == Constants.hashLength else {
                    log(debug: "Invalid id/tag/hash length")
                    throw RendezvousError.invalidRequest
            }
            #warning("Check that missing file data was already uploaded")
        }
        try upload.files.forEach { file in
            // Check that a file exists for each message
            // Calculate the hash of the file and compare it to the message value
            guard file.id.count == Constants.messageIdLength,
                file.data.count > 0,
                let f = upload.update.files.first(where: { $0.id == file.id }),
                try SHA256.hash(file.data) == f.hash else {
                    log(debug: "Invalid file \(file.id.logId)")
                    throw RendezvousError.invalidRequest
            }
        }
        
        try authenticateDevice(upload.deviceKey, token: upload.authToken)
        
        // Get the existing topic
        guard let topic = self.topic(id: upload.topicID) else {
            throw RendezvousError.resourceNotAvailable
        }
        
        // Get the member who uploaded the message
        let index = Int(upload.update.indexInMemberList)
        guard index < topic.info.members.count else {
            log(debug: "Invalid topic member")
            throw RendezvousError.invalidRequest
        }
        let member = topic.info.members[index]
        
        // Check that the member is authorized to post
        guard member.role == .admin || member.role == .participant else {
            throw RendezvousError.authenticationFailed
        }
        
        // Check that the signature is valid
        guard let signatureKey = try? member.signatureKey.toPublicKey() else {
            log(debug: "Invalid signature key")
            throw RendezvousError.invalidRequest
        }
        try upload.update.verifySignature(with: signatureKey)
        
        // Store each file
        for file in upload.files {
            // Store the file
            try storage.store(file: file.data, with: file.id, in: upload.topicID)
        }
        
        // Store the update
        let output = try storage.store(message: upload.update, in: upload.topicID, with: topic.chain.chainIndex + 1, and: topic.chain.output)
        
        // Store the new chain state
        let message = RV_DeviceDownload.Message.with {
            $0.topicID = upload.topicID
            $0.content = upload.update
            $0.chain = .with { chain in
                chain.chainIndex = topic.chain.chainIndex + 1
                chain.output = output
            }
        }
        let result = try message.chain.serializedData()
        
        update(chain: message.chain, for: upload.topicID)
        
        // Add the message to each device in the topic
        for member in topic.info.members {
            guard let devices = self.userDevices(member.info.userKey, app: topic.info.application) else {
                continue
            }
            for device in devices {
                guard device.deviceKey != upload.deviceKey else {
                    continue
                }
                add(topicMessage: message, for: device.deviceKey, of: member.info.userKey)
            }
        }
        
        didChangeData()
        
        // Return the new chain state
        return result
    }
    
    func getMessages(_ request: Request) throws -> Data {
        let userKey = try request.userPublicKey()
        let deviceKey = try request.devicePublicKey()
        let authToken = try request.authToken()
        
        // Check if authentication is valid and get application
        let app = try authenticateUser(userKey, device: deviceKey, token: authToken)
            .devices.first(where: { $0.deviceKey == deviceKey })!.application
        
        // Get the data for the device
        let data = getAndClearDeviceData(deviceKey)
        
        // Create delivery receipts for each user
        var delivered = [UserKey : [TopicID : UInt32]]()
        for message in data.messages {
            guard let members = self.topic(id: message.topicID)?.info.members.map({ $0.info.userKey }) else {
                // Topic doesn't exist (anymore?)
                continue
            }
            let chainIndex = message.chain.chainIndex
            // Add the message to the dictionary for each user
            for member in members {
                guard let old = delivered[member]?[message.topicID] else {
                    delivered[member] = [message.topicID : chainIndex]
                    continue
                }
                delivered[member, default: [:]][message.topicID] = max(old, chainIndex)
            }
        }
        
        // Send delivery receipts
        for (receiver, receipts) in delivered {
            // Note: This will send a notification also to the device who retrieves the bundle
            send(deliveryReceipts: receipts, to: receiver, from: userKey, in: app)
        }
        
        // Return the device data
        return try data.serializedData()
    }
    
    /**
     Get topic messages in a specified range.
     - Parameter request: The received GET request.
     */
    func getMessagesInRange(_ request: Request) throws -> Data {
        let userKey = try request.userPublicKey()
        let deviceKey = try request.devicePublicKey()
        let authToken = try request.authToken()
        let topicId = try request.topicId()
        let start = try request.start()
        let count = try request.count()
        
        // Check if authentication is valid
        try authenticateUser(userKey, device: deviceKey, token: authToken)
        
        // Check if the topic exists
        guard let topic = self.topic(id: topicId) else {
            throw RendezvousError.resourceNotAvailable
        }
        
        // Limit the requested range to reasonable values
        let messageCount = Int(topic.chain.chainIndex) + 1
        guard start < messageCount, count > 0 else {
            return Data()
        }
        let newCount = min(count, messageCount - start)
        
        let data = try storage.getMessages(from: start, count: newCount, for: topicId)
        return try data.serializedData()
    }
    
    /**
     Get a file in a topic.
     
     - Parameter request: The received GET request.
     - Returns: The file data
     - Throws: `RendezvousError`, `ServerError`
     - Note: Possible errors:
        - `RendezvousError.authenticationFailed`, if the authentication fails, or the user is not a topic member.
        - `ServerError.fileReadFailed`, if the file could not be read.
        - `RendezvousError.resourceNotAvailable`, if the file doesn’t exist
     */
    func getFile(_ request: Request) throws -> Data {
        let userKey = try request.userPublicKey()
        let deviceKey = try request.devicePublicKey()
        let authToken = try request.authToken()
        
        // Check if authentication is valid
        try authenticateUser(userKey, device: deviceKey, token: authToken)
        
        // Get the ids from the path
        let topicId = try request.topicId()
        let file = try request.messageId()
        
        // Check that the user has permissions for the topic
        guard let topic = self.topic(id: topicId),
            topic.info.members.contains(where: { $0.info.userKey == userKey }) else {
                throw RendezvousError.authenticationFailed
        }
        
        // Return the file data
        return try storage.getFile(file, in: topicId)
    }
}
