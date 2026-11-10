// Minimal SwiftUI / CoreGraphics / Combine stand-in so the game can be typechecked (and its
// logic run headless) on Linux. Only the API surface the game uses is modelled.
@_exported import Foundation

// MARK: CoreGraphics bits
public typealias CFData = Data
public final class CGImage {
    public let w: Int, h: Int
    /// premultiplied ARGB words (what the game hands over: 32-bit little-endian, alpha first)
    public let px: [UInt32]
    public init?(width: Int, height: Int, bitsPerComponent: Int, bitsPerPixel: Int, bytesPerRow: Int, space: CGColorSpace, bitmapInfo: CGBitmapInfo, provider: CGDataProvider, decode: [CGFloat]?, shouldInterpolate: Bool, intent: CGColorRenderingIntent) {
        w = width; h = height
        var a = [UInt32](repeating: 0, count: width * height)
        provider.data.withUnsafeBytes { (bp: UnsafeRawBufferPointer) in
            let n = min(a.count, bp.count / 4)
            for i in 0..<n { a[i] = bp.load(fromByteOffset: i * 4, as: UInt32.self) }
        }
        px = a
    }
    public var width: Int { return w }
    public var height: Int { return h }
}
/// A bitmap drawing context: the game draws a picture into its own bytes to read its pixels back
public enum CGInterpolationQuality: Int32 { case `default` = 0, none = 1, low = 2, high = 3, medium = 4 }
public final class CGContext {
    let buf: UnsafeMutableRawPointer?
    let w: Int, h: Int, stride: Int
    public var interpolationQuality: CGInterpolationQuality = .default
    public init?(data: UnsafeMutableRawPointer?, width: Int, height: Int, bitsPerComponent: Int, bytesPerRow: Int, space: CGColorSpace, bitmapInfo: UInt32) {
        if width <= 0 || height <= 0 { return nil }
        buf = data; w = width; h = height; stride = bytesPerRow
    }
    /// Nearest-neighbour copy of the image into the bytes (RGBA, top row first), filling the rect
    public func draw(_ image: CGImage, in rect: CGRect, byTiling: Bool = false) {
        guard let b = buf else { return }
        for y in 0..<h {
            for x in 0..<w {
                let sx = min(image.w - 1, x * image.w / max(1, w)), sy = min(image.h - 1, y * image.h / max(1, h))
                let c: UInt32 = image.px[sy * image.w + sx]
                let o = y * stride + x * 4
                b.storeBytes(of: UInt8((c >> 16) & 0xFF), toByteOffset: o, as: UInt8.self)
                b.storeBytes(of: UInt8((c >> 8) & 0xFF), toByteOffset: o + 1, as: UInt8.self)
                b.storeBytes(of: UInt8(c & 0xFF), toByteOffset: o + 2, as: UInt8.self)
                b.storeBytes(of: UInt8((c >> 24) & 0xFF), toByteOffset: o + 3, as: UInt8.self)
            }
        }
    }
}
// MARK: UIKit bits (the pasteboard and images, for copying sprites in and out)
public final class UIImage {
    public let cgImage: CGImage?
    public init(cgImage: CGImage) { self.cgImage = cgImage }
    public init?(data: Data) { return nil }
    public var size: CGSize { return CGSize(width: CGFloat(cgImage?.w ?? 0), height: CGFloat(cgImage?.h ?? 0)) }
}
public final class UIPasteboard {
    public static let general: UIPasteboard = UIPasteboard()
    public var string: String? = nil
    public var image: UIImage? = nil
    public var hasImages: Bool { return image != nil }
    public var hasStrings: Bool { return string != nil }
}
public final class CGColorSpace {}
public func CGColorSpaceCreateDeviceRGB() -> CGColorSpace { return CGColorSpace() }
public final class CGDataProvider { let data: Data; public init?(data: CFData) { self.data = data } }
public enum CGColorRenderingIntent { case defaultIntent }
public struct CGBitmapInfo: OptionSet { public let rawValue: UInt32; public init(rawValue: UInt32) { self.rawValue = rawValue }
    public static let byteOrder32Little = CGBitmapInfo(rawValue: 2 << 12) }
public enum CGImageAlphaInfo: UInt32 { case premultipliedLast = 1, premultipliedFirst = 2 }
extension CGRect { public var midX: CGFloat { origin.x + size.width / 2 }; public var midY: CGFloat { origin.y + size.height / 2 } }

// MARK: Combine bits
public protocol ObservableObject: AnyObject {}
@propertyWrapper public struct Published<Value> {
    public var wrappedValue: Value
    public init(wrappedValue: Value) { self.wrappedValue = wrappedValue }
}
public protocol Publisher { associatedtype Output }
public struct TimerPublisher: Publisher { public typealias Output = Date; public func autoconnect() -> TimerPublisher { self } }
extension Timer {
    public enum RunLoopMode2 { case common }
    public static func publish(every: Double, on: RunLoop, in: RunLoopMode2) -> TimerPublisher { TimerPublisher() }
}

