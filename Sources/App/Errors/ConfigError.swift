//
//  ConfigError.swift
//  App
//
//  Created by Christoph on 08.01.20.
//

import Foundation

enum ConfigError: Error {
    
    /// The config file could not be found
    case fileNotFound(String)
    
    /// The file could not be read
    case fileReadFailed(String)
    
    /// The config file is not valid JSON
    case invalidJSON(Error)
    
    /// The config file is missing a parameter
    case missingParameter
    
}
