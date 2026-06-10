import Foundation
import Security

struct Credentials {
    var accessToken: String
    var accountId: String     // numeric or act_-prefixed
    var pageId: String        // optional, needed for ad creative creation

    var actId: String { accountId.hasPrefix("act_") ? accountId : "act_\(accountId)" }

    private static let service = "com.moerdowo.MadMac"
    private static let account = "meta-ads"

    static func load() -> Credentials? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
        ]
        var item: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &item) == errSecSuccess,
              let data = item as? Data,
              let dict = try? JSONDecoder().decode([String: String].self, from: data),
              let token = dict["token"], let acct = dict["account"], !token.isEmpty, !acct.isEmpty
        else { return nil }
        return Credentials(accessToken: token, accountId: acct, pageId: dict["page"] ?? "")
    }

    func save() throws {
        let data = try JSONEncoder().encode(["token": accessToken, "account": accountId, "page": pageId])
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: Self.service,
            kSecAttrAccount as String: Self.account,
        ]
        SecItemDelete(query as CFDictionary)
        var add = query
        add[kSecValueData as String] = data
        let status = SecItemAdd(add as CFDictionary, nil)
        guard status == errSecSuccess else {
            throw NSError(domain: "Keychain", code: Int(status),
                          userInfo: [NSLocalizedDescriptionKey: "Keychain save failed (\(status))"])
        }
    }

    static func clear() {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
        SecItemDelete(query as CFDictionary)
    }
}
