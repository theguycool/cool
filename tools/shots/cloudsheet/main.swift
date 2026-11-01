import SwiftUI
import Foundation
// A contact sheet of every cloud template, one row per size class
let W = 960, H = 640
let outDir = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "/tmp/cloudsheet"
try? FileManager.default.createDirectory(atPath: outDir, withIntermediateDirectories: true)
let t = RasterTarget(W, H)
GraphicsContext.target = t
var ctx = GraphicsContext()
fillRect(&ctx, mkRect(0, 0, Double(W), Double(H)), Color(hex: 0x5AA0E0))
let art = CloudArt.shared
var y = 6.0
for (ci, ids) in art.classes.enumerated() {
    var x = 6.0
    var rowH = 0.0
    for id in ids {
        let b = art.shapes[id]
        let s = ci == 4 ? 1.0 : (ci == 2 ? 1.5 : 2.0)
        if x + Double(b.w) * s > Double(W) { x = 6.0; y += rowH + 6.0; rowH = 0 }
        ctx.draw(art.images[id], in: mkRect(x, y, Double(b.w) * s, Double(b.h) * s))
        x += Double(b.w) * s + 10.0
        rowH = max(rowH, Double(b.h) * s)
    }
    y += rowH + 14.0
}
GraphicsContext.target = nil
t.save(outDir + "/sheet.rgb")
print("rendered sheet")
