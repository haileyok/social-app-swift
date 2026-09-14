/**
 A colour parsed from a CSS hex string, with components in the `0...1` range.

 Every value ALF hands the RN app is a hex string: palette entries are six
 digits (`#RRGGBB`) and shadow colours append two alpha digits (`#RRGGBBAA`).
 Parsing lives in this SwiftUI-free target so it is verifiable on Linux; the
 SwiftUI layer only ever receives already-validated components.
 */
public struct HexColor: Equatable, Sendable {
  public let red: Double
  public let green: Double
  public let blue: Double
  public let alpha: Double

  public init(red: Double, green: Double, blue: Double, alpha: Double = 1) {
    self.red = red
    self.green = green
    self.blue = blue
    self.alpha = alpha
  }

  /**
   Parses `#RRGGBB` or `#RRGGBBAA`. The leading `#` is optional; both cases are
   accepted. Returns `nil` for any other length or a non-hex character.
   */
  public init?(hex: String) {
    var digits = hex
    if digits.hasPrefix("#") {
      digits.removeFirst()
    }
    guard digits.count == 6 || digits.count == 8 else { return nil }
    guard digits.allSatisfy({ $0.isASCII && $0.isHexDigit }) else { return nil }
    guard let value = UInt32(digits, radix: 16) else { return nil }

    if digits.count == 6 {
      self.init(
        red: Double((value >> 16) & 0xFF) / 255,
        green: Double((value >> 8) & 0xFF) / 255,
        blue: Double(value & 0xFF) / 255,
        alpha: 1)
    } else {
      self.init(
        red: Double((value >> 24) & 0xFF) / 255,
        green: Double((value >> 16) & 0xFF) / 255,
        blue: Double((value >> 8) & 0xFF) / 255,
        alpha: Double(value & 0xFF) / 255)
    }
  }
}
