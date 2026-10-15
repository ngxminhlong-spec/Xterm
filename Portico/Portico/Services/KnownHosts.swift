import Foundation
import NIOCore
import NIOSSH

/// Persistent trust-on-first-use host key store (like ~/.ssh/known_hosts).
/// Thread-safe: the NIO event loop reads it while the UI edits it.
final class KnownHosts: @unchecked Sendable {
    static let shared = KnownHosts()

    struct Entry: Codable, Identifiable, Hashable {
        var id: String { hostID }
        var hostID: String          // "hostname:port"
        var publicKey: String       // OpenSSH one-line public key
        var fingerprint: String
        var added: Date
    }

    private let lock = NSLock()
    private var entries: [String: Entry] = [:]
    private let fileURL: URL

    private init() {
        let dir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        fileURL = dir.appendingPathComponent("known_hosts.json")
        if let data = try? Data(contentsOf: fileURL),
           let list = try? JSONDecoder().decode([Entry].self, from: data) {
            for entry in list { entries[entry.hostID] = entry }
        }
    }

    static func hostID(host: String, port: Int) -> String {
        "\(host.lowercased()):\(port)"
    }

    func entry(for hostID: String) -> Entry? {
        lock.lock(); defer { lock.unlock() }
        return entries[hostID]
    }

    func all() -> [Entry] {
        lock.lock(); defer { lock.unlock() }
        return entries.values.sorted { $0.hostID < $1.hostID }
    }

    func trust(hostID: String, publicKey: String) {
        let entry = Entry(
            hostID: hostID,
            publicKey: publicKey,
            fingerprint: SSHKeyTools.fingerprint(publicLine: publicKey) ?? "unknown",
            added: Date()
        )
        lock.lock()
        entries[hostID] = entry
        lock.unlock()
        save()
    }

    func remove(hostID: String) {
        lock.lock()
        entries.removeValue(forKey: hostID)
        lock.unlock()
        save()
    }

    private func save() {
        lock.lock()
        let list = Array(entries.values)
        lock.unlock()
        if let data = try? JSONEncoder().encode(list) {
            try? data.write(to: fileURL, options: .atomic)
        }
    }
}

enum HostKeyProblem: LocalizedError {
    case changed(host: String, expected: String, received: String)

    var errorDescription: String? {
        switch self {
        case .changed(let host, let expected, let received):
            return """
            WARNING: the host key for \(host) has CHANGED.

            Expected: \(expected)
            Received: \(received)

            This can mean the server was reinstalled, or that someone is intercepting the connection. \
            If you trust the change, remove the old key under Settings → Known Hosts and connect again.
            """
        }
    }
}

/// Trust-on-first-use validator: unknown hosts are remembered, known hosts must match.
final class TOFUHostKeyDelegate: NIOSSHClientServerAuthenticationDelegate, @unchecked Sendable {
    private let hostID: String
    private let lock = NSLock()
    private var _problem: HostKeyProblem?
    private var _fingerprint: String?

    init(host: String, port: Int) {
        self.hostID = KnownHosts.hostID(host: host, port: port)
    }

    var problem: HostKeyProblem? {
        lock.lock(); defer { lock.unlock() }
        return _problem
    }

    var seenFingerprint: String? {
        lock.lock(); defer { lock.unlock() }
        return _fingerprint
    }

    func validateHostKey(hostKey: NIOSSHPublicKey, validationCompletePromise: EventLoopPromise<Void>) {
        let line = String(openSSHPublicKey: hostKey)
        let fingerprint = SSHKeyTools.fingerprint(publicLine: line) ?? "unknown"

        lock.lock()
        _fingerprint = fingerprint
        lock.unlock()

        if let known = KnownHosts.shared.entry(for: hostID) {
            if known.publicKey == line {
                validationCompletePromise.succeed(())
            } else {
                let problem = HostKeyProblem.changed(host: hostID, expected: known.fingerprint, received: fingerprint)
                lock.lock()
                _problem = problem
                lock.unlock()
                validationCompletePromise.fail(problem)
            }
        } else {
            KnownHosts.shared.trust(hostID: hostID, publicKey: line)
            validationCompletePromise.succeed(())
        }
    }
}
