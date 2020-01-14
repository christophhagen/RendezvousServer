import Vapor

/// The path to the server configuration
let configPath = "/Users/user/Development/Rendezvous/config.json"

/// The global server instance
var server: Server!

/// Called before your application initializes.
///
/// [Learn More →](https://docs.vapor.codes/3.0/getting-started/structure/#configureswift)
public func configure(
    _ config: inout Vapor.Config,
    _ env: inout Environment,
    _ services: inout Services
) throws {
    // Load the server configuration and create the server
    let config = try Config(at: configPath)
    server = try Server(config: config)
    
    // Register routes to the router
    let router = EngineRouter.default()
    try routes(router)
    services.register(router, as: Router.self)

}
