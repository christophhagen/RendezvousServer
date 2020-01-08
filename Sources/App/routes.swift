import Routing
import Vapor


/// Register your application's routes here.
///
/// [Learn More →](https://docs.vapor.codes/3.0/getting-started/structure/#routesswift)
public func routes(_ router: Router) throws {
    
    // MARK: - Admin functions
    
    // Allow registration of a new user
    router.post("user", "allow") { req in
        catchAndReturn {
            
        }
    }
}

private func catchAndReturn(_ block: () throws -> ()) -> HTTPResponse {
    do {
        try block()
        return HTTPResponse(status: .ok)
    } catch let error {
        Log.log(error: "Unknown error \(error).")
        return HTTPResponse(status: .internalServerError)
    }
}

private func catchAndReturn(_ block: () throws -> Data) -> HTTPResponse {
    do {
        let data = try block()
        return HTTPResponse(status: .ok, body: data)
    } catch let error {
        Log.log(error: "Unknown error \(error).")
        return HTTPResponse(status: .internalServerError)
    }
}
