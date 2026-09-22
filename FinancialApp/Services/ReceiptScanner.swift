import SwiftUI
import UIKit
import Vision

enum ReceiptScanner {
    enum ScanError: LocalizedError {
        case unreadable

        var errorDescription: String? {
            "Не удалось прочитать чек. Сфотографируйте при лучшем свете"
        }
    }

    static func recognize(image: UIImage) async -> Result<(text: String, data: Data), ScanError> {
        guard let cgImage = image.fixedOrientation().cgImage else {
            return .failure(.unreadable)
        }
        let request = VNRecognizeTextRequest()
        request.recognitionLevel = .accurate
        request.usesLanguageCorrection = true
        request.recognitionLanguages = ["de-DE", "en-US", "ru-RU"]

        return await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                let handler = VNImageRequestHandler(cgImage: cgImage, options: [:])
                do {
                    try handler.perform([request])
                    let lines = (request.results ?? [])
                        .compactMap { $0.topCandidates(1).first?.string }
                        .filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }
                    let text = lines.joined(separator: "\n")
                    let data = image.fixedOrientation().jpegData(compressionQuality: 0.7)
                    if text.isEmpty || data == nil {
                        continuation.resume(returning: .failure(.unreadable))
                    } else {
                        continuation.resume(returning: .success((text, data!)))
                    }
                } catch {
                    continuation.resume(returning: .failure(.unreadable))
                }
            }
        }
    }
}

struct CameraPicker: UIViewControllerRepresentable {
    @Binding var image: UIImage?
    @Environment(\.dismiss) private var dismiss

    func makeUIViewController(context: Context) -> UIImagePickerController {
        let picker = UIImagePickerController()
        picker.sourceType = UIImagePickerController.isSourceTypeAvailable(.camera) ? .camera : .photoLibrary
        picker.delegate = context.coordinator
        return picker
    }

    func updateUIViewController(_ uiViewController: UIImagePickerController, context: Context) {}

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    final class Coordinator: NSObject, UIImagePickerControllerDelegate, UINavigationControllerDelegate {
        let parent: CameraPicker
        init(_ parent: CameraPicker) { self.parent = parent }

        func imagePickerControllerDidCancel(_ picker: UIImagePickerController) {
            parent.dismiss()
        }

        func imagePickerController(
            _ picker: UIImagePickerController,
            didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey: Any]
        ) {
            parent.image = info[.originalImage] as? UIImage
            parent.dismiss()
        }
    }
}

private extension UIImage {
    func fixedOrientation() -> UIImage {
        if imageOrientation == .up { return self }
        let format = UIGraphicsImageRendererFormat.default()
        format.scale = scale
        return UIGraphicsImageRenderer(size: size, format: format).image { _ in
            draw(in: CGRect(origin: .zero, size: size))
        }
    }
}
