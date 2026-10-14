import SwiftUI
import WebKit
import UniformTypeIdentifiers

enum BrowserSheet: Identifiable {
    case menu, settings, library, extensions, downloads, wallpapers, customize
    case install(PendingInstall)

    var id: String {
        switch self {
        case .menu: return "menu"
        case .settings: return "settings"
        case .library: return "library"
        case .extensions: return "extensions"
        case .downloads: return "downloads"
        case .wallpapers: return "wallpapers"
        case .customize: return "customize"
        case .install(let p): return "install-\(p.id)"
        }
    }
}

struct RootView: View {
    @EnvironmentObject var tabs: TabManager
    @EnvironmentObject var settings: BrowserSettings
    @EnvironmentObject var toasts: ToastCenter

    var body: some View {
        ZStack(alignment: .top) {
            if let tab = tabs.selectedTab {
                BrowserView(tab: tab)
            } else {
                ZStack {
                    WallpaperView()
                    SaintsLogo(size: 54).foregroundStyle(.white)
                }
            }
            if let toast = toasts.current {
                ToastView(toast: toast)
                    .padding(.top, 8)
                    .transition(.move(edge: .top).combined(with: .opacity))
                    .zIndex(10)
            }
        }
        .preferredColorScheme(settings.data.theme.colorScheme)
        .tint(settings.accent)
        .fontDesign(settings.data.fontDesign.design)
        .dynamicTypeSize(settings.data.textSize.size)
    }
}

struct BrowserView: View {
    @ObservedObject var tab: BrowserTab

    @EnvironmentObject var tabs: TabManager
    @EnvironmentObject var settings: BrowserSettings
    @EnvironmentObject var extensions: ExtensionManager
    @EnvironmentObject var library: LibraryStore
    @ObservedObject private var host = ExtensionHost.shared

    @State private var addressText = ""
    @FocusState private var addressFocused: Bool
    @State private var showTabs = false
    @State private var sheet: BrowserSheet?
    @State private var confirmBurn = false
    @State private var homeSearching = false

    private var isTop: Bool { settings.data.barPosition == .top }
    private var collapsed: Bool { tab.chromeCollapsed && !addressFocused && !tab.showsHome }

    var body: some View {
        ZStack {
            VStack(spacing: 0) {
                if isTop && !homeSearching { topChrome }
                content
                if homeSearching {
                    EmptyView()
                } else if !isTop {
                    bottomChromeSafari
                } else if !collapsed && !addressFocused {
                    toolbarOnly
                }
            }
            .background((settings.data.theme == .black ? Color.black : Color(uiColor: .systemBackground)).ignoresSafeArea())
            .sheet(item: $sheet) { sheetView($0) }

            if showTabs {
                TabSwitcherView(isPresented: $showTabs, showingPrivate: tab.isPrivate)
                    .transition(.asymmetric(insertion: .scale(scale: 1.08).combined(with: .opacity),
                                            removal: .scale(scale: 1.08).combined(with: .opacity)))
                    .zIndex(5)
            }
        }
        .animation(.spring(response: 0.32, dampingFraction: 0.86), value: showTabs)
        .animation(.easeInOut(duration: 0.22), value: collapsed)
        .animation(.easeInOut(duration: 0.2), value: homeSearching)
        .sheet(item: $host.presentedPage) { page in
            ExtensionPageSheet(page: page)
        }
        .confirmationDialog("Close all tabs and erase all browsing data?", isPresented: $confirmBurn, titleVisibility: .visible) {
            Button("Burn Everything", role: .destructive) { tabs.burnEverything() }
        }
        .onChange(of: tabs.pendingExtensionURL) { url in
            guard let url else { return }
            tabs.pendingExtensionURL = nil
            stage(url: url)
        }
        .onChange(of: tabs.pendingExtensionFile) { file in
            guard let file else { return }
            tabs.pendingExtensionFile = nil
            stage(file: file)
        }
        .onChange(of: addressFocused) { focused in
            if focused && addressText.isEmpty, let url = tab.url {
                addressText = SearchEngine.query(from: url) ?? url.absoluteString
            }
        }
    }

    // MARK: Layout pieces

