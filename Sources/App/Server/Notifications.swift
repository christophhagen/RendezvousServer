//
//  Notifications.swift
//  App
//
//  Created by Christoph on 26.01.20.
//

import Foundation
import Vapor
import SwiftProtobuf
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

extension Server {
    
    func push(topicMessage: RV_DeviceDownload.Message, to device: Data, of user: Data) {
        push(topicMessage, type: "message", to: device, of: user)
    }
    
    func push(topicUpdate: RV_Topic, to device: Data, of user: Data) {
        push(topicUpdate, type: "topic", to: device, of: user)
    }
    
    private func push(_ object: SwiftProtobuf.Message, type: String, to device: Data, of user: Data) {
        
        guard let data = try? object.serializedData() else {
            log(error: "Failed to serialize '\(type)' for push notification")
            return
        }
        guard let deviceToken = notificationToken(for: device)?.base64EncodedString() else {
            return
        }
        
        let server = notificationServer(for: user).appendingPathComponent(type)
        
        DispatchQueue.global(qos: .utility).async {
            var request = URLRequest(url: server)
            request.httpMethod = "POST"
            request.httpBody = data
            request.addValue(deviceToken, forHTTPHeaderField: "device")
            
            let task = URLSession.shared.dataTask(with: request) { _, response, error in
                #warning("Handle errors from push requests")
            }
            task.resume()
        }
    }
}
