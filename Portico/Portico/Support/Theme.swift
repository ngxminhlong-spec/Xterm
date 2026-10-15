import UIKit
import SwiftTerm

struct TerminalTheme: Identifiable, Hashable {
    let name: String
    let background: String
    let foreground: String
    let cursor: String
    /// 16 ANSI colors: 8 normal followed by 8 bright.
    let ansi: [String]

    var id: String { name }

    var backgroundColor: UIColor { UIColor(hex: background) }
    var foregroundColor: UIColor { UIColor(hex: foreground) }
    var cursorColor: UIColor { UIColor(hex: cursor) }

    static let all: [TerminalTheme] = [midnight, black, dracula, nord, gruvbox, solarizedDark, paper]

    static func named(_ name: String) -> TerminalTheme {
        all.first { $0.name == name } ?? midnight
    }

    static let midnight = TerminalTheme(
        name: "Midnight", background: "#0B0F14", foreground: "#D6DEEB", cursor: "#82AAFF",
        ansi: ["#1D2733", "#F07178", "#C3E88D", "#FFCB6B", "#82AAFF", "#C792EA", "#89DDFF", "#D6DEEB",
               "#546E7A", "#FF8A92", "#D4F5A6", "#FFD98A", "#A3C1FF", "#DDB1F5", "#A8EAFF", "#FFFFFF"])

    static let black = TerminalTheme(
        name: "Pure Black", background: "#000000", foreground: "#E5E5E5", cursor: "#FFFFFF",
        ansi: ["#000000", "#CD3131", "#0DBC79", "#E5E510", "#2472C8", "#BC3FBC", "#11A8CD", "#E5E5E5",
               "#666666", "#F14C4C", "#23D18B", "#F5F543", "#3B8EEA", "#D670D6", "#29B8DB", "#FFFFFF"])

    static let dracula = TerminalTheme(
        name: "Dracula", background: "#282A36", foreground: "#F8F8F2", cursor: "#F8F8F2",
        ansi: ["#21222C", "#FF5555", "#50FA7B", "#F1FA8C", "#BD93F9", "#FF79C6", "#8BE9FD", "#F8F8F2",
               "#6272A4", "#FF6E6E", "#69FF94", "#FFFFA5", "#D6ACFF", "#FF92DF", "#A4FFFF", "#FFFFFF"])

    static let nord = TerminalTheme(
        name: "Nord", background: "#2E3440", foreground: "#D8DEE9", cursor: "#D8DEE9",
        ansi: ["#3B4252", "#BF616A", "#A3BE8C", "#EBCB8B", "#81A1C1", "#B48EAD", "#88C0D0", "#E5E9F0",
               "#4C566A", "#BF616A", "#A3BE8C", "#EBCB8B", "#81A1C1", "#B48EAD", "#8FBCBB", "#ECEFF4"])

    static let gruvbox = TerminalTheme(
        name: "Gruvbox", background: "#282828", foreground: "#EBDBB2", cursor: "#EBDBB2",
        ansi: ["#282828", "#CC241D", "#98971A", "#D79921", "#458588", "#B16286", "#689D6A", "#A89984",
               "#928374", "#FB4934", "#B8BB26", "#FABD2F", "#83A598", "#D3869B", "#8EC07C", "#EBDBB2"])

    static let solarizedDark = TerminalTheme(
        name: "Solarized Dark", background: "#002B36", foreground: "#839496", cursor: "#93A1A1",
        ansi: ["#073642", "#DC322F", "#859900", "#B58900", "#268BD2", "#D33682", "#2AA198", "#EEE8D5",
               "#002B36", "#CB4B16", "#586E75", "#657B83", "#839496", "#6C71C4", "#93A1A1", "#FDF6E3"])

    static let paper = TerminalTheme(
        name: "Paper", background: "#FAFAFA", foreground: "#383A42", cursor: "#526FFF",
        ansi: ["#383A42", "#E45649", "#50A14F", "#C18401", "#4078F2", "#A626A4", "#0184BC", "#A0A1A7",
               "#4F525E", "#E06C75", "#98C379", "#E5C07B", "#61AFEF", "#C678DD", "#56B6C2", "#FFFFFF"])
}

/// Parses "#RRGGBB" into 8-bit components.
func rgb8(hex: String) -> (r: UInt16, g: UInt16, b: UInt16) {
    var value = hex.trimmingCharacters(in: CharacterSet(charactersIn: "#"))
    if value.count != 6 { value = "000000" }
    var rgb: UInt64 = 0
    Scanner(string: value).scanHexInt64(&rgb)
    return (UInt16((rgb >> 16) & 0xFF), UInt16((rgb >> 8) & 0xFF), UInt16(rgb & 0xFF))
}

extension UIColor {
    convenience init(hex: String) {
        let c = rgb8(hex: hex)
        self.init(red: CGFloat(c.r) / 255, green: CGFloat(c.g) / 255, blue: CGFloat(c.b) / 255, alpha: 1)
    }
}

enum TerminalFont {
    static let choices = ["Menlo", "Courier New", "SF Mono"]

    static func make(name: String, size: CGFloat) -> UIFont {
        switch name {
        case "SF Mono":
            return UIFont.monospacedSystemFont(ofSize: size, weight: .regular)
        case "Courier New":
            return UIFont(name: "CourierNewPSMT", size: size) ?? UIFont(name: "Menlo-Regular", size: size)
                ?? UIFont.monospacedSystemFont(ofSize: size, weight: .regular)
        default:
            return UIFont(name: "Menlo-Regular", size: size)
                ?? UIFont.monospacedSystemFont(ofSize: size, weight: .regular)
        }
    }
}

/// Applies the user's theme/font preferences (stored in UserDefaults) to a terminal view.
enum TerminalAppearance {
    static let defaultFontSize: Double = 14

    @MainActor
    static func apply(to view: TerminalView) {
        let defaults = UserDefaults.standard
        let theme = TerminalTheme.named(defaults.string(forKey: "themeName") ?? TerminalTheme.midnight.name)
        let fontName = defaults.string(forKey: "fontName") ?? "Menlo"
        let storedSize = defaults.double(forKey: "fontSize")
        let size = storedSize > 0 ? storedSize : defaultFontSize

        view.font = TerminalFont.make(name: fontName, size: CGFloat(size))
        view.installColors(theme.ansi.map { hex -> SwiftTerm.Color in
            let c = rgb8(hex: hex)
            return SwiftTerm.Color(red8: c.r, green8: c.g, blue8: c.b)
        })
        view.nativeBackgroundColor = theme.backgroundColor
        view.nativeForegroundColor = theme.foregroundColor
        view.caretColor = theme.cursorColor
        view.backgroundColor = theme.backgroundColor
    }
}
