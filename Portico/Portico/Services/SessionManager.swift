import Foundation
import Combine

enum AppTab: Hashable {
    case hosts, terminal, keys, snippets, settings
}

@MainActor
final class SessionManager: ObservableObject {
    @Published var sessions: [TerminalSession] = []
    @Published var activeID: UUID?
    @Published var tab: AppTab = .hosts

    private var cancellables: [UUID: AnyCancellable] = [:]

    var active: TerminalSession? {
        sessions.first { $0.id == activeID } ?? sessions.last
    }

    func open(host: Host, config: ConnectionConfig) {
        let session = TerminalSession(host: host, config: config)
        // Re-publish session changes (state, title) so tab strips refresh.
        cancellables[session.id] = session.objectWillChange.sink { [weak self] _ in
            self?.objectWillChange.send()
        }
        sessions.append(session)
        activeID = session.id
        tab = .terminal
    }

    func close(_ session: TerminalSession) {
        session.disconnect()
        cancellables[session.id] = nil
        sessions.removeAll { $0.id == session.id }
        if activeID == session.id {
            activeID = sessions.last?.id
        }
    }

    func reapplyAppearance() {
        for session in sessions {
            session.applyAppearance()
        }
    }
}
