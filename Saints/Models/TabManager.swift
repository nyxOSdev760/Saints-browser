import Foundation
import WebKit
import Combine
import SwiftUI

final class TabManager: ObservableObject {
    static let shared = TabManager()

    @Published private(set) var normalTabs: [BrowserTab] = []
    @Published private(set) var privateTabs: [BrowserTab] = []
    @Published private(set) var selectedTab: BrowserTab?
    /// Direction of the last swipe-driven tab change (+1 next, -1 previous, 0 none) for slide animations.
    @Published var switchDirection: Int = 0

    /// Set when the user opens / downloads an extension package; the UI asks for confirmation.
    @Published var pendingExtensionURL: URL?
    @Published var pendingExtensionFile: URL?

    private var _privateStore: WKWebsiteDataStore?
    var privateDataStore: WKWebsiteDataStore {
        if let s = _privateStore { return s }
        let s = WKWebsiteDataStore.nonPersistent()
        _privateStore = s
        return s
    }

    private let sessionURL: URL = {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Saints/session.json")
    }()

    private struct SavedTab: Codable { var url: String?; var title: String; var state: Data? }
    private struct SavedSession: Codable { var tabs: [SavedTab]; var selected: Int }

    private init() {}

    var allTabs: [BrowserTab] { normalTabs + privateTabs }
    func tabs(isPrivate: Bool) -> [BrowserTab] { isPrivate ? privateTabs : normalTabs }
    func tab(numericID: Int) -> BrowserTab? { allTabs.first { $0.numericID == numericID } }
    func tab(for webView: WKWebView) -> BrowserTab? { allTabs.first { $0.webView === webView } }

    // MARK: Lifecycle

    func bootstrap() {
        let settings = BrowserSettings.shared.data
        if settings.clearDataOnLaunch {
            clearWebsiteData()
        }
        if settings.restoreTabs && !settings.clearDataOnLaunch, restoreSession() { return }
        newTab(url: nil, isPrivate: settings.privateByDefault, select: true)
    }

    @discardableResult
    func newTab(url: URL? = nil, isPrivate: Bool, select: Bool = true, configuration: WKWebViewConfiguration? = nil) -> BrowserTab {
        let tab = BrowserTab(configuration: configuration, isPrivate: isPrivate)
        if isPrivate {
            privateTabs.append(tab)
        } else {
            normalTabs.append(tab)
        }
        if let url { tab.load(url) }
        if select || selectedTab == nil { self.select(tab) }
        scheduleSave()
        return tab
    }

    func select(_ tab: BrowserTab) {
        selectedTab?.captureSnapshot()
        tab.lastActive = Date()
        selectedTab = tab
        scheduleSave()
    }

    func close(_ tab: BrowserTab) {
        tab.webView.stopLoading()
        tab.webView.navigationDelegate = nil
        tab.webView.uiDelegate = nil
        let wasSelected = selectedTab === tab
        var list = tabs(isPrivate: tab.isPrivate)
        let index = list.firstIndex { $0 === tab } ?? 0
        list.removeAll { $0 === tab }
        if tab.isPrivate { privateTabs = list } else { normalTabs = list }

        if tab.isPrivate && privateTabs.isEmpty {
            // Throw away the whole private session once the last private tab closes.
            _privateStore = nil
        }
        if wasSelected {
            if !list.isEmpty {
                selectedTab = list[min(index, list.count - 1)]
            } else if let other = tabs(isPrivate: !tab.isPrivate).last {
                selectedTab = other
            } else {
                selectedTab = nil
                newTab(url: nil, isPrivate: tab.isPrivate, select: true)
            }
        }
        scheduleSave()
    }

    func closeAll(isPrivate: Bool) {
        for tab in tabs(isPrivate: isPrivate) { close(tab) }
    }

    /// Returns false when there is no tab in that direction.
    @discardableResult
    func selectNeighbor(offset: Int) -> Bool {
        guard let current = selectedTab else { return false }
        let list = tabs(isPrivate: current.isPrivate)
        guard let i = list.firstIndex(where: { $0 === current }) else { return false }
        let next = i + offset
        guard list.indices.contains(next) else { return false }
        select(list[next])
        return true
    }

