//
//  PublicKeyProtobuf.swift
//  App
//
//  Created by Christoph on 08.01.20.
//

import Foundation
import CryptoKit25519
import SwiftProtobuf

protocol PublicKeyProtobuf: SwiftProtobuf.Message {
    
    var publicKey: Data { get set }
}

extension PublicKeyProtobuf {
    
    mutating func set(publicKey: Curve25519.Signing.PublicKey) {
        self.publicKey = publicKey.rawRepresentation
    }
    
    /**
     Get the public key from a protobuf.
     - Returns: The valid public key.
     - Throws: `RendezvousError.invalidRequest`, if the key is invalid.
     */
    func getPublicKey() throws -> Curve25519.Signing.PublicKey {
        do {
            return try .init(rawRepresentation: publicKey)
        } catch {
            throw RendezvousError.invalidRequest
        }
    }
}
