import DesignSystem
import DesignTokens
import Foundation
import OnboardingLogic
import PhotosUI
import SwiftUI
import UIComponents
import UniformTypeIdentifiers
#if canImport(UIKit)
  import UIKit
#elseif canImport(AppKit)
  import AppKit
#endif

/// The profile step: an avatar picker, a display name, and validation.
///
/// Port of `screens/Onboarding/StepProfile/index.tsx`. RN's profile step only
/// collects an avatar (its photo picker and avatar creator); the display name
/// field is the Swift addition the logic layer's ``ProfileStepResult`` already
/// carries, validated by ``ProfileValidation`` so the two clients agree on the
/// limit.
///
/// The photo library selection is retained by ``OnboardingWizardModel`` and sent
/// through the logic layer's existing avatar upload/profile-write transaction.
public struct ProfileStep: View {
  private let model: OnboardingWizardModel

  @Environment(\.alfTheme) private var theme
  @State private var selectedPhoto: PhotosPickerItem?
  @State private var isLoadingPhoto = false
  @State private var photoError: String?

  /// Creates the step.
  public init(model: OnboardingWizardModel) {
    self.model = model
  }

  public var body: some View {
    VStack(alignment: .leading, spacing: Spacing.lg) {
      OnboardingHeading(
        OnboardingCopy.profileTitle, description: OnboardingCopy.profileDescription)

      avatarPicker

      nameField

      continueButton
    }
    .frame(maxWidth: .infinity, alignment: .leading)
    .accessibilityIdentifier(OnboardingAccessibility.profileStep)
  }

  /// A real photo-library picker with an immediate circular preview.
  private var avatarPicker: some View {
    VStack(spacing: Spacing.md) {
      PhotosPicker(selection: $selectedPhoto, matching: .images) {
        ZStack(alignment: .bottomTrailing) {
          avatarPreview
            .frame(width: 140, height: 140)
            .clipShape(.circle)
            .overlay {
              Circle().strokeBorder(theme.atomColors.borderContrastMedium, lineWidth: 2)
            }
          Image(systemName: "camera.fill")
            .font(.system(size: 16, weight: .semibold))
            .foregroundStyle(theme.atomColors.textInverted)
            .padding(10)
            .background(theme.colors.primary500)
            .clipShape(.circle)
            .overlay { Circle().stroke(theme.atomColors.bg, lineWidth: 3) }
        }
      }
      .buttonStyle(.plain)
      .disabled(isLoadingPhoto || model.isRunning)
      .accessibilityLabel(OnboardingCopy.profileAvatarLabel)

      if isLoadingPhoto {
        ProgressView("Loading photo…")
      } else {
        Text(model.avatarImageData == nil ? OnboardingCopy.profileAvatarAdd : "Choose another photo")
          .font(TypeScale.sm.font(weight: Scales.FontWeight.medium))
          .foregroundStyle(theme.atomColors.textLink)
      }

      if let photoError {
        Text(photoError)
          .font(TypeScale.sm.font())
          .foregroundStyle(theme.colors.negative500)
          .multilineTextAlignment(.center)
      }
    }
    .frame(maxWidth: .infinity)
    .padding(.lg, .vertical)
    .accessibilityIdentifier(OnboardingAccessibility.profileAvatarPicker)
    .onChange(of: selectedPhoto) { _, item in
      Task { await loadPhoto(item) }
    }
  }

  @ViewBuilder private var avatarPreview: some View {
    if let data = model.avatarImageData {
      #if canImport(UIKit)
        if let image = UIImage(data: data) {
          Image(uiImage: image).resizable().scaledToFill()
        } else {
          avatarPlaceholder
        }
      #elseif canImport(AppKit)
        if let image = NSImage(data: data) {
          Image(nsImage: image).resizable().scaledToFill()
        } else {
          avatarPlaceholder
        }
      #endif
    } else {
      avatarPlaceholder
    }
  }

  private var avatarPlaceholder: some View {
    ZStack {
      Circle().fill(theme.atomColors.bgContrast100)
      Image(systemName: "person.crop.circle.fill")
        .font(.system(size: 92))
        .foregroundStyle(theme.atomColors.textContrastMedium)
    }
  }

  private func loadPhoto(_ item: PhotosPickerItem?) async {
    guard let item else { return }
    isLoadingPhoto = true
    photoError = nil
    defer { isLoadingPhoto = false }
    do {
      guard let data = try await item.loadTransferable(type: Data.self), !data.isEmpty else {
        throw PhotoSelectionError.empty
      }
      let mimeType = item.supportedContentTypes.contains(.png) ? "image/png" : "image/jpeg"
      model.setAvatar(imageData: data, mimeType: mimeType)
    } catch is CancellationError {
      return
    } catch {
      selectedPhoto = nil
      photoError = "That photo couldn’t be loaded. Please choose another one."
    }
  }

  private enum PhotoSelectionError: Error { case empty }

  /// The display-name field with its inline validation line.
  private var nameField: some View {
    VStack(alignment: .leading, spacing: Spacing.xs) {
      Text(OnboardingCopy.profileNameLabel)
        .font(TypeScale.sm.font(weight: Scales.FontWeight.medium))
        .foregroundStyle(theme.atomColors.textContrastMedium)

      TextField(OnboardingCopy.profileNamePlaceholder, text: Binding(
        get: { model.displayName },
        set: { model.displayName = $0 }))
        .font(TypeScale.md.font())
        .textFieldStyle(.plain)
        .padding(.md)
        .background(theme.atomColors.bgContrast50)
        .clipShape(.rect(cornerRadius: Radius.sm))
        .overlay {
          RoundedRectangle(cornerRadius: Radius.sm)
            .strokeBorder(borderColor)
        }
        .accessibilityIdentifier(OnboardingAccessibility.profileNameField)

      if case .tooLong = model.displayNameValidation {
        Text(OnboardingCopy.profileNameTooLong)
          .font(TypeScale.sm.font())
          .foregroundStyle(theme.atomColors.text)
      }
    }
  }

  /// The name field's border, reddened when the value is over the limit.
  private var borderColor: Color {
    if case .tooLong = model.displayNameValidation {
      return theme.colors.primary500
    }
    return theme.atomColors.borderContrastLow
  }

  /// The step's continue action.
  private var continueButton: some View {
    AlfButton(
      OnboardingCopy.continueAction,
      color: .primary,
      size: .large,
      action: { Task { await model.submitProfile() } })
      .disabled(!model.canContinue || !canSubmit)
      .accessibilityIdentifier(OnboardingAccessibility.profileContinue)
  }

  /// Whether the entered name is in a state that can be written.
  private var canSubmit: Bool {
    if case .tooLong = model.displayNameValidation { return false }
    return true
  }
}
