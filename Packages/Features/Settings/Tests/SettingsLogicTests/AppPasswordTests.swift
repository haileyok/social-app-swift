import Foundation
import Testing

import ATProtoClient
import Lexicons
import Preferences
import SwiftAtproto

@testable import SettingsLogic

/// App-password validation, ported from
/// `screens/Settings/components/AddAppPasswordDialog.tsx`.
@Suite struct AppPasswordValidationTests {

  /// The allowed-character rule is RN's `^[a-zA-Z0-9-_ ]*$`.
  @Test func characterRule() {
    #expect(AppPasswordValidation.hasValidCharacters("AliceBlue"))
    #expect(AppPasswordValidation.hasValidCharacters("alice blue"))
    #expect(AppPasswordValidation.hasValidCharacters("alice-blue"))
    #expect(AppPasswordValidation.hasValidCharacters("alice_blue"))
    #expect(AppPasswordValidation.hasValidCharacters("AliceBlue99"))
    // An empty field is allowed: RN falls back to the generated name.
    #expect(AppPasswordValidation.hasValidCharacters(""))
    // Everything else is rejected.
    #expect(!AppPasswordValidation.hasValidCharacters("alice.blue"))
    #expect(!AppPasswordValidation.hasValidCharacters("alice@blue"))
    #expect(!AppPasswordValidation.hasValidCharacters("alice/blue"))
    #expect(!AppPasswordValidation.hasValidCharacters("alice+blue"))
  }

  /// The display error is the exact RN copy.
  @Test func displayError() {
    #expect(AppPasswordValidation.displayError(typed: "alice.blue") != nil)
    #expect(
      AppPasswordValidation.displayError(typed: "alice.blue")
        == "App password names can only contain letters, numbers, spaces, hyphens, and underscores")
    #expect(AppPasswordValidation.displayError(typed: "alice-blue") == nil)
  }

  /// A blank field falls back to the generated suggestion.
  @Test func generatedNameFallback() {
    #expect(AppPasswordValidation.chosenName(typed: "", generated: "AliceBlue") == "AliceBlue")
    #expect(AppPasswordValidation.chosenName(typed: "   ", generated: "Aqua") == "Aqua")
    #expect(AppPasswordValidation.chosenName(typed: " mine ", generated: "Aqua") == "mine")
  }

  /// The length rule is checked on the chosen name.
  @Test func minimumLength() {
    let short = AppPasswordValidation.validate(
      typed: "abc", generated: "AliceBlue", existingNames: [])
    #expect(short == .invalid(message: "App password names must be at least 4 characters long"))

    let ok = AppPasswordValidation.validate(
      typed: "abcd", generated: "AliceBlue", existingNames: [])
    #expect(ok == .valid(name: "abcd"))
  }

  /// The generated name is length-checked too, since it becomes the chosen one.
  @Test func generatedNameIsLengthChecked() {
    let outcome = AppPasswordValidation.validate(
      typed: "", generated: "ab", existingNames: [])
    #expect(outcome == .invalid(message: "App password names must be at least 4 characters long"))
  }

  /// Uniqueness is checked against the account's existing names.
  @Test func uniqueness() {
    let taken = AppPasswordValidation.validate(
      typed: "AliceBlue", generated: "Aqua", existingNames: ["AliceBlue", "SkyBlue"])
    #expect(taken == .invalid(message: "App password name must be unique"))

    let free = AppPasswordValidation.validate(
      typed: "RoseBlue", generated: "Aqua", existingNames: ["AliceBlue"])
    #expect(free == .valid(name: "RoseBlue"))
  }

  /// Length is checked before uniqueness, matching RN's order.
  @Test func lengthCheckedBeforeUniqueness() {
    let outcome = AppPasswordValidation.validate(
      typed: "ab", generated: "Aqua", existingNames: ["ab"])
    #expect(outcome == .invalid(message: "App password names must be at least 4 characters long"))
  }

  /// The suggestion list is RN's `shadesOfBlue`, verbatim.
  @Test func suggestionList() {
    #expect(AppPasswordNameSuggestions.shadesOfBlue.count == 32)
    #expect(AppPasswordNameSuggestions.shadesOfBlue.first == "AliceBlue")
    #expect(AppPasswordNameSuggestions.shadesOfBlue.last == "Turquoise")
    #expect(AppPasswordNameSuggestions.shadesOfBlue.contains("DodgerBlue"))
    #expect(AppPasswordNameSuggestions.suggestion(at: 0) == "AliceBlue")
    #expect(AppPasswordNameSuggestions.suggestion(at: 31) == "Turquoise")
    // Wraps into range.
    #expect(AppPasswordNameSuggestions.suggestion(at: 32) == "AliceBlue")
  }
}

