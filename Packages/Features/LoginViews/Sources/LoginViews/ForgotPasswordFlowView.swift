import DesignSystem
import SwiftUI

/// The whole forgot-password journey: request the email, then set a new password.
///
/// The two screens are driven by ``PasswordResetFlow``'s step, so the transition
/// from "request" to "set a new password" is the flow's own transition rather
/// than a view-level navigation decision. That mirrors the RN `Login` screen,
/// which swaps the same two forms on its `Form.SetNewPassword` case.
public struct ForgotPasswordFlowView: View {
  private let viewModel: PasswordResetViewModel
  private let onFinished: () -> Void
  private let onCancel: () -> Void

  public init(
    viewModel: PasswordResetViewModel,
    onFinished: @escaping () -> Void = {},
    onCancel: @escaping () -> Void = {}
  ) {
    self.viewModel = viewModel
    self.onFinished = onFinished
    self.onCancel = onCancel
  }

  public var body: some View {
    Group {
      if viewModel.isSettingNewPassword || viewModel.isComplete {
        SetNewPasswordScreen(viewModel: viewModel, onDone: onFinished)
      } else {
        ForgotPasswordScreen(viewModel: viewModel, onCancel: onCancel)
      }
    }
    // `enteringNewPassword` is only reachable after the request succeeded, so
    // this transition is exactly the "we emailed you a code" moment.
    .animation(.default, value: viewModel.isSettingNewPassword)
  }
}
