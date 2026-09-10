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

public struct ContentType: Hashable, Sendable, ExpressibleByStringLiteral, RawRepresentable {
    public let rawValue: String

    public init(rawValue: String) {
        self.rawValue = rawValue
    }

    public init(stringLiteral value: String) {
        self.rawValue = value
    }

    public static let json: ContentType = "application/json"
    public static let protobuf: ContentType = "application/x-protobuf"
    public static let octetStream: ContentType = "application/octet-stream"
    public static let formURLEncoded: ContentType = "application/x-www-form-urlencoded"
}

public protocol EndpointProtocol: Sendable {
    associatedtype Response: Decodable & Sendable

    var host: APIHost { get }
    var path: String { get }
    var httpMethod: HTTPMethod { get }
    var contentType: ContentType? { get }
    var headers: [String: String]? { get }
    var rawBody: Data? { get }
    var body: (any Encodable & Sendable)? { get }
    var queryItems: [URLQueryItem]? { get }
    var cachePolicy: URLRequest.CachePolicy { get }
}

public extension EndpointProtocol {
    var host: APIHost { .default }
    var contentType: ContentType? { .json }
    var headers: [String: String]? { nil }
    var rawBody: Data? { nil }
    var body: (any Encodable & Sendable)? { nil }
    var queryItems: [URLQueryItem]? { nil }
    var cachePolicy: URLRequest.CachePolicy { .useProtocolCachePolicy }
}
