import Foundation
import Lexicons

/// Unambiguous names for the two generated lexicon views the moderation
/// surfaces render.
///
/// The generator declares its namespaces as top-level enums, so `App` is a type
/// in the `Lexicons` module. SwiftUI also declares an `App` protocol, and in a
/// file that imports both the bare name `App` is ambiguous - which makes
/// `App.Bsky.…` fail to resolve in any SwiftUI file. These aliases are declared
/// in a file that does not import SwiftUI, where `App` resolves to the lexicon
/// namespace unambiguously, so the rest of the package can name these types
/// without qualification.
///
/// The aliased paths are the same ones `ModerationUILogic` writes in its public
/// signatures, so a rename upstream surfaces here as a compile error rather than
/// as a silent mismatch.
public typealias ModerationProfileView = App.Bsky.ActorDefs_ProfileView
public typealias ModerationLabelerViewDetailed = App.Bsky.LabelerDefs_LabelerViewDetailed
