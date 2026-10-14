import SwiftUI
import UniformTypeIdentifiers

struct ExtensionsView: View {
    @EnvironmentObject var manager: ExtensionManager
    @EnvironmentObject var settings: BrowserSettings
    @Environment(\.dismiss) private var dismiss

    @State private var showURLPrompt = false
    @State private var urlText = ""
    @State private var importing = false
    @State private var pending: PendingInstall?
    @State private var editor: EditorTarget?
    @State private var busy = false

    struct EditorTarget: Identifiable {
        let id = UUID()
        let kind: WebExtension.Kind
        let source: String
        let existingID: String?
    }

    static let importTypes: [UTType] = {
        var types: [UTType] = [.zip, .javaScript, .plainText, .data]
        for ext in ["xpi", "crx", "css"] { if let t = UTType(filenameExtension: ext) { types.append(t) } }
        return types
    }()

    var body: some View {
        NavigationStack {
            List {
                Section {
                    Toggle(isOn: $settings.data.extensionsEnabled) {
                        Label("Enable Extensions", systemImage: "puzzlepiece.extension.fill")
                    }
                } footer: {
                    Text("Install Firefox add-ons (.xpi), Chrome extensions (.crx), userscripts (.user.js) and userstyles. Saints supports the common WebExtension APIs — storage, messaging, tabs, scripting, i18n, alarms and declarativeNetRequest content blocking.")
                }

                Section {
                    NavigationLink { UBlockView() } label: {
                        HStack(spacing: 12) {
                            UBlockBadge(size: 38)
                            VStack(alignment: .leading, spacing: 2) {
                                Text("uBlock Origin")
                                Text(UBlockEngine.shared.state.enabled ? "Built in · \(UBlockEngine.shared.status.text)" : "Built in · Off")
                                    .font(.caption).foregroundStyle(.secondary)
                            }
                        }
                    }
                } header: {
                    Text("Built In")
                }

                if busy {
                    HStack { ProgressView(); Text("Fetching…").foregroundStyle(.secondary) }
                }

                if !manager.extensions.isEmpty {
                    Section("Installed") {
                        ForEach(manager.extensions) { ext in
                            NavigationLink { ExtensionDetailView(extID: ext.id, editor: $editor) } label: {
                                ExtensionRow(ext: ext)
                            }
                        }
                        .onDelete { offsets in
                            offsets.map { manager.extensions[$0].id }.forEach(manager.uninstall)
                        }
                    }
                }

                Section("Get Extensions") {
                    Button { showURLPrompt = true } label: {
                        Label("Install from Link", systemImage: "link")
                    }
                    Button { importing = true } label: {
                        Label("Install from Files", systemImage: "folder")
                    }
                    Button { openSite("https://addons.mozilla.org/firefox/extensions/") } label: {
                        Label("Browse Firefox Add-ons", systemImage: "safari")
                    }
                    Button { openSite("https://greasyfork.org/") } label: {
                        Label("Browse Greasy Fork Userscripts", systemImage: "curlybraces")
                    }
                    Button { openSite("https://userstyles.world/") } label: {
                        Label("Browse UserStyles.world", systemImage: "paintbrush")
                    }
                }

                Section("Create") {
                    Button { editor = EditorTarget(kind: .userScript, source: BuiltInExtensions.newScriptTemplate, existingID: nil) } label: {
                        Label("New Userscript", systemImage: "chevron.left.forwardslash.chevron.right")
                    }
                    Button { editor = EditorTarget(kind: .userStyle, source: BuiltInExtensions.newStyleTemplate, existingID: nil) } label: {
                        Label("New Userstyle", systemImage: "paintpalette")
                    }
                }

                Section("Saints Gallery") {
                    ForEach(BuiltInExtensions.gallery) { item in
                        GalleryRow(item: item, installed: manager.extensions.contains { $0.name == item.name }) {
                            install(item)
                        }
                    }
                }
            }
            .navigationTitle("Extensions")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
            .alert("Install from Link", isPresented: $showURLPrompt) {
                TextField("https://…", text: $urlText)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .keyboardType(.URL)
                Button("Cancel", role: .cancel) {}
                Button("Install") { stage(urlText) }
            } message: {
                Text("Paste a link to an .xpi, .crx, .zip or .user.js file, a Firefox Add-ons page, or a Chrome Web Store page.")
            }
            .fileImporter(isPresented: $importing, allowedContentTypes: Self.importTypes) { result in
                if case .success(let url) = result { stage(file: url) }
            }
            .sheet(item: $pending) { InstallSheet(pending: $0) }
            .sheet(item: $editor) { target in
                SourceEditorView(target: target)
            }
        }
    }

