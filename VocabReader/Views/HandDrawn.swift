import SwiftUI

// 手绘风格组件：铅笔勾边的纸片卡片 + 马克笔荧光涂抹。
// 所有抖动都用固定的 pt 幅度（不随卡片尺寸放大），并由稳定种子驱动：
// 同一张卡片每次重绘形状一致，不同卡片之间各有差异。

// MARK: - Deterministic randomness

/// SplitMix64：轻量、可复现的伪随机数，保证同一种子画出同一形状。
struct SketchRandom {
    private var state: UInt64

    init(seed: UInt64) {
        state = seed
    }

    mutating func next() -> UInt64 {
        state &+= 0x9E37_79B9_7F4A_7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        return z ^ (z >> 31)
    }

    /// 返回 [range.lowerBound, range.upperBound] 之间的随机值。
    mutating func value(in range: ClosedRange<CGFloat>) -> CGFloat {
        let unit = CGFloat(next() >> 11) / CGFloat(1 << 53)
        return range.lowerBound + (range.upperBound - range.lowerBound) * unit
    }
}

enum SketchSeed {
    /// FNV-1a；不用 `hashValue`，因为它每次启动都会变，卡片形状会跟着跳。
    static func make(_ text: String) -> UInt64 {
        var hash: UInt64 = 0xCBF2_9CE4_8422_2325
        for byte in text.utf8 {
            hash ^= UInt64(byte)
            hash = hash &* 0x0000_0100_0000_01B3
        }
        return hash
    }

    static func make(_ id: UUID) -> UInt64 {
        make(id.uuidString)
    }
}

// MARK: - Sketch outline

/// 手绘纸片轮廓：圆角各不相同、边缘有低频起伏。
/// `pass == 0` 是闭合填充形状；`pass >= 1` 是不闭合的笔触，首尾错开并多画一小段，像笔起落的痕迹。
struct SketchOutlineShape: Shape {
    var seed: UInt64
    var pass: Int = 0
    var cornerRadius: CGFloat = 18
    var cornerVariance: CGFloat = 6
    var jitter: CGFloat = 1.3

    func path(in rect: CGRect) -> Path {
        let radii = cornerRadii(for: rect)
        let samples = Self.perimeterSamples(in: rect, radii: radii)
        guard samples.count > 2 else { return Path(roundedRect: rect, cornerRadius: cornerRadius) }

        var random = SketchRandom(seed: seed &+ UInt64(pass) &* 0x51_7CC1_B727_220A)
        let count = samples.count
        let isStroke = pass > 0

        // 起伏是“位置”的函数（三层不同方向的平面波叠加），而不是沿周长的距离：
        // 卡片变高（比如展开翻译）时，上半部分的笔触保持不动，只有新增部分跟着延伸；闭合处也天然无缝。
        let wavelengths: [CGFloat] = [190, 75, 34]
        let amplitudes: [CGFloat] = [0.75, 0.4, 0.2].map { $0 * jitter }
        let baseAngle = random.value(in: 0...(2 * .pi))
        let waves = zip(wavelengths, amplitudes).enumerated().map { index, pair in
            let angle = baseAngle + CGFloat(index) * .pi / 3
            let frequency = 2 * .pi / pair.0
            return (
                u: frequency * cos(angle),
                v: frequency * sin(angle),
                amplitude: pair.1,
                phase: random.value(in: 0...(2 * .pi))
            )
        }

        // 笔触起点只落在上边（采样从左上角之后的上边开始），且按绝对距离而不是周长比例取：
        // 卡片展开/收起时上边不变，起笔位置就不动；若按比例取，周长一变起笔点每帧乱跳，轮廓会抖。
        let topEdgeCount = max(1, Int(((rect.width - radii[0] - radii[1]) / Self.sampleStep).rounded()))
        let start = isStroke ? Int(random.value(in: 0...1) * CGFloat(min(topEdgeCount, count) - 1)) : 0
        let overshoot = isStroke ? Int(random.value(in: 10...22) / Self.sampleStep) : 0
        let drift = isStroke ? random.value(in: -1.4...1.4) : 0
        let strokeOffset = isStroke ? random.value(in: -0.6...0.6) : 0
        let total = count + overshoot
        // 收笔偏移只在最后一小段渐入，和周长无关，避免高度变化时整圈轮廓跟着蠕动。
        let driftRamp = min(total, Int(80 / Self.sampleStep))

        var path = Path()
        for step in 0...total {
            let index = (start + step) % count
            let sample = samples[index]
            let x = sample.point.x - rect.minX
            let y = sample.point.y - rect.minY
            var offset = waves.reduce(strokeOffset) { partial, wave in
                partial + wave.amplitude * sin(wave.u * x + wave.v * y + wave.phase)
            }
            if driftRamp > 0 {
                offset += drift * CGFloat(max(0, step - (total - driftRamp))) / CGFloat(driftRamp)
            }

            let point = CGPoint(
                x: sample.point.x + sample.normal.dx * offset,
                y: sample.point.y + sample.normal.dy * offset
            )
            if step == 0 {
                path.move(to: point)
            } else if !isStroke && step == count {
                break
            } else {
                path.addLine(to: point)
            }
        }
        if !isStroke {
            path.closeSubpath()
        }
        return path
    }

