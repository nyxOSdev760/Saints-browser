import SwiftUI
import UIKit

// MARK: - Option enums

enum ThemeMode: String, Codable, CaseIterable, Identifiable {
    case system, light, dark, black
    var id: String { rawValue }
    var title: String {
        switch self {
        case .system: return "System"
        case .light: return "Light"
        case .dark: return "Dark"
        case .black: return "AMOLED Black"
        }
    }
    var colorScheme: ColorScheme? {
        switch self {
        case .system: return nil
        case .light: return .light
        case .dark, .black: return .dark
        }
    }
}

enum BarPosition: String, Codable, CaseIterable, Identifiable {
    case bottom, top
    var id: String { rawValue }
    var title: String { self == .bottom ? "Bottom (Safari)" : "Top (Firefox)" }
}

enum BarMaterial: String, Codable, CaseIterable, Identifiable {
    case glass, solid, tinted
    var id: String { rawValue }
    var title: String {
        switch self {
        case .glass: return "Glass"
        case .solid: return "Solid"
        case .tinted: return "Accent Tint"
        }
    }
}

enum TabLayout: String, Codable, CaseIterable, Identifiable {
    case grid, list
    var id: String { rawValue }
    var title: String { self == .grid ? "Grid" : "List" }
}

enum SearchFlavor: String, Codable, CaseIterable, Identifiable {
    case standard, lite, html
    var id: String { rawValue }
    var title: String {
        switch self {
        case .standard: return "DuckDuckGo"
        case .lite: return "DuckDuckGo Lite"
        case .html: return "DuckDuckGo HTML (no JavaScript)"
        }
    }
}

enum SafeSearch: String, Codable, CaseIterable, Identifiable {
    case strict, moderate, off
    var id: String { rawValue }
    var title: String { rawValue.capitalized }
    /// DuckDuckGo `kp` parameter.
    var kp: String {
        switch self {
        case .strict: return "1"
        case .moderate: return "-1"
        case .off: return "-2"
        }
    }
}

enum AppFontDesign: String, Codable, CaseIterable, Identifiable {
    case standard, rounded, serif, monospaced
    var id: String { rawValue }
    var title: String { rawValue.capitalized }
    var design: Font.Design {
        switch self {
        case .standard: return .default
        case .rounded: return .rounded
        case .serif: return .serif
        case .monospaced: return .monospaced
        }
    }
}

enum WallpaperStyle: String, Codable, CaseIterable, Identifiable {
    case none, halo, sunset, ocean, forest, aurora, mono, solid, photo
    var id: String { rawValue }
    var title: String {
        switch self {
        case .none: return "None"
        case .solid: return "Solid Color"
        case .photo: return "Photo"
        default: return rawValue.capitalized
        }
    }
    var gradient: [Color]? {
        switch self {
        case .halo: return [Color(hex: "#F6D365"), Color(hex: "#FDA085"), Color(hex: "#7F53AC")]
        case .sunset: return [Color(hex: "#FF5F6D"), Color(hex: "#FFC371")]
        case .ocean: return [Color(hex: "#2193B0"), Color(hex: "#6DD5ED")]
        case .forest: return [Color(hex: "#134E5E"), Color(hex: "#71B280")]
        case .aurora: return [Color(hex: "#00C9FF"), Color(hex: "#92FE9D"), Color(hex: "#7F00FF")]
        case .mono: return [Color(hex: "#232526"), Color(hex: "#414345")]
        default: return nil
        }
    }
}

enum ToolbarAction: String, Codable, CaseIterable, Identifiable {
    case back, forward, share, bookmarks, tabs, menu, home, newTab, extensions, reload, find, fire, desktop, privateTab
    var id: String { rawValue }
    var title: String {
        switch self {
        case .back: return "Back"
        case .forward: return "Forward"
        case .share: return "Share"
        case .bookmarks: return "Bookmarks"
        case .tabs: return "Tabs"
        case .menu: return "Menu"
        case .home: return "Home"
        case .newTab: return "New Tab"
        case .extensions: return "Extensions"
        case .reload: return "Reload"
        case .find: return "Find in Page"
        case .fire: return "Burn (Fire Button)"
        case .desktop: return "Desktop Site"
        case .privateTab: return "New Private Tab"
        }
    }
    var symbol: String {
        switch self {
        case .back: return "chevron.backward"
        case .forward: return "chevron.forward"
        case .share: return "square.and.arrow.up"
        case .bookmarks: return "book"
        case .tabs: return "square.on.square"
        case .menu: return "line.3.horizontal"
        case .home: return "house"
        case .newTab: return "plus"
        case .extensions: return "puzzlepiece.extension"
        case .reload: return "arrow.clockwise"
        case .find: return "doc.text.magnifyingglass"
        case .fire: return "flame"
        case .desktop: return "desktopcomputer"
        case .privateTab: return "eyeglasses"
        }
    }
}

