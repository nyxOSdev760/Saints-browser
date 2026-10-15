import SwiftUI
import UIKit

struct WallpaperView: View {
    @EnvironmentObject var settings: BrowserSettings
    var isPrivate: Bool = false
    /// Small previews skip the blur so thumbnails stay crisp and cheap.
    var preview: Bool = false

    var body: some View {
        GeometryReader { geo in
            ZStack {
                if isPrivate {
                    LinearGradient(colors: [Color(hex: "#1E1530"), Color(hex: "#3B2667")], startPoint: .top, endPoint: .bottom)
                } else {
                    base(size: geo.size)
                        .blur(radius: preview ? settings.data.wallpaperBlur / 6 : settings.data.wallpaperBlur)
                        .scaleEffect(settings.data.wallpaperBlur > 0 ? 1.08 : 1)   // hide blurred edges
                    if settings.data.wallpaper != .none && settings.data.wallpaperDim > 0 {
                        Color.black.opacity(settings.data.wallpaperDim)
                    }
                }
            }
            .frame(width: geo.size.width, height: geo.size.height)
            .clipped()
        }
        .ignoresSafeArea()
    }

    @ViewBuilder private func base(size: CGSize) -> some View {
        switch settings.data.wallpaper {
        case .none:
            settings.data.theme == .black ? Color.black : Color(uiColor: .systemBackground)
        case .solid:
            Color(hex: settings.data.wallpaperSolidHex)
        case .photo:
            if let image = WallpaperStore.shared.image(settings.data.wallpaperPhotoID) {
                Image(uiImage: image).resizable().scaledToFill()
                    .frame(width: size.width, height: size.height)
                    .clipped()
            } else {
                Color(uiColor: .systemBackground)
            }
        default:
            LinearGradient(colors: settings.data.wallpaper.gradient ?? [.clear], startPoint: .topLeading, endPoint: .bottomTrailing)
        }
    }
}

struct HomePageView: View {
    @ObservedObject var tab: BrowserTab
    /// True while the home search field is focused (the browser hides its bottom bars meanwhile).
    @Binding var searching: Bool

    @EnvironmentObject var settings: BrowserSettings
    @EnvironmentObject var library: LibraryStore
    @ObservedObject private var stats = PrivacyStats.shared
    @ObservedObject private var ublock = UBlockEngine.shared
    @State private var editingBookmark: Bookmark?
    @State private var query = ""
    @State private var remote: [String] = []
    @FocusState private var fieldFocused: Bool
    @State private var appeared = false

    private var onWallpaper: Bool { tab.isPrivate || settings.data.wallpaper != .none }
    /// White text on dark wallpapers, dark text on light ones, unless the user picked a style.
    private var lightInk: Bool {
        if tab.isPrivate { return true }
        switch settings.data.homeTextStyle {
        case .light: return true
        case .dark: return false
        case .auto:
            let w = settings.data.wallpaper
            if w == .none { return false }
            if w == .solid { return Color(hex: settings.data.wallpaperSolidHex).isLightColor == false }
            return !w.isLight
        }
    }
    private var ink: Color {
        if settings.data.homeTextStyle == .auto && settings.data.wallpaper == .none && !tab.isPrivate { return .primary }
        return lightInk ? .white : .black
    }
    private var subInk: Color { ink.opacity(0.75) }

    private var greeting: String {
        if !settings.data.greeting.isEmpty { return settings.data.greeting }
        if tab.isPrivate { return "Private Browsing" }
        switch Calendar.current.component(.hour, from: Date()) {
        case 5..<12: return "Good morning"
        case 12..<18: return "Good afternoon"
        default: return "Good evening"
        }
    }

