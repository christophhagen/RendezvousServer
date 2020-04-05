//
//  SignedProtobuf.swift
//  App
//
//  Created by Christoph on 08.01.20.
//

import Foundation
import SwiftProtobuf
import CryptoKit25519

protocol SignedProtobuf: SwiftProtobuf.Message {
    
    var signature: Data { get set }
}

extension SignedProtobuf {
    
    /// A copy of the protobuf object without the signature.
    var withoutSignature: Self {
        var object = self
        object.signature = Data()
        return object
    }
    
    /**
     The serialized data without the signature.
     - Returns: The serialized data of the object, without the signature.
     - Throws: `BinaryEncodingError`, if the serialization fails
     */
    func dataWithoutSignature() throws -> Data {
        return try withoutSignature.serializedData()
    }
    
    /**
     Verify the signature of a protobuf object.
     
     - Parameter publicKey: The public key to verify the signature.
     - Throws: `RendezvousError.invalidSignature`, `BinaryEncodingError`
     */
    func verifySignature(with publicKey: SigningPublicKey) throws {
        let signature = self.signature
        let data = try dataWithoutSignature()
        guard publicKey.isValidSignature(signature, for: data) else {
            throw RendezvousError.invalidSignature
        }
    }
    
    /**
     Signs the protobuf data and adds the signature to the object.
     - Parameter privateKey: The private key to sign the message.
     - Throws: `BinaryEncodingError`, if the serialization for the signature fails.
     */
    mutating func sign(with privateKey: Curve25519.Signing.PrivateKey) throws {
        self.signature = Data()
        let data = try self.serializedData()
        self.signature = privateKey.signature(for: data)
    }
    
    /**
     Sign the protobuf data, add the signature, and serialize the data.
     - Parameter privateKey: The private key to sign the message.
     - Throws: `BinaryEncodingError`, if the serialization fails.
     */
    func data(signedWith privateKey: Curve25519.Signing.PrivateKey) throws -> Data {
        var object = self
        object.signature = Data()
        let data = try object.serializedData()
        object.signature = privateKey.signature(for: data)
        return try object.serializedData()
    }
}

extension SignedProtobuf where Self: PublicKeyProtobuf {
    
    /**
     Verify the signature of a protobuf object with the included public key.
     - Throws: `RendezvousError.invalidSignature`, `BinaryEncodingError`
     */
    func verifySignature() throws {
        let publicKey = try getPublicKey()
        let signature = self.signature
        let data = try dataWithoutSignature()
        guard publicKey.isValidSignature(signature, for: data) else {
            throw RendezvousError.invalidSignature
        }
    }
}
