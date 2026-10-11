import SwiftUI

// Shared building blocks for the AMOLED redesign. Uses only the palette in Theme.swift.

extension Theme {
    static let good = Color(hex: 0x8FBF9F)   // registered / pass
    static let bad  = Color(hex: 0xE5837F)   // fail / error
}

// Flat card: #060606 surface with a 1px #1c1c1c hairline. Cheap enough for long lists.
// Use .glowCard() (Theme.swift) only for hero cards.
struct FlatCard: ViewModifier {
    var radius: CGFloat
    var padding: CGFloat
    var highlighted: Bool
    func body(content: Content) -> some View {
        content
            .padding(padding)
            .background(Theme.surface)
            .clipShape(RoundedRectangle(cornerRadius: radius, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: radius, style: .continuous)
                    .strokeBorder(highlighted ? Theme.accent.opacity(0.45) : Theme.line, lineWidth: 1)
            )
    }
}

extension View {
    func card(_ radius: CGFloat = 14, padding: CGFloat = 16, highlighted: Bool = false) -> some View {
        modifier(FlatCard(radius: radius, padding: padding, highlighted: highlighted))
    }
    func screenBackground() -> some View { background(Theme.bg.ignoresSafeArea()) }
}

// MARK: - Text pieces

struct PageTitle: View {
    let title: String
    var subtitle: String? = nil
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.system(size: 30, weight: .bold))
                .foregroundColor(Theme.txt)
            if let s = subtitle, !s.isEmpty {
                Text(s)
                    .font(.system(size: 13))
                    .foregroundColor(Theme.muted)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

struct SectionLabel: View {
    let text: String
    init(_ text: String) { self.text = text }
    var body: some View {
        Text(text.uppercased())
            .font(.system(size: 11, weight: .semibold))
            .tracking(0.9)
            .foregroundColor(Theme.muted)
    }
}

struct CodeTag: View {
    let text: String
    var body: some View {
        Text(text)
            .font(.system(size: 12, weight: .semibold, design: .monospaced))
            .foregroundColor(Theme.accent)
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(RoundedRectangle(cornerRadius: 6, style: .continuous).fill(Theme.accent.opacity(0.12)))
            .overlay(RoundedRectangle(cornerRadius: 6, style: .continuous).strokeBorder(Theme.accent.opacity(0.35), lineWidth: 1))
            .fixedSize()
    }
}

struct InfoRow: View {
    let icon: String
    let text: String
    var color: Color = Theme.txt
    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Image(systemName: icon)
                .font(.system(size: 12))
                .foregroundColor(Theme.muted)
                .frame(width: 16)
            Text(text)
                .font(.system(size: 14))
                .foregroundColor(color)
            Spacer(minLength: 0)
        }
    }
}

struct Hairline: View {
    var body: some View { Rectangle().fill(Theme.line).frame(height: 1) }
}

// MARK: - Buttons

struct AccentButtonStyle: ButtonStyle {
    var filled = true
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 14, weight: .semibold))
            .foregroundColor(filled ? Color.black : Theme.accent)
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
            .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(filled ? Theme.accent : Color.clear))
            .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous)
                .strokeBorder(Theme.accent, lineWidth: filled ? 0 : 1))
            .opacity(configuration.isPressed ? 0.7 : 1)
    }
}

// MARK: - Session dropdown (replaces SessionPill)

struct SessionMenu: View {
    let links: [PageLink]
    let onSelect: (URL) -> Void

    var body: some View {
        if !links.isEmpty {
            Menu {
                ForEach(links) { l in
                    Button(l.text) {
                        if let u = URL(string: l.href) { onSelect(u) }
                    }
                }
            } label: {
                HStack(spacing: 6) {
                    Text("Session")
                    Image(systemName: "chevron.up.chevron.down").font(.system(size: 10, weight: .bold))
                }
                .font(.system(size: 13, weight: .semibold))
                .foregroundColor(Theme.accent)
                .padding(.horizontal, 12)
                .padding(.vertical, 7)
                .background(Capsule().fill(Theme.surface2))
                .overlay(Capsule().strokeBorder(Theme.line, lineWidth: 1))
            }
        }
    }
}

// MARK: - Status panels (replace ErrorCard / OfflineBanner)

struct ErrorPanel: View {
    let message: String
    let retry: () -> Void
    let openWeb: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top, spacing: 10) {
                Image(systemName: "exclamationmark.triangle.fill").foregroundColor(Theme.bad)
                Text(message)
                    .font(.system(size: 14))
                    .foregroundColor(Theme.txt)
                Spacer(minLength: 0)
            }
            HStack(spacing: 10) {
                Button("Retry", action: retry).buttonStyle(AccentButtonStyle())
                Button("Open page", action: openWeb).buttonStyle(AccentButtonStyle(filled: false))
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .card(14)
    }
}

struct OfflineNotice: View {
    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "wifi.slash")
            Text("Offline. Showing saved data.")
        }
        .font(.system(size: 13, weight: .medium))
        .foregroundColor(Theme.muted)
        .frame(maxWidth: .infinity, alignment: .leading)
        .card(12, padding: 12)
    }
}


// MARK: - Signed-in user's name (stored once, shown as "Hello, First Second")

enum UserName {
    static let key = "userFullName"

    /// "MUHAMMAD AFIQ BIN ABDUL" -> "Hello, Muhammad Afiq"
    static func greeting(_ full: String) -> String {
        let words = full.split(separator: " ").prefix(2).map { String($0).capitalized }
        return words.isEmpty ? "Hello" : "Hello, " + words.joined(separator: " ")
    }

    /// Call this wherever the app learns the student's name.
    static func save(_ name: String) {
        let n = name.trimmingCharacters(in: .whitespacesAndNewlines)
        if !n.isEmpty { UserDefaults.standard.set(n, forKey: key) }
    }
}
