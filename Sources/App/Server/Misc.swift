//
//  Misc.swift
//  App
//
//  Created by Christoph on 14.01.20.
//

import Foundation
import Ed25519

extension Data {
    
    func toPublicKey() throws -> Ed25519.PublicKey {
        try Ed25519.PublicKey(rawRepresentation: self)
    }
}
