//
//  AuthInterceptor.swift
//  NetworkKit
//
//  Created by Damien L Thompson on 2026-09-09.
//

import Foundation

public protocol AuthManagerProtocol: Sendable {
    var accessToken: String? { get async }
    func refreshAccessToken() async throws
}

public actor AuthInterceptor: RequestInterceptor {

    private let authManager: AuthManagerProtocol
    private var refreshTask: Task<Void, Error>?

    public init(authManager: AuthManagerProtocol) {
        self.authManager = authManager
    }

    public func adapt(_ request: inout URLRequest) async throws {
        if let token = await authManager.accessToken {
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }
    }

    public func retry(_ request: URLRequest, response: HTTPURLResponse?, data: Data?) async throws -> RetryResult {
        guard let response, response.statusCode == 401 else {
            return .doNotRetry
        }

        do {
            try await refreshToken()
            return .retry
        } catch {
            throw NetworkError.unauthorized
        }
    }

    private func refreshToken() async throws {
        if let existingTask = refreshTask {
            try await existingTask.value
            return
        }

        let task = Task {
            defer { refreshTask = nil }
            try await authManager.refreshAccessToken()
        }

        refreshTask = task
        try await task.value
    }
}
