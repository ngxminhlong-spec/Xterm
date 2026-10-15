import SwiftUI
import UniformTypeIdentifiers
import Citadel
import NIOCore

struct Breadcrumb: Hashable {
    let title: String
    let path: String
}

struct SFTPItem: Identifiable, Hashable {
    var id: String { name }
    let name: String
    let isDirectory: Bool
    let isLink: Bool
    let size: UInt64?
    let modified: Date?
}

@MainActor
final class SFTPModel: ObservableObject {
    @Published var path = "/"
    @Published var items: [SFTPItem] = []
    @Published var loading = true
    @Published var busyMessage: String?
    @Published var errorMessage: String?
    @Published var shareURL: URL?

    private var sftp: SFTPClient?
    private let connection: SSHTerminalConnection

    init(connection: SSHTerminalConnection) {
        self.connection = connection
    }

    func start() async {
        loading = true
        do {
            let client = try await connection.openSFTP()
            sftp = client
            path = try await client.getRealPath(atPath: ".")
            try await reload()
        } catch {
            errorMessage = "Couldn't open the file browser: \(describeConnectionError(error))"
        }
        loading = false
    }

    func stop() {
        let client = sftp
        sftp = nil
        Task { try? await client?.close() }
    }

    private func reload() async throws {
        guard let sftp else { return }
        let listing = try await sftp.listDirectory(atPath: path)
        var result: [SFTPItem] = []
        for name in listing {
            for component in name.components {
                let filename = component.filename
                if filename == "." || filename == ".." { continue }
                let permissions = component.attributes.permissions ?? 0
                let kind = permissions & 0o170000
                let isLink = kind == 0o120000
                let isDirectory = kind == 0o040000 || component.longname.hasPrefix("d")
                result.append(SFTPItem(
                    name: filename,
                    isDirectory: isDirectory,
                    isLink: isLink,
                    size: component.attributes.size,
                    modified: component.attributes.accessModificationTime?.modificationTime
                ))
            }
        }
        items = result.sorted { a, b in
            if a.isDirectory != b.isDirectory { return a.isDirectory }
            return a.name.localizedCaseInsensitiveCompare(b.name) == .orderedAscending
        }
    }

    func refresh() async {
        await run("Loading…") { try await self.reload() }
    }

    func open(_ item: SFTPItem) async {
        guard item.isDirectory || item.isLink else { return }
        let previous = path
        path = join(path, item.name)
        do {
            try await reload()
        } catch {
            // A symlink to a file (or a permission error): stay where we were.
            path = previous
            if item.isDirectory { errorMessage = describeConnectionError(error) }
        }
    }

    func goUp() async {
        path = parent(of: path)
        await refresh()
    }

    func goTo(_ newPath: String) async {
        path = newPath
        await refresh()
    }

    func download(_ item: SFTPItem) async {
        guard let sftp else { return }
        let remote = join(path, item.name)
        await run("Downloading \(item.name)…") {
            let buffer = try await sftp.withFile(filePath: remote, flags: .read) { file in
                try await file.readAll()
            }
            let url = FileManager.default.temporaryDirectory.appendingPathComponent(item.name)
            try Data(buffer.readableBytesView).write(to: url, options: .atomic)
            self.shareURL = url
        }
    }

    func upload(from localURL: URL) async {
        guard let sftp else { return }
        let accessed = localURL.startAccessingSecurityScopedResource()
        defer { if accessed { localURL.stopAccessingSecurityScopedResource() } }

        guard let data = try? Data(contentsOf: localURL) else {
            errorMessage = "Couldn't read that file."
            return
        }
        let remote = join(path, localURL.lastPathComponent)
        await run("Uploading \(localURL.lastPathComponent)…") {
            try await sftp.withFile(filePath: remote, flags: [.write, .create, .truncate]) { file in
                let chunkSize = 128 * 1024
                var index = 0
                var offset: UInt64 = 0
                while index < data.count {
                    let end = min(index + chunkSize, data.count)
                    try await file.write(ByteBuffer(bytes: data[index..<end]), at: offset)
                    offset += UInt64(end - index)
                    index = end
                }
            }
            try await self.reload()
        }
    }

