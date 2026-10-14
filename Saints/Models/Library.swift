import Foundation
import WebKit
import SwiftUI

struct Bookmark: Codable, Identifiable, Hashable {
    var id = UUID()
    var title: String
    var url: String
    var isFavorite: Bool = true
    var created = Date()
}

struct LocalSuggestion: Hashable {
    let title: String
    let url: String
}

struct HistoryEntry: Codable, Identifiable, Hashable {
    var id = UUID()
    var title: String
    var url: String
    var date = Date()
}

/// Bookmarks and history, stored only on this device as JSON.
final class LibraryStore: ObservableObject {
    static let shared = LibraryStore()

    @Published private(set) var bookmarks: [Bookmark] = []
    @Published private(set) var history: [HistoryEntry] = []

    private let bookmarksURL: URL
    private let historyURL: URL
    private let maxHistory = 5000

    private init() {
        let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Saints", isDirectory: true)
        try? FileManager.default.createDirectory(at: support, withIntermediateDirectories: true)
        bookmarksURL = support.appendingPathComponent("bookmarks.json")
        historyURL = support.appendingPathComponent("history.json")

        if let data = try? Data(contentsOf: bookmarksURL), let list = try? JSONDecoder().decode([Bookmark].self, from: data) {
            bookmarks = list
        } else {
            bookmarks = [
                Bookmark(title: "DuckDuckGo", url: "https://duckduckgo.com/"),
                Bookmark(title: "Wikipedia", url: "https://www.wikipedia.org/"),
                Bookmark(title: "Firefox Add-ons", url: "https://addons.mozilla.org/firefox/extensions/"),
                Bookmark(title: "Greasy Fork", url: "https://greasyfork.org/"),
                Bookmark(title: "GitHub", url: "https://github.com/"),
                Bookmark(title: "Hacker News", url: "https://news.ycombinator.com/"),
                Bookmark(title: "OpenStreetMap", url: "https://www.openstreetmap.org/"),
                Bookmark(title: "Internet Archive", url: "https://archive.org/")
            ]
            saveBookmarks()
        }
        if let data = try? Data(contentsOf: historyURL), let list = try? JSONDecoder().decode([HistoryEntry].self, from: data) {
            history = list
        }
    }

    var favorites: [Bookmark] { bookmarks.filter(\.isFavorite) }

    func isBookmarked(_ url: URL?) -> Bool {
        guard let s = url?.absoluteString else { return false }
        return bookmarks.contains { $0.url == s }
    }

    func toggleBookmark(title: String, url: URL) {
        let s = url.absoluteString
        if let i = bookmarks.firstIndex(where: { $0.url == s }) {
            bookmarks.remove(at: i)
        } else {
            bookmarks.append(Bookmark(title: title.isEmpty ? (url.host ?? s) : title, url: s))
        }
        saveBookmarks()
    }

    func update(_ bookmark: Bookmark) {
        guard let i = bookmarks.firstIndex(where: { $0.id == bookmark.id }) else { return }
        bookmarks[i] = bookmark
        saveBookmarks()
    }

    func removeBookmarks(at offsets: IndexSet) {
        bookmarks.remove(atOffsets: offsets)
        saveBookmarks()
    }

    func moveBookmarks(from: IndexSet, to: Int) {
        bookmarks.move(fromOffsets: from, toOffset: to)
        saveBookmarks()
    }

    func remove(_ bookmark: Bookmark) {
        bookmarks.removeAll { $0.id == bookmark.id }
        saveBookmarks()
    }

    func recordVisit(title: String, url: URL) {
        guard BrowserSettings.shared.data.saveHistory, let scheme = url.scheme, scheme.hasPrefix("http") else { return }
        let s = url.absoluteString
        if let first = history.first, first.url == s {
            history[0].title = title.isEmpty ? first.title : title
            history[0].date = Date()
        } else {
            history.insert(HistoryEntry(title: title, url: s), at: 0)
            if history.count > maxHistory { history.removeLast(history.count - maxHistory) }
        }
        saveHistorySoon()
    }

    func removeHistory(_ entry: HistoryEntry) {
        history.removeAll { $0.id == entry.id }
        saveHistorySoon()
    }

    func clearHistory() {
        history = []
        try? FileManager.default.removeItem(at: historyURL)
    }

