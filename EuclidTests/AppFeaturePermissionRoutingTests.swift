import ComposableArchitecture
import EuclidCore
import XCTest

@testable import Euclid

@MainActor
final class AppFeaturePermissionRoutingTests: XCTestCase {
  func testSetupPanelForwardsOpenAccessibilitySettings() async {
    let opened = LockIsolated(false)
    var permissions = PermissionClient()
    permissions.openAccessibilitySettings = {
      opened.setValue(true)
    }

    let store = Store(initialState: AppFeature.State()) {
      AppFeature()
    } withDependencies: {
      $0.permissions = permissions
    }

    await store.send(.settings(.openAccessibilitySettings)).finish()

    XCTAssertTrue(opened.value)
  }

  func testSetupPanelForwardsOpenInputMonitoringSettings() async {
    let opened = LockIsolated(false)
    var permissions = PermissionClient()
    permissions.openInputMonitoringSettings = {
      opened.setValue(true)
    }

    let store = Store(initialState: AppFeature.State()) {
      AppFeature()
    } withDependencies: {
      $0.permissions = permissions
    }

    await store.send(.settings(.openInputMonitoringSettings)).finish()

    XCTAssertTrue(opened.value)
  }
}
