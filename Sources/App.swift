import SwiftUI

@main
struct iMaluumApp: App {
    init() { Theme.applyAppearance() }

    var body: some Scene {
        WindowGroup {
            RootView()
        }
    }
}

enum Endpoints {
    static let base = URL(string: "https://imaluum.iium.edu.my/")!
    static let schedule = URL(string: "https://imaluum.iium.edu.my/MyAcademic/schedule")!
}

struct RootView: View {
    @ObservedObject private var session = WebSession.shared

    var body: some View {
        ZStack {
            Theme.bg.ignoresSafeArea()
            switch session.state {
            case .checking:
                VStack(spacing: 16) {
                    ProgressView().tint(Theme.accent).scaleEffect(1.2)
                    Text("Connecting to i-Ma'luum…")
                        .font(.system(size: 14))
                        .foregroundColor(Theme.muted)
                }
            case .loggedOut:
                LoginView()
            case .loggedIn, .demo:
                MainTabs()
            }
        }
        .tint(Theme.accent)
        .preferredColorScheme(.dark)
        .task { await session.bootstrap() }
    }
}