// MARK: core protocols
public protocol View { associatedtype Body: View; @ViewBuilder var body: Body { get } }
extension Never: View { public typealias Body = Never; public var body: Never { fatalError() } }
public protocol PrimitiveView: View where Body == Never {}
extension PrimitiveView { public var body: Never { fatalError() } }

@resultBuilder public enum ViewBuilder {
    public static func buildExpression<V: View>(_ v: V) -> V { v }
    public static func buildBlock() -> EmptyView { EmptyView() }
    public static func buildBlock<V: View>(_ v: V) -> V { v }
    public static func buildBlock<each V: View>(_ v: repeat each V) -> TupleView<(repeat each V)> { TupleView((repeat each v)) }
    public static func buildOptional<V: View>(_ v: V?) -> OptView<V> { OptView(v: v) }
    public static func buildEither<A: View, B: View>(first: A) -> Either<A, B> { Either(a: first, b: nil) }
    public static func buildEither<A: View, B: View>(second: B) -> Either<A, B> { Either(a: nil, b: second) }
    public static func buildLimitedAvailability<V: View>(_ v: V) -> AnyView { AnyView(v) }
}
public struct TupleView<T>: PrimitiveView { public init(_ t: T) {} }
public struct OptView<V: View>: PrimitiveView { var v: V? }
public struct Either<A: View, B: View>: PrimitiveView { var a: A?; var b: B? }
public struct EmptyView: PrimitiveView { public init() {} }
public struct AnyView: PrimitiveView { public init<V: View>(_ v: V) {} }
public struct Mod<C>: PrimitiveView { init(_ c: C) {} }

// MARK: state
@propertyWrapper public struct State<Value> {
    public var wrappedValue: Value { get { v } nonmutating set {} }
    let v: Value
    public init(wrappedValue: Value) { v = wrappedValue }
    public var projectedValue: Binding<Value> { Binding(get: { v }, set: { _ in }) }
}
@propertyWrapper @dynamicMemberLookup public struct Binding<Value> {
    let g: () -> Value; let s: (Value) -> Void
    public init(get: @escaping () -> Value, set: @escaping (Value) -> Void) { g = get; s = set }
    public var wrappedValue: Value { get { g() } nonmutating set { s(newValue) } }
    public var projectedValue: Binding<Value> { self }
    public subscript<T>(dynamicMember kp: WritableKeyPath<Value, T>) -> Binding<T> {
        Binding<T>(get: { g()[keyPath: kp] }, set: { _ in })
    }
    public static func constant(_ v: Value) -> Binding<Value> { Binding(get: { v }, set: { _ in }) }
}
@propertyWrapper public struct ObservedObject<O: ObservableObject> {
    @dynamicMemberLookup public struct Wrapper {
        let o: O
        public subscript<T>(dynamicMember kp: ReferenceWritableKeyPath<O, T>) -> Binding<T> {
            Binding<T>(get: { o[keyPath: kp] }, set: { o[keyPath: kp] = $0 })
        }
    }
    public var wrappedValue: O
    public init(wrappedValue: O) { self.wrappedValue = wrappedValue }
    public var projectedValue: Wrapper { Wrapper(o: wrappedValue) }
}
@propertyWrapper public struct StateObject<O: ObservableObject> {
    public var wrappedValue: O
    public init(wrappedValue: O) { self.wrappedValue = wrappedValue }
}
@propertyWrapper public struct FocusState<Value: Hashable> {
    public struct Binding {}
    public var wrappedValue: Value { get { fatalError() } nonmutating set {} }
    public init() where Value == Bool {}
    public var projectedValue: Binding { Binding() }
}
public enum ScenePhase { case active, inactive, background }
public struct EnvironmentValues { public var scenePhase: ScenePhase = .active }
@propertyWrapper public struct Environment<Value> {
    public init(_ kp: KeyPath<EnvironmentValues, Value>) { v = EnvironmentValues()[keyPath: kp] }
    let v: Value
    public var wrappedValue: Value { v }
}

// MARK: app
public protocol Scene {}
public protocol App { associatedtype S: Scene; @SceneBuilder var body: S { get }; init() }
extension App { public static func main() {} }
@resultBuilder public enum SceneBuilder { public static func buildBlock<S: Scene>(_ s: S) -> S { s } }
public struct WindowGroup<C: View>: Scene { public init(@ViewBuilder content: () -> C) {} }

