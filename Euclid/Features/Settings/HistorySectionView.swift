import ComposableArchitecture
import Inject
import SwiftUI
import EuclidCore

struct HistorySectionView: View {
	@ObserveInjection var inject
	@Bindable var store: StoreOf<SettingsFeature>

	var body: some View {
		Section {
			Label {
				Toggle("Save Transcription History", isOn: Binding(
					get: { store.euclidSettings.saveTranscriptionHistory },
					set: { store.send(.toggleSaveTranscriptionHistory($0)) }
				))
				Text("Save transcriptions and audio recordings for later access")
					.settingsCaption()
			} icon: {
				Image(systemName: "clock.arrow.circlepath")
			}

			if store.euclidSettings.saveTranscriptionHistory {
				Label {
					HStack {
						Text("Maximum History Entries")
						Spacer()
						Picker("", selection: Binding(
							get: { store.euclidSettings.maxHistoryEntries ?? 0 },
							set: { newValue in
								store.send(.setMaxHistoryEntries(newValue == 0 ? nil : newValue))
							}
						)) {
							Text("Unlimited").tag(0)
							Text("50").tag(50)
							Text("100").tag(100)
							Text("200").tag(200)
							Text("500").tag(500)
							Text("1000").tag(1000)
						}
						.pickerStyle(.menu)
						.frame(width: 120)
					}
				} icon: {
					Image(systemName: "number.square")
				}

				if store.euclidSettings.maxHistoryEntries != nil {
					Text("Oldest entries will be automatically deleted when limit is reached")
						.settingsCaption()
						.padding(.leading, 28)
				}

				PasteLastTranscriptHotkeyRow(store: store)
			}
		} header: {
			Text("History")
		} footer: {
			if !store.euclidSettings.saveTranscriptionHistory {
				Text("When disabled, transcriptions will not be saved and audio files will be deleted immediately after transcription.")
					.font(.footnote)
					.foregroundColor(.secondary)
			}
		}
		.enableInjection()
	}
}

private struct PasteLastTranscriptHotkeyRow: View {
	@ObserveInjection var inject
	@Bindable var store: StoreOf<SettingsFeature>

	var body: some View {
		let pasteHotkey = store.euclidSettings.pasteLastTranscriptHotkey
		let isShowingCapturedModifiers =
			store.isSettingPasteLastTranscriptHotkey && !store.currentPasteLastModifiers.isEmpty

		VStack(alignment: .leading, spacing: 12) {
			Label {
				VStack(alignment: .leading, spacing: 2) {
					Text("Paste Last Transcript")
						.font(.subheadline.weight(.semibold))
					Text("Assign a shortcut (modifier + key) to instantly paste your last transcription.")
						.settingsCaption()
				}
			} icon: {
				Image(systemName: "doc.on.clipboard")
			}

			let key = isShowingCapturedModifiers ? nil : pasteHotkey?.key
			let modifiers = isShowingCapturedModifiers
				? store.currentPasteLastModifiers
				: (pasteHotkey?.modifiers ?? .init(modifiers: []))

			HStack {
				Spacer()
				ZStack {
					HotKeyView(modifiers: modifiers, key: key, isActive: store.isSettingPasteLastTranscriptHotkey)

					if !store.isSettingPasteLastTranscriptHotkey, pasteHotkey == nil {
						Text("Not set")
							.settingsCaption()
					}
				}
				Spacer()
			}

			if store.isSettingPasteLastTranscriptHotkey {
				Text("Press a new shortcut. Use at least one modifier (⌘, ⌥, ⇧, ⌃) plus a key. Press Esc to cancel.")
					.settingsCaption()
				Button("Cancel") {
					store.send(.cancelSettingPasteLastTranscriptHotkeyCapture)
				}
				.buttonStyle(.borderless)
				.font(.caption)
			} else {
				HStack(spacing: 12) {
					Button("Change shortcut") {
						store.send(.startSettingPasteLastTranscriptHotkey)
					}
					.buttonStyle(.borderless)

					if pasteHotkey != nil {
						Button("Clear shortcut") {
							store.send(.clearPasteLastTranscriptHotkey)
						}
						.buttonStyle(.borderless)
						.foregroundStyle(.secondary)
					}
				}
				.font(.caption)
			}
		}
		.enableInjection()
	}
}
