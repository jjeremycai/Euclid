import ComposableArchitecture
import EuclidCore
import Inject
import Sauce
import SwiftUI

struct SettingsView: View {
	@ObserveInjection var inject
	@Bindable var store: StoreOf<SettingsFeature>
	let microphonePermission: PermissionStatus
	let accessibilityPermission: PermissionStatus
	let inputMonitoringPermission: PermissionStatus
  
	var body: some View {
		Form {
			if microphonePermission != .granted
				|| accessibilityPermission != .granted
				|| inputMonitoringPermission != .granted {
				PermissionsSectionView(
					store: store,
					microphonePermission: microphonePermission,
					accessibilityPermission: accessibilityPermission,
					inputMonitoringPermission: inputMonitoringPermission
				)
			}

			ModelSectionView(store: store, shouldFlash: store.shouldFlashModelSection)
			// Only show language picker for WhisperKit models (not Parakeet)
			if ParakeetModel(rawValue: store.euclidSettings.selectedModel) == nil {
				LanguageSectionView(store: store)
			}

			HotKeySectionView(store: store)
			RecordingIndicatorSectionView(store: store)
          
			if microphonePermission == .granted {
				MicrophoneSelectionSectionView(store: store)
			}

			SoundSectionView(store: store)
			GeneralSectionView(store: store)
			HistorySectionView(store: store)
		}
		.formStyle(.grouped)
		.background(
			SettingsHotKeyCaptureMonitor(
				isActive: store.isSettingHotKey || store.isSettingPasteLastTranscriptHotkey,
				onKeyEvent: { store.send(.keyEvent($0)) }
			)
		)
		.task {
			await store.send(.task).finish()
		}
		.enableInjection()
	}
}

private struct SettingsHotKeyCaptureMonitor: View {
	let isActive: Bool
	let onKeyEvent: (KeyEvent) -> Void

	@State private var monitor: Any?

	var body: some View {
		Color.clear
			.frame(width: 0, height: 0)
			.onAppear { syncMonitor() }
			.onDisappear { removeMonitor() }
			.onChange(of: isActive) { _, _ in
				syncMonitor()
			}
	}

	private func syncMonitor() {
		if isActive {
			installMonitorIfNeeded()
		} else {
			removeMonitor()
		}
	}

	private func installMonitorIfNeeded() {
		guard monitor == nil else { return }
		monitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown, .flagsChanged]) { event in
			guard isActive else { return event }
			guard let keyEvent = makeKeyEvent(from: event) else { return event }
			onKeyEvent(keyEvent)
			return nil
		}
	}

	private func removeMonitor() {
		guard let monitor else { return }
		NSEvent.removeMonitor(monitor)
		self.monitor = nil
	}

	private func makeKeyEvent(from event: NSEvent) -> KeyEvent? {
		switch event.type {
		case .keyDown:
			return KeyEvent(
				key: Sauce.shared.key(for: Int(event.keyCode)),
				modifiers: Modifiers.from(cocoa: event.modifierFlags)
			)
		case .flagsChanged:
			return KeyEvent(
				key: nil,
				modifiers: Modifiers.from(cocoa: event.modifierFlags)
			)
		default:
			return nil
		}
	}
}

// MARK: - Shared Styles

extension Text {
	/// Applies caption font with secondary color, commonly used for helper/description text in settings.
	func settingsCaption() -> some View {
		self.font(.caption).foregroundStyle(.secondary)
	}
}
