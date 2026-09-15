import Lexicons

/**
 Disambiguates the generated lexicon namespace from SwiftUI's `App` protocol.

 `Lexicons` declares `public enum App` for the `app.bsky.*` namespace, and
 SwiftUI declares the `App` protocol. A file that imports both - which every view
 in this package does, because it renders lexicon views - cannot spell `App.Bsky`
 without the compiler calling it ambiguous.

 This module-scope alias shadows both imports inside StarterPacksViews, so the
 view files keep writing `App.Bsky.…` exactly as the Logic package next door
 does. (A `typealias` cannot be `public` and the module is not re-exporting it,
 so the shadowing is confined to this package.)
 */
typealias App = Lexicons.App
