// Minimal stand-in for the parts of AVFoundation the game uses, so the file typechecks and the tests
// run on Linux. Signatures match the real framework; nothing here makes sound.
import Foundation

public typealias AVAudioFrameCount = UInt32
public typealias AVAudioChannelCount = UInt32
public typealias AVAudioNodeCompletionHandler = () -> Void

open class AVAudioTime {}

open class AVAudioFormat {
    public let sampleRate: Double
    public let channelCount: AVAudioChannelCount
    public init?(standardFormatWithSampleRate sampleRate: Double, channels: AVAudioChannelCount) {
        if channels == 0 { return nil }
        self.sampleRate = sampleRate
        self.channelCount = channels
    }
}

open class AVAudioBuffer {}

open class AVAudioPCMBuffer: AVAudioBuffer {
    public let format: AVAudioFormat
    public let frameCapacity: AVAudioFrameCount
    open var frameLength: AVAudioFrameCount = 0
    private var store: [UnsafeMutablePointer<Float>]
    private var table: UnsafeMutablePointer<UnsafeMutablePointer<Float>>
    public init?(pcmFormat format: AVAudioFormat, frameCapacity: AVAudioFrameCount) {
        self.format = format
        self.frameCapacity = frameCapacity
        let n = Int(format.channelCount)
        store = (0..<n).map { _ in
            let p = UnsafeMutablePointer<Float>.allocate(capacity: max(1, Int(frameCapacity)))
            p.initialize(repeating: 0, count: max(1, Int(frameCapacity)))
            return p
        }
        table = UnsafeMutablePointer<UnsafeMutablePointer<Float>>.allocate(capacity: max(1, n))
        for i in 0..<n { table[i] = store[i] }
    }
    open var floatChannelData: UnsafePointer<UnsafeMutablePointer<Float>>? { return UnsafePointer(table) }
}

open class AVAudioNode {
    public init() {}
}

open class AVAudioMixerNode: AVAudioNode {
    open var outputVolume: Float = 1
    open var volume: Float = 1
}

public struct AVAudioPlayerNodeBufferOptions: OptionSet {
    public let rawValue: UInt
    public init(rawValue: UInt) { self.rawValue = rawValue }
    public static let loops = AVAudioPlayerNodeBufferOptions(rawValue: 1)
    public static let interrupts = AVAudioPlayerNodeBufferOptions(rawValue: 2)
    public static let interruptsAtLoop = AVAudioPlayerNodeBufferOptions(rawValue: 4)
}

open class AVAudioPlayerNode: AVAudioNode {
    open var volume: Float = 1
    open var pan: Float = 0
    open var rate: Float = 1
    private(set) open var isPlaying: Bool = false
    public override init() {}
    open func scheduleBuffer(_ buffer: AVAudioPCMBuffer, at when: AVAudioTime?, options: AVAudioPlayerNodeBufferOptions = [], completionHandler: AVAudioNodeCompletionHandler? = nil) {}
    open func play() { isPlaying = true }
    open func stop() { isPlaying = false }
    open func pause() { isPlaying = false }
}

open class AVAudioUnitVarispeed: AVAudioNode {
    open var rate: Float = 1
}

open class AVAudioEngine {
    public init() {}
    public let mainMixerNode: AVAudioMixerNode = AVAudioMixerNode()
    private(set) open var isRunning: Bool = false
    open func attach(_ node: AVAudioNode) {}
    open func detach(_ node: AVAudioNode) {}
    open func connect(_ node1: AVAudioNode, to node2: AVAudioNode, format: AVAudioFormat?) {}
    open func prepare() {}
    open func start() throws { isRunning = true }
    open func stop() { isRunning = false }
    open func pause() { isRunning = false }
}

open class AVAudioSession {
    public struct Category: Hashable { public let rawValue: String; public static let ambient = Category(rawValue: "ambient") }
    public struct Mode: Hashable { public let rawValue: String; public static let `default` = Mode(rawValue: "default") }
    public struct CategoryOptions: OptionSet { public let rawValue: UInt; public init(rawValue: UInt) { self.rawValue = rawValue }; public static let mixWithOthers = CategoryOptions(rawValue: 1) }
    private static let shared = AVAudioSession()
    open class func sharedInstance() -> AVAudioSession { return shared }
    open func setCategory(_ category: Category, mode: Mode, options: CategoryOptions = []) throws {}
    open func setActive(_ active: Bool) throws {}
}
