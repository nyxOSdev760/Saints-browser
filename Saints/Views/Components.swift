import SwiftUI
import WebKit
import UIKit

/// Hosts a tab's existing WKWebView inside SwiftUI without recreating it.
/// `topInset` / `bottomInset` keep page content clear of floating glass bars.
struct WebViewContainer: UIViewRepresentable {
    let webView: WKWebView
    var topInset: CGFloat = 0
    var bottomInset: CGFloat = 0

    func makeUIView(context: Context) -> UIView {
        let container = UIView()
        container.backgroundColor = .systemBackground
        attach(to: container)
        applyInsets()
        return container
    }

    func updateUIView(_ container: UIView, context: Context) {
        if webView.superview !== container { attach(to: container) }
        applyInsets()
    }

    private func applyInsets() {
        let sv = webView.scrollView
        let insets = UIEdgeInsets(top: topInset, left: 0, bottom: bottomInset, right: 0)
        guard sv.contentInset != insets else { return }
        sv.contentInset = insets
        sv.verticalScrollIndicatorInsets = insets
    }

    private func attach(to container: UIView) {
        container.subviews.forEach { $0.removeFromSuperview() }
        webView.removeFromSuperview()
        webView.frame = container.bounds
        webView.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        container.addSubview(webView)
    }
}

/// Frosted glass panel: blurred backdrop, light edge highlight and a soft floating shadow.
struct GlassSurface<S: InsettableShape>: View {
    let shape: S
    var isPrivate = false
    var shadow = true
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        let dark = scheme == .dark || isPrivate
        shape
            .fill(.ultraThinMaterial)
            .overlay(shape.fill(isPrivate ? Color.black.opacity(0.35) : Color.white.opacity(dark ? 0.03 : 0.22)))
            .overlay(
                shape.fill(LinearGradient(colors: [Color.white.opacity(dark ? 0.10 : 0.35), .clear],
                                          startPoint: .top, endPoint: .center))
            )
            .overlay(
                shape.strokeBorder(
                    LinearGradient(colors: [Color.white.opacity(dark ? 0.32 : 0.85),
                                            Color.white.opacity(dark ? 0.06 : 0.25),
                                            Color.white.opacity(dark ? 0.14 : 0.45)],
                                   startPoint: .top, endPoint: .bottom),
                    lineWidth: 0.8)
            )
            .shadow(color: .black.opacity(shadow ? (dark ? 0.45 : 0.14) : 0), radius: 16, y: 6)
    }
}

/// Springy press feedback; dims when disabled.
struct PressableStyle: ButtonStyle {
    var scale: CGFloat = 0.9

    func makeBody(configuration: Configuration) -> some View {
        Pressable(configuration: configuration, scale: scale)
    }

    private struct Pressable: View {
        let configuration: ButtonStyleConfiguration
        let scale: CGFloat
        @Environment(\.isEnabled) private var enabled

        var body: some View {
            configuration.label
                .scaleEffect(configuration.isPressed ? scale : 1)
                .opacity(enabled ? (configuration.isPressed ? 0.75 : 1) : 0.35)
                .animation(.spring(response: 0.25, dampingFraction: 0.6), value: configuration.isPressed)
        }
    }
}

/// Measures a view's height (used to inset page content under floating bars).
struct HeightKey: PreferenceKey {
    static var defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) { value = max(value, nextValue()) }
}

extension View {
    func measureHeight(_ key: HeightKey.Type = HeightKey.self) -> some View {
        background(GeometryReader { Color.clear.preference(key: key, value: $0.size.height) })
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

/// The search-field look shared by the address bar (and formerly the start page field).
struct SearchFieldBackground: View {
    let radius: CGFloat
    var focused = false
    var isPrivate = false
    @EnvironmentObject var settings: BrowserSettings

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: radius, style: .continuous)
        ZStack {
            if settings.data.barMaterial == .glass {
                GlassSurface(shape: shape, isPrivate: isPrivate)
            } else {
                shape
                    .fill(isPrivate ? Color.white.opacity(0.12) : Color(uiColor: .secondarySystemBackground))
                    .shadow(color: .black.opacity(0.06), radius: 10, y: 3)
            }
        }
        .overlay(shape.strokeBorder(focused ? settings.accent : Color.primary.opacity(0.07), lineWidth: focused ? 2 : 1))
        .animation(.easeOut(duration: 0.15), value: focused)
    }
}

struct FieldBackground: View {
    @EnvironmentObject var settings: BrowserSettings
    var isPrivate: Bool

    var body: some View {
        if settings.data.barMaterial == .glass {
            GlassSurface(shape: RoundedRectangle(cornerRadius: min(settings.data.barCornerRadius + 8, 23), style: .continuous),
                         isPrivate: isPrivate)
        } else {
            RoundedRectangle(cornerRadius: settings.data.barCornerRadius, style: .continuous)
                .fill(isPrivate ? Color.white.opacity(0.12) : Color(uiColor: .tertiarySystemFill))
        }
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
