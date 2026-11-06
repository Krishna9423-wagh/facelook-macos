import Foundation
import Security

/// Secure storage service for biometric facial feature embeddings using macOS Keychain.
public final class KeychainBiometricsStorage: Sendable {

    public static let shared = KeychainBiometricsStorage()

    public static let defaultAccount = "primary_enrolled_face"
    public static let defaultService = "com.macid.facelook.biometrics"

    private let service: String

    public init(service: String = defaultService) {
        self.service = service
    }

    // MARK: - Save Embedding

    /// Securely writes a float embedding vector to the macOS Keychain.
    /// If an item already exists for the account, it updates it.
    @discardableResult
    public func saveEmbedding(_ embedding: [Float], for account: String = defaultAccount) -> Bool {
        guard !embedding.isEmpty else { return false }

        // Serialize [Float] to raw Data
        let data = embedding.withUnsafeBufferPointer { Data(buffer: $0) }

        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        ]

        let status = SecItemAdd(query as CFDictionary, nil)

        if status == errSecDuplicateItem {
            // Item exists, update it
            let updateQuery: [String: Any] = [
                kSecClass as String: kSecClassGenericPassword,
                kSecAttrService as String: service,
                kSecAttrAccount as String: account
            ]
            let attributesToUpdate: [String: Any] = [
                kSecValueData as String: data
            ]
            let updateStatus = SecItemUpdate(updateQuery as CFDictionary, attributesToUpdate as CFDictionary)
            return updateStatus == errSecSuccess
        }

        return status == errSecSuccess
    }

    // MARK: - Load Embedding

    /// Retrieves and deserializes the stored float embedding vector from Keychain.
    public func loadEmbedding(for account: String = defaultAccount) -> [Float]? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]

        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)

        guard status == errSecSuccess, let data = item as? Data else {
            return nil
        }

        let floatCount = data.count / MemoryLayout<Float>.size
        guard floatCount > 0 else { return nil }

        var floats = [Float](repeating: 0, count: floatCount)
        _ = floats.withUnsafeMutableBytes { data.copyBytes(to: $0) }
        return floats
    }

    // MARK: - Delete & Status

    /// Removes an enrolled embedding from the Keychain.
    @discardableResult
    public func deleteEmbedding(for account: String = defaultAccount) -> Bool {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]
        let status = SecItemDelete(query as CFDictionary)
        return status == errSecSuccess || status == errSecItemNotFound
    }

    /// Checks whether an enrolled embedding exists in Keychain.
    public func isEnrolled(for account: String = defaultAccount) -> Bool {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: false,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        let status = SecItemCopyMatching(query as CFDictionary, nil)
        return status == errSecSuccess
    }
}

