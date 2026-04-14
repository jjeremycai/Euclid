import AppKit
import Dependencies
import DependenciesMacros
import Foundation
import UniformTypeIdentifiers

@DependencyClient
struct ImportedMediaPickerClient {
  var pickFiles: @Sendable () async -> [URL]? = { nil }
}

extension ImportedMediaPickerClient: DependencyKey {
  static let liveValue = Self(
    pickFiles: {
      await MainActor.run {
        let panel = NSOpenPanel()
        panel.title = "Add Files"
        panel.prompt = "Add"
        panel.message = "Choose audio or video files to transcribe."
        panel.allowsMultipleSelection = true
        panel.canChooseDirectories = false
        panel.canChooseFiles = true
        panel.resolvesAliases = true
        panel.allowedContentTypes = ImportedMediaSupport.openPanelContentTypes
        return panel.runModal() == .OK ? panel.urls : nil
      }
    }
  )

  static let testValue = Self(
    pickFiles: { nil }
  )
}

extension DependencyValues {
  var importedMediaPicker: ImportedMediaPickerClient {
    get { self[ImportedMediaPickerClient.self] }
    set { self[ImportedMediaPickerClient.self] = newValue }
  }
}
