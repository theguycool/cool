import SwiftUI
import Foundation
// Writes the game's own creature frames and block art as raw pixels, for tools/art/sheets.py to lay
// out as labelled sheets (and to compare an older version of the game with the present one):
//   <out>/manifest.txt   one line a picture: kind name, width, height, frames, blocks per art pixel
//   <out>/<name>.rgba    the frames one after another, 4 bytes a pixel (red, green, blue, alpha)
let outDir = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "/tmp/artdump"
try? FileManager.default.createDirectory(atPath: outDir, withIntermediateDirectories: true)
ModStore.overrideDir = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("prartdump-" + String(Int.random(in: 1000...999999)), isDirectory: true)
ModRuntime.activate([], world: nil)

var manifest: [String] = []
func put(_ kind: String, _ name: String, _ frames: [PixelBuf], _ scale: Double) {
    guard let f0 = frames.first else { return }
    var out = [UInt8]()
    out.reserveCapacity(f0.w * f0.h * 4 * frames.count)
    for f in frames {
        for i in 0..<(f0.w * f0.h) {
            let c: UInt32 = i < f.px.count ? f.px[i] : 0
            out.append(UInt8((c >> 16) & 255)); out.append(UInt8((c >> 8) & 255)); out.append(UInt8(c & 255)); out.append(UInt8(c >> 24))
        }
    }
    _ = FileManager.default.createFile(atPath: outDir + "/" + name + ".rgba", contents: Data(out))
    manifest.append([kind, name, String(f0.w), String(f0.h), String(frames.count), String(scale)].joined(separator: " "))
}

for k in MobKind.allCases where k != .custom && k != .villager {
    var variants: [Int] = [0]
    if k == .zombie { variants = [0, 1, 2] }
    if k == .sheep || k == .wolf { variants = [0, 1] }
    for v in variants {
        let l: CreatureLook = creatureLook(k, v)
        put("mob", String(describing: k) + (v > 0 ? "_" + String(v) : ""), l.frames, l.scale)
    }
}
let pl: CreatureLook = playerLook(PlayerLookChoice(Settings()))
put("mob", "player", pl.frames, pl.scale)
for t in Tile.allCases where !t.isMod && t != .air {
    let b: PixelBuf = tileBuf(t)
    put("tile", String(describing: t), [b], 1.0 / Double(b.w))
}
try? manifest.joined(separator: "\n").write(toFile: outDir + "/manifest.txt", atomically: true, encoding: .utf8)
print("wrote", manifest.count, "pictures to", outDir)
