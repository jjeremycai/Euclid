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
                        modifiers: displayedModifiers(for: hotKey, at: index),
                        key: displayedKey(for: hotKey, at: index),
                        canRemove: index > 0,
                        onStartEditing: { store.send(.startSettingRecordingHotKey(index)) },
                        onCancelEditing: { store.send(.cancelSettingRecordingHotKeyCapture) },
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
                        onStartEditing: {},
                        onCancelEditing: { store.send(.cancelSettingRecordingHotKeyCapture) },
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

    private func displayedModifiers(for hotKey: HotKey, at index: Int) -> Modifiers {
        guard store.recordingHotKeyCaptureIndex == index, !store.currentModifiers.isEmpty else {
            return hotKey.modifiers
        }
        return store.currentModifiers
    }

    private func displayedKey(for hotKey: HotKey, at index: Int) -> Key? {
        guard store.recordingHotKeyCaptureIndex == index, !store.currentModifiers.isEmpty else {
            return hotKey.key
        }
        return nil
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
    let onStartEditing: () -> Void
    let onCancelEditing: () -> Void
    let onRemove: () -> Void
    let onSelectModifierSide: (Modifier.Kind, Modifier.Side) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(title)
                    .settingsCaption()
                Spacer()
            }

            HStack {
                Spacer()
                HotKeyView(modifiers: modifiers, key: key, isActive: isActive)
                    .animation(.spring(), value: key)
                    .animation(.spring(), value: modifiers)
                Spacer()
            }

            if isActive {
                Text("Press a new shortcut. Press Esc to cancel.")
                    .settingsCaption()

                Button("Cancel", action: onCancelEditing)
                    .buttonStyle(.borderless)
                    .font(.caption)
            } else {
                HStack(spacing: 12) {
                    Button("Change shortcut", action: onStartEditing)
                        .buttonStyle(.borderless)
                    if canRemove {
                        Button("Clear shortcut", role: .destructive, action: onRemove)
                            .buttonStyle(.borderless)
                    }
                }
                .font(.caption)
            }

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
