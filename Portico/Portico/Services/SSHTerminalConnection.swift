import Foundation
import Citadel
import Crypto
import NIOCore
import NIOSSH

enum ConnectionError: LocalizedError {
    case badKey(String)
    case lost

    var errorDescription: String? {
        switch self {
        case .badKey(let message): return message
        case .lost: return "The connection was lost."
        }
    }
}

/// One SSH shell session (PTY) backed by Citadel. Contains no UI code.
/// Output is delivered through `onOutput`/`onClose` on arbitrary threads.
final class SSHTerminalConnection: @unchecked Sendable {

    private enum Input {
        case bytes([UInt8])
        case resize(cols: Int, rows: Int)
    }

    var onOutput: (([UInt8]) -> Void)?
    var onConnected: (() -> Void)?
    var onClose: ((Error?) -> Void)?

    private let lock = NSLock()
    private var client: SSHClient?
    private var task: Task<Void, Never>?
    private var finished = false
    private var hostKeyDelegate: TOFUHostKeyDelegate?

    private var inputContinuation: AsyncStream<Input>.Continuation?
    private let inputStream: AsyncStream<Input>

    var fingerprint: String? { hostKeyDelegate?.seenFingerprint }

    init() {
        var captured: AsyncStream<Input>.Continuation?
        inputStream = AsyncStream<Input> { continuation in
            captured = continuation
        }
        inputContinuation = captured
    }

    // MARK: Public API

    func start(config: ConnectionConfig, cols: Int, rows: Int) {
        task = Task { [weak self] in
            await self?.run(config: config, cols: cols, rows: rows)
        }
    }

    func send(_ bytes: [UInt8]) {
        inputContinuation?.yield(.bytes(bytes))
    }

    func resize(cols: Int, rows: Int) {
        inputContinuation?.yield(.resize(cols: cols, rows: rows))
    }

    func disconnect() {
        lock.lock()
        let alreadyFinished = finished
        finished = true
        let currentClient = client
        lock.unlock()

        inputContinuation?.finish()
        task?.cancel()
        if let currentClient, !alreadyFinished {
            Task { try? await currentClient.close() }
        }
    }

    /// Opens an SFTP channel on the already authenticated connection.
    func openSFTP() async throws -> SFTPClient {
        lock.lock()
        let current = client
        lock.unlock()
        guard let current else { throw ConnectionError.lost }
        return try await current.openSFTP()
    }

    // MARK: Internals

    private func makeAuth(for config: ConnectionConfig) throws -> SSHAuthenticationMethod {
        switch config.credential {
        case .password(let password):
            return .passwordBased(username: config.username, password: password)

        case .key(let pem, let type, let passphrase):
            let decryptionKey = passphrase.flatMap { $0.isEmpty ? nil : Data($0.utf8) }
            do {
                if type == "ssh-ed25519" {
                    let key = try Curve25519.Signing.PrivateKey(sshEd25519: pem, decryptionKey: decryptionKey)
                    return .ed25519(username: config.username, privateKey: key)
                } else if type == "ssh-rsa" {
                    let key = try Insecure.RSA.PrivateKey(sshRsa: pem, decryptionKey: decryptionKey)
                    return .rsa(username: config.username, privateKey: key)
                } else {
                    throw ConnectionError.badKey("Unsupported key type \(type).")
                }
            } catch let error as ConnectionError {
                throw error
            } catch {
                if decryptionKey == nil {
                    throw ConnectionError.badKey("Couldn't read the private key. If it is passphrase protected, add the passphrase to the key. (\(error))")
                } else {
                    throw ConnectionError.badKey("Couldn't decrypt the private key. Check the passphrase. (\(error))")
                }
            }
        }
    }

    private func run(config: ConnectionConfig, cols: Int, rows: Int) async {
        let delegate = TOFUHostKeyDelegate(host: config.hostname, port: config.port)
        hostKeyDelegate = delegate

        do {
            let auth = try makeAuth(for: config)
            let settings = SSHClientSettings(
                host: config.hostname,
                port: config.port,
                authenticationMethod: { auth },
                hostKeyValidator: .custom(delegate)
            )
            let newClient = try await SSHClient.connect(to: settings)

            lock.lock()
            client = newClient
            let wasCancelled = finished
            lock.unlock()

            if wasCancelled {
                try? await newClient.close()
                return
            }

            newClient.onDisconnect { [weak self] in
                self?.finish(error: ConnectionError.lost)
            }
            onConnected?()

            let request = SSHChannelRequestEvent.PseudoTerminalRequest(
                wantReply: true,
                term: "xterm-256color",
                terminalCharacterWidth: max(cols, 20),
                terminalRowHeight: max(rows, 5),
                terminalPixelWidth: 0,
                terminalPixelHeight: 0,
                terminalModes: SSHTerminalModes([.ECHO: 1])
            )

            let startup = config.startupCommand
            let stream = inputStream

            try await newClient.withPTY(request) { inbound, outbound in
                if let startup, !startup.isEmpty {
                    try await outbound.write(ByteBuffer(string: startup + "\r"))
                }

                try await withThrowingTaskGroup(of: Void.self) { group in
                    group.addTask {
                        for await input in stream {
                            switch input {
                            case .bytes(let bytes):
                                try await outbound.write(ByteBuffer(bytes: bytes))
                            case .resize(let c, let r):
                                try await outbound.changeSize(cols: c, rows: r, pixelWidth: 0, pixelHeight: 0)
                            }
                        }
                    }
                    group.addTask { [weak self] in
                        for try await chunk in inbound {
                            switch chunk {
                            case .stdout(let buffer), .stderr(let buffer):
                                self?.onOutput?(Array(buffer.readableBytesView))
                            }
                        }
                    }
                    // Whichever side ends first (remote exit or local disconnect) ends the session.
                    _ = try await group.next()
                    group.cancelAll()
                }
            }
            finish(error: nil)
        } catch {
            if let problem = delegate.problem {
                finish(error: problem)
            } else if error is SSHClient.CommandFailed {
                // The remote shell exited with a non-zero status: a normal end of session.
                finish(error: nil)
            } else {
                finish(error: error)
            }
        }
    }

    private func finish(error: Error?) {
        lock.lock()
        let wasFinished = finished
        finished = true
        let currentClient = client
        lock.unlock()

        // Already finished (user disconnected, or an earlier error was reported).
        if wasFinished { return }

        inputContinuation?.finish()
        if let currentClient {
            Task { try? await currentClient.close() }
        }
        onClose?(error)
    }
}