    /// 四个角的半径由种子决定，所有笔触共用同一组，保证填充和描边对得上。
    private func cornerRadii(for rect: CGRect) -> [CGFloat] {
        var random = SketchRandom(seed: seed)
        let limit = min(rect.width, rect.height) / 2
        return (0..<4).map { _ in
            min(limit, max(4, cornerRadius + random.value(in: -cornerVariance...cornerVariance)))
        }
    }

    // MARK: Perimeter sampling

    private static let sampleStep: CGFloat = 3

    private struct Sample {
        let point: CGPoint
        let normal: CGVector
    }

    /// 沿圆角矩形顺时针等距取点，并记录每个点的外法线，抖动沿法线方向施加。
    private static func perimeterSamples(in rect: CGRect, radii: [CGFloat]) -> [Sample] {
        let (minX, minY, maxX, maxY) = (rect.minX, rect.minY, rect.maxX, rect.maxY)
        let (tl, tr, br, bl) = (radii[0], radii[1], radii[2], radii[3])
        var samples: [Sample] = []

        func edge(from a: CGPoint, to b: CGPoint, normal: CGVector) {
            let length = hypot(b.x - a.x, b.y - a.y)
            let steps = max(1, Int((length / sampleStep).rounded()))
            for i in 0..<steps {
                let t = CGFloat(i) / CGFloat(steps)
                samples.append(Sample(
                    point: CGPoint(x: a.x + (b.x - a.x) * t, y: a.y + (b.y - a.y) * t),
                    normal: normal
                ))
            }
        }

        func arc(center: CGPoint, radius: CGFloat, from startAngle: CGFloat) {
            let steps = max(2, Int((radius * .pi / 2 / sampleStep).rounded()))
            for i in 0..<steps {
                let angle = startAngle + (.pi / 2) * CGFloat(i) / CGFloat(steps)
                let normal = CGVector(dx: cos(angle), dy: sin(angle))
                samples.append(Sample(
                    point: CGPoint(x: center.x + normal.dx * radius, y: center.y + normal.dy * radius),
                    normal: normal
                ))
            }
        }

        edge(from: CGPoint(x: minX + tl, y: minY), to: CGPoint(x: maxX - tr, y: minY), normal: CGVector(dx: 0, dy: -1))
        arc(center: CGPoint(x: maxX - tr, y: minY + tr), radius: tr, from: -.pi / 2)
        edge(from: CGPoint(x: maxX, y: minY + tr), to: CGPoint(x: maxX, y: maxY - br), normal: CGVector(dx: 1, dy: 0))
        arc(center: CGPoint(x: maxX - br, y: maxY - br), radius: br, from: 0)
        edge(from: CGPoint(x: maxX - br, y: maxY), to: CGPoint(x: minX + bl, y: maxY), normal: CGVector(dx: 0, dy: 1))
        arc(center: CGPoint(x: minX + bl, y: maxY - bl), radius: bl, from: .pi / 2)
        edge(from: CGPoint(x: minX, y: maxY - bl), to: CGPoint(x: minX, y: minY + tl), normal: CGVector(dx: -1, dy: 0))
        arc(center: CGPoint(x: minX + tl, y: minY + tl), radius: tl, from: .pi)
        return samples
    }
}

