import SwiftUI

/// Match PunchCard's UITextField, including clear button and IME composition handling.
struct ProfileNicknameField: UIViewRepresentable {
    @Binding var text: String
    @Binding var focused: Bool
    let placeholder: String
    let scale: CGFloat
    var settingsStyle = false
    var onCommit: (() -> Void)?
    func makeCoordinator() -> Coordinator { Coordinator(self) }
    func makeUIView(context: Context) -> NicknameTextField {
        let view = NicknameTextField()
        view.delegate = context.coordinator
        view.clearButtonMode = .whileEditing
        view.returnKeyType = .done
        view.textColor = .black
        view.tintColor = UIColor(red: 108/255, green: 99/255, blue: 1, alpha: 1)
        view.font = UIFont(name: "PingFangSC-Medium", size: 13*scale)
        view.accessibilityIdentifier = "info.nickname"
        view.addTarget(context.coordinator, action: #selector(Coordinator.changed(_:)), for: .editingChanged)
        return view
    }
    func updateUIView(_ view: NicknameTextField, context: Context) {
        context.coordinator.parent = self
        view.font = settingsStyle ? .systemFont(ofSize: 16*scale) : UIFont(name: "PingFangSC-Medium", size: 13*scale)
        view.textAlignment = settingsStyle ? .right : .left
        view.textColor = settingsStyle ? UIColor(white: 34/255, alpha: 0.3) : .black
        view.clearButtonMode = settingsStyle ? .never : .whileEditing
        if view.text != text, view.markedTextRange == nil { view.text = text }
        view.attributedPlaceholder = NSAttributedString(string: placeholder, attributes: [.foregroundColor: settingsStyle ? UIColor(white: 34/255, alpha: 0.3) : UIColor(white: 0.6, alpha: 1)])
        view.wantsFocus = focused
        if focused, view.window != nil, !view.isFirstResponder { view.becomeFirstResponder() }
        if !focused, view.isFirstResponder { view.resignFirstResponder() }
    }
    func sizeThatFits(_ proposal: ProposedViewSize, uiView: NicknameTextField, context: Context) -> CGSize? {
        CGSize(width: proposal.width ?? 116*scale, height: proposal.height ?? 16*scale)
    }
    final class Coordinator: NSObject, UITextFieldDelegate {
        var parent: ProfileNicknameField
        init(_ parent: ProfileNicknameField) { self.parent = parent }
        @objc func changed(_ field: UITextField) {
            guard field.markedTextRange == nil else { return }
            var result = ""
            for character in field.text ?? "" {
                guard (result+String(character)).utf16.count <= 7 else { break }
                result.append(character)
            }
            if result != field.text { field.text = result }
            if parent.text != result { parent.text = result }
        }
        func textFieldDidBeginEditing(_ textField: UITextField) { if !parent.focused { parent.focused = true } }
        func textFieldDidEndEditing(_ textField: UITextField) {
            changed(textField)
            if parent.focused { parent.focused = false }
            parent.onCommit?()
        }
        func textFieldShouldReturn(_ textField: UITextField) -> Bool { parent.focused = false; textField.resignFirstResponder(); return true }
    }
}
final class NicknameTextField: UITextField {
    var wantsFocus = false
    override func didMoveToWindow() { super.didMoveToWindow(); if window != nil, wantsFocus { becomeFirstResponder() } }
}

struct ProfileReadOnlyField: UIViewRepresentable {
    let value: String?
    let placeholder: String
    let scale: CGFloat
    func makeUIView(context: Context) -> UITextField {
        let field = UITextField()
        field.isUserInteractionEnabled = false
        field.isAccessibilityElement = false
        field.font = UIFont(name: "PingFangSC-Medium", size: 13*scale)
        field.textColor = .black
        return field
    }
    func updateUIView(_ view: UITextField, context: Context) {
        view.text = value
        view.attributedPlaceholder = NSAttributedString(string: placeholder, attributes: [.foregroundColor: UIColor(white: 0.6, alpha: 1)])
    }
    func sizeThatFits(_ proposal: ProposedViewSize, uiView: UITextField, context: Context) -> CGSize? {
        CGSize(width: proposal.width ?? 116*scale, height: proposal.height ?? 16*scale)
    }
}

struct ProfileOriginalLabel: UIViewRepresentable {
    let text: String
    let size: CGFloat
    var medium = false
    var color = UIColor(white: 0.2, alpha: 1)
    var multiline = false
    func makeUIView(context: Context) -> UILabel { UILabel() }
    func updateUIView(_ view: UILabel, context: Context) {
        view.text = text
        view.font = UIFont(name: medium ? "PingFangSC-Medium" : "PingFangSC-Regular", size: size)
        view.textColor = color
        view.numberOfLines = multiline ? 0 : 1
        view.adjustsFontSizeToFitWidth = !multiline
        view.minimumScaleFactor = 0.7
    }
    func sizeThatFits(_ proposal: ProposedViewSize, uiView: UILabel, context: Context) -> CGSize? {
        let width = proposal.width ?? uiView.intrinsicContentSize.width
        let size = uiView.sizeThatFits(CGSize(width: width, height: .greatestFiniteMagnitude))
        return CGSize(width: multiline ? width : min(width, size.width), height: proposal.height ?? ceil(size.height))
    }
}
