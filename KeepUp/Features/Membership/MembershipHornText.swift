//
//  HornTextLabel.swift
//  QuitSmoke
//
//  Created by xbingo on 2025/2/10.
//  Copyright © 2025 Xbingo. All rights reserved.
//


import SwiftUI

final class MembershipHornLabel: UILabel {
    var firstFontSize: CGFloat = 100
    var lastFontSize: CGFloat = 20
    
    // 添加渐变色属性
    var gradientColors: [UIColor] = [.systemRed, .systemOrange] {
        didSet { setNeedsDisplay() }
    }
    
    private let isAnimating = false
    private let animationOffset: CGFloat = 0

    override func drawText(in rect: CGRect) {
        guard let text = self.text else { return }
        
        let charCount = text.count
        guard charCount > 1 else {
            super.drawText(in: rect)
            return
        }
        
        // 计算缩放比例
        var scale: CGFloat = 1.0
        if adjustsFontSizeToFitWidth {
            let originalSize = calculateSize(forScale: 1.0)
            if originalSize.width > rect.width {
                let minScale = minimumScaleFactor
                let maxScale: CGFloat = 1.0
                
                // 二分查找合适的缩放比例
                var low = minScale
                var high = maxScale
                while high - low > 0.01 {
                    let mid = (low + high) / 2
                    let size = calculateSize(forScale: mid)
                    if size.width <= rect.width {
                        low = mid
                    } else {
                        high = mid
                    }
                }
                scale = low
            }
        }
        
        let context = UIGraphicsGetCurrentContext()
        context?.saveGState()
        
        let step = (lastFontSize - firstFontSize) / CGFloat(charCount - 1)
        let attributes = { [weak self] (index: Int) -> [NSAttributedString.Key: Any] in
            guard let self = self else { return [:] }
            let fontSize = (self.firstFontSize + (CGFloat(index) * step)) * scale
            let font = self.font.withSize(fontSize)
            
            // 计算渐变色
            let progress = CGFloat(index) / CGFloat(charCount - 1)
            let color = self.gradientColor(at: progress)
            
            return [
                .font: font,
                .foregroundColor: color
            ]
        }
        
        // 修改弹性效果的计算
        let bounceOffset = { [weak self] (index: Int) -> CGFloat in
            guard let self = self else { return 0 }
            // 当不在动画状态时，返回0，即没有弹性效果
            guard self.isAnimating else { return 0 }
            let phase = (CGFloat(index) / CGFloat(charCount) + self.animationOffset)
            return sin(phase * .pi * 2) * 5 * scale // 缩放弹跳幅度
        }
        
        // 计算总宽度用于居中
        let totalWidth = calculateSize(forScale: scale).width
        var xOffset = (rect.width - totalWidth) / 2 // 居中对齐
        
        for (index, char) in text.enumerated() {
            let charStr = String(char)
            let attr = NSAttributedString(string: charStr, attributes: attributes(index))
            let size = attr.size()
            let yOffset = (rect.height - size.height) / 2 + bounceOffset(index)
            attr.draw(at: CGPoint(x: xOffset, y: yOffset))
            xOffset += size.width
        }
        
        context?.restoreGState()
    }
    
    // 计算给定缩放比例下的文本大小
    private func calculateSize(forScale scale: CGFloat) -> CGSize {
        guard let text = self.text else { return .zero }
        
        let charCount = text.count
        let step = (lastFontSize - firstFontSize) / CGFloat(charCount - 1)
        var totalWidth: CGFloat = 0
        var maxHeight: CGFloat = 0
        
        for (index, char) in text.enumerated() {
            let fontSize = (firstFontSize + (CGFloat(index) * step)) * scale
            let font = self.font.withSize(fontSize)
            let charSize = String(char).size(withAttributes: [.font: font])
            totalWidth += charSize.width
            maxHeight = max(maxHeight, charSize.height)
        }
        
        return CGSize(width: totalWidth, height: maxHeight)
    }
    
    // 渐变色计算
    private func gradientColor(at progress: CGFloat) -> UIColor {
        guard gradientColors.count > 1 else {
            return gradientColors.first ?? textColor ?? .black
        }
        
        let segment = 1.0 / CGFloat(gradientColors.count - 1)
        let index = Int(progress / segment)
        let nextIndex = min(index + 1, gradientColors.count - 1)
        let segmentProgress = (progress - CGFloat(index) * segment) / segment
        
        return UIColor.interpolate(
            from: gradientColors[index],
            to: gradientColors[nextIndex],
            with: segmentProgress
        )
    }
    
    override var intrinsicContentSize: CGSize {
        guard let text = self.text, text.count > 1 else {
            return super.intrinsicContentSize
        }
        
        let step = (lastFontSize - firstFontSize) / CGFloat(text.count - 1)
        var totalWidth: CGFloat = 0
        var maxHeight: CGFloat = 0
        
        for (index, char) in text.enumerated() {
            let fontSize = firstFontSize + (CGFloat(index) * step)
            let font = self.font.withSize(fontSize)
            let charSize = String(char).size(withAttributes: [.font: font])
            totalWidth += charSize.width
            maxHeight = max(maxHeight, charSize.height)
        }
        
        return CGSize(width: totalWidth, height: maxHeight)
    }
}

// 颜色插值扩展
extension UIColor {
    static func interpolate(from: UIColor, to: UIColor, with progress: CGFloat) -> UIColor {
        var fromRed: CGFloat = 0
        var fromGreen: CGFloat = 0
        var fromBlue: CGFloat = 0
        var fromAlpha: CGFloat = 0
        from.getRed(&fromRed, green: &fromGreen, blue: &fromBlue, alpha: &fromAlpha)
        
        var toRed: CGFloat = 0
        var toGreen: CGFloat = 0
        var toBlue: CGFloat = 0
        var toAlpha: CGFloat = 0
        to.getRed(&toRed, green: &toGreen, blue: &toBlue, alpha: &toAlpha)
        
        let red = fromRed + (toRed - fromRed) * progress
        let green = fromGreen + (toGreen - fromGreen) * progress
        let blue = fromBlue + (toBlue - fromBlue) * progress
        let alpha = fromAlpha + (toAlpha - fromAlpha) * progress
        
        return UIColor(red: red, green: green, blue: blue, alpha: alpha)
    }
}

struct MembershipHornText: UIViewRepresentable {
    let text: String
    let first: CGFloat
    let last: CGFloat
    var weight: UIFont.Weight = .medium
    var colors: [UIColor] = [.black, .black]
    func makeUIView(context: Context) -> MembershipHornLabel { MembershipHornLabel() }
    func updateUIView(_ view: MembershipHornLabel, context: Context) {
        view.text = text; view.firstFontSize = first; view.lastFontSize = last
        view.font = UIFont(name: weight == .semibold ? "PingFangSC-Semibold" : "PingFangSC-Medium", size: 1) ?? .systemFont(ofSize: 1, weight: weight); view.gradientColors = colors
        view.adjustsFontSizeToFitWidth = true; view.minimumScaleFactor = 0.3
        view.invalidateIntrinsicContentSize(); view.setNeedsDisplay()
    }
    func sizeThatFits(_ proposal: ProposedViewSize, uiView: MembershipHornLabel, context: Context) -> CGSize? {
        let size = uiView.intrinsicContentSize
        return CGSize(width: min(proposal.width ?? size.width, size.width), height: proposal.height ?? size.height)
    }
}
