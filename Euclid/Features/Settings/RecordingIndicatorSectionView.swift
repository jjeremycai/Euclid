import ComposableArchitecture
import EuclidCore
import Inject
import SwiftUI

struct RecordingIndicatorSectionView: View {
	@ObserveInjection var inject
	@Bindable var store: StoreOf<SettingsFeature>

	var body: some View {
		Section {
			pickerRow(
				title: "Style",
				systemImage: "record.circle",
				selection: Binding(
					get: { store.euclidSettings.recordingIndicatorStyle },
					set: { store.send(.setRecordingIndicatorStyle($0)) }
				)
			) {
				ForEach(RecordingIndicatorStyle.allCases, id: \.self) { style in
					Text(style.displayName)
						.tag(style)
				}
			}

			pickerRow(
				title: "Placement",
				systemImage: "arrow.up.and.down.circle",
				selection: Binding(
					get: { store.euclidSettings.recordingIndicatorPlacement },
					set: { store.send(.setRecordingIndicatorPlacement($0)) }
				)
			) {
				ForEach(RecordingIndicatorPlacement.allCases, id: \.self) { placement in
					Text(placement.displayName)
						.tag(placement)
				}
			}

			Text("Choose how the recording indicator looks and where it appears while Euclid is recording or prewarming.")
				.settingsCaption()
		} header: {
			Text("Recording Indicator")
		}
		.enableInjection()
	}

	@ViewBuilder
	private func pickerRow<Value: Hashable>(
		title: String,
		systemImage: String,
		selection: Binding<Value>,
		@ViewBuilder options: () -> some View
	) -> some View {
		Label {
			HStack {
				Text(title)
				Spacer()
				Picker("", selection: selection) {
					options()
				}
				.pickerStyle(.menu)
			}
		} icon: {
			Image(systemName: systemImage)
		}
	}
}
