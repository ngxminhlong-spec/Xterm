import SwiftUI

@main
struct PorticoApp: App {
    @StateObject private var store = AppStore()
    @StateObject private var sessions = SessionManager()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(store)
                .environmentObject(sessions)
        }
    }
}
