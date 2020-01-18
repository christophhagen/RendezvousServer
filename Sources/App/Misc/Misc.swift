//
//  Misc.swift
//  App
//
//  Created by Christoph on 14.01.20.
//

import Foundation
import Ed25519

extension Data {
    
    /**
     Convert the data to a public signing key.
     - Returns: The public key.
     - Throws: `RendezvousError.invalidRequest`, if the data is not a valid public key.
     */
    func toPublicKey() throws -> Ed25519.PublicKey {
        do {
            return try Ed25519.PublicKey(rawRepresentation: self)
        } catch {
            throw RendezvousError.invalidRequest
        }
    }
}
