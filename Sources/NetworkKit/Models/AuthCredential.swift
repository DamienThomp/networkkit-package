//
//  AuthCredential.swift
//  NetworkKit
//
//  Created by Damien L Thompson on 2026-09-09.
//

import Foundation

public enum AuthCredential: Sendable, Equatable {
    case bearer(String)
    case token(scheme: String, token: String)
    case header(field: String, value: String)

    public var httpHeader: (field: String, value: String) {
        switch self {
        case .bearer(let token):
            return ("Authorization", "Bearer \(token)")
        case .token(let scheme, let token):
            return ("Authorization", "\(scheme) token=\(token)")
        case .header(let field, let value):
            return (field, value)
        }
    }
}
