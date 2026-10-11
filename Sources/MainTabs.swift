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
        .safeAreaInset(edge: .bottom) { FloatingTabBar(selection: $tab) }
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

struct FloatingTabBar: View {
    @Binding var selection: AppTab

    var body: some View {
        HStack(spacing: 4) {
            ForEach(AppTab.allCases) { tab in
                let selected = selection == tab
                Button {
                    UIImpactFeedbackGenerator(style: .light).impactOccurred()
                    withAnimation(.spring(response: 0.32, dampingFraction: 0.8)) { selection = tab }
                } label: {
                    VStack(spacing: 3) {
                        Image(systemName: tab.icon).font(.system(size: 19, weight: .semibold))
                        Text(tab.title)
                            .font(.system(size: 10, weight: .semibold, design: .rounded))
                            .lineLimit(1)
                            .minimumScaleFactor(0.7)
                    }
                    .foregroundColor(selected ? Color.black : Color.white.opacity(0.55))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 9)
                    .background(Capsule().fill(selected ? Theme.accent : Color.clear))
                }
                .buttonStyle(.plain)
                .accessibilityLabel(tab.title)
            }
        }
        .padding(6)
        .background(Capsule().fill(Color(white: 0.07)))
        .overlay(
            Capsule().strokeBorder(
                LinearGradient(colors: [Color.white.opacity(0.28), Color.white.opacity(0.05), Theme.accent.opacity(0.4)],
                               startPoint: .topLeading, endPoint: .bottomTrailing),
                lineWidth: 1)
        )
        .padding(.horizontal, 16)
        .padding(.bottom, 4)
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
        VStack(spacing: 14) {
            VStack(spacing: 4) {
                Text("i-Ma'luum")
                    .font(.system(size: 32, weight: .bold, design: .rounded))
                    .foregroundColor(.white)
                Text("Sign in with your IIUM account")
                    .font(.system(size: 15, design: .rounded))
                    .foregroundColor(Theme.accentSoft)
            }
            .padding(.top, 8)

            WebContainer(webView: session.loginWebView)
                .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 24, style: .continuous)
                    .strokeBorder(Theme.accent.opacity(0.5), lineWidth: 1))
                .padding(.horizontal, 16)

            Button {
                session.state = .demo
            } label: {
                Text("Explore with demo data")
                    .font(.system(size: 15, weight: .semibold, design: .rounded))
                    .foregroundColor(Theme.accentSoft)
                    .padding(.vertical, 8)
            }
        }
        .amoled()
        .onAppear { session.startLogin() }
    }
}

// MARK: - In-app browser (shares the login cookies)

struct SimpleWebView: UIViewRepresentable {
    let url: URL
    func makeUIView(context: Context) -> WKWebView {
        let cfg = WKWebViewConfiguration()
        cfg.websiteDataStore = .default()
        let w = WKWebView(frame: .zero, configuration: cfg)
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
                .ignoresSafeArea(edges: .bottom)
                .navigationTitle("i-Ma'luum")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .navigationBarTrailing) {
                        Button("Done") { dismiss() }
                    }
                }
        }
    }
}
