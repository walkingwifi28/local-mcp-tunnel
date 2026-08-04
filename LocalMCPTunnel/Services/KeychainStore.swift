import Foundation
import Security

final class KeychainStore {
    static let shared = KeychainStore()

    private let service = "jp.co.walkingwifi.LocalMCPTunnel"
    private let legacyServices = ["jp.co.varista.LocalMCPTunnelApp"]
    private let account = "CONTROL_PLANE_API_KEY"

    private init() {}

    func save(_ value: String) throws {
        if value.isEmpty {
            try deleteItem(for: service)
            for legacyService in legacyServices {
                try deleteItem(for: legacyService)
            }
            return
        }

        try upsert(value, for: service)

        // The new service is now authoritative. Remove legacy copies so a
        // cleared key cannot reappear on a later launch.
        for legacyService in legacyServices {
            try deleteItem(for: legacyService)
        }
    }

    func read() throws -> String? {
        if let value = try readItem(for: service) {
            return value
        }

        for legacyService in legacyServices {
            guard let legacyValue = try readItem(for: legacyService) else { continue }
            try save(legacyValue)
            return legacyValue
        }

        return nil
    }

    private func upsert(_ value: String, for service: String) throws {
        let query = baseQuery(for: service)
        let data = Data(value.utf8)
        let attributes: [String: Any] = [kSecValueData as String: data]
        let updateStatus = SecItemUpdate(query as CFDictionary, attributes as CFDictionary)

        if updateStatus == errSecItemNotFound {
            var insert = query
            insert[kSecValueData as String] = data
            insert[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlock
            let insertStatus = SecItemAdd(insert as CFDictionary, nil)
            guard insertStatus == errSecSuccess else { throw KeychainError(insertStatus) }
        } else if updateStatus != errSecSuccess {
            throw KeychainError(updateStatus)
        }
    }

    private func readItem(for service: String) throws -> String? {
        var query = baseQuery(for: service)
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne

        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        if status == errSecItemNotFound { return nil }
        guard status == errSecSuccess else { throw KeychainError(status) }
        guard let data = item as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }

    private func deleteItem(for service: String) throws {
        let status = SecItemDelete(baseQuery(for: service) as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw KeychainError(status)
        }
    }

    private func baseQuery(for service: String) -> [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]
    }

    struct KeychainError: LocalizedError {
        let status: OSStatus

        init(_ status: OSStatus) {
            self.status = status
        }

        var errorDescription: String? {
            SecCopyErrorMessageString(status, nil) as String? ?? "Keychain error: \(status)"
        }
    }
}
