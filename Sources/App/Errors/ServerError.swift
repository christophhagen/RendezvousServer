//
//  ServerError.swift
//  App
//
//  Created by Christoph on 05.01.20.
//

import Foundation

/**
 Errors that can happen on the server side, but are not relayed to clients.
 */
enum ServerError: Error {
    
    /// The management data stored on disk is not valid.
    case invalidManagementData
    
    /// Some item could not be deleted.
    case deletionFailed
    
    /// A folder could not be created.
    case folderCreationFailed
    
    /// A file could not be written to disk.
    case fileWriteFailed
    
    /// A file could not be read from disk.
    case fileReadFailed
}
