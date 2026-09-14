import Foundation
@testable import Moderation

/// A faithful re-implementation of the golden generator's `projectCause`: only
/// the fields the generator emits are produced, so equality against the
/// fixture is exact.
struct GoldenCause: Codable, Equatable, Sendable {
  var type: String
  var source: GoldenSource
  var priority: Int
  var downgraded: Bool?
  var target: String?
  var setting: String?
  var label: GoldenLabel?
  var labelDefIdentifier: String?
  var noOverride: Bool?

  init(from decoder: Decoder) throws {
    let c = try decoder.container(keyedBy: CodingKeys.self)
    type = try c.decode(String.self, forKey: .type)
    source = try c.decode(GoldenSource.self, forKey: .source)
    priority = try c.decode(Int.self, forKey: .priority)
    downgraded = try c.decodeIfPresent(Bool.self, forKey: .downgraded)
    target = try c.decodeIfPresent(String.self, forKey: .target)
    setting = try c.decodeIfPresent(String.self, forKey: .setting)
    label = try c.decodeIfPresent(GoldenLabel.self, forKey: .label)
    labelDefIdentifier = try c.decodeIfPresent(String.self, forKey: .labelDefIdentifier)
    noOverride = try c.decodeIfPresent(Bool.self, forKey: .noOverride)
  }

  init(
    type: String,
    source: GoldenSource,
    priority: Int,
    downgraded: Bool? = nil,
    target: String? = nil,
    setting: String? = nil,
    label: GoldenLabel? = nil,
    labelDefIdentifier: String? = nil,
    noOverride: Bool? = nil
  ) {
    self.type = type
    self.source = source
    self.priority = priority
    self.downgraded = downgraded
    self.target = target
    self.setting = setting
    self.label = label
    self.labelDefIdentifier = labelDefIdentifier
    self.noOverride = noOverride
  }
}

/// The cause source as the generator serializes it.
struct GoldenSource: Codable, Equatable, Sendable {
  var type: String
  var did: String?
  var list: ListViewBasic?
}

/// The label subset the generator projects.
struct GoldenLabel: Codable, Equatable, Sendable {
  var ver: Int?
  var src: String
  var uri: String
  var val: String
}

/// One UI context's projection.
struct GoldenUI: Codable, Equatable, Sendable {
  var noOverride: Bool
  var filter: Bool
  var blur: Bool
  var alert: Bool
  var inform: Bool
  var filters: [GoldenCause]
  var blurs: [GoldenCause]
  var alerts: [GoldenCause]
  var informs: [GoldenCause]

  init(from decoder: Decoder) throws {
    let c = try decoder.container(keyedBy: CodingKeys.self)
    noOverride = try c.decode(Bool.self, forKey: .noOverride)
    filter = try c.decode(Bool.self, forKey: .filter)
    blur = try c.decode(Bool.self, forKey: .blur)
    alert = try c.decode(Bool.self, forKey: .alert)
    inform = try c.decode(Bool.self, forKey: .inform)
    filters = try c.decodeIfPresent([GoldenCause].self, forKey: .filters) ?? []
    blurs = try c.decodeIfPresent([GoldenCause].self, forKey: .blurs) ?? []
    alerts = try c.decodeIfPresent([GoldenCause].self, forKey: .alerts) ?? []
    informs = try c.decodeIfPresent([GoldenCause].self, forKey: .informs) ?? []
  }

  init(
    noOverride: Bool,
    filter: Bool,
    blur: Bool,
    alert: Bool,
    inform: Bool,
    filters: [GoldenCause],
    blurs: [GoldenCause],
    alerts: [GoldenCause],
    informs: [GoldenCause]
  ) {
    self.noOverride = noOverride
    self.filter = filter
    self.blur = blur
    self.alert = alert
    self.inform = inform
    self.filters = filters
    self.blurs = blurs
    self.alerts = alerts
    self.informs = informs
  }
}

/// A full decision projection, matching `projectDecision`.
struct GoldenDecision: Codable, Equatable, Sendable {
  var blocked: Bool
  var muted: Bool
  var causes: [GoldenCause]
  var ui: [String: GoldenUI]
}

/// The expected side of a case: either a single decision, or the before/after
/// pair for the downgrade case.
struct GoldenExpected: Decodable, Sendable {
  var single: GoldenDecision?
  var before: GoldenDecision?
  var afterDowngrade: GoldenDecision?

  private enum CodingKeys: String, CodingKey {
    case blocked
    case before
    case afterDowngrade
  }

  init(from decoder: Decoder) throws {
    let c = try decoder.container(keyedBy: CodingKeys.self)
    if c.contains(.before) {
      before = try c.decode(GoldenDecision.self, forKey: .before)
      afterDowngrade = try c.decode(GoldenDecision.self, forKey: .afterDowngrade)
      single = nil
    } else {
      single = try GoldenDecision(from: decoder)
      before = nil
      afterDowngrade = nil
    }
  }
}

/// A case's input, with the engine call resolved from its `fn` discriminator.
///
/// The subject is kept in a local of each `init` and captured by value into the
/// returned ``Subject``, avoiding any capture of `self` during initialization.
struct GoldenInput: Decodable, Sendable {
  enum Subject: Sendable {
    case post(PostView)
    case profile(ProfileViewBasic)
    case userList(ListView)
    case feedGenerator(FeedGeneratorView)
    case notification(NotificationView)
    case status(StatusView)

