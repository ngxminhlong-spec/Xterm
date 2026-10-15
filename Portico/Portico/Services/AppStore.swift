import Foundation
import Combine

/// Hosts, snippets and key metadata. Secrets (passwords, private keys,
/// passphrases) are kept in the Keychain; everything else is JSON in
/// Application Support.
@MainActor
final class AppStore: ObservableObject {
    @Published var hosts: [Host] = [] { didSet { save(hosts, to: "hosts.json") } }
    @Published var snippets: [Snippet] = [] { didSet { save(snippets, to: "snippets.json") } }
    @Published var keys: [SSHKeyInfo] = [] { didSet { save(keys, to: "keys.json") } }

    private let directory: URL

    init() {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        try? FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
        directory = base

        hosts = AppStore.load([Host].self, from: base.appendingPathComponent("hosts.json")) ?? []
        keys = AppStore.load([SSHKeyInfo].self, from: base.appendingPathComponent("keys.json")) ?? []
        if let saved = AppStore.load([Snippet].self, from: base.appendingPathComponent("snippets.json")) {
            snippets = saved
        } else {
            snippets = [
                Snippet(title: "Disk usage", command: "df -h"),
                Snippet(title: "Memory", command: "free -h"),
                Snippet(title: "Top processes", command: "top -o %CPU"),
                Snippet(title: "Listening ports", command: "ss -tulpn"),
                Snippet(title: "Last logins", command: "last -n 10"),
                Snippet(title: "Attach tmux", command: "tmux attach || tmux new")
            ]
        }
    }

    // MARK: Persistence

    private static func load<T: Decodable>(_ type: T.Type, from url: URL) -> T? {
        guard let data = try? Data(contentsOf: url) else { return nil }
        return try? JSONDecoder().decode(type, from: data)
    }

    private func save<T: Encodable>(_ value: T, to name: String) {
        guard let data = try? JSONEncoder().encode(value) else { return }
        try? data.write(to: directory.appendingPathComponent(name), options: .atomic)
    }

    // MARK: Hosts

    func upsert(_ host: Host, password: String?) {
        if let index = hosts.firstIndex(where: { $0.id == host.id }) {
            hosts[index] = host
        } else {
            hosts.append(host)
        }
        if host.auth == .password, let password {
            if password.isEmpty {
                Keychain.remove(host.passwordAccount)
            } else {
                Keychain.set(password, for: host.passwordAccount)
            }
        }
    }

    func delete(_ host: Host) {
        Keychain.remove(host.passwordAccount)
        hosts.removeAll { $0.id == host.id }
    }

    func duplicate(_ host: Host) {
        var copy = host
        copy.id = UUID()
        copy.name = host.displayName + " copy"
        copy.lastConnected = nil
        let password = Keychain.get(host.passwordAccount)
        upsert(copy, password: password)
    }

    func markConnected(_ host: Host) {
        guard let index = hosts.firstIndex(where: { $0.id == host.id }) else { return }
        hosts[index].lastConnected = Date()
    }

    func savedPassword(for host: Host) -> String? {
        Keychain.get(host.passwordAccount)
    }

    func key(withID id: UUID?) -> SSHKeyInfo? {
        guard let id else { return nil }
        return keys.first { $0.id == id }
    }

    /// Builds the connection description. `password` overrides the stored one.
    func config(for host: Host, password: String? = nil) -> ConnectionConfig? {
        let startup = host.startupCommand.isEmpty ? nil : host.startupCommand
        switch host.auth {
        case .password:
            let value = password ?? Keychain.get(host.passwordAccount) ?? ""
            return ConnectionConfig(hostname: host.hostname, port: host.port, username: host.username,
                                    credential: .password(value), startupCommand: startup)
        case .key:
            guard let keyInfo = self.key(withID: host.keyID), let pem = Keychain.get(keyInfo.privateAccount) else { return nil }
            let passphrase = Keychain.get(keyInfo.passphraseAccount)
            return ConnectionConfig(hostname: host.hostname, port: host.port, username: host.username,
                                    credential: .key(pem: pem, type: keyInfo.type, passphrase: passphrase),
                                    startupCommand: startup)
        }
    }

    // MARK: Keys

    @discardableResult
    func generateEd25519(name: String) -> SSHKeyInfo {
        let comment = name.replacingOccurrences(of: " ", with: "-") + "@portico"
        let generated = SSHKeyTools.generateEd25519(comment: comment)
        let info = SSHKeyInfo(name: name, type: "ssh-ed25519", publicKey: generated.publicLine,
                              fingerprint: generated.fingerprint, encrypted: false)
        Keychain.set(generated.privatePEM, for: info.privateAccount)
        keys.append(info)
        return info
    }

    @discardableResult
    func importKey(name: String, pem: String, passphrase: String?) throws -> SSHKeyInfo {
        let inspection = try SSHKeyTools.inspect(pem: pem)
        let info = SSHKeyInfo(name: name, type: inspection.type, publicKey: inspection.publicLine,
                              fingerprint: inspection.fingerprint, encrypted: inspection.encrypted)
        Keychain.set(pem, for: info.privateAccount)
        if let passphrase, !passphrase.isEmpty {
            Keychain.set(passphrase, for: info.passphraseAccount)
        }
        keys.append(info)
        return info
    }

    func setPassphrase(_ passphrase: String, for key: SSHKeyInfo) {
        if passphrase.isEmpty {
            Keychain.remove(key.passphraseAccount)
        } else {
            Keychain.set(passphrase, for: key.passphraseAccount)
        }
    }

    func hasPassphrase(_ key: SSHKeyInfo) -> Bool {
        Keychain.get(key.passphraseAccount) != nil
    }

    func privateKeyText(_ key: SSHKeyInfo) -> String? {
        Keychain.get(key.privateAccount)
    }

    func delete(_ key: SSHKeyInfo) {
        Keychain.remove(key.privateAccount)
        Keychain.remove(key.passphraseAccount)
        for index in hosts.indices where hosts[index].keyID == key.id {
            hosts[index].keyID = nil
        }
        keys.removeAll { $0.id == key.id }
    }
}