    func hasNeighbor(offset: Int) -> Bool {
        guard let current = selectedTab else { return false }
        let list = tabs(isPrivate: current.isPrivate)
        guard let i = list.firstIndex(where: { $0 === current }) else { return false }
        return list.indices.contains(i + offset)
    }

    /// Safari-style swipe on the address bar: slide to the neighbouring tab, or open a new tab past the last one.
    func swipe(offset: Int) {
        let opensNew = offset > 0 && !hasNeighbor(offset: offset)
        guard opensNew || hasNeighbor(offset: offset) else { return }
        switchDirection = offset > 0 ? 1 : -1
        // Let the outgoing page pick up the direction before it animates away.
        DispatchQueue.main.async {
            withAnimation(.spring(response: 0.42, dampingFraction: 0.86)) {
                if opensNew {
                    _ = self.newTab(isPrivate: self.selectedTab?.isPrivate ?? false)
                } else {
                    _ = self.selectNeighbor(offset: offset)
                }
            }
            // Other ways of switching tabs (tab overview, links) shouldn't slide.
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) { self.switchDirection = 0 }
        }
    }

    /// Re-applies extension scripts, content blockers and privacy scripts to every open tab.
    func refreshUserContent() {
        for tab in allTabs {
            WebViewFactory.installUserContent(on: tab.webView.configuration.userContentController, isPrivate: tab.isPrivate)
            tab.reloadSettings()
        }
    }

    func clearWebsiteData(completion: (() -> Void)? = nil) {
        let types = WKWebsiteDataStore.allWebsiteDataTypes()
        WKWebsiteDataStore.default().removeData(ofTypes: types, modifiedSince: .distantPast) {
            completion?()
        }
        URLCache.shared.removeAllCachedResponses()
        HTTPCookieStorage.shared.removeCookies(since: .distantPast)
    }

    /// The Fire Button: closes every tab and erases all browsing data.
    func burnEverything() {
        for tab in allTabs {
            tab.webView.stopLoading()
            tab.webView.navigationDelegate = nil
            tab.webView.uiDelegate = nil
        }
        normalTabs = []
        privateTabs = []
        selectedTab = nil
        _privateStore = nil
        LibraryStore.shared.clearHistory()
        clearWebsiteData()
        try? FileManager.default.removeItem(at: sessionURL)
        newTab(url: nil, isPrivate: false, select: true)
        ToastCenter.shared.show("Tabs and data burned", symbol: "flame.fill")
    }

    // MARK: Session restore

    private var saveWorkItem: DispatchWorkItem?

    func scheduleSave() {
        saveWorkItem?.cancel()
        let item = DispatchWorkItem { [weak self] in self?.saveSession() }
        saveWorkItem = item
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5, execute: item)
    }

    func saveSession() {
        guard BrowserSettings.shared.data.restoreTabs else {
            try? FileManager.default.removeItem(at: sessionURL)
            return
        }
        let saved = normalTabs.map { tab -> SavedTab in
            var state: Data?
            if let s = tab.webView.interactionState as? Data, s.count < 2_000_000 { state = s }
            return SavedTab(url: tab.url?.absoluteString, title: tab.title, state: state)
        }
        let selected = normalTabs.firstIndex { $0 === selectedTab } ?? max(0, normalTabs.count - 1)
        let session = SavedSession(tabs: saved, selected: selected)
        let url = sessionURL
        DispatchQueue.global(qos: .utility).async {
            if let data = try? JSONEncoder().encode(session) { try? data.write(to: url, options: .atomic) }
        }
    }

    private func restoreSession() -> Bool {
        guard let data = try? Data(contentsOf: sessionURL),
              let session = try? JSONDecoder().decode(SavedSession.self, from: data), !session.tabs.isEmpty else { return false }
        for saved in session.tabs {
            let tab = BrowserTab(isPrivate: false)
            tab.title = saved.title
            if let state = saved.state {
                tab.webView.interactionState = state
                tab.url = saved.url.flatMap(URL.init(string:))
            } else if let s = saved.url, let url = URL(string: s) {
                tab.load(url)
            }
            normalTabs.append(tab)
        }
        selectedTab = normalTabs[min(max(session.selected, 0), normalTabs.count - 1)]
        return true
    }
}
