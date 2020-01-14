import Routing
import Vapor
import SwiftProtobuf

/// Register your application's routes here.
///
/// [Learn More →](https://docs.vapor.codes/3.0/getting-started/structure/#routesswift)
public func routes(_ router: Router) throws {
    
    // MARK: Info
    
    router.get("ping") { _ in
        return HTTPResponse(status: .ok)
    }
    
    // MARK: Admin
    
    // Update the auth token of the server admin
    router.getCatching("admin", "renew", call: server.updateAdminAuthToken)
    
    if server.isDevelopmentServer {
        // Reset the server
        router.getCatching("admin", "reset", call: server.deleteAllServerData)
    }
    
    // Allow registration of a new user
    router.postCatching("user", "allow", call: server.allowUser)
    
    // MARK: Users
    
    // Register a new user with the given pin
    router.postCatching("user", "register", call: server.registerUser)
    
    // Register a user with a device, prekeys, and topic keys.
    router.postCatching("user", "full", call: server.registerUserWithDeviceAndKeys)
    
    // Get the current user info
    router.getCatching("user", "info", call: server.userInfo)
    
    // Allow a user to delete itself
    router.postCatching("user", "delete", call: server.deleteUser)
    
    // MARK: Devices
    
    // Register a new device
    router.postCatching("device", "register", call: server.registerDevice)
    
    // Delete a device
    router.postCatching("device", "delete", call: server.deleteDevice)
    
    // MARK: PreKeys
    
    // Add new device prekeys
    router.postCatching("device", "prekeys", call: server.addDevicePreKeys)
    
    // Get prekeys for each device to create topic keys
    router.getCatching("user", "prekeys", call: server.getDevicePreKeys)
    
    // MARK: Topic Keys
    
    // Add new topic keys
    router.postCatching("user", "topickeys", call: server.addTopicKeys)
    
    // Get a topic key
    router.getCatching("user", "topickey", call: server.getTopicKey)
    
    // MARK: Topics
    
    // Create a topic (only internal users)
    router.postCatching("topic", "create", call: server.createTopic)
}

extension Router {
    
    func getCatching<T>(_ path: PathComponentsRepresentable..., call: @escaping (Request) throws -> T) {
        self.get(path) { (request: Request) -> HTTPResponse in
            catching(path, request: request, closure: call)
        }
    }
    
    func postCatching<T>(_ path: PathComponentsRepresentable..., call: @escaping (Request) throws -> T) {
        self.post(path) { (request: Request) -> HTTPResponse in
            catching(path, request: request, closure: call)
        }
    }
}

private func catching<T>(_ path: PathComponentsRepresentable..., request: Request, closure: @escaping (Request) throws -> T) -> HTTPResponse {
    
    let route = path.convertToPathComponents().map { $0.string }.joined(separator: "/")
    Server.log(debug: "Request to \(route)")
    do {
        let data = try closure(request)
        if let d = data as? Data {
            return HTTPResponse(status: .ok, body: d)
        } else {
            return HTTPResponse(status: .ok)
        }
    } catch let error as RendezvousError {
        Server.log(debug: "\(route): Client error \(error)")
        return HTTPResponse(status: error.response)
    } catch let error as BinaryEncodingError{
        Server.log(debug: "\(route): Protobuf error \(error)")
        return HTTPResponse(status: .internalServerError)
    } catch {
        Server.log(debug: "\(route): Unhandled error \(error)")
        return HTTPResponse(status: .internalServerError)
    }
}

extension PathComponent {
    
    var string: String {
        switch self {
        case .constant(let value):
            return value
        case .parameter(let value):
            return "<\(value)>"
        default:
            return "\(self)"
        }
    }
}
