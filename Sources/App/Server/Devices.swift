//
//  Devices.swift
//  App
//
//  Created by Christoph on 14.01.20.
//

import Foundation
import Vapor

extension Server {
    
    /**
     Register a new device for a user.
     
     - Parameter request: The received POST request.
     - Returns: The authentication token for the device.
     - Throws: `RendezvousError`, `BinaryEncodingError`
     
     - Note: The request must contain in the HTTP body:
        - A protobuf object of type `RV_InternalUser`, with only the new device added.
     
     - Note: Possible errors:
        - `RendezvousError.invalidRequest`, if the body data is missing or not a valid protobuf object
        - `RendezvousError.authenticationFailed`, if the user public key doesn't exist.
        - `RendezvousError.userOrDeviceAlreadyExists`, if a device with the same public key already exists.
        - `RendezvousError.invalidSignature`, if the signature doesn’t match the public key.
        - `RendezvousError.requestOutdated`, if the timestamp of the request is not fresh.
        - `BinaryEncodingError`, if the protobuf operations produce an error.
     */
    func registerDevice(_ request: Request) throws -> Data {
        // Get the data from the request.
        let data = try request.body()
        let userInfo = try RV_InternalUser(validRequest: data)
        
        // Check that the user exists
        guard let oldInfo = user(with: userInfo.publicKey) else {
            throw RendezvousError.authenticationFailed
        }
        
        
        
        // Check that at least one device is present
        guard userInfo.devices.count == oldInfo.devices.count + 1 else {
            throw RendezvousError.invalidRequest
        }
        
        // Check that the request is fresh.
        try userInfo.isFreshAndSigned()
        
        // Check that the info is newer
        guard userInfo.timestamp >= oldInfo.timestamp else {
            throw RendezvousError.requestOutdated
        }
        
        // Check that no other data was modified
        var oldDevices = userInfo.devices
        let newDevice = oldDevices.popLast()!
        guard userInfo.creationTime == oldInfo.creationTime,
            userInfo.name == oldInfo.name,
            userInfo.notificationServer == oldInfo.notificationServer,
            oldDevices == oldInfo.devices else {
                throw RendezvousError.invalidRequest
        }

        // Check that the device doesn't exist yet.
        guard !deviceExists(newDevice.deviceKey) else {
            throw RendezvousError.resourceAlreadyExists
        }
        
        // Create an authentication token
        let authToken = makeAuthToken()
        set(authToken: authToken, for: newDevice.deviceKey)
        
        // Write the new info
        set(userInfo: userInfo)
        
        // Initialize the device data
        createDeviceData(for: newDevice.deviceKey)
        
        log(info: "User '\(userInfo.name)': New device registered")
        
        // Return the authentication token
        return authToken
    }
    
    /**
     Add a notification token for a device.
     
     The token will be used to authenticate the server when sending push notifications to the notification server of the user.
     
     - Parameter request: The received POST request.
     - Throws: `RendezvousError`
     
     - Note: The request must contain the user key, device key and authentication token in the HTTP headers, and an authentication token in the HTTP body.
     
     - Note: Possible Errors:
        - `invalidRequest`, if the user key, device key, or authentication token are missing, or if the provided notification token has invalid length.
        - `authenticationFailed`, if the user or device doesn't exist, or the token is invalid
     */
    func addPushTokenForDevice(_ request: Request) throws {
        let userKey = try request.userPublicKey()
        let deviceKey = try request.devicePublicKey()
        let authToken = try request.authToken()
        let notificationToken = try request.body()
        
        guard notificationToken.count == Server.authTokenLength else {
            throw RendezvousError.invalidRequest
        }
        
        // Check if authentication is valid
        _ = try authenticateDevice(user: userKey, device: deviceKey, token: authToken)
        
        add(notificationToken: notificationToken, for: deviceKey)
    }
    
    /**
     Remove a device from a user.
     
     - Parameter request: The received POST request.
     - Throws: `RendezvousError` and `BinaryEncodingError` errors
     
     - Note: The request must contain in the HTTP body:
        - A protobuf object of type `RV_InternalUser`, with only the device removed.
     
     - Note: Possible errors:
        - `RendezvousError.invalidRequest`, if the request data is malformed or missing.
        - `RendezvousError.authenticationFailed`, if the user doesn't exist.
        - `RendezvousError.invalidSignature`, if the signature doesn't match the data.
        - `RendezvousError.requestOutdated`, if the timestamp of the request is not fresh.
        - `BinaryEncodingError`, if the internal protobuf handling for signature verification fails.
     */
    func deleteDevice(_ request: Request) throws {
        // Get the data from the request.
        let data = try request.body()
        let userInfo = try RV_InternalUser(validRequest: data)
        
        // Check that the user exists
        guard let oldInfo = user(with: userInfo.publicKey) else {
            throw RendezvousError.authenticationFailed
        }
        
        // Check that one device was removed.
        guard userInfo.devices.count == oldInfo.devices.count - 1 else {
            throw RendezvousError.invalidRequest
        }
        
        // Check that the request is fresh.
        try userInfo.isFreshAndSigned()
        
        // Check that the info is newer
        guard userInfo.timestamp > oldInfo.timestamp else {
            throw RendezvousError.requestOutdated
        }
        
        // Check that no other data was modified
        var newDevices = oldInfo.devices
        let index = oldInfo.devices.firstIndex { !userInfo.devices.contains($0) }!
        let oldDevice = newDevices.remove(at: index)
        guard userInfo.creationTime == oldInfo.creationTime,
            userInfo.name == oldInfo.name,
            userInfo.notificationServer == oldInfo.notificationServer,
            newDevices == userInfo.devices else {
                throw RendezvousError.invalidRequest
        }

        // Remove the authentication token and device data
        delete(device: oldDevice.deviceKey)
        
        // Write the new info
        set(userInfo: userInfo)
        
        log(info: "User '\(userInfo.name)': Device deleted")
        try storage.deleteData(forDevice: oldDevice.deviceKey, of: userInfo.publicKey)
    }
    
}
