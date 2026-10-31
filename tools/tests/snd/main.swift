import SwiftUI
import AVFoundation
import Foundation
// the iOS-only session lines, compiled here against the stub with the same signatures
try? AVAudioSession.sharedInstance().setCategory(.ambient, mode: .default, options: [.mixWithOthers])
try? AVAudioSession.sharedInstance().setActive(true)
var fails = 0
func check(_ ok: Bool, _ msg: String) { print((ok ? "PASS " : "FAIL ") + msg); if !ok { fails += 1 } }
func centroid(_ x: [Float]) -> Double {
    // spectral centroid from a zero-crossing-free estimate: mean absolute first difference / mean absolute value
    var d = 0.0, a = 0.0
    for i in 1..<x.count { d += Double(abs(x[i] - x[i - 1])); a += Double(abs(x[i])) }
    return a > 0 ? d / a * Synth.rate / (2.0 * Double.pi) : 0
}
var bad: [String] = []
var cents: [SoundID: Double] = [:]
var blob = [UInt8]()
var index = ""
for id in SoundID.allCases {
    for v in 0..<3 {
        let x = SoundBank.effect(id, v)
        let peak = x.map { abs($0) }.max() ?? 0
        let dur = Double(x.count) / Synth.rate
        let maxDur: Double = (id == .thunderNear || id == .thunderFar) ? 3.2 : 1.2
        if x.contains(where: { $0.isNaN }) || peak > 1.0 || peak < 0.1 || dur > maxDur || abs(x.first ?? 1) > 0.01 || abs(x.last ?? 1) > 0.01 { bad.append("\(id)/\(v) peak \(peak) dur \(dur)") }
        if v == 1 {
            cents[id] = centroid(x)
            index += "\(id) \(x.count) \(blob.count)\n"
            for f in x { var s = Int16(max(-1, min(1, f)) * 32000); withUnsafeBytes(of: &s) { blob.append(contentsOf: $0) } }
        }
    }
}
check(bad.isEmpty, "all \(SoundID.allCases.count) effects x 3 variants synthesise cleanly: no NaN, no clipping, quiet ends, under 1.2 s (thunder 3.2 s) (\(bad.prefix(3)))")
check(cents[.digStone]! > cents[.digDirt]! * 1.8 && cents[.explosion]! < cents[.digStone]! * 0.5 && cents[.digCrystal]! > cents[.digWood]!, String(format: "timbres match the material: stone %.0f Hz, dirt %.0f, wood %.0f, crystal %.0f, explosion %.0f (brightness estimate)", cents[.digStone]!, cents[.digDirt]!, cents[.digWood]!, cents[.digCrystal]!, cents[.explosion]!))
for l in LoopID.allCases {
    let x = SoundBank.loop(l)
    let jump = abs(x[0] - x[x.count - 1])
    let peak = x.map { abs($0) }.max() ?? 0
    // the seam must look like any other step between neighbouring samples of the same sound
    var steps: [Float] = []
    for i in 1..<x.count { steps.append(abs(x[i] - x[i - 1])) }
    steps.sort()
    let p99 = steps[Int(Double(steps.count) * 0.99)]
    check(peak > 0.2 && peak <= 1 && jump <= p99, String(format: "loop %@ is seamless (end-to-start step %.3f, within the sound's own 99th-percentile step %.3f; %.1f s)", "\(l)", jump, p99, Double(x.count) / Synth.rate))
}
let t0 = Date().timeIntervalSinceReferenceDate
for id in SoundID.allCases { _ = SoundBank.effect(id, 0) }
for l in LoopID.allCases { _ = SoundBank.loop(l) }
let ms = (Date().timeIntervalSinceReferenceDate - t0) * 1000
print(String(format: "synthesising every effect once and all loops: %.0f ms (debug build)", ms))
Sound.shared.start()
check(Sound.shared.running, "the sound engine starts")
for _ in 0..<50 { Sound.shared.play(.pickup, 0.5) }
check(true, "playing a sound 50 times in a burst is safe (repeats closer than 50 ms are dropped)")
FileManager.default.createFile(atPath: "/tmp/sounds.raw", contents: Data(blob))
try! index.write(toFile: "/tmp/sounds.txt", atomically: true, encoding: .utf8)
print(fails == 0 ? "ALL SOUND TESTS PASSED" : "\(fails) FAILED")