    @ViewBuilder private var content: some View {
        ZStack(alignment: .bottom) {
            WebViewContainer(webView: tab.webView)
                .opacity(tab.showsHome ? 0 : 1)
            if tab.showsHome {
                HomePageView(tab: tab, searching: $homeSearching)
            }
            if addressFocused {
                SuggestionsView(query: addressText) { pick in submit(pick) }
                    .background(Color(uiColor: .systemGroupedBackground))
                    .transition(.opacity)
            }
            if !addressFocused, ExtensionManager.isStoreListing(tab.url) {
                Button {
                    if let url = tab.url { stage(url: url) }
                } label: {
                    Label("Add to Saints", systemImage: "puzzlepiece.extension.fill")
                        .font(.subheadline.weight(.semibold))
                        .padding(.horizontal, 18).padding(.vertical, 11)
                        .background(settings.accent, in: Capsule())
                        .foregroundStyle(.white)
                        .shadow(radius: 8, y: 3)
                }
                .padding(.bottom, 14)
                .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var addressBar: some View {
        AddressBar(tab: tab, text: $addressText, focused: $addressFocused, onSubmit: submit,
                   onShowExtensions: { sheet = .extensions })
    }

    private var collapsedBar: some View {
        Button { tab.chromeCollapsed = false } label: {
            HStack(spacing: 4) {
                if tab.url?.scheme == "https" { Image(systemName: "lock.fill").font(.system(size: 9)) }
                Text(tab.url?.host ?? "").font(.caption.weight(.medium))
            }
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity)
            .frame(height: 24)
        }
        .buttonStyle(.plain)
    }

    private var topChrome: some View {
        VStack(spacing: 6) {
            if collapsed {
                collapsedBar
            } else {
                if settings.data.showTabStrip { TabStrip(isPrivate: tab.isPrivate) }
                addressBar.padding(.horizontal, 10)
            }
        }
        .padding(.vertical, 6)
        .background(BarBackground(isPrivate: tab.isPrivate))
        .if(tab.isPrivate) { $0.environment(\.colorScheme, .dark) }
    }

    private var bottomChromeSafari: some View {
        VStack(spacing: 4) {
            if collapsed {
                collapsedBar
            } else {
                if settings.data.showTabStrip && !addressFocused { TabStrip(isPrivate: tab.isPrivate) }
                addressBar.padding(.horizontal, 10).padding(.top, 6)
                if !addressFocused {
                    BrowserToolbar(tab: tab, perform: perform)
                }
            }
        }
        .padding(.bottom, addressFocused ? 6 : 0)
        .background(BarBackground(isPrivate: tab.isPrivate))
        .if(tab.isPrivate) { $0.environment(\.colorScheme, .dark) }
    }

    private var toolbarOnly: some View {
        BrowserToolbar(tab: tab, perform: perform)
            .background(BarBackground(isPrivate: tab.isPrivate))
            .if(tab.isPrivate) { $0.environment(\.colorScheme, .dark) }
    }

    // MARK: Actions

    private func submit(_ text: String) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        addressFocused = false
        tab.loadInput(trimmed)
        addressText = ""
    }

    private func perform(_ action: ToolbarAction) {
        switch action {
        case .back:
            if tab.canGoBack { tab.webView.goBack() } else if !tab.showsHome { tab.goHome() }
        case .forward:
            tab.webView.goForward()
        case .share:
            if let url = tab.url { Share.present([URLCleaner.clean(url) ?? url]) }
        case .bookmarks:
            sheet = .library
        case .tabs:
            tab.captureSnapshot { showTabs = true }
        case .menu:
            sheet = .menu
        case .home:
            tab.goHome()
        case .newTab:
            tabs.newTab(isPrivate: tab.isPrivate)
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) { addressFocused = true }
        case .privateTab:
            tabs.newTab(isPrivate: true)
        case .extensions:
            sheet = .extensions
        case .reload:
            tab.webView.reload()
        case .find:
            tab.webView.findInteraction?.presentFindNavigator(showingReplace: false)
        case .fire:
            confirmBurn = true
        case .desktop:
            tab.toggleDesktopMode()
        }
    }

    private func open(_ next: BrowserSheet) {
        sheet = nil
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) { sheet = next }
    }

    @ViewBuilder private func sheetView(_ which: BrowserSheet) -> some View {
        switch which {
        case .menu:
            MenuSheet(tab: tab, open: open, perform: { action in
                sheet = nil
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) { perform(action) }
            })
        case .settings:
            SettingsView()
        case .library:
            LibraryView(tab: tab)
        case .extensions:
            ExtensionsView()
        case .downloads:
            DownloadsView()
        case .wallpapers:
            NavigationStack { WallpaperStudioView(standalone: true) }
        case .customize:
            NavigationStack { CustomizeView(standalone: true) }
        case .install(let pending):
            InstallSheet(pending: pending)
        }
    }

    private func stage(url: URL) {
        ToastCenter.shared.show("Fetching extension…", symbol: "arrow.down.circle")
        ExtensionManager.shared.stage(fromURL: url.absoluteString) { result in
            switch result {
            case .success(let pending): open(.install(pending))
            case .failure(let error): ToastCenter.shared.show(error.localizedDescription, symbol: "exclamationmark.triangle")
            }
        }
    }

    private func stage(file: URL) {
        let scoped = file.startAccessingSecurityScopedResource()
        defer { if scoped { file.stopAccessingSecurityScopedResource() } }
        do {
            let data = try Data(contentsOf: file)
            let pending = try ExtensionManager.shared.stage(data: data, filename: file.lastPathComponent, sourceURL: nil)
            open(.install(pending))
        } catch {
            ToastCenter.shared.show(error.localizedDescription, symbol: "exclamationmark.triangle")
        }
    }
}

// MARK: - Extension popup / options sheet

struct ExtensionPageSheet: View {
    let page: ExtensionHost.ExtensionPage
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ExtensionPageWebView(page: page)
                .ignoresSafeArea(edges: .bottom)
                .navigationTitle(page.ext.name)
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } }
                }
        }
        .presentationDetents(page.context == "popup" ? [.medium, .large] : [.large])
        .presentationDragIndicator(.visible)
    }
}

