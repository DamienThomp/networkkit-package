//
//  EndpointProtocol.swift
//  NetworkKit
//
//  Created by Damien L Thompson on 2026-09-09.
//

import Foundation

public enum HTTPMethod: String, Sendable {
    case get = "GET"
    case head = "HEAD"
    case post = "POST"
    case put = "PUT"
    case delete = "DELETE"
    case patch = "PATCH"
}

public enum ContentType: String, Sendable {
    case applicationJson = "application/json"
}

public protocol EndpointProtocol: Sendable {
    associatedtype Response: Decodable & Sendable

    var host: APIHost { get }
    var path: String { get }
    var httpMethod: HTTPMethod { get }
    var contentType: ContentType? { get }
    var headers: [String: String]? { get }
    var body: (any Encodable & Sendable)? { get }
    var queryItems: [URLQueryItem]? { get }
    var cachePolicy: URLRequest.CachePolicy { get }
}

public extension EndpointProtocol {
    var host: APIHost { .default }
    var contentType: ContentType? { .applicationJson }
    var headers: [String: String]? { nil }
    var body: (any Encodable & Sendable)? { nil }
    var queryItems: [URLQueryItem]? { nil }
    var cachePolicy: URLRequest.CachePolicy { .useProtocolCachePolicy }
}
