import Foundation
import Crypto

/// Pure-Foundation helpers for OpenSSH key material: generation, inspection
/// (without decrypting) and fingerprints.
enum SSHKeyTools {

    // MARK: Wire-format helpers

    private static func u32(_ value: UInt32) -> [UInt8] {
        [UInt8((value >> 24) & 0xFF), UInt8((value >> 16) & 0xFF), UInt8((value >> 8) & 0xFF), UInt8(value & 0xFF)]
    }

    private static func sshString(_ bytes: [UInt8]) -> [UInt8] {
        u32(UInt32(bytes.count)) + bytes
    }

    private struct Reader {
        let bytes: [UInt8]
        var pos = 0

        init(_ data: Data) { bytes = [UInt8](data) }

        mutating func skip(_ count: Int) -> Bool {
            guard count >= 0, pos + count <= bytes.count else { return false }
            pos += count
            return true
        }

        mutating func readU32() -> UInt32? {
            guard pos + 4 <= bytes.count else { return nil }
            var value: UInt32 = 0
            for i in 0..<4 { value = (value << 8) | UInt32(bytes[pos + i]) }
            pos += 4
            return value
        }

        mutating func readString() -> [UInt8]? {
            guard let length = readU32() else { return nil }
            let n = Int(length)
            guard pos + n <= bytes.count else { return nil }
            let slice = Array(bytes[pos..<(pos + n)])
            pos += n
            return slice
        }
    }

    // MARK: Fingerprints

    static func fingerprint(blob: Data) -> String {
        let digest = Data(SHA256.hash(data: blob))
        let b64 = digest.base64EncodedString().replacingOccurrences(of: "=", with: "")
        return "SHA256:" + b64
    }

    /// Fingerprint for a one-line OpenSSH public key ("ssh-ed25519 AAAA... comment").
    static func fingerprint(publicLine: String) -> String? {
        let parts = publicLine.split(separator: " ", omittingEmptySubsequences: true)
        guard parts.count >= 2, let blob = Data(base64Encoded: String(parts[1])) else { return nil }
        return fingerprint(blob: blob)
    }

    // MARK: Generation

    struct GeneratedKey {
        let privatePEM: String
        let publicLine: String
        let fingerprint: String
    }

    static func generateEd25519(comment: String) -> GeneratedKey {
        let key = Curve25519.Signing.PrivateKey()
        let pub = [UInt8](key.publicKey.rawRepresentation)
        let seed = [UInt8](key.rawRepresentation)
        let keyType = Array("ssh-ed25519".utf8)

        let pubBlob = sshString(keyType) + sshString(pub)

        let check = UInt32.random(in: 0...UInt32.max)
        var priv: [UInt8] = []
        priv += u32(check)
        priv += u32(check)
        priv += sshString(keyType)
        priv += sshString(pub)
        priv += sshString(seed + pub)
        priv += sshString(Array(comment.utf8))
        var pad: UInt8 = 1
        while priv.count % 8 != 0 {
            priv.append(pad)
            pad += 1
        }

        var body: [UInt8] = Array("openssh-key-v1".utf8) + [0]
        body += sshString(Array("none".utf8))   // cipher
        body += sshString(Array("none".utf8))   // kdf
        body += sshString([])                   // kdf options
        body += u32(1)                          // number of keys
        body += sshString(pubBlob)
        body += sshString(priv)

        let b64 = Data(body).base64EncodedString()
        var lines: [String] = []
        var index = b64.startIndex
        while index < b64.endIndex {
            let end = b64.index(index, offsetBy: 70, limitedBy: b64.endIndex) ?? b64.endIndex
            lines.append(String(b64[index..<end]))
            index = end
        }
        let pem = "-----BEGIN OPENSSH PRIVATE KEY-----\n" + lines.joined(separator: "\n") + "\n-----END OPENSSH PRIVATE KEY-----\n"

        let publicLine = "ssh-ed25519 " + Data(pubBlob).base64EncodedString() + (comment.isEmpty ? "" : " " + comment)
        return GeneratedKey(privatePEM: pem, publicLine: publicLine, fingerprint: fingerprint(blob: Data(pubBlob)))
    }

    // MARK: Inspection

    struct Inspection {
        let type: String
        let publicLine: String
        let fingerprint: String
        let encrypted: Bool
    }

    enum InspectError: LocalizedError {
        case notOpenSSH
        case malformed
        case unsupportedType(String)

        var errorDescription: String? {
            switch self {
            case .notOpenSSH:
                return "This isn't an OpenSSH-format private key. Convert it first with: ssh-keygen -p -o -f <keyfile>"
            case .malformed:
                return "The key file is damaged or incomplete."
            case .unsupportedType(let type):
                return "Key type \(type) isn't supported yet. Use an Ed25519 or RSA key."
            }
        }
    }

    /// Reads type, public key and encryption flag from an OpenSSH private key
    /// without needing the passphrase.
    static func inspect(pem: String) throws -> Inspection {
        let cleaned = pem.replacingOccurrences(of: "\r", with: "")
        guard let begin = cleaned.range(of: "-----BEGIN OPENSSH PRIVATE KEY-----"),
              let end = cleaned.range(of: "-----END OPENSSH PRIVATE KEY-----"),
              begin.upperBound <= end.lowerBound else {
            throw InspectError.notOpenSSH
        }
        let b64 = String(cleaned[begin.upperBound..<end.lowerBound].filter { !$0.isWhitespace })
        guard let data = Data(base64Encoded: b64) else { throw InspectError.malformed }

        var reader = Reader(data)
        let magic = Array("openssh-key-v1".utf8) + [0]
        guard reader.bytes.count > magic.count, Array(reader.bytes[0..<magic.count]) == magic else {
            throw InspectError.malformed
        }
        _ = reader.skip(magic.count)

        guard let cipher = reader.readString(),
              reader.readString() != nil,        // kdf name
              reader.readString() != nil,        // kdf options
              let count = reader.readU32(), count == 1,
              let pubBlob = reader.readString() else {
            throw InspectError.malformed
        }

        var blobReader = Reader(Data(pubBlob))
        guard let typeBytes = blobReader.readString(),
              let type = String(bytes: typeBytes, encoding: .utf8) else {
            throw InspectError.malformed
        }
        guard type == "ssh-ed25519" || type == "ssh-rsa" else {
            throw InspectError.unsupportedType(type)
        }

        let blob = Data(pubBlob)
        return Inspection(
            type: type,
            publicLine: type + " " + blob.base64EncodedString(),
            fingerprint: fingerprint(blob: blob),
            encrypted: String(bytes: cipher, encoding: .utf8) != "none"
        )
    }
}
