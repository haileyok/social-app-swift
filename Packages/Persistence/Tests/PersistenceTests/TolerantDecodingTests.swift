import Foundation
import Testing

@testable import Persistence

@Suite struct TolerantDecodingTests {
  /// Builds a full, valid persisted document as raw JSON.
  static func validDocument(
    accounts: [[String: Any]] = [],
    currentDID: String? = nil
  ) -> [String: Any] {
    var session: [String: Any] = ["accounts": accounts]
    if let currentDID {
      session["currentAccount"] = ["did": currentDID]
    }
    return [
      "colorMode": "dark",
      "darkTheme": "dim",
      "session": session,
      "reminders": ["lastEmailConfirm": "2026-01-01"],
      "languagePrefs": [
        "primaryLanguage": "en",
        "contentLanguages": ["en", "ja"],
        "postLanguage": "en",
        "postLanguageHistory": ["en"],
        "appLanguage": "en",
      ],
      "requireAltTextEnabled": true,
      "invites": ["copiedInvites": ["code-1"]],
      "onboarding": ["step": "Home"],
      "mutedThreads": [],
    ]
  }

  static func account(
    did: String, handle: String = "alice.example", service: String = "https://bsky.social"
  ) -> [String: Any] {
    [
      "service": service,
      "did": did,
      "handle": handle,
      "accessJwt": "access-\(did)",
      "refreshJwt": "refresh-\(did)",
    ]
  }

  private func decode(_ document: [String: Any]) -> (PersistedSchema, [DecodeIssue]) {
    let raw = JSONValue.object(document.mapValues { JSONValue.fromAny($0) })
    return PersistedSchema.decodeTolerantly(from: raw)
  }

  @Test func decodesAValidDocumentWithNoIssues() {
    let (schema, issues) = decode(
      Self.validDocument(accounts: [Self.account(did: "did:plc:alice")], currentDID: "did:plc:alice")
    )
    #expect(issues.isEmpty)
    #expect(schema.colorMode == .dark)
    #expect(schema.requireAltTextEnabled == true)
    #expect(schema.session.accounts.count == 1)
    #expect(schema.session.accounts.first?.did == "did:plc:alice")
    #expect(schema.session.currentAccount?.did == "did:plc:alice")
  }

  /// The central deviation: one bad field must NOT discard the document.
  ///
  /// The TS layer validates the whole document with zod and returns
  /// `undefined` on any failure, which drops every account and every
  /// preference. Here the bad field falls back and everything else survives.
  @Test func oneBadFieldDoesNotDiscardOtherAccounts() {
    var document = Self.validDocument(
      accounts: [
        Self.account(did: "did:plc:alice"),
        Self.account(did: "did:plc:bob"),
      ],
      currentDID: "did:plc:alice")
    // Corrupt a single scalar: colorMode is an enum, "chartreuse" is invalid.
    document["colorMode"] = "chartreuse"

    let (schema, issues) = decode(document)

    // The bad field fell back to the default...
    #expect(schema.colorMode == .system)
    #expect(issues.contains { $0.field == "colorMode" })
    // ...while BOTH accounts and the current-account pointer survived.
    #expect(schema.session.accounts.count == 2)
    #expect(schema.session.accounts.map(\.did).sorted() == ["did:plc:alice", "did:plc:bob"])
    #expect(schema.session.currentAccount?.did == "did:plc:alice")
    // And unrelated preferences survived.
    #expect(schema.requireAltTextEnabled == true)
    #expect(schema.invites.copiedInvites == ["code-1"])
  }

  @Test func wrongTypedScalarFallsBackToDefault() {
    var document = Self.validDocument()
    document["requireAltTextEnabled"] = "yes"  // string where bool expected
    document["mutedThreads"] = 42  // number where array expected

    let (schema, issues) = decode(document)

    #expect(schema.requireAltTextEnabled == false)
    #expect(schema.mutedThreads == [])
    #expect(issues.contains { $0.field == "requireAltTextEnabled" })
    #expect(issues.contains { $0.field == "mutedThreads" })
  }

  @Test func corruptAccountEntryDropsOnlyThatAccount() {
    var alice = Self.account(did: "did:plc:alice")
    alice["emailConfirmed"] = "not-a-bool"  // bad field inside one account
    let document = Self.validDocument(
      accounts: [
        alice,
        ["handle": "no-did.example"],  // entry with no did: unrecoverable
        Self.account(did: "did:plc:bob"),
      ])

    let (schema, issues) = decode(document)

    // Alice survives with her bad field defaulted; only the did-less entry is
    // dropped.
    #expect(schema.session.accounts.count == 2)
    #expect(schema.session.accounts.map(\.did) == ["did:plc:alice", "did:plc:bob"])
    #expect(schema.session.accounts.first?.emailConfirmed == nil)
    #expect(issues.contains { $0.field.contains("accounts[1]") })
    #expect(schema.session.accounts.first?.accessJwt == "access-did:plc:alice")
  }

  @Test func missingNestedObjectFallsBackToDefaults() {
    var document = Self.validDocument()
    document.removeValue(forKey: "languagePrefs")
    document.removeValue(forKey: "onboarding")

    let (schema, _) = decode(document)

    #expect(schema.languagePrefs == LanguagePrefs())
    #expect(schema.onboarding.step == "Home")
  }

  @Test func nonObjectAccountElementIsSkipped() {
    var document = Self.validDocument(accounts: [Self.account(did: "did:plc:alice")])
    var session = document["session"] as? [String: Any] ?? [:]
    session["accounts"] = [Self.account(did: "did:plc:alice"), "not-an-object"]
    document["session"] = session

    let (schema, issues) = decode(document)

    #expect(schema.session.accounts.count == 1)
    #expect(issues.contains { $0.field.contains("accounts[1]") })
  }

  @Test func nonObjectRootYieldsDefaults() {
    let (schema, issues) = PersistedSchema.decodeTolerantly(from: .string("hello"))
    #expect(schema == PersistedSchema.defaults())
    #expect(issues.count == 1)
    #expect(issues.first?.field == "(root)")
  }

  @Test func unknownFieldsAreIgnoredNotErrors() {
    var document = Self.validDocument(accounts: [Self.account(did: "did:plc:alice")])
    document["someFutureField"] = ["nested": true]

    let (schema, issues) = decode(document)

    #expect(issues.isEmpty)
    #expect(schema.session.accounts.count == 1)
  }

  @Test func optionalTokenFieldsMayBeAbsent() {
    let document = Self.validDocument(accounts: [
      ["service": "https://bsky.social", "did": "did:plc:alice", "handle": "alice.example"]
    ])

    let (schema, issues) = decode(document)

    #expect(issues.isEmpty)
    // A logged-out account entry (no tokens) is valid.
    #expect(schema.session.accounts.first?.accessJwt == nil)
    #expect(schema.session.accounts.first?.refreshJwt == nil)
  }
}

extension JSONValue {
  /// Test helper: bridges an `[String: Any]` literal into `JSONValue`.
  static func fromAny(_ value: Any) -> JSONValue {
    switch value {
    case let bool as Bool:
      return .bool(bool)
    case let number as Double:
      return .number(number)
    case let number as Int:
      return .number(Double(number))
    case let string as String:
      return .string(string)
    case let array as [Any]:
      return .array(array.map(fromAny))
    case let object as [String: Any]:
      return .object(object.mapValues(fromAny))
    default:
      return .null
    }
  }
}
