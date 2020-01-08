//
//  Request+Extensions.swift
//  App
//
//  Created by Christoph on 05.01.20.
//

import Foundation
import Vapor


extension Request {
    
    /**
     Search for a key in the request header, and throw an error if the key is missing.
     - Parameter header: The key of the header.
     - Returns: The value as a string.
     - Throws: `RendezvousError.parameterMissingInRequest`, if the value is missing.
     */
    private func get(header: HeaderKey) throws -> String {
        guard let value = http.headers.firstValue(name: .init(header.rawValue)) else {
            Log.log(info: "Missing HTTP header \(header) in request")
            throw RendezvousError.parameterMissingInRequest
        }
        return value
    }
    
    /**
     Get a binary value from the request headers.
     - Parameter header: The key of the header.
     - Throws: `RendezvousError.parameterMissingInRequest`, if the value is missing, or if it is not base64 encoded.
     - Returns: The value as data.
     */
    private func binary(header: HeaderKey) throws -> Data {
        let value = try get(header: header)
        guard let binary = Data(base64Encoded: value) else {
            throw RendezvousError.parameterMissingInRequest
        }
        return binary
    }
    
    /**
     Get the authentication token from the request.

     This can be the administrator token, the user token, or the device token.
     - Returns: The  binary token.
     - Throws: `RendezvousError` errors
     - Note: An authentication token is always `Management.authTokenLength` bytes of binary data, and is sent base64 encoded in requests.
     - Note: Possible Errors:
     - `parameterMissingInRequest`, if the request doesn't contain a token, if the token is not base64 encoded data, or if the length of the token is invalid.
     */
    func authToken() throws -> Data {
        let token = try binary(header: .authToken)
        guard token.count == Management.authTokenLength else {
            throw RendezvousError.parameterMissingInRequest
        }
        return token
    }
    
    /**
     Get the user name from the request.
     - Note:User names have a maximum length of `Management.maximumNameLength` characters.
     - Returns: The user name.
     - Throws: `RendezvousError` errors
     - Note: Possible Errors:
     - `parameterMissingInRequest`, if the request doesn't contain a user name, or if the name is longer than `Management.maximumNameLength` characters.
     */
    func user() throws -> String {
        let name = try get(header: .username)
        guard name.count >= Management.maximumNameLength else {
            throw RendezvousError.parameterMissingInRequest
        }
        return name
    }
    
    /**
    Get the pin from the request.
    - Note:Pins have a maximum length of 32 characters.
    - Returns: The user name.
    - Throws: `RendezvousError` errors
    - Note: Possible Errors:
    - `parameterMissingInRequest`, if the request doesn't contain a pin, or if the pin is not a valid number.
    */
    func pin() throws -> UInt32 {
        let value = try get(header: .pin)
        guard let pin = UInt32(value), pin < Management.pinMaximum else {
            throw RendezvousError.parameterMissingInRequest
        }
        return pin
    }
    
    /**
     Get the public key from the request.
     - Returns: The public key in binary format.
     - Throws: `RendezvousError` errors
     - Note: Possible Errors:
     - `parameterMissingInRequest`, if the request doesn't contain a key, or if the key has invalid length.
     */
    func key() throws -> PublicKey {
        let key = try binary(header: .key)
        guard key.count == Management.publicKeyLength else {
            throw RendezvousError.parameterMissingInRequest
        }
        return key
    }
}
