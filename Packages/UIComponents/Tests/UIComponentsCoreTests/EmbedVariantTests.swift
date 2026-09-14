import Foundation
import Moderation
import Testing

@testable import UIComponentsCore

@Suite("Embed variant dispatch")
struct EmbedVariantTests {
  @Test("images dispatch carries the count and media flag")
  func imagesDispatch() {
    let info = embedVariantInfo(.images([EmbedImage(alt: "a"), EmbedImage(alt: "b")]))
    #expect(info?.variant == .images)
    #expect(info?.imageCount == 2)
    #expect(info?.hasMedia == true)
    #expect(info?.hasQuotedPost == false)
  }

  @Test("gallery dispatch carries the item count")
  func galleryDispatch() {
    let info = embedVariantInfo(.gallery([.image(EmbedImage(alt: "x")), .unknown(type: "z")]))
    #expect(info?.variant == .gallery)
    #expect(info?.imageCount == 2)
    #expect(info?.hasMedia == true)
  }

  @Test("external dispatch has media but no images")
  func externalDispatch() {
    let info = embedVariantInfo(.external(EmbedExternal(uri: "https://example.com")))
    #expect(info?.variant == .external)
    #expect(info?.imageCount == 0)
    #expect(info?.hasMedia == true)
  }

  @Test("a quote with a hydrated record reports hasQuotedPost; a blocked one does not")
  func quoteDispatch() {
    let quote = embedVariantInfo(EmbedFixtures.quote(text: "hi"))
    #expect(quote?.variant == .record)
    #expect(quote?.hasQuotedPost == true)

    let blocked = embedVariantInfo(EmbedFixtures.blockedQuote())
    #expect(blocked?.variant == .record)
    #expect(blocked?.hasQuotedPost == false)
    #expect(blocked?.hasMedia == false)

    let notFound = embedVariantInfo(EmbedFixtures.notFoundQuote())
    #expect(notFound?.variant == .record)
    #expect(notFound?.hasQuotedPost == false)
  }

  @Test("recordWithMedia reports both the media and the quote")
  func recordWithMediaDispatch() {
    let info = embedVariantInfo(EmbedFixtures.recordWithMedia(imageCount: 1))
    #expect(info?.variant == .recordWithMedia)
    #expect(info?.hasMedia == true)
    #expect(info?.hasQuotedPost == true)
    #expect(info?.imageCount == 1)
    #expect(info?.isVideo == false)
  }

  @Test("an unknown embed is unsupported, and no embed is nil")
  func unknownAndNil() {
    #expect(embedVariantInfo(.unknown(type: "app.bsky.embed.weird"))?.variant == .unsupported)
    #expect(embedVariantInfo(nil) == nil)
  }

  @Test("Gallery layout picks by count")
  func galleryLayout() {
    #expect(ImageGalleryLayout.forImageCount(0) == .single)
    #expect(ImageGalleryLayout.forImageCount(1) == .single)
    #expect(ImageGalleryLayout.forImageCount(2) == .twoUp)
    #expect(ImageGalleryLayout.forImageCount(3) == .threeUp)
    #expect(ImageGalleryLayout.forImageCount(4) == .grid)
    #expect(ImageGalleryLayout.forImageCount(7) == .grid)
  }

  @Test("A layout drops images beyond its cell count")
  func galleryTruncation() {
    let four = EmbedFixtures.images(4)
    #expect(galleryImages(four, layout: .twoUp).count == 2)
    #expect(galleryImages(four, layout: .grid).count == 4)
    #expect(galleryImages([], layout: .grid).isEmpty)
  }

  @Test("Gallery items unwrap to their images, dropping unknown variants")
  func galleryItemUnwrap() {
    let items: [EmbedGalleryItem] = [
      .image(EmbedImage(alt: "a", image: "https://cdn.example/a.jpg")),
      .unknown(type: "app.bsky.embed.gallery#video"),
      .image(EmbedImage(alt: "b")),
    ]
    let images = galleryImages(items)
    #expect(images.count == 2)
    #expect(images.first?.alt == "a")
    #expect(images.last?.alt == "b")
    #expect(galleryImages([EmbedGalleryItem]()).isEmpty)
    #expect(galleryImages([.unknown(type: "x")]).isEmpty)
  }

  @Test("The layout follows the images that survive unwrapping")
  func galleryLayoutAfterUnwrap() {
    let items: [EmbedGalleryItem] = [
      .image(EmbedImage(alt: "a")),
      .unknown(type: "unknown"),
    ]
    let images = galleryImages(items)
    #expect(ImageGalleryLayout.forImageCount(images.count) == .single)
  }

  @Test("Embed image URLs require a non-empty string")
  func imageURLs() {
    #expect(embedImageURL(EmbedImage(alt: "a", image: nil)) == nil)
    #expect(embedImageURL(EmbedImage(alt: "a", image: "")) == nil)
    #expect(
      embedImageURL(EmbedImage(alt: "a", image: "https://cdn.example/x.jpg"))
        == URL(string: "https://cdn.example/x.jpg"))
  }
}

@Suite("Embed fixtures")
struct EmbedFixtureTests {
  @Test("The quote fixture decodes on the real path")
  func quote() {
    guard let embed = EmbedFixtures.quote(text: "hello there") else {
      Issue.record("fixture failed to decode")
      return
    }
    #expect(embed.recordView?.record?.viewRecord?.value?.text == "hello there")
    #expect(embed.recordView?.record?.viewRecord?.author?.handle == "bob.bsky.social")
  }

  @Test("The blocked and not-found fixtures decode to their union cases")
  func unhydrated() {
    #expect(EmbedFixtures.blockedQuote()?.recordView?.record?.viewBlocked != nil)
    if case .viewNotFound = EmbedFixtures.notFoundQuote()?.recordView?.record {} else {
      Issue.record("expected viewNotFound")
    }
  }

  @Test("The recordWithMedia fixture carries both halves")
  func recordWithMedia() {
    guard case .recordWithMedia(let value)? = EmbedFixtures.recordWithMedia(imageCount: 2) else {
      Issue.record("fixture failed to decode")
      return
    }
    #expect(value.record?.record?.viewRecord?.value?.text == "Quoted post with media.")
    if case .images(let images)? = value.media {
      #expect(images.count == 2)
    } else {
      Issue.record("expected images media")
    }
  }

  @Test("Malformed JSON decodes to nil rather than trapping")
  func malformed() {
    #expect(EmbedFixtures.embed(json: "not json") == nil)
  }
}
