import SwiftUI

extension Color {
    init(hex: UInt32, opacity: Double = 1) {
        self.init(.sRGB,
                  red: Double((hex >> 16) & 0xFF) / 255,
                  green: Double((hex >> 8) & 0xFF) / 255,
                  blue: Double(hex & 0xFF) / 255,
                  opacity: opacity)
    }
}

enum Theme {
    /// Secondary colour requested: #9D846B
    static let accent = Color(hex: 0x9D846B)
    static let accentSoft = Color(hex: 0xC9B6A0)
    static let accentDeep = Color(hex: 0x6B5844)
    static let success = Color(hex: 0x5EE08A)
    static let textSecondary = Color.white.opacity(0.62)

    static var pillGradient: LinearGradient {
        LinearGradient(colors: [accentSoft, accent], startPoint: .topLeading, endPoint: .bottomTrailing)
    }
}

/// True-black background (OLED pixels fully off) with two faint accent glows.
struct AmoledBackground: View {
    var body: some View {
        Color.black
            .overlay(
                ZStack {
                    Circle().fill(Theme.accent.opacity(0.20))
                        .frame(width: 320, height: 320).blur(radius: 90)
                        .offset(x: 150, y: -280)
                    Circle().fill(Theme.accentDeep.opacity(0.22))
                        .frame(width: 300, height: 300).blur(radius: 100)
                        .offset(x: -170, y: 260)
                }
            )
            .clipped()
            .ignoresSafeArea()
    }
}

extension View {
    func amoled() -> some View { background(AmoledBackground()) }

    func glassCard(_ radius: CGFloat = 22) -> some View {
        self
            .padding(16)
            .background(
                RoundedRectangle(cornerRadius: radius, style: .continuous)
                    .fill(LinearGradient(colors: [Color.white.opacity(0.10), Color.white.opacity(0.03)],
                                         startPoint: .topLeading, endPoint: .bottomTrailing))
            )
            .overlay(
                RoundedRectangle(cornerRadius: radius, style: .continuous)
                    .strokeBorder(LinearGradient(colors: [Color.white.opacity(0.32), Color.white.opacity(0.04), Theme.accent.opacity(0.40)],
                                                 startPoint: .topLeading, endPoint: .bottomTrailing),
                                  lineWidth: 1)
            )
    }
}

struct CodePill: View {
    let text: String
    var body: some View {
        Text(text)
            .font(.system(size: 14, weight: .bold, design: .rounded))
            .foregroundColor(.black)
            .padding(.horizontal, 12)
            .padding(.vertical, 5)
            .background(Capsule().fill(Theme.pillGradient))
    }
}

struct ScreenHeader: View {
    let title: String
    var subtitle: String? = nil

    var body: some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.system(size: 30, weight: .bold, design: .rounded))
                    .foregroundColor(.white)
                if let s = subtitle, !s.isEmpty {
                    Text(s)
                        .font(.system(size: 17, weight: .medium, design: .rounded))
                        .foregroundColor(Theme.accentSoft)
                }
            }
            Spacer()
            AccountMenu()
        }
    }
}

struct AccountMenu: View {
    @ObservedObject private var session = WebSession.shared
    var body: some View {
        Menu {
            Button(role: .destructive) {
                Task { await session.signOut() }
            } label: {
                Label(session.state == .demo ? "Exit demo" : "Sign out",
                      systemImage: "rectangle.portrait.and.arrow.right")
            }
        } label: {
            Image(systemName: "person.crop.circle.fill")
                .font(.system(size: 30))
                .foregroundColor(Theme.accent)
        }
    }
}

struct SessionPill: View {
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
                    Text("Sem, Session")
                    Image(systemName: "chevron.down").font(.system(size: 11, weight: .bold))
                }
                .font(.system(size: 15, weight: .semibold, design: .rounded))
                .foregroundColor(.black)
                .padding(.horizontal, 18)
                .padding(.vertical, 10)
                .background(Capsule().fill(Theme.pillGradient))
            }
        }
    }
}

struct ErrorCard: View {
    let message: String
    let retry: () -> Void
    let openWeb: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("Couldn't load this page", systemImage: "exclamationmark.triangle.fill")
                .font(.system(size: 15, weight: .semibold, design: .rounded))
                .foregroundColor(Theme.accentSoft)
            Text(message)
                .font(.system(size: 13))
                .foregroundColor(Theme.textSecondary)
            HStack(spacing: 10) {
                Button("Retry", action: retry)
                    .buttonStyle(.borderedProminent)
                Button("Open in web view", action: openWeb)
                    .buttonStyle(.bordered)
            }
            .tint(Theme.accent)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassCard(18)
    }
}

struct OfflineBanner: View {
    var body: some View {
        Label("Offline — showing saved data", systemImage: "wifi.slash")
            .font(.system(size: 12, weight: .medium))
            .foregroundColor(Theme.accentSoft)
    }
}
