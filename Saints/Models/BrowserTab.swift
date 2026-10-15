import Foundation
import WebKit
import UIKit
import Combine

/// Builds User-Agent strings that match real browsers on this device.
enum UserAgent {
    private static var os: (major: Int, minor: Int, patch: Int) {
        let parts = UIDevice.current.systemVersion.split(separator: ".").compactMap { Int($0) }
        return (parts.first ?? 18, parts.count > 1 ? parts[1] : 0, parts.count > 2 ? parts[2] : 0)
    }

    /// Safari's version tracks the OS version (iOS 17.5 → Safari 17.5, iOS 26.0 → Safari 26.0).
    static var safariVersion: String { "\(os.major).\(os.minor)" }

    /// Since iOS 26 WebKit freezes the OS token at 18_6, like Safari does.
    private static var osToken: String {
        let v = os
        if v.major >= 26 { return "18_6" }
        return v.patch > 0 ? "\(v.major)_\(v.minor)_\(v.patch)" : "\(v.major)_\(v.minor)"
    }

    static var safariSuffix: String { "Version/\(safariVersion) Mobile/15E148 Safari/604.1" }

    private static let prefixKey = "saints.webkitUAPrefix"

    /// Reads WebKit's own UA once so other identities reuse its exact device/OS token.
    static func learnWebKitPrefix() {
        let probe = WKWebView(frame: .zero)
        probe.evaluateJavaScript("navigator.userAgent") { value, _ in
            guard let ua = value as? String, let end = ua.range(of: "(KHTML, like Gecko)") else { return }
            UserDefaults.standard.set(String(ua[..<end.upperBound]), forKey: prefixKey)
            _ = probe   // keep the probe alive until the callback runs
        }
    }

    private static var devicePrefix: String {
        if let learned = UserDefaults.standard.string(forKey: prefixKey) { return learned }
        return UIDevice.current.userInterfaceIdiom == .pad
            ? "Mozilla/5.0 (iPad; CPU OS \(osToken) like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko)"
            : "Mozilla/5.0 (iPhone; CPU iPhone OS \(osToken) like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko)"
    }

    static func string(for identity: BrowserIdentity) -> String {
        switch identity {
        case .safari:
            return "\(devicePrefix) \(safariSuffix)"
        case .chrome:
            return "\(devicePrefix) CriOS/141.0.7390.96 Mobile/15E148 Safari/604.1"
        case .firefox:
            return "\(devicePrefix) FxiOS/144.0 Mobile/15E148 Safari/605.1.15"
        case .edge:
            return "\(devicePrefix) Version/\(safariVersion) EdgiOS/141.0.3537.71 Mobile/15E148 Safari/604.1"
        case .desktopSafari:
            return "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/\(safariVersion) Safari/605.1.15"
        case .desktopChrome:
            return "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/141.0.0.0 Safari/537.36"
        }
    }

    /// The `customUserAgent` to set on a web view, or nil to let WebKit send its native Safari string
    /// (WebKit then also switches correctly between the mobile and desktop Safari strings).
    static func custom(for settings: SettingsData, desktopMode: Bool, host: String? = nil) -> String? {
        // A per-site choice wins over the global identity and custom string.
        if let site = SiteSettings.shared.identity(for: host) {
            if site == .safari { return nil }
            if desktopMode && !site.isDesktop { return nil }
            return string(for: site)
        }
        let custom = settings.customUserAgent.trimmingCharacters(in: .whitespacesAndNewlines)
        if !custom.isEmpty { return custom }
        let identity = settings.browserIdentity
        if identity == .safari { return nil }
        if desktopMode && !identity.isDesktop { return nil }
        return string(for: identity)
    }
}

enum WebViewFactory {
    /// Appended to WebKit's own UA prefix so pages see exactly what Safari on this iOS version sends.
    static var safariSuffix: String { UserAgent.safariSuffix }

