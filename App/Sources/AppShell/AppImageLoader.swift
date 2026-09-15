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
final class AppImageLoader: ImageLoading, @unchecked Sendable {

  /// Shared: one session, one cache, for every image in the app.
  static let shared = AppImageLoader()

  private let session: URLSession
  private let cache = NSCache<NSURL, NSData>()

  init(session: URLSession = .shared) {
    self.session = session
    cache.countLimit = 600
  }

  func loadImage(at url: URL, targetSize: ImageTargetSize?) async throws -> Data {
    if let cached = cache.object(forKey: url as NSURL) {
      return cached as Data
    }
    let (data, response) = try await session.data(from: url)
    guard let http = response as? HTTPURLResponse, 200..<300 ~= http.statusCode else {
      throw ImageLoaderError.undecodable
    }
    guard !data.isEmpty else {
      throw ImageLoaderError.undecodable
    }
    cache.setObject(data as NSData, forKey: url as NSURL)
    return data
  }
}