/// 阅读卡片底板：纸片填充 + 两道不完全重合的铅笔描边。
/// 首页文章卡片、收藏卡片、阅读页封面卡和段落翻译便签共用，只调整底色和圆角。
struct ReadingCardBackground: View {
    var seed: UInt64 = 0
    var fill: Color = .readingCardFill
    var cornerRadius: CGFloat = 18
    var cornerVariance: CGFloat = 6
    var lineOpacity: Double = 1

    var body: some View {
        ZStack {
            outline(pass: 0)
                .fill(fill)

            outline(pass: 1)
                .stroke(
                    Color.readingSketchLine.opacity(0.85 * lineOpacity),
                    style: StrokeStyle(lineWidth: 1.1, lineCap: .round, lineJoin: .round)
                )

            outline(pass: 2)
                .stroke(
                    Color.readingSketchLine.opacity(0.4 * lineOpacity),
                    style: StrokeStyle(lineWidth: 0.7, lineCap: .round, lineJoin: .round)
                )
        }
    }

    private func outline(pass: Int) -> SketchOutlineShape {
        SketchOutlineShape(
            seed: seed,
            pass: pass,
            cornerRadius: cornerRadius,
            cornerVariance: cornerVariance
        )
    }
}

/// 手绘分隔线：一道轻微起伏、两端略收的铅笔横线。
struct SketchDividerShape: Shape {
    var seed: UInt64

    func path(in rect: CGRect) -> Path {
        var random = SketchRandom(seed: seed)
        let phaseA = random.value(in: 0...(2 * .pi))
        let phaseB = random.value(in: 0...(2 * .pi))
        let startInset = random.value(in: 0...6)
        let endInset = random.value(in: 0...10)
        let width = max(0, rect.width - startInset - endInset)
        let steps = max(2, Int(width / 4))

        var path = Path()
        for i in 0...steps {
            let t = CGFloat(i) / CGFloat(steps)
            let x = rect.minX + startInset + width * t
            let y = rect.midY + 0.8 * sin(x / 60 + phaseA) + 0.35 * sin(x / 17 + phaseB)
            if i == 0 {
                path.move(to: CGPoint(x: x, y: y))
            } else {
                path.addLine(to: CGPoint(x: x, y: y))
            }
        }
        return path
    }
}

struct SketchDivider: View {
    var seed: UInt64

    var body: some View {
        SketchDividerShape(seed: seed)
            .stroke(
                Color.readingSketchLine.opacity(0.6),
                style: StrokeStyle(lineWidth: 1, lineCap: .round)
            )
            .frame(height: 4)
            .accessibilityHidden(true)
    }
}

// MARK: - Marker highlight

/// 马克笔涂抹形状：上下边缘轻微起伏、整体略微倾斜，左端斜切、右端圆钝，像一笔划过去。
struct MarkerSwipeShape: Shape {
    var seed: UInt64

