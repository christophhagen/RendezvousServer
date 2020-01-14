//
//  Config.swift
//  App
//
//  Created by Christoph on 05.01.20.
//

import Foundation

struct Config: Logger {

    /**
     The id of the private key that was created for the push notifications. Can be found when creating a new key under [developer.apple.com](https://developer.apple.com) -> `Certificates, Identifiers & Profiles` -> `Keys` -> `All`. More information about the setup: [Perfect-Notifications Setup](https://github.com/PerfectlySoft/Perfect-Notifications#obtain-apns-auth-key)
     */
    let keyId: String
    
    /**
     The id of the development team. Can be found under [developer.apple.com](https://developer.apple.com) -> `Account` -> `Membership` -> `Team ID`
     */
    let teamId: String
    
    /**
     The path to the key file for push notifications which has been downloaded from [developer.apple.com](https://developer.apple.com).
     - Note: The path can be relative to the working directory of the project
     */
    let privateKeyPath: URL
    
    /**
     The topic to which the push messages should be sent. This value must match the bundle identifier of the app that is targeted.
     */
    let apnsTopic: String
    
    /**
     The path to the folder where the message data will be stored.
     - note: This can be a path relative to the working directory of the project.
     */
    let baseDirectory: URL
    
    let serverDataPath: URL
    
    let isDevelopmentServer: Bool
    
    let shouldServeStaticFiles: Bool
    
    let logFile: URL?
    
    init(config: [String : Any]) throws {
        
        func load(_ key: String, or error: String) throws -> String {
            guard let value = config[key] as? String else {
                Config.log(error: error)
                throw ConfigError.missingParameter
            }
            return value
        }
        
        let privateKeyPath = try load("pathToPrivateKey", or: "Missing private key path")
        let dataFolder = try load("pathToDataFolder", or: "Missing data folder path")
        let serverDataPath = try load("pathToServerData", or: "Missing server data path")
        
        self.keyId = try load("keyId", or: "Missing key id")
        self.teamId = try load("teamId", or: "Missing team id")
        self.apnsTopic = try load("apnsTopic", or: "Missing APNs topic")
        
        self.privateKeyPath = URL(fileURLWithPath: privateKeyPath)
        self.baseDirectory = URL(fileURLWithPath: dataFolder)
        self.serverDataPath = URL(fileURLWithPath: serverDataPath)
        
        self.isDevelopmentServer = config["isDevelopmentServer"] as? Bool ?? false
        self.shouldServeStaticFiles = config["shouldServeStaticFiles"] as? Bool ?? false
        
        if let path = config["logFilePath"] as? String {
            self.logFile = URL(fileURLWithPath: path)
        } else {
            self.logFile = nil
        }
    }
    
    init(data: Data) throws {
        let dictionary: [String: Any]
        do {
            dictionary = try JSONSerialization.jsonObject(with: data, options: []) as! [String: Any]
        } catch {
            Config.log(error: "Failed to load JSON data from config file: \(error)")
            throw ConfigError.invalidJSON(error)
        }
        try self.init(config: dictionary)
    }
    
    init(at path: String) throws {
        Config.log(debug: "Loading from file: \(path)")
        guard FileManager.default.fileExists(atPath: path) else {
            Config.log(error: "Config file not found at path \(path)")
            throw ConfigError.fileNotFound(path)
        }
        let data: Data // received from a network request, for example
        do {
            let url = URL(fileURLWithPath: path)
            data = try Data(contentsOf: url)
        } catch {
            Config.log(error: "Failed to load data from config file: \(error)")
            throw ConfigError.fileReadFailed(path)
        }
        try self.init(data: data)
    }
}
