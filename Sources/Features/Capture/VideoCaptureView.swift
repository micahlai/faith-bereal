import SwiftUI
import UniformTypeIdentifiers
import UIKit

struct VideoCaptureView: UIViewControllerRepresentable {
    let onCapture: (URL) -> Void
    let onCancel: () -> Void
    let onFailure: (String) -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(onCapture: onCapture, onCancel: onCancel, onFailure: onFailure)
    }

    func makeUIViewController(context: Context) -> UIImagePickerController {
        let picker = UIImagePickerController()
        picker.sourceType = .camera
        picker.cameraCaptureMode = .video
        picker.mediaTypes = [UTType.movie.identifier]
        picker.videoMaximumDuration = 30
        picker.videoQuality = .typeHigh
        picker.modalPresentationStyle = .fullScreen
        picker.delegate = context.coordinator
        return picker
    }

    func updateUIViewController(_ uiViewController: UIImagePickerController, context: Context) {}

    final class Coordinator: NSObject, UINavigationControllerDelegate, UIImagePickerControllerDelegate {
        private let onCapture: (URL) -> Void
        private let onCancel: () -> Void
        private let onFailure: (String) -> Void

        init(
            onCapture: @escaping (URL) -> Void,
            onCancel: @escaping () -> Void,
            onFailure: @escaping (String) -> Void
        ) {
            self.onCapture = onCapture
            self.onCancel = onCancel
            self.onFailure = onFailure
        }

        func imagePickerControllerDidCancel(_ picker: UIImagePickerController) {
            onCancel()
        }

        func imagePickerController(
            _ picker: UIImagePickerController,
            didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey: Any]
        ) {
            guard let url = info[.mediaURL] as? URL else {
                onCancel()
                return
            }
            do {
                onCapture(try CaptureMediaStore.persistVideo(from: url))
            } catch {
                onFailure("The recorded video could not be saved. Please record it again.")
            }
        }
    }
}
