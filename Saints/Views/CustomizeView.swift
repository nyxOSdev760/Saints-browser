import SwiftUI

/// One place for every look-and-feel option.
struct CustomizeView: View {
    var standalone = false

    @EnvironmentObject var settings: BrowserSettings
    @Environment(\.dismiss) private var dismiss

    private let accents = ["#7F53AC", "#0A84FF", "#30D158", "#FF9F0A", "#FF375F", "#BF5AF2", "#64D2FF", "#FFD60A", "#AC8E68", "#8E8E93"]

    var body: some View {
        Form {
            Section {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 12) {
                        ForEach(ThemePreset.all) { preset in
                            PresetCard(preset: preset) {
                                withAnimation(.easeInOut(duration: 0.25)) { settings.apply(preset) }
                            }
                        }
                    }
                    .padding(.vertical, 6)
                }
                .listRowInsets(EdgeInsets(top: 4, leading: 16, bottom: 4, trailing: 16))
            } header: {
                Text("Themes")
            } footer: {
                Text("A theme sets appearance, accent color, bars, font and wallpaper at once. Tweak anything afterwards.")
            }

            Section("Appearance") {
                Picker("Mode", selection: $settings.data.theme) {
                    Image(systemName: "circle.lefthalf.filled").tag(ThemeMode.system)
                    Image(systemName: "sun.max.fill").tag(ThemeMode.light)
                    Image(systemName: "moon.fill").tag(ThemeMode.dark)
                    Image(systemName: "moon.stars.fill").tag(ThemeMode.black)
                }
                .pickerStyle(.segmented)
                Text(settings.data.theme.title).font(.caption).foregroundStyle(.secondary)

                LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 5), spacing: 12) {
                    ForEach(accents, id: \.self) { hex in
                        Circle()
                            .fill(Color(hex: hex))
                            .frame(width: 34, height: 34)
                            .overlay(Circle().strokeBorder(.primary, lineWidth: settings.data.accentHex == hex ? 3 : 0).padding(-4))
                            .onTapGesture { settings.data.accentHex = hex; settings.haptic() }
                    }
                }
                .padding(.vertical, 6)
                ColorPicker("Custom Accent", selection: settings.accentBinding, supportsOpacity: false)

                Picker("Text Size", selection: $settings.data.textSize) {
                    ForEach(TextSizeOption.allCases) { Text($0.title).tag($0) }
                }
                Picker("Font", selection: $settings.data.fontDesign) {
                    ForEach(AppFontDesign.allCases) { Text($0.title).font(.system(.body, design: $0.design)).tag($0) }
                }
            }

            Section {
                Picker("Dark Web Pages", selection: $settings.data.darkWebPages) {
                    ForEach(DarkWebMode.allCases) { Text($0.title).tag($0) }
                }
            } footer: {
                Text("Darkens bright websites. Sites that already have a dark theme are left alone.")
            }

            Section("More") {
                NavigationLink { WallpaperStudioView() } label: { row("Wallpaper", "photo.on.rectangle", .orange) }
                NavigationLink { HomeSettings() } label: { row("Start Page", "house.fill", .pink) }
                NavigationLink { ToolbarSettings() } label: { row("Address Bar & Toolbar", "rectangle.bottomhalf.inset.filled", .blue) }
                NavigationLink { TabSettings() } label: { row("Tabs", "square.on.square", .indigo) }
                NavigationLink { AppearanceSettings() } label: { row("Bars, Fonts & Details", "slider.horizontal.3", .gray) }
            }
        }
        .navigationTitle("Customize")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            if standalone {
                ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } }
            }
        }
    }

    private func row(_ title: String, _ symbol: String, _ color: Color) -> some View {
        Label {
            Text(title)
        } icon: {
            Image(systemName: symbol)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(.white)
                .frame(width: 28, height: 28)
                .background(color.gradient, in: RoundedRectangle(cornerRadius: 7, style: .continuous))
        }
    }
}

private struct PresetCard: View {
    let preset: ThemePreset
    var onApply: () -> Void
    @EnvironmentObject var settings: BrowserSettings

    private var isCurrent: Bool {
        settings.data.accentHex == preset.accent && settings.data.theme == preset.theme && settings.data.wallpaper == preset.wallpaper
    }

    private var background: some View {
        Group {
            if let colors = preset.wallpaper.gradient {
                LinearGradient(colors: colors, startPoint: .topLeading, endPoint: .bottomTrailing)
            } else if let hex = preset.solidHex {
                Color(hex: hex)
            } else {
                preset.theme == .black ? Color.black
                    : preset.theme == .dark ? Color(hex: "#1C1C1E")
                    : preset.theme == .light ? Color(hex: "#F2F2F7")
                    : Color(uiColor: .secondarySystemBackground)
            }
        }
    }

    var body: some View {
        Button(action: onApply) {
            VStack(spacing: 6) {
                ZStack(alignment: .bottom) {
                    background
                    // Mini address bar + accent dot.
                    HStack(spacing: 4) {
                        Circle().fill(Color(hex: preset.accent)).frame(width: 8, height: 8)
                        RoundedRectangle(cornerRadius: min(6, preset.radius / 2), style: .continuous)
                            .fill(preset.theme == .light ? Color.white.opacity(0.85) : Color.white.opacity(0.2))
                            .frame(height: 10)
                    }
                    .padding(8)
                }
                .frame(width: 84, height: 112)
                .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(Color.primary.opacity(0.1)))
                .overlay(
                    RoundedRectangle(cornerRadius: 17, style: .continuous)
                        .strokeBorder(isCurrent ? Color(hex: preset.accent) : .clear, lineWidth: 3)
                        .padding(-3)
                )
                Text(preset.name)
                    .font(.system(.caption, design: preset.font.design).weight(.semibold))
                    .foregroundStyle(.primary)
            }
        }
        .buttonStyle(.plain)
    }
}