    func path(in rect: CGRect) -> Path {
        var random = SketchRandom(seed: seed)
        let tilt = random.value(in: -1.6...1.6)
        let startCut = random.value(in: 2...5)
        let endBulge = random.value(in: 2...4.5)
        let topPhase = random.value(in: 0...(2 * .pi))
        let bottomPhase = random.value(in: 0...(2 * .pi))
        let wobble = min(1.4, rect.height * 0.12)
        let steps = max(4, Int(rect.width / 6))

        func y(_ base: CGFloat, _ t: CGFloat, _ phase: CGFloat) -> CGFloat {
            base + tilt * (t - 0.5) + wobble * sin(t * .pi * 3 + phase)
        }

        var path = Path()
        // 上缘：从左往右，左端斜切起笔。
        path.move(to: CGPoint(x: rect.minX + startCut, y: y(rect.minY, 0, topPhase)))
        for i in 1...steps {
            let t = CGFloat(i) / CGFloat(steps)
            path.addLine(to: CGPoint(x: rect.minX + startCut + (rect.width - startCut) * t, y: y(rect.minY, t, topPhase)))
        }
        // 右端：笔头收笔的圆钝端。
        path.addQuadCurve(
            to: CGPoint(x: rect.maxX - 1, y: y(rect.maxY, 1, bottomPhase)),
            control: CGPoint(x: rect.maxX + endBulge, y: rect.midY)
        )
        // 下缘：从右往左。
        for i in stride(from: steps - 1, through: 0, by: -1) {
            let t = CGFloat(i) / CGFloat(steps)
            path.addLine(to: CGPoint(x: rect.minX + (rect.width - 1) * t, y: y(rect.maxY, t, bottomPhase)))
        }
        path.closeSubpath()
        return path
    }
}

/// 逐行给文字画马克笔荧光底：每一行单独一笔，宽度贴合该行文字，换行后也自然。
/// 主笔覆盖文字下半部分，再叠一道更窄的笔触，重叠处颜色更深，模拟马克笔来回涂的质感。
struct MarkerHighlightRenderer: TextRenderer {
    var seed: UInt64
    var color: Color

    var displayPadding: EdgeInsets {
        EdgeInsets(top: 2, leading: 6, bottom: 4, trailing: 10)
    }

    func draw(layout: Text.Layout, in context: inout GraphicsContext) {
        let isDark = context.environment.colorScheme == .dark

        for (index, line) in layout.enumerated() {
            let bounds = line.typographicBounds.rect
            guard bounds.width > 0 else {
                context.draw(line)
                continue
            }
            var random = SketchRandom(seed: seed &+ UInt64(index) &* 0x9E37_79B9)
            let lineSeed = random.next()
            // 深色模式下荧光底压在字的下沿，避免橙色标题叠在琥珀色上发糊。
            let bandTop: CGFloat = isDark ? 0.62 : 0.40
            let bandHeight: CGFloat = isDark ? 0.36 : 0.52
            let mainBand = CGRect(
                x: bounds.minX - random.value(in: 2...5),
                y: bounds.minY + bounds.height * bandTop,
                width: bounds.width + random.value(in: 5...10),
                height: bounds.height * bandHeight
            )
            let overlapBand = CGRect(
                x: mainBand.minX + random.value(in: 6...16),
                y: mainBand.minY + mainBand.height * 0.22,
                width: mainBand.width * random.value(in: 0.45...0.8),
                height: mainBand.height * 0.55
            )

            var marker = context
            marker.blendMode = isDark ? .normal : .multiply
            marker.opacity = isDark ? 0.34 : 0.62
            marker.fill(MarkerSwipeShape(seed: lineSeed).path(in: mainBand), with: .color(color))
            marker.opacity = isDark ? 0.18 : 0.3
            marker.fill(MarkerSwipeShape(seed: lineSeed &+ 1).path(in: overlapBand), with: .color(color))

            context.draw(line)
        }
    }
}

extension Text {
    /// 给标题加马克笔荧光底；种子决定每一笔的倾斜和长短。
    func markerHighlight(seed: UInt64, color: Color = .readingMarker) -> some View {
        textRenderer(MarkerHighlightRenderer(seed: seed, color: color))
    }
}
