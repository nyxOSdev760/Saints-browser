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
        case .glass: return "Floating Glass"
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
    case none, halo, sunset, ocean, forest, aurora, mono
    case dusk, peach, lagoon, berry, mint, cosmic, sand, midnight, rose, ember, glacier
    case solid, photo
    var id: String { rawValue }
    var title: String {
        switch self {
        case .none: return "None"
        case .solid: return "Solid Color"
        case .photo: return "Photo"
        default: return rawValue.capitalized
        }
    }
    static var gradients: [WallpaperStyle] { allCases.filter { $0.gradient != nil } }
    var gradient: [Color]? {
        switch self {
        case .halo: return [Color(hex: "#F6D365"), Color(hex: "#FDA085"), Color(hex: "#7F53AC")]
        case .sunset: return [Color(hex: "#FF5F6D"), Color(hex: "#FFC371")]
        case .ocean: return [Color(hex: "#2193B0"), Color(hex: "#6DD5ED")]
        case .forest: return [Color(hex: "#134E5E"), Color(hex: "#71B280")]
        case .aurora: return [Color(hex: "#00C9FF"), Color(hex: "#92FE9D"), Color(hex: "#7F00FF")]
        case .mono: return [Color(hex: "#232526"), Color(hex: "#414345")]
        case .dusk: return [Color(hex: "#2C3E50"), Color(hex: "#FD746C")]
        case .peach: return [Color(hex: "#FFDDE1"), Color(hex: "#EE9CA7")]
        case .lagoon: return [Color(hex: "#43CEA2"), Color(hex: "#185A9D")]
        case .berry: return [Color(hex: "#8E2DE2"), Color(hex: "#F15F79")]
        case .mint: return [Color(hex: "#D4FC79"), Color(hex: "#96E6A1")]
        case .cosmic: return [Color(hex: "#0F0C29"), Color(hex: "#302B63"), Color(hex: "#24243E")]
        case .sand: return [Color(hex: "#E6DADA"), Color(hex: "#C9B79C")]
        case .midnight: return [Color(hex: "#000000"), Color(hex: "#1C1C3C")]
        case .rose: return [Color(hex: "#F4C4F3"), Color(hex: "#FC67FA")]
        case .ember: return [Color(hex: "#3A1C71"), Color(hex: "#D76D77"), Color(hex: "#FFAF7B")]
        case .glacier: return [Color(hex: "#E0EAFC"), Color(hex: "#CFDEF3"), Color(hex: "#89A4C7")]
        default: return nil
        }
    }
    /// Light gradients look better with dark text.
    var isLight: Bool { [.peach, .mint, .sand, .glacier, .rose].contains(self) }
}

/// What SV Browser tells websites it is (the User-Agent). Safari is what WebKit really is, so it's the safest.
enum BrowserIdentity: String, Codable, CaseIterable, Identifiable {
    case safari, chrome, firefox, edge, desktopSafari, desktopChrome
    var id: String { rawValue }
    var title: String {
        switch self {
        case .safari: return "Safari (recommended)"
        case .chrome: return "Chrome for iPhone"
        case .firefox: return "Firefox for iPhone"
        case .edge: return "Edge for iPhone"
        case .desktopSafari: return "Safari for Mac"
        case .desktopChrome: return "Chrome for Mac"
        }
    }
    var isDesktop: Bool { self == .desktopSafari || self == .desktopChrome }
}

enum DarkWebMode: String, Codable, CaseIterable, Identifiable {
    case off, followApp, always
    var id: String { rawValue }
    var title: String {
        switch self {
        case .off: return "Off"
        case .followApp: return "When SV Browser Is Dark"
        case .always: return "Always"
        }
    }
}

enum HomeTextStyle: String, Codable, CaseIterable, Identifiable {
    case auto, light, dark
    var id: String { rawValue }
    var title: String { rawValue.capitalized }
}

enum TileShape: String, Codable, CaseIterable, Identifiable {
    case rounded, circle, square
    var id: String { rawValue }
    var title: String { rawValue.capitalized }
    var cornerFraction: CGFloat {
        switch self {
        case .rounded: return 0.28
        case .circle: return 0.5
        case .square: return 0.1
        }
    }
}

enum IconWeight: String, Codable, CaseIterable, Identifiable {
    case light, regular, medium, semibold, bold
    var id: String { rawValue }
    var title: String { rawValue.capitalized }
    var weight: Font.Weight {
        switch self {
        case .light: return .light
        case .regular: return .regular
        case .medium: return .medium
        case .semibold: return .semibold
        case .bold: return .bold
        }
    }
}

