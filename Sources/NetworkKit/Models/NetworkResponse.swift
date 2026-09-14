//
//  NetworkResponse.swift
//  NetworkKit
//
//  Created by Damien L Thompson on 2026-09-13.
//

import Foundation

public struct NetworkResponse<Value: Sendable>: Sendable {
    public let value: Value
    public let statusCode: Int
    public let headers: [String: String]
    public let url: URL?

    public init(value: Value, statusCode: Int, headers: [String: String], url: URL?) {
        self.value = value
        self.statusCode = statusCode
        self.headers = headers
        self.url = url
    }

    /// Returns the first header value for `name`, compared case-insensitively per HTTP.
    public func header(named name: String) -> String? {
        headers.first { $0.key.caseInsensitiveCompare(name) == .orderedSame }?.value
    }
}
