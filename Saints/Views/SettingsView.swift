import SwiftUI
import PhotosUI
import WebKit

struct SettingsView: View {
    @EnvironmentObject var settings: BrowserSettings
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                Section {
                    HStack(spacing: 14) {
                        Text("SV Browser").font(.title3.weight(.bold))
                        Spacer()
                        VStack(alignment: .trailing, spacing: 2) {
                            Text("No tracking. No telemetry.").font(.caption.weight(.semibold))
                            Text("Search by DuckDuckGo").font(.caption).foregroundStyle(.secondary)
                        }
                    }
                    .padding(.vertical, 6)
                }
                Section("Customize") {
                    link("Customize", "paintbrush.fill", .pink) { CustomizeView() }
                    link("Wallpaper", "photo.on.rectangle", .orange) { WallpaperStudioView() }
                    link("Address Bar & Toolbar", "rectangle.bottomhalf.inset.filled", .blue) { ToolbarSettings() }
                    link("Tabs", "square.on.square", .indigo) { TabSettings() }
                    link("Start Page", "house.fill", .red) { HomeSettings() }
                }
                Section("Browsing") {
                    link("Search", "magnifyingglass", .green) { SearchSettings() }
                    link("uBlock Origin", "shield.fill", Color(hex: "#800000")) { UBlockView() }
                    link("Privacy & Security", "hand.raised.fill", .purple) { PrivacySettings() }
                    link("Website Content", "doc.richtext", .teal) { ContentSettings() }
                    link("Extensions", "puzzlepiece.extension.fill", .cyan) { ExtensionsSettingsLink() }
                }
                Section {
                    link("About SV Browser", "info.circle.fill", .gray) { AboutView() }
                }
            }
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
        }
    }

    private func link<D: View>(_ title: String, _ symbol: String, _ color: Color, @ViewBuilder destination: @escaping () -> D) -> some View {
        NavigationLink {
            destination()
        } label: {
            Label {
                Text(title)
            } icon: {
                Image(systemName: symbol)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(width: 28, height: 28)
                    .background(color, in: RoundedRectangle(cornerRadius: 7, style: .continuous))
            }
        }
    }
}

// MARK: - Appearance

struct AppearanceSettings: View {
    @EnvironmentObject var settings: BrowserSettings
    private let presets = ["#0A84FF", "#30D158", "#7F53AC", "#FF9F0A", "#FF375F", "#BF5AF2", "#64D2FF", "#FFD60A", "#AC8E68", "#8E8E93"]

    var body: some View {
        Form {
            Section("Theme") {
                Picker("Appearance", selection: $settings.data.theme) {
                    ForEach(ThemeMode.allCases) { Text($0.title).tag($0) }
                }
                Picker("Font", selection: $settings.data.fontDesign) {
                    ForEach(AppFontDesign.allCases) { Text($0.title).font(.system(.body, design: $0.design)).tag($0) }
                }
            }
            Section("Accent Color") {
                LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 5), spacing: 12) {
                    ForEach(presets, id: \.self) { hex in
                        Circle()
                            .fill(Color(hex: hex))
                            .frame(width: 36, height: 36)
                            .overlay(Circle().strokeBorder(.primary, lineWidth: settings.data.accentHex == hex ? 3 : 0))
                            .onTapGesture { settings.data.accentHex = hex; settings.haptic() }
                    }
                }
                .padding(.vertical, 6)
                ColorPicker("Custom Color", selection: settings.accentBinding, supportsOpacity: false)
            }
            Section("Bars") {
                Picker("Material", selection: $settings.data.barMaterial) {
                    ForEach(BarMaterial.allCases) { Text($0.title).tag($0) }
                }
                VStack(alignment: .leading) {
                    Text("Corner Roundness: \(Int(settings.data.barCornerRadius))")
                    Slider(value: $settings.data.barCornerRadius, in: 0...24, step: 1)
                }
                Toggle("Compact Bars", isOn: $settings.data.compactBars)
                Toggle("Show Loading Progress", isOn: $settings.data.showProgressBar)
                Toggle("Show Full Web Address", isOn: $settings.data.showFullURL)
            }
            Section {
                Toggle("Haptic Feedback", isOn: $settings.data.haptics)
            }
            Section {
                PreviewBar()
            } header: { Text("Preview") }
        }
        .navigationTitle("Appearance")
    }
}

