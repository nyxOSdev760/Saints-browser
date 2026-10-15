import Foundation

/// Drives the app into a given state for the CI screenshot job (`-saintsShot <mode>` launch argument).
/// Does nothing in normal use.
enum ScreenshotDriver {
    private static var ran = false

    static var mode: String? {
        let args = ProcessInfo.processInfo.arguments
        guard let i = args.firstIndex(of: "-saintsShot"), i + 1 < args.count else { return nil }
        return args[i + 1]
    }

    @MainActor
    static func run(showTabs: @escaping () -> Void, showSheet: @escaping (BrowserSheet) -> Void) async {
        guard !ran, let mode else { return }
        ran = true
        let tabs = TabManager.shared
        func wait(_ seconds: Double) async { try? await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000)) }
        func open(_ s: String) -> BrowserTab { tabs.newTab(url: URL(string: s), isPrivate: false, select: true) }

        await wait(1)
        switch mode {
        case "page":
            tabs.selectedTab?.load(URL(string: "https://en.wikipedia.org/wiki/Web_browser")!)
        case "tabs":
            for site in ["https://en.wikipedia.org/wiki/Web_browser", "https://duckduckgo.com/?q=saints+browser",
                         "https://github.com/uBlockOrigin/uBOL-home", "https://news.ycombinator.com/"] {
                let tab = open(site)
                await wait(6)
                tab.captureSnapshot()
                await wait(0.5)
            }
            if let first = tabs.normalTabs.first { tabs.select(first) }
            await wait(1)
            showTabs()
        case "menu":
            tabs.selectedTab?.load(URL(string: "https://en.wikipedia.org/wiki/Web_browser")!)
            await wait(6)
            showSheet(.menu)
        case "ua":
            let html = "<meta name=viewport content='width=device-width'><body style='font:17px -apple-system;padding:24px'>"
                + "<h3>User agent</h3><p id=u></p><script>u.textContent=navigator.userAgent</script>"
            tabs.selectedTab?.load(URL(string: "data:text/html," + (html.addingPercentEncoding(withAllowedCharacters: .alphanumerics) ?? ""))!)
        case "claude":
            tabs.selectedTab?.load(URL(string: "https://claude.ai/login")!)
        case "detect":
            tabs.selectedTab?.load(URL(string: "https://www.whatismybrowser.com/")!)
        case "customize":
            showSheet(.customize)
        case "wallpaper":
            BrowserSettings.shared.data.wallpaper = .aurora
            showSheet(.wallpapers)
        default:
            break   // "home": the start page as-is
        }
    }
}
