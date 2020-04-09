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
     
     - Parameter request: The received request.
     - Throws: `RendezvousError` errors
     
     - Note: The request must contain the current admin token in the request header.
     
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
    func updateAdminAuthToken(_ request: Request) throws -> AuthToken {
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
            $0.pin =  UInt32.random(in: 0..<Constants.pinMaximum)
            $0.expiry = timeInSeconds() + Constants.pinExpiryInterval
            $0.numberOfTries = Constants.pinAllowedTries
        }
        
        // Store the user
        allow(user: user)
        
        didChangeData()
        log(debug: "Allowed user '\(user.name)' to register.")
        
        // Return the pin, expiry and username in the response
        return try user.serializedData()
    }
    
    /**
     Handle a request to delete an existing user.
     
     The request must contain in the HTTP body:
     - A protobuf object of type `RV_InternalUser`
     
     - Parameter request: The received request.
     - Throws: `RendezvousError` and `ServerError` errors
     
     - Note: The request must contain the current admin token and the user key in the request header.
      
     - Note: Possible errors:
        - `RendezvousError.invalidRequest`, if the request doesn't contain an authentication token or user key.
        - `RendezvousError.authenticationFailed`, if the admin token is invalid.
        - `ServerError.deletionFailed`, if the user folder could not be deleted.
     */
    func deleteUserAsAdmin(_ request: Request) throws {
        try checkAdminAccess(request)
        
        let userKey = try request.userPublicKey()

        // Check that the user exists.
        guard let user = self.user(with: userKey) else {
            throw RendezvousError.resourceNotAvailable
        }
        
        // Delete the user data
        try storage.deleteData(forUser: userKey)
        
        // Delete the user
        delete(user: userKey)
        
        // Delete all of the users devices
        for device in user.devices {
            delete(device: device.deviceKey)
        }
        didChangeData()
    }
    
    func enableTestAccounts(_ request: Request) throws {
        try checkAdminAccess(request)
        
        // Alice
        set(userInfo: aliceUserInfo)
        set(authToken: aliceAuthToken, for: aliceDeviceKey)
        createDeviceData(for: aliceDeviceKey, remainingPreKeys: 0, remainingTopicKeys: 0)
        
        // Bob
        set(userInfo: bobUserInfo)
        set(authToken: bobAuthToken, for: bobDeviceKey)
        createDeviceData(for: bobDeviceKey, remainingPreKeys: 0, remainingTopicKeys: 0)
        
        // Create topic
        try storage.create(topic: topicId)
        add(topic: topicForAliceAndBob)
    }
}

private var aliceUserKey: SigningPrivateKey {
    SigningPrivateKey("39XzfZHV9iT5kDbgn7od8bLhUF5Yceu64mLf/hml3qo=")
}

private var bobUserKey: SigningPrivateKey {
    SigningPrivateKey("IHUznMEmKl4jUaMa+WxDbFFAAXLOYrEUWe1TpHdzpIQ=")
}

private var aliceDeviceKey: DeviceKey {
    SigningPrivateKey("gAil9KMsuXrhNzrA6/uIicEq7s2h8haSMCwDfKIkMvY=").publicKey.rawRepresentation
}

private var bobDeviceKey: DeviceKey {
    SigningPrivateKey("lBiJ6qRU9SEpB27UMMeSKfpi/gfAYuannkP1KcteZ1o=").publicKey.rawRepresentation
}

private var aliceAuthToken: Data {
    Data(base64Encoded: "51ajGY/YncZQh4k+OAjeEA==")!
}

private var bobAuthToken: Data {
    Data(base64Encoded: "XxGKcXdxST74MigCfTNiPA==")!
}

private var aliceUserInfo: RV_InternalUser {
    try! .init(serializedData: Data(base64Encoded: "CiDKdUb1kY4LsZbIq/gCfxJFg6wNdxQMZiyAVOxDi6MhKRDIu6P0BRoFQWxpY2UiLgogTtrvi4edyq0bvXYYtB3NHrUprRL+bLgvpHlFCvccMw8QyLuj9AUYASICQ0MoyLuj9AU6QCbo9rtLlKfGixtstQFKk6deAfjaZkd4OZXHpPoyWH75B2s59fq+fSPHqG9wejpNDoOze+lF1mvVUNYjWju+hgk=")!)
}

private var bobUserInfo: RV_InternalUser {
    try! .init(serializedData: Data(base64Encoded: "CiAJIw6IEjgTn218itF6oyPFLnkpMTp/yHfSRL0r069YyhDZ2qP0BRoDQm9iIi4KILMn1C+mnpftvFOR7xwNq4+aDehzscC8wAAEa4C4vgkqENnao/QFGAEiAkNDKNnao/QFOkBiqGvL4AbPWuXnVzHldkMAaTbDYhShrwZ5jhCleowBoMQx3643tV6ddvx/kcMam4KvqSUfeqYss5yoBT7ffk0G")!)
}

private var topicId: TopicID {
    Data(base64Encoded: "WVDrge+XZp9heqPO")!
}

private var topicForAliceAndBob: RV_Topic {
    try! .init(serializedData: Data(base64Encoded: "")!)
}

private extension SigningPrivateKey {
    
    init(_ base64: String) {
        try! self.init(rawRepresentation: Data(base64Encoded: base64)!)
    }
}
