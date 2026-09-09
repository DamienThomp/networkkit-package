//
//  APIHost.swift
//  NetworkKit
//
//  Created by Damien L Thompson on 2026-09-09.
//

import Foundation

public struct APIHost: Hashable, Sendable, ExpressibleByStringLiteral, RawRepresentable {

    public let rawValue: String

    public init(rawValue: String) {
        self.rawValue = rawValue
    }

    public init(stringLiteral value: String) {
        self.rawValue = value
    }

    /// Default host fallback if an app only uses a single base URL.
    public static let `default`: APIHost = "default"
}
