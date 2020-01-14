//
//  Storage.swift
//  App
//
//  Created by Christoph on 05.01.20.
//

import Foundation

/**
 
 Folder structure:
 ```
 base/
    users/
        userIdentityKey/
            prekeys/
                deviceIdentityKey // The prekeys of a device
            messages/
                deviceIdentityKey // The topic messages for a device
            topickeys // The available topic keys of a user
    topicdata/
        topicID/
            messageIV
    topics/
        topicID/
            chain0
            chain1000
 ```
 */

private extension Data {
    
    var fileId: String {
        return base32EncodedString()
    }
}

final class Storage: Logger {
    
    /// The file manager
    let fm = FileManager.default
    
    /// The root directory for the server data.
    let base: URL
    
    /// The number of chain links to store in a single file
    static let chainPartCount: UInt32 = 1000
    
    // MARK: Initialization
    
    /**
     Initialize the storage interface.
     - Parameter baseURL: The root directory for the server data.
     */
    init(baseURL: URL) {
        self.base = baseURL
        
        createBaseDirectory()
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
            fatalError("Failed to write to server directory \(url.path): \(error)")
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
    
    private func createBaseDirectory() {
        guard !dataExists(at: base) else {
            return
        }
        do {
            try createFolder(at: base)
        } catch {
            fatalError("Failed to create server directory: \(error)")
        }
    }
    
    private func deleteBaseDirectory() throws {
        guard dataExists(at: base) else {
            return
        }
        do {
            try removeItem(at: base)
        } catch {
            throw ServerError.deletionFailed
        }
    }
    
    func deleteAllData() throws {
        try deleteBaseDirectory()
        createBaseDirectory()
    }
    
    // MARK: URLs
    
    /// A url to a test file in the base directory
    var testURL: URL {
        base.appendingPathComponent("permissions")
    }
    
    /// The directory where the user data is stored
    private var usersDirectory: URL {
        base.appendingPathComponent("users")
    }
    
    /**
     The url to the folder of a user.
     - Parameter user: The base32 encoded public key of the user.
     - Returns: The url of the user folder.
     */
    private func userURL(_ user: Data) -> URL {
        usersDirectory.appendingPathComponent(user.fileId)
    }
    
    /**
     The url containing available topic keys of the user.
     - Parameter user: The base32 encoded public key of the user.
     - Returns: The url of the file containing the topic keys.
     */
    private func userTopicKeyURL(_ user: Data) -> URL {
        userURL(user).appendingPathComponent("topickeys")
    }
    
    private func userPreKeyURL(_ user: Data) -> URL {
        userURL(user).appendingPathComponent("prekeys")
    }
    
    /**
     The url containing the device pre keys of a user.
     - Parameter user: The public key of the user.
     - Parameter device: The public key of a device.
     - Returns: The url to the prekey file.
     */
    private func devicePreKeyURL(_ device: Data, of user: Data) -> URL {
        return userPreKeyURL(user).appendingPathComponent(device.fileId)
    }
    
    /**
     Get the url where topic messages are stored.
     */
    private func topicDataURL(_ topic: Data) -> URL {
        base.appendingPathComponent("topicdata").appendingPathComponent(topic.fileId)
    }
    
    /**
     Get the storage url for a message in a topic.
     */
    private func topicDataURL(_ topic: Data, message: Data) -> URL {
        topicDataURL(topic).appendingPathComponent(message.fileId)
    }
    
    /**
    Get the url where topic chains are stored.
    */
    private func topicURL(_ topic: Data) -> URL {
        base.appendingPathComponent("topics").appendingPathComponent(topic.fileId)
    }
    
    /**
     Get the storage url for a topic chain.
     */
    private func topicURL(_ topic: Data, chainIndex: UInt32) -> URL {
        // Rounds the parts to multiples of the chain part count
        let chain = (chainIndex / Storage.chainPartCount) * Storage.chainPartCount
        let file = String(format: "%10d", chain)
        return topicURL(topic).appendingPathComponent(file)
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
    func create(user: Data) throws {
        let url = userURL(user)
        // Remove any existing directory or file
        try removeItem(at: url)
        // Create the user folder
        try createFolder(at: url)
        // Create the prekey and messages folders
        try createFolder(at: userPreKeyURL(user))
    }
    
    /**
     Remove a user folder, and thus all data from the user.
     - Parameter user: The user whose data to delete.
     - Throws: `ServerError.deletionFailed`, if the file/folder could not be deleted
     */
    func deleteData(forUser user: Data) throws {
        let url = userURL(user)
        try removeItem(at: url)
    }
    
    // MARK: PreKeys
    
    /**
     Store new prekeys for the device of a user.
     
     - Parameter preKeys: The prekeys to store.
     - Parameter device: The public key of the device.
     - Parameter user: The public key of the user.
     - Returns: The prekeys available for the device.
     - Throws: `ServerError` errors
     
     - Note: Possible errors:
     - `BinaryEncodingError`, if the prekey serialization fails, or if the existing data is not a valid protobuf.
     - `ServerError.fileWriteFailed`, if the prekey data could not be written.
     - `ServerError.fileReadFailed`, if the file could not be read.
     */
    func store(preKeys: [RV_DevicePrekey], for device: Data, of user: Data) throws -> UInt32 {
        let url = devicePreKeyURL(device, of: user)
        guard dataExists(at: url) else {
            // No keys exist, simply write new keys
            try write(preKeys: preKeys, to: url)
            return UInt32(preKeys.count)
        }
        let oldKeys = try getPrekeys(at: url)
        try write(preKeys: oldKeys + preKeys, to: url)
        return UInt32(oldKeys.count + preKeys.count)
    }
    
    /**
     Write prekeys to a url.
     
     - Parameter preKeys: The prekeys to store.
     - Parameter url: The url to write the prekeys to.
     - Throws: `ServerError` errors
     - Note: Possible errors:
     - `BinaryEncodingError`, if the serialization fails.
     - `ServerError.fileWriteFailed`, if the data could not be written.
     */
    private func write(preKeys: [RV_DevicePrekey], to url: URL) throws {
        let object = RV_DevicePreKeyList.with {
            $0.remainingKeys = UInt32(preKeys.count)
            $0.prekeys = preKeys
        }
        let data = try object.serializedData()
        try write(data: data, to: url)
    }
    
    /**
     Get a number of prekeys for all devices of a user.
     
     - Parameter count: The maximum number of prekeys to collect.
     - Parameter devices: The public keys for all devices of the user.
     - Parameter user: The public key of the user.
     - Returns: The bundle with up to `count` prekeys per device.
     - Throws: `ServerError`, `BinaryEncodingError`
     - Note: Possible errors:
        - `BinaryEncodingError`, if the prekey data for a device is not a valid protobuf, or if the prekey serialization fails.
        - `ServerError.fileReadFailed`, if the prekey file for a device could not be read.
        - `ServerError.fileWriteFailed`, if the prekey data for a device could not be written.
        - `ServerError.deletionFailed`, if the prekey data for a device could not be deleted.
     */
    func get(preKeys count: Int, for devices: [Data], of user: Data) throws -> RV_DevicePreKeyBundle {
        
        // Get all keys for each device.
        var preKeys = [Data : [RV_DevicePrekey]]()
        for device in devices {
            let url = devicePreKeyURL(device, of: user)
            guard dataExists(at: url) else {
                preKeys[device] = []
                continue
            }
            preKeys[device] = try getPrekeys(at: url)
        }
        
        // Find the maximum amount of prekeys
        let availableCount = preKeys.values.reduce(count) { min($0, $1.count) }
        
        // Add `availableCount` prekeys for each device
        return try .with { bundle in
            bundle.keyCount = UInt32(availableCount)
            bundle.devices = try preKeys.map { (device, keys) in
                try RV_DevicePreKeyList.with { list in
                    list.deviceKey = device
                    list.remainingKeys = UInt32(keys.count - availableCount)
                    list.prekeys = Array(keys[0..<availableCount])
                    
                    // Write the remaining keys back to disk
                    let url = devicePreKeyURL(device, of: user)
                    if keys.count > availableCount {
                        try write(preKeys: Array(keys.dropFirst(availableCount)), to: url)
                    } else {
                        try removeItem(at: url)
                    }
                }
            }
        }
    }
    
    /**
     Get the prekeys stored at a url.
     
     - Parameter url: The url where the prekeys are stored.
     - Returns: The list of prekeys.
     - Throws: `ServerError`, `BinaryEncodingError`
     - Note: Possible errors:
        - `ServerError.fileReadFailed`, if the file could not be read.
        - `BinaryEncodingError`, if the data is not a valid protobuf.
     */
    private func getPrekeys(at url: URL) throws -> [RV_DevicePrekey] {
        let data = try self.data(at: url)
        return try RV_DevicePreKeyList(serializedData: data).prekeys
    }
    
    // MARK: Topic keys
    
    /**
     Store new topic keys for a user.
     
     - Parameter topicKeys: The topic keys to store.
     - Parameter user: The public key of the user.
     - Returns: The topic keys available for the user.
     - Throws: `ServerError`, `BinaryEncodingError`
     
     - Note: Possible errors:
        - `BinaryEncodingError`, if the topic keys serialization fails, or if the existing data is not a valid protobuf.
        - `ServerError.fileWriteFailed`, if the topic keys data could not be written.
        - `ServerError.fileReadFailed`, if the file could not be read.
     */
    func store(topicKeys: [RV_TopicKey], for user: Data) throws -> UInt32 {
        let url = userTopicKeyURL(user)
        guard dataExists(at: url) else {
            // No previous keys exist
            try write(topicKeys: topicKeys, to: url)
            return UInt32(topicKeys.count)
        }
        let oldKeys = try getTopicKeys(at: url)
        try write(topicKeys: oldKeys + topicKeys, to: url)
        return UInt32(topicKeys.count + oldKeys.count)
    }
    
    /**
     Get a topic key for a user.
     
     - Parameter user: The user for which to get the topic key.
     - Returns: The topic key.
     - Throws: `RendezvousError`, `ServerError`, `BinaryEncodingError`
     
     - Note: Possible errors:
        - `RendezvousError.resourceNotAvailable`, if no topic key exists.
        - `ServerError.fileWriteFailed`, if the data could not be written.
        - `ServerError.deletionFailed`, if the file/folder could not be deleted
        - `ServerError.fileReadFailed`, if the file could not be read.
        - `BinaryEncodingError`, if the data is not a valid protobuf, or if the serialization fails.
     */
    func getTopicKey(of user: Data) throws -> RV_TopicKey {
        let url = userTopicKeyURL(user)
        guard dataExists(at: url) else {
            // No keys exist
            throw RendezvousError.resourceNotAvailable
        }
        var oldKeys = try getTopicKeys(at: url)
        guard let key = oldKeys.popLast() else {
            // No keys exist
            try removeItem(at: url)
            throw RendezvousError.resourceNotAvailable
        }
        try write(topicKeys: oldKeys, to: url)
        return key
    }
    
    /**
     Write topic keys to a url.
     
     - Parameter topicKeys: The  topic keys to store.
     - Parameter url: The url to write the topic keys to.
     - Throws: `ServerError` errors
     - Note: Possible errors:
     - `BinaryEncodingError`, if the serialization fails.
     - `ServerError.fileWriteFailed`, if the data could not be written.
     */
    private func write(topicKeys: [RV_TopicKey], to url: URL) throws {
        let object = RV_TopicKeyList.with {
            $0.keys = topicKeys
        }
        let data = try object.serializedData()
        try write(data: data, to: url)
    }
    
    /**
     Get the topic keys stored at a url.
     
     - Parameter url: The url where the topic keys are stored.
     - Returns: The list of topic keys.
     - Throws: `ServerError` errors
     - Note: Possible errors:
     - `ServerError.fileReadFailed`, if the file could not be read.
     - `BinaryEncodingError`, if the data is not a valid protobuf.
     */
    private func getTopicKeys(at url: URL) throws -> [RV_TopicKey] {
        let data = try self.data(at: url)
        return try RV_TopicKeyList(serializedData: data).keys
    }
    
    // MARK: Topic data
    
    /**
     Create the folders for a new topic.
     - Parameter topic: The topic id.
     - Throws: `RendezvousError`, `ServerError`
     - Note: Possible errors:
        - `RendezvousError.resourceAlreadyExists`, if the topic already exists
        - `ServerError.folderCreationFailed`, if the folder couldn’t be created.
     */
    func create(topic: Data) throws {
        let dataURL = topicDataURL(topic)
        let url = topicURL(topic)
        guard !dataExists(at: url), !dataExists(at: dataURL) else {
            throw RendezvousError.resourceAlreadyExists
        }
        try createFolder(at: url)
        try createFolder(at: dataURL)
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
            try fm.createDirectory(at: url, withIntermediateDirectories: true)
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
