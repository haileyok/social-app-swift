import Foundation

/// A small Public Suffix List implementation used by
/// ``URLHelpers/splitApexDomain(_:)``.
///
/// The rules come from the same PSL data the RN app gets through the npm `psl`
/// package (see `PublicSuffixList.swift`). The matching algorithm follows
/// section 3 of the PSL spec: find the longest matching rule, honour `!`
/// exception rules, and treat `*` as a single-label wildcard.
public enum PublicSuffixList {

  struct Rule {
    let labels: [String]
    let isException: Bool
    let isWildcard: Bool
  }

  /// Rules indexed by their last label, for fast lookup. Parsed once.
  static let parsedRules: [String: [Rule]] = {
    var byLastLabel: [String: [Rule]] = [:]
    for chunk in publicSuffixListRuleChunks {
      for token in chunk.split(separator: " ") {
        let raw = String(token)
        var body = raw
        var isException = false
        if body.hasPrefix("!") {
          isException = true
          body.removeFirst()
        }
        var labels = body.lowercased().split(separator: ".").map(String.init)
        var isWildcard = false
        if let last = labels.last, last == "*" {
          isWildcard = true
          labels.removeLast()
        }
        guard let last = labels.last else { continue }
        byLastLabel[last, default: []].append(
          Rule(labels: labels, isException: isException, isWildcard: isWildcard))
      }
    }
    return byLastLabel
  }()

  /// The registrable domain (public suffix + one label), or `nil` when the
  /// host is not covered by any rule. Mirrors `psl.parse(host).domain`, which
  /// returns `null` for unlisted hosts.
  public static func registrableDomain(of hostname: String) -> String? {
    let host = hostname.lowercased().trimmingCharacters(in: CharacterSet(charactersIn: "."))
    guard !host.isEmpty else { return nil }
    let labels = host.split(separator: ".").map(String.init)
    guard labels.count >= 2 else { return nil }

    // Exception rules take priority; they name the registrable domain directly.
    var bestMatchLength = 0
    var matchedIsException = false

    for start in 0..<labels.count {
      let candidateLabels = Array(labels[start...])
      guard let last = candidateLabels.last, let rules = parsedRules[last] else { continue }
      for rule in rules {
        let ruleLength = rule.labels.count + (rule.isWildcard ? 1 : 0)
        guard ruleLength <= candidateLabels.count else { continue }
        guard ruleLength > bestMatchLength else { continue }
        if matchRule(rule, against: candidateLabels) {
          bestMatchLength = ruleLength
          matchedIsException = rule.isException
        }
      }
    }

    guard bestMatchLength > 0 else { return nil }

    // An exception rule's match length already includes the public suffix; the
    // registrable domain is the suffix plus one prior label.
    let suffixLength = matchedIsException ? bestMatchLength - 1 : bestMatchLength
    let registrableLength = suffixLength + 1
    guard registrableLength <= labels.count else { return nil }
    return labels.suffix(registrableLength).joined(separator: ".")
  }

  /// Whether `rule` matches the leftmost labels of `candidate` (which is a
  /// suffix slice of the full host).
  static func matchRule(_ rule: Rule, against candidate: [String]) -> Bool {
    let ruleLength = rule.labels.count + (rule.isWildcard ? 1 : 0)
    guard ruleLength <= candidate.count else { return false }

    // Rule labels are compared from the right (end of the host).
    let tail = Array(candidate.suffix(ruleLength))
    if rule.isWildcard {
      // `*.` rules match any single label in that position.
      guard tail.count == rule.labels.count + 1 else { return false }
      let fixedTail = Array(tail.dropFirst())
      return fixedTail == rule.labels
    }
    return tail == rule.labels
  }
}
