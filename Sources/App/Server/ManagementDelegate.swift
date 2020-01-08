//
//  ManagementDelegate.swift
//  App
//
//  Created by Christoph on 05.01.20.
//

import Foundation

protocol ManagementDelegate {
    
    /**
     The management data changed and should be saved to disk.
     - Parameter data: The management data.
     - Note: The data handed to this function can be used to restore the management instance by calling `Management(data:delegate:)`
     */
    func management(shouldPersistData data: Data)
    
    /**
     The management has created a user and expects that the storage provider creates the user directory.
     - Parameter user: The created user.
     - Throws: Errors from `Storage.create(user:)`
     */
    func management(created user: String) throws
    
    /**
     The management deleted a user and expects taht the storage provider deletes the user directory.
     - Parameter user: The deleted user.
     - Throws: Error from `Storage.deleteData(forUser:)`
     */
    func management(deleted user: String) throws
}
