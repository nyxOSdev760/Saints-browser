import SwiftUI
import WebKit
import UIKit

/// Hosts a tab's existing WKWebView inside SwiftUI without recreating it.
struct WebViewContainer: UIViewRepresentable {
    let webView: WKWebView

    func makeUIView(context: Context) -> UIView {
        let container = UIView()
        container.backgroundColor = .systemBackground
        attach(to: container)
        return container
    }

    func updateUIView(_ container: UIView, context: Context) {
        if webView.superview !== container { attach(to: container) }
    }

    private func attach(to container: UIView) {
        container.subviews.forEach { $0.removeFromSuperview() }
        webView.removeFromSuperview()
        webView.frame = container.bounds
        webView.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        container.addSubview(webView)
    }
}

/// The Saints wordmark: a halo floating over the name.
struct SaintsLogo: View {
    var size: CGFloat = 44
    @EnvironmentObject var settings: BrowserSettings

    var body: some View {
        VStack(spacing: size * 0.08) {
            Ellipse()
                .stroke(
                    LinearGradient(colors: [Color(hex: "#FFE29F"), Color(hex: "#F6B24E")], startPoint: .leading, endPoint: .trailing),
                    lineWidth: size * 0.09)
                .frame(width: size * 1.1, height: size * 0.28)
                .shadow(color: Color(hex: "#F6B24E").opacity(0.7), radius: size * 0.2)
            Text("Saints")
                .font(.system(size: size, weight: .bold, design: settings.data.fontDesign.design))
                .tracking(-0.5)
        }
    }
}

struct FaviconView: View {
    let urlString: String
    var size: CGFloat = 52
    var cornerFraction: CGFloat = 0.28
    @EnvironmentObject var settings: BrowserSettings

    private var host: String { URL(string: urlString)?.host ?? urlString }
    private var letter: String {
        let h = host.hasPrefix("www.") ? String(host.dropFirst(4)) : host
        return String(h.prefix(1)).uppercased()
    }

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: size * cornerFraction, style: .continuous)
                .fill(.thinMaterial)
            Text(letter)
                .font(.system(size: size * 0.42, weight: .semibold, design: .rounded))
                .foregroundStyle(.secondary)
            if settings.data.loadFavicons, let url = URL(string: "https://icons.duckduckgo.com/ip3/\(host).ico") {
                AsyncImage(url: url) { phase in
                    if let image = phase.image {
                        image.resizable().interpolation(.high).scaledToFit()
                            .frame(width: size * 0.55, height: size * 0.55)
                            .frame(width: size, height: size)
                            .background(RoundedRectangle(cornerRadius: size * cornerFraction, style: .continuous).fill(.regularMaterial))
                    }
                }
            }
        }
        .frame(width: size, height: size)
    }
}

/// Background used by the address bar and toolbar, driven by the user's material choice.
struct BarBackground: View {
    @EnvironmentObject var settings: BrowserSettings
    @Environment(\.colorScheme) var scheme
    var isPrivate: Bool

    var body: some View {
        Group {
            if isPrivate {
                Color(hex: "#1E1530")
            } else {
                switch settings.data.barMaterial {
                case .glass:
                    Rectangle().fill(.bar)
                case .solid:
                    settings.data.theme == .black ? Color.black : Color(uiColor: .secondarySystemBackground)
                case .tinted:
                    ZStack {
                        Rectangle().fill(.bar)
                        settings.accent.opacity(scheme == .dark ? 0.28 : 0.16)
                    }
                }
            }
        }
        .ignoresSafeArea(edges: [.top, .bottom])
    }
}

struct FieldBackground: View {
    @EnvironmentObject var settings: BrowserSettings
    var isPrivate: Bool

    var body: some View {
        RoundedRectangle(cornerRadius: settings.data.barCornerRadius, style: .continuous)
            .fill(isPrivate ? Color.white.opacity(0.12) : Color(uiColor: .tertiarySystemFill))
    }
}

struct ToastView: View {
    let toast: ToastCenter.Toast
    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: toast.symbol)
            Text(toast.text).font(.subheadline.weight(.medium)).lineLimit(2)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 11)
        .background(.regularMaterial, in: Capsule())
        .shadow(color: .black.opacity(0.15), radius: 12, y: 4)
        .padding(.horizontal, 24)
    }
}

enum Share {
    static func present(_ items: [Any]) {
        let vc = UIActivityViewController(activityItems: items, applicationActivities: nil)
        guard let top = UIApplication.topViewController else { return }
        if let pop = vc.popoverPresentationController {
            pop.sourceView = top.view
            pop.sourceRect = CGRect(x: top.view.bounds.midX, y: top.view.bounds.maxY - 60, width: 1, height: 1)
        }
        top.present(vc, animated: true)
    }
}

/// Wraps any WKWebView configuration in a SwiftUI view (used for extension popups / options).
struct ExtensionPageWebView: UIViewRepresentable {
    let page: ExtensionHost.ExtensionPage

    func makeUIView(context: Context) -> WKWebView {
        let config = ExtensionHost.shared.pageConfiguration(for: page.ext, context: page.context)
        let webView = WKWebView(frame: .zero, configuration: config)
        webView.isInspectable = BrowserSettings.shared.data.webInspector
        webView.isOpaque = false
        webView.backgroundColor = .systemBackground
        ExtensionHost.shared.registerPopup(webView, extID: page.ext.id)
        if let url = URL(string: page.ext.baseURL + page.path.trimmingCharacters(in: CharacterSet(charactersIn: "/"))) {
            webView.load(URLRequest(url: url))
        }
        return webView
    }

    func updateUIView(_ uiView: WKWebView, context: Context) {}
}

extension View {
    @ViewBuilder func `if`<T: View>(_ condition: Bool, transform: (Self) -> T) -> some View {
        if condition { transform(self) } else { self }
    }
}
