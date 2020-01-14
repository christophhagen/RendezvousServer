//
//  RendezvousError.swift
//  App
//
//  Created by Christoph on 05.01.20.
//

import Foundation
import Vapor

enum RendezvousError: Int, Error {
    
    /// The request does not contain all necessary data, or some data is not properly formatted.
    case invalidRequest = 400
    
    /// The authentication for the request failed.
    case authenticationFailed = 401
    
    /// The user, device or topic already exists
    case resourceAlreadyExists = 409
    
    /// A signature for a request was invalid
    case invalidSignature = 406
    
    /// The request is too old to be processed.
    case requestOutdated = 410
    
    /// Invalid topic key signature, missing receiver, or missing device.
    case invalidKeyUpload = 412
    
    /// Some requested data is not available.
    case resourceNotAvailable = 404
    
    var response: HTTPResponseStatus {
        switch self {
        case .invalidRequest:
            return .badRequest
        case .authenticationFailed:
            return .unauthorized
        case .resourceAlreadyExists:
            return .conflict
        case .invalidSignature:
            return .notAcceptable
        case .requestOutdated:
            return .gone
        case .invalidKeyUpload:
            return .preconditionFailed
        case .resourceNotAvailable:
            return .notFound
        }
    }
    
}
