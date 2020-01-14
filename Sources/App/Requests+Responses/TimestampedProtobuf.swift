//
//  TimestampedProtobuf.swift
//  App
//
//  Created by Christoph on 08.01.20.
//

import Foundation
import SwiftProtobuf
import Ed25519

protocol TimestampedProtobuf: SignedProtobuf, PublicKeyProtobuf {
    
    var timestamp: UInt32 { get set }
}

extension TimestampedProtobuf {
    
    /// The number of seconds until a deletion request becomes invalid
    static var requestFreshnessAllowedDelay: UInt32 {
        return 60
    }
    
    /**
     Check that the request has been created recently, and that the signature matches the contained public key.
     
     - Throws: `RendezvousError`, `BinaryEncodingError`
     - Note: Possible Errors:
        - `RendezvousError.invalidSignature`, if the signature doesn't match the public key.
        - `RendezvousError.requestOutdated`, if the timestamp of the request is not fresh.
        - `BinaryEncodingError`, if the protobuf operations produce an error.
     */
    func isFreshAndSigned() throws {
        guard timestamp > Date.secondsNow - Self.requestFreshnessAllowedDelay else {
            throw RendezvousError.requestOutdated
        }
        try verifySignature()
    }
    
    /**
     Renew the timestamp and sign the data.
     
     - Parameter privateKey: The signing key.
     - Throws: `BinaryEncodingError`, if the serialization for the signature fails.
     */
    mutating func timestamp(andSignWith privateKey: Ed25519.PrivateKey) throws {
        self.timestamp = Date.secondsNow
        self.signature = Data()
        let data = try serializedData()
        self.signature = privateKey.signature(for: data)
    }
    
    /**
     Add a timestamp to the rotobuf object, sign it, and serialize it.
     
     - Parameter privateKey: The signing key.
     - Returns: The serialized data.
     - Throws: `BinaryEncodingError`, if the serialization fails.
     */
    func data(timestampedAndSignedWith privateKey: Ed25519.PrivateKey) throws -> Data {
        var object = self
        try object.timestamp(andSignWith: privateKey)
        return try object.serializedData()
    }
}

extension Date {
    
    /// The current seconds since 1.1.1970
    static var secondsNow: UInt32 {
        return UInt32(Date().timeIntervalSince1970)
    }
    
    /**
     Create a date from the seconds since 1.1.1970.
     
     - Parameter seconds: The seconds since 1.1.1970.
     */
    init(seconds: UInt32) {
        self.init(timeIntervalSince1970: TimeInterval(seconds))
    }
    
    /// The date expressed in seconds since 1.1.1970
    var seconds: UInt32 {
        UInt32(timeIntervalSince1970)
    }
}
