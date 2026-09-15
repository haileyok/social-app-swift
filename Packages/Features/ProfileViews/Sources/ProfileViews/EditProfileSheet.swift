import DesignSystem
import DesignTokens
import Lexicons
import ProfileLogic
import SwiftUI
import UIComponents
import UIComponentsCore

/// The edit-profile sheet.
///
/// Port of `EditProfileDialog`: a banner and avatar with change affordances, the
/// display-name and description fields, and a save action that is disabled until
/// something changed. Validation is ``ProfileEdit```s, so the grapheme and byte
/// caps the form shows are the same ones the write enforces.
///
/// The sheet owns only its draft text; the caller supplies the starting profile
/// and receives the finished ``ProfileEdit``.
public struct EditProfileSheet: View {
  private let profile: Lexicons.App.Bsky.ActorDefs_ProfileViewDetailed
  private let strings: any ProfileStrings
  private let onCancel: () -> Void
  private let onSave: (ProfileEdit) -> Void

  @Environment(\.dismiss) private var dismiss
  @State private var displayName: String
  @State private var description: String
  @State private var validationMessage: String?

  public init(
    profile: Lexicons.App.Bsky.ActorDefs_ProfileViewDetailed,
    strings: any ProfileStrings = defaultProfileStrings,
    onCancel: @escaping () -> Void = {},
    onSave: @escaping (ProfileEdit) -> Void = { _ in }
  ) {
    self.profile = profile
    self.strings = strings
    self.onCancel = onCancel
    self.onSave = onSave
    _displayName = State(initialValue: profile.displayName ?? "")
    _description = State(initialValue: profile.description ?? "")
  }

  /// The edit the current field values describe.
  private var draft: ProfileEdit {
    ProfileEdit(profile: profile, displayName: displayName, description: description)
  }

  public var body: some View {
    NavigationStack {
      Form {
        imageSection
        fieldsSection
        if let validationMessage {
          Section {
            Text(validationMessage)
              .font(TypeScale.sm.font())
              .foregroundStyle(.red)
          }
        }
      }
      .navigationTitle(strings.editProfileTitle)
      .toolbar {
        ToolbarItem(placement: .cancellationAction) {
          Button(strings.cancel) {
            onCancel()
            dismiss()
          }
        }
        ToolbarItem(placement: .confirmationAction) {
          Button(strings.save, action: save)
            .disabled(!draft.isDirty)
        }
      }
    }
  }

  // MARK: - Sections

  private var imageSection: some View {
    Section {
      VStack(alignment: .leading, spacing: Spacing.sm) {
        Banner(banner: profile.banner?.rawValue, height: BannerGeometry.defaultHeight)
          .clipShape(.rect(cornerRadius: Radius.sm))
        HStack {
          Avatar(
            avatar: profile.avatar?.rawValue,
            handle: profile.handle.rawValue,
            displayName: profile.displayName,
            size: .lg)
          Spacer()
          Text("Tap to change")
            .font(TypeScale.sm.font())
            .foregroundStyle(.secondary)
        }
      }
      .padding(.vertical, Spacing.xs)
    }
  }

  private var fieldsSection: some View {
    Section {
      TextField(strings.displayNameField, text: $displayName)
        .onChange(of: displayName) { _, _ in revalidate() }
      TextField(strings.descriptionField, text: $description, axis: .vertical)
        .lineLimit(3...6)
        .onChange(of: description) { _, _ in revalidate() }
    } footer: {
      Text(characterCount)
        .font(TypeScale.xs.font())
        .foregroundStyle(.secondary)
    }
  }

  /// The live `used / limit` counts, matching the RN dialog's footers.
  private var characterCount: String {
    let name = "\(displayName.count)/\(ProfileLimits.maxDisplayName)"
    let desc = "\(description.count)/\(ProfileLimits.maxDescription)"
    return "\(strings.displayNameField): \(name) · \(strings.descriptionField): \(desc)"
  }

  // MARK: - Actions

  /// Re-runs validation, surfacing the first error as field copy.
  private func revalidate() {
    do {
      try draft.validate()
      validationMessage = nil
    } catch let error as ProfileEditValidationError {
      validationMessage = error.message
    } catch {
      validationMessage = nil
    }
  }

  private func save() {
    do {
      let edit = draft
      try edit.validate()
      onSave(edit)
      dismiss()
    } catch let error as ProfileEditValidationError {
      validationMessage = error.message
    } catch {
      validationMessage = "Could not save the profile."
    }
  }
}