    func decide(opts: ModerationOpts) -> ModerationDecision {
      switch self {
      case .post(let subject): return moderatePost(subject, opts: opts)
      case .profile(let subject): return moderateProfile(subject, opts: opts)
      case .userList(let subject): return moderateUserList(subject, opts: opts)
      case .feedGenerator(let subject): return moderateFeedGenerator(subject, opts: opts)
      case .notification(let subject): return moderateNotification(subject, opts: opts)
      case .status(let subject): return moderateStatus(subject, opts: opts)
      }
    }
  }

  let fn: String
  let opts: ModerationOpts
  let subject: Subject

  private enum CodingKeys: String, CodingKey {
    case fn
    case subject
    case opts
  }

  init(from decoder: Decoder) throws {
    let c = try decoder.container(keyedBy: CodingKeys.self)
    let fn = try c.decode(String.self, forKey: .fn)
    let opts = try c.decode(ModerationOpts.self, forKey: .opts)
    let subject: Subject
    switch fn {
    case "moderatePost":
      subject = .post(try c.decode(PostView.self, forKey: .subject))
    case "moderateProfile":
      subject = .profile(try c.decode(ProfileViewBasic.self, forKey: .subject))
    case "moderateUserList":
      subject = .userList(try c.decode(ListView.self, forKey: .subject))
    case "moderateFeedGenerator":
      subject = .feedGenerator(try c.decode(FeedGeneratorView.self, forKey: .subject))
    case "moderateNotification":
      subject = .notification(try c.decode(NotificationView.self, forKey: .subject))
    case "moderateStatus":
      subject = .status(try c.decode(StatusView.self, forKey: .subject))
    default:
      throw DecodingError.dataCorruptedError(
        forKey: .fn,
        in: c,
        debugDescription: "unknown engine fn: \(fn)"
      )
    }
    self.fn = fn
    self.opts = opts
    self.subject = subject
  }

  func makeDecision() -> ModerationDecision {
    subject.decide(opts: opts)
  }
}

/// One golden case.
struct GoldenCase: Decodable, Sendable {
  let name: String
  let input: GoldenInput
  let expected: GoldenExpected
}

/// The golden document.
struct GoldenDocument: Decodable, Sendable {
  let version: Int
  let generator: String
  let cases: [GoldenCase]
}

/// The eight UI contexts, in the generator's fixed order.
let goldenUIContexts = ModerationContext.allCases

/// Projects a cause the way `projectCause` does. The generator's `matches`
/// branch is keyed on `muted-word` while the engine emits `mute-word`, so it is
/// dead code and never contributes to the golden output; matches are therefore
/// intentionally not projected here.
func projectCause(_ cause: ModerationCause) -> GoldenCause {
  let source: GoldenSource =
    switch cause.source {
    case .user: GoldenSource(type: "user", did: nil, list: nil)
    case .labeler(let did): GoldenSource(type: "labeler", did: did, list: nil)
    case .list(let list): GoldenSource(type: "list", did: nil, list: list)
    }
  guard cause.type == .label else {
    return GoldenCause(
      type: cause.type.rawValue,
      source: source,
      priority: cause.priority,
      downgraded: cause.downgraded
    )
  }
  let label = cause.label.map {
    GoldenLabel(ver: $0.ver, src: $0.src, uri: $0.uri, val: $0.val)
  }
  return GoldenCause(
    type: cause.type.rawValue,
    source: source,
    priority: cause.priority,
    downgraded: cause.downgraded,
    target: cause.target?.rawValue,
    setting: cause.setting?.rawValue,
    label: label,
    labelDefIdentifier: cause.labelDef?.identifier,
    noOverride: cause.noOverride
  )
}

/// Projects a full decision, including every UI context.
func projectDecision(_ decision: ModerationDecision) -> GoldenDecision {
  var ui: [String: GoldenUI] = [:]
  for context in goldenUIContexts {
    let contextUI = decision.ui(context)
    ui[context.rawValue] = GoldenUI(
      noOverride: contextUI.noOverride,
      filter: contextUI.filter,
      blur: contextUI.blur,
      alert: contextUI.alert,
      inform: contextUI.inform,
      filters: contextUI.filters.map(projectCause),
      blurs: contextUI.blurs.map(projectCause),
      alerts: contextUI.alerts.map(projectCause),
      informs: contextUI.informs.map(projectCause)
    )
  }
  return GoldenDecision(
    blocked: decision.blocked,
    muted: decision.muted,
    causes: decision.causes.map(projectCause),
    ui: ui
  )
}

/// Resolves the golden fixture path relative to this source file.
func goldenFixtureURL() -> URL {
  var url = URL(fileURLWithPath: #filePath)
  // Tests/ModerationTests/<file> -> Packages/Moderation/Tests/ModerationTests
  url.deleteLastPathComponent()  // ModerationTests
  url.deleteLastPathComponent()  // Tests
  url.deleteLastPathComponent()  // Moderation
  url.deleteLastPathComponent()  // Packages
  return url.appending(path: "TestSupport/Fixtures/Golden/moderation.json")
}
