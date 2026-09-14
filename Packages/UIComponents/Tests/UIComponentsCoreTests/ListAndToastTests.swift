import Foundation
import Testing

@testable import UIComponentsCore

@Suite("List states")
struct ListStateTests {
  @Test("An initial load with no items is loading")
  func loading() {
    #expect(ListState.resolve(itemCount: 0, isInitialLoading: true) == .loading)
  }

  @Test("A settled load with no items is empty, not loading")
  func empty() {
    #expect(ListState.resolve(itemCount: 0, isInitialLoading: false) == .empty)
  }

  @Test("Items are content regardless of the loading flag")
  func content() {
    #expect(ListState.resolve(itemCount: 3, isInitialLoading: true) == .content)
    #expect(ListState.resolve(itemCount: 3, isInitialLoading: false) == .content)
  }

  @Test("An error wins over the empty result")
  func error() {
    let error = ListState.ListErrorState(title: "Nope", message: "Try again")
    #expect(ListState.resolve(itemCount: 0, isInitialLoading: false, error: error) == .error(error))
    #expect(ListState.resolve(itemCount: 5, isInitialLoading: false, error: error) == .error(error))
  }

  @Test("An error with existing content is marked as pagination")
  func paginationError() {
    let error = ListState.ListErrorState(title: "Nope", message: "Try again", hasContent: true)
    #expect(error.hasContent)
  }

  @Test("The failure kinds each carry distinct copy")
  func failureKinds() {
    let messages = Set(ListFailureKind.allCases.map(\.message))
    #expect(messages.count == ListFailureKind.allCases.count)
  }

  @Test("The bundled string sets are non-empty")
  func stringSets() {
    for set in [ListStrings.feed, ListStrings.profile, ListStrings.notifications] {
      #expect(!set.emptyTitle.isEmpty)
      #expect(!set.emptyMessage.isEmpty)
      #expect(!set.errorTitle.isEmpty)
      #expect(!set.errorMessage.isEmpty)
      #expect(!set.retryLabel.isEmpty)
    }
  }

  @Test("The skeleton fills a viewport")
  func skeletonCount() {
    #expect(ListState.skeletonRowCount > 0)
  }
}

@Suite("Toast state")
struct ToastStateTests {
  @Test("An empty state is not presented")
  func empty() {
    let state = ToastState()
    #expect(state.isPresented == false)
    #expect(state.current == nil)
  }

  @Test("Showing a toast presents it")
  func show() {
    var state = ToastState()
    state.show(Toast(message: "hi"))
    #expect(state.isPresented)
    #expect(state.current?.message == "hi")
    #expect(state.queue.isEmpty)
  }

  @Test("A second toast replaces the first and queues it")
  func replacement() {
    var state = ToastState()
    state.show(Toast(message: "first"))
    state.show(Toast(message: "second"))
    #expect(state.current?.message == "second")
    #expect(state.queue.map(\.message) == ["first"])
  }

  @Test("Dismissing promotes the queued toast, then clears")
  func dismissPromotes() {
    var state = ToastState()
    state.show(Toast(message: "first"))
    state.show(Toast(message: "second"))
    state.dismiss()
    #expect(state.current?.message == "first")
    #expect(state.queue.isEmpty)
    state.dismiss()
    #expect(state.current == nil)
    #expect(state.isPresented == false)
  }

  @Test("Clear removes the visible toast and the queue")
  func clear() {
    var state = ToastState()
    state.show(Toast(message: "first"))
    state.show(Toast(message: "second"))
    state.clear()
    #expect(state.current == nil)
    #expect(state.queue.isEmpty)
  }

  @Test("Toast defaults to the neutral kind and a three second life")
  func defaults() {
    let toast = Toast(message: "hi")
    #expect(toast.kind == .neutral)
    #expect(toast.duration == 3)
  }
}