// MARK: - Persisted settings

struct SettingsData: Codable, Equatable {
    // Appearance
    var theme: ThemeMode = .system
    var accentHex: String = "#7F53AC"
    var fontDesign: AppFontDesign = .rounded
    var barPosition: BarPosition = .bottom
    var barMaterial: BarMaterial = .glass
    var barCornerRadius: Double = 14
    var compactBars: Bool = false
    var hideBarsOnScroll: Bool = true
    var showTabStrip: Bool = false
    var showFullURL: Bool = false
    var showProgressBar: Bool = true
    var haptics: Bool = true
    var swipeAddressBarToSwitchTabs: Bool = true

    // Toolbar
    var toolbarItems: [ToolbarAction] = [.back, .forward, .share, .tabs, .menu]

    // Tabs
    var tabLayout: TabLayout = .grid
    var tabGridColumns: Int = 2
    var openLinksInBackground: Bool = false
    var restoreTabs: Bool = true

    // Home page
    var wallpaper: WallpaperStyle = .halo
    var wallpaperSolidHex: String = "#1C1C1E"
    var wallpaperDim: Double = 0.15
    var wallpaperStamp: Double = 0
    var showLogo: Bool = true
    var greeting: String = ""
    var showFavorites: Bool = true
    var favoritesColumns: Int = 4
    var showPrivacyStats: Bool = true
    var loadFavicons: Bool = true

    // Search
    var searchFlavor: SearchFlavor = .standard
    var searchRegion: String = "wt-wt"
    var safeSearch: SafeSearch = .moderate
    var searchSuggestions: Bool = true

    // Privacy
    var blockTrackers: Bool = true
    var blockAds: Bool = true
    var blockCookieBanners: Bool = true
    var httpsOnly: Bool = true
    var stripTrackingParams: Bool = true
    var globalPrivacyControl: Bool = true
    var blockPopups: Bool = true
    var javaScriptEnabled: Bool = true
    var saveHistory: Bool = true
    var clearDataOnLaunch: Bool = false
    var privateByDefault: Bool = false
    var webInspector: Bool = false

    // Content
    var defaultZoom: Double = 1.0
    var desktopByDefault: Bool = false
    var customUserAgent: String = ""

    // Extensions
    var extensionsEnabled: Bool = true
    var interceptExtensionDownloads: Bool = true

    init() {}

