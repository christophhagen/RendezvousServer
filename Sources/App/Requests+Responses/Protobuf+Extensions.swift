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

extension RV_DevicePrekey: SignedProtobuf, PublicKeyProtobuf { }

extension RV_Topic: TimestampedProtobuf { }
