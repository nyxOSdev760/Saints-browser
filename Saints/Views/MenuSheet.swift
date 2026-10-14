import SwiftUI

/// Firefox-style app menu presented as a half sheet.
struct MenuSheet: View {
    @ObservedObject var tab: BrowserTab
    var open: (BrowserSheet) -> Void
    var perform: (ToolbarAction) -> Void

    @EnvironmentObject var settings: BrowserSettings
    @EnvironmentObject var library: LibraryStore
    @EnvironmentObject var extensions: ExtensionManager
    @EnvironmentObject var tabs: TabManager
    @Environment(\.dismiss) private var dismiss

    private let columns = Array(repeating: GridItem(.flexible(), spacing: 10), count: 4)

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 18) {
                    if let url = tab.url {
                        pageHeader(url)
                    }
                    LazyVGrid(columns: columns, spacing: 10) {
                        tile("New Tab", "plus.square.on.square") { tabs.newTab(isPrivate: false); dismiss() }
                        tile("Private Tab", "eyeglasses") { tabs.newTab(isPrivate: true); dismiss() }
                        tile("Bookmarks", "book") { open(.library) }
                        tile("Downloads", "arrow.down.circle") { open(.downloads) }
                        tile("Extensions", "puzzlepiece.extension") { open(.extensions) }
                        tile("Find", "doc.text.magnifyingglass", disabled: tab.showsHome) { perform(.find) }
                        tile(tab.desktopMode ? "Mobile Site" : "Desktop Site", tab.desktopMode ? "iphone" : "desktopcomputer", disabled: tab.showsHome) {
                            tab.toggleDesktopMode(); dismiss()
                        }
                        tile("Burn", "flame") { perform(.fire) }
                    }
                    .padding(.horizontal, 16)

                    let actionable = extensions.activeExtensions.filter { $0.popupPath != nil || ($0.kind == .webExtension && $0.hasBackground) }
                    if !actionable.isEmpty {
                        VStack(alignment: .leading, spacing: 10) {
                            Text("Extensions").font(.footnote.weight(.semibold)).foregroundStyle(.secondary).padding(.horizontal, 20)
                            ScrollView(.horizontal, showsIndicators: false) {
                                HStack(spacing: 12) {
                                    ForEach(actionable) { ext in
                                        Button {
                                            dismiss()
                                            DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) { ExtensionHost.shared.activate(ext) }
                                        } label: {
                                            VStack(spacing: 6) {
                                                ExtensionIcon(ext: ext, size: 44)
                                                Text(ext.name).font(.caption2).lineLimit(1).frame(width: 70)
                                            }
                                        }
                                        .buttonStyle(.plain)
                                    }
                                }
                                .padding(.horizontal, 20)
                            }
                        }
                    }

                    VStack(spacing: 0) {
                        row("Zoom", "textformat.size") {
                            HStack(spacing: 14) {
                                Button { tab.setZoom(tab.zoom - 0.1) } label: { Image(systemName: "minus") }
                                Text("\(Int((tab.zoom * 100).rounded()))%").monospacedDigit().frame(width: 48)
                                Button { tab.setZoom(tab.zoom + 0.1) } label: { Image(systemName: "plus") }
                            }
                            .buttonStyle(.borderless)
                        }
                        Divider().padding(.leading, 52)
                        row("Theme", "circle.lefthalf.filled") {
                            Picker("", selection: $settings.data.theme) {
                                ForEach(ThemeMode.allCases) { Text($0.title).tag($0) }
                            }
                            .labelsHidden()
                        }
                        Divider().padding(.leading, 52)
                        row("Address Bar", "rectangle.bottomhalf.inset.filled") {
                            Picker("", selection: $settings.data.barPosition) {
                                Text("Bottom").tag(BarPosition.bottom)
                                Text("Top").tag(BarPosition.top)
                            }
                            .pickerStyle(.segmented)
                            .frame(width: 150)
                        }
                        Divider().padding(.leading, 52)
                        Button { open(.settings) } label: {
                            row("Settings", "gearshape") { Image(systemName: "chevron.right").foregroundStyle(.tertiary) }
                        }
                        .buttonStyle(.plain)
                    }
                    .background(Color(uiColor: .secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                    .padding(.horizontal, 16)
                }
                .padding(.vertical, 12)
            }
            .background(Color(uiColor: .systemGroupedBackground))
            .navigationTitle("Saints")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } }
            }
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
    }

    private func pageHeader(_ url: URL) -> some View {
        HStack(spacing: 12) {
            FaviconView(urlString: url.absoluteString, size: 40)
            VStack(alignment: .leading, spacing: 2) {
                Text(tab.displayTitle).font(.subheadline.weight(.semibold)).lineLimit(1)
                Text(url.host ?? url.absoluteString).font(.caption).foregroundStyle(.secondary).lineLimit(1)
            }
            Spacer()
            Button {
                library.toggleBookmark(title: tab.title, url: url)
                settings.haptic(.medium)
            } label: {
                Image(systemName: library.isBookmarked(url) ? "star.fill" : "star")
                    .font(.title3)
                    .foregroundStyle(library.isBookmarked(url) ? Color.yellow : Color.secondary)
            }
            Button { Share.present([URLCleaner.clean(url) ?? url]) } label: {
                Image(systemName: "square.and.arrow.up").font(.title3)
            }
        }
        .padding(14)
        .background(Color(uiColor: .secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .padding(.horizontal, 16)
    }

    private func tile(_ title: String, _ symbol: String, disabled: Bool = false, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(spacing: 7) {
                Image(systemName: symbol).font(.system(size: 20))
                Text(title).font(.caption2).lineLimit(1).minimumScaleFactor(0.8)
            }
            .frame(maxWidth: .infinity)
            .frame(height: 70)
            .background(Color(uiColor: .secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        }
        .buttonStyle(.plain)
        .disabled(disabled)
        .opacity(disabled ? 0.4 : 1)
    }

    private func row<Trailing: View>(_ title: String, _ symbol: String, @ViewBuilder trailing: () -> Trailing) -> some View {
        HStack(spacing: 14) {
            Image(systemName: symbol).frame(width: 24).foregroundStyle(settings.accent)
            Text(title)
            Spacer()
            trailing()
        }
        .padding(.horizontal, 14)
        .frame(minHeight: 50)
        .contentShape(Rectangle())
    }
}

struct ExtensionIcon: View {
    let ext: WebExtension
    var size: CGFloat = 40
    @EnvironmentObject var settings: BrowserSettings

    var body: some View {
        Group {
            if let image = ExtensionManager.shared.icon(for: ext) {
                Image(uiImage: image).resizable().interpolation(.high).scaledToFit().padding(size * 0.12)
            } else {
                Image(systemName: ext.kind == .webExtension ? "puzzlepiece.extension.fill" : (ext.kind == .userScript ? "curlybraces" : "paintbrush.fill"))
                    .font(.system(size: size * 0.42))
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(settings.accent.gradient)
            }
        }
        .frame(width: size, height: size)
        .background(Color(uiColor: .tertiarySystemFill))
        .clipShape(RoundedRectangle(cornerRadius: size * 0.24, style: .continuous))
    }
}
