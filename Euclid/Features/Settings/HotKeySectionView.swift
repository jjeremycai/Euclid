import ComposableArchitecture
import EuclidCore
import Inject
import Sauce
import SwiftUI

struct HotKeySectionView: View {
    @ObserveInjection var inject
    @Bindable var store: StoreOf<SettingsFeature>

    private var recordingHotkeys: [HotKey] {
        store.euclidSettings.recordingHotkeys
    }

    private var hasKeyedRecordingHotkey: Bool {
        recordingHotkeys.contains { $0.key != nil }
    }

    private var hasModifierOnlyRecordingHotkey: Bool {
        recordingHotkeys.contains { $0.key == nil }
    }

    var body: some View {
        Section("Hot Keys") {
            VStack(spacing: 12) {
                ForEach(Array(recordingHotkeys.enumerated()), id: \.offset) { index, hotKey in
                    RecordingHotKeyRow(
                        title: index == 0 ? "Primary" : "Shortcut \(index + 1)",
                        hotKey: hotKey,
                        isActive: store.recordingHotKeyCaptureIndex == index,
                        modifiers: store.recordingHotKeyCaptureIndex == index ? store.currentModifiers : hotKey.modifiers,
                        key: store.recordingHotKeyCaptureIndex == index ? nil : hotKey.key,
                        canRemove: index > 0,
                        onTap: { store.send(.startSettingRecordingHotKey(index)) },
                        onRemove: { store.send(.removeRecordingHotKey(index)) },
                        onSelectModifierSide: { kind, side in
                            store.send(.setModifierSide(index, kind, side))
                        }
                    )
                }

                if store.isAddingRecordingHotKey {
                    RecordingHotKeyRow(
                        title: "New Shortcut",
                        hotKey: HotKey(key: nil, modifiers: []),
                        isActive: true,
                        modifiers: store.currentModifiers,
                        key: nil,
                        canRemove: false,
                        onTap: {},
                        onRemove: {},
                        onSelectModifierSide: { _, _ in }
                    )
                }

                Button {
                    store.send(.addRecordingHotKey)
                } label: {
                    Label("Add hotkey", systemImage: "plus.circle")
                }
                .disabled(store.isSettingHotKey)
            }

            Label {
                Toggle(
                    "Enable double-tap lock",
                    isOn: Binding(
                        get: { store.euclidSettings.doubleTapLockEnabled },
                        set: { store.send(.setDoubleTapLockEnabled($0)) }
                    )
                )
            } icon: {
                Image(systemName: "hand.tap")
            }

            if hasKeyedRecordingHotkey {
                Label {
                    Toggle(
                        "Use double-tap only",
                        isOn: Binding(
                            get: { store.euclidSettings.useDoubleTapOnly },
                            set: { store.send(.setUseDoubleTapOnly($0)) }
                        )
                    )
                    .disabled(!store.euclidSettings.doubleTapLockEnabled)
                } icon: {
                    Image(systemName: "hand.tap.fill")
                }
            }

            if hasModifierOnlyRecordingHotkey {
                Label {
                    Slider(
                        value: Binding(
                            get: { store.euclidSettings.minimumKeyTime },
                            set: { store.send(.setMinimumKeyTime($0)) }
                        ),
                        in: 0.0 ... 2.0,
                        step: 0.1
                    ) {
                        Text("Ignore below \(store.euclidSettings.minimumKeyTime, specifier: "%.1f")s")
                    }
                } icon: {
                    Image(systemName: "clock")
                }
            }
        }
        .enableInjection()
    }
}

private struct RecordingHotKeyRow: View {
    @ObserveInjection var inject
    let title: String
    let hotKey: HotKey
    let isActive: Bool
    let modifiers: Modifiers
    let key: Key?
    let canRemove: Bool
    let onTap: () -> Void
    let onRemove: () -> Void
    let onSelectModifierSide: (Modifier.Kind, Modifier.Side) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(title)
                    .settingsCaption()
                Spacer()
                if canRemove {
                    Button(role: .destructive, action: onRemove) {
                        Image(systemName: "minus.circle")
                    }
                    .buttonStyle(.plain)
                    .help("Remove hotkey")
                }
            }

            HStack {
                Spacer()
                HotKeyView(modifiers: modifiers, key: key, isActive: isActive)
                    .animation(.spring(), value: key)
                    .animation(.spring(), value: modifiers)
                Spacer()
            }
            .contentShape(Rectangle())
            .onTapGesture(perform: onTap)

            if !isActive, hotKey.key == nil, !hotKey.modifiers.isEmpty {
                ModifierSideControls(
                    modifiers: hotKey.modifiers,
                    onSelect: onSelectModifierSide
                )
                .transition(.opacity)
            }
        }
        .enableInjection()
    }
}

private struct ModifierSideControls: View {
    @ObserveInjection var inject
    var modifiers: Modifiers
    var onSelect: (Modifier.Kind, Modifier.Side) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            ForEach(modifiers.kinds, id: \.self) { kind in
                if kind.supportsSideSelection {
                    let binding = Binding<Modifier.Side>(
                        get: { modifiers.side(for: kind) ?? .either },
                        set: { onSelect(kind, $0) }
                    )

                    VStack(alignment: .leading, spacing: 4) {
                        Text("\(kind.symbol) \(kind.displayName)")
                            .settingsCaption()

                        Picker("Modifier side", selection: binding) {
                            ForEach(Modifier.Side.allCases, id: \.self) { side in
                                Text(side.displayName)
                                    .tag(side)
                                    .disabled(!kind.supportsSideSelection && side != .either)
                            }
                        }
                        .pickerStyle(.segmented)
                    }
                }
            }
        }
        .enableInjection()
    }
}
