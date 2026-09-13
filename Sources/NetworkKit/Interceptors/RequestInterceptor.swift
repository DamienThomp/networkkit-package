//
//  RequestInterceptor.swift
//  NetworkKit
//
//  Created by Damien L Thompson on 2026-09-09.
//

import Foundation

public enum RetryResult: Sendable {
    case retry
    case doNotRetry
}

public protocol RequestInterceptor: Sendable {
    func adapt(_ request: inout URLRequest) async throws
    func retry(_ request: URLRequest, response: HTTPURLResponse?, data: Data?) async throws -> RetryResult
    func didReceive(_ response: HTTPURLResponse, data: Data, for request: URLRequest) async
}

public extension RequestInterceptor {
    func didReceive(_ response: HTTPURLResponse, data: Data, for request: URLRequest) async {}

    func retry(_ request: URLRequest, response: HTTPURLResponse?, data: Data?) async throws -> RetryResult {
        return .doNotRetry
    }
}
