import SwiftUI

enum ProfileMetric: String, CaseIterable, Identifiable {
    case year, height, weight
    var id: String { rawValue }
    var titleKey: String { "info.\(rawValue)" }
    var placeholderKey: String { "info.\(rawValue)Placeholder" }
    var range: ClosedRange<Double> { switch self { case .year: 1940...2019; case .height: 100...220; case .weight: 20...200 } }
    var increment: Double { self == .year ? 1 : 0.1 }
    func value(in profile: UserProfile) -> Double { switch self { case .year: Double(profile.year); case .height: profile.height; case .weight: profile.weight } }
    func set(_ value: Double, in profile: inout UserProfile) {
        switch self { case .year: profile.year = Int(value.rounded()); case .height: profile.height = (value*10).rounded()/10; case .weight: profile.weight = (value*10).rounded()/10 }
    }
    func display(_ value: Double, locale: Locale) -> String {
        switch self { case .year: String(Int(value.rounded())) + (locale.identifier.hasPrefix("zh") ? " 年" : "")
        case .height: String(format: "%.1f cm", value); case .weight: String(format: "%.1f kg", value) }
    }
}

struct ProfileRulerOverlay: View {
    @Environment(\.locale) private var locale
    let metric: ProfileMetric
    let scale: CGFloat
    let completion: (Double?) -> Void
    @State private var value: Double
    init(metric: ProfileMetric, value: Double, scale: CGFloat, completion: @escaping (Double?) -> Void) {
        self.metric = metric; self.scale = scale; self.completion = completion; _value = State(initialValue: value)
    }
    var body: some View {
        GeometryReader { geometry in
            ZStack(alignment: .bottom) {
                Color.black.opacity(0.5).onTapGesture { completion(nil) }.accessibilityIdentifier("info.ruler.cancel")
                VStack(spacing: 8*scale) {
                    ZStack(alignment: .bottom) {
                        RoundedRectangle(cornerRadius: 10*scale).fill(.white)
                        RulerScroll(metric: metric, value: $value, scale: scale).frame(height: 60*scale).padding(.bottom, 15*scale)
                        Image("me_body_talk").resizable().frame(width: 62*scale, height: 47*scale)
                            .overlay(alignment: .top) { Text(metric.display(value, locale: locale)).font(.custom("PingFangSC-Regular", fixedSize: 12*scale)).frame(height: 32*scale) }
                            .padding(.bottom, 76*scale).allowsHitTesting(false)
                    }.frame(height: 130*scale)
                    Button("info.rulerConfirm") { completion(value) }.font(.custom("PingFangSC-Regular", fixedSize: 17*scale)).foregroundStyle(Color(hex: 0x333333).opacity(0.72))
                        .frame(maxWidth: .infinity).frame(height: 56*scale).background(.white, in: RoundedRectangle(cornerRadius: 10*scale))
                        .accessibilityIdentifier("info.ruler.confirm")
                }.padding(.horizontal, 15*scale).padding(.bottom, max(geometry.safeAreaInsets.bottom, 34))
            }
        }.accessibilityElement(children: .contain)
    }
}

private struct RulerScroll: UIViewRepresentable {
    let metric: ProfileMetric
    @Binding var value: Double
    let scale: CGFloat
    func makeUIView(context: Context) -> RulerView {
        let view = RulerView(metric: metric, scale: scale, initial: value)
        view.changed = { value = $0 }
        view.accessibilityLabel = metric.rawValue
        view.accessibilityIdentifier = "info.ruler"
        return view
    }
    func updateUIView(_ uiView: RulerView, context: Context) {}
}

