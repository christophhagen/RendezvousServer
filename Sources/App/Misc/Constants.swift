//
//  Constants.swift
//  App
//
//  Created by Christoph on 03.02.20.
//

import Foundation

public enum Constants {
    
    /// The time interval after which pins expire (in seconds)
    public static let pinExpiryInterval: UInt32 = 60 * 60 * 32 * 7
    
    /// The number of times a pin can be wrong before blocking the registration
    public static let pinAllowedTries: UInt32 = 3
    
    /// The maximum value for the pin
    public static let pinMaximum: UInt32 = 100000
    
    /// The maximum allowed characters for user names
    public static let maximumNameLength = 32
    
    /// The number of bytes for an authentication token
    public static let authTokenLength = 16
    
    /// The length of a topic id
    public static let topicIdLength = 12
    
    /// The length of a message id
    public static let messageIdLength = 12
    
    /// The length of a SHA256 hash (in bytes)
    public static let hashLength = 32
    
    /// The length of a message authentication code
    public static let tagLength = 16
    
    /// The maximum length of an app id
    public static let maximumAppIdLength = 10
    
    /// The maximum length of message metadata
    public static let maximumMetadataLength = 100
    
}
