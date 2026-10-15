import Foundation

/// Hops to the main actor. Order is not guaranteed between calls, so don't use it
/// for ordered streams (terminal output has its own ordered pipeline).
func onMain(_ block: @escaping @MainActor () -> Void) {
    Task { @MainActor in block() }
}

/// Turns the many error shapes NIO/Citadel throw into something a person can act on.
func describeConnectionError(_ error: Error) -> String {
    if let localized = error as? LocalizedError, let description = localized.errorDescription {
        return description
    }
    let text = String(describing: error)
    let lower = text.lowercased()
    if lower.contains("userauth") || lower.contains("authentication") || lower.contains("auth") && lower.contains("fail") {
        return "Authentication failed. Check the username, password or key.\n\(text)"
    }
    if lower.contains("timeout") || lower.contains("timedout") {
        return "The connection timed out. Check the address, port and your network.\n\(text)"
    }
    if lower.contains("refused") {
        return "Connection refused. Is the SSH server running on that port?\n\(text)"
    }
    if lower.contains("nodename") || lower.contains("resolve") || lower.contains("unknown host") {
        return "Couldn't resolve that host name.\n\(text)"
    }
    return text
}
