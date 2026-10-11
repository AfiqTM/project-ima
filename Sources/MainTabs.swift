import SwiftUI
import WebKit

enum AppTab: Int, CaseIterable, Identifiable {
    case classes, exams, services, disciplinary, coCurriculum
    var id: Int { rawValue }

    var icon: String {
        switch self {
        case .classes: return "calendar"
        case .exams: return "doc.text.fill"
        case .services: return "square.grid.2x2.fill"
        case .disciplinary: return "exclamationmark.shield.fill"
        case .coCurriculum: return "trophy.fill"
        }
    }

    var title: String {
        switch self {
        case .classes: return "Classes"
        case .exams: return "Exams"
        case .services: return "Services"
        case .disciplinary: return "Discipline"
        case .coCurriculum: return "Co-Curr"
        }
    }
}

struct MainTabs: View {
    @State private var tab: AppTab = .classes
    @State private var visited: Set<AppTab> = [.classes]

    var body: some View {
        ZStack {
            ForEach(AppTab.allCases) { t in
                if visited.contains(t) {
                    content(t)
                        .opacity(tab == t ? 1 : 0)
                        .allowsHitTesting(tab == t)
                        .accessibilityHidden(tab != t)
                }
            }
        }
        .overlay(alignment: .bottom) { AppTabBar(selection: $tab) }
        .onChange(of: tab) { newValue in visited.insert(newValue) }
    }

    @ViewBuilder
    private func content(_ t: AppTab) -> some View {
        switch t {
        case .classes: ClassesView()
        case .exams: ExamsView()
        case .services: SimplePageView(title: "My Services", keys: ["my services", "services"], extra: (title: "Others", keys: ["others"]))
        case .disciplinary: SimplePageView(title: "Disciplinary", keys: ["disciplinary"])
        case .coCurriculum: SimplePageView(title: "Co-Curriculum", keys: ["co-curriculum", "co-curricul"])
        }
    }
}

// Floating liquid-glass tab bar with a glass "lens" that follows your finger.
// Press and drag: the lens glides continuously and magnifies slightly; on release it settles on the nearest tab.
// Tapping glides the lens to that tab. Real glass on iOS 26 (Xcode 26 build), frosted fallback otherwise.
struct AppTabBar: View {
    @Binding var selection: AppTab
    @State private var dragX: CGFloat? = nil   // finger x while pressing, nil at rest
    @State private var lastIdx = 0
    private let pad: CGFloat = 6

    private func index(at x: CGFloat, itemW: CGFloat) -> Int {
        min(max(Int((x - pad) / itemW), 0), AppTab.allCases.count - 1)
    }

