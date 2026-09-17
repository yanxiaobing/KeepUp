import SwiftUI

struct WeightRuler: UIViewRepresentable {
    @Binding var value: Double
    var range: ClosedRange<Double> = 20...200
    var large = false
    var identifier = "weight.ruler"
    func makeUIView(context: Context) -> WeightRulerView {
        let view = WeightRulerView(range: range, large: large, initial: value)
        view.changed = { value = $0 }; view.accessibilityIdentifier = identifier
        return view
    }
    func updateUIView(_ view: WeightRulerView, context: Context) { view.changed = { value = $0 } }
}

final class WeightRulerView: UIView, UIScrollViewDelegate {
    private let range: ClosedRange<Double>
    private let large: Bool
    private let initial: Double
    private let scroll = UIScrollView()
    private let ticks = UIView()
    private let fade = CAGradientLayer()
    private var initialized = false
    var changed: ((Double) -> Void)?
    init(range: ClosedRange<Double>, large: Bool, initial: Double) {
        self.range = range; self.large = large; self.initial = initial
        super.init(frame: .zero)
        scroll.showsHorizontalScrollIndicator = false; scroll.delegate = self
        scroll.addSubview(ticks); addSubview(scroll)
        fade.colors = [UIColor.white.cgColor, UIColor.white.withAlphaComponent(0).cgColor, UIColor.white.cgColor]
        fade.locations = [0, 0.5, 1]; fade.startPoint = CGPoint(x: 0, y: 0.5); fade.endPoint = CGPoint(x: 1, y: 0.5)
        layer.addSublayer(fade)
        isAccessibilityElement = true; accessibilityTraits = .adjustable; accessibilityLabel = "kg"
    }
    required init?(coder: NSCoder) { fatalError() }
    override func layoutSubviews() {
        super.layoutSubviews(); scroll.frame = bounds; fade.frame = bounds
        guard !initialized, bounds.width > 0 else { return }; initialized = true
        let count = Int((range.upperBound-range.lowerBound)*10)
        ticks.frame = CGRect(x: 0, y: 0, width: Double(count)*10+bounds.width, height: bounds.height); scroll.contentSize = ticks.bounds.size
        for index in 0...count {
            let major = index % 10 == 0, middle = index % 5 == 0
            let height: CGFloat = large ? (major ? 50 : middle ? 30 : 15) : (major ? 32 : middle ? 24 : 14)
            let tick = UIView(frame: CGRect(x: bounds.width/2+CGFloat(index)*10, y: 0, width: 1, height: height))
            tick.backgroundColor = large ? UIColor(white: 178/255, alpha: 1) : UIColor(white: 34/255, alpha: 0.5); ticks.addSubview(tick)
            if major {
                let font: UIFont = large ? .boldSystemFont(ofSize: 18) : .systemFont(ofSize: 12)
                let labelHeight = ceil(font.lineHeight)
                let label = UILabel(frame: CGRect(x: tick.frame.minX-30, y: bounds.height-labelHeight, width: 60, height: labelHeight))
                label.text = String(format: "%.0f", range.lowerBound+Double(index)/10); label.textAlignment = .center
                label.font = font
                label.textColor = large ? UIColor(red: 105/255, green: 105/255, blue: 111/255, alpha: 1) : UIColor(white: 34/255, alpha: 0.5); ticks.addSubview(label)
            }
        }
        scroll.contentOffset.x = (min(range.upperBound, max(range.lowerBound, initial))-range.lowerBound)*100
        scrollViewDidScroll(scroll)
    }
    private var current: Double { min(range.upperBound, max(range.lowerBound, (range.lowerBound*10+scroll.contentOffset.x/10).rounded()/10)) }
    func scrollViewDidScroll(_ scrollView: UIScrollView) { accessibilityValue = String(format: "%.1f", current); changed?(current) }
    func scrollViewWillEndDragging(_ scrollView: UIScrollView, withVelocity velocity: CGPoint, targetContentOffset: UnsafeMutablePointer<CGPoint>) { targetContentOffset.pointee.x = (targetContentOffset.pointee.x/10).rounded()*10 }
    override func accessibilityIncrement() { adjust(10) }
    override func accessibilityDecrement() { adjust(-10) }
    private func adjust(_ offset: CGFloat) { scroll.setContentOffset(CGPoint(x: min(scroll.contentSize.width-bounds.width, max(0, scroll.contentOffset.x+offset)), y: 0), animated: false) }
}
