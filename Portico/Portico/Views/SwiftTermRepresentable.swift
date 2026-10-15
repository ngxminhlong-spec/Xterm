import SwiftUI
import SwiftTerm

/// Hosts the session's long-lived SwiftTerm view inside SwiftUI.
/// (Keep this file free of bare `Color` references: SwiftTerm also defines `Color`.)
struct SwiftTermRepresentable: UIViewRepresentable {
    let session: TerminalSession

    func makeUIView(context: Context) -> TerminalView {
        let view = session.terminalView
        onMain { _ = view.becomeFirstResponder() }
        return view
    }

    func updateUIView(_ uiView: TerminalView, context: Context) {}
}
