import SwiftUI
import WebKit

// MARK: - Address bar

struct AddressBar: View {
    @ObservedObject var tab: BrowserTab
    @Binding var text: String
    var focused: FocusState<Bool>.Binding
    var onSubmit: (String) -> Void
    var onShowExtensions: () -> Void
    var onSwipeUp: () -> Void = {}

    @EnvironmentObject var settings: BrowserSettings
    @EnvironmentObject var extensions: ExtensionManager
    @EnvironmentObject var tabs: TabManager
    @ObservedObject private var ublock = UBlockEngine.shared
    @State private var dragOffset: CGFloat = 0
    @State private var dragLift: CGFloat = 0

    private var isEditing: Bool { focused.wrappedValue }
    private var height: CGFloat { settings.data.compactBars ? 38 : 46 }

    private var displayText: String {
        guard let url = tab.url else { return "Search with DuckDuckGo" }
        if let q = SearchEngine.query(from: url) { return q }
        if settings.data.showFullURL { return url.absoluteString }
        var host = url.host ?? url.absoluteString
        if host.hasPrefix("www.") { host.removeFirst(4) }
        return host
    }

    var body: some View {
        HStack(spacing: 8) {
            ZStack(alignment: .bottom) {
                HStack(spacing: 6) {
                    if isEditing {
                        Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
                    } else {
                        pageMenu
                    }
                    ZStack {
                        // The field always exists so it can take focus the moment the bar is tapped.
                        TextField("Search or enter address", text: $text)
                            .focused(focused)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                            .keyboardType(.webSearch)
                            .submitLabel(.go)
                            .onSubmit { onSubmit(text) }
                            .opacity(isEditing ? 1 : 0)
                            .allowsHitTesting(isEditing)
                        if !isEditing {
                            Button(action: beginEditing) {
                                HStack(spacing: 5) {
                                    if tab.url?.scheme == "https" {
                                        Image(systemName: "lock.fill").font(.caption2).foregroundStyle(.secondary)
                                    } else if tab.url?.scheme == "http" {
                                        Image(systemName: "exclamationmark.triangle.fill").font(.caption2).foregroundStyle(.orange)
                                    }
                                    Text(displayText)
                                        .lineLimit(1)
                                        .truncationMode(.middle)
                                        .foregroundStyle(tab.url == nil ? Color.secondary : Color.primary)
                                }
                                .frame(maxWidth: .infinity, maxHeight: .infinity,
                                       alignment: settings.data.centerAddress ? .center : .leading)
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    if isEditing {
                        if !text.isEmpty {
                            Button { text = "" } label: {
                                Image(systemName: "xmark.circle.fill").foregroundStyle(.secondary)
                                    .frame(width: 28, height: 28)
                            }
                            .buttonStyle(.plain)
                        }
                    } else {
                        reloadButton
                    }
                }
                .padding(.horizontal, 10)
                .frame(height: height)
                .background(FieldBackground(isPrivate: tab.isPrivate))

                if settings.data.showProgressBar && tab.isLoading && !isEditing {
                    GeometryReader { geo in
                        Capsule()
                            .fill(settings.accent)
                            .frame(width: max(8, geo.size.width * tab.progress), height: 2.5)
                            .animation(.easeOut(duration: 0.2), value: tab.progress)
                    }
                    .frame(height: 2.5)
                    .padding(.horizontal, settings.data.barCornerRadius / 2)
                }
            }
            .offset(x: dragOffset, y: min(0, dragLift))
            .scaleEffect(1 - min(abs(dragOffset), 120) / 1200)
            .overlay(alignment: .trailing) { newTabHint }
            .gesture(swipeGesture, including: isEditing || !settings.data.swipeAddressBarToSwitchTabs ? .subviews : .all)

            if isEditing {
                Button("Cancel") {
                    text = ""
                    focused.wrappedValue = false
                }
                .transition(.move(edge: .trailing).combined(with: .opacity))
            }
        }
        .animation(.spring(response: 0.3, dampingFraction: 0.85), value: isEditing)
    }

    private func beginEditing() {
        text = tab.url.map { SearchEngine.query(from: $0) ?? $0.absoluteString } ?? ""
        focused.wrappedValue = true
    }

    /// Past the last tab, a "+" bubble grows as you drag; releasing opens a new tab.
    @ViewBuilder private var newTabHint: some View {
        if dragOffset < -12 && !tabs.hasNeighbor(offset: 1) {
            let progress = min(1, -dragOffset / 90)
            HStack(spacing: 4) {
                Image(systemName: "plus")
                Text("New Tab").font(.caption.weight(.semibold))
            }
            .font(.footnote.weight(.bold))
            .foregroundStyle(progress >= 1 ? Color.white : settings.accent)
            .padding(.horizontal, 10)
            .frame(height: 32)
            .background(Capsule().fill(progress >= 1 ? settings.accent : settings.accent.opacity(0.15)))
            .scaleEffect(0.6 + 0.4 * progress)
            .opacity(Double(progress))
            .offset(x: 4)
            .animation(.spring(response: 0.25, dampingFraction: 0.7), value: progress >= 1)
            .allowsHitTesting(false)
        }
    }

    private var swipeGesture: some Gesture {
        DragGesture(minimumDistance: 16)
            .onChanged { v in
                let dx = v.translation.width, dy = v.translation.height
                if abs(dx) > abs(dy) {
                    // Rubber-band once there's nowhere to go.
                    let blocked = dx > 0 ? !tabs.hasNeighbor(offset: -1) : false
                    dragOffset = blocked ? dx / 6 : dx / 1.6
                    dragLift = 0
                } else if dy < 0 {
                    dragLift = dy / 3
                    dragOffset = 0
                }
            }
            .onEnded { v in
                let dx = v.translation.width, dy = v.translation.height
                withAnimation(.spring(response: 0.35, dampingFraction: 0.75)) {
                    dragOffset = 0
                    dragLift = 0
                }
                if dy < -50 && abs(dx) < 60 {
                    settings.haptic(.medium)
                    onSwipeUp()
                } else if dx < -70 {
                    settings.haptic(tabs.hasNeighbor(offset: 1) ? .light : .medium)
                    tabs.swipe(offset: 1)
                } else if dx > 70 && tabs.hasNeighbor(offset: -1) {
                    settings.haptic()
                    tabs.swipe(offset: -1)
                }
            }
    }

    @ViewBuilder private var reloadButton: some View {
        if tab.url != nil {
            Button {
                if tab.isLoading { tab.webView.stopLoading() } else { tab.webView.reload() }
            } label: {
                Image(systemName: tab.isLoading ? "xmark" : "arrow.clockwise")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .frame(width: 28, height: 28)
            }
        }
    }

    /// Safari "AA"-style page menu.
    private var pageMenu: some View {
        Menu {
            Section {
                Button { tab.setZoom(tab.zoom + 0.1) } label: { Label("Zoom In (\(Int(tab.zoom * 100))%)", systemImage: "plus.magnifyingglass") }
                Button { tab.setZoom(tab.zoom - 0.1) } label: { Label("Zoom Out", systemImage: "minus.magnifyingglass") }
                Button { tab.setZoom(1) } label: { Label("Actual Size", systemImage: "1.magnifyingglass") }
            }
            Section {
                Button { tab.toggleDesktopMode() } label: {
                    Label(tab.desktopMode ? "Request Mobile Site" : "Request Desktop Site",
                          systemImage: tab.desktopMode ? "iphone" : "desktopcomputer")
                }
                Button { tab.webView.findInteraction?.presentFindNavigator(showingReplace: false) } label: {
                    Label("Find on Page", systemImage: "doc.text.magnifyingglass")
                }
            }
            if ublock.state.enabled, let host = tab.url?.host {
                Section("uBlock Origin") {
                    Button {
                        settings.haptic(.medium)
                        let target = tab
                        ublock.toggleAllowlist(host) { [weak target] in target?.webView.reload() }
                    } label: {
                        if ublock.isAllowlisted(host) {
                            Label("Turn On for This Site", systemImage: "shield.fill")
                        } else {
                            Label("Turn Off for This Site", systemImage: "shield.slash")
                        }
                    }
                }
            }
            let actionable = extensions.activeExtensions.filter { $0.kind == .webExtension && ($0.popupPath != nil || $0.hasBackground) }
            if !actionable.isEmpty {
                Section("Extensions") {
                    ForEach(actionable) { ext in
                        Button { ExtensionHost.shared.activate(ext) } label: { Label(ext.name, systemImage: "puzzlepiece.extension") }
                    }
                }
            }
            Button { onShowExtensions() } label: { Label("Manage Extensions", systemImage: "puzzlepiece.extension.fill") }
        } label: {
            Image(systemName: tab.isPrivate ? "eyeglasses" : (extensions.activeExtensions.isEmpty ? "textformat.size" : "puzzlepiece.extension"))
                .font(.footnote.weight(.semibold))
                .foregroundStyle(tab.isPrivate ? Color.purple : Color.secondary)
                .frame(width: 28, height: 28)
        }
    }
}

// MARK: - Toolbar

struct BrowserToolbar: View {
    @ObservedObject var tab: BrowserTab
    var perform: (ToolbarAction) -> Void

    @EnvironmentObject var settings: BrowserSettings
    @EnvironmentObject var tabs: TabManager
    @EnvironmentObject var library: LibraryStore

    var body: some View {
        HStack {
            ForEach(settings.data.toolbarItems) { item in
                if item == .tabs {
                    tabsButton
                } else {
                    Button { settings.haptic(); perform(item) } label: { icon(for: item) }
                        .buttonStyle(PressableStyle())
                        .disabled(isDisabled(item))
                        .frame(maxWidth: .infinity)
                }
            }
        }
        .font(.system(size: settings.data.toolbarLabels ? 17 : 19, weight: settings.data.toolbarIconWeight.weight))
        .frame(height: (settings.data.compactBars ? 38 : 44) + (settings.data.toolbarLabels ? 10 : 0))
    }

    @ViewBuilder private func labeled<Icon: View>(_ icon: Icon, _ title: String) -> some View {
        if settings.data.toolbarLabels {
            VStack(spacing: 2) {
                icon
                Text(title).font(.system(size: 10, weight: .medium)).lineLimit(1)
            }
            .frame(width: 60, height: 48)
            .contentShape(Rectangle())
        } else {
            icon
                .frame(width: 44, height: 40)
                .contentShape(Rectangle())
        }
    }

    private func icon(for item: ToolbarAction) -> some View {
        var symbol = item.symbol
        if item == .bookmarks && library.isBookmarked(tab.url) { symbol = "book.fill" }
        if item == .desktop && tab.desktopMode { symbol = "iphone" }
        return labeled(Image(systemName: symbol), item.shortTitle)
    }

    private func isDisabled(_ item: ToolbarAction) -> Bool {
        switch item {
        case .back: return !tab.canGoBack && tab.showsHome
        case .forward: return !tab.canGoForward
        case .share, .reload, .find, .desktop: return tab.showsHome
        default: return false
        }
    }

    private var tabsButton: some View {
        Button { settings.haptic(); perform(.tabs) } label: {
            labeled(
                ZStack {
                    RoundedRectangle(cornerRadius: 5, style: .continuous)
                        .strokeBorder(lineWidth: 1.8)
                        .frame(width: 22, height: 22)
                    Text("\(tabs.tabs(isPrivate: tab.isPrivate).count)")
                        .font(.system(size: 11, weight: .bold, design: .rounded))
                        .contentTransition(.numericText())
                        .animation(.spring(response: 0.3), value: tabs.tabs(isPrivate: tab.isPrivate).count)
                },
                "Tabs")
        }
        .buttonStyle(PressableStyle())
        .frame(maxWidth: .infinity)
        .contextMenu {
            Button { tabs.newTab(isPrivate: false) } label: { Label("New Tab", systemImage: "plus.square.on.square") }
            Button { tabs.newTab(isPrivate: true) } label: { Label("New Private Tab", systemImage: "eyeglasses") }
            Divider()
            Button(role: .destructive) { tabs.close(tab) } label: { Label("Close This Tab", systemImage: "xmark") }
        }
    }
}

// MARK: - Tab strip (Firefox / iPad style)

struct TabStrip: View {
    @EnvironmentObject var tabs: TabManager
    @EnvironmentObject var settings: BrowserSettings
    let isPrivate: Bool

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 6) {
                    ForEach(tabs.tabs(isPrivate: isPrivate)) { tab in
                        TabChip(tab: tab, selected: tab === tabs.selectedTab)
                            .id(tab.id)
                            .onTapGesture { tabs.select(tab) }
                    }
                    Button { tabs.newTab(isPrivate: isPrivate) } label: {
                        Image(systemName: "plus").frame(width: 30, height: 30)
                    }
                }
                .padding(.horizontal, 10)
            }
            .onChange(of: tabs.selectedTab?.id) { id in
                if let id { withAnimation { proxy.scrollTo(id, anchor: .center) } }
            }
        }
        .frame(height: 36)
    }
}