// MARK: - Install confirmation

struct InstallSheet: View {
    let pending: PendingInstall
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject var settings: BrowserSettings
    @State private var installed = false

    private var ext: WebExtension { pending.ext }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    HStack(spacing: 14) {
                        Image(systemName: ext.kind == .webExtension ? "puzzlepiece.extension.fill" : (ext.kind == .userScript ? "curlybraces" : "paintbrush.fill"))
                            .font(.title)
                            .foregroundStyle(.white)
                            .frame(width: 58, height: 58)
                            .background(settings.accent.gradient, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                        VStack(alignment: .leading, spacing: 3) {
                            Text(ext.name).font(.headline)
                            Text("\(ext.kind.label) · v\(ext.version)").font(.subheadline).foregroundStyle(.secondary)
                            if !ext.author.isEmpty { Text(ext.author).font(.caption).foregroundStyle(.secondary) }
                        }
                    }
                    .padding(.vertical, 4)
                    if !ext.summary.isEmpty { Text(ext.summary).font(.subheadline) }
                    if ext.name.localizedCaseInsensitiveContains("uBlock Origin") {
                        NavigationLink {
                            UBlockView()
                        } label: {
                            Label("Saints has uBlock Origin built in. It runs natively in WebKit and needs no extension.",
                                  systemImage: "shield.fill")
                                .font(.footnote)
                        }
                    }
                    if pending.replacing != nil {
                        Label("This will update the installed version.", systemImage: "arrow.triangle.2.circlepath")
                            .font(.footnote)
                    }
                }
                if !ext.displayPermissions.isEmpty {
                    Section("It will be able to") {
                        ForEach(ext.displayPermissions.prefix(30), id: \.self) { p in
                            Label(PermissionText.describe(p), systemImage: PermissionText.symbol(p)).font(.subheadline)
                        }
                    }
                }
                Section {
                    if !ext.contentScripts.isEmpty {
                        Label("\(ext.contentScripts.count) content script\(ext.contentScripts.count == 1 ? "" : "s")", systemImage: "doc.text")
                    }
                    if ext.hasBackground { Label("Runs a background page", systemImage: "gearshape.2") }
                    if ext.popupPath != nil { Label("Has a toolbar popup", systemImage: "rectangle.portrait.on.rectangle.portrait") }
                    if !ext.dnrRulesets.isEmpty { Label("Blocks content with native WebKit rules", systemImage: "shield.lefthalf.filled") }
                    if let source = ext.sourceURL { Text(source).font(.caption).foregroundStyle(.secondary).lineLimit(2) }
                } footer: {
                    Text("Saints runs extensions in isolated worlds and never sends extension or browsing data anywhere.")
                }
            }
            .navigationTitle("Add Extension")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { ExtensionManager.shared.discard(pending); dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(pending.replacing == nil ? "Add" : "Update") {
                        do {
                            try ExtensionManager.shared.commit(pending)
                            installed = true
                            ToastCenter.shared.show("\(ext.name) added", symbol: "puzzlepiece.extension.fill")
                            dismiss()
                        } catch {
                            ToastCenter.shared.show(error.localizedDescription, symbol: "exclamationmark.triangle")
                        }
                    }
                    .font(.body.weight(.semibold))
                }
            }
        }
        .onDisappear { if !installed { ExtensionManager.shared.discard(pending) } }
    }
}

enum PermissionText {
    static func describe(_ p: String) -> String {
        switch p {
        case "<all_urls>", "*://*/*", "http://*/*", "https://*/*": return "Read and change data on all websites"
        case "tabs": return "Access browser tabs"
        case "storage", "unlimitedStorage": return "Store data on this device"
        case "activeTab": return "Access the current tab when you use it"
        case "scripting": return "Run scripts on pages"
        case "notifications": return "Show notifications"
        case "contextMenus", "menus": return "Add items to menus"
        case "declarativeNetRequest", "declarativeNetRequestWithHostAccess": return "Block content on pages"
        case "webRequest", "webRequestBlocking": return "Observe network requests (limited on iOS)"
        case "cookies": return "Access cookies (not available on iOS)"
        case "alarms": return "Schedule tasks"
        case "clipboardWrite", "GM_setClipboard": return "Write to the clipboard"
        case "GM_xmlhttpRequest", "GM.xmlHttpRequest": return "Make cross-site network requests"
        case "GM_setValue", "GM_getValue", "GM.setValue", "GM.getValue": return "Store data on this device"
        default:
            if p.contains("://") || p.hasPrefix("*") { return "Access \(p)" }
            return p
        }
    }

    static func symbol(_ p: String) -> String {
        if p.contains("://") || p == "<all_urls>" || p.hasPrefix("*") { return "globe" }
        if p.lowercased().contains("storage") || p.contains("Value") { return "internaldrive" }
        if p.contains("tab") { return "square.on.square" }
        if p.contains("xmlhttp") || p.contains("Request") { return "network" }
        return "checkmark.shield"
    }
}