/// The app-password service's exact XRPC calls.
@Suite struct AppPasswordServiceTests {

  /// `listAppPasswords` is a GET against the PDS with no query params.
  @Test func listRequestShape() async throws {
    let transport = ScriptedTransport(
      ScriptedTransport.json(["passwords": []]))
    let service = LiveAppPasswordService(
      client: XrpcClient(baseURL: "https://pds.test", transport: transport))

    _ = try await service.listAppPasswords()

    let request = try #require(transport.lastRequest)
    #expect(request.method == "GET")
    #expect(request.url == "https://pds.test/xrpc/com.atproto.server.listAppPasswords")
    #expect(request.body == nil)
  }

  /// The list response decodes name and privileged, which is all the list
  /// endpoint returns.
  @Test func listDecodes() async throws {
    let transport = ScriptedTransport(
      ScriptedTransport.json([
        "passwords": [
          ["name": "AliceBlue", "privileged": true, "createdAt": "2024-01-01T00:00:00Z"],
          ["name": "SkyBlue", "createdAt": "2024-01-02T00:00:00Z"],
        ]
      ]))
    let service = LiveAppPasswordService(
      client: XrpcClient(baseURL: "https://pds.test", transport: transport))

    let passwords = try await service.listAppPasswords()
    #expect(passwords.count == 2)
    #expect(passwords[0].name == "AliceBlue")
    #expect(passwords[0].privileged)
    // An absent `privileged` means false.
    #expect(passwords[1].privileged == false)
    // The list endpoint never returns the plaintext.
    #expect(passwords.allSatisfy { $0.password == nil })
  }

  /// `createAppPassword` POSTs the exact body RN sends.
  @Test func createRequestBody() async throws {
    let transport = ScriptedTransport(
      ScriptedTransport.json([
        "name": "AliceBlue", "password": "abcd-efgh-ijkl-mnop",
        "createdAt": "2024-01-01T00:00:00Z", "privileged": true,
      ]))
    let service = LiveAppPasswordService(
      client: XrpcClient(baseURL: "https://pds.test", transport: transport))

    let created = try await service.createAppPassword(name: "AliceBlue", privileged: true)

    let request = try #require(transport.lastRequest)
    #expect(request.method == "POST")
    #expect(request.url == "https://pds.test/xrpc/com.atproto.server.createAppPassword")
    #expect(request.headers["Content-Type"] == "application/json")
    #expect(request.json["name"] as? String == "AliceBlue")
    #expect(request.json["privileged"] as? Bool == true)
    #expect(created.name == "AliceBlue")
    #expect(created.password == "abcd-efgh-ijkl-mnop")
    #expect(created.privileged)
  }

  /// A non-privileged create still sends the flag explicitly, because RN passes
  /// the boolean through.
  @Test func createBodySendsFalsePrivileged() async throws {
    let transport = ScriptedTransport(
      ScriptedTransport.json([
        "name": "Aqua", "password": "aaaa-bbbb-cccc-dddd",
        "createdAt": "2024-01-01T00:00:00Z",
      ]))
    let service = LiveAppPasswordService(
      client: XrpcClient(baseURL: "https://pds.test", transport: transport))

    _ = try await service.createAppPassword(name: "Aqua", privileged: false)

    let request = try #require(transport.lastRequest)
    #expect(request.json["privileged"] as? Bool == false)
  }