    /// Bot-check / CAPTCHA providers. Nothing of ours is injected into these frames, because they inspect the
    /// JavaScript environment and treat any modified built-in as a sign of an automated or fake browser.
    static let verificationHosts = [
        "challenges.cloudflare.com", "hcaptcha.com", "recaptcha.net", "gstatic.com", "arkoselabs.com",
        "funcaptcha.com", "captcha-delivery.com", "perimeterx.net", "px-cdn.net", "px-cloud.net",
        "kasada.io", "datadome.co", "geetest.com", "friendlycaptcha.com", "turnstile.com"
    ]

    /// JS guard: true on verification hosts (and Google's /recaptcha frames).
    static var verificationGuard: String {
        let list = verificationHosts.map { "'\($0)'" }.joined(separator: ",")
        return "[\(list)].some((d) => location.hostname === d || location.hostname.endsWith('.' + d))"
            + " || (location.hostname.endsWith('google.com') && location.pathname.startsWith('/recaptcha'))"
    }

    /// Global Privacy Control signal. Main frame only, never on verification pages. Safari has no
    /// `doNotTrack`, so it is deliberately not faked (a fake value marks the browser as spoofed).
    static var gpcScript: String {
        """
        (function () {
          if (\(verificationGuard) || \(SiteSettings.offGuardJS)) return;
          try {
            Object.defineProperty(Navigator.prototype, 'globalPrivacyControl', { get: () => true, configurable: true, enumerable: true });
          } catch (e) {}
        })();
        """
    }

    /// Darkens light pages. Pages that are already dark (or follow `prefers-color-scheme`) are left alone.
    static func darkPagesScript(always: Bool) -> String {
        """
        (function () {
          if (window.__saintsDark || \(SiteSettings.offGuardJS)) return;
          window.__saintsDark = true;
          const always = \(always);
          const css = 'html{filter:invert(0.9) hue-rotate(180deg)!important;background:#fff!important}' +
            'img,video,picture,canvas,iframe,embed,object,svg image,[style*="background-image"]' +
            '{filter:invert(1) hue-rotate(180deg)!important}';
          const lum = (c) => {
            const m = /rgba?\\(([^)]+)\\)/.exec(c || '');
            if (!m) return null;
            const p = m[1].split(',').map(parseFloat);
            if (p.length > 3 && p[3] === 0) return null;
            return (0.299 * p[0] + 0.587 * p[1] + 0.114 * p[2]) / 255;
          };
          const apply = () => {
            if (!always && !matchMedia('(prefers-color-scheme: dark)').matches) return;
            const root = getComputedStyle(document.documentElement).backgroundColor;
            const body = document.body ? getComputedStyle(document.body).backgroundColor : '';
            const l = lum(body) ?? lum(root) ?? 1;
            if (l < 0.45) return;                       // already dark
            const style = document.createElement('style');
            style.id = 'saints-dark-pages';
            style.textContent = css;
            (document.head || document.documentElement).appendChild(style);
          };
          if (document.readyState === 'loading') document.addEventListener('DOMContentLoaded', apply, { once: true });
          else apply();
        })();
        """
    }

    static func makeConfiguration(isPrivate: Bool) -> WKWebViewConfiguration {
        let settings = BrowserSettings.shared.data
        let config = WKWebViewConfiguration()
        config.websiteDataStore = isPrivate ? TabManager.shared.privateDataStore : .default()
        config.setURLSchemeHandler(ExtensionSchemeHandler.shared, forURLScheme: ExtensionSchemeHandler.scheme)
        config.allowsInlineMediaPlayback = true
        config.allowsPictureInPictureMediaPlayback = true
        config.applicationNameForUserAgent = safariSuffix
        config.preferences.javaScriptCanOpenWindowsAutomatically = !settings.blockPopups
        // Safe Browsing lookups contact third-party servers; Saints keeps them off.
        config.preferences.isFraudulentWebsiteWarningEnabled = false
        config.defaultWebpagePreferences.allowsContentJavaScript = settings.javaScriptEnabled
        config.defaultWebpagePreferences.preferredContentMode = settings.desktopByDefault ? .desktop : .mobile
        config.upgradeKnownHostsToHTTPS = true
        config.userContentController = WKUserContentController()
        installUserContent(on: config.userContentController, isPrivate: isPrivate)
        return config
    }

