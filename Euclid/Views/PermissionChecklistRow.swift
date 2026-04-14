import EuclidCore
import SwiftUI

struct PermissionChecklistAction {
  enum Style {
    case primary
    case secondary
  }

  let title: String
  var style: Style = .secondary
  let action: () -> Void
}

struct PermissionChecklistTheme {
  let rowBackground: Color
  let rowBorder: Color
  let titleColor: Color
  let subtitleColor: Color
  let mutedIconColor: Color
  let primaryButtonBackground: Color
  let primaryButtonForeground: Color
  let secondaryButtonBackground: Color
  let secondaryButtonBorder: Color
  let secondaryButtonForeground: Color
  let grantedColor: Color

  static let settings = PermissionChecklistTheme(
    rowBackground: Color(nsColor: .controlBackgroundColor),
    rowBorder: Color.primary.opacity(0.06),
    titleColor: .primary,
    subtitleColor: .secondary,
    mutedIconColor: .secondary,
    primaryButtonBackground: .accentColor,
    primaryButtonForeground: .white,
    secondaryButtonBackground: Color(nsColor: .windowBackgroundColor),
    secondaryButtonBorder: Color.primary.opacity(0.12),
    secondaryButtonForeground: .primary,
    grantedColor: .green
  )

  static let clickyPanel = PermissionChecklistTheme(
    rowBackground: Color(red: 0.09, green: 0.10, blue: 0.09),
    rowBorder: Color(red: 0.22, green: 0.23, blue: 0.22),
    titleColor: Color(red: 0.68, green: 0.71, blue: 0.70),
    subtitleColor: Color(red: 0.42, green: 0.45, blue: 0.44),
    mutedIconColor: Color(red: 0.42, green: 0.45, blue: 0.44),
    primaryButtonBackground: Color(red: 0.15, green: 0.39, blue: 0.92),
    primaryButtonForeground: .white,
    secondaryButtonBackground: Color(red: 0.13, green: 0.14, blue: 0.13),
    secondaryButtonBorder: Color(red: 0.22, green: 0.23, blue: 0.22),
    secondaryButtonForeground: Color(red: 0.93, green: 0.93, blue: 0.93),
    grantedColor: Color(red: 0.20, green: 0.83, blue: 0.60)
  )
}

struct PermissionChecklistRow: View {
  let icon: String
  let iconColor: Color
  let title: String
  var subtitle: String? = nil
  let status: PermissionStatus
  var primaryAction: PermissionChecklistAction? = nil
  var secondaryAction: PermissionChecklistAction? = nil
  var theme: PermissionChecklistTheme = .settings

  var body: some View {
    HStack(alignment: .center, spacing: 12) {
      Image(systemName: icon)
        .font(.system(size: 13, weight: .medium))
        .foregroundStyle(status == .granted ? theme.mutedIconColor : iconColor)
        .frame(width: 18)

      VStack(alignment: .leading, spacing: 2) {
        Text(title)
          .font(.callout.weight(.medium))
          .foregroundStyle(theme.titleColor)

        if let subtitle {
          Text(subtitle)
            .font(.caption)
            .foregroundStyle(theme.subtitleColor)
            .fixedSize(horizontal: false, vertical: true)
        }
      }

      Spacer(minLength: 12)

      if status == .granted {
        PermissionGrantedBadge(color: theme.grantedColor)
      } else {
        HStack(spacing: 6) {
          if let primaryAction {
            PermissionChecklistButton(action: primaryAction, theme: theme)
          }

          if let secondaryAction {
            PermissionChecklistButton(action: secondaryAction, theme: theme)
          }
        }
      }
    }
    .padding(.horizontal, 12)
    .padding(.vertical, 10)
    .frame(maxWidth: .infinity, alignment: .leading)
    .background(
      RoundedRectangle(cornerRadius: 10, style: .continuous)
        .fill(theme.rowBackground)
    )
    .overlay(
      RoundedRectangle(cornerRadius: 10, style: .continuous)
        .strokeBorder(theme.rowBorder, lineWidth: 1)
    )
  }
}

private struct PermissionGrantedBadge: View {
  let color: Color

  var body: some View {
    HStack(spacing: 5) {
      Circle()
        .fill(color)
        .frame(width: 7, height: 7)

      Text("Granted")
        .font(.caption.weight(.semibold))
        .foregroundStyle(color)
    }
  }
}

private struct PermissionChecklistButton: View {
  let action: PermissionChecklistAction
  let theme: PermissionChecklistTheme

  var body: some View {
    Button(action.title, action: action.action)
      .buttonStyle(.plain)
      .font(.system(size: 11, weight: .semibold))
      .foregroundStyle(foregroundStyle)
      .padding(.horizontal, 10)
      .padding(.vertical, 4)
      .background(background)
      .overlay(border)
      .clipShape(Capsule())
  }

  private var foregroundStyle: Color {
    switch action.style {
    case .primary:
      return theme.primaryButtonForeground
    case .secondary:
      return theme.secondaryButtonForeground
    }
  }

  @ViewBuilder
  private var background: some View {
    switch action.style {
    case .primary:
      Capsule()
        .fill(theme.primaryButtonBackground)
    case .secondary:
      Capsule()
        .fill(theme.secondaryButtonBackground)
    }
  }

  @ViewBuilder
  private var border: some View {
    switch action.style {
    case .primary:
      EmptyView()
    case .secondary:
      Capsule()
        .strokeBorder(theme.secondaryButtonBorder, lineWidth: 0.8)
    }
  }
}
