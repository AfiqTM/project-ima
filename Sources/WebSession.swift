import SwiftUI
import WebKit
import Security

enum SessionError: LocalizedError {
    case notLoggedIn
    case badData
    case notFound(String, [String])
    case external

    var errorDescription: String? {
        switch self {
        case .notLoggedIn: return "Your session has expired. Please sign in again."
        case .badData: return "The page was loaded but its content couldn't be read."
        case .notFound(let what, let seen):
            let list = seen.prefix(25).joined(separator: ", ")
            return "Couldn't find “\(what)” in the i-Ma'luum menu. Menu entries seen (\(seen.count)): \(list.isEmpty ? "none" : list)"
        case .external: return "This link opens outside i-Ma'luum."
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
        await restoreCookies()
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
        CookieVault.clear()
        menu = []
        state = .loggedOut
        loginWebView.load(URLRequest(url: Endpoints.base))
    }

    // MARK: Staying signed in
    // WKWebView drops session cookies when the app is closed, so the iium.edu.my cookies
    // (including the CAS single-sign-on cookie) are kept in the Keychain and restored on launch.

    private var lastCookieSave = Date.distantPast

    func saveCookies(throttled: Bool) async {
        if throttled, Date().timeIntervalSince(lastCookieSave) < 60 { return }
        lastCookieSave = Date()
        let all = await WKWebsiteDataStore.default().httpCookieStore.allCookies()
        let saved = all.filter { $0.domain.contains("iium.edu.my") }.map(SavedCookie.init)
        guard !saved.isEmpty, let data = try? JSONEncoder().encode(saved) else { return }
        CookieVault.write(data)
    }

    func restoreCookies() async {
        guard let data = CookieVault.read(),
              let saved = try? JSONDecoder().decode([SavedCookie].self, from: data) else { return }
        let store = WKWebsiteDataStore.default().httpCookieStore
        let existing = await store.allCookies()
        let have = Set(existing.map { "\($0.name)|\($0.domain)|\($0.path)" })
        for sc in saved where !have.contains("\(sc.name)|\(sc.domain)|\(sc.path)") {
            if let c = sc.makeCookie() { await store.setCookie(c) }
        }
    }

    // MARK: Fetching

    func fetch(_ url: URL) async throws -> PageData {
        guard url.host?.hasSuffix("imaluum.iium.edu.my") == true else { throw SessionError.external }
        try await acquire()
        defer { busy = false }
        attachWorker()
        try await load(url)
        try await ensureLoggedIn()
        await waitForContent()
        let result = try await worker.evaluateJavaScript(JS.extractPage)
        guard let s = result as? String, let data = s.data(using: .utf8) else { throw SessionError.badData }
        let page = try JSONDecoder().decode(PageData.self, from: data)
        if state == .checking || state == .loggedOut { state = .loggedIn }
        await saveCookies(throttled: true)
        return page
    }

    /// Finds a page URL from the site's own menu by link text (so URLs never need hard-coding).
    func link(for keys: [String]) async throws -> URL {
        if menu.isEmpty { menu = try await fetchMenu() }
        func norm(_ x: String) -> String { x.lowercased().filter { $0.isLetter || $0.isNumber } }
        let wanted = keys.map(norm)
        for k in wanted {
            if let l = menu.first(where: { norm($0.text) == k }), let u = URL(string: l.href) { return u }
        }
        for k in wanted {
            if let l = menu.first(where: { norm($0.text).contains(k) }), let u = URL(string: l.href) { return u }
        }
        let seen = menu.map { $0.text }
        menu = []   // force a fresh read on retry
        throw SessionError.notFound(keys.first ?? "page", seen)
    }

    private func fetchMenu() async throws -> [PageLink] {
        try await acquire()
        defer { busy = false }
        attachWorker()
        try await load(Endpoints.schedule)
        try await ensureLoggedIn()
        await waitForContent()
        let result = try await worker.evaluateJavaScript(JS.menuLinks)
        guard let s = result as? String, let data = s.data(using: .utf8) else { throw SessionError.badData }
        return try JSONDecoder().decode([PageLink].self, from: data)
    }

    /// Returns once the worker is on i-Ma'luum. If it was bounced through CAS single sign-on, waits for it to come back;
    /// a real password form means the session is gone.
    private func ensureLoggedIn() async throws {
        for _ in 0..<24 {
            if worker.url?.host?.hasSuffix("imaluum.iium.edu.my") == true { return }
            let js = "!!document.querySelector('input[type=password]')"
            if let hasPassword = try? await worker.evaluateJavaScript(js) as? Bool, hasPassword { break }
            try await Task.sleep(nanoseconds: 300_000_000)
        }
        state = .loggedOut
        throw SessionError.notLoggedIn
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
            await saveCookies(throttled: false)
        }
    }
}

// MARK: - JavaScript used to read pages