// MARK: styles & values
public protocol ShapeStyle {}
public struct Color: PrimitiveView, ShapeStyle, Hashable {
    public enum RGBColorSpace { case sRGB }
    public var r: Double, g: Double, b: Double, a: Double
    public init(_ s: RGBColorSpace, red: Double, green: Double, blue: Double, opacity: Double = 1) { r = red; g = green; b = blue; a = opacity }
    public func opacity(_ o: Double) -> Color { var c = self; c.a *= o; return c }
    public static let white = Color(.sRGB, red: 1, green: 1, blue: 1), black = Color(.sRGB, red: 0, green: 0, blue: 0)
    public static let clear = Color(.sRGB, red: 0, green: 0, blue: 0, opacity: 0), gray = Color(.sRGB, red: 0.5, green: 0.5, blue: 0.5)
    public static let yellow = Color(.sRGB, red: 1, green: 0.9, blue: 0.1), red = Color(.sRGB, red: 0.9, green: 0.15, blue: 0.1), green = Color(.sRGB, red: 0.2, green: 0.8, blue: 0.2)
    public static let cyan = Color(.sRGB, red: 0.2, green: 0.8, blue: 0.9), orange = Color(.sRGB, red: 1, green: 0.6, blue: 0.1), purple = Color(.sRGB, red: 0.6, green: 0.3, blue: 0.8), blue = Color(.sRGB, red: 0.2, green: 0.4, blue: 0.9)
}
public struct Gradient { public let colors: [Color]; public init(colors: [Color]) { self.colors = colors } }
public struct StrokeStyle { let lw: CGFloat; public init(lineWidth: CGFloat = 1, lineCap: Int = 0, dash: [CGFloat] = []) { lw = lineWidth } }
public struct Angle { let v: Double; public init(radians: Double) { v = radians }; public init(degrees: Double) { v = degrees * Double.pi / 180 }; public static func degrees(_ d: Double) -> Angle { Angle(degrees: d) }; public static func radians(_ r: Double) -> Angle { Angle(radians: r) } }
public struct Font: Hashable {
    public enum Weight: Hashable { case regular, medium, semibold, bold, heavy, black }
    public enum Design: Hashable { case `default`, monospaced, rounded, serif }
    public static func system(size: CGFloat, weight: Weight = .regular, design: Design = .default) -> Font { Font() }
    public static let caption = Font(), body = Font(), headline = Font()
}
public enum TextAlignment { case leading, center, trailing }
public struct UnitPoint { public var x: CGFloat; public var y: CGFloat; public init(x: CGFloat, y: CGFloat) { self.x = x; self.y = y }; public static let center = UnitPoint(x: 0.5, y: 0.5), top = UnitPoint(x: 0.5, y: 0), bottom = UnitPoint(x: 0.5, y: 1), leading = UnitPoint(x: 0, y: 0.5), trailing = UnitPoint(x: 1, y: 0.5), bottomLeading = UnitPoint(x: 0, y: 1), bottomTrailing = UnitPoint(x: 1, y: 1), topLeading = UnitPoint(x: 0, y: 0), topTrailing = UnitPoint(x: 1, y: 0) }
public struct Alignment { public static let leading = Alignment(), trailing = Alignment(), center = Alignment(), top = Alignment(), bottom = Alignment(), bottomTrailing = Alignment(), topLeading = Alignment(), topTrailing = Alignment(), bottomLeading = Alignment() }
public enum HorizontalAlignment { case leading, center, trailing }
public enum VerticalAlignment { case top, center, bottom }
public struct Edge { public struct Set: OptionSet { public let rawValue: Int; public init(rawValue: Int) { self.rawValue = rawValue }
    public static let top = Set(rawValue: 1), bottom = Set(rawValue: 2), leading = Set(rawValue: 4), trailing = Set(rawValue: 8), horizontal = Set(rawValue: 12), vertical = Set(rawValue: 3), all = Set(rawValue: 15) } }
public enum ColorScheme { case dark, light }
public enum CoordinateSpace { case local, global, named(String) }
public struct PlainButtonStyle {}
extension PlainButtonStyle { public static var plain: PlainButtonStyle { PlainButtonStyle() } }

// MARK: views
public struct Text: PrimitiveView {
    public init(_ s: String) {}
    public init(verbatim s: String) {}
    public func font(_ f: Font?) -> Text { self }
    public func foregroundColor(_ c: Color?) -> Text { self }
    public func bold() -> Text { self }
}
public struct Image: PrimitiveView {
    public enum Interpolation { case none, low, medium, high }
    public let cg: CGImage?
    public init(decorative: CGImage, scale: CGFloat) { cg = decorative }
    public init(systemName: String) { cg = nil }
    public func resizable() -> Image { self }
    public func interpolation(_ i: Interpolation) -> Image { self }
}
public protocol Shape: View {}
extension Shape { public var body: Never { fatalError() }
    public func fill<S: ShapeStyle>(_ s: S) -> Mod<Self> { Mod(self) }
    public func stroke<S: ShapeStyle>(_ s: S, lineWidth: CGFloat = 1) -> Mod<Self> { Mod(self) } }
