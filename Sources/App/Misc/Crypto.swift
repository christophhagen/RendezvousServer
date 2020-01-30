//
//  Crypto.swift
//  App
//
//  Created by Christoph on 05.01.20.
//

import Foundation
import Crypto

func timeInSeconds() -> UInt32 {
     return UInt32(Date().timeIntervalSince1970)
}

/**
 Compare two token in (hopefully) constant time.
 - Returns: `true`, if the tokens match.
 */
func constantTimeCompare(_ lhs: Data, _ rhs: Data) -> Bool {
    guard lhs.count == rhs.count else {
        return false
    }
    var areEqual = true
    for i in 0..<lhs.count {
        areEqual = areEqual && constantTimeCompare(lhs[i], rhs[i])
    }
    return areEqual
}

/**
Compare two bytes in (hopefully) constant time.
- Returns: `true`, if the values match.
*/
private func constantTimeCompare(_ lhs: UInt8, _ rhs: UInt8) -> Bool {
    var areEqual = true
    for i in 0..<8 {
        areEqual = areEqual && (lhs & (1 << i) == rhs & (1 << i))
    }
    return areEqual
}

/**
 Create a number of random bytes.
 - Parameter count: The number of bytes to create.
 - Returns: The created bytes.
 */
func randomBytes(count: Int) -> Data {
    #warning("Ensure cryptographically secure random numbers")
    return try! CryptoRandom().generateData(count: count)
}
