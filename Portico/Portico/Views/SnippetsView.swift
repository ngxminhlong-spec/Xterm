import SwiftUI

struct SnippetsView: View {
    @EnvironmentObject var store: AppStore
    @State private var editing: Snippet?

    var body: some View {
        NavigationStack {
            Group {
                if store.snippets.isEmpty {
                    EmptyStateView(icon: "bolt", title: "No snippets", message: "Save commands you run often and send them to any session with one tap.") {
                        Button("Add Snippet") { editing = Snippet(title: "", command: "") }
                            .buttonStyle(.borderedProminent)
                    }
                } else {
                    List {
                        ForEach(store.snippets) { snippet in
                            Button {
                                editing = snippet
                            } label: {
                                VStack(alignment: .leading, spacing: 3) {
                                    Text(snippet.title).font(.headline).foregroundStyle(.primary)
                                    Text(snippet.command)
                                        .font(.system(.footnote, design: .monospaced))
                                        .foregroundStyle(.secondary)
                                        .lineLimit(2)
                                }
                            }
                        }
                        .onDelete { offsets in store.snippets.remove(atOffsets: offsets) }
                        .onMove { source, destination in store.snippets.move(fromOffsets: source, toOffset: destination) }
                    }
                    .toolbar {
                        ToolbarItem(placement: .navigationBarLeading) { EditButton() }
                    }
                }
            }
            .navigationTitle("Snippets")
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button {
                        editing = Snippet(title: "", command: "")
                    } label: {
                        Image(systemName: "plus")
                    }
                    .accessibilityLabel("Add snippet")
                }
            }
            .sheet(item: $editing) { snippet in
                SnippetEditView(snippet: snippet)
            }
        }
    }
}

struct SnippetEditView: View {
    @EnvironmentObject var store: AppStore
    @Environment(\.dismiss) private var dismiss
    @State private var snippet: Snippet

    init(snippet: Snippet) {
        _snippet = State(initialValue: snippet)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Title") {
                    TextField("e.g. Restart nginx", text: $snippet.title)
                }
                Section {
                    TextField("Command", text: $snippet.command, axis: .vertical)
                        .font(.system(.body, design: .monospaced))
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .lineLimit(1...6)
                    Toggle("Press Return after sending", isOn: $snippet.sendReturn)
                } header: {
                    Text("Command")
                } footer: {
                    Text("Turn off Return to type the command without running it, so you can add arguments first.")
                }
            }
            .navigationTitle("Snippet")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { save() }
                        .disabled(snippet.command.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
        }
    }

    private func save() {
        var clean = snippet
        clean.title = snippet.title.trimmingCharacters(in: .whitespaces)
        if clean.title.isEmpty { clean.title = clean.command }
        if let index = store.snippets.firstIndex(where: { $0.id == clean.id }) {
            store.snippets[index] = clean
        } else {
            store.snippets.append(clean)
        }
        dismiss()
    }
}
