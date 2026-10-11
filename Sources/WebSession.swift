import SwiftUI
import WebKit

enum SessionError: LocalizedError {
    case notLoggedIn
    case badData
    case notFound(String)

    var errorDescription: String? {
        switch self {
        case .notLoggedIn: return "Your session has expired. Please sign in again."
        case .badData: return "The page was loaded but its content couldn't be read."
        case .notFound(let what): return "Couldn't find the “\(what)” page in the i-Ma'luum menu."
        }
    }
}

/// Owns two web views that share one cookie store:
/// - `loginWebView`: visible, used for the real i-Ma'luum / CAS login (your password never touches this app's code)
/// - `worker`: hidden, loads pages and extracts their tables as JSON, which the app renders natively
@MainActor
final class WebSession: NSObject, ObservableObject, WKNavigationDelegate {
    enum State: Equatable { case checking, loggedOut, loggedIn, demo }

    static let shared = WebSession()

    @Published var state: State = .checking

    let loginWebView: WKWebView
    private let worker: WKWebView
    private var continuation: CheckedContinuation<Void, Error>?
    private var busy = false
    private var menu: [PageLink] = []

    override init() {
        let cfg1 = WKWebViewConfiguration()
        cfg1.websiteDataStore = .default()
        let login = WKWebView(frame: .zero, configuration: cfg1)
        login.customUserAgent = "Mozilla/5.0 (iPhone; CPU iPhone OS 17_0 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.0 Mobile/15E148 Safari/604.1"
        login.isOpaque = false
        login.backgroundColor = .black
        login.scrollView.backgroundColor = .black

        let cfg2 = WKWebViewConfiguration()
        cfg2.websiteDataStore = .default()
        cfg2.defaultWebpagePreferences.preferredContentMode = .desktop
        let hidden = WKWebView(frame: CGRect(x: 0, y: 0, width: 1280, height: 900), configuration: cfg2)
        hidden.customUserAgent = "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.0 Safari/605.1.15"
        hidden.isUserInteractionEnabled = false

        loginWebView = login
        worker = hidden
        super.init()
        loginWebView.navigationDelegate = self
        worker.navigationDelegate = self
    }

    // MARK: Session lifecycle

    func bootstrap() async {
        do {
            let page = try await fetch(Endpoints.schedule)
            PageCache.save(page, for: Endpoints.schedule)
        } catch SessionError.notLoggedIn {
            state = .loggedOut
        } catch {
            // Offline or server hiccup: let the user in if we have saved data.
            state = PageCache.hasAny() ? .loggedIn : .loggedOut
        }
    }

    func startLogin() {
        if loginWebView.url == nil {
            loginWebView.load(URLRequest(url: Endpoints.base))
        }
    }

    func signOut() async {
        let store = WKWebsiteDataStore.default()
        await store.removeData(ofTypes: WKWebsiteDataStore.allWebsiteDataTypes(), modifiedSince: .distantPast)
        PageCache.clear()
        menu = []
        state = .loggedOut
        loginWebView.load(URLRequest(url: Endpoints.base))
    }

    // MARK: Fetching

    func fetch(_ url: URL) async throws -> PageData {
        try await acquire()
        defer { busy = false }
        attachWorker()
        try await load(url)
        try ensureLoggedIn()
        await waitForContent()
        let result = try await worker.evaluateJavaScript(JS.extractPage)
        guard let s = result as? String, let data = s.data(using: .utf8) else { throw SessionError.badData }
        let page = try JSONDecoder().decode(PageData.self, from: data)
        if state == .checking || state == .loggedOut { state = .loggedIn }
        return page
    }

    /// Finds a page URL from the site's own menu by link text (so URLs never need hard-coding).
    func link(for keys: [String]) async throws -> URL {
        if menu.isEmpty { menu = try await fetchMenu() }
        let lowered = keys.map { $0.lowercased() }
        for k in lowered {
            if let l = menu.first(where: { $0.text.lowercased() == k }), let u = URL(string: l.href) { return u }
        }
        for k in lowered {
            if let l = menu.first(where: { $0.text.lowercased().contains(k) }), let u = URL(string: l.href) { return u }
        }
        throw SessionError.notFound(keys.first ?? "page")
    }

    private func fetchMenu() async throws -> [PageLink] {
        try await acquire()
        defer { busy = false }
        attachWorker()
        try await load(Endpoints.base)
        try ensureLoggedIn()
        try await Task.sleep(nanoseconds: 500_000_000)
        let result = try await worker.evaluateJavaScript(JS.menuLinks)
        guard let s = result as? String, let data = s.data(using: .utf8) else { throw SessionError.badData }
        return try JSONDecoder().decode([PageLink].self, from: data)
    }

    private func ensureLoggedIn() throws {
        guard let host = worker.url?.host, host.hasSuffix("imaluum.iium.edu.my") else {
            state = .loggedOut
            throw SessionError.notLoggedIn
        }
    }

    /// A web view that isn't in any window can be throttled by iOS; park it (invisible, behind the UI) in the key window.
    private func attachWorker() {
        guard worker.superview == nil else { return }
        let window = UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .flatMap { $0.windows }
            .first { $0.isKeyWindow } ?? UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .flatMap { $0.windows }.first
        guard let window = window else { return }
        worker.frame = CGRect(x: 0, y: 0, width: 1280, height: 900)
        window.insertSubview(worker, at: 0)
    }

