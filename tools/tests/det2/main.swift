import SwiftUI
// standard-world generation fingerprint for every older generator version (worlds saved with them keep generating the same), finite and infinite, many chunks
for ver in [1, 2, 3, 4] {
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
    let wants: [UInt64] = [17484840331411981850, 12337572311508444499, 6561527433802086430, 17650721157646406198]
    let want: UInt64 = wants[ver - 1]
    print(h == want ? "PASS v\(ver) fingerprint unchanged" : "FAIL v\(ver) fingerprint changed: worldgen must stay the same for existing worlds")
}

// version 5 has no villages, and nothing about it changes the older versions
do {
    var any4 = 0, any5 = 0
    for seed in [UInt64(12345), 777, 9, 4242] {
        any4 += WorldGen(seed: seed, infinite: true, rareChance: 0.28, genVersion: 4).villages(overlapping: -4000, 4000).count
        any5 += WorldGen(seed: seed, infinite: true, rareChance: 0.28, genVersion: 5).villages(overlapping: -4000, 4000).count
    }
    print(any4 > 0 && any5 == 0 ? "PASS version 4 keeps its villages (\(any4)), version 5 has none" : "FAIL village counts v4 \(any4) v5 \(any5)")
}