    func delete(_ item: SFTPItem) async {
        guard let sftp else { return }
        let remote = join(path, item.name)
        await run("Deleting…") {
            if item.isDirectory && !item.isLink {
                try await sftp.rmdir(at: remote)
            } else {
                try await sftp.remove(at: remote)
            }
            try await self.reload()
        }
    }

    func rename(_ item: SFTPItem, to newName: String) async {
        guard let sftp, !newName.isEmpty else { return }
        await run("Renaming…") {
            try await sftp.rename(at: self.join(self.path, item.name), to: self.join(self.path, newName))
            try await self.reload()
        }
    }

    func makeDirectory(named name: String) async {
        guard let sftp, !name.isEmpty else { return }
        await run("Creating folder…") {
            try await sftp.createDirectory(atPath: self.join(self.path, name))
            try await self.reload()
        }
    }

    // MARK: Helpers

    private func run(_ message: String, _ work: @escaping () async throws -> Void) async {
        busyMessage = message
        do {
            try await work()
        } catch {
            errorMessage = describeConnectionError(error)
        }
        busyMessage = nil
    }

    func join(_ directory: String, _ name: String) -> String {
        directory.hasSuffix("/") ? directory + name : directory + "/" + name
    }

    func parent(of path: String) -> String {
        var parts = path.split(separator: "/").map(String.init)
        if !parts.isEmpty { parts.removeLast() }
        return "/" + parts.joined(separator: "/")
    }

    var breadcrumbs: [Breadcrumb] {
        var crumbs = [Breadcrumb(title: "/", path: "/")]
        var current = ""
        for part in path.split(separator: "/") {
            current += "/" + part
            crumbs.append(Breadcrumb(title: String(part), path: current))
        }
        return crumbs
    }
}

struct SFTPBrowserView: View {
    @Environment(\.dismiss) private var dismiss
    @StateObject private var model: SFTPModel

    private enum NameAction {
        case newFolder
        case rename(SFTPItem)
    }

    @State private var showUploader = false
    @State private var nameAction: NameAction?
    @State private var showNameAlert = false
    @State private var nameText = ""
    @State private var deleteTarget: SFTPItem?

