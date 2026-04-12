import Foundation

/// Known Parakeet Core ML bundles that Euclid supports.
public enum ParakeetModel: String, CaseIterable, Sendable {
	case englishV2 = "parakeet-tdt-0.6b-v2-coreml"
	case multilingualV3 = "parakeet-tdt-0.6b-v3-coreml"

	/// The identifier used throughout the app (matches the on-disk folder name).
	public var identifier: String { rawValue }

	/// Whether the model only supports English transcription.
	public var isEnglishOnly: Bool {
		self == .englishV2
	}

	/// Short capability label for UI copy.
	public var capabilityLabel: String {
		isEnglishOnly ? "English" : "Multilingual"
	}

	/// Approximate on-disk size for the current Core ML bundle revision.
	public var storageSizeLabel: String {
		switch self {
		case .englishV2:
			"2.58GB"
		case .multilingualV3:
			"2.67GB"
		}
	}

	/// Approximate bytes used for progress estimation and display.
	public var estimatedStorageBytes: UInt64 {
		switch self {
		case .englishV2:
			2_580_000_000
		case .multilingualV3:
			2_670_000_000
		}
	}

	/// Convenience text for recommendation badges.
	public var recommendationLabel: String {
		isEnglishOnly ? "Recommended (English)" : "Recommended (Multilingual)"
	}
}
