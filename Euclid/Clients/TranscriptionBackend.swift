import EuclidCore

enum TranscriptionBackend: Sendable, Equatable {
  case whisperKit(modelName: String)
  case parakeet(ParakeetModel)

  init(modelName: String) {
    if let variant = ParakeetModel(rawValue: modelName) {
      self = .parakeet(variant)
    } else {
      self = .whisperKit(modelName: modelName)
    }
  }

  var modelName: String {
    switch self {
    case .whisperKit(let modelName):
      modelName
    case .parakeet(let variant):
      variant.identifier
    }
  }

  var logLabel: String {
    switch self {
    case .whisperKit:
      "WhisperKit"
    case .parakeet:
      "Parakeet"
    }
  }

  var supportsVocabularyPrompt: Bool {
    if case .whisperKit = self { return true }
    return false
  }
}
