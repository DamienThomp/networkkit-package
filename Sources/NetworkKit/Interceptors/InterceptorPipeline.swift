//
//  InterceptorPipeline.swift
//  NetworkKit
//
//  Created by Damien L Thompson on 2026-09-09.
//

import Foundation

public protocol InterceptorPipelineProtocol: Sendable {
    func adapt(_ request: inout URLRequest) async throws
    func didReceive(_ response: HTTPURLResponse, data: Data, for request: URLRequest) async
    func shouldRetry(
        _ request: URLRequest,
        response: HTTPURLResponse?,
        data: Data?,
        attempt: Int,
        maxRetries: Int
    ) async throws -> Bool
}

public final class InterceptorPipeline: InterceptorPipelineProtocol {
    private let interceptors: [RequestInterceptor]

    public init(interceptors: [RequestInterceptor] = []) {
        self.interceptors = interceptors
    }

    public func adapt(_ request: inout URLRequest) async throws {
        for interceptor in interceptors {
            try await interceptor.adapt(&request)
        }
    }

    public func didReceive(_ response: HTTPURLResponse, data: Data, for request: URLRequest) async {
        for interceptor in interceptors {
            await interceptor.didReceive(response, data: data, for: request)
        }
    }

    public func shouldRetry(
        _ request: URLRequest,
        response: HTTPURLResponse?,
        data: Data?,
        attempt: Int,
        maxRetries: Int
    ) async throws -> Bool {
        guard attempt < maxRetries else { return false }

        for interceptor in interceptors {
            let result = try await interceptor.retry(request, response: response, data: data)
            if case .retry = result {
                return true
            }
        }

        return false
    }
}
