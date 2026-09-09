//
//  NetworkManagerFactory.swift
//  NetworkKit
//
//  Created by Damien L Thompson on 2026-09-09.
//

import Foundation

public enum NetworkManagerFactory {
    public static func makeDefaultClient(
        hostResolver: @escaping @Sendable (APIHost) -> URL,
        authManager: AuthManagerProtocol? = nil,
        customInterceptors: [RequestInterceptor] = [],
        session: URLSession = .shared,
        encoder: JSONEncoder = JSONEncoder(),
        decoder: JSONDecoder = JSONDecoder()
    ) -> NetworkManagerProtocol {

        var interceptors: [RequestInterceptor] = []

        if let authManager {
            interceptors.append(AuthInterceptor(authManager: authManager))
        }

        interceptors.append(contentsOf: customInterceptors)

        return NetworkManager(
            hostResolver: hostResolver,
            session: session,
            pipeline: InterceptorPipeline(interceptors: interceptors),
            encoder: encoder,
            decoder: decoder
        )
    }
}