    init(connection: SSHTerminalConnection) {
        _model = StateObject(wrappedValue: SFTPModel(connection: connection))
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                breadcrumbBar
                content
            }
            .navigationTitle("Files")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { dismiss() }
                }
                ToolbarItemGroup(placement: .navigationBarTrailing) {
                    Button {
                        askName(.newFolder, initial: "")
                    } label: {
                        Image(systemName: "folder.badge.plus")
                    }
                    Button {
                        showUploader = true
                    } label: {
                        Image(systemName: "square.and.arrow.up")
                    }
                }
            }
            .overlay(alignment: .bottom) {
                if let message = model.busyMessage {
                    HStack(spacing: 8) {
                        ProgressView()
                        Text(message).font(.footnote)
                    }
                    .padding(.horizontal, 14)
                    .padding(.vertical, 10)
                    .background(.ultraThinMaterial, in: Capsule())
                    .padding(.bottom, 16)
                }
            }
            .fileImporter(isPresented: $showUploader, allowedContentTypes: [.item]) { result in
                if case .success(let url) = result {
                    Task { await model.upload(from: url) }
                }
            }
            .alert(nameAlertTitle, isPresented: $showNameAlert) {
                TextField("Name", text: $nameText)
                Button("OK") { commitName() }
                Button("Cancel", role: .cancel) {}
            }
            .confirmationDialog(
                "Delete \(deleteTarget?.name ?? "item")?",
                isPresented: Binding(get: { deleteTarget != nil }, set: { if !$0 { deleteTarget = nil } }),
                titleVisibility: .visible
            ) {
                Button("Delete", role: .destructive) {
                    if let target = deleteTarget {
                        Task { await model.delete(target) }
                    }
                    deleteTarget = nil
                }
            }
            .sheet(item: Binding(
                get: { model.shareURL.map { ShareItem(url: $0) } },
                set: { if $0 == nil { model.shareURL = nil } }
            )) { item in
                ShareSheet(items: [item.url])
            }
        }
        .alert(
            "Files",
            isPresented: Binding(get: { model.errorMessage != nil }, set: { if !$0 { model.errorMessage = nil } })
        ) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(model.errorMessage ?? "")
        }
        .task { await model.start() }
        .onDisappear { model.stop() }
    }

    private var nameAlertTitle: String {
        if case .rename? = nameAction { return "Rename" }
        return "New folder"
    }

    private func askName(_ action: NameAction, initial: String) {
        nameAction = action
        nameText = initial
        showNameAlert = true
    }

    private func commitName() {
        let name = nameText.trimmingCharacters(in: .whitespaces)
        guard let action = nameAction else { return }
        switch action {
        case .newFolder:
            Task { await model.makeDirectory(named: name) }
        case .rename(let item):
            Task { await model.rename(item, to: name) }
        }
    }

    private var breadcrumbBar: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 4) {
                ForEach(Array(model.breadcrumbs.enumerated()), id: \.offset) { index, crumb in
                    if index > 0 {
                        Image(systemName: "chevron.right").font(.caption2).foregroundStyle(.tertiary)
                    }
                    Button(crumb.title) {
                        Task { await model.goTo(crumb.path) }
                    }
                    .font(.footnote.weight(index == model.breadcrumbs.count - 1 ? .semibold : .regular))
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
        }
        .background(.bar)
    }

    @ViewBuilder
    private var content: some View {
        if model.loading {
            VStack { Spacer(); ProgressView("Opening…"); Spacer() }
        } else {
            List {
                if model.path != "/" {
                    Button {
                        Task { await model.goUp() }
                    } label: {
                        Label("..", systemImage: "arrow.turn.left.up")
                    }
                }
                ForEach(model.items) { item in
                    row(item)
                }
            }
            .listStyle(.plain)
            .refreshable { await model.refresh() }
            .overlay {
                if model.items.isEmpty && model.busyMessage == nil {
                    Text("Empty folder").foregroundStyle(.secondary)
                }
            }
        }
    }

    private func row(_ item: SFTPItem) -> some View {
        Button {
            if item.isDirectory || item.isLink {
                Task { await model.open(item) }
            } else {
                Task { await model.download(item) }
            }
        } label: {
            HStack(spacing: 12) {
                Image(systemName: item.isDirectory ? "folder.fill" : (item.isLink ? "link" : "doc"))
                    .foregroundStyle(item.isDirectory ? Color.accentColor : Color.secondary)
                    .frame(width: 26)
                VStack(alignment: .leading, spacing: 2) {
                    Text(item.name).foregroundStyle(.primary).lineLimit(1)
                    if let detail = detail(for: item) {
                        Text(detail).font(.caption).foregroundStyle(.secondary)
                    }
                }
                Spacer()
                if !item.isDirectory && !item.isLink {
                    Image(systemName: "arrow.down.circle").foregroundStyle(.tertiary)
                }
            }
        }
        .swipeActions(edge: .trailing) {
            Button("Delete", role: .destructive) { deleteTarget = item }
            Button("Rename") { askName(.rename(item), initial: item.name) }
                .tint(.blue)
        }
        .contextMenu {
            if !item.isDirectory {
                LabelButton("Download & share", "square.and.arrow.down") {
                    Task { await model.download(item) }
                }
            }
            LabelButton("Rename", "pencil") { askName(.rename(item), initial: item.name) }
            LabelButton("Delete", "trash", role: .destructive) { deleteTarget = item }
        }
    }

    private func detail(for item: SFTPItem) -> String? {
        var parts: [String] = []
        if !item.isDirectory, let size = item.size {
            parts.append(ByteCountFormatter.string(fromByteCount: Int64(size), countStyle: .file))
        }
        if let modified = item.modified {
            parts.append(modified.formatted(date: .abbreviated, time: .shortened))
        }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }
}

struct ShareItem: Identifiable {
    let url: URL
    var id: String { url.absoluteString }
}

struct ShareSheet: UIViewControllerRepresentable {
    let items: [Any]

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: items, applicationActivities: nil)
    }

    func updateUIViewController(_ controller: UIActivityViewController, context: Context) {}
}
