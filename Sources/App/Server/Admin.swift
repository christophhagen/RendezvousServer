//
//  Admin.swift
//  App
//
//  Created by Christoph on 14.01.20.
//

import Foundation
import Vapor

extension Server {
    
    /**
     Check that the admin credentials are valid.
     
     - The request must contain the current admin token in the request header.
     
     - Parameter request: The received request.
     - Throws: `RendezvousError` errors
     - Note: Possible errors:
     - `invalidRequest`, if the request doesn't contain an authentication token.
     - `authenticationFailed`, if the admin token is invalid.
     */
    func checkAdminAccess(_ request: Request) throws {
        // Check authentication
        let authToken = try request.authToken()
        guard constantTimeCompare(authToken, adminToken) else {
            throw RendezvousError.authenticationFailed
        }
    }
    
    /**
     Update the authentication token of the admin.
     
     The request must contain in the HTTP headers:
     - The authentication token of the admin.
     
     - Parameter request: The received request.
     - Returns: The new admin token.
     */
    func updateAdminAuthToken(_ request: Request) throws -> Data {
        try checkAdminAccess(request)
        adminToken = makeAuthToken()
        log(info: "Admin authentication token changed")
        didChangeData()
        return adminToken
    }
    
    /**
     Delete all server data.
     
     - Parameter request: The received GET request.
     */
    func deleteAllServerData(_ request: Request) throws {
        try checkAdminAccess(request)
        try reset()
    }
    
    
    /**
     Allow a user to register on the server.
     
     - Note: The request must contain the authentication token of the admin and the name of the user in the HTTP headers.
     
     - Parameter request: The received POST request.
     - Returns: The serialized data of the user (`RV_AllowedUser`)
     - Throws: `RendezvousError` errors, `ServerError` errors
     
     - Note: Possible errors:
        - `RendezvousError.invalidRequest`, if the request doesn't contain an authentication token.
        - `RendezvousError.authenticationFailed`, if the admin token is invalid.
        - `RendezvousError.userOrDeviceAlreadyExists`, if the user is already registered.
        - `BinaryEncodingError`, if the response protobuf couldn't be serialized
     */
    func allowUser(_ request: Request) throws -> Data {
        try checkAdminAccess(request)
        
        // Extract the user and check that it doesn't exist yet
        let name = try request.user()
        guard !userExists(name) else {
            throw RendezvousError.resourceAlreadyExists
        }
        
        // Create the user with a random pin and the expiry date
        let user = RV_AllowedUser.with {
            $0.name = name
            $0.pin =  UInt32.random(in: 0..<Server.pinMaximum)
            $0.expiry = timeInSeconds() + Server.pinExpiryInterval
            $0.numberOfTries = Server.pinAllowedTries
        }
        
        // Store the user
        allow(user: user)
        
        didChangeData()
        log(debug: "Allowed user '\(user.name)' to register.")
        
        // Return the pin, expiry and username in the response
        return try user.serializedData()
    }
    
}
