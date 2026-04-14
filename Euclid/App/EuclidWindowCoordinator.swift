import ComposableArchitecture
import AppKit
import SwiftUI

@MainActor
final class EuclidWindowCoordinator {
	private var invisibleWindow: InvisibleWindow?
	private var settingsWindow: NSWindow?
	private let setupPanel = SetupPanel()

	var isSetupVisible: Bool {
		setupPanel.isVisible
	}

	func presentMainView(store: StoreOf<AppFeature>) {
		guard invisibleWindow == nil else {
			return
		}

		let transcriptionStore = store.scope(state: \.transcription, action: \.transcription)
		let transcriptionView = TranscriptionView(store: transcriptionStore)
		invisibleWindow = InvisibleWindow.fromView(transcriptionView)
		invisibleWindow?.makeKeyAndOrderFront(nil)
	}

	func presentSettingsView(store: StoreOf<AppFeature>) {
		if let settingsWindow {
			settingsWindow.makeKeyAndOrderFront(nil)
			NSApp.activate(ignoringOtherApps: true)
			return
		}

		let settingsView = AppView(store: store)
		let settingsWindow = NSWindow(
			contentRect: .init(x: 0, y: 0, width: 700, height: 700),
			styleMask: [.titled, .fullSizeContentView, .closable, .miniaturizable],
			backing: .buffered,
			defer: false
		)
		settingsWindow.titleVisibility = .visible
		settingsWindow.contentView = NSHostingView(rootView: settingsView)
		settingsWindow.isReleasedWhenClosed = false
		settingsWindow.center()
		settingsWindow.toolbarStyle = NSWindow.ToolbarStyle.unified
		settingsWindow.makeKeyAndOrderFront(nil)
		NSApp.activate(ignoringOtherApps: true)
		self.settingsWindow = settingsWindow
	}

	func presentSetupPanel(
		store: StoreOf<AppFeature>,
		onSetupComplete: @escaping () -> Void
	) {
		setupPanel.show(store: store, onSetupComplete: onSetupComplete)
	}
}
