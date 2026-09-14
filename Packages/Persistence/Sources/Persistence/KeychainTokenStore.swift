#if canImport(Security)
  import Foundation
  import Security

  /// Keychain-backed token store for Apple platforms.
  ///
  /// This entire file is behind `canImport(Security)` so the package keeps
  /// building on Linux, where the file-backed store is the implementation in
  /// use. Tokens are stored as generic passwords keyed by
  /// `<did>:<kind>` under one service, with
  /// `kSecAttrAccessibleAfterFirstUnlock` so a background refresh can read
  /// them after a reboot without an unlock.
  public struct KeychainTokenStore: SessionTokenStore {
    /// Keychain service the items live under.
    public let service: String

    public init(service: String = "app.bsky.social.session") {
      self.service = service
    }

    private func account(for did: String, kind: SessionTokenKind) -> String {
      "\(did):\(kind.rawValue)"
    }

    private func baseQuery(did: String, kind: SessionTokenKind) -> [String: Any] {
      [
        kSecClass as String: kSecClassGenericPassword,
        kSecAttrService as String: service,
        kSecAttrAccount as String: account(for: did, kind: kind),
      ]
    }

    private func query() -> [String: Any] {
      [
        kSecClass as String: kSecClassGenericPassword,
        kSecAttrService as String: service,
      ]
    }

    public func store(
      _ token: String, kind: SessionTokenKind, for did: String
    ) async throws {
      let base = baseQuery(did: did, kind: kind)
      // Keychain has no upsert: delete then add.
      SecItemDelete(base as CFDictionary)
      var item = base
      item[kSecValueData as String] = Data(token.utf8)
      item[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlock
      let status = SecItemAdd(item as CFDictionary, nil)
      guard status == errSecSuccess else {
        throw SessionTokenStoreError.keychain(status)
      }
    }

    public func token(
      kind: SessionTokenKind, for did: String
    ) async throws -> String? {
      var item = baseQuery(did: did, kind: kind)
      item[kSecReturnData as String] = true
      item[kSecMatchLimit as String] = kSecMatchLimitOne
      var result: CFTypeRef?
      let status = SecItemCopyMatching(item as CFDictionary, &result)
      if status == errSecItemNotFound { return nil }
      guard status == errSecSuccess else {
        throw SessionTokenStoreError.keychain(status)
      }
      guard let data = result as? Data else {
        throw SessionTokenStoreError.invalidTokenData
      }
      guard let token = String(data: data, encoding: .utf8) else {
        throw SessionTokenStoreError.invalidTokenData
      }
      return token
    }

    public func remove(kind: SessionTokenKind, for did: String) async throws {
      let status = SecItemDelete(baseQuery(did: did, kind: kind) as CFDictionary)
      guard status == errSecSuccess || status == errSecItemNotFound else {
        throw SessionTokenStoreError.keychain(status)
      }
    }

    public func removeAll(for did: String) async throws {
      for kind in SessionTokenKind.allCases {
        try await remove(kind: kind, for: did)
      }
    }

    /// Deletes every item under this store's service.
    public func removeAll() async throws {
      let status = SecItemDelete(query() as CFDictionary)
      guard status == errSecSuccess || status == errSecItemNotFound else {
        throw SessionTokenStoreError.keychain(status)
      }
    }

    /// Keychain cannot enumerate attributes cheaply, so the DIDs are read
    /// back from the stored account attributes.
    public func dids() async throws -> [String] {
      var item = query()
      item[kSecReturnAttributes as String] = true
      item[kSecMatchLimit as String] = kSecMatchLimitAll
      var result: CFTypeRef?
      let status = SecItemCopyMatching(item as CFDictionary, &result)
      if status == errSecItemNotFound { return [] }
      guard status == errSecSuccess else {
        throw SessionTokenStoreError.keychain(status)
      }
      guard let items = result as? [[String: Any]] else { return [] }
      var dids: Set<String> = []
      for entry in items {
        guard let account = entry[kSecAttrAccount as String] as? String
        else { continue }
        // DIDs themselves contain ':' (e.g. did:plc:abc); the kind is the
        // final component, so drop only that.
        let components = account.split(separator: ":")
        guard components.count >= 2 else { continue }
        dids.insert(components.dropLast().joined(separator: ":"))
      }
      return dids.sorted()
    }
  }
#endif
