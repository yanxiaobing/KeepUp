import SwiftUI
import UIKit

struct CalendarCardMenuAction {
    enum Kind: String {
        case delete, checkIn, reminder
        var image: String {
            switch self {
            case .delete: "homepage_btn_longpress_delete"
            case .checkIn: "homepage_btn_longpress_add"
            case .reminder: "homepage_btn_longpress_clock"
            }
        }
        var titleKey: String {
            switch self {
            case .delete: "action.delete"
            case .checkIn: "action.checkIn"
            case .reminder: "reminder.title"
            }
        }
    }
    let kind: Kind
    var confirmation: String? = nil
    let perform: () -> Void
}

/// UIKit provides the original 0.5s gesture, window-wide blur, and card snapshot.
/// The overlay receives gestures without turning a held card into a tap on release.
struct CalendarInteractiveCard<Content: View>: View {
    let identifier: String
    let label: String
    let actions: [CalendarCardMenuAction]
    let tap: () -> Void
    @ViewBuilder let content: () -> Content
    @Environment(\.locale) private var locale
    var body: some View {
        content().accessibilityHidden(true)
            .overlay { CalendarCardTouchSurface(identifier: identifier, label: label, actions: actions, locale: locale, tap: tap) }
    }
}

private struct CalendarCardTouchSurface: UIViewRepresentable {
    let identifier: String
    let label: String
    let actions: [CalendarCardMenuAction]
    let locale: Locale
    let tap: () -> Void
    func makeUIView(context: Context) -> CalendarCardTouchView { CalendarCardTouchView() }
    func updateUIView(_ view: CalendarCardTouchView, context: Context) {
        view.accessibilityIdentifier = identifier
        view.accessibilityLabel = label
        view.actions = actions; view.locale = locale; view.tap = tap
        view.accessibilityCustomActions = [UIAccessibilityCustomAction(name: localized("calendar.cardActions", locale), actionHandler: { [weak view] _ in
            view?.showMenu(); return true
        })]
    }
    static func dismantleUIView(_ view: CalendarCardTouchView, coordinator: ()) { view.menu?.dismiss(animated: false) }
}

