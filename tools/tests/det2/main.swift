import SwiftUI
// standard-world generation fingerprint for both generator versions, finite and infinite, many chunks
for ver in [1, 2] {
    var h: UInt64 = 1469598103934665603
    for seed in [UInt64(12345), 777, 9, 4242] {
        let g = WorldGen(seed: seed, infinite: seed != 9, rareChance: 0.28, genVersion: ver)
        var cxs: [Int] = [-200, -69, -40, -3, 0, 5, 37, 63, 77, 130, 256]
        cxs.append(floorDiv(g.portalX, chunkW))
        for cx in cxs {
            let c = generateChunk(g, .overworld, cx)
            for b in c.tiles { h = (h ^ UInt64(b)) &* 1099511628211 }
            for b in c.walls { h = (h ^ UInt64(b)) &* 1099511628211 }
        }
        h = (h ^ UInt64(bitPattern: Int64(g.portalX))) &* 1099511628211
    }
    print("v\(ver) standard hash", h)
    let want: UInt64 = ver == 1 ? 17484840331411981850 : 12337572311508444499
    print(h == want ? "PASS v\(ver) fingerprint unchanged" : "FAIL v\(ver) fingerprint changed: worldgen must stay the same for existing worlds")
}