    private func openSite(_ s: String) {
        if let url = URL(string: s) {
            TabManager.shared.newTab(url: url, isPrivate: false)
            dismiss()
        }
    }

    private func install(_ item: GalleryItem) {
        do {
            try manager.saveSource(item.source, kind: item.kind, existingID: manager.extensions.first { $0.name == item.name }?.id)
            settings.haptic(.medium)
            ToastCenter.shared.show("\(item.name) added", symbol: "puzzlepiece.extension.fill")
        } catch {
            ToastCenter.shared.show(error.localizedDescription, symbol: "exclamationmark.triangle")
        }
    }

    private func stage(_ link: String) {
        busy = true
        manager.stage(fromURL: link) { result in
            busy = false
            urlText = ""
            switch result {
            case .success(let p): pending = p
            case .failure(let e): ToastCenter.shared.show(e.localizedDescription, symbol: "exclamationmark.triangle")
            }
        }
    }

    private func stage(file: URL) {
        let scoped = file.startAccessingSecurityScopedResource()
        defer { if scoped { file.stopAccessingSecurityScopedResource() } }
        do {
            let data = try Data(contentsOf: file)
            pending = try manager.stage(data: data, filename: file.lastPathComponent, sourceURL: nil)
        } catch {
            ToastCenter.shared.show(error.localizedDescription, symbol: "exclamationmark.triangle")
        }
    }
}

private struct ExtensionRow: View {
    let ext: WebExtension
    @EnvironmentObject var manager: ExtensionManager

    var body: some View {
        HStack(spacing: 12) {
            ExtensionIcon(ext: ext, size: 38)
            VStack(alignment: .leading, spacing: 2) {
                Text(ext.name).lineLimit(1)
                Text("\(ext.kind.label) · v\(ext.version)").font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            Toggle("", isOn: Binding(get: { ext.enabled }, set: { manager.setEnabled($0, for: ext.id) }))
                .labelsHidden()
        }
    }
}

private struct GalleryRow: View {
    let item: GalleryItem
    let installed: Bool
    var onInstall: () -> Void
    @EnvironmentObject var settings: BrowserSettings

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: item.symbol)
                .foregroundStyle(.white)
                .frame(width: 38, height: 38)
                .background(settings.accent.gradient, in: RoundedRectangle(cornerRadius: 9, style: .continuous))
            VStack(alignment: .leading, spacing: 2) {
                Text(item.name)
                Text(item.summary).font(.caption).foregroundStyle(.secondary).lineLimit(2)
            }
            Spacer()
            Button(installed ? "Added" : "Add", action: onInstall)
                .buttonStyle(.bordered)
                .disabled(installed)
        }
    }
}

struct ExtensionDetailView: View {
    let extID: String
    @Binding var editor: ExtensionsView.EditorTarget?
    @EnvironmentObject var manager: ExtensionManager
    @Environment(\.dismiss) private var dismiss
    @State private var confirmRemove = false
    @State private var page: ExtensionHost.ExtensionPage?

