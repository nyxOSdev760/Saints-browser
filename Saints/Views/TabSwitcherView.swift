import SwiftUI

/// Safari-style tab overview: portrait thumbnails with titles underneath, a tab-group menu in the
/// bottom bar (Tabs / Private) between "+" and "Done".
struct TabSwitcherView: View {
    @Binding var isPresented: Bool
    @State var showingPrivate: Bool
    @State private var search = ""
    @State private var confirmCloseAll = false

    @EnvironmentObject var tabs: TabManager
    @EnvironmentObject var settings: BrowserSettings
    @EnvironmentObject var library: LibraryStore

    private var allInGroup: [BrowserTab] { tabs.tabs(isPrivate: showingPrivate) }

    private var list: [BrowserTab] {
        guard !search.isEmpty else { return allInGroup }
        let q = search.lowercased()
        return allInGroup.filter {
            $0.displayTitle.lowercased().contains(q) || ($0.url?.absoluteString.lowercased().contains(q) ?? false)
        }
    }

    private var background: Color {
        if showingPrivate { return Color(hex: "#1C1C1E") }
        return settings.data.theme == .black ? .black : Color(uiColor: .systemGroupedBackground)
    }

    var body: some View {
        VStack(spacing: 0) {
            if allInGroup.isEmpty {
                emptyState
            } else if settings.data.tabLayout == .grid {
                grid
            } else {
                listView
            }
            bottomBar
        }
        .background(background.ignoresSafeArea())
        .if(showingPrivate) { $0.environment(\.colorScheme, .dark) }
        .confirmationDialog("Close all \(allInGroup.count) \(showingPrivate ? "private " : "")tabs?",
                            isPresented: $confirmCloseAll, titleVisibility: .visible) {
            Button("Close \(allInGroup.count) Tabs", role: .destructive) {
                tabs.closeAll(isPrivate: showingPrivate)
                if !showingPrivate { isPresented = false }
            }
        }
    }

    // MARK: Search