    private func waitForContent() async {
        for _ in 0..<12 {
            let js = "document.readyState==='complete' && document.querySelectorAll('table').length"
            if let n = try? await worker.evaluateJavaScript(js) as? Int, n > 0 { return }
            try? await Task.sleep(nanoseconds: 250_000_000)
        }
    }

    private func acquire() async throws {
        while busy {
            if Task.isCancelled { throw CancellationError() }
            try await Task.sleep(nanoseconds: 80_000_000)
        }
        busy = true
    }

    private func load(_ url: URL) async throws {
        let watchdog = Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: 35_000_000_000)
            guard !Task.isCancelled else { return }
            self?.continuation?.resume(throwing: URLError(.timedOut))
            self?.continuation = nil
        }
        defer { watchdog.cancel() }
        try await withCheckedThrowingContinuation { (c: CheckedContinuation<Void, Error>) in
            continuation = c
            worker.load(URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 30))
        }
    }

    // MARK: WKNavigationDelegate

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        if webView === loginWebView {
            Task { await checkLoginPage() }
            return
        }
        continuation?.resume()
        continuation = nil
    }

    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
        fail(webView, error)
    }

    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
        fail(webView, error)
    }

    private func fail(_ webView: WKWebView, _ error: Error) {
        guard webView === worker else { return }
        if (error as NSError).code == NSURLErrorCancelled { return }
        continuation?.resume(throwing: error)
        continuation = nil
    }

    private func checkLoginPage() async {
        let js = "(location.host.indexOf('imaluum.iium.edu.my')>=0) && ((document.body.innerText||'').indexOf('My Academic')>=0)"
        if let ok = try? await loginWebView.evaluateJavaScript(js) as? Bool, ok, state == .loggedOut {
            state = .loggedIn
        }
    }
}

// MARK: - JavaScript used to read pages

enum JS {
    static let extractPage = #"""
    (function(){
      function t(e){return ((e.innerText||e.textContent||'')+'').replace(/\s+/g,' ').trim();}
      function ok(h){return h && h.indexOf('javascript')!==0 && h.slice(-1)!=='#';}
      var root=document.querySelector('.content-wrapper')||document.body;
      function inSide(e){return !!e.closest('.main-sidebar, .left-side, .sidebar, .sidebar-menu, .main-header, .navbar');}
      var tables=[];
      document.querySelectorAll('table').forEach(function(tb){
        if(inSide(tb)) return;
        var rows=[];
        tb.querySelectorAll('tr').forEach(function(tr){
          var cells=[];
          tr.querySelectorAll('th,td').forEach(function(c){cells.push(t(c));});
          if(!cells.length) return;
          var a=tr.querySelector('a[href]');
          rows.push({cells:cells, href:(a && ok(a.href))? a.href : null});
        });
        if(rows.length){
          var cap=tb.querySelector('caption');
          var prev=tb.previousElementSibling;
          tables.push({title: cap? t(cap) : (prev? t(prev).slice(0,80):''), rows:rows});
        }
      });
      var hEl=root.querySelector('.box-title,.panel-title,h3,h4,h2');
      var dd=[];
      root.querySelectorAll('.dropdown-menu a[href]').forEach(function(a){
        if(inSide(a)) return;
        var x=t(a); if(x && ok(a.href)) dd.push({text:x, href:a.href});
      });
      var links=[], seen={};
      root.querySelectorAll('a[href]').forEach(function(a){
        if(a.closest('.dropdown-menu') || a.closest('table')) return;
        if(inSide(a)) return;
        var x=t(a); if(!x || !ok(a.href) || seen[a.href]) return;
        seen[a.href]=1; links.push({text:x, href:a.href});
      });
      return JSON.stringify({heading: hEl? t(hEl):'', tables:tables, dropdown:dd, links:links.slice(0,60), text:t(root).slice(0,2500)});
    })()
    """#

    static let menuLinks = #"""
    JSON.stringify(Array.from(document.querySelectorAll('a[href]')).map(function(a){
      return {text: ((a.innerText||a.textContent||'')+'').replace(/\s+/g,' ').trim(), href: a.href};
    }).filter(function(x){
      return x.text && x.href.indexOf('javascript')!==0 && x.href.slice(-1)!=='#';
    }))
    """#
}

// MARK: - Page view model

@MainActor
final class PageViewModel: ObservableObject {
    @Published var page: PageData?
    @Published var isLoading = false
    @Published var errorMessage: String?
    @Published var isOffline = false
    var currentURL: URL?

    private let resolver: () async throws -> URL
    private let demo: PageData

    init(demo: PageData = DemoData.placeholder, resolver: @escaping () async throws -> URL) {
        self.demo = demo
        self.resolver = resolver
    }

    func load(url override: URL? = nil) async {
        if WebSession.shared.state == .demo { page = demo; return }
        guard !isLoading else { return }
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }
        do {
            let url: URL
            if let o = override { url = o }
            else if let c = currentURL { url = c }
            else { url = try await resolver() }
            currentURL = url
            if page == nil, let cached = PageCache.load(url) { page = cached }
            let fresh = try await WebSession.shared.fetch(url)
            page = fresh
            isOffline = false
            PageCache.save(fresh, for: url)
        } catch is CancellationError {
        } catch SessionError.notLoggedIn {
        } catch let e as URLError where e.code == .cancelled {
        } catch {
            if page != nil { isOffline = true } else { errorMessage = error.localizedDescription }
        }
    }
}
