import ATProtoClient
import Foundation
import Lexicons
import ProfileLogic
import SwiftAtproto

/**
 Saves an edited profile record.

 The RN flow writes the whole `app.bsky.actor.profile` record back with
 `putRecord`, merging the edit onto the *record* it just fetched with
 `getRecord` - not onto the profile *view* the screen rendered (views carry
 CDN URLs where records carry blob refs). This port does the same, and writes
 through a dictionary so every field the record already carries - including
 fields this app never edits - survives untouched.

 Avatar/banner replacement requires blob uploads and is not wired yet: a
 `.replaced` change still writes the existing blob. TODO: upload through
 `com.atproto.repo.uploadBlob` and swap the ref before the put.
 */
enum ProfileEditor {

  /** Fetches the live record, overlays the edit, and puts it back. */
  static func save(clients: AppSessionClients, edit: ProfileEdit) async throws {
    let output = try await clients.pds.get(
      Com.Atproto.RepoGetRecord.id,
      params: [
        ("repo", clients.did),
        ("collection", "app.bsky.actor.profile"),
        ("rkey", "self"),
      ]
    ) as Com.Atproto.RepoGetRecord_Output

    // Round-trip the record through its raw JSON so nothing is lost in a
    // field-by-field copy.
    let raw = try JSONEncoder().encode(output.value)
    var record = try JSONDecoder().decode([String: AnyCodable].self, from: raw)

    // The generated record types decode `$type` but do not encode it back
    // (the codegen gap documented in tools/lexicon-codegen); the PDS requires
    // it, so the dictionary path sets it explicitly.
    record["$type"] = AnyCodable("app.bsky.actor.profile")

    if edit.displayName.isEmpty {
      record["displayName"] = nil
    } else {
      record["displayName"] = AnyCodable(edit.displayName)
    }
    if edit.description.isEmpty {
      record["description"] = nil
    } else {
      record["description"] = AnyCodable(edit.description)
    }

    _ = try await clients.pds.putRecord(
      repo: clients.did,
      collection: "app.bsky.actor.profile",
      rkey: "self",
      record: record)
  }
}