    static func installUserContent(on controller: WKUserContentController, isPrivate: Bool) {
        controller.removeAllUserScripts()
        controller.removeAllScriptMessageHandlers()
        UBlockEngine.shared.install(into: controller)
        if BrowserSettings.shared.data.globalPrivacyControl {
            controller.addUserScript(WKUserScript(source: gpcScript, injectionTime: .atDocumentStart,
                                                  forMainFrameOnly: true, in: .page))
        }
        let darkMode = BrowserSettings.shared.data.darkWebPages
        if darkMode != .off {
            controller.addUserScript(WKUserScript(source: darkPagesScript(always: darkMode == .always),
                                                  injectionTime: .atDocumentStart, forMainFrameOnly: true, in: .page))
        }
        ExtensionHost.shared.install(into: controller, isPrivate: isPrivate)
        ContentBlocker.shared.apply(to: controller)
    }
}

final class BrowserTab: NSObject, ObservableObject, Identifiable {
    private static var nextNumericID = 1

    let id = UUID()
    let numericID: Int
    let isPrivate: Bool
    let webView: WKWebView

    @Published var title: String = ""
    @Published var url: URL?
    @Published var progress: Double = 0
    @Published var isLoading = false
    @Published var canGoBack = false
    @Published var canGoForward = false
    @Published var hasOnlySecureContent = false
    @Published var snapshot: UIImage?
    @Published var chromeCollapsed = false
    @Published var desktopMode: Bool
    @Published var zoom: Double

    var lastActive = Date()
    private var observations: [NSKeyValueObservation] = []
    private var lastOffset: CGFloat = 0
    private var upgradedHosts: Set<String> = []
    private static var httpAllowedHosts: Set<String> = []

    var showsHome: Bool { url == nil }
    var displayTitle: String {
        if !title.isEmpty { return title }
        return url?.host ?? (showsHome ? "New Tab" : "Untitled")
    }

    init(configuration: WKWebViewConfiguration? = nil, isPrivate: Bool) {
        BrowserTab.nextNumericID += 1
        numericID = BrowserTab.nextNumericID
        self.isPrivate = isPrivate
        let settings = BrowserSettings.shared.data
        desktopMode = settings.desktopByDefault
        zoom = settings.defaultZoom
        webView = WKWebView(frame: .zero, configuration: configuration ?? WebViewFactory.makeConfiguration(isPrivate: isPrivate))
        super.init()

        webView.navigationDelegate = self
        webView.uiDelegate = self
        webView.allowsBackForwardNavigationGestures = true
        webView.allowsLinkPreview = true
        webView.isFindInteractionEnabled = true
        webView.isInspectable = settings.webInspector
        webView.pageZoom = zoom
        webView.scrollView.contentInsetAdjustmentBehavior = .automatic
        webView.scrollView.keyboardDismissMode = .interactive
        webView.customUserAgent = UserAgent.custom(for: settings, desktopMode: desktopMode, host: url?.host)
        observe()
    }

    deinit {
        observations.forEach { $0.invalidate() }
    }

    private func observe() {
        observations = [
            webView.observe(\.title, options: [.new]) { [weak self] wv, _ in self?.title = wv.title ?? "" },
            webView.observe(\.url, options: [.new]) { [weak self] wv, _ in
                guard let self else { return }
                if let u = wv.url, u.absoluteString != "about:blank" { self.url = u }
            },
            webView.observe(\.estimatedProgress, options: [.new]) { [weak self] wv, _ in self?.progress = wv.estimatedProgress },
            webView.observe(\.isLoading, options: [.new]) { [weak self] wv, _ in self?.isLoading = wv.isLoading },
            webView.observe(\.canGoBack, options: [.new]) { [weak self] wv, _ in self?.canGoBack = wv.canGoBack },
            webView.observe(\.canGoForward, options: [.new]) { [weak self] wv, _ in self?.canGoForward = wv.canGoForward },
            webView.observe(\.hasOnlySecureContent, options: [.new]) { [weak self] wv, _ in self?.hasOnlySecureContent = wv.hasOnlySecureContent },
            webView.scrollView.observe(\.contentOffset, options: [.new]) { [weak self] sv, _ in self?.scrolled(sv) }
        ]
    }