    private var searchField: some View {
        HStack(spacing: 6) {
            Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
            TextField(showingPrivate ? "Search Private Tabs" : "Search Tabs", text: $search)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
            if !search.isEmpty {
                Button { search = "" } label: { Image(systemName: "xmark.circle.fill").foregroundStyle(.secondary) }
                    .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 10)
        .frame(height: 36)
        .background(Color(uiColor: .tertiarySystemFill), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
    }

    // MARK: Grid

    private var grid: some View {
        let count = max(1, min(settings.data.tabGridColumns, 4))
        let columns = Array(repeating: GridItem(.flexible(), spacing: 18), count: count)
        return ScrollViewReader { proxy in
            ScrollView {
                VStack(spacing: 16) {
                    searchField
                    LazyVGrid(columns: columns, spacing: 22) {
                        ForEach(list) { tab in
                            SafariTabCard(tab: tab, selected: tab === tabs.selectedTab,
                                          onTap: { choose(tab) },
                                          onClose: { close(tab) },
                                          onCloseOthers: { closeOthers(than: tab) })
                                .id(tab.id)
                                .transition(.scale(scale: 0.8).combined(with: .opacity))
                        }
                    }
                }
                .padding(.horizontal, 18)
                .padding(.top, 12)
                .padding(.bottom, 20)
                .animation(.spring(response: 0.32, dampingFraction: 0.85), value: list.map(\.id))
            }
            .scrollDismissesKeyboard(.immediately)
            .onAppear {
                if let id = tabs.selectedTab?.id { proxy.scrollTo(id, anchor: .center) }
            }
        }
    }

    // MARK: List

    private var listView: some View {
        List {
            Section {
                searchField
                    .listRowBackground(Color.clear)
                    .listRowInsets(EdgeInsets(top: 4, leading: 0, bottom: 4, trailing: 0))
            }
            ForEach(list) { tab in
                HStack(spacing: 12) {
                    Button { choose(tab) } label: {
                        HStack(spacing: 12) {
                            if let url = tab.url {
                                FaviconView(urlString: url.absoluteString, size: 34)
                            } else {
                                Image(systemName: "house").frame(width: 34, height: 34)
                            }
                            VStack(alignment: .leading, spacing: 2) {
                                Text(tab.displayTitle).lineLimit(1).foregroundStyle(.primary)
                                Text(tab.url?.host ?? "Start Page").font(.caption).foregroundStyle(.secondary)
                            }
                            Spacer()
                            if tab === tabs.selectedTab {
                                Image(systemName: "checkmark").foregroundStyle(settings.accent)
                            }
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.borderless)
                    Button { close(tab) } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.title3)
                            .foregroundStyle(.secondary)
                            .frame(width: 40, height: 40)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.borderless)
                    .accessibilityLabel("Close tab")
                }
                .swipeActions {
                    Button(role: .destructive) { close(tab) } label: { Label("Close", systemImage: "xmark") }
                }
            }
        }
        .listStyle(.insetGrouped)
        .scrollContentBackground(.hidden)
    }

    // MARK: Empty

    private var emptyState: some View {
        VStack(spacing: 10) {
            Spacer()
            if showingPrivate {
                Text("Private Browsing").font(.title2.weight(.bold))
                Text("SV Browser won't remember the pages you visit, your search history or AutoFill information after you close a private tab.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 40)
            } else {
                Image(systemName: "square.on.square").font(.system(size: 40)).foregroundStyle(.secondary)
                Text("No Open Tabs").font(.title3.weight(.semibold))
            }
            Spacer()
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: Bottom bar

    private var groupTitle: String {
        if showingPrivate {
            return tabs.privateTabs.isEmpty ? "Private" : "\(tabs.privateTabs.count) Private Tab\(tabs.privateTabs.count == 1 ? "" : "s")"
        }
        return "\(tabs.normalTabs.count) Tab\(tabs.normalTabs.count == 1 ? "" : "s")"
    }

    private var bottomBar: some View {
        HStack {
            Button {
                settings.haptic()
                tabs.newTab(isPrivate: showingPrivate)
                isPresented = false
            } label: {
                Image(systemName: "plus").font(.title2.weight(.regular)).frame(width: 44, height: 44)
            }
            .frame(minWidth: 70, alignment: .leading)

            Spacer()

            Menu {
                Section {
                    Button { switchGroup(private: false) } label: {
                        Label("\(tabs.normalTabs.count) Tab\(tabs.normalTabs.count == 1 ? "" : "s")",
                              systemImage: showingPrivate ? "square.on.square" : "checkmark")
                    }
                    Button { switchGroup(private: true) } label: {
                        Label("Private", systemImage: showingPrivate ? "checkmark" : "hand.raised")
                    }
                }
                Section {
                    Picker("Layout", selection: $settings.data.tabLayout) {
                        Label("Grid", systemImage: "square.grid.2x2").tag(TabLayout.grid)
                        Label("List", systemImage: "list.bullet").tag(TabLayout.list)
                    }
                }
                if !allInGroup.isEmpty {
                    Section {
                        Button(role: .destructive) { confirmCloseAll = true } label: {
                            Label("Close All \(allInGroup.count) Tabs", systemImage: "xmark")
                        }
                    }
                }
            } label: {
                HStack(spacing: 4) {
                    Text(groupTitle).font(.body.weight(.semibold))
                    Image(systemName: "chevron.down").font(.caption.weight(.bold))
                }
                .foregroundStyle(.primary)
                .padding(.horizontal, 12)
                .frame(height: 36)
                .contentShape(Rectangle())
            }

            Spacer()

            Button("Done") { finish() }
                .font(.body.weight(.semibold))
                .frame(minWidth: 70, alignment: .trailing)
        }
        .padding(.horizontal, 14)
        .frame(height: 52)
        .background(.bar)
    }

    // MARK: Actions

    private func switchGroup(private isPrivate: Bool) {
        settings.haptic()
        withAnimation(.easeInOut(duration: 0.2)) { showingPrivate = isPrivate }
        search = ""
    }

    private func choose(_ tab: BrowserTab) {
        settings.haptic()
        tabs.select(tab)
        isPresented = false
    }

    private func close(_ tab: BrowserTab) {
        settings.haptic()
        withAnimation(.spring(response: 0.3, dampingFraction: 0.85)) { tabs.close(tab) }
    }

    private func closeOthers(than keep: BrowserTab) {
        for tab in allInGroup where tab !== keep { tabs.close(tab) }
    }

    private func finish() {
        if let selected = tabs.selectedTab, selected.isPrivate != showingPrivate {
            if let last = allInGroup.last {
                tabs.select(last)
            } else if showingPrivate {
                tabs.newTab(isPrivate: true)
            }
        }
        isPresented = false
    }
}

/// A Safari-style tab thumbnail: page preview with a close button, title underneath.
private struct SafariTabCard: View {
    @ObservedObject var tab: BrowserTab
    let selected: Bool
    var onTap: () -> Void
    var onClose: () -> Void
    var onCloseOthers: () -> Void

    @EnvironmentObject var settings: BrowserSettings
    @EnvironmentObject var library: LibraryStore
    @State private var dragX: CGFloat = 0

    private let radius: CGFloat = 14

    var body: some View {
        VStack(spacing: 8) {
            Button(action: onTap) { thumbnail }
                .buttonStyle(ThumbPressStyle())
                // Sibling of the thumbnail button, never nested in it, so the ✕ always closes.
                .overlay(alignment: .topTrailing) { closeButton }
                .contextMenu { menu }

            HStack(spacing: 5) {
                if let url = tab.url {
                    FaviconView(urlString: url.absoluteString, size: 14, cornerFraction: 0.25)
                } else {
                    Image(systemName: tab.isPrivate ? "hand.raised.fill" : "star.fill")
                        .font(.system(size: 10))
                        .foregroundStyle(.secondary)
                }
                Text(tab.showsHome ? "Start Page" : tab.displayTitle)
                    .font(.caption.weight(.medium))
                    .lineLimit(1)
            }
            .padding(.horizontal, 4)
            .frame(maxWidth: .infinity)
            .onTapGesture(perform: onTap)
        }
        .offset(x: dragX)
        .opacity(1 - Double(min(abs(dragX), 250) / 320))
        .simultaneousGesture(swipeToClose)
        .onAppear { if !tab.showsHome && tab.snapshot == nil { tab.captureSnapshot() } }
    }

    private var thumbnail: some View {
        Color.clear
            .aspectRatio(0.72, contentMode: .fit)
            .overlay(alignment: .top) { preview }
            .background(Color(uiColor: .secondarySystemBackground))
            .clipShape(RoundedRectangle(cornerRadius: radius, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: radius, style: .continuous)
                    .strokeBorder(Color.primary.opacity(0.08), lineWidth: 0.5)
            )
            .padding(selected ? 3 : 0)
            .overlay(
                RoundedRectangle(cornerRadius: radius + 3, style: .continuous)
                    .strokeBorder(selected ? settings.accent : Color.clear, lineWidth: 3)
            )
            .shadow(color: .black.opacity(0.14), radius: 10, y: 4)
            .contentShape(RoundedRectangle(cornerRadius: radius, style: .continuous))
    }

    @ViewBuilder private var preview: some View {
        if tab.showsHome {
            ZStack {
                WallpaperView(isPrivate: tab.isPrivate, preview: true)
                VStack(spacing: 10) {
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .fill(.regularMaterial)
                        .frame(height: 16)
                        .padding(.horizontal, 16)
                }
            }
        } else if let image = tab.snapshot {
            Image(uiImage: image).resizable().scaledToFill()
        } else {
            Image(systemName: "globe").font(.largeTitle).foregroundStyle(.tertiary)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    private var closeButton: some View {
        Button(action: onClose) {
            Image(systemName: "xmark")
                .font(.system(size: 11, weight: .bold))
                .foregroundStyle(.white)
                .frame(width: 24, height: 24)
                .background(Circle().fill(Color.black.opacity(0.45)))
                .background(Circle().fill(.ultraThinMaterial))
                .frame(width: 44, height: 44)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .padding(selected ? 3 : 0)
        .accessibilityLabel("Close tab")
    }

    @ViewBuilder private var menu: some View {
        if let url = tab.url {
            Button { UIPasteboard.general.url = url } label: { Label("Copy Link", systemImage: "doc.on.doc") }
            Button { library.toggleBookmark(title: tab.title, url: url) } label: {
                Label(library.isBookmarked(url) ? "Remove Bookmark" : "Add Bookmark", systemImage: "book")
            }
            Button { Share.present([url]) } label: { Label("Share", systemImage: "square.and.arrow.up") }
        }
        Divider()
        Button(role: .destructive, action: onCloseOthers) { Label("Close Other Tabs", systemImage: "xmark.square") }
        Button(role: .destructive, action: onClose) { Label("Close Tab", systemImage: "xmark") }
    }

    private var swipeToClose: some Gesture {
        DragGesture(minimumDistance: 30)
            .onChanged { v in
                if abs(v.translation.width) > abs(v.translation.height) * 1.5 { dragX = v.translation.width }
            }
            .onEnded { v in
                if abs(dragX) > 100 {
                    withAnimation(.easeOut(duration: 0.18)) { dragX = v.translation.width > 0 ? 500 : -500 }
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.15, execute: onClose)
                } else {
                    withAnimation(.spring()) { dragX = 0 }
                }
            }
    }
}

private struct ThumbPressStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.96 : 1)
            .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
    }
}