    var body: some View {
        ZStack {
            WallpaperView(isPrivate: tab.isPrivate)
                .onTapGesture { fieldFocused = false }
            ScrollView {
                // The address bar is the one search field; the start page just shows shortcuts.
                VStack(spacing: 28) {
                    if settings.data.showGreeting { header }
                    if tab.isPrivate { privateNote }
                    if settings.data.showFavorites && !library.favorites.isEmpty { favorites }
                    if settings.data.showRecent && !tab.isPrivate && !recent.isEmpty { recentSection }
                    if settings.data.showPrivacyStats && !tab.isPrivate { privacyLine }
                }
                .padding(.top, settings.data.showGreeting ? 48 : 28)
                .padding(.bottom, 30)
                .padding(.horizontal, 18)
                .frame(maxWidth: 620)
                .frame(maxWidth: .infinity)
            }
            .scrollDismissesKeyboard(.interactively)
        }
        .animation(.spring(response: 0.32, dampingFraction: 0.88), value: fieldFocused)
        .onChange(of: fieldFocused) { focused in
            searching = focused
            if !focused { query = "" }
        }
        .onChange(of: query) { fetchSuggestions($0) }
        .onDisappear { searching = false; appeared = false }
        .onAppear { appeared = true }
        .sheet(item: $editingBookmark) { BookmarkEditor(bookmark: $0) }
    }

    // MARK: Header & search

    private var header: some View {
        VStack(spacing: 10) {
            if settings.data.showGreeting {
                Text(greeting)
                    .font(.headline)
                    .foregroundStyle(subInk)
            }
        }
    }

    private var searchField: some View {
        HStack(spacing: 10) {
            HStack(spacing: 10) {
                Image(systemName: "magnifyingglass")
                    .font(.body.weight(.medium))
                    .foregroundStyle(.secondary)
                TextField("Search or enter address", text: $query)
                    .focused($fieldFocused)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .keyboardType(.webSearch)
                    .submitLabel(.go)
                    .onSubmit { go(query) }
                if !query.isEmpty {
                    Button { query = "" } label: {
                        Image(systemName: "xmark.circle.fill").foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 16)
            .frame(height: 52)
            .background(fieldBackground)
            .overlay(
                RoundedRectangle(cornerRadius: fieldRadius, style: .continuous)
                    .strokeBorder(fieldFocused ? settings.accent : Color.primary.opacity(0.06), lineWidth: fieldFocused ? 2 : 1)
            )
            .shadow(color: .black.opacity(onWallpaper ? 0.18 : 0.06), radius: 12, y: 4)
            .contentShape(Rectangle())
            .onTapGesture { fieldFocused = true }

            if fieldFocused {
                Button("Cancel") { fieldFocused = false }
                    .foregroundStyle(ink)
                    .transition(.move(edge: .trailing).combined(with: .opacity))
            }
        }
    }

    private var fieldRadius: CGFloat { min(26, settings.data.searchFieldRoundness) }

    @ViewBuilder private var fieldBackground: some View {
        if settings.data.barMaterial == .glass {
            GlassSurface(shape: RoundedRectangle(cornerRadius: fieldRadius, style: .continuous), isPrivate: tab.isPrivate, shadow: false)
        } else if onWallpaper {
            RoundedRectangle(cornerRadius: fieldRadius, style: .continuous).fill(.regularMaterial)
        } else {
            RoundedRectangle(cornerRadius: fieldRadius, style: .continuous).fill(Color(uiColor: .secondarySystemBackground))
        }
    }

    // MARK: Suggestions

    private var suggestions: some View {
        let trimmed = query.trimmingCharacters(in: .whitespaces)
        let local = library.suggestions(for: trimmed, limit: 4)
        return VStack(spacing: 0) {
            if trimmed.isEmpty {
                if !recent.isEmpty {
                    sectionTitle("Recently Visited")
                    ForEach(recent.prefix(5), id: \.url) { item in
                        suggestionRow(icon: "clock", title: item.title, subtitle: item.url) { go(item.url) }
                    }
                } else {
                    Text("Type to search privately with DuckDuckGo. Try a !bang like “!w saints”.")
                        .font(.subheadline).foregroundStyle(subInk)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.top, 8)
                }
            } else {
                suggestionRow(icon: "magnifyingglass", title: trimmed, subtitle: "Search DuckDuckGo", bold: true) { go(trimmed) }
                ForEach(remote.filter { $0.lowercased() != trimmed.lowercased() }, id: \.self) { s in
                    suggestionRow(icon: "magnifyingglass", title: s, fill: { query = s + " " }) { go(s) }
                }
                if !local.isEmpty {
                    sectionTitle("Bookmarks & History")
                    ForEach(local, id: \.url) { item in
                        suggestionRow(icon: "globe", title: item.title.isEmpty ? item.url : item.title, subtitle: item.url) { go(item.url) }
                    }
                }
            }
        }
        .padding(.vertical, 6)
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(onWallpaper ? AnyShapeStyle(.regularMaterial) : AnyShapeStyle(Color(uiColor: .secondarySystemBackground)))
        )
    }

