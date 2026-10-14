import SwiftUI
import QuickLook

struct LibraryView: View {
    @ObservedObject var tab: BrowserTab
    @EnvironmentObject var library: LibraryStore
    @Environment(\.dismiss) private var dismiss
    @State private var section = 0
    @State private var search = ""
    @State private var editing: Bookmark?
    @State private var confirmClear = false

    var body: some View {
        NavigationStack {
            List {
                Picker("", selection: $section) {
                    Text("Bookmarks").tag(0)
                    Text("History").tag(1)
                }
                .pickerStyle(.segmented)
                .listRowBackground(Color.clear)
                .listRowInsets(EdgeInsets())

                if section == 0 { bookmarks } else { history }
            }
            .searchable(text: $search, placement: .navigationBarDrawer(displayMode: .always))
            .navigationTitle(section == 0 ? "Bookmarks" : "History")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } }
                ToolbarItem(placement: .navigationBarLeading) {
                    if section == 0 {
                        EditButton()
                    } else {
                        Button("Clear", role: .destructive) { confirmClear = true }.disabled(library.history.isEmpty)
                    }
                }
            }
            .confirmationDialog("Clear all history?", isPresented: $confirmClear, titleVisibility: .visible) {
                Button("Clear History", role: .destructive) { library.clearHistory() }
            }
            .sheet(item: $editing) { BookmarkEditor(bookmark: $0) }
        }
    }

    private func matches(_ title: String, _ url: String) -> Bool {
        search.isEmpty || title.localizedCaseInsensitiveContains(search) || url.localizedCaseInsensitiveContains(search)
    }

    @ViewBuilder private var bookmarks: some View {
        if library.bookmarks.isEmpty {
            Text("No bookmarks yet. Tap ☆ in the menu to save a page.").foregroundStyle(.secondary)
        }
        ForEach(library.bookmarks.filter { matches($0.title, $0.url) }) { b in
            Button { openURL(b.url) } label: {
                HStack(spacing: 12) {
                    FaviconView(urlString: b.url, size: 32)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(b.title).foregroundStyle(.primary).lineLimit(1)
                        Text(b.url).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                    }
                    Spacer()
                    if b.isFavorite { Image(systemName: "star.fill").font(.caption).foregroundStyle(.yellow) }
                }
            }
            .swipeActions(edge: .trailing) {
                Button(role: .destructive) { library.remove(b) } label: { Label("Delete", systemImage: "trash") }
                Button { editing = b } label: { Label("Edit", systemImage: "pencil") }.tint(.orange)
            }
            .contextMenu {
                Button { TabManager.shared.newTab(url: URL(string: b.url), isPrivate: false); dismiss() } label: {
                    Label("Open in New Tab", systemImage: "plus.square.on.square")
                }
                Button { TabManager.shared.newTab(url: URL(string: b.url), isPrivate: true); dismiss() } label: {
                    Label("Open in Private Tab", systemImage: "eyeglasses")
                }
                Button { editing = b } label: { Label("Edit", systemImage: "pencil") }
            }
        }
        .onMove(perform: search.isEmpty ? moveBookmarks : nil)
    }

    @ViewBuilder private var history: some View {
        let grouped = Dictionary(grouping: library.history.filter { matches($0.title, $0.url) }) {
            Calendar.current.startOfDay(for: $0.date)
        }
        if grouped.isEmpty {
            Text(BrowserSettings.shared.data.saveHistory ? "No history." : "History is turned off in Settings → Privacy.")
                .foregroundStyle(.secondary)
        }
        ForEach(grouped.keys.sorted(by: >), id: \.self) { day in
            Section(day.formatted(date: .complete, time: .omitted)) {
                ForEach(grouped[day] ?? []) { h in
                    Button { openURL(h.url) } label: {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(h.title.isEmpty ? h.url : h.title).foregroundStyle(.primary).lineLimit(1)
                            HStack {
                                Text(URL(string: h.url)?.host ?? h.url)
                                Spacer()
                                Text(h.date.formatted(date: .omitted, time: .shortened))
                            }
                            .font(.caption).foregroundStyle(.secondary)
                        }
                    }
                    .swipeActions {
                        Button(role: .destructive) { library.removeHistory(h) } label: { Label("Delete", systemImage: "trash") }
                    }
                }
            }
        }
    }

    private func moveBookmarks(from: IndexSet, to: Int) {
        library.moveBookmarks(from: from, to: to)
    }

    private func openURL(_ s: String) {
        guard let url = URL(string: s) else { return }
        tab.load(url)
        dismiss()
    }
}

struct DownloadsView: View {
    @ObservedObject private var downloads = DownloadManager.shared
    @Environment(\.dismiss) private var dismiss
    @State private var preview: URL?

    var body: some View {
        NavigationStack {
            List {
                if downloads.files.isEmpty {
                    Text("Downloaded files appear here and in the Files app under On My iPhone › Saints.")
                        .foregroundStyle(.secondary)
                }
                ForEach(downloads.files, id: \.self) { file in
                    Button { preview = file } label: {
                        HStack(spacing: 12) {
                            Image(systemName: "doc").font(.title2).foregroundStyle(.secondary)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(file.lastPathComponent).foregroundStyle(.primary).lineLimit(2)
                                Text(sizeString(file)).font(.caption).foregroundStyle(.secondary)
                            }
                        }
                    }
                    .swipeActions {
                        Button(role: .destructive) { downloads.delete(file) } label: { Label("Delete", systemImage: "trash") }
                        Button { Share.present([file]) } label: { Label("Share", systemImage: "square.and.arrow.up") }.tint(.blue)
                    }
                }
            }
            .navigationTitle("Downloads")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
            .quickLookPreview($preview)
            .onAppear { downloads.refresh() }
        }
    }

    private func sizeString(_ url: URL) -> String {
        let size = (try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0
        return ByteCountFormatter.string(fromByteCount: Int64(size), countStyle: .file)
    }
}
