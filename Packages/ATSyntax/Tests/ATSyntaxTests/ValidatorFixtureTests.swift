import Testing
import Foundation
@testable import ATSyntax

/// Loads interop fixture lines (from the atproto repo's
/// interop-test-files/syntax/*.txt): `#` comments and blank lines skipped.
func fixtureLines(_ name: String) throws -> [String] {
  // .copy resources land in the module bundle root: "Fixtures/<name>.txt"
  // becomes "<name>.txt" on some platforms; probe both layouts.
  let candidates = [
    Bundle.module.url(forResource: "Fixtures/\(name)", withExtension: "txt"),
    Bundle.module.url(forResource: name, withExtension: "txt"),
  ]
  guard let url = candidates.compactMap({ $0 }).first else {
    throw ATSyntaxError("missing fixture resource: \(name).txt")
  }
  let text = try String(contentsOf: url, encoding: .utf8)
  // NOTE: no whitespace trimming — several fixtures test leading/trailing
  // spaces as invalid inputs. Only comments and empty lines are skipped.
  return text
    .split(separator: "\n", omittingEmptySubsequences: false)
    .filter { line in
      let l = line.hasPrefix("#")
      return !l && !line.isEmpty
    }
    .map { line in String(line) }
}

@Suite struct NSIDTests {
  @Test func validNsidFixtures() throws {
    let lines = try fixtureLines("nsid_valid")
    #expect(lines.count == 25)
    for line in lines {
      #expect(ATSyntax.isValidNsid(line), "expected valid: \(line)")
      let nsid = try Nsid(line)
      #expect(nsid.rawValue == line)
    }
  }

  @Test func invalidNsidFixtures() throws {
    let lines = try fixtureLines("nsid_invalid")
    #expect(lines.count == 27)
    for line in lines {
      #expect(!ATSyntax.isValidNsid(line), "expected invalid: \(line)")
    }
  }

  @Test func segments() throws {
    let nsid = try Nsid("com.example.foo")
    #expect(nsid.authority == "com.example")
    #expect(nsid.name == "foo")
    #expect(nsid.segments == ["com", "example", "foo"])
  }
}

@Suite struct DidTests {
  @Test func validDidFixtures() throws {
    let lines = try fixtureLines("did_valid")
    #expect(lines.count == 24)
    for line in lines {
      #expect(ATSyntax.isValidDid(line), "expected valid: \(line)")
    }
  }

  @Test func invalidDidFixtures() throws {
    let lines = try fixtureLines("did_invalid")
    #expect(lines.count == 18)
    for line in lines {
      #expect(!ATSyntax.isValidDid(line), "expected invalid: \(line)")
    }
  }

  @Test func methodExtraction() throws {
    #expect(try Did("did:plc:abcdef").method == "plc")
    #expect(try Did("did:web:example.com").method == "web")
  }
}

@Suite struct HandleTests {
  @Test func validHandleFixtures() throws {
    let lines = try fixtureLines("handle_valid")
    #expect(lines.count == 71)
    for line in lines {
      #expect(ATSyntax.isValidHandle(line), "expected valid: \(line)")
    }
  }

  @Test func invalidHandleFixtures() throws {
    let lines = try fixtureLines("handle_invalid")
    #expect(lines.count == 48)
    for line in lines {
      #expect(!ATSyntax.isValidHandle(line), "expected invalid: \(line)")
    }
  }

  @Test func normalization() throws {
    #expect(try Handle("ALICE.Example").normalized == "alice.example")
  }
}

@Suite struct RecordKeyTests {
  @Test func validRecordKeyFixtures() throws {
    for line in try fixtureLines("recordkey_valid") {
      #expect(ATSyntax.isValidRecordKey(line), "expected valid: \(line)")
    }
  }

  @Test func invalidRecordKeyFixtures() throws {
    for line in try fixtureLines("recordkey_invalid") {
      #expect(!ATSyntax.isValidRecordKey(line), "expected invalid: \(line)")
    }
  }

  @Test func dotAndDotDotRejected() {
    #expect(!ATSyntax.isValidRecordKey("."))
    #expect(!ATSyntax.isValidRecordKey(".."))
  }
}

@Suite struct AtIdentifierTests {
  @Test func validAtIdentifierFixtures() throws {
    for line in try fixtureLines("atidentifier_valid") {
      let id = try AtIdentifier(line)
      #expect(id.description == line)
    }
  }

  @Test func invalidAtIdentifierFixtures() throws {
    for line in try fixtureLines("atidentifier_invalid") {
      #expect(throws: ATSyntaxError.self) {
        _ = try AtIdentifier(line)
      }
    }
  }

  @Test func discriminatedAccess() throws {
    let did = try AtIdentifier("did:plc:abcdef")
    #expect(did.did != nil)
    #expect(did.handle == nil)
    let handle = try AtIdentifier("alice.example")
    #expect(handle.handle != nil)
    #expect(handle.did == nil)
  }
}

@Suite struct TidTests {
  @Test func validTidFixtures() throws {
    for line in try fixtureLines("tid_valid") {
      #expect(ATSyntax.isValidTid(line), "expected valid: \(line)")
    }
  }

  @Test func invalidTidFixtures() throws {
    for line in try fixtureLines("tid_invalid") {
      #expect(!ATSyntax.isValidTid(line), "expected invalid: \(line)")
    }
  }
}
