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
        let upload = try RV_TopicMessageUpload(validRequest: data)
        
        // Check the length of relevant fields
        guard upload.message.metadata.count < Server.maximumMetadataLength,
            upload.message.id.count == Server.messageIdLength else {
                throw RendezvousError.invalidRequest
        }
        
        try authenticateDevice(upload.deviceKey, token: upload.authToken)
        
        // Get the existing topic
        guard let topic = self.topic(id: upload.topicID) else {
            throw RendezvousError.resourceNotAvailable
        }
        
        // Get the member who uploaded the message
        let index = Int(upload.message.indexInMemberList)
        guard index < topic.info.members.count else {
            throw RendezvousError.invalidRequest
        }
        let member = topic.info.members[index]
        // Check that the member is authorized to post
        guard member.role == .admin || member.role == .participant else {
            throw RendezvousError.authenticationFailed
        }
        // Check that the signature is valid
        guard let signatureKey = try? member.signatureKey.toPublicKey() else {
            throw RendezvousError.invalidRequest
        }
        try upload.message.verifySignature(with: signatureKey)
        
        // Calculate the hash of the file and compare it to the message value
        guard try SHA256.hash(upload.file) == upload.message.hash else {
            throw RendezvousError.invalidRequest
        }
        
        // Store the file and the message
        try storage.store(file: upload.file, with: upload.message.id, in: upload.topicID)
        
        // Store the message
        let output = try storage.store(message: upload.message, in: upload.topicID, with: topic.chain.nextChainIndex, and: topic.chain.output)
        
        // Store the new chain state
        let message = RV_DeviceDownload.Message.with {
            $0.topicID = upload.topicID
            $0.content = upload.message
            $0.chain = .with { chain in
                chain.nextChainIndex = topic.chain.nextChainIndex + 1
                chain.output = output
            }
        }
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
        
        // Return the new chain state
        return try message.chain.serializedData()
    }
    
    func getMessages(_ request: Request) throws -> Data {
        // Check if authentication is valid
        let deviceKey = try authenticateDevice(request)
        
        let data = getAndClearDeviceData(deviceKey)
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
        // Check if authentication is valid
        let user = try authenticateUser(request)
        
        // Get the ids from the path
        let topicId = try request.topicId()
        let file = try request.fileId()
        
        // Check that the user has permissions for the topic
        guard let topic = self.topic(id: topicId),
            topic.info.members.contains(where: { $0.info.userKey == user }) else {
                throw RendezvousError.authenticationFailed
        }
        
        // Return the file data
        return try storage.get(file: file, in: topicId)
    }
}
