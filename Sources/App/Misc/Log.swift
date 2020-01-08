//
//  Log.swift
//  App
//
//  Created by Christoph on 05.01.20.
//

import Foundation

private let timeFormatter: DateFormatter = {
    let df = DateFormatter()
    df.dateFormat = "dd.MM. HH:mm"
    return df
}()


enum LogLevel: Int {
    case debug = 1
    case info = 2
    case warnings = 3
    case errors = 4
    case none = 5
}

protocol Logger {
    
}

extension Logger {
    
    static var logLevel: LogLevel {
        return Log.logLevels[name] ?? Log.logLevel
    }
    
    static func set(logLevel: LogLevel?) {
        Log.logLevels[name] = logLevel
    }
    
    private static func log(level: String, message: String) {
        Log.log(message: "[\(timeFormatter.string(from: Date()))][\(level)][\(String(describing: self))] \(message)")
    }
    
    private static var name: String {
        return String(describing: self)
    }
    
    private var name: String {
        let thisType = type(of: self)
        return String(describing: thisType)
    }
    
    // MARK: - Class logging
    
    static func log(debug message: String) {
        guard logLevel.rawValue <= LogLevel.debug.rawValue else { return }
        log(level: "DEBUG", message: message)
    }
    
    static func log(info message: String) {
        guard logLevel.rawValue <= LogLevel.info.rawValue else { return }
        log(level: "INFO ", message: message)
    }
    
    static func log(warning message: String) {
        guard logLevel.rawValue <= LogLevel.warnings.rawValue else { return }
        log(level: "WARN ", message: message)
    }
    
    static func log(error message: String) {
        guard logLevel.rawValue <= LogLevel.errors.rawValue else { return }
        log(level: "ERROR", message: message)
    }
    
    // MARK: - Instance logging
    
    func log(debug message: String) {
        Self.log(debug: message)
    }
    
    func log(info message: String) {
        Self.log(info: message)
    }
    
    func log(warning message: String) {
        Self.log(warning: message)
    }
    
    func log(error message: String) {
        Self.log(error: message)
    }
    
}

struct Log: Logger {
    
    static var logLevel: LogLevel = .debug
    
    fileprivate static var logLevels = [String: LogLevel]()
    
    private static var file: FileHandle?
    
    static func set(logFile: URL) -> Bool {
        if let f = file {
            f.closeFile()
        }
        if !FileManager.default.fileExists(atPath: logFile.path) {
            do {
                try "".write(to: logFile, atomically: true, encoding: .utf8)
            } catch {
                print("Failed to create log file \(logFile.path): \(error)")
                return false
            }
        }
        do {
            file = try FileHandle(forWritingTo: logFile)
        } catch {
            print("Failed to open log file \(logFile.path): \(error)")
            file = nil
        }
        return file != nil
    }
    
    fileprivate static func log(message: String) {
        if let f = file {
            f.write((message + "\n").data(using: .utf8)!)
            f.synchronizeFile()
        } else {
            print(message)
        }
    }
}

extension String {
    
    var logId: SubSequence {
        return prefix(5)
    }
}

extension Data {
    
    var logId: String.SubSequence {
        return hexEncodedString().prefix(5)
    }
}
