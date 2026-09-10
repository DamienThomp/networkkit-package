//
//  NetworkLogging.swift
//  NetworkKit
//
//  Created by Damien L Thompson on 2026-09-10.
//

import Foundation
import os

public protocol NetworkLogging: Sendable {
    func log(_ message: @autoclosure () -> String)
}

public struct NoOpNetworkLogger: NetworkLogging {
    public init() {}

    public func log(_ message: @autoclosure () -> String) {}
}

public struct DebugNetworkLogger: NetworkLogging {
    private let logger: Logger

    public init(subsystem: String = "NetworkKit", category: String = "Network") {
        logger = Logger(subsystem: subsystem, category: category)
    }

    public func log(_ message: @autoclosure () -> String) {
        let text = message()
        logger.debug("\(text, privacy: .public)")
    }
}
