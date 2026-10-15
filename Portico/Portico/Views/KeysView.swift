import SwiftUI
import UniformTypeIdentifiers

struct KeysView: View {
    @EnvironmentObject var store: AppStore

    @State private var showGenerate = false
    @State private var newKeyName = ""
    @State private var showFileImporter = false
    @State private var importDraft: ImportDraft?
    @State private var errorMessage: String?

    var body: some View {
        NavigationStack {
            Group {
                if store.keys.isEmpty {
                    EmptyStateView(icon: "key", title: "No SSH keys", message: "Generate a key on this device, or import an existing OpenSSH private key.") {
                        Button("Generate Key") { startGenerate() }
                            .buttonStyle(.borderedProminent)
                    }
                } else {
                    List {
                        ForEach(store.keys) { key in
                            NavigationLink(value: key) {
                                VStack(alignment: .leading, spacing: 3) {
                                    HStack {
                                        Text(key.name).font(.headline)
                                        Text(key.typeLabel)
                                            .font(.caption2.weight(.semibold))
                                            .padding(.horizontal, 6)
                                            .padding(.vertical, 2)
                                            .background(Color.accentColor.opacity(0.18), in: Capsule())
                                        if key.encrypted {
                                            Image(systemName: "lock.fill").font(.caption).foregroundStyle(.secondary)
                                        }
                                    }
                                    Text(key.fingerprint)
                                        .font(.system(.caption, design: .monospaced))
                                        .foregroundStyle(.secondary)
                                        .lineLimit(1)
                                        .truncationMode(.middle)
                                }
                            }
                        }
                    }
                }
            }
            .navigationTitle("Keys")
            .navigationDestination(for: SSHKeyInfo.self) { key in
                KeyDetailView(key: key)
            }
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Menu {
                        LabelButton("Generate Ed25519 key", "wand.and.stars") { startGenerate() }
                        LabelButton("Import from Files", "folder") { showFileImporter = true }
                        LabelButton("Paste a private key", "doc.on.clipboard") {
                            importDraft = ImportDraft(name: "", pem: "")
                        }
                    } label: {
                        Image(systemName: "plus")
                    }
                }
            }
            .alert("Generate Ed25519 key", isPresented: $showGenerate) {
                TextField("Name", text: $newKeyName)
                Button("Generate") {
                    let name = newKeyName.trimmingCharacters(in: .whitespaces)
                    store.generateEd25519(name: name.isEmpty ? "Portico key" : name)
                }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("A new key pair is created on this device. The private key stays in the Keychain.")
            }
            .fileImporter(isPresented: $showFileImporter, allowedContentTypes: [.item]) { result in
                handleFile(result)
            }
            .sheet(item: $importDraft) { draft in
                ImportKeySheet(draft: draft)
            }
        }
        .alert(
            "Couldn't import",
            isPresented: Binding(get: { errorMessage != nil }, set: { if !$0 { errorMessage = nil } })
        ) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(errorMessage ?? "")
        }
    }

    private func startGenerate() {
        newKeyName = ""
        showGenerate = true
    }

    private func handleFile(_ result: Result<URL, Error>) {
        switch result {
        case .failure(let error):
            errorMessage = error.localizedDescription
        case .success(let url):
            let accessed = url.startAccessingSecurityScopedResource()
            defer { if accessed { url.stopAccessingSecurityScopedResource() } }
            guard let data = try? Data(contentsOf: url), let text = String(data: data, encoding: .utf8) else {
                errorMessage = "That file couldn't be read as text."
                return
            }
            importDraft = ImportDraft(name: url.lastPathComponent, pem: text)
        }
    }
}

struct ImportDraft: Identifiable {
    let id = UUID()
    var name: String
    var pem: String
}

struct ImportKeySheet: View {
    @EnvironmentObject var store: AppStore
    @Environment(\.dismiss) private var dismiss

    @State private var name: String
    @State private var pem: String
    @State private var passphrase = ""
    @State private var errorMessage: String?

