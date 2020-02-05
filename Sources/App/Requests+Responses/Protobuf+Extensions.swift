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

extension RV_TopicUpdate: SignedProtobuf { }

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

extension RV_InternalUser {
    
    func devices(for appId: String) -> [Data] {
        return devices.compactMap {
            // Filter for devices of the right app.
            guard $0.application == appId else {
                return nil
            }
            return $0.deviceKey
        }
    }
}

extension RV_ManagementData.KeyValuePair {
    
    static func from(_ pair: (key: Data, value: Data)) -> RV_ManagementData.KeyValuePair {
        return .with {
            $0.key = pair.key
            $0.value = pair.value
        }
    }
}

extension RV_ManagementData.DeviceData {
    
    static func from(_ pair: (key: Data, value: RV_DeviceDownload)) -> RV_ManagementData.DeviceData {
        return .with {
            $0.deviceKey = pair.key
            $0.data = pair.value
        }
    }
}
