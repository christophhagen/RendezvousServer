//
//  PreKeys.swift
//  App
//
//  Created by Christoph on 14.01.20.
//

import Foundation
import Vapor

extension Server {

    /**
     Add new prekeys for a device.
     
     
     - Parameter request: The received request.
     - Throws: `RendezvousError`, `ServerError`, `BinaryEncodingError`
     
     - Note: The request must contain a `RV_DevicePrekeyUploadRequest` in the HTTP body.
     
     - Note: Possible errors:
        - `RendezvousError.invalidRequest`, if no body data was provided, or the request data is invalid.
        - `RendezvousError.authenticationFailed`, if the user or device doesn't exist, or the auth token is invalid.
        - `RendezvousError.invalidKeyUpload`, if the signature or public key for a prekey is invalid.
        - `BinaryEncodingError`, if the prekey serialization fails, or if the existing data is not a valid protobuf.
        - `ServerError.fileWriteFailed`, if the prekey data could not be written.
        - `ServerError.fileReadFailed`, if the file could not be read.
     */
    func addDevicePreKeys(_ request: Request) throws {
        // Get the request data
        let data = try request.body()
        let preKeyRequest = try RV_DevicePrekeyUploadRequest(validRequest: data)
        
        // Check if authentication is valid
        _ = try authenticateDevice(user: preKeyRequest.publicKey,
                                   device: preKeyRequest.deviceKey,
                                   token: preKeyRequest.authToken)
        
        let deviceKey = try preKeyRequest.deviceKey.toPublicKey()
        
        // Check the signature for each prekey
        try preKeyRequest.preKeys.forEach {
            guard deviceKey.isValidSignature($0.signature, for: $0.preKey) else {
                throw RendezvousError.invalidSignature
            }
        }
        
        // Add the prekeys to the device
        let count = try storage.store(
            preKeys: preKeyRequest.preKeys,
            for: preKeyRequest.deviceKey,
            of: preKeyRequest.publicKey)
        
        // Update the remaining count
        set(remainingPreKeys: count, for: preKeyRequest.deviceKey)
    }
    
    /**
     Get prekeys for all devices of a user, to create new topic keys.
     
     - Parameter request: The received GET request.
     - Returns: The available keys serialized in an `RV_DevicePreKeyBundle`
     - Throws: `RendezvousError`, `ServerError`, `BinaryEncodingError`
     
     - Note: Possible errors:
        - `RendezvousError.invalidRequest`, if any header is missing or invalid.
        - `RendezvousError.authenticationFailed`, if the user or device doesn't exist, or the token is invalid.
        - `ServerError.fileReadFailed`, if the prekey file for a device could not be read.
        - `BinaryEncodingError`, if the prekey data for a device is not a valid protobuf, or if the prekey serialization fails.
        - `ServerError.fileWriteFailed`, if the prekey data for a device could not be written.
        - `ServerError.deletionFailed`, if the prekey data for a device could not be deleted.
     
     - Note: The request must contain in the HTTP headers:
        - The public key of the user.
        - The public key of the device.
        - The authentication token of the device.
        - The number of keys to get for each device.
     */
    func getDevicePreKeys(_ request: Request) throws -> Data {
        let userKey = try request.userPublicKey()
        let deviceKey = try request.devicePublicKey()
        let authToken = try request.authToken()
        let count = try request.count()
        
        // Check if authentication is valid
        let user = try authenticateDevice(user: userKey, device: deviceKey, token: authToken)
        
        #warning("TODO: Exclude prekeys from requesting device")
        // Get the available device keys and return them
        let devices = user.devices.map { $0.deviceKey }
        let keys = try storage.get(preKeys: count, for: devices, of: userKey)
        
        // Update the remaining count
        for device in keys.devices {
            set(remainingPreKeys: device.remainingKeys, for: device.deviceKey)
        }
        
        // Return the data to send to the client
        return try keys.serializedData()
    }
}