public struct Rectangle: Shape { public init() {} }
public struct Circle: Shape { public init() {} }
public struct RoundedRectangle: Shape { public init(cornerRadius: CGFloat) {} }
public struct Capsule: Shape { public init() {} }
public struct Spacer: PrimitiveView { public init(minLength: CGFloat? = nil) {} }
public struct ZStack<C: View>: PrimitiveView { public init(alignment: Alignment = .center, @ViewBuilder content: () -> C) {} }
public struct VStack<C: View>: PrimitiveView { public init(alignment: HorizontalAlignment = .center, spacing: CGFloat? = nil, @ViewBuilder content: () -> C) {} }
public struct HStack<C: View>: PrimitiveView { public init(alignment: VerticalAlignment = .center, spacing: CGFloat? = nil, @ViewBuilder content: () -> C) {} }
public struct Group<C: View>: PrimitiveView { public init(@ViewBuilder content: () -> C) {} }
public enum Axis { public struct Set: OptionSet { public let rawValue: Int; public init(rawValue: Int) { self.rawValue = rawValue }; public static let horizontal = Set(rawValue: 1), vertical = Set(rawValue: 2) } }
public struct ScrollView<C: View>: PrimitiveView { public init(_ axes: Axis.Set = .vertical, showsIndicators: Bool = true, @ViewBuilder content: () -> C) {} }
public struct GridItem { public enum Size { case adaptive(minimum: CGFloat, maximum: CGFloat = .infinity), flexible(minimum: CGFloat = 10, maximum: CGFloat = .infinity), fixed(CGFloat) }
    public init(_ s: Size = .flexible(), spacing: CGFloat? = nil, alignment: Alignment? = nil) {} }
public struct LazyVGrid<C: View>: PrimitiveView { public init(columns: [GridItem], alignment: HorizontalAlignment = .center, spacing: CGFloat? = nil, @ViewBuilder content: () -> C) {} }
public struct LazyVStack<C: View>: PrimitiveView { public init(alignment: HorizontalAlignment = .center, spacing: CGFloat? = nil, @ViewBuilder content: () -> C) {} }
public struct ForEach<D, ID: Hashable, C: View>: PrimitiveView {
    public init(_ d: D, id: KeyPath<D.Element, ID>, @ViewBuilder content: @escaping (D.Element) -> C) where D: RandomAccessCollection {}
}
extension ForEach where D == Range<Int>, ID == Int { public init(_ d: Range<Int>, @ViewBuilder content: @escaping (Int) -> C) {} }
extension ForEach where D: RandomAccessCollection, D.Element: Identifiable, ID == D.Element.ID { public init(_ d: D, @ViewBuilder content: @escaping (D.Element) -> C) {} }
public struct Button<L: View>: PrimitiveView {
    public init(action: @escaping () -> Void, @ViewBuilder label: () -> L) {}
}
extension Button where L == Text { public init(_ t: String, action: @escaping () -> Void) {} }
public struct Toggle: PrimitiveView { public init(_ t: String, isOn: Binding<Bool>) {} }
public struct Slider: PrimitiveView { public init(value: Binding<Double>, in r: ClosedRange<Double>, step: Double = 0) {} }
public struct Stepper: PrimitiveView { public init(_ t: String, value: Binding<Int>, in r: ClosedRange<Int>, step: Int = 1) {} }
public struct TextField: PrimitiveView { public init(_ t: String, text: Binding<String>) {} }
public struct GeometryProxy { public var size: CGSize = .zero; public func frame(in c: CoordinateSpace) -> CGRect { .zero } }
public struct GeometryReader<C: View>: PrimitiveView { public init(@ViewBuilder content: @escaping (GeometryProxy) -> C) {} }
public enum TimelineSchedule { case animation }
public struct TimelineView<C: View>: PrimitiveView {
    public init(_ s: TimelineSchedule, @ViewBuilder content: @escaping (TimelineContext) -> C) {}
}
public struct TimelineContext { public var date: Date = Date() }
public struct Canvas: PrimitiveView {
    public init(opaque: Bool = false, renderer: @escaping (inout GraphicsContext, CGSize) -> Void) {}
}

// MARK: graphics
public struct Path {
    /// polygons in user space (rects and ellipses become polygons)
    public var polys: [[CGPoint]] = []
    var cur: [CGPoint] = []
    public init() {}
    public init(_ r: CGRect) { addRect(r) }
    public init(ellipseIn r: CGRect) { addEllipse(in: r) }
    public init(roundedRect r: CGRect, cornerRadius: CGFloat) { addRect(r) }
    mutating func flush() { if cur.count >= 2 { polys.append(cur) }; cur = [] }
    public mutating func move(to p: CGPoint) { flush(); cur = [p] }
    public mutating func addLine(to p: CGPoint) { if cur.isEmpty { cur = [p] } else { cur.append(p) } }
    public mutating func addRect(_ r: CGRect) { flush(); polys.append([CGPoint(x: r.minX, y: r.minY), CGPoint(x: r.maxX, y: r.minY), CGPoint(x: r.maxX, y: r.maxY), CGPoint(x: r.minX, y: r.maxY)]) }
    public mutating func addEllipse(in r: CGRect) {
        flush()
        var p: [CGPoint] = []
        let n = 28
        for i in 0..<n { let t = Double(i) / Double(n) * 2 * Double.pi; p.append(CGPoint(x: r.midX + r.width / 2 * cos(t), y: r.midY + r.height / 2 * sin(t))) }
        polys.append(p)
    }
    public mutating func addArc(center: CGPoint, radius: CGFloat, startAngle: Angle, endAngle: Angle, clockwise: Bool) {
        var a0 = startAngle.rad, a1 = endAngle.rad
        if !clockwise { while a1 < a0 { a1 += 2 * Double.pi } } else { while a1 > a0 { a1 -= 2 * Double.pi } }
        let n = 16
        for i in 0...n { let t = a0 + (a1 - a0) * Double(i) / Double(n); addLine(to: CGPoint(x: center.x + radius * cos(t), y: center.y + radius * sin(t))) }
    }
    public mutating func closeSubpath() { flush() }
    func all() -> [[CGPoint]] { var p = polys; if cur.count >= 2 { p.append(cur) }; return p }
}
extension Angle { var rad: Double { return v } }

