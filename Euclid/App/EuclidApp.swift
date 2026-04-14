import ComposableArchitecture
import Inject
import Sparkle
import AppKit
import SwiftUI

@main
struct EuclidApp: App {
	static let appStore = Store(initialState: AppFeature.State()) {
		AppFeature()
	}

	@NSApplicationDelegateAdaptor(EuclidAppDelegate.self) var appDelegate
  
    var body: some Scene {
        MenuBarExtra {
            CheckForUpdatesView()

            // Copy last transcript to clipboard
            MenuBarCopyLastTranscriptButton()

            Button("Transcribe Files…") {
                appDelegate.presentFilesView()
            }

            Button("Settings...") {
                appDelegate.presentSettingsView()
            }.keyboardShortcut(",")
			
			Divider()
			
			Button("Quit") {
				NSApplication.shared.terminate(nil)
			}.keyboardShortcut("q")
		} label: {
			let image: NSImage = {
				let ratio = $0.size.height / $0.size.width
				$0.size.height = 18
				$0.size.width = 18 / ratio
				return $0
			}(NSImage(named: "EuclidIcon")!)
			Image(nsImage: image)
		}


		WindowGroup {}.defaultLaunchBehavior(.suppressed)
			.commands {
				CommandGroup(after: .appInfo) {
					CheckForUpdatesView()

					Button("Transcribe Files…") {
						appDelegate.presentFilesView()
					}

					Button("Settings...") {
						appDelegate.presentSettingsView()
					}.keyboardShortcut(",")
				}

				CommandGroup(replacing: .help) {}
			}
	}
}
