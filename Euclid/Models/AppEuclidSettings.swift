import ComposableArchitecture
import Dependencies
import Foundation
import EuclidCore

// Re-export types so the app target can use them without EuclidCore prefixes.
typealias RecordingAudioBehavior = EuclidCore.RecordingAudioBehavior
typealias RecordingIndicatorPlacement = EuclidCore.RecordingIndicatorPlacement
typealias RecordingIndicatorStyle = EuclidCore.RecordingIndicatorStyle
typealias EuclidSettings = EuclidCore.EuclidSettings

extension SharedReaderKey
	where Self == FileStorageKey<EuclidSettings>.Default
{
	static var euclidSettings: Self {
		Self[
			.fileStorage(.euclidSettingsURL),
			default: .init()
		]
	}
}

// MARK: - Storage Migration

extension URL {
	static var euclidSettingsURL: URL {
		get {
			URL.euclidMigratedFileURL(named: "euclid_settings.json")
		}
	}
}
