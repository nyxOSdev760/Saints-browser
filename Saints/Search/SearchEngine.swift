import Foundation

/// DuckDuckGo-only search. No partner/attribution parameters are ever sent.
enum SearchEngine {
    static func searchURL(for query: String, settings: SettingsData) -> URL? {
        var components: URLComponents
        switch settings.searchFlavor {
        case .standard: components = URLComponents(string: "https://duckduckgo.com/")!
        case .lite: components = URLComponents(string: "https://lite.duckduckgo.com/lite/")!
        case .html: components = URLComponents(string: "https://html.duckduckgo.com/html/")!
        }
        var items = [URLQueryItem(name: "q", value: query)]
        if !settings.searchRegion.isEmpty && settings.searchRegion != "wt-wt" {
            items.append(URLQueryItem(name: "kl", value: settings.searchRegion))
        }
        if settings.safeSearch != .moderate {
            items.append(URLQueryItem(name: "kp", value: settings.safeSearch.kp))
        }
        components.queryItems = items
        return components.url
    }

    /// Returns the search query if `url` is a DuckDuckGo results page.
    static func query(from url: URL?) -> String? {
        guard let url, let host = url.host?.lowercased(), host.hasSuffix("duckduckgo.com"),
              let comps = URLComponents(url: url, resolvingAgainstBaseURL: false) else { return nil }
        return comps.queryItems?.first(where: { $0.name == "q" })?.value
    }

    /// Turns whatever the user typed into a URL: either the address itself or a DuckDuckGo search.
    static func resolve(_ input: String, settings: SettingsData) -> URL? {
        let text = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return nil }

        if let url = URL(string: text), let scheme = url.scheme?.lowercased(),
           ["http", "https", "file", "about", "data", "saints-ext"].contains(scheme) {
            return url
        }
        if !text.contains(" ") {
            let lower = text.lowercased()
            let looksLikeHost = lower.hasPrefix("localhost")
                || lower.range(of: #"^\d{1,3}(\.\d{1,3}){3}(:\d+)?(/.*)?$"#, options: .regularExpression) != nil
                || lower.range(of: #"^[a-z0-9-]+(\.[a-z0-9-]+)*\.[a-z]{2,}(:\d+)?([/?#].*)?$"#, options: .regularExpression) != nil
            if looksLikeHost, let url = URL(string: "https://" + text) {
                return url
            }
        }
        return searchURL(for: text, settings: settings)
    }

    static let regions: [SearchRegion] = [
        SearchRegion(code: "wt-wt", name: "No region"),
        SearchRegion(code: "us-en", name: "United States"),
        SearchRegion(code: "uk-en", name: "United Kingdom"),
        SearchRegion(code: "ca-en", name: "Canada (English)"),
        SearchRegion(code: "ca-fr", name: "Canada (French)"),
        SearchRegion(code: "au-en", name: "Australia"),
        SearchRegion(code: "in-en", name: "India"),
        SearchRegion(code: "ie-en", name: "Ireland"),
        SearchRegion(code: "nz-en", name: "New Zealand"),
        SearchRegion(code: "de-de", name: "Germany"),
        SearchRegion(code: "fr-fr", name: "France"),
        SearchRegion(code: "es-es", name: "Spain"),
        SearchRegion(code: "it-it", name: "Italy"),
        SearchRegion(code: "nl-nl", name: "Netherlands"),
        SearchRegion(code: "se-sv", name: "Sweden"),
        SearchRegion(code: "no-no", name: "Norway"),
        SearchRegion(code: "dk-da", name: "Denmark"),
        SearchRegion(code: "fi-fi", name: "Finland"),
        SearchRegion(code: "pl-pl", name: "Poland"),
        SearchRegion(code: "pt-pt", name: "Portugal"),
        SearchRegion(code: "br-pt", name: "Brazil"),
        SearchRegion(code: "mx-es", name: "Mexico"),
        SearchRegion(code: "ar-es", name: "Argentina"),
        SearchRegion(code: "jp-jp", name: "Japan"),
        SearchRegion(code: "kr-kr", name: "Korea"),
        SearchRegion(code: "cn-zh", name: "China"),
        SearchRegion(code: "tw-tzh", name: "Taiwan"),
        SearchRegion(code: "ru-ru", name: "Russia"),
        SearchRegion(code: "tr-tr", name: "Turkey"),
        SearchRegion(code: "za-en", name: "South Africa"),
        SearchRegion(code: "ph-en", name: "Philippines"),
        SearchRegion(code: "sg-en", name: "Singapore")
    ]
}

struct SearchRegion: Hashable {
    let code: String
    let name: String
}

/// Fetches DuckDuckGo autocomplete suggestions over an ephemeral, cookie-less session.
final class SuggestionService {
    static let shared = SuggestionService()

    private let session: URLSession = {
        let config = URLSessionConfiguration.ephemeral
        config.httpCookieStorage = nil
        config.httpShouldSetCookies = false
        config.urlCache = nil
        config.timeoutIntervalForRequest = 4
        return URLSession(configuration: config)
    }()

    private var task: URLSessionDataTask?

    func suggestions(for query: String, completion: @escaping ([String]) -> Void) {
        task?.cancel()
        let trimmed = query.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty,
              var comps = URLComponents(string: "https://duckduckgo.com/ac/") else {
            completion([])
            return
        }
        comps.queryItems = [URLQueryItem(name: "q", value: trimmed), URLQueryItem(name: "type", value: "list")]
        guard let url = comps.url else { completion([]); return }
        task = session.dataTask(with: url) { data, _, _ in
            var results: [String] = []
            if let data, let json = try? JSONSerialization.jsonObject(with: data) {
                if let arr = json as? [Any], arr.count > 1, let list = arr[1] as? [String] {
                    results = list
                } else if let arr = json as? [[String: Any]] {
                    results = arr.compactMap { $0["phrase"] as? String }
                }
            }
            DispatchQueue.main.async { completion(Array(results.prefix(6))) }
        }
        task?.resume()
    }
}
