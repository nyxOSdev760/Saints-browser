import SwiftUI

/// Settings page for the built-in uBlock Origin engine.
struct UBlockView: View {
    @ObservedObject private var engine = UBlockEngine.shared
    @EnvironmentObject var settings: BrowserSettings
    @State private var listSearch = ""

    private static let groupOrder = ["default", "ads", "privacy", "malware", "annoyances", "regions"]
    private static let groupTitles = [
        "default": "Default", "ads": "Ads", "privacy": "Privacy", "malware": "Malware Protection & Security",
        "annoyances": "Annoyances", "regions": "Regions & Languages"
    ]

    var body: some View {
        Form {
            Section {
                HStack(spacing: 14) {
                    UBlockBadge(size: 52)
                    VStack(alignment: .leading, spacing: 3) {
                        Text("uBlock Origin").font(.headline)
                        Text("Filters from uBlock Origin Lite, running natively in WebKit")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                }
                .padding(.vertical, 4)
                Toggle("Enabled", isOn: Binding(get: { engine.state.enabled }, set: { engine.setEnabled($0) }))
            }

            if engine.state.enabled {
                Section("Status") {
                    HStack {
                        Text(engine.status.text)
                            .foregroundStyle(statusColor)
                        Spacer()
                        if case .working = engine.status { ProgressView() }
                    }
                    if engine.state.lastUpdated != nil {
                        LabeledContent("Network rules", value: engine.state.networkRules.formatted())
                        LabeledContent("Element hiding filters", value: engine.state.cosmeticRules.formatted())
                        LabeledContent("Filter lists", value: "\(engine.state.activeRulesets.count)")
                        if let date = engine.state.lastUpdated {
                            LabeledContent("Updated", value: date.formatted(.relative(presentation: .named)))
                        }
                    }
                    Button(engine.selectionChanged ? "Apply List Changes" : "Update Filters Now") { engine.update() }
                        .disabled(isWorking)
                }

                Section {
                    Toggle("Scriptlet Filtering", isOn: Binding(get: { engine.state.scriptlets }, set: { engine.setScriptlets($0) }))
                    Toggle("Update Weekly", isOn: Binding(get: { engine.state.autoUpdate }, set: { engine.setAutoUpdate($0) }))
                } footer: {
                    Text("Scriptlets defuse ads and anti-adblock scripts that can't be blocked by URL, such as video ads.")
                }

                if !engine.state.allowlist.isEmpty {
                    Section {
                        ForEach(engine.state.allowlist, id: \.self) { host in
                            Text(host)
                        }
                        .onDelete { offsets in
                            offsets.map { engine.state.allowlist[$0] }.forEach(engine.removeFromAllowlist)
                        }
                    } header: {
                        Text("Turned Off On")
                    } footer: {
                        Text("Use the page menu (left of the address) to switch uBlock Origin off for a site.")
                    }
                }

                listsSection
            }

            Section {
                Text("Lists are downloaded from github.com/uBlockOrigin/uBOL-home. SV Browser never sends anything about the pages you visit; blocking happens on your device.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                Text("uBlock Origin and uBO Lite are © Raymond Hill and contributors, GPLv3. Filter lists belong to their respective authors.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
        .navigationTitle("uBlock Origin")
        .searchable(text: $listSearch, prompt: "Search filter lists")
    }

    private var isWorking: Bool {
        if case .working = engine.status { return true }
        return false
    }

    private var statusColor: Color {
        switch engine.status {
        case .ready: return .green
        case .failed: return .red
        default: return .secondary
        }
    }

    @ViewBuilder private var listsSection: some View {
        if engine.catalog.isEmpty {
            Section("Filter Lists") {
                Text("The list catalog appears after the first download.").foregroundStyle(.secondary)
            }
        } else {
            let filtered = engine.catalog.filter {
                listSearch.isEmpty || $0.name.localizedCaseInsensitiveContains(listSearch)
                    || ($0.lang ?? "").localizedCaseInsensitiveContains(listSearch)
            }
            let groups = Dictionary(grouping: filtered, by: \.group)
            ForEach(groups.keys.sorted(by: groupSort), id: \.self) { group in
                Section(Self.groupTitles[group] ?? group.capitalized) {
                    ForEach(groups[group] ?? []) { ruleset in
                        Toggle(isOn: Binding(get: { engine.selection.contains(ruleset.id) },
                                             set: { engine.setSelected(ruleset.id, $0) })) {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(ruleset.name)
                                if ruleset.filterCount > 0 {
                                    Text("\(ruleset.filterCount.formatted()) filters").font(.caption).foregroundStyle(.secondary)
                                }
                            }
                        }
                    }
                }
            }
            Section {
                Button("Restore Default Lists") { engine.resetSelection() }
            } footer: {
                Text("More lists mean more blocking but slower updates. Tap “Apply List Changes” above after changing lists.")
            }
        }
    }

    private func groupSort(_ a: String, _ b: String) -> Bool {
        let ia = Self.groupOrder.firstIndex(of: a) ?? 99
        let ib = Self.groupOrder.firstIndex(of: b) ?? 99
        return ia != ib ? ia < ib : a < b
    }
}

/// uBO-style red shield badge.
struct UBlockBadge: View {
    var size: CGFloat = 40
    var body: some View {
        Image(systemName: "shield.fill")
            .font(.system(size: size * 0.5, weight: .semibold))
            .foregroundStyle(.white)
            .overlay(
                Text("u").font(.system(size: size * 0.26, weight: .heavy, design: .rounded))
                    .foregroundStyle(Color(hex: "#800000"))
                    .offset(y: -size * 0.02)
            )
            .frame(width: size, height: size)
            .background(Color(hex: "#800000"), in: RoundedRectangle(cornerRadius: size * 0.24, style: .continuous))
    }
}