/// Software render target for headless screenshots: set GraphicsContext.target before drawing
public final class RasterTarget {
    public let w: Int, h: Int
    public var rgb: [Double]
    public init(_ w: Int, _ h: Int) { self.w = w; self.h = h; rgb = [Double](repeating: 0, count: w * h * 3) }
    public func save(_ path: String) {
        var out = [UInt8](); out.reserveCapacity(w * h * 3)
        for v in rgb { out.append(UInt8(max(0, min(255, (v * 255).rounded())))) }
        _ = FileManager.default.createFile(atPath: path, contents: Data(out))
    }
}

public struct GraphicsContext {
    public static var target: RasterTarget? = nil
    public init() {}
    public struct Shading {
        var color: Color? = nil; var grad: Gradient? = nil; var p0: CGPoint = .zero; var p1: CGPoint = .zero
        public static func color(_ c: Color) -> Shading { Shading(color: c) }
        public static func linearGradient(_ g: Gradient, startPoint: CGPoint, endPoint: CGPoint) -> Shading { Shading(grad: g, p0: startPoint, p1: endPoint) }
    }
    public struct Filter { var mul: Color; public static func colorMultiply(_ c: Color) -> Filter { Filter(mul: c) } }
    public enum BlendMode { case normal, plusLighter, multiply, screen }
    public var opacity: Double = 1
    public var blendMode: BlendMode = .normal
    var tf: (Double, Double, Double, Double, Double, Double) = (1, 0, 0, 1, 0, 0)   // a b c d tx ty
    var mul: (Double, Double, Double) = (1, 1, 1)
    var clipR: (Double, Double, Double, Double)? = nil

