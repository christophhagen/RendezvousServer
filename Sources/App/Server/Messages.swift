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
        let request = try RV_TopicMessageUpload(validRequest: data)
        
        // Check the length of relevant fields
        guard request.message.metadata.count < Server.maximumMetadataLength,
            request.message.id.count == Server.messageIdLength else {
                throw RendezvousError.invalidRequest
        }
        
        try authenticate(device: request.deviceKey, token: request.authToken)
        
        // Get the existing topic
        guard let topic = self.topic(id: request.topicID) else {
            throw RendezvousError.resourceNotAvailable
        }
        
        // Get the member who uploaded the message
        let index = Int(request.message.indexInMemberList)
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
        try request.message.verifySignature(with: signatureKey)
        
        // Calculate the hash of the file and compare it to the message value
        guard try SHA256.hash(request.file) == request.message.hash else {
            throw RendezvousError.invalidRequest
        }
        
        // Store the file and the message
        try storage.store(file: request.file, with: request.message.id, in: request.topicID)
        
        // Store the message
        let output = try storage.store(message: request.message, in: request.topicID, with: topic.chain.nextChainIndex, and: topic.chain.output)
        
        // Store the new chain state
        let message = RV_DeviceDownload.Message.with {
            $0.topicID = request.topicID
            $0.content = request.message
            $0.chain = .with { chain in
                chain.nextChainIndex = topic.chain.nextChainIndex + 1
                chain.output = output
            }
        }
        update(chain: message.chain, for: request.topicID)
        
        // Add the message to each device in the topic
        for member in topic.info.members {
            guard let devices = self.userDevices(member.info.userKey) else {
                continue
            }
            for device in devices {
                guard device.deviceKey != request.deviceKey else {
                    continue
                }
                add(topicMessage: message, for: device.deviceKey)
            }
        }
        
        // Return the new chain state
        return try message.chain.serializedData()
    }
    
    func getMessages(_ request: Request) throws -> Data {
        let deviceKey = try request.devicePublicKey()
        let authToken = try request.authToken()
        
        // Check if authentication is valid
        _ = try authenticate(device: deviceKey, token: authToken)
        
        let data = getAndClearDeviceData(deviceKey)
        return try data.serializedData()
    }
}
