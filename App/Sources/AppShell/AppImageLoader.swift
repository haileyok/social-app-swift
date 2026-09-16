import Foundation
import UIComponents
import UIComponentsCore

/**
 The app's image loader: URLSession bytes with an in-memory cache.

 The component library ships a placeholder loader that never produces bytes so
 galleries render without wiring; the app installs this at both roots instead.
 Caching is memory-only for now (an `NSCache` of raw bytes, decoded per view by
 `RemoteImage`), which is enough for feed scrolling: the cache absorbs
 re-renders and back-navigation, and eviction is automatic under memory
 pressure.
 */
actor AppImageLoader: ImageLoading {

  /// Shared: one session, one cache, for every image in the app.
  static let shared = AppImageLoader()

  private let session: URLSession
  private let cache = NSCache<NSURL, NSData>()
  private var inFlight: [URL: Task<Data, Error>] = [:]

  init(session: URLSession = .shared) {
    self.session = session
    cache.countLimit = 600
  }

  func loadImage(at url: URL, targetSize: ImageTargetSize?) async throws -> Data {
    if let cached = cache.object(forKey: url as NSURL) {
      return cached as Data
    }
    if let existing = inFlight[url] {
      return try await existing.value
    }

    let session = session
    let task = Task<Data, Error> {
      let (data, response) = try await session.data(from: url)
      guard let http = response as? HTTPURLResponse, 200..<300 ~= http.statusCode,
        !data.isEmpty
      else { throw ImageLoaderError.undecodable }
      return data
    }
    inFlight[url] = task
    defer { inFlight[url] = nil }
    let data = try await task.value
    cache.setObject(data as NSData, forKey: url as NSURL)
    return data
  }

  func prefetch(_ urls: [URL], targetSize: ImageTargetSize?) async {
    await withTaskGroup(of: Void.self) { group in
      for url in Array(Set(urls)).prefix(24) {
        group.addTask { [weak self] in
          _ = try? await self?.loadImage(at: url, targetSize: targetSize)
        }
      }
    }
  }
}
