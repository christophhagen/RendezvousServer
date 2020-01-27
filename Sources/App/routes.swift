import Routing
import Vapor
import SwiftProtobuf

/// Register your application's routes here.
///
/// [Learn More →](https://docs.vapor.codes/3.0/getting-started/structure/#routesswift)
public func routes(_ router: Router) throws {
    
    #warning("Add delivery receipts for all messages to devices")
    
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
    
    #warning("Allow admin to delete users")
    
    // MARK: Users
    
    // Register a new user with the given pin
    router.postCatching("user", "register", call: server.registerUser)
    
    // Get the current user info
    router.getCatching("user", "info", call: server.userInfo)
    
    // Allow a user to delete itself
    router.postCatching("user", "delete", call: server.deleteUser)
    
    // MARK: Devices
    
    // Register a new device
    router.postCatching("device", "register", call: server.registerDevice)
    
    // Register a device token for push notifications
    router.postCatching("device", "push", call: server.addPushTokenForDevice)
    
    // Delete a device
    router.postCatching("device", "delete", call: server.deleteDevice)

    // MARK: PreKeys
    
    // Add new device prekeys
    router.postCatching("device", "prekeys", call: server.addDevicePreKeys)
    
    // Get prekeys for each device to create topic keys
    router.getCatching("user", "prekeys", call: server.getDevicePreKeys)
    
    #warning("Allow devices to check which prekeys remain on the server")
    
    // MARK: Topic Keys
    
    #warning("Get topic keys missing a device, and a number of prekeys")
    
    // Add new topic keys
    router.postCatching("user", "topickeys", call: server.addTopicKeys)
    
    // Get a topic key for a single user
    router.getCatching("user", "topickey", call: server.getTopicKey)
    
    // Get a topic key for multiple users
    router.postCatching("users", "topickey", call: server.getTopicKeys)
    
    #warning("Allow devices to check which topic keys remain on the server")
    
    // MARK: Topics
    
    // Create a topic (only internal users)
    router.postCatching("topic", "create", call: server.createTopic)
    
    #warning("Allow topic admins to add/remove/change users")
    
    #warning("Allow topic admins to delete topics")
    
    #warning("Allow any member to leave a topic")
    
    // MARK: Messages
    
    // Add a new message to a topic
    router.postCatching("topic", "message", call: server.addMessage)
    
    #warning("Allow uploads of large files before adding a message")
    
    #warning("Allow upload of multiple messages")
    
    #warning("Get topic messages in a specified range")
    
    // Download new messages for a device
    router.getCatching("device", "messages", call: server.getMessages)
      
}
