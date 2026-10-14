import SwiftUI

struct TabSwitcherView: View {
    @Binding var isPresented: Bool
    @State var showingPrivate: Bool
    @State private var search = ""

    @EnvironmentObject var tabs: TabManager
    @EnvironmentObject var settings: BrowserSettings

    private var list: [BrowserTab] {
        let all = tabs.tabs(isPrivate: showingPrivate)
        guard !search.isEmpty else { return all }
        let q = search.lowercased()
        return all.filter { $0.displayTitle.lowercased().contains(q) || ($0.url?.absoluteString.lowercased().contains(q) ?? false) }
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            if list.isEmpty {
                emptyState
            } else if settings.data.tabLayout == .grid {
                grid
            } else {
                listView
            }
            bottomBar
        }
        .background(
            (showingPrivate ? Color(hex: "#1E1530") : (settings.data.theme == .black ? Color.black : Color(uiColor: .systemGroupedBackground)))
                .ignoresSafeArea()
        )
        .if(showingPrivate) { $0.environment(\.colorScheme, .dark) }
    }

    private var header: some View {
        VStack(spacing: 10) {
            Picker("", selection: $showingPrivate) {
                Text("Tabs (\(tabs.normalTabs.count))").tag(false)
                Text("Private (\(tabs.privateTabs.count))").tag(true)
            }
            .pickerStyle(.segmented)
            HStack {
                Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
                TextField("Search tabs", text: $search)
            }
            .padding(9)
            .background(Color(uiColor: .tertiarySystemFill), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        }
        .padding(.horizontal, 16)
        .padding(.top, 10)
        .padding(.bottom, 6)
    }

    private var grid: some View {
        let columns = Array(repeating: GridItem(.flexible(), spacing: 14), count: max(1, min(settings.data.tabGridColumns, 4)))
        return ScrollViewReader { proxy in
            ScrollView {
                LazyVGrid(columns: columns, spacing: 16) {
                    ForEach(list) { tab in
                        TabCard(tab: tab, selected: tab === tabs.selectedTab) {
                            choose(tab)
                        } onClose: {
                            withAnimation(.spring(response: 0.3)) { tabs.close(tab) }
                        }
                        .id(tab.id)
                    }
                }
                .padding(16)
            }
            .onAppear { if let id = tabs.selectedTab?.id { proxy.scrollTo(id, anchor: .center) } }
        }
    }

    private var listView: some View {
        List {
            ForEach(list) { tab in
                HStack(spacing: 12) {
                    // Borderless buttons so a List row can hold two independent tap targets.
                    Button { choose(tab) } label: {
                        HStack(spacing: 12) {
                            if let url = tab.url {
                                FaviconView(urlString: url.absoluteString, size: 34)
                            } else {
                                Image(systemName: "house").frame(width: 34, height: 34)
                            }
                            VStack(alignment: .leading, spacing: 2) {
                                Text(tab.displayTitle).lineLimit(1).foregroundStyle(.primary)
                                Text(tab.url?.host ?? "Home").font(.caption).foregroundStyle(.secondary)
                            }
                            Spacer()
                            if tab === tabs.selectedTab {
                                Image(systemName: "checkmark").foregroundStyle(settings.accent)
                            }
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.borderless)
                    Button {
                        settings.haptic()
                        withAnimation { tabs.close(tab) }
                    } label: {
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
                    Button(role: .destructive) { tabs.close(tab) } label: { Label("Close", systemImage: "xmark") }
                }
            }
        }
        .listStyle(.insetGrouped)
        .scrollContentBackground(.hidden)
    }

    private var emptyState: some View {
        VStack(spacing: 12) {
            Spacer()
            Image(systemName: showingPrivate ? "eyeglasses" : "square.on.square").font(.system(size: 44)).foregroundStyle(.secondary)
            Text(showingPrivate ? "No private tabs" : "No tabs").font(.headline)
            Text(showingPrivate ? "Private tabs keep no history, cookies or cache after you close them." : "Tap + to open a new tab.")
                .font(.subheadline).foregroundStyle(.secondary).multilineTextAlignment(.center)
            Spacer()
        }
        .padding()
        .frame(maxWidth: .infinity)
    }

    private var bottomBar: some View {
        HStack {
            Menu {
                Button(role: .destructive) {
                    tabs.closeAll(isPrivate: showingPrivate)
                    isPresented = false
                } label: { Label("Close All \(showingPrivate ? "Private " : "")Tabs", systemImage: "xmark.square") }
            } label: {
                Text("Close All").frame(minWidth: 80, alignment: .leading)
            }
            .disabled(list.isEmpty)
            Spacer()
            Button {
                settings.haptic()
                tabs.newTab(isPrivate: showingPrivate)
                isPresented = false
            } label: {
                Image(systemName: "plus").font(.title2.weight(.medium)).frame(width: 52, height: 40)
            }
            Spacer()
            Button("Done") {
                if let selected = tabs.selectedTab, selected.isPrivate != showingPrivate,
                   let first = tabs.tabs(isPrivate: showingPrivate).last {
                    tabs.select(first)
                }
                isPresented = false
            }
            .font(.body.weight(.semibold))
            .frame(minWidth: 80, alignment: .trailing)
        }
        .padding(.horizontal, 20)
        .frame(height: 50)
        .background(.bar)
    }

    private func choose(_ tab: BrowserTab) {
        settings.haptic()
        tabs.select(tab)
        isPresented = false
    }
}

private struct TabCard: View {
    @ObservedObject var tab: BrowserTab
    let selected: Bool
    var onTap: () -> Void
    var onClose: () -> Void
    @EnvironmentObject var settings: BrowserSettings
    @State private var dragX: CGFloat = 0

    var body: some View {
        // The close button is a sibling of the card button (not nested in it), so taps on ✕ always close.
        Button(action: onTap) { card }
            .buttonStyle(CardPressStyle())
            .overlay(alignment: .topTrailing) {
                Button {
                    settings.haptic()
                    onClose()
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(.primary)
                        .frame(width: 24, height: 24)
                        .background(.regularMaterial, in: Circle())
                        .frame(width: 44, height: 44)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Close tab")
            }
            .offset(x: dragX)
            .opacity(1 - Double(min(abs(dragX), 250) / 300))
            .simultaneousGesture(
                DragGesture(minimumDistance: 30)
                    .onChanged { v in
                        if abs(v.translation.width) > abs(v.translation.height) * 1.5 { dragX = v.translation.width }
                    }
                    .onEnded { v in
                        if abs(dragX) > 110 {
                            withAnimation(.easeOut(duration: 0.18)) { dragX = v.translation.width > 0 ? 500 : -500 }
                            DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) { onClose() }
                        } else {
                            withAnimation(.spring()) { dragX = 0 }
                        }
                    }
            )
            .onAppear { if !tab.showsHome && tab.snapshot == nil { tab.captureSnapshot() } }
    }

    private var card: some View {
        VStack(spacing: 0) {
            HStack(spacing: 6) {
                if let url = tab.url {
                    FaviconView(urlString: url.absoluteString, size: 16)
                } else {
                    Image(systemName: tab.isPrivate ? "eyeglasses" : "house.fill").font(.caption2).foregroundStyle(.secondary)
                }
                Text(tab.displayTitle).font(.caption.weight(.semibold)).lineLimit(1)
                Spacer(minLength: 34)   // room for the close button
            }
            .padding(.leading, 10)
            .frame(height: 36)

            ZStack {
                if tab.showsHome {
                    WallpaperView(isPrivate: tab.isPrivate)
                    SaintsLogo(size: 20).foregroundStyle(settings.data.wallpaper == .none && !tab.isPrivate ? Color.primary : Color.white)
                } else if let image = tab.snapshot {
                    Image(uiImage: image).resizable().scaledToFill()
                } else {
                    Color(uiColor: .secondarySystemBackground)
                    Image(systemName: "globe").font(.largeTitle).foregroundStyle(.secondary)
                }
            }
            .frame(height: 190)
            .frame(maxWidth: .infinity)
            .clipped()
            .allowsHitTesting(false)
        }
        .background(Color(uiColor: .secondarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .strokeBorder(selected ? settings.accent : Color.clear, lineWidth: 3)
        )
        .shadow(color: .black.opacity(0.12), radius: 8, y: 3)
        .contentShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
    }
}

private struct CardPressStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.97 : 1)
            .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
    }
}
