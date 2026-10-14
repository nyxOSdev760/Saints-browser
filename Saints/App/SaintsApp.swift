import SwiftUI
import Combine

@main
struct SaintsApp: App {
    @StateObject private var settings = BrowserSettings.shared
    @StateObject private var tabs = TabManager.shared
    @StateObject private var extensions = ExtensionManager.shared
    @StateObject private var library = LibraryStore.shared
    @StateObject private var toasts = ToastCenter.shared
    @Environment(\.scenePhase) private var scenePhase

    init() {
        AppBootstrap.start()
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(settings)
                .environmentObject(tabs)
                .environmentObject(extensions)
                .environmentObject(library)
                .environmentObject(toasts)
                .onOpenURL(perform: AppBootstrap.open)
        }
        .onChange(of: scenePhase) { phase in
            if phase == .background { TabManager.shared.saveSession() }
        }
    }
}

enum AppBootstrap {
    private static var cancellables = Set<AnyCancellable>()
    private static var started = false

    static func start() {
        guard !started else { return }
        started = true
        let settings = BrowserSettings.shared

        var booted = false
        let boot = {
            guard !booted else { return }
            booted = true
            TabManager.shared.bootstrap()
        }
        // Wait briefly for content blockers so the first page load is already protected.
        ContentBlocker.shared.compileBuiltIns(settings: settings.data) {
            TabManager.shared.refreshUserContent()
            boot()
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5, execute: boot)

        ExtensionManager.shared.compileRulesets()
        ExtensionHost.shared.refreshBackgrounds()

        settings.$data
            .removeDuplicates()
            .scan((SettingsData(), SettingsData())) { ($0.1, $1) }
            .dropFirst()
            .receive(on: DispatchQueue.main)
            .sink { pair in react(old: pair.0, new: pair.1) }
            .store(in: &cancellables)
    }

    private static func react(old: SettingsData, new: SettingsData) {
        let blockersChanged = old.blockTrackers != new.blockTrackers || old.blockAds != new.blockAds
            || old.blockCookieBanners != new.blockCookieBanners
        let scriptsChanged = old.globalPrivacyControl != new.globalPrivacyControl
            || old.extensionsEnabled != new.extensionsEnabled
        let tabsChanged = old.webInspector != new.webInspector || old.customUserAgent != new.customUserAgent
            || old.blockPopups != new.blockPopups

        if old.extensionsEnabled != new.extensionsEnabled {
            ExtensionHost.shared.refreshBackgrounds()
            ExtensionManager.shared.compileRulesets()
        }
        if blockersChanged {
            ContentBlocker.shared.compileBuiltIns(settings: new) {
                TabManager.shared.refreshUserContent()
            }
        } else if scriptsChanged || tabsChanged {
            TabManager.shared.refreshUserContent()
        }
        if old.defaultZoom != new.defaultZoom {
            TabManager.shared.allTabs.forEach { $0.setZoom(new.defaultZoom) }
        }
    }

    static func open(_ url: URL) {
        if url.isFileURL {
            TabManager.shared.pendingExtensionFile = url
            return
        }
        if url.scheme == "saints" {
            let comps = URLComponents(url: url, resolvingAgainstBaseURL: false)
            if let target = comps?.queryItems?.first(where: { $0.name == "url" })?.value, let targetURL = URL(string: target) {
                if BrowserTab.isExtensionPackage(targetURL) || ExtensionManager.isStoreListing(targetURL) && comps?.host == "install" {
                    TabManager.shared.pendingExtensionURL = targetURL
                } else {
                    TabManager.shared.newTab(url: targetURL, isPrivate: comps?.host == "private")
                }
            } else if let q = comps?.queryItems?.first(where: { $0.name == "q" })?.value {
                TabManager.shared.newTab(url: SearchEngine.searchURL(for: q, settings: BrowserSettings.shared.data), isPrivate: false)
            } else {
                TabManager.shared.newTab(isPrivate: comps?.host == "private")
            }
            return
        }
        if url.scheme?.hasPrefix("http") == true {
            TabManager.shared.newTab(url: url, isPrivate: false)
        }
    }
}
