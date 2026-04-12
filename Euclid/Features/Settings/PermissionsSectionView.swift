import ComposableArchitecture
import EuclidCore
import Inject
import SwiftUI

struct PermissionsSectionView: View {
	@ObserveInjection var inject
	@Bindable var store: StoreOf<SettingsFeature>
	let microphonePermission: PermissionStatus
	let accessibilityPermission: PermissionStatus
	let inputMonitoringPermission: PermissionStatus

	var body: some View {
		Section {
			HStack(spacing: 12) {
				// Microphone
				permissionCard(
					title: "Microphone",
					icon: "mic.fill",
					status: microphonePermission,
					action: { store.send(.requestMicrophone) }
				)

				permissionCard(
					title: "Accessibility",
					icon: "accessibility",
					status: accessibilityPermission,
					action: { store.send(.requestAccessibility) }
				)

				permissionCard(
					title: "Input Monitoring",
					icon: "keyboard",
					status: inputMonitoringPermission,
					action: { store.send(.requestInputMonitoring) }
				)
			}

			if accessibilityPermission != .granted {
				VStack(alignment: .leading, spacing: 8) {
					Label {
						Text("Grant Accessibility first. Euclid should appear in the Accessibility list after macOS shows the prompt.")
							.font(.callout)
							.foregroundStyle(.primary)
					} icon: {
						Image(systemName: "figure.wave")
							.foregroundStyle(.yellow)
					}

					Button("Open Accessibility Settings") {
						store.send(.openAccessibilitySettings)
					}
					.buttonStyle(.bordered)
					.controlSize(.small)
				}
				.padding(12)
				.background(Color(nsColor: .controlBackgroundColor))
				.clipShape(RoundedRectangle(cornerRadius: 10))
			}

			if inputMonitoringPermission != .granted {
				VStack(alignment: .leading, spacing: 8) {
					Label {
						Text(inputMonitoringHelpText)
							.font(.callout)
							.foregroundStyle(.primary)
					} icon: {
						Image(systemName: "exclamationmark.triangle.fill")
							.foregroundStyle(.yellow)
					}

					HStack(spacing: 8) {
						Button("Retry Input Monitoring Prompt") {
							store.send(.requestInputMonitoring)
						}
						.buttonStyle(.borderedProminent)
						.controlSize(.small)

						Button("Open Input Monitoring Settings") {
							store.send(.openInputMonitoringSettings)
						}
						.buttonStyle(.bordered)
						.controlSize(.small)
					}
				}
				.padding(12)
				.background(Color(nsColor: .controlBackgroundColor))
				.clipShape(RoundedRectangle(cornerRadius: 10))
			}

		} header: {
			Text("Permissions")
		}
		.enableInjection()
	}
	
	@ViewBuilder
	private func permissionCard(
		title: String,
		icon: String,
		status: PermissionStatus,
		action: @escaping () -> Void
	) -> some View {
		HStack(spacing: 8) {
			Image(systemName: icon)
				.font(.body)
				.foregroundStyle(.secondary)
				.frame(width: 16)
			
			Text(title)
				.font(.body.weight(.medium))
				.lineLimit(1)
				.truncationMode(.tail)
				.layoutPriority(1)
			
			Spacer()
			
			switch status {
			case .granted:
				Image(systemName: "checkmark.circle.fill")
					.foregroundStyle(.green)
					.font(.body)
			case .denied, .notDetermined:
				Button("Grant") {
					action()
				}
				.buttonStyle(.bordered)
				.controlSize(.small)
			}
		}
		.padding(.horizontal, 12)
		.padding(.vertical, 8)
		.frame(maxWidth: .infinity)
		.background(Color(nsColor: .controlBackgroundColor))
		.clipShape(RoundedRectangle(cornerRadius: 8))
	}

	private var inputMonitoringHelpText: String {
		if accessibilityPermission != .granted {
			return "After Accessibility is granted: 1. Click Retry Input Monitoring Prompt. 2. Open Input Monitoring Settings. 3. Enable Euclid there if it appears."
		}
		return "1. Click Retry Input Monitoring Prompt. 2. Open Input Monitoring Settings. 3. Enable Euclid there if it appears."
	}
}
