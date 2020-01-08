//
//  Server.swift
//  App
//
//  Created by Christoph on 05.01.20.
//

import Foundation

final class Server {
    
    let management: Management
    
    let storage: Storage
    
    init(config: Config) throws {
        let storage = Storage(baseURL: config.baseDirectory)
        if let data = try storage.managementData() {
            self.management = try Management(storedData: data)
        } else {
            self.management = Management()
        }
        self.storage = storage
        management.delegate = self
    }
}

extension Server: ManagementDelegate {
    
    func management(shouldPersistData data: Data) {
        // Store data on disk
    }
    
    func management(created user: String) throws {
        try storage.create(user: user)
    }
    
    func management(deleted user: String) throws {
        try storage.deleteData(forUser: user)
    }
}
