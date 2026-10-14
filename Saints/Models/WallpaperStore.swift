import UIKit
import SwiftUI

/// The user's own wallpaper photos, stored on device as JPEGs.
final class WallpaperStore: ObservableObject {
    static let shared = WallpaperStore()

    struct Photo: Identifiable, Hashable {
        let id: String
        let url: URL
    }

    @Published private(set) var photos: [Photo] = []
    private var cache: [String: UIImage] = [:]
    private var thumbCache: [String: UIImage] = [:]

    let directory: URL

    private init() {
        let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        directory = support.appendingPathComponent("Saints/Wallpapers", isDirectory: true)
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        migrateLegacyPhoto(support: support)
        reload()
    }

    /// Earlier versions kept a single `wallpaper.jpg`; move it into the gallery.
    private func migrateLegacyPhoto(support: URL) {
        let legacy = support.appendingPathComponent("Saints/wallpaper.jpg")
        guard FileManager.default.fileExists(atPath: legacy.path) else { return }
        let id = UUID().uuidString
        try? FileManager.default.moveItem(at: legacy, to: directory.appendingPathComponent("\(id).jpg"))
        let settings = BrowserSettings.shared
        if settings.data.wallpaper == .photo && settings.data.wallpaperPhotoID.isEmpty {
            settings.data.wallpaperPhotoID = id
        }
    }

    func reload() {
        let files = (try? FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: [.creationDateKey])) ?? []
        photos = files.filter { $0.pathExtension.lowercased() == "jpg" }
            .sorted { a, b in
                let da = (try? a.resourceValues(forKeys: [.creationDateKey]).creationDate) ?? .distantPast
                let db = (try? b.resourceValues(forKeys: [.creationDateKey]).creationDate) ?? .distantPast
                return da > db
            }
            .map { Photo(id: $0.deletingPathExtension().lastPathComponent, url: $0) }
    }

    /// Saves a photo (downscaled to at most 2400 px) and returns its id.
    @discardableResult
    func add(_ data: Data) -> String? {
        guard let image = UIImage(data: data) else { return nil }
        let scaled = Self.downscale(image, maxSide: 2400)
        guard let jpeg = scaled.jpegData(compressionQuality: 0.88) else { return nil }
        let id = UUID().uuidString
        do {
            try jpeg.write(to: directory.appendingPathComponent("\(id).jpg"), options: .atomic)
        } catch {
            return nil
        }
        reload()
        return id
    }

    func delete(_ id: String) {
        try? FileManager.default.removeItem(at: directory.appendingPathComponent("\(id).jpg"))
        cache.removeValue(forKey: id)
        thumbCache.removeValue(forKey: id)
        let settings = BrowserSettings.shared
        if settings.data.wallpaperPhotoID == id {
            settings.data.wallpaperPhotoID = ""
            if settings.data.wallpaper == .photo { settings.data.wallpaper = .none }
        }
        reload()
    }

    func image(_ id: String) -> UIImage? {
        guard !id.isEmpty else { return nil }
        if let cached = cache[id] { return cached }
        guard let image = UIImage(contentsOfFile: directory.appendingPathComponent("\(id).jpg").path) else { return nil }
        cache = [id: image]          // keep only the active wallpaper in memory
        return image
    }

    func thumbnail(_ id: String) -> UIImage? {
        if let t = thumbCache[id] { return t }
        guard let image = UIImage(contentsOfFile: directory.appendingPathComponent("\(id).jpg").path) else { return nil }
        let thumb = Self.downscale(image, maxSide: 360)
        thumbCache[id] = thumb
        return thumb
    }

    static func downscale(_ image: UIImage, maxSide: CGFloat) -> UIImage {
        let size = image.size
        let scale = min(1, maxSide / max(size.width, size.height))
        guard scale < 1 else { return image }
        let target = CGSize(width: (size.width * scale).rounded(), height: (size.height * scale).rounded())
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        return UIGraphicsImageRenderer(size: target, format: format).image { _ in
            image.draw(in: CGRect(origin: .zero, size: target))
        }
    }
}