private struct TabChip: View {
    @ObservedObject var tab: BrowserTab
    let selected: Bool
    @EnvironmentObject var tabs: TabManager
    @EnvironmentObject var settings: BrowserSettings

    var body: some View {
        HStack(spacing: 6) {
            Text(tab.displayTitle).font(.caption.weight(selected ? .semibold : .regular)).lineLimit(1)
            Button { tabs.close(tab) } label: {
                Image(systemName: "xmark").font(.system(size: 9, weight: .bold))
            }
            .buttonStyle(.plain)
            .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 10)
        .frame(width: 150, height: 30)
        .background(
            RoundedRectangle(cornerRadius: min(settings.data.barCornerRadius, 10), style: .continuous)
                .fill(selected ? settings.accent.opacity(0.22) : Color(uiColor: .tertiarySystemFill))
        )
    }
}

// MARK: - Suggestions

struct SuggestionsView: View {
    let query: String
    var onPick: (String) -> Void

    @EnvironmentObject var settings: BrowserSettings
    @EnvironmentObject var library: LibraryStore
    @State private var remote: [String] = []

    var body: some View {
        List {
            if !query.isEmpty {
                Button { onPick(query) } label: {
                    Label {
                        Text("Search DuckDuckGo for “\(query)”").lineLimit(1)
                    } icon: { Image(systemName: "magnifyingglass").foregroundStyle(settings.accent) }
                }
            }
            if !remote.isEmpty {
                Section("DuckDuckGo Suggestions") {
                    ForEach(remote, id: \.self) { s in
                        Button { onPick(s) } label: {
                            HStack {
                                Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
                                Text(s).foregroundStyle(.primary)
                                Spacer()
                            }
                        }
                    }
                }
            }
            let local = library.suggestions(for: query)
            if !local.isEmpty {
                Section("Bookmarks & History") {
                    ForEach(local, id: \.url) { item in
                        Button { onPick(item.url) } label: {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(item.title.isEmpty ? item.url : item.title).foregroundStyle(.primary).lineLimit(1)
                                Text(item.url).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                            }
                        }
                    }
                }
            }
            if query.isEmpty {
                Section {
                    Label("Tip: DuckDuckGo !bangs work here — try “!w saints” or “!gh swift”.", systemImage: "lightbulb")
                        .font(.footnote).foregroundStyle(.secondary)
                }
            }
        }
        .listStyle(.insetGrouped)
        .scrollDismissesKeyboard(.immediately)
        .onChange(of: query) { q in fetch(q) }
        .onAppear { fetch(query) }
    }

    private func fetch(_ q: String) {
        guard settings.data.searchSuggestions, q.count > 1, !q.contains("://") else { remote = []; return }
        SuggestionService.shared.suggestions(for: q) { remote = $0 }
    }
}
