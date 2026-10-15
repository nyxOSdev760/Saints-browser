import SwiftUI
import PhotosUI

/// Pick, add and tune home page wallpapers.
struct WallpaperStudioView: View {
    var standalone = false

    @EnvironmentObject var settings: BrowserSettings
    @ObservedObject private var store = WallpaperStore.shared
    @Environment(\.dismiss) private var dismiss
    @State private var picked: [PhotosPickerItem] = []
    @State private var importing = false

    private let solids = ["#000000", "#1C1C1E", "#3A3A3C", "#F2F2F7", "#FFFFFF", "#0A2342",
                          "#1B4332", "#3C096C", "#6A040F", "#F4A261", "#E9C46A", "#2A9D8F"]
    private let grid = Array(repeating: GridItem(.flexible(), spacing: 10), count: 4)

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 26) {
                HomePreview()
                    .frame(height: 250)
                    .frame(maxWidth: .infinity)

                section("Your Photos") {
                    LazyVGrid(columns: grid, spacing: 10) {
                        PhotosPicker(selection: $picked, maxSelectionCount: 10, matching: .images) {
                            ZStack {
                                RoundedRectangle(cornerRadius: 12, style: .continuous)
                                    .fill(settings.accent.opacity(0.12))
                                if importing {
                                    ProgressView()
                                } else {
                                    VStack(spacing: 4) {
                                        Image(systemName: "plus").font(.title2.weight(.semibold))
                                        Text("Add").font(.caption.weight(.semibold))
                                    }
                                    .foregroundStyle(settings.accent)
                                }
                            }
                            .aspectRatio(0.62, contentMode: .fit)
                        }
                        ForEach(store.photos) { photo in
                            Button { select(photo: photo.id) } label: {
                                Color.clear
                                    .aspectRatio(0.62, contentMode: .fit)
                                    .overlay {
                                        if let thumb = store.thumbnail(photo.id) {
                                            Image(uiImage: thumb).resizable().scaledToFill()
                                        }
                                    }
                                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                                    .overlay(ring(selected: settings.data.wallpaper == .photo && settings.data.wallpaperPhotoID == photo.id))
                            }
                            .buttonStyle(.plain)
                            .contextMenu {
                                Button(role: .destructive) { store.delete(photo.id) } label: { Label("Delete Photo", systemImage: "trash") }
                            }
                        }
                    }
                }

                section("Gradients") {
                    LazyVGrid(columns: grid, spacing: 10) {
                        swatch(selected: settings.data.wallpaper == .none, label: "Plain") {
                            Color(uiColor: .systemBackground)
                                .overlay(Image(systemName: "circle.slash").foregroundStyle(.secondary))
                        } action: { settings.data.wallpaper = .none }
                        ForEach(WallpaperStyle.gradients) { style in
                            swatch(selected: settings.data.wallpaper == style, label: style.title) {
                                LinearGradient(colors: style.gradient ?? [], startPoint: .topLeading, endPoint: .bottomTrailing)
                            } action: { settings.data.wallpaper = style }
                        }
                    }
                }

                section("Colors") {
                    LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 10), count: 6), spacing: 12) {
                        ForEach(solids, id: \.self) { hex in
                            let selected = settings.data.wallpaper == .solid && settings.data.wallpaperSolidHex == hex
                            Circle()
                                .fill(Color(hex: hex))
                                .overlay(Circle().strokeBorder(Color.primary.opacity(0.15), lineWidth: 1))
                                .overlay(Circle().strokeBorder(selected ? settings.accent : .clear, lineWidth: 3).padding(-4))
                                .frame(height: 40)
                                .onTapGesture {
                                    settings.data.wallpaperSolidHex = hex
                                    settings.data.wallpaper = .solid
                                    settings.haptic()
                                }
                        }
                    }
                    ColorPicker("Custom Color", selection: Binding(
                        get: { Color(hex: settings.data.wallpaperSolidHex) },
                        set: { settings.data.wallpaperSolidHex = $0.hexString; settings.data.wallpaper = .solid }
                    ), supportsOpacity: false)
                    .padding(.top, 6)
                }

                section("Adjust") {
                    VStack(alignment: .leading, spacing: 14) {
                        slider("Dim", value: $settings.data.wallpaperDim, range: 0...0.8, percent: true)
                        slider("Blur", value: $settings.data.wallpaperBlur, range: 0...30, percent: false)
                        VStack(alignment: .leading, spacing: 6) {
                            Text("Text Color").font(.subheadline)
                            Picker("Text Color", selection: $settings.data.homeTextStyle) {
                                ForEach(HomeTextStyle.allCases) { Text($0.title).tag($0) }
                            }
                            .pickerStyle(.segmented)
                        }
                    }
                    .disabled(settings.data.wallpaper == .none)
                    .opacity(settings.data.wallpaper == .none ? 0.45 : 1)
                }
            }
            .padding(18)
        }
        .background(Color(uiColor: .systemGroupedBackground).ignoresSafeArea())
        .navigationTitle("Wallpaper")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            if standalone {
                ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } }
            }
        }
        .onChange(of: picked) { items in
            guard !items.isEmpty else { return }
            importing = true
            Task {
                var lastID: String?
                for item in items {
                    if let data = try? await item.loadTransferable(type: Data.self) {
                        lastID = await MainActor.run { store.add(data) } ?? lastID
                    }
                }
                await MainActor.run {
                    importing = false
                    picked = []
                    if let lastID { select(photo: lastID) }
                }
            }
        }
    }

    private func select(photo id: String) {
        settings.data.wallpaperPhotoID = id
        settings.data.wallpaper = .photo
        settings.data.wallpaperStamp = Date().timeIntervalSince1970
        settings.haptic()
    }

    private func section<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title).font(.headline)
            content()
        }
    }

    private func ring(selected: Bool) -> some View {
        RoundedRectangle(cornerRadius: 14, style: .continuous)
            .strokeBorder(selected ? settings.accent : Color.clear, lineWidth: 3)
            .padding(-3)
    }

    private func swatch<Fill: View>(selected: Bool, label: String, @ViewBuilder fill: () -> Fill,
                                    action: @escaping () -> Void) -> some View {
        Button {
            action()
            settings.haptic()
        } label: {
            VStack(spacing: 5) {
                fill()
                    .aspectRatio(0.62, contentMode: .fit)
                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(Color.primary.opacity(0.08)))
                    .overlay(ring(selected: selected))
                Text(label).font(.caption2).foregroundStyle(.secondary).lineLimit(1)
            }
        }
        .buttonStyle(.plain)
    }

    private func slider(_ title: String, value: Binding<Double>, range: ClosedRange<Double>, percent: Bool) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(title).font(.subheadline)
                Spacer()
                Text(percent ? "\(Int(value.wrappedValue * 100))%" : "\(Int(value.wrappedValue))")
                    .font(.subheadline.monospacedDigit()).foregroundStyle(.secondary)
            }
            Slider(value: value, in: range)
        }
    }
}