    func suggestions(for query: String, limit: Int = 4) -> [LocalSuggestion] {
        let q = query.lowercased()
        guard !q.isEmpty else { return [] }
        var seen = Set<String>()
        var out: [LocalSuggestion] = []
        for b in bookmarks where b.title.lowercased().contains(q) || b.url.lowercased().contains(q) {
            if seen.insert(b.url).inserted { out.append(LocalSuggestion(title: b.title, url: b.url)) }
        }
        for h in history where h.title.lowercased().contains(q) || h.url.lowercased().contains(q) {
            if out.count >= limit { break }
            if seen.insert(h.url).inserted { out.append(LocalSuggestion(title: h.title, url: h.url)) }
        }
        return Array(out.prefix(limit))
    }

    private func saveBookmarks() {
        if let data = try? JSONEncoder().encode(bookmarks) { try? data.write(to: bookmarksURL, options: .atomic) }
    }

    private var historyWorkItem: DispatchWorkItem?
    private func saveHistorySoon() {
        historyWorkItem?.cancel()
        let snapshot = history
        let url = historyURL
        let item = DispatchWorkItem {
            if let data = try? JSONEncoder().encode(snapshot) { try? data.write(to: url, options: .atomic) }
        }
        historyWorkItem = item
        DispatchQueue.global(qos: .utility).asyncAfter(deadline: .now() + 1, execute: item)
    }
}

// MARK: - Toasts

final class ToastCenter: ObservableObject {
    static let shared = ToastCenter()
    struct Toast: Identifiable, Equatable { let id = UUID(); let text: String; let symbol: String }
    @Published var current: Toast?

    func show(_ text: String, symbol: String = "checkmark.circle") {
        let toast = Toast(text: text, symbol: symbol)
        withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) { current = toast }
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.6) { [weak self] in
            if self?.current == toast {
                withAnimation(.easeOut(duration: 0.25)) { self?.current = nil }
            }
        }
    }
}

// MARK: - Downloads

final class DownloadManager: NSObject, ObservableObject, WKDownloadDelegate {
    static let shared = DownloadManager()

    @Published private(set) var files: [URL] = []
    private var destinations: [ObjectIdentifier: URL] = [:]

    var directory: URL {
        let dir = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Downloads", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    override init() {
        super.init()
        refresh()
    }

    func refresh() {
        let list = (try? FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: [.creationDateKey])) ?? []
        files = list.sorted { a, b in
            let da = (try? a.resourceValues(forKeys: [.creationDateKey]).creationDate) ?? .distantPast
            let db = (try? b.resourceValues(forKeys: [.creationDateKey]).creationDate) ?? .distantPast
            return da > db
        }
    }

    func delete(_ url: URL) {
        try? FileManager.default.removeItem(at: url)
        refresh()
    }

    func download(_ download: WKDownload, decideDestinationUsing response: URLResponse, suggestedFilename: String,
                  completionHandler: @escaping (URL?) -> Void) {
        var target = directory.appendingPathComponent(suggestedFilename.isEmpty ? "download" : suggestedFilename)
        let base = target.deletingPathExtension().lastPathComponent
        let ext = target.pathExtension
        var n = 1
        while FileManager.default.fileExists(atPath: target.path) {
            target = directory.appendingPathComponent(ext.isEmpty ? "\(base) (\(n))" : "\(base) (\(n)).\(ext)")
            n += 1
        }
        destinations[ObjectIdentifier(download)] = target
        ToastCenter.shared.show("Downloading \(target.lastPathComponent)…", symbol: "arrow.down.circle")
        completionHandler(target)
    }

    func downloadDidFinish(_ download: WKDownload) {
        let target = destinations.removeValue(forKey: ObjectIdentifier(download))
        refresh()
        guard let target else { return }
        let lower = target.lastPathComponent.lowercased()
        if lower.hasSuffix(".xpi") || lower.hasSuffix(".crx") || lower.hasSuffix(".user.js") || lower.hasSuffix(".user.css") {
            TabManager.shared.pendingExtensionFile = target
        } else {
            ToastCenter.shared.show("Saved \(target.lastPathComponent) to Downloads", symbol: "arrow.down.circle.fill")
        }
    }

    func download(_ download: WKDownload, didFailWithError error: Error, resumeData: Data?) {
        destinations.removeValue(forKey: ObjectIdentifier(download))
        ToastCenter.shared.show("Download failed: \(error.localizedDescription)", symbol: "exclamationmark.triangle")
    }
}