    private func scrolled(_ sv: UIScrollView) {
        guard BrowserSettings.shared.data.hideBarsOnScroll else {
            if chromeCollapsed { chromeCollapsed = false }
            return
        }
        let y = sv.contentOffset.y + sv.adjustedContentInset.top
        let dy = y - lastOffset
        lastOffset = y
        let atBottom = y + sv.bounds.height >= sv.contentSize.height - 4
        if y <= 10 || atBottom {
            if chromeCollapsed { chromeCollapsed = false }
        } else if sv.isTracking || sv.isDecelerating {
            if dy > 6 && !chromeCollapsed { chromeCollapsed = true }
            else if dy < -6 && chromeCollapsed { chromeCollapsed = false }
        }
    }

    // MARK: Actions

    func load(_ url: URL) {
        lastActive = Date()
        if url.isFileURL {
            webView.loadFileURL(url, allowingReadAccessTo: url.deletingLastPathComponent())
        } else {
            webView.load(URLRequest(url: url))
        }
        self.url = url
    }

    func loadInput(_ text: String) {
        if let url = SearchEngine.resolve(text, settings: BrowserSettings.shared.data) { load(url) }
    }

    func goHome() {
        webView.stopLoading()
        url = nil
        title = ""
    }

    func toggleDesktopMode() {
        desktopMode.toggle()
        webView.customUserAgent = UserAgent.custom(for: BrowserSettings.shared.data, desktopMode: desktopMode, host: url?.host)
        if let url = webView.url {
            webView.load(URLRequest(url: url))
        }
    }

    func setZoom(_ value: Double) {
        zoom = min(max(value, 0.5), 3.0)
        webView.pageZoom = zoom
    }

    func captureSnapshot(completion: (() -> Void)? = nil) {
        guard !showsHome, webView.bounds.width > 0 else { snapshot = nil; completion?(); return }
        let config = WKSnapshotConfiguration()
        config.snapshotWidth = NSNumber(value: Double(min(webView.bounds.width, 420)))
        webView.takeSnapshot(with: config) { [weak self] image, _ in
            if let image { self?.snapshot = image }
            completion?()
        }
    }

    func reloadSettings() {
        let settings = BrowserSettings.shared.data
        webView.isInspectable = settings.webInspector
        webView.customUserAgent = UserAgent.custom(for: settings, desktopMode: desktopMode, host: url?.host)
        webView.configuration.preferences.javaScriptCanOpenWindowsAutomatically = !settings.blockPopups
    }

    private func showErrorPage(_ error: NSError, for failingURL: URL) {
        let host = failingURL.host ?? failingURL.absoluteString
        let canFallback = failingURL.scheme == "https" && upgradedHosts.contains(host)
        var httpURL = URLComponents(url: failingURL, resolvingAgainstBaseURL: false)
        httpURL?.scheme = "http"
        let fallback = canFallback ? """
            <p class="warn">This site may not support HTTPS. Saints upgraded the connection to keep you safe.</p>
            <a class="btn secondary" href="saints-allow-http:\(httpURL?.url?.absoluteString ?? "")">Continue with insecure HTTP</a>
            """ : ""
        let message = error.localizedDescription
            .replacingOccurrences(of: "&", with: "&amp;").replacingOccurrences(of: "<", with: "&lt;")
        let html = """
        <!doctype html><html><head><meta name="viewport" content="width=device-width,initial-scale=1">
        <style>
        :root { color-scheme: light dark; }
        body { font: -apple-system-body; font-family: -apple-system, system-ui; margin: 0; min-height: 100vh; display: flex;
               align-items: center; justify-content: center; background: Canvas; color: CanvasText; }
        main { max-width: 420px; padding: 32px; text-align: center; }
        h1 { font-size: 22px; margin: 0 0 8px; } p { opacity: .75; line-height: 1.4; } .warn { opacity: .9; }
        .btn { display: block; margin: 12px auto 0; padding: 12px 18px; border-radius: 12px; background: #0A84FF; color: white;
               text-decoration: none; font-weight: 600; } .secondary { background: rgba(127,127,127,.2); color: inherit; }
        </style></head><body><main>
        <h1>Can’t open this page</h1><p><b>\(host)</b></p><p>\(message)</p>
        <a class="btn" href="\(failingURL.absoluteString)">Try Again</a>
        \(fallback)
        </main></body></html>
        """
        webView.loadSimulatedRequest(URLRequest(url: failingURL), responseHTML: html)
    }

