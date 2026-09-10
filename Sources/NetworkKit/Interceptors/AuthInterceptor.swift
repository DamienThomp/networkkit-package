//
//  AuthInterceptor.swift
//  NetworkKit
//
//  Created by Damien L Thompson on 2026-09-09.
//

import Foundation

public protocol AuthManagerProtocol: Sendable {
    var credential: AuthCredential? { get async }
    func refreshCredentials() async throws
    func shouldRefresh(for response: HTTPURLResponse) -> Bool
}

public extension AuthManagerProtocol {
    func shouldRefresh(for response: HTTPURLResponse) -> Bool {
        response.statusCode == 401
    }
}

public actor AuthInterceptor: RequestInterceptor {

    private let authManager: AuthManagerProtocol
    private var refreshTask: Task<Void, Error>?

    public init(authManager: AuthManagerProtocol) {
        self.authManager = authManager
    }

    public func adapt(_ request: inout URLRequest) async throws {
        if let credential = await authManager.credential {
            let header = credential.httpHeader
            request.setValue(header.value, forHTTPHeaderField: header.field)
        }
    }

    public func retry(_ request: URLRequest, response: HTTPURLResponse?, data: Data?) async throws -> RetryResult {
        guard let response, authManager.shouldRefresh(for: response) else {
            return .doNotRetry
        }

        do {
            try await refreshCredentials()
            return .retry
        } catch {
            throw NetworkError.unauthorized
        }
    }

    private func refreshCredentials() async throws {
        if let existingTask = refreshTask {
            try await existingTask.value
            return
        }

        let task = Task {
            defer { refreshTask = nil }
            try await authManager.refreshCredentials()
        }

        refreshTask = task
        try await task.value
    }
}