/// A miniature of the start page using the current wallpaper and theme.
struct HomePreview: View {
    @EnvironmentObject var settings: BrowserSettings

    private var lightInk: Bool {
        switch settings.data.homeTextStyle {
        case .light: return true
        case .dark: return false
        case .auto:
            let w = settings.data.wallpaper
            if w == .none { return false }
            if w == .solid { return !Color(hex: settings.data.wallpaperSolidHex).isLightColor }
            return !w.isLight
        }
    }

    var body: some View {
        ZStack {
            WallpaperView(preview: true)
            VStack(spacing: 12) {
                HStack {
                    Image(systemName: "magnifyingglass").font(.caption)
                    Text("Search or enter address").font(.caption)
                    Spacer()
                }
                .foregroundStyle(.secondary)
                .padding(.horizontal, 10)
                .frame(height: 30)
                .background(RoundedRectangle(cornerRadius: min(14, settings.data.searchFieldRoundness * 0.6), style: .continuous).fill(.regularMaterial))
                .padding(.horizontal, 22)
                HStack(spacing: 9) {
                    ForEach(0..<4) { _ in
                        RoundedRectangle(cornerRadius: 24 * settings.data.favoriteShape.cornerFraction, style: .continuous)
                            .fill(.regularMaterial)
                            .frame(width: 24, height: 24)
                    }
                }
            }
        }
        .frame(width: 150)
        .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 24, style: .continuous).strokeBorder(Color.primary.opacity(0.15), lineWidth: 4))
        .shadow(color: .black.opacity(0.15), radius: 12, y: 6)
    }
}
