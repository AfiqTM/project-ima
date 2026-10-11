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

    /// Finds a name in already-scraped page text ("Hello, Name ..." or an all-caps "... BIN/BINTI ..." line).
    static func extract(from text: String) -> String? {
        if let r = text.range(of: #"Hello,?\s*([^\n\r]+)"#, options: [.regularExpression, .caseInsensitive]) {
            let m = String(text[r]).replacingOccurrences(of: #"^Hello,?\s*"#, with: "", options: [.regularExpression, .caseInsensitive])
            if !m.isEmpty, m.count < 80 { return m }
        }
        for line in text.components(separatedBy: .newlines) {
            let l = line.trimmingCharacters(in: .whitespaces)
            if l.count < 80, l.range(of: #"^[A-Z][A-Z'.@/ -]+$"#, options: .regularExpression) != nil,
               l.range(of: #"\b(BIN|BINTI|BT|A/L|A/P)\b"#, options: .regularExpression) != nil { return l }
        }
        return nil
    }

    /// Call this wherever the app learns the student's name.
    static func save(_ name: String) {
        let n = name.trimmingCharacters(in: .whitespacesAndNewlines)
        if !n.isEmpty { UserDefaults.standard.set(n, forKey: key) }
    }
}


extension UserName {
    /// "MUHAMMAD AFIQ BIN ABDUL" -> "Muhammad Afiq"
    static func shortName(_ full: String) -> String {
        full.split(separator: " ").prefix(2).map { String($0).capitalized }.joined(separator: " ")
    }
}

// "Hello," in muted text, the name in bold accent.
struct GreetingTitle: View {
    let name: String
    var subtitle: String? = nil
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            (Text(name.isEmpty ? "Hello" : "Hello, ").foregroundColor(Theme.muted)
             + Text(name).foregroundColor(Theme.accent).bold())
                .font(.system(size: 28))
            if let s = subtitle, !s.isEmpty {
                Text(s).font(.system(size: 13)).foregroundColor(Theme.muted)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

// MARK: - Reads "Hello, <name>" from the logged-in i-Ma'luum page (shares the login cookies)

import WebKit

final class NameFetcher: NSObject, WKNavigationDelegate {
    static let shared = NameFetcher()

    private var web: WKWebView?
    private var running = false
    private var urls: [URL] = []
    private var attempts = 0

    func fetchIfNeeded() {
        guard !running, (UserDefaults.standard.string(forKey: UserName.key) ?? "").isEmpty else { return }
        running = true
        urls = [Endpoints.base, Endpoints.schedule]
        loadNext()
    }

    private func loadNext() {
        guard !urls.isEmpty else { finish(); return }
        attempts = 0
        let cfg = WKWebViewConfiguration()
        cfg.websiteDataStore = .default()
        let w = WKWebView(frame: CGRect(x: 0, y: 0, width: 1280, height: 900), configuration: cfg)
        w.navigationDelegate = self
        web = w
        w.load(URLRequest(url: urls.removeFirst()))
    }

    private func finish() {
        web = nil
        running = false
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        probe(webView)
    }

    private func probe(_ w: WKWebView) {
        let js = #"""
        (function(){
          function norm(s){ return (s||'').replace(/\s+/g,' ').trim(); }
          function ok(s){
            s = norm(s);
            return (s.length>=6 && s.length<80 && s.indexOf(' ')>0 && /^[A-Z][A-Z'.@\/ -]+$/.test(s)) ? s : null;
          }
          function own(e){
            var t='';
            for (var k=0;k<e.childNodes.length;k++){ if (e.childNodes[k].nodeType===3) t+=e.childNodes[k].nodeValue; }
            return t;
          }
          // 1) the name in the top bar (upper-right, next to the avatar): last all-caps text in nav/header
          var scopes = document.querySelectorAll('nav, header, .navbar, .main-header, .topbar, .app-header');
          for (var i=0;i<scopes.length;i++){
            var els = scopes[i].querySelectorAll('*');
            for (var j=els.length-1;j>=0;j--){
              var v = ok(own(els[j]));
              if (v) return v;
            }
          }
          // 2) "Hello, Name" anywhere
          var t = document.body ? (document.body.textContent || '') : '';
          var m = t.match(/Hello,?\s*([^\n\r]+)/i);
          if (m && m[1].trim()) return norm(m[1]);
          // 3) first all-caps line containing BIN / BINTI etc.
          var lines = t.split(/\n/);
          for (var n=0;n<lines.length;n++){
            var L = ok(lines[n]);
            if (L && /\b(BIN|BINTI|BT|A\/L|A\/P)\b/.test(L)) return L;
          }
          return '';
        })()
        """#
        w.evaluateJavaScript(js) { [weak self, weak w] result, _ in
            guard let self = self, let w = w, self.web === w else { return }
            if let name = result as? String, !name.isEmpty, name.count < 80 {
                UserName.save(name)
                self.finish()
                return
            }
            self.attempts += 1
            if self.attempts < 4 {
                // the page may still be rendering
                DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) { [weak self, weak w] in
                    if let self = self, let w = w, self.web === w { self.probe(w) }
                }
            } else {
                self.loadNext()
            }
        }
    }
}


// MARK: - Liquid glass

/// Space to leave at the bottom of scrolling screens so content clears the floating tab bar.
let tabBarInset: CGFloat = 80

extension View {
    @ViewBuilder
    func liquidGlass<S: InsettableShape>(in shape: S) -> some View {
        #if compiler(>=6.2)
        if #available(iOS 26.0, *) {
            self.glassEffect(.regular.interactive(), in: shape)
        } else {
            self.frostedGlass(in: shape)
        }
        #else
        self.frostedGlass(in: shape)
        #endif
    }

    func frostedGlass<S: InsettableShape>(in shape: S) -> some View {
        self
            .background(.ultraThinMaterial, in: shape)
            .background(shape.fill(Color.white.opacity(0.04)))
            .overlay(
                shape.strokeBorder(
                    LinearGradient(colors: [Color.white.opacity(0.35), Color.white.opacity(0.06), Color.white.opacity(0.18)],
                                   startPoint: .topLeading, endPoint: .bottomTrailing),
                    lineWidth: 0.8)
            )
    }
}
