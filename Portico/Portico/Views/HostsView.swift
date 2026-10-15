import SwiftUI

struct HostsView: View {
    @EnvironmentObject var store: AppStore
    @EnvironmentObject var manager: SessionManager

    @State private var editing: Host?
    @State private var isNewHost = false
    @State private var search = ""
    @State private var passwordPromptHost: Host?
    @State private var showPasswordPrompt = false
    @State private var promptedPassword = ""
    @State private var errorMessage: String?

    private var filtered: [Host] {
        let sorted = store.hosts.sorted { a, b in
            let da = a.lastConnected ?? .distantPast
            let db = b.lastConnected ?? .distantPast
            if da != db { return da > db }
            return a.displayName.localizedCaseInsensitiveCompare(b.displayName) == .orderedAscending
        }
        let query = search.trimmingCharacters(in: .whitespaces).lowercased()
        guard !query.isEmpty else { return sorted }
        return sorted.filter {
            $0.displayName.lowercased().contains(query)
                || $0.hostname.lowercased().contains(query)
                || $0.username.lowercased().contains(query)
        }
    }

    var body: some View {
        NavigationStack {
            Group {
                if store.hosts.isEmpty {
                    EmptyStateView(icon: "server.rack", title: "No hosts yet", message: "Add a server to start an SSH session.") {
                        Button("Add Host") { newHost() }
                            .buttonStyle(.borderedProminent)
                    }
                } else {
                    List {
                        ForEach(filtered) { host in
                            Button {
                                connect(host)
                            } label: {
                                HostRow(host: host)
                            }
                            .swipeActions(edge: .trailing) {
                                Button("Delete", role: .destructive) { store.delete(host) }
                                Button("Edit") { edit(host) }.tint(.blue)
                            }
                            .swipeActions(edge: .leading) {
                                Button("Duplicate") { store.duplicate(host) }.tint(.indigo)
                            }
                            .contextMenu {
                                LabelButton("Connect", "play.fill") { connect(host) }
                                LabelButton("Edit", "pencil") { edit(host) }
                                LabelButton("Duplicate", "plus.square.on.square") { store.duplicate(host) }
                                LabelButton("Delete", "trash", role: .destructive) { store.delete(host) }
                            }
                        }
                    }
                    .searchable(text: $search, prompt: "Search hosts")
                }
            }
            .navigationTitle("Hosts")
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button {
                        newHost()
                    } label: {
                        Image(systemName: "plus")
                    }
                    .accessibilityLabel("Add host")
                }
            }
            .sheet(item: $editing) { host in
                HostEditView(host: host, isNew: isNewHost, existingPassword: store.savedPassword(for: host))
            }
            .alert("Password for \(passwordPromptHost?.displayName ?? "host")", isPresented: $showPasswordPrompt) {
                SecureField("Password", text: $promptedPassword)
                Button("Connect") {
                    if let host = passwordPromptHost {
                        start(host, password: promptedPassword)
                    }
                    promptedPassword = ""
                }
                Button("Cancel", role: .cancel) {
                    promptedPassword = ""
                }
            }
        }
        .alert(
            "Can't connect",
            isPresented: Binding(
                get: { errorMessage != nil },
                set: { if !$0 { errorMessage = nil } }
            )
        ) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(errorMessage ?? "")
        }
    }

    private func newHost() {
        isNewHost = true
        editing = Host()
    }

    private func edit(_ host: Host) {
        isNewHost = false
        editing = host
    }

    private func connect(_ host: Host) {
        if host.auth == .password && store.savedPassword(for: host) == nil {
            promptedPassword = ""
            passwordPromptHost = host
            showPasswordPrompt = true
        } else {
            start(host, password: nil)
        }
    }

    private func start(_ host: Host, password: String?) {
        guard let config = store.config(for: host, password: password) else {
            errorMessage = "The SSH key for this host is missing. Open the host and choose a key."
            return
        }
        store.markConnected(host)
        manager.open(host: host, config: config)
    }
}

struct HostRow: View {
    let host: Host

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: host.auth == .key ? "key.fill" : "server.rack")
                .foregroundStyle(.white)
                .frame(width: 36, height: 36)
                .background(Color.accentColor.gradient, in: RoundedRectangle(cornerRadius: 9))
            VStack(alignment: .leading, spacing: 2) {
                Text(host.displayName)
                    .font(.headline)
                    .foregroundStyle(.primary)
                Text(host.subtitle)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Image(systemName: "chevron.right")
                .font(.footnote.weight(.semibold))
                .foregroundStyle(.tertiary)
        }
        .contentShape(Rectangle())
    }
}

struct HostEditView: View {
    @EnvironmentObject var store: AppStore
    @Environment(\.dismiss) private var dismiss

    @State private var host: Host
    @State private var password: String
    private let isNew: Bool

    init(host: Host, isNew: Bool, existingPassword: String?) {
        _host = State(initialValue: host)
        _password = State(initialValue: existingPassword ?? "")
        self.isNew = isNew
    }

    private var canSave: Bool {
        !host.hostname.trimmingCharacters(in: .whitespaces).isEmpty
            && !host.username.trimmingCharacters(in: .whitespaces).isEmpty
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Server") {
                    TextField("Name (optional)", text: $host.name)
                    TextField("Hostname or IP address", text: $host.hostname)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .keyboardType(.URL)
                    HStack {
                        Text("Port")
                        Spacer()
                        TextField("22", value: $host.port, format: .number.grouping(.never))
                            .keyboardType(.numberPad)
                            .multilineTextAlignment(.trailing)
                            .frame(width: 90)
                    }
                }

                Section("Authentication") {
                    TextField("Username", text: $host.username)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                    Picker("Method", selection: $host.auth) {
                        ForEach(AuthMethod.allCases) { method in
                            Text(method.label).tag(method)
                        }
                    }
                    .pickerStyle(.segmented)

                    if host.auth == .password {
                        SecureField("Password", text: $password)
                    } else {
                        Picker("Key", selection: $host.keyID) {
                            Text("None").tag(UUID?.none)
                            ForEach(store.keys) { key in
                                Text("\(key.name) · \(key.typeLabel)").tag(Optional(key.id))
                            }
                        }
                        if store.keys.isEmpty {
                            Text("No keys yet. Generate or import one in the Keys tab.")
                                .font(.footnote)
                                .foregroundStyle(.secondary)
                        }
                    }
                }

                Section {
                    TextField("Startup command (optional)", text: $host.startupCommand)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                } header: {
                    Text("On connect")
                } footer: {
                    Text("Runs right after login, for example: tmux attach || tmux new")
                }
            }
            .navigationTitle(isNew ? "New Host" : "Edit Host")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { save() }
                        .disabled(!canSave)
                }
            }
        }
    }

    private func save() {
        var clean = host
        clean.hostname = host.hostname.trimmingCharacters(in: .whitespaces)
        clean.username = host.username.trimmingCharacters(in: .whitespaces)
        clean.name = host.name.trimmingCharacters(in: .whitespaces)
        clean.port = min(max(host.port, 1), 65535)
        store.upsert(clean, password: clean.auth == .password ? password : nil)
        dismiss()
    }
}
