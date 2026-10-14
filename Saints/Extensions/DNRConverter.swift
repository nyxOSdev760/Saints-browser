import Foundation

/// Translates an extension's Manifest V3 `declarativeNetRequest` static rules into WebKit
/// content-blocker rules, so MV3 ad/tracker blockers work natively on iOS.
enum DNRConverter {
    /// WebKit allows at most 150k rules per list; extensions get a single list.
    static let maxRules = 145_000

    static func convert(_ rules: [[String: Any]]) -> [[String: Any]] {
        UBlockConverter.network(rules).chunks(size: maxRules).first ?? []
    }
}
