import SwiftUI
import Foundation
// The combat stick's dial, idle and aiming (only the painted parts can be drawn here; the real touch
// handling needs an iPad)
let W = 204, H = 204
let outDir = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "/tmp/stickshots"
try? FileManager.default.createDirectory(atPath: outDir, withIntermediateDirectories: true)
func dial(_ name: String, _ tx: Double, _ ty: Double, _ down: Bool, _ manual: Bool) {
    let t = RasterTarget(W, H)
    GraphicsContext.target = t
    var ctx = GraphicsContext()
    fillRect(&ctx, mkRect(0, 0, Double(W), Double(H)), Color(hex: 0x6AA0D8))
    CombatStickView.paint(&ctx, CGSize(width: W, height: H), 68, tx, ty, down, manual)
    GraphicsContext.target = nil
    t.save(outDir + "/" + name + ".rgb")
    print("rendered", name)
}
dial("1_idle", 0, 0, false, false)
dial("2_assist", 8, 4, true, false)
dial("3_up_right", 44, -44, true, true)
dial("4_left", -66, 6, true, true)