    init(draft: ImportDraft) {
        _name = State(initialValue: draft.name)
        _pem = State(initialValue: draft.pem)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Name") {
                    TextField("e.g. Work laptop key", text: $name)
                }
                Section {
                    TextEditor(text: $pem)
                        .font(.system(.footnote, design: .monospaced))
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .frame(minHeight: 180)
                    LabelButton("Paste from clipboard", "doc.on.clipboard") {
                        pem = UIPasteboard.general.string ?? pem
                    }
                } header: {
                    Text("Private key")
                } footer: {
                    Text("OpenSSH format (-----BEGIN OPENSSH PRIVATE KEY-----). Ed25519 and RSA are supported.")
                }
                Section {
                    SecureField("Passphrase (if the key has one)", text: $passphrase)
                } header: {
                    Text("Passphrase")
                } footer: {
                    Text("Stored in the Keychain so connections don't ask for it every time.")
                }
                if let errorMessage {
                    Section {
                        Text(errorMessage).foregroundStyle(.red).font(.footnote)
                    }
                }
            }
            .navigationTitle("Import Key")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Import") { importKey() }
                        .disabled(pem.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
        }
    }

    private func importKey() {
        let trimmedName = name.trimmingCharacters(in: .whitespaces)
        do {
            try store.importKey(
                name: trimmedName.isEmpty ? "Imported key" : trimmedName,
                pem: pem.trimmingCharacters(in: .whitespacesAndNewlines) + "\n",
                passphrase: passphrase
            )
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

struct KeyDetailView: View {
    @EnvironmentObject var store: AppStore
    @Environment(\.dismiss) private var dismiss

    let key: SSHKeyInfo
    @State private var passphrase = ""
    @State private var copied = false
    @State private var confirmDelete = false

    private var installCommand: String {
        "mkdir -p ~/.ssh && echo '\(key.publicKey)' >> ~/.ssh/authorized_keys"
    }

    var body: some View {
        Form {
            Section("Key") {
                LabeledContent("Name", value: key.name)
                LabeledContent("Type", value: key.typeLabel)
                LabeledContent("Created", value: key.created.formatted(date: .abbreviated, time: .omitted))
                VStack(alignment: .leading, spacing: 4) {
                    Text("Fingerprint").font(.caption).foregroundStyle(.secondary)
                    Text(key.fingerprint)
                        .font(.system(.footnote, design: .monospaced))
                        .textSelection(.enabled)
                }
            }

            Section {
                Text(key.publicKey)
                    .font(.system(.footnote, design: .monospaced))
                    .textSelection(.enabled)
                LabelButton(copied ? "Copied" : "Copy public key", "doc.on.doc") {
                    UIPasteboard.general.string = key.publicKey
                    copied = true
                }
                ShareLink(item: key.publicKey) {
                    Label("Share public key", systemImage: "square.and.arrow.up")
                }
                LabelButton("Copy install command", "terminal") {
                    UIPasteboard.general.string = installCommand
                }
            } header: {
                Text("Public key")
            } footer: {
                Text("Add this line to ~/.ssh/authorized_keys on your server. The install command does that in one paste.")
            }

            if key.encrypted {
                Section {
                    SecureField(store.hasPassphrase(key) ? "Passphrase saved" : "Passphrase", text: $passphrase)
                    Button("Save passphrase") {
                        store.setPassphrase(passphrase, for: key)
                        passphrase = ""
                    }
                    .disabled(passphrase.isEmpty)
                } header: {
                    Text("Passphrase")
                } footer: {
                    Text("This key is encrypted. Its passphrase is stored in the Keychain.")
                }
            }

            Section {
                Button("Delete key", role: .destructive) { confirmDelete = true }
            }
        }
        .navigationTitle(key.name)
        .navigationBarTitleDisplayMode(.inline)
        .confirmationDialog("Delete this key?", isPresented: $confirmDelete, titleVisibility: .visible) {
            Button("Delete", role: .destructive) {
                store.delete(key)
                dismiss()
            }
        } message: {
            Text("Hosts that use it will need another key. This can't be undone.")
        }
    }
}
