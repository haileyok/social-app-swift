import Foundation
import Lexicons
import Preferences

/// One saved feed as the management screen models it.
///
/// Port of `app.bsky.actor.defs.SavedFeed` as `SaveFeeds.tsx` uses it: an `id`
/// minted on write, a `type` (`timeline`/`feed`/`list`), the `value` the item
/// points at, and whether it is pinned. Pinned items are the ones that appear
/// as tabs.
public struct SavedFeedItem: Sendable, Equatable, Hashable {
  /// The minted id, which is the handle every mutation keys on.
  public let id: String
  /// `timeline`, `feed` or `list`.
  public let type: String
  /// `following` for the timeline, an AT URI otherwise.
  public let value: String
  /// Whether the item is pinned to the home tab bar.
  public var isPinned: Bool

  public init(id: String, type: String, value: String, isPinned: Bool) {
    self.id = id
    self.type = type
    self.value = value
    self.isPinned = isPinned
  }

  /// Decodes one item out of the raw preference record.
  public init?(pref: PrefObject) {
    guard let id = pref["id"]?.stringValue,
      let type = pref["type"]?.stringValue,
      let value = pref["value"]?.stringValue
    else { return nil }
    self.init(
      id: id, type: type, value: value, isPinned: pref["pinned"]?.boolValue ?? false)
  }

  /// Encodes back into the raw preference record.
  ///
  /// Includes `$type` because that is what the record on the wire carries; the
  /// saved-feeds array is a list of plain objects with the item type, not the
  /// `savedFeedsPrefV2` discriminant.
  public var prefObject: PrefObject {
    PrefObject(fields: [
      "id": JSONValue(id),
      "type": JSONValue(type),
      "value": JSONValue(value),
      "pinned": JSONValue(isPinned),
    ])
  }

  /// The type RN infers for a value, so a new item gets the right one.
  public static func type(forValue value: String) -> String? {
    SavedFeeds.type(forUri: value)
  }
}

/// The saved-feeds list operations, ported from `screens/SavedFeeds.tsx`.
///
/// RN holds an editing copy of the list in component state, applies every
/// reorder/pin/unpin/remove to that copy, and writes once on "Save changes"
/// with `overwriteSavedFeeds`. This type is that copy plus the ordering rules,
/// so the order the screen shows and the order written back are produced by the
/// same code.
///
/// The list is always kept in "pinned first" order, matching the engine's
/// `pinnedFirst` partition: pinned items keep their relative order and precede
/// the unpinned ones, which also keep theirs.
public struct SavedFeedsEditor: Sendable, Equatable {
  /// The working list, pinned first.
  public private(set) var items: [SavedFeedItem]
  /// The list as loaded from the server, for the dirty check.
  private let original: [SavedFeedItem]

  /// Creates an editor from the current saved feeds.
  public init(items: [SavedFeedItem]) {
    self.original = items
    self.items = SavedFeedsEditor.pinnedFirst(items)
  }

  /// Creates an editor from the raw preference records.
  public init(prefs: [PrefObject]) {
    self.init(items: prefs.compactMap(SavedFeedItem.init(pref:)))
  }

  /// The pinned items, in order.
  public var pinned: [SavedFeedItem] {
    items.filter(\.isPinned)
  }

  /// The unpinned items, in order.
  public var unpinned: [SavedFeedItem] {
    items.filter { !$0.isPinned }
  }

  /// Whether the list differs from what was loaded, which is RN's
  /// `hasUnsavedChanges`.
  public var hasUnsavedChanges: Bool {
    items != original
  }

  /// Whether the account has no saved feeds of any type, which RN uses to
  /// offer the recommended set.
  public var isEmpty: Bool {
    items.isEmpty
  }

  // MARK: - Mutations

  /// Toggles an item's pin. Pinning moves it into the pinned block; unpinning
  /// moves it into the unpinned block. Both preserve the other items' order.
  public mutating func togglePinned(id: String) {
    guard let index = items.firstIndex(where: { $0.id == id }) else { return }
    items[index].isPinned.toggle()
    items = SavedFeedsEditor.pinnedFirst(items)
  }

  /// Removes an item. Only unpinned items are removable in the RN screen; the
  /// guard is reproduced so a pinned feed cannot be dropped silently.
  ///
  /// - Returns: whether the item was removed.
  @discardableResult
  public mutating func remove(id: String) -> Bool {
    guard let index = items.firstIndex(where: { $0.id == id }) else { return false }
    guard !items[index].isPinned else { return false }
    items.remove(at: index)
    return true
  }

  /// Moves a pinned item one position earlier. The first pinned item cannot
  /// move up, matching the disabled button.
  ///
  /// - Parameter index: the index into the pinned sublist.
  /// - Returns: whether the list changed.
  @discardableResult
  public mutating func movePinnedUp(at index: Int) -> Bool {
    movePinned(from: index, to: index - 1)
  }

  /// Moves a pinned item one position later.
  ///
  /// - Parameter index: the index into the pinned sublist.
  /// - Returns: whether the list changed.
  @discardableResult
  public mutating func movePinnedDown(at index: Int) -> Bool {
    movePinned(from: index, to: index + 1)
  }

  /// Replaces the pinned block with a new order, the drag-and-drop path.
  ///
  /// - Returns: whether the list changed.
  @discardableResult
  public mutating func reorderPinned(_ reordered: [SavedFeedItem]) -> Bool {
    let allowed = Set(pinned.map(\.id))
    guard reordered.count == allowed.count,
      reordered.allSatisfy({ allowed.contains($0.id) })
    else { return false }
    let previous = items
    items = SavedFeedsEditor.pinnedFirst(reordered + unpinned)
    return items != previous
  }

  /// Resets the working list to what was loaded.
  public mutating func discardChanges() {
    items = original
  }

  /// Appends items, as RN's "add recommended feeds" does.
  public mutating func append(_ newItems: [SavedFeedItem]) {
    guard !newItems.isEmpty else { return }
    items = SavedFeedsEditor.pinnedFirst(items + newItems)
  }

  private mutating func movePinned(from index: Int, to target: Int) -> Bool {
    var pinnedItems = pinned
    guard pinnedItems.indices.contains(index), pinnedItems.indices.contains(target)
    else { return false }
    pinnedItems.swapAt(index, target)
    return reorderPinned(pinnedItems)
  }

  /// Stable partition: pinned items keep their order and precede unpinned
  /// items, which also keep theirs. Mirrors the engine's `pinnedFirst`.
  public static func pinnedFirst(_ items: [SavedFeedItem]) -> [SavedFeedItem] {
    items.filter(\.isPinned) + items.filter { !$0.isPinned }
  }

  /// The recommeded set RN offers when the list is empty, from
  /// `RECOMMENDED_SAVED_FEEDS`.
  ///
  /// RN mints fresh ids for these (`TID.nextStr()`); the caller-supplied id
  /// generator keeps that testable.
  public static func recommendedItems(
    discoverFeedURI: String = SettingsConstants.discoverFeedURI,
    makeID: () -> String
  ) -> [SavedFeedItem] {
    [
      SavedFeedItem(
        id: makeID(), type: "feed", value: discoverFeedURI, isPinned: true),
      SavedFeedItem(id: makeID(), type: "timeline", value: "following", isPinned: true),
    ]
  }
}

extension SettingsConstants {
  /// `DISCOVER_SAVED_FEED`'s value from `lib/constants.ts`.
  public static let discoverFeedURI =
    "at://did:plc:z72i7hdynmk6r22z27h6tvur/app.bsky.feed.generator/whats-hot"
}