    func apply(_ p: CGPoint) -> (Double, Double) {
        let x = Double(p.x), y = Double(p.y)
        return (tf.0 * x + tf.2 * y + tf.4, tf.1 * x + tf.3 * y + tf.5)
    }
    func blend(_ t: RasterTarget, _ x: Int, _ y: Int, _ r: Double, _ g: Double, _ b: Double, _ a: Double) {
        if a <= 0 { return }
        if let c = clipR { if Double(x) + 0.5 < c.0 || Double(x) + 0.5 > c.2 || Double(y) + 0.5 < c.1 || Double(y) + 0.5 > c.3 { return } }
        let i = (y * t.w + x) * 3
        let sr = r * mul.0, sg = g * mul.1, sb = b * mul.2
        let aa = min(1, a)
        switch blendMode {
        case .plusLighter:
            t.rgb[i] = min(1, t.rgb[i] + sr * aa); t.rgb[i + 1] = min(1, t.rgb[i + 1] + sg * aa); t.rgb[i + 2] = min(1, t.rgb[i + 2] + sb * aa)
        case .multiply:
            t.rgb[i] *= 1 - aa + aa * sr; t.rgb[i + 1] *= 1 - aa + aa * sg; t.rgb[i + 2] *= 1 - aa + aa * sb
        case .screen:
            t.rgb[i] = 1 - (1 - t.rgb[i]) * (1 - sr * aa); t.rgb[i + 1] = 1 - (1 - t.rgb[i + 1]) * (1 - sg * aa); t.rgb[i + 2] = 1 - (1 - t.rgb[i + 2]) * (1 - sb * aa)
        case .normal:
            t.rgb[i] = t.rgb[i] * (1 - aa) + sr * aa; t.rgb[i + 1] = t.rgb[i + 1] * (1 - aa) + sg * aa; t.rgb[i + 2] = t.rgb[i + 2] * (1 - aa) + sb * aa
        }
    }
    func shade(_ s: Shading, _ x: Double, _ y: Double) -> (Double, Double, Double, Double) {
        if let c = s.color { return (c.r, c.g, c.b, c.a) }
        guard let gr = s.grad, !gr.colors.isEmpty else { return (0, 0, 0, 0) }
        let a = apply(s.p0), b = apply(s.p1)
        let dx = b.0 - a.0, dy = b.1 - a.1
        let l2 = max(1e-9, dx * dx + dy * dy)
        var t = ((x - a.0) * dx + (y - a.1) * dy) / l2
        t = max(0, min(1, t))
        let n = gr.colors.count
        if n == 1 { let c = gr.colors[0]; return (c.r, c.g, c.b, c.a) }
        let f = t * Double(n - 1)
        let i = min(n - 2, Int(f)), u = f - Double(i)
        let c0 = gr.colors[i], c1 = gr.colors[i + 1]
        return (c0.r + (c1.r - c0.r) * u, c0.g + (c1.g - c0.g) * u, c0.b + (c1.b - c0.b) * u, c0.a + (c1.a - c0.a) * u)
    }
    func fillPoly(_ pts: [(Double, Double)], _ s: Shading) {
        guard let t = GraphicsContext.target, pts.count >= 3 else { return }
        var minY = Double.infinity, maxY = -Double.infinity
        for p in pts { minY = min(minY, p.1); maxY = max(maxY, p.1) }
        let y0 = max(0, Int(floor(minY))), y1 = min(t.h - 1, Int(ceil(maxY)))
        if y1 < y0 { return }
        for y in y0...y1 {
            let py = Double(y) + 0.5
            var xs: [Double] = []
            var j = pts.count - 1
            for i in 0..<pts.count {
                let a = pts[i], b = pts[j]
                if (a.1 > py) != (b.1 > py) { xs.append(a.0 + (py - a.1) * (b.0 - a.0) / (b.1 - a.1)) }
                j = i
            }
            xs.sort()
            var k = 0
            while k + 1 < xs.count {
                let xa = max(0, Int((xs[k] - 0.5).rounded(.up))), xb = min(t.w - 1, Int((xs[k + 1] - 0.5).rounded(.up)) - 1)
                if xb >= xa { for x in xa...xb { let c = shade(s, Double(x) + 0.5, py); blend(t, x, y, c.0, c.1, c.2, c.3 * opacity) } }
                k += 2
            }
        }
    }
    public func fill(_ p: Path, with s: Shading) {
        if GraphicsContext.target == nil { return }
        for poly in p.all() { fillPoly(poly.map { apply($0) }, s) }
    }
    func strokeSegs(_ p: Path, _ s: Shading, _ lw: Double) {
        if GraphicsContext.target == nil { return }
        let scale = sqrt(abs(tf.0 * tf.3 - tf.1 * tf.2))
        let hw = max(0.5, lw * scale * 0.5)
        for poly in p.all() {
            let q = poly.map { apply($0) }
            let closed = p.polys.contains { $0.count == poly.count && $0.first == poly.first } && poly.count > 2
            let n = closed ? q.count : q.count - 1
            for i in 0..<max(0, n) {
                let a = q[i], b = q[(i + 1) % q.count]
                let dx = b.0 - a.0, dy = b.1 - a.1, l = max(1e-9, sqrt(dx * dx + dy * dy))
                let nx = -dy / l * hw, ny = dx / l * hw
                fillPoly([(a.0 + nx, a.1 + ny), (b.0 + nx, b.1 + ny), (b.0 - nx, b.1 - ny), (a.0 - nx, a.1 - ny)], s)
            }
        }
    }
    public func stroke(_ p: Path, with s: Shading, lineWidth: CGFloat = 1) { strokeSegs(p, s, Double(lineWidth)) }
    public func stroke(_ p: Path, with s: Shading, style: StrokeStyle) { strokeSegs(p, s, Double(style.lw)) }
    public func draw(_ i: Image, in r: CGRect) {
        guard let t = GraphicsContext.target, let cg = i.cg, cg.w > 0, cg.h > 0 else { return }
        let corners = [apply(CGPoint(x: r.minX, y: r.minY)), apply(CGPoint(x: r.maxX, y: r.minY)), apply(CGPoint(x: r.maxX, y: r.maxY)), apply(CGPoint(x: r.minX, y: r.maxY))]
        var x0 = Double.infinity, x1 = -Double.infinity, y0 = Double.infinity, y1 = -Double.infinity
        for c in corners { x0 = min(x0, c.0); x1 = max(x1, c.0); y0 = min(y0, c.1); y1 = max(y1, c.1) }
        // inverse of the full transform (user rect -> device)
        let det = tf.0 * tf.3 - tf.1 * tf.2
        if abs(det) < 1e-12 { return }
        let ia = tf.3 / det, ib = -tf.1 / det, ic = -tf.2 / det, id = tf.0 / det
        let ix0 = max(0, Int(floor(x0))), ix1 = min(t.w - 1, Int(ceil(x1))), iy0 = max(0, Int(floor(y0))), iy1 = min(t.h - 1, Int(ceil(y1)))
        if ix1 < ix0 || iy1 < iy0 { return }
        let rw = Double(r.width), rh = Double(r.height)
        if abs(rw) < 1e-9 || abs(rh) < 1e-9 { return }
        for y in iy0...iy1 {
            for x in ix0...ix1 {
                let dx = Double(x) + 0.5 - tf.4, dy = Double(y) + 0.5 - tf.5
                let ux = ia * dx + ic * dy, uy = ib * dx + id * dy
                let fu = (ux - Double(r.minX)) / rw, fv = (uy - Double(r.minY)) / rh
                if fu < 0 || fu >= 1 || fv < 0 || fv >= 1 { continue }
                let sx = min(cg.w - 1, Int(fu * Double(cg.w))), sy = min(cg.h - 1, Int(fv * Double(cg.h)))
                let p = cg.px[sy * cg.w + sx]
                let a = Double(p >> 24) / 255.0
                if a <= 0 { continue }
                // premultiplied -> straight
                let rr = Double((p >> 16) & 255) / 255.0 / a, gg = Double((p >> 8) & 255) / 255.0 / a, bb = Double(p & 255) / 255.0 / a
                blend(t, x, y, min(1, rr), min(1, gg), min(1, bb), a * opacity)
            }
        }
    }
    public func draw(_ t: Text, at p: CGPoint) {}
    public mutating func addFilter(_ f: Filter) { mul = (mul.0 * f.mul.r, mul.1 * f.mul.g, mul.2 * f.mul.b) }
    public mutating func translateBy(x: CGFloat, y: CGFloat) { tf.4 += tf.0 * Double(x) + tf.2 * Double(y); tf.5 += tf.1 * Double(x) + tf.3 * Double(y) }
    public mutating func scaleBy(x: CGFloat, y: CGFloat) { tf.0 *= Double(x); tf.1 *= Double(x); tf.2 *= Double(y); tf.3 *= Double(y) }
    public mutating func rotate(by a: Angle) {
        let c = cos(a.rad), s = sin(a.rad)
        let a0 = tf.0, b0 = tf.1, c0 = tf.2, d0 = tf.3
        tf.0 = a0 * c + c0 * s; tf.1 = b0 * c + d0 * s; tf.2 = -a0 * s + c0 * c; tf.3 = -b0 * s + d0 * c
    }
    public mutating func clip(to p: Path) {
        var x0 = Double.infinity, x1 = -Double.infinity, y0 = Double.infinity, y1 = -Double.infinity
        for poly in p.all() { for q in poly { let d = apply(q); x0 = min(x0, d.0); x1 = max(x1, d.0); y0 = min(y0, d.1); y1 = max(y1, d.1) } }
        if let c = clipR { x0 = max(x0, c.0); y0 = max(y0, c.1); x1 = min(x1, c.2); y1 = min(y1, c.3) }
        clipR = (x0, y0, x1, y1)
    }
}

