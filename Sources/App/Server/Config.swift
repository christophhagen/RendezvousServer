//
//  Config.swift
//  App
//
//  Created by Christoph on 05.01.20.
//

import Foundation

/**
 A configuration for a Rendezvous server.
 */
struct Config: Logger {

    /// The server to use for push notifications
    let notificationServer: URL
    
    /// The path to the folder where the server data will be stored.
    let baseDirectory: URL
    
    /// Indicate if this server is used for development, i.e. if server resets are allowed by the admin
    let isDevelopmentServer: Bool
    
    /// Indicate if the server should also serve static files (can be handled by external programs such as Nginx)
    let shouldServeStaticFiles: Bool
    
    /// The path to the log file
    let logFile: URL?
    
    /**
     Create a configuration from a JSON dictionary.
     - Parameter config: The JSON dictionary.
     - Throws: `ConfigError.missingParameter`, if the config is missing options.
     */
    init(config: [String : Any]) throws {

        // Get the server data folder
        guard let dataFolder = config["dataFolder"] as? String else {
            Config.log(error: "Missing data folder path")
            throw ConfigError.missingParameter
        }
        self.baseDirectory = URL(fileURLWithPath: dataFolder)
        
        // Get the default notification server
        guard let notificationServerPath = config["notificationServer"] as? String, let notificationServer = URL(string: notificationServerPath) else {
            Config.log(error: "Missing notification server")
            throw ConfigError.missingParameter
        }
        self.notificationServer = notificationServer
        
        // Set the log file, if specified
        if let path = config["logFile"] as? String {
            self.logFile = URL(fileURLWithPath: path)
        } else {
            self.logFile = nil
        }
        
        // Set flags
        self.isDevelopmentServer = config["development"] as? Bool ?? false
        self.shouldServeStaticFiles = config["staticFiles"] as? Bool ?? false
    }
    
    /**
     Create a configuration from file data.
     
     - Parameter data: The file data read from disk.
     - Throws: `ConfigError`
     
     - Note: Possible errors:
        - `ConfigError.invalidJSON(_)`, if the configuration data is not valid JSON data.
        - `ConfigError.missingParameter`, if the config is missing options.
     */
    init(data: Data) throws {
        
        // Try to create the JSON dictionary
        let dictionary: [String: Any]
        do {
            dictionary = try JSONSerialization.jsonObject(with: data, options: []) as! [String: Any]
        } catch {
            Config.log(error: "Failed to load JSON data from config file: \(error)")
            throw ConfigError.invalidJSON(error)
        }
        
        // Load the values from JSON
        try self.init(config: dictionary)
    }
    
    /**
     Create a configuration from a file.
     
     - Parameter path: The path to the configuration file.
     - Throws: `ConfigError`
     
     - Note: Possible errors:
        - `ConfigError.fileNotFound(_)`, if the path contains no file.
        - ` ConfigError.fileReadFailed(_)`, if the file could not be read.
        - `ConfigError.invalidJSON(_)`, if the configuration data is not valid JSON data.
        - `ConfigError.missingParameter`, if the config is missing options.
    */
    init(at path: String) throws {
        Config.log(debug: "Loading from file: \(path)")
        
        // Verify that the file exists
        guard FileManager.default.fileExists(atPath: path) else {
            Config.log(error: "Config file not found at path \(path)")
            throw ConfigError.fileNotFound(path)
        }
        
        // Read the file data
        let data: Data
        do {
            let url = URL(fileURLWithPath: path)
            data = try Data(contentsOf: url)
        } catch {
            Config.log(error: "Failed to load data from config file: \(error)")
            throw ConfigError.fileReadFailed(path)
        }
        
        // Load the JSON
        try self.init(data: data)
    }
}