private final class RulerView: UIView, UIScrollViewDelegate {
    let metric: ProfileMetric
    let scale: CGFloat
    let initial: Double
    var changed: ((Double) -> Void)?
    private let scroll = UIScrollView()
    private let ticks = UIView()
    private let fade = CAGradientLayer()
    private var initialized = false
    init(metric: ProfileMetric, scale: CGFloat, initial: Double) {
        self.metric = metric; self.scale = scale; self.initial = initial
        super.init(frame: .zero)
        scroll.showsHorizontalScrollIndicator = false; scroll.delegate = self
        scroll.addSubview(ticks); addSubview(scroll)
        fade.colors = [UIColor.white.cgColor, UIColor.white.withAlphaComponent(0).cgColor, UIColor.white.cgColor]
        fade.locations = [0, 0.5, 1]; fade.startPoint = CGPoint(x: 0, y: 0.5); fade.endPoint = CGPoint(x: 1, y: 0.5)
        layer.addSublayer(fade)
        isAccessibilityElement = true; accessibilityTraits = .adjustable
    }
    required init?(coder: NSCoder) { fatalError() }
    override func layoutSubviews() {
        super.layoutSubviews()
        scroll.frame = bounds; fade.frame = bounds
        guard bounds.width > 0, !initialized else { return }
        initialized = true
        let count = Int(((metric.range.upperBound-metric.range.lowerBound)/metric.increment).rounded())
        ticks.frame = CGRect(x: 0, y: 0, width: CGFloat(count)*10+bounds.width, height: bounds.height)
        scroll.contentSize = ticks.bounds.size
        for index in 0...count {
            let major = index % 10 == 0, middle = index % 5 == 0
            let tick = UIView(frame: CGRect(x: bounds.width/2+CGFloat(index)*10, y: 0, width: 1, height: (major ? 32 : middle ? 24 : 14)*scale))
            tick.backgroundColor = UIColor(white: 0.2, alpha: major || middle ? 1 : 0.3); ticks.addSubview(tick)
            if major {
                let label = UILabel(frame: CGRect(x: tick.frame.minX-35, y: 35*scale, width: 70, height: 20*scale))
                label.text = String(format: "%.0f", metric.range.lowerBound+Double(index)*metric.increment)
                label.textAlignment = .center; label.font = UIFont(name: "PingFangSC-Regular", size: 12*scale); label.textColor = UIColor(white: 0.2, alpha: 1)
                let measured = (label.text! as NSString).size(withAttributes: [.font: label.font!])
                label.frame = CGRect(x: tick.frame.minX-ceil(measured.width)/2, y: bounds.height-ceil(measured.height), width: ceil(measured.width), height: ceil(measured.height))
                ticks.addSubview(label)
            }
        }
        scroll.contentOffset.x = (min(metric.range.upperBound, max(metric.range.lowerBound, initial))-metric.range.lowerBound)/metric.increment*10
    }
    private var currentValue: Double {
        min(metric.range.upperBound, max(metric.range.lowerBound, metric.range.lowerBound+(scroll.contentOffset.x/10).rounded()*metric.increment))
    }
    func scrollViewDidScroll(_ scrollView: UIScrollView) {
        let value = currentValue
        accessibilityValue = String(format: metric == .year ? "%.0f" : "%.1f", value)
        changed?(value)
    }
    func scrollViewWillEndDragging(_ scrollView: UIScrollView, withVelocity velocity: CGPoint, targetContentOffset: UnsafeMutablePointer<CGPoint>) {
        targetContentOffset.pointee.x = (targetContentOffset.pointee.x/10).rounded()*10
    }
    override func accessibilityIncrement() { adjust(1) }
    override func accessibilityDecrement() { adjust(-1) }
    private func adjust(_ amount: CGFloat) {
        scroll.setContentOffset(CGPoint(x: min(scroll.contentSize.width-bounds.width, max(0, scroll.contentOffset.x+amount*10)), y: 0), animated: false)
    }
}

extension Color {
    init(hex: UInt32) { self.init(.sRGB, red: Double((hex >> 16)&255)/255, green: Double((hex >> 8)&255)/255, blue: Double(hex&255)/255, opacity: 1) }
}
