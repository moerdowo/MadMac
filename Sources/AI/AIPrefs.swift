import SwiftUI
import Security

// AI feature gate: everything AI is hidden unless `enabled` AND a key exists.

enum ImageQuality: String, CaseIterable, Identifiable {
    case low = "Low", medium = "Medium", high = "High"
    var id: String { rawValue }
    var apiValue: String { rawValue.lowercased() }
    var costHint: String {
        switch self {
        case .low: return "≈ $0.01–0.02 / image"
        case .medium: return "≈ $0.04–0.07 / image"
        case .high: return "≈ $0.17–0.25 / image"
        }
    }
}

final class AIPrefs: ObservableObject {
    static let shared = AIPrefs()

    @AppStorage("aiEnabled") var enabled = false
    @AppStorage("aiTextModel") var textModel = "gpt-4o-mini"
    @AppStorage("aiImageQuality") var imageQuality: ImageQuality = .medium
    @AppStorage("aiAutoPolicyCheck") var autoPolicyCheck = true

    /// AI features are usable only with the toggle on and a stored key.
    var isActive: Bool { enabled && Self.loadKey() != nil }

    // ── OpenAI key in the Keychain ─────────────────────────────────────────

    private static let service = "com.moerdowo.MadMac"
    private static let account = "openai"

    static func loadKey() -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
        ]
        var item: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &item) == errSecSuccess,
              let data = item as? Data,
              let key = String(data: data, encoding: .utf8), !key.isEmpty else { return nil }
        return key
    }

    static func saveKey(_ key: String) throws {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
        SecItemDelete(query as CFDictionary)
        guard !key.isEmpty else { return }
        var add = query
        add[kSecValueData as String] = Data(key.utf8)
        let status = SecItemAdd(add as CFDictionary, nil)
        guard status == errSecSuccess else {
            throw NSError(domain: "Keychain", code: Int(status),
                          userInfo: [NSLocalizedDescriptionKey: "Keychain save failed (\(status))"])
        }
    }

    static func clearKey() {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
        SecItemDelete(query as CFDictionary)
    }
}
