import SwiftUI
import UIKit

struct WallpaperView: View {
    @EnvironmentObject var settings: BrowserSettings
    var isPrivate: Bool = false

    static var photoURL: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Saints/wallpaper.jpg")
    }

    private static var cached: (stamp: Double, image: UIImage)?

    static func loadPhoto(stamp: Double) -> UIImage? {
        if let cached, cached.stamp == stamp { return cached.image }
        guard let image = UIImage(contentsOfFile: photoURL.path) else { return nil }
        cached = (stamp, image)
        return image
    }

    var body: some View {
        ZStack {
            if isPrivate {
                LinearGradient(colors: [Color(hex: "#1E1530"), Color(hex: "#3B2667")], startPoint: .top, endPoint: .bottom)
            } else {
                switch settings.data.wallpaper {
                case .none:
                    settings.data.theme == .black ? Color.black : Color(uiColor: .systemBackground)
                case .solid:
                    settings.solidWallpaperBinding.wrappedValue
                case .photo:
                    if let image = Self.loadPhoto(stamp: settings.data.wallpaperStamp) {
                        GeometryReader { geo in
                            Image(uiImage: image).resizable().scaledToFill()
                                .frame(width: geo.size.width, height: geo.size.height).clipped()
                        }
                    } else {
                        Color(uiColor: .systemBackground)
                    }
                default:
                    LinearGradient(colors: settings.data.wallpaper.gradient ?? [.clear], startPoint: .topLeading, endPoint: .bottomTrailing)
                }
                if settings.data.wallpaper != .none {
                    Color.black.opacity(settings.data.wallpaperDim)
                }
            }
        }
        .ignoresSafeArea()
    }
}

struct HomePageView: View {
    @ObservedObject var tab: BrowserTab
    var onSearchTap: () -> Void

    @EnvironmentObject var settings: BrowserSettings
    @EnvironmentObject var library: LibraryStore
    @ObservedObject private var stats = PrivacyStats.shared
    @State private var editingBookmark: Bookmark?

    private var onWallpaper: Bool { tab.isPrivate || settings.data.wallpaper != .none }

    private var greeting: String {
        if !settings.data.greeting.isEmpty { return settings.data.greeting }
        if tab.isPrivate { return "Private Browsing" }
        let hour = Calendar.current.component(.hour, from: Date())
        switch hour {
        case 5..<12: return "Good morning"
        case 12..<18: return "Good afternoon"
        default: return "Good evening"
        }
    }

    var body: some View {
        ZStack {
            WallpaperView(isPrivate: tab.isPrivate)
            ScrollView {
                VStack(spacing: 26) {
                    Spacer(minLength: 40)
                    if settings.data.showLogo {
                        SaintsLogo(size: 46)
                            .foregroundStyle(onWallpaper ? Color.white : Color.primary)
                    }
                    Text(greeting)
                        .font(.title3.weight(.medium))
                        .foregroundStyle(onWallpaper ? Color.white.opacity(0.9) : Color.secondary)

                    Button(action: onSearchTap) {
                        HStack {
                            Image(systemName: "magnifyingglass")
                            Text("Search privately with DuckDuckGo")
                            Spacer()
                        }
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 16)
                        .frame(height: 50)
                        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: settings.data.barCornerRadius + 4, style: .continuous))
                    }
                    .buttonStyle(.plain)
                    .padding(.horizontal, 24)

                    if tab.isPrivate {
                        privateCard
                    }
                    if settings.data.showFavorites && !library.favorites.isEmpty {
                        favorites
                    }
                    if settings.data.showPrivacyStats && !tab.isPrivate {
                        statsCard
                    }
                    Spacer(minLength: 30)
                }
                .frame(maxWidth: 640)
                .frame(maxWidth: .infinity)
            }
            .scrollDismissesKeyboard(.immediately)
        }
        .sheet(item: $editingBookmark) { b in
            BookmarkEditor(bookmark: b)
        }
    }

    private var favorites: some View {
        let columns = Array(repeating: GridItem(.flexible(), spacing: 12), count: max(3, min(settings.data.favoritesColumns, 6)))
        return VStack(alignment: .leading, spacing: 12) {
            Text("Favorites").font(.headline)
                .foregroundStyle(onWallpaper ? Color.white : Color.primary)
            LazyVGrid(columns: columns, spacing: 16) {
                ForEach(library.favorites) { b in
                    Button {
                        if let url = URL(string: b.url) { tab.load(url) }
                    } label: {
                        VStack(spacing: 6) {
                            FaviconView(urlString: b.url, size: 56)
                            Text(b.title).font(.caption2).lineLimit(1)
                                .foregroundStyle(onWallpaper ? Color.white : Color.primary)
                        }
                    }
                    .buttonStyle(.plain)
                    .contextMenu {
                        Button { editingBookmark = b } label: { Label("Edit", systemImage: "pencil") }
                        Button { TabManager.shared.newTab(url: URL(string: b.url), isPrivate: tab.isPrivate) } label: {
                            Label("Open in New Tab", systemImage: "plus.square.on.square")
                        }
                        Button(role: .destructive) { library.remove(b) } label: { Label("Remove", systemImage: "trash") }
                    }
                }
            }
        }
        .padding(18)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
        .padding(.horizontal, 16)
    }

    private var statsCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("Privacy Protection", systemImage: "shield.lefthalf.filled").font(.headline)
            HStack(spacing: 10) {
                stat("\(stats.linksCleaned)", "Tracking links cleaned")
                stat("\(stats.httpsUpgrades)", "HTTPS upgrades")
            }
            HStack(spacing: 6) {
                pill("Trackers", on: settings.data.blockTrackers)
                pill("Ads", on: settings.data.blockAds)
                pill("Cookie pop-ups", on: settings.data.blockCookieBanners)
                pill("GPC", on: settings.data.globalPrivacyControl)
            }
            Text("Saints has no telemetry, no analytics and no accounts. These numbers never leave your device.")
                .font(.caption).foregroundStyle(.secondary)
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
        .padding(.horizontal, 16)
    }

    private var privateCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("You're in a private tab", systemImage: "eyeglasses").font(.headline)
            Text("Saints won't remember pages you visit, searches, or cookies once you close all private tabs. Extensions are off here unless you allow them.")
                .font(.subheadline).foregroundStyle(.secondary)
        }
        .foregroundStyle(.white)
        .padding(18)
        .background(Color.white.opacity(0.08), in: RoundedRectangle(cornerRadius: 22, style: .continuous))
        .padding(.horizontal, 16)
    }

    private func stat(_ value: String, _ label: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(value).font(.title2.weight(.bold)).foregroundStyle(settings.accent)
            Text(label).font(.caption).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(Color(uiColor: .tertiarySystemFill), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    }

    private func pill(_ text: String, on: Bool) -> some View {
        HStack(spacing: 3) {
            Image(systemName: on ? "checkmark" : "xmark").font(.system(size: 9, weight: .bold))
            Text(text).font(.caption2.weight(.semibold))
        }
        .padding(.horizontal, 8).padding(.vertical, 5)
        .background((on ? Color.green : Color.gray).opacity(0.18), in: Capsule())
        .foregroundStyle(on ? Color.green : Color.secondary)
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