    private static func isLocal(_ host: String) -> Bool {
        host == "localhost" || host.hasSuffix(".local") || host.hasPrefix("192.168.") || host.hasPrefix("10.")
            || host.hasPrefix("127.") || host.hasPrefix("172.16.") || host.range(of: #"^\d+\.\d+\.\d+\.\d+$"#, options: .regularExpression) != nil
    }

    static func isExtensionPackage(_ url: URL) -> Bool {
        let p = url.path.lowercased()
        return p.hasSuffix(".xpi") || p.hasSuffix(".crx") || p.hasSuffix(".user.js") || p.hasSuffix(".user.css")
    }
}

// MARK: - Navigation

extension BrowserTab: WKNavigationDelegate {
    func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction,
                 preferences: WKWebpagePreferences,
                 decisionHandler: @escaping (WKNavigationActionPolicy, WKWebpagePreferences) -> Void) {
        let settings = BrowserSettings.shared.data
        preferences.preferredContentMode = desktopMode ? .desktop : .mobile
        preferences.allowsContentJavaScript = settings.javaScriptEnabled

        guard let url = navigationAction.request.url, let scheme = url.scheme?.lowercased() else {
            decisionHandler(.allow, preferences)
            return
        }
        let isMainFrame = navigationAction.targetFrame?.isMainFrame ?? true

        if scheme == "saints-allow-http" {
            let target = String(url.absoluteString.dropFirst("saints-allow-http:".count))
            if let httpURL = URL(string: target), let host = httpURL.host {
                BrowserTab.httpAllowedHosts.insert(host)
                load(httpURL)
            }
            decisionHandler(.cancel, preferences)
            return
        }

        if !["http", "https", "about", "data", "blob", "file", ExtensionSchemeHandler.scheme, "javascript"].contains(scheme) {
            // tel:, mailto:, maps:, app links …
            if navigationAction.navigationType == .linkActivated || isMainFrame {
                UIApplication.shared.open(url)
            }
            decisionHandler(.cancel, preferences)
            return
        }

        if settings.extensionsEnabled && settings.interceptExtensionDownloads && isMainFrame && BrowserTab.isExtensionPackage(url) {
            TabManager.shared.pendingExtensionURL = url
            decisionHandler(.cancel, preferences)
            return
        }

        if navigationAction.shouldPerformDownload {
            decisionHandler(.download, preferences)
            return
        }

        if isMainFrame, scheme == "http", settings.httpsOnly, let host = url.host,
           !BrowserTab.isLocal(host), !BrowserTab.httpAllowedHosts.contains(host),
           var comps = URLComponents(url: url, resolvingAgainstBaseURL: false) {
            comps.scheme = "https"
            if comps.port == 80 { comps.port = nil }
            if let secure = comps.url {
                upgradedHosts.insert(host)
                PrivacyStats.shared.addUpgrade()
                decisionHandler(.cancel, preferences)
                webView.load(URLRequest(url: secure))
                return
            }
        }

        // Per-site identity: make sure this navigation goes out with the right User-Agent.
        if isMainFrame, scheme.hasPrefix("http"), (navigationAction.request.httpMethod ?? "GET") == "GET" {
            let desired = UserAgent.custom(for: settings, desktopMode: desktopMode, host: url.host)
            let current = (webView.customUserAgent ?? "").isEmpty ? nil : webView.customUserAgent
            if current != desired {
                webView.customUserAgent = desired
                decisionHandler(.cancel, preferences)
                webView.load(navigationAction.request)
                return
            }
        }

        if isMainFrame, settings.stripTrackingParams, scheme.hasPrefix("http"), let cleaned = URLCleaner.clean(url) {
            PrivacyStats.shared.addCleaned()
            decisionHandler(.cancel, preferences)
            var request = navigationAction.request
            request.url = cleaned
            webView.load(request)
            return
        }

        decisionHandler(.allow, preferences)
    }

