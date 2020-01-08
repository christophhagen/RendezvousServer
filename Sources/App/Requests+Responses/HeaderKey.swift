//
//  HeaderKey.swift
//  App
//
//  Created by Christoph on 05.01.20.
//

import Foundation

/**
 An enum with all possible header keys used by Rendezvous.
 */
enum HeaderKey: String {
    
    /// The authentication token (admin, user, or device)
    case authToken = "auth"
    
    /// The user name, when a new user is created.
    case username = "user"
    
    /// The pin used for registration
    case pin = "pin"
    
    /// A public key, either the user id or the device id
    case key = "key"
}
