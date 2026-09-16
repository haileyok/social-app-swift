import Lexicons
import ProfileLogic

/**
 Saves an edited profile through the production profile mutation pipeline.

 `ProfileManager` mirrors RN's `useProfileUpdateMutation`: it validates the
 edit, uploads replacement avatar/banner blobs, merges the changes into the
 current profile record without dropping unknown fields, writes the record,
 and waits for the appview to observe the commit.
 */
enum ProfileEditor {

  @discardableResult
  static func save(clients: AppSessionClients, edit: ProfileEdit) async throws
    -> App.Bsky.ActorDefs_ProfileViewDetailed?
  {
    try await ProfileManager(
      client: clients.pds,
      appView: ProfileClient(client: clients.appview)
    ).write(edit, repo: clients.did)
  }
}