    private func sectionTitle(_ text: String) -> some View {
        Text(text)
            .font(.caption.weight(.semibold))
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 16)
            .padding(.top, 10)
            .padding(.bottom, 4)
    }

    private func suggestionRow(icon: String, title: String, subtitle: String? = nil, bold: Bool = false,
                               fill: (() -> Void)? = nil, action: @escaping () -> Void) -> some View {
        HStack(spacing: 12) {
            Button(action: action) {
                HStack(spacing: 12) {
                    Image(systemName: icon)
                        .font(.subheadline)
                        .foregroundStyle(bold ? settings.accent : Color.secondary)
                        .frame(width: 22)
                    VStack(alignment: .leading, spacing: 1) {
                        Text(title).font(bold ? .body.weight(.semibold) : .body).lineLimit(1).foregroundStyle(.primary)
                        if let subtitle {
                            Text(subtitle).font(.caption).lineLimit(1).foregroundStyle(.secondary)
                        }
                    }
                    Spacer(minLength: 0)
                }
                .padding(.vertical, 10)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            if let fill {
                Button(action: fill) {
                    Image(systemName: "arrow.up.left").font(.subheadline).foregroundStyle(.secondary)
                        .frame(width: 36, height: 36).contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 16)
    }

    private func fetchSuggestions(_ q: String) {
        let trimmed = q.trimmingCharacters(in: .whitespaces)
        guard settings.data.searchSuggestions, trimmed.count > 1, !trimmed.contains("://") else { remote = []; return }
        SuggestionService.shared.suggestions(for: trimmed) { results in
            if trimmed == query.trimmingCharacters(in: .whitespaces) { remote = Array(results.prefix(5)) }
        }
    }

    private func go(_ text: String) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        fieldFocused = false
        settings.haptic()
        tab.loadInput(trimmed)
    }

    // MARK: Sections

    private var recent: [LocalSuggestion] {
        var seen = Set<String>()
        var out: [LocalSuggestion] = []
        for h in library.history {
            guard let host = URL(string: h.url)?.host, seen.insert(host).inserted else { continue }
            out.append(LocalSuggestion(title: h.title.isEmpty ? host : h.title, url: h.url))
            if out.count == 8 { break }
        }
        return out
    }

    private var favorites: some View {
        let columns = Array(repeating: GridItem(.flexible(), spacing: 8), count: max(3, min(settings.data.favoritesColumns, 6)))
        return VStack(alignment: .leading, spacing: 14) {
            Text("Favorites").font(.title3.weight(.bold)).foregroundStyle(ink)
            LazyVGrid(columns: columns, spacing: 18) {
                ForEach(Array(library.favorites.enumerated()), id: \.element.id) { index, b in
                    Button {
                        if let url = URL(string: b.url) { settings.haptic(); tab.load(url) }
                    } label: {
                        VStack(spacing: 7) {
                            FaviconView(urlString: b.url, size: 60, cornerFraction: settings.data.favoriteShape.cornerFraction)
                                .shadow(color: .black.opacity(0.08), radius: 4, y: 2)
                            Text(b.title)
                                .font(.caption)
                                .lineLimit(1)
                                .foregroundStyle(ink)
                        }
                        .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(CardPressStyleHome())
                    .contextMenu {
                        Button { TabManager.shared.newTab(url: URL(string: b.url), isPrivate: tab.isPrivate) } label: {
                            Label("Open in New Tab", systemImage: "plus.square.on.square")
                        }
                        Button { TabManager.shared.newTab(url: URL(string: b.url), isPrivate: true) } label: {
                            Label("Open in Private Tab", systemImage: "eyeglasses")
                        }
                        Button { editingBookmark = b } label: { Label("Edit", systemImage: "pencil") }
                        Button(role: .destructive) { library.remove(b) } label: { Label("Remove", systemImage: "trash") }
                    }
                    .opacity(appeared ? 1 : 0)
                    .offset(y: appeared ? 0 : 14)
                    .scaleEffect(appeared ? 1 : 0.92)
                    .animation(.spring(response: 0.45, dampingFraction: 0.8).delay(Double(index) * 0.035), value: appeared)
                }
            }
        }
    }

    private var recentSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Recently Visited").font(.title3.weight(.bold)).foregroundStyle(ink)
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 10) {
                    ForEach(recent, id: \.url) { item in
                        Button { go(item.url) } label: {
                            HStack(spacing: 10) {
                                FaviconView(urlString: item.url, size: 32)
                                VStack(alignment: .leading, spacing: 1) {
                                    Text(item.title).font(.subheadline.weight(.medium)).lineLimit(1)
                                    Text(URL(string: item.url)?.host ?? "").font(.caption).foregroundStyle(.secondary).lineLimit(1)
                                }
                            }
                            .padding(10)
                            .frame(width: 210, alignment: .leading)
                            .background(tileBackground)
                        }
                        .buttonStyle(CardPressStyleHome())
                    }
                }
            }
        }
    }

    @ViewBuilder private var tileBackground: some View {
        if onWallpaper {
            RoundedRectangle(cornerRadius: 14, style: .continuous).fill(.regularMaterial)
        } else {
            RoundedRectangle(cornerRadius: 14, style: .continuous).fill(Color(uiColor: .secondarySystemBackground))
        }
    }

    private var privacyLine: some View {
        HStack(spacing: 12) {
            UBlockBadge(size: 30)
            VStack(alignment: .leading, spacing: 2) {
                Text(ublock.state.enabled ? "uBlock Origin · \(ublock.status.text)" : "uBlock Origin is off")
                    .font(.subheadline.weight(.semibold))
                    .lineLimit(1)
                Text("\(stats.linksCleaned) tracking links cleaned · \(stats.httpsUpgrades) HTTPS upgrades · nothing leaves this device")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }
            Spacer(minLength: 0)
        }
        .padding(12)
        .background(tileBackground)
    }

    private var privateNote: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: "eyeglasses").font(.title2)
            VStack(alignment: .leading, spacing: 4) {
                Text("Private tab").font(.headline)
                Text("No history, cookies or cache are kept after you close all private tabs.")
                    .font(.subheadline).opacity(0.8)
            }
            Spacer(minLength: 0)
        }
        .foregroundStyle(.white)
        .padding(14)
        .background(Color.white.opacity(0.1), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    }
}

private struct CardPressStyleHome: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.94 : 1)
            .opacity(configuration.isPressed ? 0.85 : 1)
            .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
    }
}

struct BookmarkEditor: View {
    @State var bookmark: Bookmark
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Form {
                TextField("Title", text: $bookmark.title)
                TextField("Address", text: $bookmark.url)
                    .textInputAutocapitalization(.never).autocorrectionDisabled().keyboardType(.URL)
                Toggle("Show on Home Page", isOn: $bookmark.isFavorite)
            }
            .navigationTitle("Edit Bookmark")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { LibraryStore.shared.update(bookmark); dismiss() }
                }
            }
        }
        .presentationDetents([.medium])
    }
}
