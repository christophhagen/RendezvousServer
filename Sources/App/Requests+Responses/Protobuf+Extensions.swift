//
//  Protobuf+Extensions.swift
//  App
//
//  Created by Christoph on 08.01.20.
//

import Foundation
import SwiftProtobuf

extension SwiftProtobuf.Message {
    
    /**
    Read a protobuf from a request..
    - Parameter data: The data from the request.
    - Throws: `RendezvousError.invalidRequest`
    */
    init(validRequest data: Data) throws {
        do {
            try self.init(serializedData: data)
        } catch {
            throw RendezvousError.invalidRequest
        }
    }
}

extension RV_InternalUser: TimestampedProtobuf { }

extension RV_TopicMessage: SignedProtobuf { }

extension RV_Topic: TimestampedProtobuf {
    
    var publicKey: Data {
        get {
            guard indexOfMessageCreator < members.count else {
                return Data()
            }
            return members[Int(indexOfMessageCreator)].signatureKey
        }
        set {
            guard indexOfMessageCreator < members.count else {
                return
            }
            members[Int(indexOfMessageCreator)].signatureKey = newValue
        }
    }
}