private final class CalendarCardTouchView: UIView {
    var actions: [CalendarCardMenuAction] = []
    var locale = Locale.current
    var tap: () -> Void = {}
    weak var menu: CalendarRadialMenu?
    override init(frame: CGRect) {
        super.init(frame: frame)
        backgroundColor = .clear
        isAccessibilityElement = true
        accessibilityTraits = .button
        let hold = UILongPressGestureRecognizer(target: self, action: #selector(held(_:)))
        hold.minimumPressDuration = 0.5
        let click = UITapGestureRecognizer(target: self, action: #selector(clicked))
        click.require(toFail: hold)
        addGestureRecognizer(hold); addGestureRecognizer(click)
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
    override func accessibilityActivate() -> Bool { tap(); return true }
    @objc private func clicked() { tap() }
    @objc private func held(_ gesture: UILongPressGestureRecognizer) {
        if gesture.state == .began { showMenu() }
    }
    func showMenu() {
        guard menu == nil, let window, !actions.isEmpty else { return }
        let cardFrame = convert(bounds, to: window)
        let renderer = UIGraphicsImageRenderer(size: bounds.size)
        let snapshot = renderer.image { _ in
            window.drawHierarchy(in: CGRect(x: -cardFrame.minX, y: -cardFrame.minY, width: window.bounds.width, height: window.bounds.height), afterScreenUpdates: false)
        }
        let overlay = CalendarRadialMenu(frame: window.bounds, cardFrame: cardFrame, image: snapshot, actions: actions, locale: locale)
        menu = overlay
        window.addSubview(overlay)
        overlay.show()
    }
}

private final class CalendarRadialMenu: UIView {
    private let blur = UIVisualEffectView(effect: UIBlurEffect(style: .light))
    private var buttons: [UIButton] = []
    private var destinations: [CGPoint] = []
    private let origin: CGPoint
    private let locale: Locale
    private var closing = false
    private var confirmationView: UIView?

    init(frame: CGRect, cardFrame: CGRect, image: UIImage, actions: [CalendarCardMenuAction], locale: Locale) {
        origin = CGPoint(x: cardFrame.midX, y: cardFrame.midY)
        self.locale = locale
        super.init(frame: frame)
        accessibilityIdentifier = "calendar.cardMenu"
        accessibilityViewIsModal = true
        autoresizingMask = [.flexibleWidth, .flexibleHeight]
        blur.frame = bounds; blur.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        blur.backgroundColor = UIColor(white: 0.97, alpha: 0.2)
        blur.isUserInteractionEnabled = false
        addSubview(blur)
        let background = UIButton(frame: bounds)
        background.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        background.accessibilityIdentifier = "calendar.menu.dismiss"
        background.accessibilityLabel = localized("action.close", locale)
        background.addAction(UIAction { [weak self] _ in self?.dismiss() }, for: .touchUpInside)
        addSubview(background)

        // The source uses a 120pt radius, 30° spacing, and reverses actions on the right.
        let side = abs(origin.x - bounds.midX) < 2 ? 1 : (origin.x < bounds.midX ? 0 : 2)
        let ordered = side == 2 ? Array(actions.reversed()) : actions
        let start = side == 0 ? 0.0 : (side == 1 ? -15.0 : -30.0) * Double(actions.count-1)
        for (index, action) in ordered.enumerated() {
            let angle = (start + 30 * Double(index)) * .pi / 180
            let point = CGPoint(x: origin.x + sin(angle)*120, y: origin.y - cos(angle)*120)
            // Keep controls reachable for a card partially scrolled under the calendar.
            destinations.append(CGPoint(x: min(max(31, point.x), bounds.width-31), y: max(62, point.y)))
            let button = UIButton(frame: CGRect(x: 0, y: 0, width: 54, height: 54))
            button.center = origin
            button.setImage(UIImage(named: action.kind.image), for: .normal)
            button.layer.cornerRadius = 27; button.clipsToBounds = true
            button.accessibilityLabel = localized(action.kind.titleKey, locale)
            button.accessibilityIdentifier = "calendar.menu.\(action.kind.rawValue)"
            button.addAction(UIAction { [weak self] _ in
                guard let self, !self.closing else { return }
                if let message = action.confirmation { self.confirm(message: message, action: action.perform) }
                else { self.dismiss(completion: action.perform) }
            }, for: .touchUpInside)
            addSubview(button); buttons.append(button)
        }
        let card = UIImageView(image: image)
        card.frame = cardFrame
        card.isAccessibilityElement = false
        addSubview(card)
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
    func show() {
        blur.alpha = 0
        buttons.forEach { $0.alpha = 0 }
        UIView.animate(withDuration: UIAccessibility.isReduceMotionEnabled ? 0 : 0.25) {
            self.blur.alpha = 1
            for (index, button) in self.buttons.enumerated() { button.center = self.destinations[index]; button.alpha = 1 }
        } completion: { _ in UIAccessibility.post(notification: .screenChanged, argument: self.buttons.first) }
    }
    func dismiss(animated: Bool = true, completion: (() -> Void)? = nil) {
        guard !closing else { return }
        closing = true
        UIView.animate(withDuration: animated && !UIAccessibility.isReduceMotionEnabled ? 0.15 : 0) {
            self.alpha = 0
        } completion: { _ in
            self.removeFromSuperview()
            UIAccessibility.post(notification: .screenChanged, argument: nil)
            completion?()
        }
    }
    override func accessibilityPerformEscape() -> Bool {
        if confirmationView != nil { closeConfirmation() } else { dismiss() }
        return true
    }
    private func closeConfirmation() {
        confirmationView?.removeFromSuperview(); confirmationView = nil
        UIAccessibility.post(notification: .screenChanged, argument: buttons.first)
    }
    private func confirm(message: String, action: @escaping () -> Void) {
        guard confirmationView == nil else { return }
        let shade = UIView(frame: bounds)
        shade.backgroundColor = UIColor(white: 0, alpha: 0.6)
        shade.accessibilityIdentifier = "calendar.deleteConfirmation"
        shade.isAccessibilityElement = false
        shade.accessibilityViewIsModal = true
        let backdrop = UIButton(frame: shade.bounds)
        backdrop.accessibilityLabel = localized("action.cancel", locale)
        backdrop.addAction(UIAction { [weak self] _ in self?.closeConfirmation() }, for: .touchUpInside)
        shade.addSubview(backdrop)
        let width = bounds.width - 80*bounds.width/375
        let label = UILabel()
        label.text = message; label.font = .systemFont(ofSize: 15)
        label.textColor = UIColor(red: 72/255, green: 72/255, blue: 75/255, alpha: 1)
        label.numberOfLines = 0; label.textAlignment = .center
        let textWidth = width - 40*bounds.width/375
        let height = label.sizeThatFits(CGSize(width: textWidth, height: .greatestFiniteMagnitude)).height
        let panel = UIView(frame: CGRect(x: (bounds.width-width)/2, y: (bounds.height-height-117)/2, width: width, height: height+117))
        panel.backgroundColor = .white; panel.layer.cornerRadius = 15; panel.clipsToBounds = true
        label.frame = CGRect(x: (width-textWidth)/2, y: 40, width: textWidth, height: height)
        panel.addSubview(label)
        let line = UIView(frame: CGRect(x: 0, y: height+69, width: width, height: 1))
        line.backgroundColor = UIColor(white: 220/255, alpha: 1); panel.addSubview(line)
        for (index, title) in [localized("calendar.deleteCancel", locale), localized("action.delete", locale)].enumerated() {
            let button = UIButton(frame: CGRect(x: CGFloat(index)*width/2, y: height+70, width: width/2, height: 47))
            button.setTitle(title, for: .normal); button.titleLabel?.font = .systemFont(ofSize: 15)
            button.setTitleColor(index == 0 ? UIColor(white: 193/255, alpha: 1) : UIColor(red: 245/255, green: 208/255, blue: 57/255, alpha: 1), for: .normal)
            button.accessibilityIdentifier = index == 0 ? "calendar.deleteCancel" : "calendar.confirmDelete"
            button.addAction(UIAction { [weak self] _ in
                if index == 0 { self?.closeConfirmation() }
                else { self?.dismiss(completion: action) }
            }, for: .touchUpInside)
            panel.addSubview(button)
        }
        let divider = UIView(frame: CGRect(x: width/2-0.5, y: height+70, width: 1, height: 47))
        divider.backgroundColor = line.backgroundColor; panel.addSubview(divider)
        shade.addSubview(panel); addSubview(shade); confirmationView = shade
        shade.alpha = 0
        if !UIAccessibility.isReduceMotionEnabled { panel.transform = CGAffineTransform(scaleX: 0.85, y: 0.85) }
        UIView.animate(withDuration: UIAccessibility.isReduceMotionEnabled ? 0 : 0.25) {
            shade.alpha = 1; panel.transform = .identity
        } completion: { _ in UIAccessibility.post(notification: .screenChanged, argument: label) }
    }
}
