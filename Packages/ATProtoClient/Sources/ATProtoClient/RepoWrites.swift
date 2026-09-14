import Foundation

extension XrpcClient {

  /// `com.atproto.repo.uploadBlob` — multipart body with raw bytes.
  public func uploadBlob(
    _ data: Data, mimeType: String, encoding: String = "*/*",
    authorization: String? = nil
  ) async throws -> BlobUploadResponse {
    let boundary = "Boundary-\(UUID().uuidString)"
    var body = Data()
    body.append(contentsOf: Array("--\(boundary)\r\n".utf8))
    body.append(
      contentsOf: Array(
        "Content-Disposition: form-data; name=\"blob\"; filename=\"blob\"\r\n"
          .utf8))
    body.append(contentsOf: Array("Content-Type: \(mimeType)\r\n\r\n".utf8))
    body.append(data)
    body.append(contentsOf: Array("\r\n--\(boundary)--\r\n".utf8))

    let response = try await rawPost(
      "com.atproto.repo.uploadBlob", body: body,
      contentType: "multipart/form-data; boundary=\(boundary)",
      authorization: authorization)
    return try Self.decode(response)
  }

  public struct BlobUploadResponse: Decodable, Sendable {
    public let blob: BlobRef
  }

  public struct BlobRef: Decodable, Sendable {
    public let type: String?
    public let ref: BlobRefLink?
    public let mimeType: String?
    public let size: Int?
  }

  public struct BlobRefLink: Decodable, Sendable {
    public let link: String?
  }

  public struct CreateRecordBody<Input: Encodable & Sendable>: Encodable, Sendable {
    public var repo: String
    public var collection: String
    public var record: Input
    public var rkey: String?
    public var swapCommit: String?

    public init(
      repo: String, collection: String, record: Input, rkey: String? = nil,
      swapCommit: String? = nil
    ) {
      self.repo = repo
      self.collection = collection
      self.record = record
      self.rkey = rkey
      self.swapCommit = swapCommit
    }
  }

  public struct RecordRef: Decodable, Sendable {
    public let uri: String
    public let cid: String?
  }

  /// `com.atproto.repo.createRecord`.
  public func createRecord<Input: Encodable & Sendable>(
    repo: String, collection: String, record: Input, rkey: String? = nil,
    authorization: String? = nil
  ) async throws -> RecordRef {
    try await procedure(
      "com.atproto.repo.createRecord",
      body: CreateRecordBody(
        repo: repo, collection: collection, record: record, rkey: rkey),
      authorization: authorization)
  }

  public struct PutRecordBody<Input: Encodable & Sendable>: Encodable, Sendable {
    public var repo: String
    public var collection: String
    public var rkey: String
    public var record: Input
    public var swapRecord: String?
    public var swapCommit: String?

    public init(
      repo: String, collection: String, rkey: String, record: Input,
      swapRecord: String? = nil, swapCommit: String? = nil
    ) {
      self.repo = repo
      self.collection = collection
      self.rkey = rkey
      self.record = record
      self.swapRecord = swapRecord
      self.swapCommit = swapCommit
    }
  }

  /// `com.atproto.repo.putRecord`.
  public func putRecord<Input: Encodable & Sendable>(
    repo: String, collection: String, rkey: String, record: Input,
    swapRecord: String? = nil, authorization: String? = nil
  ) async throws -> RecordRef {
    try await procedure(
      "com.atproto.repo.putRecord",
      body: PutRecordBody(
        repo: repo, collection: collection, rkey: rkey, record: record,
        swapRecord: swapRecord),
      authorization: authorization)
  }

  public struct DeleteRecordBody: Encodable, Sendable {
    public var repo: String
    public var collection: String
    public var rkey: String
    public var swapRecord: String?
    public var swapCommit: String?

    public init(
      repo: String, collection: String, rkey: String, swapRecord: String? = nil,
      swapCommit: String? = nil
    ) {
      self.repo = repo
      self.collection = collection
      self.rkey = rkey
      self.swapRecord = swapRecord
      self.swapCommit = swapCommit
    }
  }

  /// `com.atproto.repo.deleteRecord`.
  public func deleteRecord(
    repo: String, collection: String, rkey: String,
    authorization: String? = nil
  ) async throws -> PasswordSession.EmptyBody {
    try await procedure(
      "com.atproto.repo.deleteRecord",
      body: DeleteRecordBody(repo: repo, collection: collection, rkey: rkey),
      authorization: authorization)
  }
}
