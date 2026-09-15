import Foundation
import MessagesLogic
import SwiftUI

/// Date separators for the conversation list.
///
/// The RN list groups messages by day and inserts a separator chip; this port
/// derives the same day boundary and the copy for it. The formatting itself goes
/// through `Date.FormatStyle`, which is the native counterpart of RN's
/// `TimeElapsed`/`formatDate` pair.
public enum MessageDateSeparator {
  /// The day a message belongs to, for grouping.
  public static func day(of date: Date, calendar: Calendar = .current) -> Date {
    calendar.startOfDay(for: date)
  }

  /// The label for a separator, e.g. "Today", "Yesterday", or a medium date.
  public static func label(for date: Date, now: Date = Date(), calendar: Calendar = .current) -> String {
    if calendar.isDate(date, inSameDayAs: now) { return MessagesCopy.today }
    if let yesterday = calendar.date(byAdding: .day, value: -1, to: now),
      calendar.isDate(date, inSameDayAs: yesterday) {
      return MessagesCopy.yesterday
    }
    return date.formatted(Date.FormatStyle(date: .abbreviated, time: .omitted))
  }

  /// The relative time shown on an inbox row (or a short clock time for today).
  public static func relativeLabel(
    for date: Date, now: Date = Date(), calendar: Calendar = .current,
    locale: Locale = .current
  ) -> String {
    if calendar.isDate(date, inSameDayAs: now) {
      return date.formatted(Date.FormatStyle(date: .omitted, time: .shortened))
    }
    let days = calendar.dateComponents([.day], from: day(of: date, calendar: calendar), to: day(of: now, calendar: calendar)).day ?? 0
    if days < 7 {
      return date.formatted(.dateTime.weekday(.abbreviated))
    }
    return date.formatted(Date.FormatStyle(date: .numeric, time: .omitted))
  }
}

/// The grouping the conversation list renders.
///
/// The items arrive in display order (oldest first, pending last); this splits
/// them at day boundaries and inserts a separator row, which is what the RN
/// `MessageList` does with `DateSeparator`.
public enum ConversationRow: Identifiable, Sendable {
  /// A date separator.
  case separator(id: String, label: String)
  /// A message row.
  case item(ConvoItem)

  public var id: String {
    switch self {
    case .separator(let id, _): "sep-\(id)"
    case .item(let item): "item-\(item.key)"
    }
  }

  /// Builds the rows from the model's items, inserting a separator when the
  /// calendar day changes. The first item always gets a separator, matching RN.
  static func build(_ items: [ConvoItem], calendar: Calendar = .current, now: Date = Date()) -> [ConversationRow] {
    var rows: [ConversationRow] = []
    var lastDay: Date?
    for item in items {
      guard let date = date(of: item) else {
        rows.append(.item(item))
        continue
      }
      let itemDay = MessageDateSeparator.day(of: date, calendar: calendar)
      if lastDay != itemDay {
        rows.append(
          .separator(id: isoDay(itemDay), label: MessageDateSeparator.label(
            for: date, now: now, calendar: calendar)))
        lastDay = itemDay
      }
      rows.append(.item(item))
    }
    return rows
  }

  /// The timestamp an item carries, when it has one.
  static func date(of item: ConvoItem) -> Date? {
    switch item {
    case .message(let view): MessagesDate.date(from: view.sentAt.rawValue)
    case .deletedMessage(let view): MessagesDate.date(from: view.sentAt.rawValue)
    case .systemMessage(let view): MessagesDate.date(from: view.sentAt.rawValue)
    case .pendingMessage, .error: nil
    }
  }

  private static func isoDay(_ date: Date) -> String {
    let formatter = ISO8601DateFormatter()
    formatter.formatOptions = [.withFullDate]
    return formatter.string(from: date)
  }
}

/// The send state a bubble renders for one outbox entry.
///
/// Mirrors the RN `MessageItem` treatment: a pending message shows as sending, a
/// failed one dims and offers a retry rather than disappearing.
enum MessageSendState: Sendable, Equatable {
  /// On its way to the server.
  case pending
  /// The send failed; retry is available.
  case failed
  /// Server-acknowledged (or someone else's message).
  case sent
}