enum TextSizeOption: String, Codable, CaseIterable, Identifiable {
    case small, standard, large, xLarge
    var id: String { rawValue }
    var title: String {
        switch self {
        case .small: return "Small"
        case .standard: return "Default"
        case .large: return "Large"
        case .xLarge: return "Extra Large"
        }
    }
    var size: DynamicTypeSize {
        switch self {
        case .small: return .small
        case .standard: return .large
        case .large: return .xLarge
        case .xLarge: return .xxLarge
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
    /// Label shown under toolbar icons.
    var shortTitle: String {
        switch self {
        case .fire: return "Burn"
        case .find: return "Find"
        case .desktop: return "Desktop"
        case .privateTab: return "Private"
        case .extensions: return "Add-ons"
        case .bookmarks: return "Library"
        default: return title
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
    var accentHex: String = "#0A84FF"
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
    var lastDarkTheme: ThemeMode = .dark
    var darkWebPages: DarkWebMode = .off
    var textSize: TextSizeOption = .standard
    var toolbarIconWeight: IconWeight = .regular
    var toolbarLabels: Bool = false
    var centerAddress: Bool = false

    // Toolbar
    var toolbarItems: [ToolbarAction] = [.back, .forward, .share, .tabs, .menu]

    // Tabs
    var tabLayout: TabLayout = .grid
    var tabGridColumns: Int = 2
    var openLinksInBackground: Bool = false
    var restoreTabs: Bool = true

    // Home page
    var wallpaper: WallpaperStyle = .none
    /// Bumped when the home page is redesigned; older saves are migrated off the old default wallpaper.
    var homeVersion: Int = 3
    var wallpaperSolidHex: String = "#1C1C1E"
    var wallpaperDim: Double = 0.15
    var wallpaperStamp: Double = 0
    var wallpaperPhotoID: String = ""
    var wallpaperBlur: Double = 0
    var homeTextStyle: HomeTextStyle = .auto
    var showGreeting: Bool = false
    var showRecent: Bool = true
    var favoriteShape: TileShape = .rounded
    var searchFieldRoundness: Double = 20
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
    var globalPrivacyControl: Bool = false
    /// Bumped when a compatibility default changes.
    var compatVersion: Int = 1
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
    var browserIdentity: BrowserIdentity = .safari

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
        lastDarkTheme = v(.lastDarkTheme, lastDarkTheme)
        darkWebPages = v(.darkWebPages, darkWebPages)
        textSize = v(.textSize, textSize)
        toolbarIconWeight = v(.toolbarIconWeight, toolbarIconWeight)
        toolbarLabels = v(.toolbarLabels, toolbarLabels)
        centerAddress = v(.centerAddress, centerAddress)
        toolbarItems = v(.toolbarItems, toolbarItems)
        tabLayout = v(.tabLayout, tabLayout)
        tabGridColumns = v(.tabGridColumns, tabGridColumns)
        openLinksInBackground = v(.openLinksInBackground, openLinksInBackground)
        restoreTabs = v(.restoreTabs, restoreTabs)
        wallpaper = v(.wallpaper, wallpaper)
        homeVersion = v(.homeVersion, 1)
        if homeVersion < 2 {
            if wallpaper == .halo { wallpaper = .none }
        }
        let migrateToV3 = homeVersion < 3
        homeVersion = 3
        wallpaperSolidHex = v(.wallpaperSolidHex, wallpaperSolidHex)
        wallpaperDim = v(.wallpaperDim, wallpaperDim)
        wallpaperStamp = v(.wallpaperStamp, wallpaperStamp)
        wallpaperPhotoID = v(.wallpaperPhotoID, wallpaperPhotoID)
        wallpaperBlur = v(.wallpaperBlur, wallpaperBlur)
        homeTextStyle = v(.homeTextStyle, homeTextStyle)
        showGreeting = v(.showGreeting, showGreeting)
        showRecent = v(.showRecent, showRecent)
        favoriteShape = v(.favoriteShape, favoriteShape)
        searchFieldRoundness = v(.searchFieldRoundness, searchFieldRoundness)
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
        let compatBefore = v(.compatVersion, 0)
        if compatBefore < 1 { globalPrivacyControl = false }
        compatVersion = 1
        blockPopups = v(.blockPopups, blockPopups)
        javaScriptEnabled = v(.javaScriptEnabled, javaScriptEnabled)
        saveHistory = v(.saveHistory, saveHistory)
        clearDataOnLaunch = v(.clearDataOnLaunch, clearDataOnLaunch)
        privateByDefault = v(.privateByDefault, privateByDefault)
        webInspector = v(.webInspector, webInspector)
        defaultZoom = v(.defaultZoom, defaultZoom)
        desktopByDefault = v(.desktopByDefault, desktopByDefault)
        customUserAgent = v(.customUserAgent, customUserAgent)
        browserIdentity = v(.browserIdentity, browserIdentity)
        extensionsEnabled = v(.extensionsEnabled, extensionsEnabled)
        interceptExtensionDownloads = v(.interceptExtensionDownloads, interceptExtensionDownloads)
        if compatBefore < 1 { centerAddress = false }
        if migrateToV3 {
            // SV Browser rename: plain blue accent, floating glass bars, no greeting by default.
            if accentHex == "#7F53AC" { accentHex = "#0A84FF" }
            showGreeting = false
            barMaterial = .glass
        }
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

    /// Whether Saints is currently showing its dark appearance.
    func isDark(system: ColorScheme) -> Bool {
        switch data.theme {
        case .dark, .black: return true
        case .light: return false
        case .system: return system == .dark
        }
    }

    /// Menu quick toggle: flips between light and the last dark style used (Dark or AMOLED).
    func toggleDarkMode(system: ColorScheme) {
        if isDark(system: system) {
            if data.theme == .dark || data.theme == .black { data.lastDarkTheme = data.theme }
            data.theme = .light
        } else {
            data.theme = data.lastDarkTheme == .black ? .black : .dark
        }
        haptic(.medium)
    }

    func apply(_ preset: ThemePreset) {
        data.theme = preset.theme
        data.accentHex = preset.accent
        data.barMaterial = preset.material
        data.fontDesign = preset.font
        data.barCornerRadius = preset.radius
        data.wallpaper = preset.wallpaper
        if let solid = preset.solidHex { data.wallpaperSolidHex = solid }
        data.wallpaperDim = preset.wallpaper == .none || preset.wallpaper == .solid ? 0 : 0.12
        data.wallpaperBlur = 0
        haptic(.medium)
    }

    func haptic(_ style: UIImpactFeedbackGenerator.FeedbackStyle = .light) {
        guard data.haptics else { return }
        UIImpactFeedbackGenerator(style: style).impactOccurred()
    }
}

// MARK: - Theme presets

struct ThemePreset: Identifiable {
    let name: String
    let theme: ThemeMode
    let accent: String
    let material: BarMaterial
    let font: AppFontDesign
    let radius: Double
    let wallpaper: WallpaperStyle
    var solidHex: String?
    var id: String { name }

    static let all: [ThemePreset] = [
        ThemePreset(name: "Default", theme: .system, accent: "#0A84FF", material: .glass, font: .rounded, radius: 14, wallpaper: .none),
        ThemePreset(name: "Midnight", theme: .black, accent: "#0A84FF", material: .solid, font: .standard, radius: 12, wallpaper: .midnight),
        ThemePreset(name: "Ocean", theme: .dark, accent: "#64D2FF", material: .tinted, font: .rounded, radius: 18, wallpaper: .ocean),
        ThemePreset(name: "Forest", theme: .dark, accent: "#30D158", material: .tinted, font: .rounded, radius: 16, wallpaper: .forest),
        ThemePreset(name: "Sunset", theme: .light, accent: "#FF9F0A", material: .glass, font: .rounded, radius: 20, wallpaper: .sunset),
        ThemePreset(name: "Paper", theme: .light, accent: "#AC8E68", material: .solid, font: .serif, radius: 8, wallpaper: .solid, solidHex: "#F5F0E6"),
        ThemePreset(name: "Terminal", theme: .black, accent: "#30D158", material: .solid, font: .monospaced, radius: 4, wallpaper: .none),
        ThemePreset(name: "Candy", theme: .light, accent: "#FF375F", material: .glass, font: .rounded, radius: 22, wallpaper: .berry),
        ThemePreset(name: "Cosmic", theme: .dark, accent: "#BF5AF2", material: .tinted, font: .rounded, radius: 16, wallpaper: .cosmic),
        ThemePreset(name: "Glacier", theme: .light, accent: "#5E7CE2", material: .glass, font: .standard, radius: 14, wallpaper: .glacier)
    ]
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

    /// Perceived brightness above ~60% → treat as a light color.
    var isLightColor: Bool {
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        UIColor(self).getRed(&r, green: &g, blue: &b, alpha: &a)
        return (0.299 * r + 0.587 * g + 0.114 * b) > 0.6
    }

    var hexString: String {
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        UIColor(self).getRed(&r, green: &g, blue: &b, alpha: &a)
        func c(_ x: CGFloat) -> Int { Int((min(max(x, 0), 1) * 255).rounded()) }
        return String(format: "#%02X%02X%02X", c(r), c(g), c(b))
    }
}