  /// `revokeAppPassword` POSTs only the name.
  @Test func revokeRequestBody() async throws {
    let transport = ScriptedTransport(
      HTTPResponse(status: 200, headers: [:], body: Data()))
    let service = LiveAppPasswordService(
      client: XrpcClient(baseURL: "https://pds.test", transport: transport))

    try await service.revokeAppPassword(name: "AliceBlue")

    let request = try #require(transport.lastRequest)
    #expect(request.method == "POST")
    #expect(request.url == "https://pds.test/xrpc/com.atproto.server.revokeAppPassword")
    #expect(request.json["name"] as? String == "AliceBlue")
    // The endpoint takes only `name`; nothing else is sent.
    #expect(request.json.keys.sorted() == ["name"])
  }

  /// A create failure surfaces as an error rather than an empty password.
  @Test func createFailurePropagates() async throws {
    let transport = ScriptedTransport(
      ScriptedTransport.xrpcError("AccountTakedown", message: "taken down", status: 400))
    let service = LiveAppPasswordService(
      client: XrpcClient(baseURL: "https://pds.test", transport: transport))

    await #expect(throws: (any Error).self) {
      _ = try await service.createAppPassword(name: "AliceBlue", privileged: false)
    }
  }
}

/// The store's app-password operations over a fake service.
@Suite struct AppPasswordStoreTests {

  /// A create with a valid name calls the service with the chosen name and the
  /// privileged flag.
  @Test func createUsesChosenName() async {
    let harness = await StoreHarness()
    defer { harness.cleanUp() }

    let result = await harness.store.createAppPassword(
      typedName: "MyPhone", privileged: true, generatedName: "AliceBlue")

    guard case .success(let created) = result else {
      Issue.record("expected success, got \(result)")
      return
    }
    #expect(created.name == "MyPhone")
    #expect(harness.appPasswords.lastCreatedName == "MyPhone")
    #expect(harness.appPasswords.calls.contains { $0.privileged == true })
  }

  /// A create with a blank name uses the generated suggestion.
  @Test func createFallsBackToGeneratedName() async {
    let harness = await StoreHarness()
    defer { harness.cleanUp() }

    let result = await harness.store.createAppPassword(
      typedName: "", privileged: false, generatedName: "SkyBlue")

    guard case .success(let created) = result else {
      Issue.record("expected success, got \(result)")
      return
    }
    #expect(created.name == "SkyBlue")
    #expect(harness.appPasswords.lastCreatedName == "SkyBlue")
  }

  /// The too-short rule never reaches the service.
  @Test func createRejectsShortNameWithoutNetwork() async {
    let harness = await StoreHarness()
    defer { harness.cleanUp() }

    let result = await harness.store.createAppPassword(
      typedName: "ab", privileged: false, generatedName: "Aqua")

    guard case .failure(let error) = result else {
      Issue.record("expected failure, got \(result)")
      return
    }
    #expect(error.message == "App password names must be at least 4 characters long")
    #expect(harness.appPasswords.calls.isEmpty)
  }

  /// The uniqueness rule is checked against the loaded list, and never reaches
  /// the service.
  @Test func createRejectsDuplicateWithoutNetwork() async {
    let harness = await StoreHarness(
      passwords: [SettingsAppPassword(name: "AliceBlue", privileged: false)])
    defer { harness.cleanUp() }
    await harness.store.loadAppPasswords()

    let result = await harness.store.createAppPassword(
      typedName: "AliceBlue", privileged: false, generatedName: "Aqua")

    guard case .failure(let error) = result else {
      Issue.record("expected failure, got \(result)")
      return
    }
    #expect(error.message == "App password name must be unique")
    #expect(harness.appPasswords.calls.contains { $0.method == "create" } == false)
  }

