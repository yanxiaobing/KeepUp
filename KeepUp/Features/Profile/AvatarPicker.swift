import SwiftUI
import TOCropViewController

/// Uses the same square crop controller and settings as PunchCard's PCImageService.
struct AvatarPicker: UIViewControllerRepresentable {
    let camera: Bool
    let locale: Locale
    let completion: (UIImage?) -> Void
    func makeCoordinator() -> Coordinator { Coordinator(locale: locale, completion: completion) }
    func makeUIViewController(context: Context) -> UIImagePickerController {
        let picker = UIImagePickerController()
        picker.sourceType = camera ? .camera : .photoLibrary
        picker.delegate = context.coordinator
        return picker
    }
    func updateUIViewController(_ controller: UIImagePickerController, context: Context) {}
    final class Coordinator: NSObject, UIImagePickerControllerDelegate, UINavigationControllerDelegate, @preconcurrency TOCropViewControllerDelegate {
        let locale: Locale
        let completion: (UIImage?) -> Void
        init(locale: Locale, completion: @escaping (UIImage?) -> Void) { self.locale = locale; self.completion = completion }
        func imagePickerControllerDidCancel(_ picker: UIImagePickerController) { completion(nil) }
        func imagePickerController(_ picker: UIImagePickerController, didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey: Any]) {
            guard let image = info[.originalImage] as? UIImage else { completion(nil); return }
            let crop = squareCropController(image: image, locale: locale)
            crop.delegate = self
            picker.pushViewController(crop, animated: true)
        }
        func cropViewController(_ cropViewController: TOCropViewController, didCropTo image: UIImage, with cropRect: CGRect, angle: Int) { completion(image) }
        func cropViewController(_ cropViewController: TOCropViewController, didFinishCancelled cancelled: Bool) {
            if cancelled { completion(nil) }
        }
    }
}


private func squareCropController(image: UIImage, locale: Locale) -> TOCropViewController {
    let crop = TOCropViewController(croppingStyle: .default, image: image)
    crop.title = localized("info.crop", locale)
    crop.doneButtonTitle = localized("info.done", locale)
    crop.cancelButtonTitle = localized("action.cancel", locale)
    // iOS 26 uses icon buttons; supply localized VoiceOver labels as well.
    crop.toolbar.doneIconButton.accessibilityLabel = localized("info.done", locale)
    crop.toolbar.doneIconButton.accessibilityIdentifier = "info.crop.done"
    crop.toolbar.cancelIconButton.accessibilityLabel = localized("action.cancel", locale)
    crop.toolbar.cancelIconButton.accessibilityIdentifier = "info.crop.cancel"
    crop.aspectRatioPreset = TOCropViewControllerAspectRatioPreset.square
    crop.allowedAspectRatios = [TOCropViewControllerAspectRatioPreset(size: TOCropViewControllerAspectRatioPreset.square, title: "1:1")]
    crop.aspectRatioLockEnabled = true
    crop.resetAspectRatioEnabled = false
    crop.aspectRatioPickerButtonHidden = true
    crop.resetButtonHidden = true
    crop.cropView.alwaysShowCroppingGrid = true
    return crop
}

struct ExistingImageCropper: UIViewControllerRepresentable {
    let image: UIImage
    let locale: Locale
    let completion: (UIImage?) -> Void
    func makeCoordinator() -> Coordinator { Coordinator(completion: completion) }
    func makeUIViewController(context: Context) -> TOCropViewController {
        let crop = squareCropController(image: image, locale: locale)
        crop.delegate = context.coordinator
        return crop
    }
    func updateUIViewController(_ controller: TOCropViewController, context: Context) {}
    final class Coordinator: NSObject, @preconcurrency TOCropViewControllerDelegate {
        let completion: (UIImage?) -> Void
        init(completion: @escaping (UIImage?) -> Void) { self.completion = completion }
        func cropViewController(_ controller: TOCropViewController, didCropTo image: UIImage, with cropRect: CGRect, angle: Int) { completion(image) }
        func cropViewController(_ controller: TOCropViewController, didFinishCancelled cancelled: Bool) { if cancelled { completion(nil) } }
    }
}