    var body: some View {
        GeometryReader { geo in
            let count = CGFloat(AppTab.allCases.count)
            let itemW = (geo.size.width - pad * 2) / count
            let lensH = geo.size.height - pad * 2
            let restX = pad + CGFloat(selection.rawValue) * itemW
            let lensX: CGFloat = {
                guard let d = dragX else { return restX }
                return min(max(d - itemW / 2, pad), geo.size.width - pad - itemW)
            }()
            let active = dragX != nil ? index(at: lensX + itemW / 2, itemW: itemW) : selection.rawValue

            GlassGroup {
                ZStack(alignment: .leading) {
                    // the bar
                    GlassCapsule(interactive: true)
                        .frame(width: geo.size.width, height: geo.size.height)

                    // the sliding lens
                    GlassCapsule(tint: Color.black.opacity(0.28))
                        .frame(width: itemW, height: lensH)
                        .scaleEffect(dragX != nil ? 1.12 : 1)
                        .offset(x: lensX)

                    // tabs
                    HStack(spacing: 0) {
                        ForEach(AppTab.allCases) { tab in
                            let on = active == tab.rawValue
                            VStack(spacing: 3) {
                                Image(systemName: tab.icon).font(.system(size: 21, weight: .semibold))
                                Text(tab.title)
                                    .font(.system(size: 10.5, weight: .semibold))
                                    .lineLimit(1)
                                    .minimumScaleFactor(0.7)
                            }
                            .foregroundColor(on ? Theme.accent : Theme.txt.opacity(0.85))
                            .frame(width: itemW, height: geo.size.height)
                            .accessibilityElement(children: .ignore)
                            .accessibilityLabel(tab.title)
                            .accessibilityAddTraits(selection == tab ? [.isButton, .isSelected] : .isButton)
                        }
                    }
                    .padding(.horizontal, pad)
                    .animation(.easeOut(duration: 0.15), value: active)
                }
            }
            .contentShape(Capsule())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { v in
                        let i = index(at: v.location.x, itemW: itemW)
                        if dragX == nil {
                            lastIdx = selection.rawValue
                            withAnimation(.spring(response: 0.32, dampingFraction: 0.8)) { dragX = v.location.x }
                        } else {
                            withAnimation(.interactiveSpring(response: 0.18, dampingFraction: 0.88)) { dragX = v.location.x }
                        }
                        if i != lastIdx {
                            UIImpactFeedbackGenerator(style: .light).impactOccurred()
                            lastIdx = i
                        }
                    }
                    .onEnded { v in
                        let i = index(at: v.location.x, itemW: itemW)
                        withAnimation(.spring(response: 0.5, dampingFraction: 0.76)) {
                            if let t = AppTab(rawValue: i) { selection = t }
                            dragX = nil
                        }
                    }
            )
        }
        .frame(height: 68)
        .shadow(color: .black.opacity(0.55), radius: 16, y: 8)
        .padding(.horizontal, 14)
        .padding(.bottom, 4)
        .offset(y: 10)   // slightly lower
    }
}

// MARK: - Login

struct WebContainer: UIViewRepresentable {
    let webView: WKWebView
    func makeUIView(context: Context) -> WKWebView { webView }
    func updateUIView(_ uiView: WKWebView, context: Context) {}
}

struct LoginView: View {
    @ObservedObject private var session = WebSession.shared

    var body: some View {
        VStack(spacing: 16) {
            VStack(spacing: 4) {
                Text("i-Ma'luum")
                    .font(.system(size: 32, weight: .bold))
                    .foregroundColor(Theme.txt)
                Text("Sign in with your IIUM account")
                    .font(.system(size: 14))
                    .foregroundColor(Theme.muted)
            }
            .padding(.top, 8)

            WebContainer(webView: session.loginWebView)
                .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .strokeBorder(Theme.line, lineWidth: 1))
                .padding(.horizontal, 16)

            Button {
                session.state = .demo
            } label: {
                Text("Explore with demo data")
            }
            .buttonStyle(AccentButtonStyle(filled: false))
            .padding(.bottom, 8)
        }
        .screenBackground()
        .onAppear { session.startLogin() }
    }
}

// MARK: - In-app browser (shares the login cookies, dark CSS injected)

struct SimpleWebView: UIViewRepresentable {
    let url: URL
    func makeUIView(context: Context) -> WKWebView {
        let cfg = WKWebViewConfiguration()
        cfg.websiteDataStore = .default()
        cfg.userContentController.addUserScript(
            WKUserScript(source: WebTheme.js, injectionTime: .atDocumentStart, forMainFrameOnly: false))
        let w = WKWebView(frame: .zero, configuration: cfg)
        w.isOpaque = false
        w.backgroundColor = .black
        w.scrollView.backgroundColor = .black
        w.load(URLRequest(url: url))
        return w
    }
    func updateUIView(_ uiView: WKWebView, context: Context) {}
}

struct WebSheet: View {
    let url: URL
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            SimpleWebView(url: url)
                .background(Theme.bg)
                .ignoresSafeArea(edges: .bottom)
                .navigationTitle("i-Ma'luum")
                .navigationBarTitleDisplayMode(.inline)
                .toolbarBackground(Theme.bg, for: .navigationBar)
                .toolbarBackground(.visible, for: .navigationBar)
                .toolbarColorScheme(.dark, for: .navigationBar)
                .toolbar {
                    ToolbarItem(placement: .navigationBarTrailing) {
                        Button("Done") { dismiss() }
                            .foregroundColor(Theme.accent)
                    }
                }
        }
        .preferredColorScheme(.dark)
    }
}
