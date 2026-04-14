import ComposableArchitecture
import EuclidCore
import SwiftUI

struct SetupPanelView: View {
    let store: StoreOf<AppFeature>
    var onDismiss: () -> Void = {}
    var onSetupComplete: () -> Void = {}

    private var allGranted: Bool {
        store.microphonePermission == .granted
            && store.accessibilityPermission == .granted
            && store.inputMonitoringPermission == .granted
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // MARK: - Header
            HStack(spacing: 8) {
                Circle()
                    .fill(statusDotColor)
                    .frame(width: 8, height: 8)
                    .shadow(color: statusDotColor.opacity(0.6), radius: 4)

                Text("Euclid")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(panelTextPrimary)

                Spacer()

                Text(statusText)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(panelTextTertiary)

                Button {
                    onDismiss()
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(panelTextTertiary)
                        .frame(width: 20, height: 20)
                        .background(
                            Circle()
                                .fill(Color.white.opacity(0.08))
                        )
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 14)

            Divider()
                .overlay(panelBorder)
                .padding(.horizontal, 16)

            // MARK: - Intro
            introSection
            .padding(.top, 16)
            .padding(.horizontal, 16)
            .padding(.bottom, 16)

            // MARK: - Permissions
            VStack(alignment: .leading, spacing: 0) {
                Text("PERMISSIONS")
                    .font(.system(size: 10, weight: .semibold, design: .rounded))
                    .fontWeight(.medium)
                    .foregroundStyle(panelTextTertiary)
                    .padding(.horizontal, 16)
                    .padding(.bottom, 8)

                VStack(spacing: 8) {
                    PermissionChecklistRow(
                        icon: "mic.fill",
                        iconColor: .orange,
                        title: "Microphone",
                        subtitle: microphoneSubtitle,
                        status: store.microphonePermission,
                        primaryAction: microphonePrimaryAction,
                        theme: .clickyPanel
                    )

                    PermissionChecklistRow(
                        icon: "accessibility",
                        iconColor: .orange,
                        title: "Accessibility",
                        subtitle: accessibilitySubtitle,
                        status: store.accessibilityPermission,
                        primaryAction: accessibilityPrimaryAction,
                        secondaryAction: openAccessibilitySettingsAction,
                        theme: .clickyPanel
                    )

                    PermissionChecklistRow(
                        icon: "keyboard",
                        iconColor: .orange,
                        title: "Input Monitoring",
                        subtitle: inputMonitoringSubtitle,
                        status: store.inputMonitoringPermission,
                        primaryAction: inputMonitoringPrimaryAction,
                        secondaryAction: openInputMonitoringSettingsAction,
                        theme: .clickyPanel
                    )
                }
                .padding(.horizontal, 16)
            }
            .padding(.bottom, 12)

            // MARK: - Quit
            Divider()
                .overlay(panelBorder)
                .padding(.horizontal, 16)

            Button {
                NSApplication.shared.terminate(nil)
            } label: {
                HStack(spacing: 8) {
                    Circle()
                        .fill(panelTextTertiary)
                        .frame(width: 6, height: 6)
                    Text("Quit Euclid")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(panelTextSecondary)
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        }
        .frame(width: 320)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(panelBackground)
                .shadow(color: .black.opacity(0.5), radius: 20, y: 10)
                .shadow(color: .black.opacity(0.3), radius: 4, y: 2)
        )
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .onChange(of: allGranted) { _, granted in
            if granted {
                onSetupComplete()
            }
        }
    }

    @ViewBuilder
    private var introSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(allGranted ? "You're all set." : "Hi! This is Euclid.")
                .font(.system(size: 12, weight: .bold))
                .foregroundStyle(panelTextSecondary)

            Text("Euclid lives in your menu bar. Hold the hotkey, speak, and your transcript appears where you're typing.")
                .font(.system(size: 11))
                .foregroundStyle(panelTextTertiary)
                .fixedSize(horizontal: false, vertical: true)

            Text("Euclid only listens while you're recording. Nothing runs in the background.")
                .font(.system(size: 11))
                .foregroundStyle(panelSuccess)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var microphoneSubtitle: String? {
        guard store.microphonePermission != .granted else { return nil }
        if store.microphonePermission == .denied {
            return "Enable Euclid in System Settings to record"
        }
        return "Used only while you are recording"
    }

    private var accessibilitySubtitle: String? {
        guard store.accessibilityPermission != .granted else { return nil }
        if store.accessibilityPermission == .denied {
            return "Enable Euclid in Privacy & Security after the prompt"
        }
        return "Lets Euclid paste back into the active app"
    }

    private var inputMonitoringSubtitle: String? {
        guard store.inputMonitoringPermission != .granted else { return nil }
        if store.inputMonitoringPermission == .denied {
            return "Retry the prompt, then enable Euclid in System Settings"
        }
        return "Required for your global hotkey"
    }

    private var microphonePrimaryAction: PermissionChecklistAction? {
        guard store.microphonePermission != .granted else { return nil }
        if store.microphonePermission == .denied {
            return PermissionChecklistAction(
                title: "Open Settings",
                style: .primary,
                action: { store.send(.settings(.openMicrophoneSettings)) }
            )
        }
        return PermissionChecklistAction(
            title: "Grant",
            style: .primary,
            action: { store.send(.requestMicrophone) }
        )
    }

    private var accessibilityPrimaryAction: PermissionChecklistAction? {
        guard store.accessibilityPermission != .granted else { return nil }
        return PermissionChecklistAction(
            title: store.accessibilityPermission == .denied ? "Retry Prompt" : "Grant",
            style: .primary,
            action: { store.send(.requestAccessibility) }
        )
    }

    private var inputMonitoringPrimaryAction: PermissionChecklistAction? {
        guard store.inputMonitoringPermission != .granted else { return nil }
        return PermissionChecklistAction(
            title: store.inputMonitoringPermission == .denied ? "Retry Prompt" : "Grant",
            style: .primary,
            action: { store.send(.requestInputMonitoring) }
        )
    }

    private var openAccessibilitySettingsAction: PermissionChecklistAction? {
        guard store.accessibilityPermission != .granted else { return nil }
        return PermissionChecklistAction(
            title: "Open Settings",
            action: { store.send(.settings(.openAccessibilitySettings)) }
        )
    }

    private var openInputMonitoringSettingsAction: PermissionChecklistAction? {
        guard store.inputMonitoringPermission != .granted else { return nil }
        return PermissionChecklistAction(
            title: "Open Settings",
            action: { store.send(.settings(.openInputMonitoringSettings)) }
        )
    }

    private var panelBackground: Color {
        Color(red: 0.063, green: 0.071, blue: 0.067)
    }

    private var panelBorder: Color {
        Color(red: 0.216, green: 0.231, blue: 0.224)
    }

    private var panelTextPrimary: Color {
        Color(red: 0.925, green: 0.933, blue: 0.929)
    }

    private var panelTextSecondary: Color {
        Color(red: 0.678, green: 0.710, blue: 0.698)
    }

    private var panelTextTertiary: Color {
        Color(red: 0.420, green: 0.451, blue: 0.435)
    }

    private var panelSuccess: Color {
        Color(red: 0.204, green: 0.827, blue: 0.600)
    }

    private var panelAccent: Color {
        Color(red: 0.149, green: 0.388, blue: 0.922)
    }

    private var statusDotColor: Color {
        allGranted ? panelSuccess : panelAccent
    }

    private var statusText: String {
        allGranted ? "Ready" : "Setup"
    }
}
