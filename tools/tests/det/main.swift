import SwiftUI
var h: UInt64 = 1469598103934665603
for seed in [UInt64(12345), 777, 9] {
    let g = WorldGen(seed: seed, infinite: seed != 9, rareChance: 0.28, genVersion: 1)
    for cx in [-40, -3, 0, 5, 77, 130] {
        let c = generateChunk(g, .overworld, cx)
        for b in c.tiles { h = (h ^ UInt64(b)) &* 1099511628211 }
    }
}
print("terrain hash", h)
print(h == 14360621207339404312 ? "PASS terrain fingerprint unchanged" : "FAIL terrain fingerprint changed: worldgen must stay the same for existing worlds")
