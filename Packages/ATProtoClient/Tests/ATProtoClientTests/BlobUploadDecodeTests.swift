import Testing
@testable import ATProtoClient

/// Regression tests for blob-upload response decoding.
///
/// Atproto prefixes metadata keys with `$` (`$link`, `$type`); a missing
/// CodingKeys mapping silently decodes those fields as nil. Onboarding's
/// avatar upload caught exactly this for `$link` - these tests pin it.
@Suite struct BlobUploadDecodeTests {

  @Test func decodesDollarLinkWireKey() throws {
    let json = #"""
      {"blob":{"type":"blob","ref":{"$link":"bafkreihdwdcefgh4dqkjv67uzcmw7ojee6xedzdetojuzjevtenxquvyku"},"mimeType":"image/png","size":2048}}
      """#
    let data = Data(json.utf8)
    let decoded = try JSONDecoder().decode(XrpcClient.BlobUploadResponse.self, from: data)
    #expect(decoded.blob.ref?.link == "bafkreihdwdcefgh4dqkjv67uzcmw7ojee6xedzdetojuzjevtenxquvyku")
    #expect(decoded.blob.mimeType == "image/png")
    #expect(decoded.blob.size == 2048)
    #expect(decoded.blob.type == "blob")
  }

  @Test func toleratesMissingRefAndOptionalFields() throws {
    let json = #"{"blob":{}}"#
    let decoded = try JSONDecoder().decode(XrpcClient.BlobUploadResponse.self, from: Data(json.utf8))
    #expect(decoded.blob.ref == nil)
    #expect(decoded.blob.mimeType == nil)
  }
}
