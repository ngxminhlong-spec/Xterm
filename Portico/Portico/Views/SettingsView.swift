import SwiftUI
import LocalAuthentication

struct SettingsView: View {
    @EnvironmentObject var manager: SessionManager

    @AppStorage("themeName") private var themeName = TerminalTheme.midnight.name
    @AppStorage("fontName") private var fontName = "Menlo"
    @AppStorage("fontSize") private var fontSize = TerminalAppearance.defaultFontSize
    @AppStorage("keepAwake") private var keepAwake = false
    @AppStorage("biometricLock") private var biometricLock = false

    @State private var lockUnavailable = false

    var body: some View {
        NavigationStack {
            Form {
                Section("Appearance") {
                    Picker("Theme", selection: $themeName) {
                        ForEach(TerminalTheme.all) { theme in
                            Text(theme.name).tag(theme.name)
                        }
                    }
                    ThemePreview(theme: TerminalTheme.named(themeName), fontName: fontName, fontSize: fontSize)
                        .listRowInsets(EdgeInsets())
                    Picker("Font", selection: $fontName) {
                        ForEach(TerminalFont.choices, id: \.self) { Text($0).tag($0) }
                    }
                    VStack(alignment: .leading) {
                        Text("Font size: \(Int(fontSize)) pt")
                        Slider(value: $fontSize, in: 9...24, step: 1)
                    }
                }

                Section("Terminal") {
                    Toggle("Keep screen awake", isOn: $keepAwake)
                }

                Section {
                    Toggle("Lock with Face ID / passcode", isOn: $biometricLock)
                } header: {
                    Text("Security")
                } footer: {
                    Text("Locks the app when you leave it, so your servers and keys stay private. Passwords and keys are stored in the iOS Keychain either way.")
                }

                Section("Trust") {
                    NavigationLink("Known Hosts") { KnownHostsView() }
                }

                Section("About") {
                    LabeledContent("Version", value: Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "1.0")
                    Text("Portico is built on Citadel (SSH) and SwiftTerm (terminal emulation), both MIT licensed.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
            .navigationTitle("Settings")
            .onChange(of: themeName) { _ in manager.reapplyAppearance() }
            .onChange(of: fontName) { _ in manager.reapplyAppearance() }
            .onChange(of: fontSize) { _ in manager.reapplyAppearance() }
            .onChange(of: biometricLock) { enabled in
                if enabled {
                    var error: NSError?
                    if !LAContext().canEvaluatePolicy(.deviceOwnerAuthentication, error: &error) {
                        biometricLock = false
                        lockUnavailable = true
                    }
                }
            }
            .alert("Can't enable lock", isPresented: $lockUnavailable) {
                Button("OK", role: .cancel) {}
            } message: {
                Text("Set a device passcode (or Face ID) in iOS Settings first.")
            }
        }
    }
}

struct ThemePreview: View {
    let theme: TerminalTheme
    let fontName: String
    let fontSize: Double

    private var font: Font {
        let size = min(max(fontSize, 10), 16)
        return fontName == "SF Mono" ? .system(size: size, design: .monospaced) : .custom(fontName == "Courier New" ? "CourierNewPSMT" : "Menlo-Regular", size: size)
    }

    private func swatch(_ hex: String) -> some View {
        Rectangle().fill(Color(uiColor: UIColor(hex: hex))).frame(height: 10)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 0) {
                Text("you@server").foregroundColor(Color(uiColor: UIColor(hex: theme.ansi[10])))
                Text(":").foregroundColor(Color(uiColor: theme.foregroundColor))
                Text("~/code").foregroundColor(Color(uiColor: UIColor(hex: theme.ansi[12])))
                Text("$ ls -la").foregroundColor(Color(uiColor: theme.foregroundColor))
            }
            Text("drwxr-xr-x  src   README.md")
                .foregroundColor(Color(uiColor: UIColor(hex: theme.ansi[6])))
            Text("error: permission denied")
                .foregroundColor(Color(uiColor: UIColor(hex: theme.ansi[1])))
            HStack(spacing: 0) {
                ForEach(0..<8, id: \.self) { swatch(theme.ansi[$0]) }
            }
            HStack(spacing: 0) {
                ForEach(8..<16, id: \.self) { swatch(theme.ansi[$0]) }
            }
        }
        .font(font)
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(uiColor: theme.backgroundColor))
    }
}

struct KnownHostsView: View {
    @State private var entries: [KnownHosts.Entry] = KnownHosts.shared.all()

    var body: some View {
        List {
            if entries.isEmpty {
                Text("No hosts have been trusted yet. A host is added the first time you connect to it.")
                    .foregroundStyle(.secondary)
            }
            ForEach(entries) { entry in
                VStack(alignment: .leading, spacing: 3) {
                    Text(entry.hostID).font(.headline)
                    Text(entry.fingerprint)
                        .font(.system(.caption, design: .monospaced))
                        .foregroundStyle(.secondary)
                        .textSelection(.enabled)
                    Text("Added \(entry.added.formatted(date: .abbreviated, time: .omitted))")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
            }
            .onDelete { offsets in
                for index in offsets {
                    KnownHosts.shared.remove(hostID: entries[index].hostID)
                }
                entries = KnownHosts.shared.all()
            }
        }
        .navigationTitle("Known Hosts")
        .navigationBarTitleDisplayMode(.inline)
    }
}