private struct PreviewBar: View {
    @EnvironmentObject var settings: BrowserSettings
    var body: some View {
        VStack(spacing: 8) {
            HStack {
                Image(systemName: "lock.fill").font(.caption2).foregroundStyle(.secondary)
                Text("duckduckgo.com")
                Spacer()
                Image(systemName: "arrow.clockwise").font(.footnote).foregroundStyle(.secondary)
            }
            .padding(.horizontal, 12)
            .frame(height: settings.data.compactBars ? 38 : 46)
            .background(FieldBackground(isPrivate: false))
            HStack {
                ForEach(settings.data.toolbarItems) { item in
                    Image(systemName: item.symbol).frame(maxWidth: .infinity)
                }
            }
            .foregroundStyle(settings.accent)
            .frame(height: 30)
        }
        .padding(10)
        .background(BarBackground(isPrivate: false).clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous)))
    }
}

// MARK: - Toolbar

struct ToolbarSettings: View {
    @EnvironmentObject var settings: BrowserSettings

    var body: some View {
        Form {
            Section("Address Bar") {
                Picker("Position", selection: $settings.data.barPosition) {
                    ForEach(BarPosition.allCases) { Text($0.title).tag($0) }
                }
                Toggle("Hide Bars While Scrolling", isOn: $settings.data.hideBarsOnScroll)
                Toggle("Swipe Address Bar to Switch Tabs", isOn: $settings.data.swipeAddressBarToSwitchTabs)
                Toggle("Show Tab Strip", isOn: $settings.data.showTabStrip)
                Toggle("Center Address", isOn: $settings.data.centerAddress)
            }
            Section("Toolbar Style") {
                Picker("Icon Weight", selection: $settings.data.toolbarIconWeight) {
                    ForEach(IconWeight.allCases) { Text($0.title).tag($0) }
                }
                Toggle("Show Button Labels", isOn: $settings.data.toolbarLabels)
            }
            Section {
                ForEach(settings.data.toolbarItems) { item in
                    Label(item.title, systemImage: item.symbol)
                }
                .onMove { settings.data.toolbarItems.move(fromOffsets: $0, toOffset: $1) }
                .onDelete { offsets in
                    if settings.data.toolbarItems.count - offsets.count >= 1 {
                        settings.data.toolbarItems.remove(atOffsets: offsets)
                    }
                }
            } header: {
                Text("Toolbar Buttons (drag to reorder)")
            } footer: {
                Text("Up to 7 buttons. Keep Tabs and Menu so you can always reach everything.")
            }
            let available = ToolbarAction.allCases.filter { !settings.data.toolbarItems.contains($0) }
            if !available.isEmpty && settings.data.toolbarItems.count < 7 {
                Section("Add a Button") {
                    ForEach(available) { item in
                        Button {
                            settings.data.toolbarItems.append(item)
                        } label: {
                            Label(item.title, systemImage: item.symbol)
                        }
                    }
                }
            }
            Section {
                Button("Restore Default Toolbar") {
                    settings.data.toolbarItems = SettingsData().toolbarItems
                }
            }
        }
        .environment(\.editMode, .constant(.active))
        .navigationTitle("Address Bar & Toolbar")
    }
}

// MARK: - Tabs

struct TabSettings: View {
    @EnvironmentObject var settings: BrowserSettings
    var body: some View {
        Form {
            Section("Tab Overview") {
                Picker("Layout", selection: $settings.data.tabLayout) {
                    ForEach(TabLayout.allCases) { Text($0.title).tag($0) }
                }
                .pickerStyle(.segmented)
                if settings.data.tabLayout == .grid {
                    Stepper("Columns: \(settings.data.tabGridColumns)", value: $settings.data.tabGridColumns, in: 1...4)
                }
            }
            Section {
                Toggle("Open Links in Background", isOn: $settings.data.openLinksInBackground)
                Toggle("Restore Tabs on Launch", isOn: $settings.data.restoreTabs)
                Toggle("Start in Private Mode", isOn: $settings.data.privateByDefault)
            }
        }
        .navigationTitle("Tabs")
    }
}

// MARK: - Home

struct HomeSettings: View {
    @EnvironmentObject var settings: BrowserSettings