  /// A create failure is mapped onto the generic copy with the raw message kept
  /// for logging.
  @Test func createFailureIsMapped() async {
    let harness = await StoreHarness()
    defer { harness.cleanUp() }
    harness.appPasswords.setCreateError(
      XrpcError(rawCode: "InvalidRequest", message: "boom", status: 400))

    let result = await harness.store.createAppPassword(
      typedName: "MyPhone", privileged: false, generatedName: "Aqua")

    guard case .failure(let error) = result else {
      Issue.record("expected failure, got \(result)")
      return
    }
    #expect(error.message == "Failed to create app password. Please try again.")
    #expect(error.raw == "boom")
  }

  /// The list is reloaded after a successful create, so the new name shows.
  @Test func listReloadsAfterCreate() async {
    let harness = await StoreHarness()
    defer { harness.cleanUp() }
    await harness.store.loadAppPasswords()

    _ = await harness.store.createAppPassword(
      typedName: "MyPhone", privileged: false, generatedName: "Aqua")

    #expect(harness.store.state.appPasswords.map(\.name) == ["MyPhone"])
  }

  /// The list is sorted by name, so the screen's order is stable.
  @Test func listIsSortedByName() async {
    let harness = await StoreHarness(
      passwords: [
        SettingsAppPassword(name: "Zebra", privileged: false),
        SettingsAppPassword(name: "Alice", privileged: false),
      ])
    defer { harness.cleanUp() }

    await harness.store.loadAppPasswords()
    #expect(harness.store.state.appPasswords.map(\.name) == ["Alice", "Zebra"])
  }

  /// A list failure records the fetch error copy and leaves the list empty.
  @Test func listFailureIsMapped() async {
    let harness = await StoreHarness()
    defer { harness.cleanUp() }
    harness.appPasswords.setListError(
      XrpcError(rawCode: nil, message: "offline", status: -1))

    await harness.store.loadAppPasswords()

    #expect(harness.store.state.appPasswordsStatus == .failed)
    #expect(harness.store.state.appPasswordsError?.message
      == "There was an issue fetching your app passwords")
    #expect(harness.store.state.appPasswords.isEmpty)
  }

  /// Revoking removes the password and reloads the list.
  @Test func revoke() async {
    let harness = await StoreHarness(
      passwords: [
        SettingsAppPassword(name: "Alice", privileged: false),
        SettingsAppPassword(name: "Bob", privileged: false),
      ])
    defer { harness.cleanUp() }
    await harness.store.loadAppPasswords()

    let result = await harness.store.revokeAppPassword(name: "Alice")

    guard case .success = result else {
      Issue.record("expected success, got \(result)")
      return
    }
    #expect(harness.appPasswords.calls.contains { $0.method == "revoke" && $0.name == "Alice" })
    #expect(harness.store.state.appPasswords.map(\.name) == ["Bob"])
  }

  /// A revoke failure is mapped and the list is left alone.
  @Test func revokeFailureIsMapped() async {
    let harness = await StoreHarness(
      passwords: [SettingsAppPassword(name: "Alice", privileged: false)])
    defer { harness.cleanUp() }
    await harness.store.loadAppPasswords()
    harness.appPasswords.setRevokeError(
      XrpcError(rawCode: nil, message: "nope", status: 500))

    let result = await harness.store.revokeAppPassword(name: "Alice")

    guard case .failure(let error) = result else {
      Issue.record("expected failure, got \(result)")
      return
    }
    #expect(error.message == "Failed to delete app password. Please try again.")
    #expect(harness.store.state.appPasswords.map(\.name) == ["Alice"])
  }

  /// The form validation runs against the loaded list, through the store.
  @Test func formValidationUsesLoadedList() async {
    let harness = await StoreHarness(
      passwords: [SettingsAppPassword(name: "AliceBlue", privileged: false)])
    defer { harness.cleanUp() }
    await harness.store.loadAppPasswords()

    let outcome = harness.store.validateAppPasswordForm(
      typedName: "AliceBlue", generatedName: "Aqua")
    #expect(outcome == .invalid(message: "App password name must be unique"))
  }
}
