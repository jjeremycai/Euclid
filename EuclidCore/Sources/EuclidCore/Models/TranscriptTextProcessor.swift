import Foundation

public enum TranscriptTextProcessor {
  public static func process(
    _ text: String,
    settings: EuclidSettings,
    skipModifications: Bool = false
  ) -> String {
    guard !text.isEmpty else { return text }
    guard !skipModifications else { return text }

    var output = text
    if settings.wordRemovalsEnabled {
      output = WordRemovalApplier.apply(output, removals: settings.wordRemovals)
    }
    return WordRemappingApplier.apply(output, remappings: settings.wordRemappings)
  }
}