    func webView(_ webView: WKWebView, decidePolicyFor navigationResponse: WKNavigationResponse,
                 decisionHandler: @escaping (WKNavigationResponsePolicy) -> Void) {
        let mime = navigationResponse.response.mimeType?.lowercased() ?? ""
        let settings = BrowserSettings.shared.data
        if settings.extensionsEnabled, navigationResponse.isForMainFrame,
           mime == "application/x-xpinstall" || mime == "application/x-chrome-extension",
           let url = navigationResponse.response.url {
            TabManager.shared.pendingExtensionURL = url
            decisionHandler(.cancel)
            return
        }
        if let http = navigationResponse.response as? HTTPURLResponse,
           let disposition = http.value(forHTTPHeaderField: "Content-Disposition")?.lowercased(),
           disposition.hasPrefix("attachment") {
            decisionHandler(.download)
            return
        }
        decisionHandler(navigationResponse.canShowMIMEType ? .allow : .download)
    }

    func webView(_ webView: WKWebView, navigationAction: WKNavigationAction, didBecome download: WKDownload) {
        download.delegate = DownloadManager.shared
    }

    func webView(_ webView: WKWebView, navigationResponse: WKNavigationResponse, didBecome download: WKDownload) {
        download.delegate = DownloadManager.shared
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        if let url = webView.url, !isPrivate {
            LibraryStore.shared.recordVisit(title: webView.title ?? "", url: url)
        }
        ExtensionHost.shared.tabUpdated(self)
        TabManager.shared.scheduleSave()
    }

    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
        handle(error as NSError)
    }

    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
        handle(error as NSError)
    }

    private func handle(_ error: NSError) {
        if error.domain == NSURLErrorDomain && error.code == NSURLErrorCancelled { return }
        if error.domain == "WebKitErrorDomain" && (error.code == 102 || error.code == 204) { return }
        guard let failing = (error.userInfo[NSURLErrorFailingURLErrorKey] as? URL) ?? webView.url else { return }
        showErrorPage(error, for: failing)
    }

    func webViewWebContentProcessDidTerminate(_ webView: WKWebView) {
        webView.reload()
    }
}

// MARK: - UI delegate

extension BrowserTab: WKUIDelegate {
    func webView(_ webView: WKWebView, createWebViewWith configuration: WKWebViewConfiguration,
                 for navigationAction: WKNavigationAction, windowFeatures: WKWindowFeatures) -> WKWebView? {
        let background = BrowserSettings.shared.data.openLinksInBackground
        let tab = TabManager.shared.newTab(isPrivate: isPrivate, select: !background, configuration: configuration)
        if background { ToastCenter.shared.show("Opened in a new tab", symbol: "plus.square.on.square") }
        return tab.webView
    }

    func webViewDidClose(_ webView: WKWebView) {
        TabManager.shared.close(self)
    }