    var body: some View {
        Form {
            Section {
                HStack {
                    Spacer()
                    HomePreview().frame(height: 230)
                    Spacer()
                }
                .listRowBackground(Color.clear)
                NavigationLink { WallpaperStudioView() } label: {
                    Label("Wallpaper", systemImage: "photo.on.rectangle")
                }
                Picker("Text Color", selection: $settings.data.homeTextStyle) {
                    ForEach(HomeTextStyle.allCases) { Text($0.title).tag($0) }
                }
            }
            Section("Header") {
                Toggle("Show Greeting", isOn: $settings.data.showGreeting)
                if settings.data.showGreeting {
                    TextField("Greeting (empty = time of day)", text: $settings.data.greeting)
                }
            }
            Section("Search Field") {
                VStack(alignment: .leading) {
                    Text("Roundness: \(Int(settings.data.searchFieldRoundness))")
                    Slider(value: $settings.data.searchFieldRoundness, in: 0...26, step: 1)
                }
            }
            Section("Favorites") {
                Toggle("Show Favorites", isOn: $settings.data.showFavorites)
                if settings.data.showFavorites {
                    Stepper("Per Row: \(settings.data.favoritesColumns)", value: $settings.data.favoritesColumns, in: 3...6)
                    Picker("Icon Shape", selection: $settings.data.favoriteShape) {
                        ForEach(TileShape.allCases) { Text($0.title).tag($0) }
                    }
                    .pickerStyle(.segmented)
                }
            }
            Section("Sections") {
                Toggle("Recently Visited", isOn: $settings.data.showRecent)
                Toggle("Privacy Summary", isOn: $settings.data.showPrivacyStats)
                Toggle("Load Site Icons via DuckDuckGo", isOn: $settings.data.loadFavicons)
            }
        }
        .navigationTitle("Start Page")
    }
}

// MARK: - Search

struct SearchSettings: View {
    @EnvironmentObject var settings: BrowserSettings
    var body: some View {
        Form {
            Section {
                Picker("Engine", selection: $settings.data.searchFlavor) {
                    ForEach(SearchFlavor.allCases) { Text($0.title).tag($0) }
                }
                .pickerStyle(.inline)
                .labelsHidden()
            } header: { Text("DuckDuckGo Version") } footer: {
                Text("SV Browser only uses DuckDuckGo. Lite and HTML versions are faster and work without JavaScript.")
            }
            Section("Results") {
                Picker("Region", selection: $settings.data.searchRegion) {
                    ForEach(SearchEngine.regions, id: \.code) { Text($0.name).tag($0.code) }
                }
                Picker("Safe Search", selection: $settings.data.safeSearch) {
                    ForEach(SafeSearch.allCases) { Text($0.title).tag($0) }
                }
            }
            Section {
                Toggle("Search Suggestions", isOn: $settings.data.searchSuggestions)
            } footer: {
                Text("Suggestions are fetched from DuckDuckGo with no cookies. Turn off to send nothing until you press Go.")
            }
        }
        .navigationTitle("Search")
    }
}

// MARK: - Privacy

struct PrivacySettings: View {
    @EnvironmentObject var settings: BrowserSettings
    @State private var confirmClear = false
    @State private var cleared = false

    var body: some View {
        Form {
            Section {
                Toggle("Block Trackers", isOn: $settings.data.blockTrackers)
                Toggle("Block Ads", isOn: $settings.data.blockAds)
                Toggle("Hide Cookie Pop-ups", isOn: $settings.data.blockCookieBanners)
                Toggle("Remove Tracking From Links", isOn: $settings.data.stripTrackingParams)
                Toggle("Global Privacy Control", isOn: $settings.data.globalPrivacyControl)
            } header: { Text("Protection") } footer: {
                Text("Blocking uses WebKit's built-in content blocker, so it's fast and private — nothing is checked against a server. Global Privacy Control changes a browser property that some \"verify you're human\" checks dislike; turn it off if a site won't let you in.")
            }
            Section("Security") {
                Toggle("HTTPS-Only Mode", isOn: $settings.data.httpsOnly)
                Toggle("Block Pop-up Windows", isOn: $settings.data.blockPopups)
                Toggle("Allow JavaScript", isOn: $settings.data.javaScriptEnabled)
            }
            Section("Data") {
                Toggle("Save Browsing History", isOn: $settings.data.saveHistory)
                Toggle("Clear Website Data on Launch", isOn: $settings.data.clearDataOnLaunch)
                Button("Clear Cookies & Website Data", role: .destructive) { confirmClear = true }
                Button("Clear History", role: .destructive) { LibraryStore.shared.clearHistory(); ToastCenter.shared.show("History cleared") }
                Button("Reset Privacy Stats") { PrivacyStats.shared.reset() }
            }
            Section {
                Label("SV Browser contains no analytics, crash reporters, ad SDKs or remote config.", systemImage: "checkmark.shield.fill")
                Label("Safe Browsing lookups are disabled so no URLs are sent to third parties.", systemImage: "checkmark.shield.fill")
                Label("SV Browser looks like Safari to websites to reduce fingerprinting.", systemImage: "checkmark.shield.fill")
            } header: { Text("Telemetry") }
            .font(.footnote)
        }
        .navigationTitle("Privacy & Security")
        .confirmationDialog("Remove all cookies and website data? You'll be signed out of websites.", isPresented: $confirmClear, titleVisibility: .visible) {
            Button("Clear", role: .destructive) {
                TabManager.shared.clearWebsiteData { ToastCenter.shared.show("Website data cleared", symbol: "trash") }
            }
        }
    }
}

