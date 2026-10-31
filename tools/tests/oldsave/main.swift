import SwiftUI
import Foundation
var fails = 0
var passes = 0
func check(_ ok: Bool, _ msg: String) { print((ok ? "PASS " : "FAIL ") + msg); if ok { passes += 1 } else { fails += 1 } }
// saves written by the version before the mines update (tools/fixtures)
let fixtures: String = ProcessInfo.processInfo.environment["PR_FIXTURES"] ?? "tools/fixtures"
for name in ["standard", "flat"] {
    let data = try! Data(contentsOf: URL(fileURLWithPath: fixtures + "/oldsave3_\(name).json"))
    let s = try! JSONDecoder().decode(SaveData.self, from: data)
    let g = Game.load(s, settings: Settings())
    g.viewW = 1100; g.viewH = 800
    check(g.gen.genVersion == 3, "\(name): a world saved by the previous version keeps its generator version (\(g.gen.genVersion))")
    check(g.inv.total(.spear(.iron)) == 1 && g.inv.total(.hammer(.gold)) == 1 && g.inv.total(.ammo(.bullet)) == 30 && g.inv.armor[3]?.item == .gear(.headlamp), "\(name): its spear, hammer, bullets and headlamp load")
    if let i = g.inv.slots.firstIndex(where: { $0?.item == .gun(.pistol) }) { check(g.inv.slots[i]!.extra == 4, "\(name): the pistol keeps its 4 loaded shots") }
    let px = Int(floor(g.pb.x))
    check((0..<5).allSatisfy { g.world.tile(px + 3 + $0, Int(g.pb.y) - 3) == .brick }, "\(name): what the player built is still there")
    let mines = (-10...10).compactMap { g.gen.mineSite(cell: $0) }
    check(!mines.isEmpty && mines.allSatisfy { $0.plan == nil }, "\(name): its mines keep their original layout (\(mines.count) near spawn)")
    let info = (try? String(contentsOfFile: fixtures + "/oldsave3_\(name).mine", encoding: .utf8)) ?? "none"
    if info != "none" {
        let xy = info.split(separator: " ")[0].split(separator: ",").map { Int($0)! }
        g.world.loadAround(centerX: xy[0], radius: 2)
        check(g.world.tile(xy[0], xy[1]) == .chest && g.world.chestItems(xy[0], xy[1]).isEmpty, "\(name): the mine chest emptied before the update stays empty (\(info))")
    }
    // chests never opened in those older mines now roll from the new loot tables
    if let m = mines.first(where: { $0.cell != 0 }) {
        let f = m.levels.last!
        let loot = generateChestLoot(g.gen, .overworld, m.x + 2 + m.right.last! - 1, f - 1)
        let table = Set((MineLoot.common + MineLoot.useful + MineLoot.exceptional).map { $0.item })
        check(!loot.isEmpty && loot.allSatisfy { table.contains($0.item) }, "\(name): unopened chests in its old mines hold loot from the new rarity tables")
    }
    // the new weapons work in an old world
    g.inv.slots[0] = Stack(item: .knife(.iron), count: 1)
    g.setSel(0)
    g.monstersEnabled = false
    let z = g.addMob(.zombie, g.pb.x + 1.5, g.pb.y)
    z.maxHP = 999; z.hp = 999
    g.mobGrid.rebuild(g.mobs)
    g.aimX = z.b.x; g.aimY = z.b.cy; g.aimValid = true
    g.swingEmpty(.knife(.iron))
    check(z.hp < 999, "\(name): a new knife works in the old world")
    let again = try! JSONEncoder().encode(g.makeSave())
    let back = Game.load(try! JSONDecoder().decode(SaveData.self, from: again), settings: Settings())
    check(back.gen.genVersion == 3 && back.inv.total(.knife(.iron)) == 1, "\(name): it saves again with the new items and stays a version-3 world")
}
print("\(passes) passed, \(fails) failed")
print(fails == 0 ? "ALL OLD-SAVE TESTS PASSED" : "SOME OLD-SAVE TESTS FAILED")