    func webView(_ webView: WKWebView, runJavaScriptAlertPanelWithMessage message: String,
                 initiatedByFrame frame: WKFrameInfo, completionHandler: @escaping () -> Void) {
        let alert = UIAlertController(title: frame.securityOrigin.host, message: message, preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: "OK", style: .default) { _ in completionHandler() })
        present(alert, fallback: completionHandler)
    }

    func webView(_ webView: WKWebView, runJavaScriptConfirmPanelWithMessage message: String,
                 initiatedByFrame frame: WKFrameInfo, completionHandler: @escaping (Bool) -> Void) {
        let alert = UIAlertController(title: frame.securityOrigin.host, message: message, preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: "Cancel", style: .cancel) { _ in completionHandler(false) })
        alert.addAction(UIAlertAction(title: "OK", style: .default) { _ in completionHandler(true) })
        present(alert) { completionHandler(false) }
    }

    func webView(_ webView: WKWebView, runJavaScriptTextInputPanelWithPrompt prompt: String, defaultText: String?,
                 initiatedByFrame frame: WKFrameInfo, completionHandler: @escaping (String?) -> Void) {
        let alert = UIAlertController(title: frame.securityOrigin.host, message: prompt, preferredStyle: .alert)
        alert.addTextField { $0.text = defaultText }
        alert.addAction(UIAlertAction(title: "Cancel", style: .cancel) { _ in completionHandler(nil) })
        alert.addAction(UIAlertAction(title: "OK", style: .default) { _ in completionHandler(alert.textFields?.first?.text) })
        present(alert) { completionHandler(nil) }
    }

    func webView(_ webView: WKWebView, contextMenuConfigurationForElement elementInfo: WKContextMenuElementInfo,
                 completionHandler: @escaping (UIContextMenuConfiguration?) -> Void) {
        guard let link = elementInfo.linkURL else { completionHandler(nil); return }
        let config = UIContextMenuConfiguration(identifier: nil, previewProvider: nil) { suggested in
            let open = UIAction(title: "Open in New Tab", image: UIImage(systemName: "plus.square.on.square")) { _ in
                TabManager.shared.newTab(url: link, isPrivate: self.isPrivate, select: !BrowserSettings.shared.data.openLinksInBackground)
            }
            let openPrivate = UIAction(title: "Open in Private Tab", image: UIImage(systemName: "eyeglasses")) { _ in
                TabManager.shared.newTab(url: link, isPrivate: true, select: true)
            }
            let copy = UIAction(title: "Copy Link", image: UIImage(systemName: "doc.on.doc")) { _ in
                UIPasteboard.general.url = URLCleaner.clean(link) ?? link
            }
            let share = UIAction(title: "Share Link", image: UIImage(systemName: "square.and.arrow.up")) { _ in
                let vc = UIActivityViewController(activityItems: [URLCleaner.clean(link) ?? link], applicationActivities: nil)
                UIApplication.topViewController?.present(vc, animated: true)
            }
            let bookmark = UIAction(title: "Add Bookmark", image: UIImage(systemName: "book")) { _ in
                LibraryStore.shared.toggleBookmark(title: link.host ?? "", url: link)
            }
            var items: [UIMenuElement] = [open, openPrivate, copy, share, bookmark]
            if BrowserTab.isExtensionPackage(link) {
                items.insert(UIAction(title: "Install Extension", image: UIImage(systemName: "puzzlepiece.extension")) { _ in
                    TabManager.shared.pendingExtensionURL = link
                }, at: 0)
            }
            return UIMenu(children: items + suggested)
        }
        completionHandler(config)
    }

    private func present(_ alert: UIAlertController, fallback: @escaping () -> Void) {
        guard let top = UIApplication.topViewController else { fallback(); return }
        top.present(alert, animated: true)
    }
}

extension UIApplication {
    static var topViewController: UIViewController? {
        let scenes = shared.connectedScenes.compactMap { $0 as? UIWindowScene }
        let scene = scenes.first(where: { $0.activationState == .foregroundActive }) ?? scenes.first
        let window = scene?.windows.first(where: { $0.isKeyWindow }) ?? scene?.windows.first
        var top = window?.rootViewController
        while let presented = top?.presentedViewController { top = presented }
        return top
    }
}