// MARK: - Content

struct ContentSettings: View {
    @EnvironmentObject var settings: BrowserSettings
    var body: some View {
        Form {
            Section("Page Zoom") {
                Picker("Default Zoom", selection: $settings.data.defaultZoom) {
                    ForEach([0.75, 0.85, 1.0, 1.15, 1.25, 1.5, 1.75, 2.0], id: \.self) { Text("\(Int($0 * 100))%").tag($0) }
                }
            }
            Section {
                Picker("Identify As", selection: $settings.data.browserIdentity) {
                    ForEach(BrowserIdentity.allCases) { Text($0.title).tag($0) }
                }
                Text(settings.data.customUserAgent.isEmpty
                     ? UserAgent.string(for: settings.data.browserIdentity)
                     : settings.data.customUserAgent)
                    .font(.caption2.monospaced())
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)
            } header: {
                Text("Browser Identity")
            } footer: {
                Text("What websites are told this browser is. Safari matches the engine SV Browser really uses, so sites work best with it. If a site says your browser isn't supported, try Chrome for iPhone for that site.")
            }
            Section {
                Toggle("Request Desktop Sites", isOn: $settings.data.desktopByDefault)
                TextField("Custom User Agent (overrides the above)", text: $settings.data.customUserAgent, axis: .vertical)
                    .font(.footnote.monospaced())
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
            } footer: {
                Text("A custom user agent makes you easier to fingerprint. Leave empty to use the identity above.")
            }
            Section {
                Toggle("Web Inspector", isOn: $settings.data.webInspector)
            } header: { Text("Developer") } footer: {
                Text("Lets Safari on a Mac inspect pages and extensions in SV Browser.")
            }
        }
        .navigationTitle("Website Content")
    }
}

struct ExtensionsSettingsLink: View {
    @EnvironmentObject var settings: BrowserSettings
    @State private var showManager = false
    var body: some View {
        Form {
            Section {
                Toggle("Enable Extensions", isOn: $settings.data.extensionsEnabled)
                Toggle("Offer to Install Extension Links", isOn: $settings.data.interceptExtensionDownloads)
            } footer: {
                Text("When you open a .xpi, .crx, .user.js or .user.css link, or visit an add-on store page, SV Browser offers to install it.")
            }
            Section {
                Button("Manage Extensions") { showManager = true }
            }
        }
        .navigationTitle("Extensions")
        .sheet(isPresented: $showManager) { ExtensionsView() }
    }
}

// MARK: - About

struct AboutView: View {
    @EnvironmentObject var settings: BrowserSettings
    @State private var confirmReset = false

    private var version: String {
        let v = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "1.0"
        let b = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "1"
        return "\(v) (\(b))"
    }

    var body: some View {
        List {
            Section {
                VStack(spacing: 10) {
                    Text("SV Browser").font(.title2.weight(.bold))
                    Text("Version \(version)").font(.footnote).foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 12)
            }
            Section("Our Promise") {
                Text("SV Browser doesn't collect anything. There are no accounts, no analytics, no crash reports, no ad identifiers and no servers of our own. Your bookmarks, history, extensions and settings live only on this device.")
                    .font(.subheadline)
            }
            Section("Built With") {
                LabeledContent("Engine", value: "WebKit")
                LabeledContent("Search", value: "DuckDuckGo")
                LabeledContent("Extensions", value: "WebExtensions + Userscripts")
            }
            Section {
                Button("Reset All Settings", role: .destructive) { confirmReset = true }
            }
        }
        .navigationTitle("About")
        .confirmationDialog("Reset all SV Browser settings to defaults?", isPresented: $confirmReset, titleVisibility: .visible) {
            Button("Reset", role: .destructive) { settings.reset() }
        }
    }
}
