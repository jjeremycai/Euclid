import ComposableArchitecture
import EuclidCore
import Sauce
import XCTest

@testable import Euclid

@MainActor
final class SettingsFeatureHotKeyCaptureTests: XCTestCase {
  func testEmptyEventDoesNotClearExistingRecordingHotKey() {
    var state = SettingsFeature.State()
    let originalHotKey = HotKey(key: .r, modifiers: [.command])
    state.$euclidSettings.withLock { $0.hotkey = originalHotKey }

    let reducer = SettingsFeature()

    _ = reducer.reduce(into: &state, action: .startSettingRecordingHotKey(0))
    _ = reducer.reduce(
      into: &state,
      action: .keyEvent(KeyEvent(key: nil, modifiers: .init(modifiers: [])))
    )

    XCTAssertEqual(state.euclidSettings.hotkey, originalHotKey)
    XCTAssertTrue(state.isSettingHotKey)
  }

  func testModifierOnlyCaptureStillCommitsOnModifierRelease() {
    var state = SettingsFeature.State()
    state.$euclidSettings.withLock { $0.hotkey = HotKey(key: .r, modifiers: [.command]) }

    let reducer = SettingsFeature()

    _ = reducer.reduce(into: &state, action: .startSettingRecordingHotKey(0))
    _ = reducer.reduce(
      into: &state,
      action: .keyEvent(KeyEvent(key: nil, modifiers: .init(modifiers: [.option, .shift])))
    )
    _ = reducer.reduce(
      into: &state,
      action: .keyEvent(KeyEvent(key: nil, modifiers: .init(modifiers: [])))
    )

    XCTAssertEqual(state.euclidSettings.hotkey, HotKey(key: nil, modifiers: [.option, .shift]))
  }
}