    var body: some View {
        if let ext = manager.extensionWith(id: extID) {
            List {
                Section {
                    HStack(spacing: 14) {
                        ExtensionIcon(ext: ext, size: 56)
                        VStack(alignment: .leading, spacing: 3) {
                            Text(ext.name).font(.headline)
                            Text("\(ext.kind.label) · v\(ext.version)").font(.subheadline).foregroundStyle(.secondary)
                            if !ext.author.isEmpty { Text(ext.author).font(.caption).foregroundStyle(.secondary) }
                        }
                    }
                    if !ext.summary.isEmpty { Text(ext.summary).font(.subheadline) }
                }
                Section {
                    Toggle("Enabled", isOn: Binding(get: { ext.enabled }, set: { manager.setEnabled($0, for: ext.id) }))
                    Toggle("Run in Private Tabs", isOn: Binding(get: { ext.allowPrivate }, set: { manager.setAllowPrivate($0, for: ext.id) }))
                }
                Section {
                    if ext.popupPath != nil {
                        Button { page = .init(ext: ext, path: ext.popupPath ?? "", context: "popup") } label: {
                            Label("Open Popup", systemImage: "rectangle.portrait.on.rectangle.portrait")
                        }
                    }
                    if ext.optionsPath != nil {
                        Button { page = .init(ext: ext, path: ext.optionsPath ?? "", context: "options") } label: {
                            Label("Options", systemImage: "slider.horizontal.3")
                        }
                    }
                    if ext.hasBackground {
                        Button { ExtensionHost.shared.reloadBackground(ext.id) } label: { Label("Reload Background", systemImage: "arrow.clockwise") }
                    }
                    if ext.kind != .webExtension, let source = manager.source(of: ext) {
                        Button { editor = .init(kind: ext.kind, source: source, existingID: ext.id) } label: {
                            Label("Edit Source", systemImage: "chevron.left.forwardslash.chevron.right")
                        }
                    }
                    if !ext.homepage.isEmpty, let url = URL(string: ext.homepage) {
                        Button { TabManager.shared.newTab(url: url, isPrivate: false) } label: { Label("Homepage", systemImage: "house") }
                    }
                }
                if !ext.displayPermissions.isEmpty {
                    Section("Permissions") {
                        ForEach(ext.displayPermissions, id: \.self) { p in
                            Label(PermissionText.describe(p), systemImage: PermissionText.symbol(p)).font(.subheadline)
                        }
                    }
                }
                Section("Details") {
                    LabeledContent("Content scripts", value: "\(ext.contentScripts.count)")
                    if ext.kind == .webExtension { LabeledContent("Manifest", value: "V\(ext.manifestVersion)") }
                    if !ext.dnrRulesets.isEmpty { LabeledContent("Block rulesets", value: "\(ext.dnrRulesets.count)") }
                    LabeledContent("Installed", value: ext.installDate.formatted(date: .abbreviated, time: .omitted))
                    if let src = ext.sourceURL { Text(src).font(.caption).foregroundStyle(.secondary).textSelection(.enabled) }
                }
                Section {
                    Button("Remove Extension", role: .destructive) { confirmRemove = true }
                }
            }
            .navigationTitle(ext.name)
            .navigationBarTitleDisplayMode(.inline)
            .sheet(item: $page) { ExtensionPageSheet(page: $0) }
            .confirmationDialog("Remove \(ext.name)?", isPresented: $confirmRemove, titleVisibility: .visible) {
                Button("Remove", role: .destructive) {
                    manager.uninstall(ext.id)
                    dismiss()
                }
            }
        } else {
            Text("Extension removed.").foregroundStyle(.secondary)
        }
    }
}

struct SourceEditorView: View {
    let target: ExtensionsView.EditorTarget
    @State private var text: String
    @Environment(\.dismiss) private var dismiss
    @State private var error: String?

    init(target: ExtensionsView.EditorTarget) {
        self.target = target
        _text = State(initialValue: target.source)
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                if let error {
                    Text(error).font(.footnote).foregroundStyle(.white).padding(8).frame(maxWidth: .infinity).background(.red)
                }
                TextEditor(text: $text)
                    .font(.system(.footnote, design: .monospaced))
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .padding(.horizontal, 6)
            }
            .navigationTitle(target.kind == .userStyle ? "Userstyle" : "Userscript")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        do {
                            try ExtensionManager.shared.saveSource(text, kind: target.kind, existingID: target.existingID)
                            ToastCenter.shared.show("Saved", symbol: "checkmark.circle.fill")
                            dismiss()
                        } catch {
                            self.error = error.localizedDescription
                        }
                    }
                    .font(.body.weight(.semibold))
                }
            }
        }
    }
}
