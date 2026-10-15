import Foundation

enum AuthMethod: String, Codable, CaseIterable, Identifiable {
    case password
    case key

    var id: String { rawValue }
    var label: String { self == .password ? "Password" : "SSH Key" }
}

struct Host: Identifiable, Codable, Hashable {
    var id = UUID()
    var name: String = ""
    var hostname: String = ""
    var port: Int = 22
    var username: String = ""
    var auth: AuthMethod = .password
    var keyID: UUID? = nil
    var startupCommand: String = ""
    var lastConnected: Date? = nil

    var displayName: String { name.isEmpty ? hostname : name }
    var subtitle: String { "\(username)@\(hostname)" + (port == 22 ? "" : ":\(port)") }
    var passwordAccount: String { "pw.\(id.uuidString)" }
}

struct Snippet: Identifiable, Codable, Hashable {
    var id = UUID()
    var title: String
    var command: String
    var sendReturn: Bool = true
}

struct SSHKeyInfo: Identifiable, Codable, Hashable {
    var id = UUID()
    var name: String
    var type: String            // "ssh-ed25519", "ssh-rsa", ...
    var publicKey: String       // OpenSSH one-line public key
    var fingerprint: String     // SHA256:...
    var created: Date = Date()
    var encrypted: Bool = false // private key is passphrase protected

    var privateAccount: String { "key.\(id.uuidString)" }
    var passphraseAccount: String { "keypass.\(id.uuidString)" }
    var typeLabel: String {
        switch type {
        case "ssh-ed25519": return "Ed25519"
        case "ssh-rsa": return "RSA"
        default: return type
        }
    }
}

/// Everything the SSH layer needs to open a connection. Foundation-only on purpose.
struct ConnectionConfig {
    enum Credential {
        case password(String)
        case key(pem: String, type: String, passphrase: String?)
    }

    var hostname: String
    var port: Int
    var username: String
    var credential: Credential
    var startupCommand: String?
}