// MARK: gestures
public protocol Gesture {}
public struct DragGesture: Gesture {
    public struct Value { public var location: CGPoint = .zero; public var startLocation: CGPoint = .zero; public var translation: CGSize = .zero }
    public init(minimumDistance: CGFloat = 10, coordinateSpace: CoordinateSpace = .local) {}
    public func onChanged(_ f: @escaping (Value) -> Void) -> DragGesture { self }
    public func onEnded(_ f: @escaping (Value) -> Void) -> DragGesture { self }
}
public struct LongPressGesture: Gesture {
    public init(minimumDuration: Double = 0.5) {}
    public func onEnded(_ f: @escaping (Bool) -> Void) -> LongPressGesture { self }
}
public struct TapGesture: Gesture {
    public init(count: Int = 1) {}
    public func onEnded(_ f: @escaping () -> Void) -> TapGesture { self }
}

// MARK: keys
public struct KeyEquivalent: Equatable { let c: Int
    public static let leftArrow = KeyEquivalent(c: 1), rightArrow = KeyEquivalent(c: 2), upArrow = KeyEquivalent(c: 3), downArrow = KeyEquivalent(c: 4), space = KeyEquivalent(c: 5), escape = KeyEquivalent(c: 6), tab = KeyEquivalent(c: 7) }
public struct KeyPress {
    public enum Result { case handled, ignored }
    public struct Phases: OptionSet { public let rawValue: Int; public init(rawValue: Int) { self.rawValue = rawValue }; public static let down = Phases(rawValue: 1), up = Phases(rawValue: 2), `repeat` = Phases(rawValue: 4) }
    public var phase: Phases = .down
    public var key: KeyEquivalent = .space
    public var characters: String = ""
}

// MARK: preferences
public protocol PreferenceKey { associatedtype Value; static var defaultValue: Value { get }; static func reduce(value: inout Value, nextValue: () -> Value) }

// MARK: modifiers
public protocol ViewModifier { associatedtype Body: View; typealias Content = _ModContent; @ViewBuilder func body(content: Content) -> Body }
public struct _ModContent: PrimitiveView {}