enum JS {
    static let extractPage = #"""
    (function(){
      function t(e){return ((e.innerText||e.textContent||'')+'').replace(/\s+/g,' ').trim();}
      function ok(h){return h && h.indexOf('javascript')!==0 && h.slice(-1)!=='#';}
      function inSide(e){return !!e.closest('.main-sidebar, .left-side, .sidebar, .sidebar-menu, .main-header, .navbar, .breadcrumb');}
      var root=document.querySelector('.content-wrapper')||document.body;

      // ---- tables (nested tables are read on their own; rows that merely wrap a table are skipped)
      var tables=[];
      document.querySelectorAll('table').forEach(function(tb){
        if(inSide(tb)) return;
        var rows=[];
        Array.prototype.forEach.call(tb.rows, function(tr){
          for(var i=0;i<tr.cells.length;i++){ if(tr.cells[i].querySelector('table')) return; }
          var cells=[], lines=[];
          Array.prototype.forEach.call(tr.cells, function(c){
            cells.push(t(c));
            lines.push(((c.innerText||c.textContent||'')+'').split(/\n+/).map(function(x){return x.replace(/\s+/g,' ').trim();}).filter(function(x){return x.length>0;}));
          });
          if(!cells.length) return;
          var a=tr.querySelector('a[href]');
          rows.push({cells:cells, lines:lines, href:(a && ok(a.href))? a.href : null});
        });
        if(rows.length){
          var cap=tb.querySelector('caption');
          var prev=tb.previousElementSibling;
          tables.push({title: cap? t(cap) : (prev && !prev.querySelector('table') ? t(prev).slice(0,80):''), rows:rows});
        }
      });
      // a header-only table followed by a values-only table (same column count) is really one table
      var merged=[];
      for(var i=0;i<tables.length;i++){
        var A=tables[i], B=tables[i+1];
        if(B && A.rows.length===1 && B.rows.length===1 && A.rows[0].cells.length===B.rows[0].cells.length && A.rows[0].cells.length>1){
          merged.push({title:A.title, rows:[A.rows[0], B.rows[0]]}); i++;
        } else { merged.push(A); }
      }
      tables=merged;

      var hEl=root.querySelector('.box-title,.panel-title,h3,h4,h2');
      var dd=[];
      root.querySelectorAll('.dropdown-menu a[href]').forEach(function(a){
        if(inSide(a)) return;
        var x=t(a); if(x && ok(a.href)) dd.push({text:x, href:a.href});
      });

      // ---- links; "click here" style tiles take their real name from the tile's heading
      function tileInfo(a){
        var inner=a.querySelector('h1,h2,h3,h4,h5');
        if(inner){ var p0=a.querySelector('p'); return {title:t(inner), sub:p0? t(p0):''}; }
        var el=a.parentElement;
        for(var i=0;i<6 && el && el!==root;i++){
          var h=el.querySelector('h1,h2,h3,h4,h5');
          if(h && el.querySelectorAll('a[href]').length<=1){
            var p=el.querySelector('p');
            return {title:t(h), sub:p? t(p):''};
          }
          el=el.parentElement;
        }
        return null;
      }
      var links=[], seen={};
      root.querySelectorAll('a[href]').forEach(function(a){
        if(a.closest('.dropdown-menu') || a.closest('table') || inSide(a)) return;
        var x=t(a); if(!x || !ok(a.href)) return;
        if(x.toLowerCase()==='home') return;
        var sub=null;
        if(/click here|register here|more info|read more|^here$/i.test(x)){
          var info=tileInfo(a);
          if(info && info.title){ x=info.title; sub=info.sub||null; }
        }
        var key=a.href+'|'+x; if(seen[key]) return; seen[key]=1;
        links.push({text:x, href:a.href, subtitle:sub});
      });
      return JSON.stringify({heading: hEl? t(hEl):'', tables:tables, dropdown:dd, links:links.slice(0,80), text:t(root).slice(0,2500)});
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


// MARK: - Cookie persistence

struct SavedCookie: Codable {
    var name: String
    var value: String
    var domain: String
    var path: String
    var expires: Date?
    var secure: Bool
    var httpOnly: Bool
    var sameSite: String?

    init(_ c: HTTPCookie) {
        name = c.name; value = c.value; domain = c.domain; path = c.path
        expires = c.expiresDate; secure = c.isSecure; httpOnly = c.isHTTPOnly
        sameSite = c.sameSitePolicy?.rawValue
    }

    func makeCookie() -> HTTPCookie? {
        // Session cookies get a long expiry so they survive the app being closed.
        let exp = expires ?? Date().addingTimeInterval(30 * 24 * 3600)
        if exp < Date() { return nil }
        var props: [HTTPCookiePropertyKey: Any] = [
            .name: name, .value: value, .domain: domain, .path: path, .expires: exp
        ]
        if secure { props[.secure] = "TRUE" }
        if httpOnly { props[HTTPCookiePropertyKey("HttpOnly")] = "TRUE" }
        if let s = sameSite { props[.sameSitePolicy] = s }
        return HTTPCookie(properties: props)
    }
}

enum CookieVault {
    private static let service = "imaluum.cookies"
    private static var fileURL: URL {
        let dir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("session.bin")
    }

    static func write(_ data: Data) {
        let q: [String: Any] = [kSecClass as String: kSecClassGenericPassword,
                                kSecAttrService as String: service,
                                kSecAttrAccount as String: "cookies"]
        SecItemDelete(q as CFDictionary)
        var add = q
        add[kSecValueData as String] = data
        add[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        if SecItemAdd(add as CFDictionary, nil) != errSecSuccess {
            // Some sideloading setups block Keychain access; fall back to a protected file.
            try? data.write(to: fileURL, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
        }
    }

    static func read() -> Data? {
        let q: [String: Any] = [kSecClass as String: kSecClassGenericPassword,
                                kSecAttrService as String: service,
                                kSecAttrAccount as String: "cookies",
                                kSecReturnData as String: true,
                                kSecMatchLimit as String: kSecMatchLimitOne]
        var out: CFTypeRef?
        if SecItemCopyMatching(q as CFDictionary, &out) == errSecSuccess, let d = out as? Data { return d }
        return try? Data(contentsOf: fileURL)
    }

    static func clear() {
        let q: [String: Any] = [kSecClass as String: kSecClassGenericPassword,
                                kSecAttrService as String: service]
        SecItemDelete(q as CFDictionary)
        try? FileManager.default.removeItem(at: fileURL)
    }
}
