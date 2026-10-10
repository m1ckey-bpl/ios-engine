import SwiftUI
import UIKit
import UniformTypeIdentifiers

public struct DocumentPickerView: UIViewControllerRepresentable {
    public var allowsMultipleSelection: Bool
    public var onPick: ([URL]) -> Void
    public var onCancel: () -> Void
    
    public init(allowsMultipleSelection: Bool = true, onPick: @escaping ([URL]) -> Void, onCancel: @escaping () -> Void = {}) {
        self.allowsMultipleSelection = allowsMultipleSelection
        self.onPick = onPick
        self.onCancel = onCancel
    }
    
    public func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }
    
    public func makeUIViewController(context: Context) -> UIDocumentPickerViewController {
        let audioTypes: [UTType] = [.audio, .mp3, .wav, .aiff, .data, .item]
        let picker = UIDocumentPickerViewController(forOpeningContentTypes: audioTypes, asCopy: true)
        picker.allowsMultipleSelection = allowsMultipleSelection
        picker.shouldShowFileExtensions = true
        picker.delegate = context.coordinator
        return picker
    }
    
    public func updateUIViewController(_ uiViewController: UIDocumentPickerViewController, context: Context) {}
    
    public class Coordinator: NSObject, UIDocumentPickerDelegate {
        let parent: DocumentPickerView
        
        init(_ parent: DocumentPickerView) {
            self.parent = parent
        }
        
        public func documentPicker(_ controller: UIDocumentPickerViewController, didPickDocumentsAt urls: [URL]) {
            parent.onPick(urls)
        }
        
        public func documentPickerWasCancelled(_ controller: UIDocumentPickerViewController) {
            parent.onCancel()
        }
    }
}
