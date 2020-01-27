//
//  Router+Extensions.swift
//  App
//
//  Created by Christoph on 26.01.20.
//

import SwiftProtobuf
import Vapor

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
    } catch let error as BinaryEncodingError {
        Server.log(debug: "\(route): Protobuf error \(error)")
        return HTTPResponse(status: .internalServerError)
    } catch let error as BinaryDecodingError {
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
