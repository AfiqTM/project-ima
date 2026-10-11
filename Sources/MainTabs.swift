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
        .safeAreaInset(edge: .bottom, spacing: 0) { AppTabBar(selection: $tab) }
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

// Flat, full-width bar: pure black, hairline on top, accent line above the selected tab.
struct AppTabBar: View {
    @Binding var selection: AppTab

    var body: some View {
        VStack(spacing: 0) {
            Hairline()
            HStack(spacing: 0) {
                ForEach(AppTab.allCases) { tab in
                    let selected = selection == tab
                    Button {
                        UIImpactFeedbackGenerator(style: .light).impactOccurred()
                        selection = tab
                    } label: {
                        VStack(spacing: 4) {
                            Rectangle()
                                .fill(selected ? Theme.accent : Color.clear)
                                .frame(width: 22, height: 2)
                                .clipShape(Capsule())
                            Image(systemName: tab.icon).font(.system(size: 18, weight: .semibold))
                            Text(tab.title)
                                .font(.system(size: 10, weight: .semibold))
                                .lineLimit(1)
                                .minimumScaleFactor(0.7)
                        }
                        .foregroundColor(selected ? Theme.accent : Theme.muted)
                        .frame(maxWidth: .infinity)
                        .padding(.bottom, 4)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(tab.title)
                }
            }
            .padding(.top, 6)
        }
        .background(Theme.bg.ignoresSafeArea(edges: .bottom))
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
