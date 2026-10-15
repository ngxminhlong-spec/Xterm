import SwiftUI
import LocalAuthentication

struct RootView: View {
    @EnvironmentObject var manager: SessionManager
    @Environment(\.scenePhase) private var scenePhase

    @AppStorage("biometricLock") private var lockEnabled = false
    @AppStorage("keepAwake") private var keepAwake = false

    @State private var locked = false
    @State private var backgroundedAt: Date?

    var body: some View {
        TabView(selection: $manager.tab) {
            HostsView()
                .tabItem { Label("Hosts", systemImage: "server.rack") }
                .tag(AppTab.hosts)
            TerminalTabView()
                .tabItem { Label("Terminal", systemImage: "terminal") }
                .tag(AppTab.terminal)
            KeysView()
                .tabItem { Label("Keys", systemImage: "key") }
                .tag(AppTab.keys)
            SnippetsView()
                .tabItem { Label("Snippets", systemImage: "bolt") }
                .tag(AppTab.snippets)
            SettingsView()
                .tabItem { Label("Settings", systemImage: "gearshape") }
                .tag(AppTab.settings)
        }
        .overlay {
            if lockEnabled && (locked || scenePhase != .active) {
                LockCover(showUnlock: locked) { authenticate() }
            }
        }
        .onAppear {
            UIApplication.shared.isIdleTimerDisabled = keepAwake
            if lockEnabled {
                locked = true
                authenticate()
            }
        }
        .onChange(of: keepAwake) { value in
            UIApplication.shared.isIdleTimerDisabled = value
        }
        .onChange(of: scenePhase) { phase in
            switch phase {
            case .background:
                backgroundedAt = Date()
            case .active:
                if lockEnabled, let left = backgroundedAt, Date().timeIntervalSince(left) > 5 {
                    locked = true
                }
                backgroundedAt = nil
                if locked && lockEnabled { authenticate() }
            default:
                break
            }
        }
    }

    private func authenticate() {
        let context = LAContext()
        var error: NSError?
        guard context.canEvaluatePolicy(.deviceOwnerAuthentication, error: &error) else {
            locked = false
            return
        }
        context.evaluatePolicy(.deviceOwnerAuthentication, localizedReason: "Unlock Portico") { success, _ in
            if success {
                Task { @MainActor in locked = false }
            }
        }
    }
}

struct LockCover: View {
    let showUnlock: Bool
    let onUnlock: () -> Void

    var body: some View {
        ZStack {
            Rectangle().fill(.background).ignoresSafeArea()
            VStack(spacing: 16) {
                Image(systemName: "lock.fill")
                    .font(.system(size: 44))
                    .foregroundStyle(.secondary)
                Text("Portico is locked").font(.headline)
                if showUnlock {
                    Button("Unlock", action: onUnlock)
                        .buttonStyle(.borderedProminent)
                }
            }
        }
    }
}
