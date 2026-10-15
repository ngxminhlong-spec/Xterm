import SwiftUI

struct TerminalTabView: View {
    @EnvironmentObject var manager: SessionManager

    var body: some View {
        NavigationStack {
            if let session = manager.active {
                ActiveSessionView(session: session)
            } else {
                EmptyStateView(icon: "terminal", title: "No open sessions", message: "Pick a host in the Hosts tab to start a session.") {
                    Button("Choose a Host") { manager.tab = .hosts }
                        .buttonStyle(.borderedProminent)
                }
                .navigationTitle("Terminal")
            }
        }
    }
}

struct ActiveSessionView: View {
    @EnvironmentObject var manager: SessionManager
    @ObservedObject var session: TerminalSession
    @AppStorage("themeName") private var themeName = TerminalTheme.midnight.name

    @State private var showSFTP = false
    @State private var showSnippets = false
    @State private var showHostKey = false

    var body: some View {
        let theme = TerminalTheme.named(themeName)

        VStack(spacing: 0) {
            SessionStrip()
            ZStack(alignment: .top) {
                SwiftTermRepresentable(session: session)
                    .id(session.id)
                StatusBanner(session: session)
            }
        }
        .background(Color(uiColor: theme.backgroundColor))
        .navigationTitle(session.title)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItemGroup(placement: .navigationBarTrailing) {
                Button {
                    showSnippets = true
                } label: {
                    Image(systemName: "bolt.fill")
                }
                .accessibilityLabel("Snippets")

                Button {
                    showSFTP = true
                } label: {
                    Image(systemName: "folder")
                }
                .disabled(session.state != .connected)
                .accessibilityLabel("Files")

                Menu {
                    LabelButton("Paste", "doc.on.clipboard") { session.pasteFromClipboard() }
                    LabelButton("Reconnect", "arrow.clockwise") { session.reconnect() }
                    LabelButton("Host key", "key.viewfinder") { showHostKey = true }
                    Divider()
                    LabelButton("Close session", "xmark.circle", role: .destructive) {
                        manager.close(session)
                    }
                } label: {
                    Image(systemName: "ellipsis.circle")
                }
            }
        }
        .sheet(isPresented: $showSFTP) {
            SFTPBrowserView(connection: session.connection)
        }
        .sheet(isPresented: $showSnippets) {
            SnippetPickerView(session: session)
        }
        .alert("Server host key", isPresented: $showHostKey) {
            Button("Copy") { UIPasteboard.general.string = session.fingerprint ?? "" }
            Button("OK", role: .cancel) {}
        } message: {
            Text(session.fingerprint ?? "Not connected yet.")
        }
    }
}

struct SessionStrip: View {
    @EnvironmentObject var manager: SessionManager

    var body: some View {
        if manager.sessions.count > 1 {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(manager.sessions) { session in
                        SessionChip(session: session, selected: session.id == manager.active?.id)
                    }
                    Button {
                        manager.tab = .hosts
                    } label: {
                        Image(systemName: "plus")
                            .padding(8)
                            .background(Color(uiColor: .secondarySystemBackground), in: Circle())
                    }
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
            }
            .background(.bar)
        }
    }
}

struct SessionChip: View {
    @EnvironmentObject var manager: SessionManager
    @ObservedObject var session: TerminalSession
    let selected: Bool

    private var dotColor: Color {
        switch session.state {
        case .connected: return .green
        case .connecting: return .orange
        case .closed: return .gray
        case .failed: return .red
        }
    }

    var body: some View {
        Button {
            manager.activeID = session.id
        } label: {
            HStack(spacing: 6) {
                Circle().fill(dotColor).frame(width: 8, height: 8)
                Text(session.title).lineLimit(1).font(.subheadline)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 7)
            .background(
                selected ? Color.accentColor.opacity(0.25) : Color(uiColor: .secondarySystemBackground),
                in: Capsule()
            )
        }
        .buttonStyle(.plain)
        .contextMenu {
            Button("Close", role: .destructive) { manager.close(session) }
        }
    }
}

struct StatusBanner: View {
    @ObservedObject var session: TerminalSession

    var body: some View {
        switch session.state {
        case .connected:
            EmptyView()
        case .connecting:
            HStack(spacing: 8) {
                ProgressView()
                Text("Connecting to \(session.host.hostname)…").font(.footnote)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
            .background(.ultraThinMaterial, in: Capsule())
            .padding(.top, 8)
        case .closed:
            banner(text: "Session ended")
        case .failed:
            banner(text: "Connection failed")
        }
    }

    private func banner(text: String) -> some View {
        HStack(spacing: 10) {
            Text(text).font(.footnote.weight(.medium))
            Button("Reconnect") { session.reconnect() }
                .font(.footnote.weight(.semibold))
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        .background(.ultraThinMaterial, in: Capsule())
        .padding(.top, 8)
    }
}

struct SnippetPickerView: View {
    @EnvironmentObject var store: AppStore
    @Environment(\.dismiss) private var dismiss
    let session: TerminalSession

    var body: some View {
        NavigationStack {
            List {
                if store.snippets.isEmpty {
                    Text("No snippets yet. Add some in the Snippets tab.")
                        .foregroundStyle(.secondary)
                }
                ForEach(store.snippets) { snippet in
                    Button {
                        session.sendText(snippet.command + (snippet.sendReturn ? "\r" : ""))
                        dismiss()
                    } label: {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(snippet.title).foregroundStyle(.primary)
                            Text(snippet.command)
                                .font(.system(.footnote, design: .monospaced))
                                .foregroundStyle(.secondary)
                                .lineLimit(2)
                        }
                    }
                }
            }
            .navigationTitle("Run Snippet")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") { dismiss() }
                }
            }
        }
        .presentationDetents([.medium, .large])
    }
}
