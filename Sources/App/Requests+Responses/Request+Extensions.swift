//
//  Request+Extensions.swift
//  App
//
//  Created by Christoph on 05.01.20.
//

import Foundation
import Vapor
import CryptoKit25519

extension Request {
    
    /**
     Get the binary data of the request.
     - Returns: The HTTP body data.
     - Throws: `RendezvousError.invalidRequest`, if no body data was provided.
     */
    func body() throws -> Data {
        guard let data = http.body.data else {
            throw RendezvousError.invalidRequest
        }
        return data
    }
    
    /**
     Get the authentication token from the request.

     This can be the administrator token, the user token, or the device token.
     
     - Returns: The  binary token.
     - Throws: `RendezvousError` errors
     - Note: An authentication token is always `Management.authTokenLength` bytes of binary data, and is sent base64 encoded in requests.
     
     - Note: Possible Errors:
        - `invalidRequest`, if the request doesn't contain a token, if the token is not base64 encoded data, or if the length of the token is invalid.
     */
    func authToken() throws -> AuthToken {
        try binary(header: .authToken, length: Server.authTokenLength)
    }
    
    /**
     Get the user name from the request.
     - Note:User names have a maximum length of `Server.maximumNameLength` characters.
     - Returns: The user name.
     - Throws: `RendezvousError` errors
     - Note: Possible Errors:
     - `invalidRequest`, if the request doesn't contain a user name, or if the name is longer than `Server.maximumNameLength` characters.
     */
    func user() throws -> String {
        try get(header: .username, maxLength: Server.maximumNameLength)
    }
    
    /**
    Get the pin from the request.
     - Returns: The pin.
     - Throws: `RendezvousError` errors
     - Note: Possible Errors:
        - `invalidRequest`, if the request doesn't contain a pin, or if the pin is not a valid number.
     */
    func pin() throws -> UInt32 {
        let value = try get(header: .pin)
        guard let pin = UInt32(value), pin < Server.pinMaximum else {
            throw RendezvousError.invalidRequest
        }
        return pin
    }
    
    /**
     Get the count from the request.
     - Returns: The count.
     - Throws: `RendezvousError` errors
     - Note: Possible Errors:
        - `invalidRequest`, if the request doesn't contain a count, or if the count is not a valid number.
    */
    func count() throws -> Int {
        try int(header: .count)
    }
    
    /**
     Get the range start from the request.
     - Returns: The range start (inclusive).
     - Throws: `RendezvousError` errors
     - Note: Possible Errors:
        - `invalidRequest`, if the request doesn't contain a start value, or if it is not a valid number.
     */
    func start() throws -> Int {
        try int(header: .start)
    }
    
    /**
     Get the public key of the device from the request.
     - Returns: The public key in binary format.
     - Throws: `RendezvousError` errors
     - Note: Possible Errors:
        - `invalidRequest`, if the request doesn't contain a key, or if the key has invalid length.
     */
    func devicePublicKey() throws -> DeviceKey {
        return try key(header: .device)
    }
    
    /**
     Get the public key of the user from the request.
     
     - Returns: The public key in binary format.
     - Throws: `RendezvousError` errors
     
     - Note: Possible Errors:
        - `invalidRequest`, if the request doesn't contain a key, or if the key has invalid length.
    */
    func userPublicKey() throws -> UserKey {
        return try key(header: .user)
    }
    
    /**
     Get the public key of the requested user from the request.
     
     - Returns: The public key in binary format.
     - Throws: `RendezvousError` errors
     
     - Note: Possible Errors:
        - `invalidRequest`, if the request doesn't contain a key, or if the key has invalid length.
     */
    func receiverPublicKey() throws -> UserKey {
        return try key(header: .receiver)
    }
    
    /**
     Get the app id from the request.
     
     - Note:App ids have a maximum length of `Server.appIdLength` characters.
     - Returns: The app id.
     - Throws: `RendezvousError` errors
     - Note: Possible Errors:
        - `invalidRequest`, if the request doesn't contain an app id, or if the id larger than `Server.maximumAppIdLength` characters.
     */
    func appId() throws -> String {
        try get(header: .appId, maxLength: Server.maximumAppIdLength)
    }
    
    /**
     Get the topic id from the request.
     
     - Returns: The topic id.
     - Throws: `RendezvousError` errors
     - Note: Possible Errors:
        - `invalidRequest`, if the request doesn't contain a topic id, or if the id is invalid.
     */
    func topicId() throws -> TopicID {
        try binaryFromPathComponent(length: Server.topicIdLength)
    }
    
    /**
     Get the file id from the request.
     
     - Returns: The file id.
     - Throws: `RendezvousError` errors
     - Note: Possible Errors:
        - `invalidRequest`, if the request doesn't contain a file id, or if the id is invalid.
     */
    func messageId() throws -> MessageID {
        try binaryFromPathComponent(length: Server.messageIdLength)
    }
    
    /**
     Search for a key in the request header, and throw an error if the key is missing.
     - Parameter header: The key of the header.
     - Returns: The value as a string.
     - Throws: `RendezvousError.invalidRequest`, if the value is missing.
     */
    private func get(header: HeaderKey) throws -> String {
        guard let value = http.headers.firstValue(name: .init(header.rawValue)) else {
            Log.log(info: "Missing HTTP header \(header) in request")
            throw RendezvousError.invalidRequest
        }
        return value
    }
    
    /**
     Get a string value from the request headers.
     - Parameter header: The key of the header.
     - Parameter maxLength: The maximum length of the value.
     - Throws: `RendezvousError.invalidRequest`, if the value is missing, is not base64 encoded, or has invalid length.
     - Returns: The value as data.
     */
    private func get(header: HeaderKey, maxLength: Int) throws -> String {
        let value = try get(header: header)
        guard value.count <= maxLength else {
            throw RendezvousError.invalidRequest
        }
        return value
    }
    
    /**
     Get a binary value from the request headers.
     - Parameter header: The key of the header.
     - Throws: `RendezvousError.invalidRequest`, if the value is missing, or if it is not base64 encoded.
     - Returns: The value as data.
     */
    private func binary(header: HeaderKey) throws -> Data {
        let value = try get(header: header)
        guard let binary = Data(base64Encoded: value) else {
            throw RendezvousError.invalidRequest
        }
        return binary
    }
    
    /**
     Get a binary value from the request headers.
     - Parameter header: The key of the header.
     - Parameter length: The required length of the token.
     - Throws: `RendezvousError.invalidRequest`, if the value is missing, is not base64 encoded, or has invalid length.
     - Returns: The value as data.
     */
    private func binary(header: HeaderKey, length: Int) throws -> Data {
        let value = try binary(header: header)
        guard value.count == length else {
            throw RendezvousError.invalidRequest
        }
        return value
    }
    
    /**
     Get a binary value from a path component.
     */
    private func binaryFromPathComponent(length: Int) throws -> Data {
        let value = try parameters.next(String.self)
        guard let binary = Data(base32Encoded: value) else {
            throw RendezvousError.invalidRequest
        }
        guard binary.count == length else {
            throw RendezvousError.invalidRequest
        }
        return binary
    }
    
    private func key(header: HeaderKey) throws -> Data {
        try binary(header: header, length: Curve25519.keyLength)
    }
    
    private func int(header: HeaderKey) throws -> Int {
        let value = try get(header: header)
        guard let count = Int(value), count >= 0 else {
            throw RendezvousError.invalidRequest
        }
        return count
    }
}
