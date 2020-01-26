//
//  Misc.swift
//  App
//
//  Created by Christoph on 14.01.20.
//

import Foundation
import CryptoKit25519

extension Data {
    
    /**
     Convert the data to a public signing key.
     - Returns: The public key.
     - Throws: `RendezvousError.invalidRequest`, if the data is not a valid public key.
     */
    func toPublicKey() throws -> Curve25519.Signing.PublicKey {
        do {
            return try .init(rawRepresentation: self)
        } catch {
            throw RendezvousError.invalidRequest
        }
    }
}