extension View {
    public func font(_ f: Font?) -> Mod<Self> { Mod(self) }
    public func foregroundColor(_ c: Color?) -> Mod<Self> { Mod(self) }
    public func opacity(_ o: Double) -> Mod<Self> { Mod(self) }
    public func frame(width: CGFloat? = nil, height: CGFloat? = nil, alignment: Alignment = .center) -> Mod<Self> { Mod(self) }
    public func frame(minWidth: CGFloat? = nil, idealWidth: CGFloat? = nil, maxWidth: CGFloat? = nil, minHeight: CGFloat? = nil, idealHeight: CGFloat? = nil, maxHeight: CGFloat? = nil, alignment: Alignment = .center) -> Mod<Self> { Mod(self) }
    public func padding(_ l: CGFloat? = nil) -> Mod<Self> { Mod(self) }
    public func padding(_ e: Edge.Set, _ l: CGFloat? = nil) -> Mod<Self> { Mod(self) }
    public func background<B: View>(_ b: B) -> Mod<Self> { Mod(self) }
    public func overlay<B: View>(_ b: B, alignment: Alignment = .center) -> Mod<Self> { Mod(self) }
    public func shadow(color: Color, radius: CGFloat, x: CGFloat = 0, y: CGFloat = 0) -> Mod<Self> { Mod(self) }
    public func ignoresSafeArea() -> Mod<Self> { Mod(self) }
    public func clipped() -> Mod<Self> { Mod(self) }
    public func offset(_ s: CGSize) -> Mod<Self> { Mod(self) }
    public func offset(x: CGFloat = 0, y: CGFloat = 0) -> Mod<Self> { Mod(self) }
    public func position(x: CGFloat, y: CGFloat) -> Mod<Self> { Mod(self) }
    public func contentShape<S: Shape>(_ s: S) -> Mod<Self> { Mod(self) }
    public func gesture<G: Gesture>(_ g: G) -> Mod<Self> { Mod(self) }
    public func simultaneousGesture<G: Gesture>(_ g: G) -> Mod<Self> { Mod(self) }
    public func highPriorityGesture<G: Gesture>(_ g: G) -> Mod<Self> { Mod(self) }
    public func onTapGesture(count: Int = 1, perform: @escaping () -> Void) -> Mod<Self> { Mod(self) }
    public func onHover(perform: @escaping (Bool) -> Void) -> Mod<Self> { Mod(self) }
    public func onLongPressGesture(minimumDuration: Double = 0.5, perform: @escaping () -> Void) -> Mod<Self> { Mod(self) }
    public func onAppear(perform: (() -> Void)? = nil) -> Mod<Self> { Mod(self) }
    public func onDisappear(perform: (() -> Void)? = nil) -> Mod<Self> { Mod(self) }
    public func onReceive<P: Publisher>(_ p: P, perform: @escaping (P.Output) -> Void) -> Mod<Self> { Mod(self) }
    public func onChange<V: Equatable>(of v: V, perform: @escaping (V) -> Void) -> Mod<Self> { Mod(self) }
    public func onChange<V: Equatable>(of v: V, _ f: @escaping (V, V) -> Void) -> Mod<Self> { Mod(self) }
    public func modifier<M: ViewModifier>(_ m: M) -> Mod<Self> { Mod(self) }
    public func buttonStyle(_ s: PlainButtonStyle) -> Mod<Self> { Mod(self) }
    public func lineLimit(_ n: Int?) -> Mod<Self> { Mod(self) }
    public func multilineTextAlignment(_ a: TextAlignment) -> Mod<Self> { Mod(self) }
    public func minimumScaleFactor(_ f: CGFloat) -> Mod<Self> { Mod(self) }
    public func rotationEffect(_ a: Angle) -> Mod<Self> { Mod(self) }
    public func scaleEffect(_ s: CGFloat, anchor: UnitPoint = .center) -> Mod<Self> { Mod(self) }
    public func preferredColorScheme(_ c: ColorScheme?) -> Mod<Self> { Mod(self) }
    public func focusable(_ b: Bool = true) -> Mod<Self> { Mod(self) }
    public func focused(_ b: FocusState<Bool>.Binding) -> Mod<Self> { Mod(self) }
    public func focusEffectDisabled(_ b: Bool = true) -> Mod<Self> { Mod(self) }
    public func onKeyPress(phases: KeyPress.Phases, action: @escaping (KeyPress) -> KeyPress.Result) -> Mod<Self> { Mod(self) }
    public func coordinateSpace(name: String) -> Mod<Self> { Mod(self) }
    public func allowsHitTesting(_ b: Bool) -> Mod<Self> { Mod(self) }
    public func zIndex(_ z: Double) -> Mod<Self> { Mod(self) }
    public func cornerRadius(_ r: CGFloat) -> Mod<Self> { Mod(self) }
    public func disabled(_ b: Bool) -> Mod<Self> { Mod(self) }
    public func id<H: Hashable>(_ h: H) -> Mod<Self> { Mod(self) }
    public func preference<K: PreferenceKey>(key: K.Type, value: K.Value) -> Mod<Self> { Mod(self) }
    public func onPreferenceChange<K: PreferenceKey>(_ k: K.Type, perform: @escaping (K.Value) -> Void) -> Mod<Self> where K.Value: Equatable { Mod(self) }
    public func transition(_ t: Int) -> Mod<Self> { Mod(self) }
}
