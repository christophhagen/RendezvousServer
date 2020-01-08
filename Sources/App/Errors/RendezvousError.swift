//
//  RendezvousError.swift
//  App
//
//  Created by Christoph on 05.01.20.
//

import Foundation


enum RendezvousError: Error {
    
    /// A required HTTP header value is missing in the request.
    case parameterMissingInRequest
    
    /// The authentication for the request failed.
    case authenticationFailed
    
    /// The user who is supposed to be registered already exists
    case userAlreadyExists
    
    
    
}
