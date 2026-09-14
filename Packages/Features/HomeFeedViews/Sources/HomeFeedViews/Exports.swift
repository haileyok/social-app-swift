// The modules `HomeFeedViews`' public API is written in terms of.
//
// A screen's signature cannot avoid naming its model (`HomeFeedLogic`), its
// theme (`DesignSystem`), or its moderation options (`Moderation`). Re-exporting
// them here means a consumer - the app shell's `AppShell+HomeFeedViews.swift` -
// needs one package dependency and one import, instead of declaring the whole
// transitive graph itself. The app shell deliberately does not own this package
// graph; the feature package does.
@_exported import DesignSystem
@_exported import DesignSystemCore
@_exported import HomeFeedLogic
@_exported import Moderation
@_exported import UIComponentsCore