    init(from decoder: Decoder) throws {
        // Decode leniently so new settings added in updates fall back to defaults.
        self.init()
        let c = try decoder.container(keyedBy: CodingKeys.self)
        func v<T: Decodable>(_ key: CodingKeys, _ current: T) -> T {
            (try? c.decodeIfPresent(T.self, forKey: key)) ?? current
        }
        theme = v(.theme, theme)
        accentHex = v(.accentHex, accentHex)
        fontDesign = v(.fontDesign, fontDesign)
        barPosition = v(.barPosition, barPosition)
        barMaterial = v(.barMaterial, barMaterial)
        barCornerRadius = v(.barCornerRadius, barCornerRadius)
        compactBars = v(.compactBars, compactBars)
        hideBarsOnScroll = v(.hideBarsOnScroll, hideBarsOnScroll)
        showTabStrip = v(.showTabStrip, showTabStrip)
        showFullURL = v(.showFullURL, showFullURL)
        showProgressBar = v(.showProgressBar, showProgressBar)
        haptics = v(.haptics, haptics)
        swipeAddressBarToSwitchTabs = v(.swipeAddressBarToSwitchTabs, swipeAddressBarToSwitchTabs)
        toolbarItems = v(.toolbarItems, toolbarItems)
        tabLayout = v(.tabLayout, tabLayout)
        tabGridColumns = v(.tabGridColumns, tabGridColumns)
        openLinksInBackground = v(.openLinksInBackground, openLinksInBackground)
        restoreTabs = v(.restoreTabs, restoreTabs)
        wallpaper = v(.wallpaper, wallpaper)
        wallpaperSolidHex = v(.wallpaperSolidHex, wallpaperSolidHex)
        wallpaperDim = v(.wallpaperDim, wallpaperDim)
        wallpaperStamp = v(.wallpaperStamp, wallpaperStamp)
        showLogo = v(.showLogo, showLogo)
        greeting = v(.greeting, greeting)
        showFavorites = v(.showFavorites, showFavorites)
        favoritesColumns = v(.favoritesColumns, favoritesColumns)
        showPrivacyStats = v(.showPrivacyStats, showPrivacyStats)
        loadFavicons = v(.loadFavicons, loadFavicons)
        searchFlavor = v(.searchFlavor, searchFlavor)
        searchRegion = v(.searchRegion, searchRegion)
        safeSearch = v(.safeSearch, safeSearch)
        searchSuggestions = v(.searchSuggestions, searchSuggestions)
        blockTrackers = v(.blockTrackers, blockTrackers)
        blockAds = v(.blockAds, blockAds)
        blockCookieBanners = v(.blockCookieBanners, blockCookieBanners)
        httpsOnly = v(.httpsOnly, httpsOnly)
        stripTrackingParams = v(.stripTrackingParams, stripTrackingParams)
        globalPrivacyControl = v(.globalPrivacyControl, globalPrivacyControl)
        blockPopups = v(.blockPopups, blockPopups)
        javaScriptEnabled = v(.javaScriptEnabled, javaScriptEnabled)
        saveHistory = v(.saveHistory, saveHistory)
        clearDataOnLaunch = v(.clearDataOnLaunch, clearDataOnLaunch)
        privateByDefault = v(.privateByDefault, privateByDefault)
        webInspector = v(.webInspector, webInspector)
        defaultZoom = v(.defaultZoom, defaultZoom)
        desktopByDefault = v(.desktopByDefault, desktopByDefault)
        customUserAgent = v(.customUserAgent, customUserAgent)
        extensionsEnabled = v(.extensionsEnabled, extensionsEnabled)
        interceptExtensionDownloads = v(.interceptExtensionDownloads, interceptExtensionDownloads)
    }
}

final class BrowserSettings: ObservableObject {
    static let shared = BrowserSettings()
    private static let key = "saints.settings.v1"

    @Published var data: SettingsData {
        didSet {
            guard data != oldValue else { return }
            save()
        }
    }

    private init() {
        if let raw = UserDefaults.standard.data(forKey: Self.key),
           let decoded = try? JSONDecoder().decode(SettingsData.self, from: raw) {
            data = decoded
        } else {
            data = SettingsData()
        }
    }

    private func save() {
        if let raw = try? JSONEncoder().encode(data) {
            UserDefaults.standard.set(raw, forKey: Self.key)
        }
    }

    func reset() {
        data = SettingsData()
    }

    var accent: Color { Color(hex: data.accentHex) }

    var accentBinding: Binding<Color> {
        Binding(get: { Color(hex: self.data.accentHex) },
                set: { self.data.accentHex = $0.hexString })
    }

    var solidWallpaperBinding: Binding<Color> {
        Binding(get: { Color(hex: self.data.wallpaperSolidHex) },
                set: { self.data.wallpaperSolidHex = $0.hexString })
    }

    func haptic(_ style: UIImpactFeedbackGenerator.FeedbackStyle = .light) {
        guard data.haptics else { return }
        UIImpactFeedbackGenerator(style: style).impactOccurred()
    }
}

// MARK: - Color helpers

extension Color {
    init(hex: String) {
        var s = hex.trimmingCharacters(in: .whitespacesAndNewlines)
        if s.hasPrefix("#") { s.removeFirst() }
        var value: UInt64 = 0
        Scanner(string: s).scanHexInt64(&value)
        let r, g, b, a: Double
        if s.count == 8 {
            r = Double((value >> 24) & 0xFF) / 255
            g = Double((value >> 16) & 0xFF) / 255
            b = Double((value >> 8) & 0xFF) / 255
            a = Double(value & 0xFF) / 255
        } else {
            r = Double((value >> 16) & 0xFF) / 255
            g = Double((value >> 8) & 0xFF) / 255
            b = Double(value & 0xFF) / 255
            a = 1
        }
        self.init(.sRGB, red: r, green: g, blue: b, opacity: a)
    }

    var hexString: String {
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        UIColor(self).getRed(&r, green: &g, blue: &b, alpha: &a)
        func c(_ x: CGFloat) -> Int { Int((min(max(x, 0), 1) * 255).rounded()) }
        return String(format: "#%02X%02X%02X", c(r), c(g), c(b))
    }
}
