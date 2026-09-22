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


@MainActor private func squareCropController(image: UIImage, locale: Locale) -> TOCropViewController {
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

/// The system owns the bottom presentation and dismissal; actions run after dismissal.
struct AvatarSourceSheet: View {
    let options: [AvatarSheetOption]
    let select: (String?) -> Void
    @ScaledMetric private var rowHeight = 52.0

    var body: some View {
        VStack(spacing: 12) {
            VStack(spacing: 0) {
                ForEach(Array(options.enumerated()), id: \.offset) { index, option in
                    if index > 0 { Divider() }
                    Button { select(option.id) } label: {
                        Text(LocalizedStringKey(option.titleKey))
                            .frame(maxWidth: .infinity, minHeight: rowHeight).contentShape(Rectangle())
                    }.accessibilityIdentifier(option.id)
                }
            }.background(.background, in: RoundedRectangle(cornerRadius: 14))
            Button(role: .cancel) { select(nil) } label: {
                Text("action.cancel").frame(maxWidth: .infinity, minHeight: rowHeight).contentShape(Rectangle())
            }
            .background(.background, in: RoundedRectangle(cornerRadius: 14))
            .accessibilityIdentifier("info.avatar.cancel")
        }
        .buttonStyle(.plain).font(.body).foregroundStyle(.primary)
        .padding(.horizontal, 16).padding(.top, 24).padding(.bottom, 12)
        .presentationDetents([.height(rowHeight * Double(options.count + 1) + 49)])
        .presentationDragIndicator(.visible)
        .presentationBackground(Color(uiColor: .secondarySystemBackground))
    }
}

struct AvatarSheetOption: Identifiable {
    let id: String
    let titleKey: String
}
