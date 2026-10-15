import Foundation
import Combine
import UIKit
import SwiftTerm

/// One open terminal tab: owns the SwiftTerm view and the SSH connection behind it.
final class TerminalSession: ObservableObject, Identifiable, TerminalViewDelegate {

    enum State: Equatable {
        case connecting
        case connected
        case closed
        case failed(String)
    }

    let id = UUID()
    let host: Host
    let terminalView: TerminalView

    @Published var state: State = .connecting
    @Published var title: String

    private let config: ConnectionConfig
    private(set) var connection = SSHTerminalConnection()

    var fingerprint: String? { connection.fingerprint }

    @MainActor
    init(host: Host, config: ConnectionConfig) {
        self.host = host
        self.config = config
        self.title = host.displayName
        self.terminalView = TerminalView(frame: CGRect(x: 0, y: 0, width: 390, height: 640))
        terminalView.terminalDelegate = self
        TerminalAppearance.apply(to: terminalView)
        connect()
    }

    // MARK: Lifecycle

    private enum Event {
        case output([UInt8])
        case connected
        case closed(Error?)
    }

    private var eventTask: Task<Void, Never>?

    @MainActor
    func connect() {
        state = .connecting

        // Everything the SSH layer reports goes through one ordered stream that is
        // consumed on the main actor, so terminal output can never be reordered.
        var captured: AsyncStream<Event>.Continuation!
        let stream = AsyncStream<Event>(bufferingPolicy: .unbounded) { captured = $0 }
        let events = captured!

        let conn = SSHTerminalConnection()
        connection = conn
        conn.onOutput = { events.yield(.output($0)) }
        conn.onConnected = { events.yield(.connected) }
        conn.onClose = { error in
            events.yield(.closed(error))
            events.finish()
        }

        eventTask?.cancel()
        eventTask = Task { @MainActor [weak self] in
            for await event in stream {
                guard let self else { return }
                self.handle(event)
            }
        }

        let terminal = terminalView.getTerminal()
        conn.start(config: config, cols: terminal.cols, rows: terminal.rows)
    }

    @MainActor
    private func handle(_ event: Event) {
        switch event {
        case .output(let bytes):
            terminalView.feed(byteArray: bytes[...])
        case .connected:
            state = .connected
        case .closed(let error):
            if let error {
                let message = describeConnectionError(error)
                state = .failed(message)
                let text = message.replacingOccurrences(of: "\n", with: "\r\n")
                terminalView.feed(text: "\r\n\u{1B}[31m\(text)\u{1B}[0m\r\n")
            } else {
                state = .closed
                terminalView.feed(text: "\r\n\u{1B}[90m[session ended]\u{1B}[0m\r\n")
            }
        }
    }

    @MainActor
    func reconnect() {
        eventTask?.cancel()
        connection.disconnect()
        terminalView.feed(text: "\r\n\u{1B}[90m[reconnecting…]\u{1B}[0m\r\n")
        connect()
    }

    @MainActor
    func disconnect() {
        eventTask?.cancel()
        connection.disconnect()
        state = .closed
    }

    // MARK: Input helpers

    func sendText(_ text: String) {
        connection.send(Array(text.utf8))
    }

    @MainActor
    func pasteFromClipboard() {
        if let text = UIPasteboard.general.string, !text.isEmpty {
            sendText(text)
        }
    }

    @MainActor
    func applyAppearance() {
        TerminalAppearance.apply(to: terminalView)
    }

    // MARK: TerminalViewDelegate

    func sizeChanged(source: TerminalView, newCols: Int, newRows: Int) {
        connection.resize(cols: newCols, rows: newRows)
    }

    func setTerminalTitle(source: TerminalView, title: String) {
        onMain { [weak self] in
            self?.title = title.isEmpty ? (self?.host.displayName ?? "") : title
        }
    }

    func hostCurrentDirectoryUpdate(source: TerminalView, directory: String?) {}

    func send(source: TerminalView, data: ArraySlice<UInt8>) {
        connection.send(Array(data))
    }

    func scrolled(source: TerminalView, position: Double) {}

    func requestOpenLink(source: TerminalView, link: String, params: [String: String]) {
        guard let url = URL(string: link), ["http", "https"].contains(url.scheme?.lowercased() ?? "") else { return }
        onMain { UIApplication.shared.open(url) }
    }

    func bell(source: TerminalView) {
        onMain { UIImpactFeedbackGenerator(style: .light).impactOccurred() }
    }

    func clipboardCopy(source: TerminalView, content: Data) {
        guard let text = String(data: content, encoding: .utf8) else { return }
        onMain { UIPasteboard.general.string = text }
    }

    func clipboardRead(source: TerminalView) -> Data? {
        nil
    }

    func iTermContent(source: TerminalView, content: ArraySlice<UInt8>) {}

    func rangeChanged(source: TerminalView, startY: Int, endY: Int) {}
}
