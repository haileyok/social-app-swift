import Foundation

/**
 The file system handle the Persistence stores hold.

 `FileManager` is not `Sendable` in the iOS SDK, so it cannot be stored inside a
 `Sendable` type (`Storage`, `FileTokenStore`) or passed across an actor's
 isolation boundary (an `actor`'s `init` is `nonisolated`, so every argument to it
 is "sent"). Linux does not catch either mistake: `FoundationEssentials`'
 `FileManager` *is* `Sendable`, so the mismatch only surfaces when the package is
 compiled for iOS - which first happened when LoginViews linked
 LoginLogic/Persistence into the app target.

 The judgement being recorded here is that the handle is safe to share: the
 default manager is a documented thread-safe singleton, and every use is a
 synchronous path operation (`fileExists`, `createDirectory`, `contentsOfDirectory`,
 `removeItem`, `Data(contentsOf:)`) with no shared mutable bookkeeping of our own.
 Recording it once, in one box, keeps it out of the stores' own type declarations.
 */
public struct SendableFileManager: @unchecked Sendable {
  public let value: FileManager

  public init(_ value: FileManager = .default) {
    self.value = value
  }
}
