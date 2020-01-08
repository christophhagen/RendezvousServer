//
//  Storage.swift
//  App
//
//  Created by Christoph on 05.01.20.
//

import Foundation

final class Storage: Logger {
    
    /// The file manager
    let fm = FileManager.default
    
    /// The root directory for the server data.
    let base: URL
    
    // MARK: Initialization
    
    /**
     Initialize the storage interface.
     - Parameter baseURL: The root directory for the server data.
     */
    init(baseURL: URL) {
        self.base = baseURL
        
        testReadAndWriteToBaseDirectory()
    }
    
    /**
     Test the directory to see if writing and reading works.
     - Note: Produces an application crash, if the server directory is not accessible.
     */
    private func testReadAndWriteToBaseDirectory() {
        let string = "WriteTest"
        let url = testURL
        // Test write permissions
        do {
            try string.data(using: .utf8)!.write(to: url)
        } catch {
            fatalError("Failed to write to server directory \(base.path): \(error)")
        }
        // Test read permissions
        do {
            let read = try String(contentsOf: url)
            guard read == string else {
                fatalError("Failed to read from server directory \(base.path): Data invalid: \(read)")
            }
        } catch {
            fatalError("Failed to read from server directory \(base.path): \(error)")
        }
        // Test deletion
        do {
            try removeItem(at: url)
        } catch {
            fatalError("Failed to delete from server directory \(base.path): \(error)")
        }
    }
    
    private func createUsersDirectory() {
        
    }
    
    // MARK: URLs
    
    /// A url to a test file in the base directory
    var testURL: URL {
        return base.appendingPathComponent("permissions")
    }
    
    /// The directory where the user data is stored
    private var usersDirectory: URL {
        return base.appendingPathComponent("users")
    }
    
    /**
     The url to the folder of a user.
     - Parameter user: The user
     - Returns: The url of the user folder.
     */
    private func userURL(_ user: String) -> URL {
        return usersDirectory.appendingPathComponent(user)
    }
    
    /// The url for the management data, which contains users, devices and tokens.
    private var managementDataURL: URL {
        return base.appendingPathComponent("server")
    }
    
    // MARK: Users
    
    /**
     Create the folder structure for a user.
     - Throws: `ServerError` errors
     - Note: Possible errors:
     - `deletionFailed`, if an existing folder could not be deleted
     - `folderCreationFailed`, if the user folder couldn't be created.
     */
    func create(user: String) throws {
        let url = userURL(user)
        // Remove any existing directory or file
        try removeItem(at: url)
        // Create the folder
    }
    
    /**
     Remove a user folder, and thus all data from the user.
     - Parameter user: The user whose data to delete.
     - Throws: `ServerError.deletionFailed`, if the file/folder could not be deleted
     */
    func deleteData(forUser user: String) throws {
        let url = userURL(user)
        try removeItem(at: url)
    }
    
    // MARK: Management data
    
    /**
     Store management data on disk.
     - Parameter data: The data to store.
     - Throws: `ServerError.fileWriteFailed`, if the data could not be written.
     */
    func store(managementData data: Data) throws {
        let url = managementDataURL
        try write(data: data, to: url)
    }
    
    /**
     Get the management data on disk.
     - Returns: The data, if it exists.
     - Throws: `ServerError.fileReadFailed`, if the data could not be read.
     */
    func managementData() throws -> Data? {
        let url = managementDataURL
        guard dataExists(at: url) else {
            return nil
        }
        return try data(at: url)
    }
    
    /**
     Delete the management data from disk.
     - Throws: `ServerError.deletionFailed`, if the data could not be deleted
     */
    func deleteManagementData() throws {
        let url = managementDataURL
        guard dataExists(at: url) else {
            return
        }
        try removeItem(at: url)
    }
    
    // MARK: Basic functions
    
    /**
     Check if a file or directory exists at the url.
     - Parameter url: The url to check.
     - Returns: `true`, if a file or directory exists.
     */
    private func dataExists(at url: URL) -> Bool {
        return fm.fileExists(atPath: url.path)
    }
    
    /**
     Create a folder.
     - Parameter url: The url of the folder to create.
     - Throws: `ServerError.folderCreationFailed`, if the folder couldn't be created.
     - Note: This function assumes that the parent directory exists.
     */
    private func createFolder(at url: URL) throws {
        do {
            try fm.createDirectory(at: url, withIntermediateDirectories: false)
        } catch {
            log(error: "Failed to create directory \(url.path): \(error)")
            throw ServerError.folderCreationFailed
        }
    }
    
    /**
    Write data to a url.
     - Parameter data: The data to write.
     - Parameter url: The url to write to.
     - Throws: `ServerError.fileWriteFailed`, if the data could not be written.
     */
    private func write(data: Data, to url: URL) throws {
        do {
            try data.write(to: url)
        } catch {
            log(error: "Failed to write \(data) to \(url): \(error)")
            throw ServerError.fileWriteFailed
        }
    }
    
    /**
     Read data from a url.
     - Parameter url: The url to read from.
     - Returns: The data at the url.
     - Throws: `ServerError.fileReadFailed`, if the file could not be read.
     */
    private func data(at url: URL) throws -> Data {
        do {
            return try Data(contentsOf: url)
        } catch {
            log(error: "Failed to read data at \(url): \(error)")
            throw ServerError.fileReadFailed
        }
    }
    
    /**
     Delete a file or folder.
     - Parameter url: The url to the file or folder
     - Throws: `ServerError.deletionFailed`, if the file/folder could not be deleted
     */
    private func removeItem(at url: URL) throws {
        guard fm.fileExists(atPath: url.path) else {
            return
        }
        do {
            try fm.removeItem(at: url)
        } catch {
            log(error: "Failed to delete item at: \(url.path)")
            throw ServerError.deletionFailed
        }
    }
    
    
}
