import Testing

@testable import DesignSystemCore

@Suite("HexColor parsing")
struct HexColorTests {
  @Test("parses #RRGGBB")
  func sixDigits() throws {
    let color = try #require(HexColor(hex: "#054CFF"))
    #expect(color.red == 5.0 / 255)
    #expect(color.green == 76.0 / 255)
    #expect(color.blue == 1.0)
    #expect(color.alpha == 1)
  }

  @Test("parses #RRGGBBAA with the alpha byte last")
  func eightDigits() throws {
    let color = try #require(HexColor(hex: "#0000001a"))
    #expect(color.red == 0)
    #expect(color.green == 0)
    #expect(color.blue == 0)
    #expect(color.alpha == 26.0 / 255)
  }

  @Test("accepts lowercase hex and a missing leading #")
  func tolerances() throws {
    let withHash = try #require(HexColor(hex: "#ffffff"))
    let withoutHash = try #require(HexColor(hex: "ffffff"))
    let lower = try #require(HexColor(hex: "#abcdef"))
    #expect(withHash == withoutHash)
    #expect(lower.red == 171.0 / 255)
  }

  @Test(
    "rejects malformed input",
    arguments: ["", "#", "#fff", "#fffff", "#fffffff", "#fffffffff", "#gggggg", " #ffffff"])
  func rejects(_ input: String) {
    #expect(HexColor(hex: input) == nil)
  }

  @Test("the ALF shadow alpha suffixes parse")
  func shadowAlphaSuffixes() throws {
    let light = try #require(HexColor(hex: "#0000001a"))
    let dark = try #require(HexColor(hex: "#00000066"))
    #expect(abs(light.alpha - 0.1) < 0.01)
    #expect(abs(dark.alpha - 0.4) < 0.01)
  }
}
