import SwiftUI
import Foundation
// The combat stick: dead zone, aim by direction for every kind of weapon, release, and working at the
// same time as walking and jumping. The stick view itself is only compile-checked and painted here;
// real touches need an iPad.

var fails = 0
var passes = 0
func check(_ ok: Bool, _ msg: String) {
    print((ok ? "PASS " : "FAIL ") + msg)
    if ok { passes += 1 } else { fails += 1 }
}
func near(_ a: Double, _ b: Double, _ eps: Double = 0.001) -> Bool { return abs(a - b) <= eps }

func arena(_ seed: UInt64 = 4242) -> Game {
    let g = Game(mode: .survival, infinite: true, seed: seed, settings: Settings())
    g.viewW = 1100; g.viewH = 800
    g.monstersEnabled = false
    g.pauseSpawning = true
    g.mobs.removeAll()
    let w = g.world
    let x0 = Int(g.pb.x) - 40
    w.loadAround(centerX: Int(g.pb.x), radius: 5)
    for x in x0...(x0 + 80) {
        for y in 40..<100 { w.set(x, y, .air) }
        for y in 100..<106 { w.set(x, y, .stone) }
    }
    g.pb.x = Double(x0 + 40) + 0.5; g.pb.y = 100; g.pb.vx = 0; g.pb.vy = 0
    g.maxHP = 400; g.hp = 400
    g.light.valid = false
    g.timeOfDay = 0.25
    g.pauseMobs = true
    return g
}
/// one frame the way the game loop runs it
func frame(_ g: Game) { g.applyActButton(); g.tick(1.0 / 60.0) }
func frames(_ g: Game, _ n: Int) { for _ in 0..<n { frame(g) } }
func put(_ g: Game, _ k: MobKind, _ dx: Double, dy: Double = 0) -> Mob {
    let m = g.addMob(k, g.pb.x + dx, 100 + dy)
    m.b.vx = 0; m.b.vy = 0
    g.mobGrid.rebuild(g.mobs)
    return m
}
func hold(_ g: Game, _ item: Item, extra: Int = 0) {
    g.inv.slots[0] = Stack(item: item, count: item.maxStack > 1 ? 20 : 1, extra: extra)
    g.setSel(0)
}
func release() { actState.stickReleased() }
func resetStick() { actState.stickReleased(); actState.was = false }

// ---------------------------------------------------------------- dead zone, power, normalising
print("== stick maths")
do {
    resetStick()
    actState.stickAt(0.1, 0)
    check(actState.held && !actState.manual && near(actState.power, 0.1), "a thumb inside the dead zone holds the attack but leaves the aim to the game")
    actState.stickAt(0.3, 0)
    check(actState.manual && near(actState.dirX, 1) && near(actState.dirY, 0), "a thumb past the dead zone aims by hand")
    actState.stickAt(0.2, 0)
    check(actState.manual, "drifting back a little keeps the hand aim (no flicker at the edge)")
    actState.stickAt(0.15, 0)
    check(!actState.manual, "coming well back inside the dead zone hands the aim back")
    actState.stickAt(0.2, 0)
    check(!actState.manual, "and creeping out again does not re-engage until the thumb is properly out")
    actState.stickAt(0.8, 0.8)
    check(near(actState.dirX, 0.7071, 0.001) && near(actState.dirY, 0.7071, 0.001) && near(actState.power, 1.0), "a diagonal is a unit direction at full power (not 1.41 times longer)")
    actState.stickAt(9, 0)
    check(near(actState.power, 1.0) && near(actState.dirX, 1), "pushing past the rim counts as the rim")
    release()
    check(!actState.held && !actState.manual && actState.power == 0, "letting go clears everything")
}

// ---------------------------------------------------------------- melee, all directions
print("== melee")
func swingTest(_ name: String, mobDX: Double, mobDY: Double, kind: MobKind = .zombie, stick: (Double, Double), expectHit: Bool) {
    resetStick()
    let g = arena()
    hold(g, .sword(.iron))
    g.facing = 1
    let m = put(g, kind, mobDX, dy: mobDY)
    if mobDY < -0.5 { m.b.y = 100 + mobDY }
    let h0 = m.hp
    actState.stickAt(stick.0, stick.1)
    frames(g, 8)
    release()
    frame(g)
    check((m.hp < h0) == expectHit, "\(name): \(expectHit ? "hits" : "misses") (hp \(Int(h0)) -> \(Int(m.hp)))")
}
swingTest("sword aimed right at a zombie on the right", mobDX: 1.8, mobDY: 0, stick: (1, 0), expectHit: true)
swingTest("sword aimed left at a zombie on the right", mobDX: 1.8, mobDY: 0, stick: (-1, 0), expectHit: false)
swingTest("sword aimed left at a zombie on the left", mobDX: -1.8, mobDY: 0, stick: (-1, 0), expectHit: true)
swingTest("sword aimed up at a bat overhead", mobDX: 0.4, mobDY: -3.4, kind: .bat, stick: (0, -1), expectHit: true)
swingTest("sword aimed straight ahead does not hit the bat overhead", mobDX: 0.4, mobDY: -3.4, kind: .bat, stick: (1, 0), expectHit: false)
swingTest("sword aimed diagonally up-right at a bat up and to the right", mobDX: 1.8, mobDY: -2.2, kind: .bat, stick: (1, -1), expectHit: true)
do {
    // down: a zombie standing in a pit below
    resetStick()
    let g = arena()
    let px = Int(floor(g.pb.x))
    for x in (px + 1)...(px + 3) { for y in 100..<103 { g.world.set(x, y, .air) } }
    hold(g, .sword(.iron))
    let z = g.addMob(.zombie, Double(px) + 2.2, 103)
    z.b.vx = 0; z.b.vy = 0
    g.mobGrid.rebuild(g.mobs)
    let h0 = z.hp
    actState.stickAt(0.8, 1)
    frames(g, 8)
    release(); frame(g)
    check(z.hp < h0, "sword aimed down-right reaches a zombie in a pit")
}
do {
    // up turns the player nowhere: facing is kept
    resetStick()
    let g = arena()
    hold(g, .sword(.iron))
    g.facing = -1
    actState.stickAt(0, -1)
    frames(g, 6)
    check(g.facing == -1, "swinging straight up keeps the way the player faces")
    release(); frame(g)
    actState.stickAt(1, 0)
    frames(g, 3)
    check(g.facing == 1, "aiming right turns the player right")
    release(); frame(g)
}
do {
    // holding keeps swinging, letting go stops
    resetStick()
    let g = arena()
    hold(g, .sword(.iron))
    let z = put(g, .zombie, 1.8)
    z.maxHP = 1000; z.hp = 1000
    actState.stickAt(1, 0)
    frames(g, 120)
    let hitsHeld = 1000 - z.hp
    release()
    frames(g, 5)
    let hpAfter = z.hp
    frames(g, 60)
    check(hitsHeld > 20 && z.hp == hpAfter, "holding the stick keeps swinging (\(Int(hitsHeld)) damage in 2 s); letting go stops at once")
}
do {
    // inside the dead zone the game picks the target (the action-button behaviour)
    resetStick()
    let g = arena()
    hold(g, .sword(.iron))
    let z = put(g, .zombie, -1.8)
    g.facing = 1
    let h0 = z.hp
    actState.stickAt(0.05, 0)
    frames(g, 8)
    release(); frame(g)
    check(z.hp < h0, "thumb in the middle: auto-aim turns and hits the zombie behind")
}

// ---------------------------------------------------------------- ranged
print("== ranged")
do {
    resetStick()
    let g = arena()
    hold(g, .bow)
    _ = g.inv.add(.ammo(.arrow), 40)
    actState.stickAt(0.7, -0.7)
    frames(g, 50)
    release(); frame(g)
    let p = g.projectiles.first { $0.kind == .arrow }
    check(p != nil && p!.vx > 0 && p!.vy < 0 && abs(abs(p!.vy) - abs(p!.vx)) < abs(p!.vx) * 0.25, "a bow drawn with the thumb up-right looses its arrow up and to the right (vx \(p.map { Int($0.vx) } ?? 0), vy \(p.map { Int($0.vy) } ?? 0))")
    // charging only while held; release fires
    resetStick()
    let g2 = arena()
    hold(g2, .bow)
    _ = g2.inv.add(.ammo(.arrow), 40)
    actState.stickAt(-1, 0)
    frames(g2, 20)
    let charging: Bool = g2.bowCharge > 0.1
    let before = g2.projectiles.filter { $0.kind == .arrow }.count
    release(); frame(g2)
    let after = g2.projectiles.filter { $0.kind == .arrow }.count
    check(charging && before == 0 && after == 1, "the bow charges while the stick is held and fires on release (charging \(charging), shots \(before) -> \(after))")
    let q = g2.projectiles.first { $0.kind == .arrow }
    check(q != nil && q!.vx < 0, "aiming left shoots left")
}
do {
    resetStick()
    let g = arena()
    hold(g, .gun(.pistol), extra: GunType.pistol.magazine)
    _ = g.inv.add(.ammo(.bullet), 40)
    actState.stickAt(0, -1)
    frames(g, 4)
    release(); frame(g)
    let b = g.projectiles.first { $0.fromPlayer }
    check(b != nil && abs(b!.vx) < abs(b!.vy) * 0.2 && b!.vy < 0, "a pistol fired with the stick straight up shoots straight up")
}
do {
    // a sling lands further the further the thumb is pushed
    var landings: [Double] = []
    for power in [0.4, 1.0] {
        resetStick()
        let g = arena()
        hold(g, .sling)
        _ = g.inv.add(.block(.stone), 20)
        actState.stickAt(power, -0.0)
        frames(g, 3)
        landings.append(g.aimX - g.pb.x)
        release(); frame(g)
    }
    check(landings[1] > landings[0] + 3.0, "the sling's aim point goes further out with the thumb (\(String(format: "%.1f", landings[0])) vs \(String(format: "%.1f", landings[1])) blocks)")
}

// ---------------------------------------------------------------- tools and blocks
print("== tools and blocks")
do {
    resetStick()
    let g = arena()
    let px = Int(floor(g.pb.x))
    // a dirt block up and to the right, reachable
    g.world.set(px + 2, 97, .dirt)
    hold(g, .tool(.pickaxe, .iron))
    actState.stickAt(0.7, -0.7)
    frames(g, 4)
    let tx = Int(floor(g.aimX)), ty = Int(floor(g.aimY))
    check(tx == px + 2 && ty == 97, "a pickaxe aims at the first block along the stick (aimed \(tx - px), \(ty))")
    frames(g, 90)
    release(); frame(g)
    check(g.world.tile(px + 2, 97) != .dirt, "holding the stick up-right digs that block out")
}
do {
    resetStick()
    let g = arena()
    let px = Int(floor(g.pb.x))
    hold(g, .tool(.pickaxe, .iron))
    actState.stickAt(0, 1)
    frames(g, 100)
    release(); frame(g)
    check(g.world.tile(px, 100) == .air, "the stick pointing straight down digs the floor under the player")
}
do {
    // a creature in the line of the stick is fought instead of the block behind it
    resetStick()
    let g = arena()
    let px = Int(floor(g.pb.x))
    g.world.set(px + 4, 99, .dirt)
    hold(g, .tool(.pickaxe, .iron))
    let z = put(g, .zombie, 1.9)
    let h0 = z.hp
    actState.stickAt(1, -0.15)
    frames(g, 20)
    release(); frame(g)
    check(z.hp < h0 && g.world.tile(px + 4, 99) == .dirt, "a zombie in the way is struck, and the block behind it is left alone")
}
do {
    resetStick()
    let g = arena()
    let px = Int(floor(g.pb.x))
    g.world.set(px + 3, 100 - 1, .stone)
    hold(g, .block(.planks))
    actState.stickAt(1, 0)
    frames(g, 10)
    release(); frame(g)
    check(g.aimX >= Double(px) + 1.0 && g.aimX < Double(px + 3), "blocks aim for the empty cell in front of the first solid block along the stick")
}
do {
    // the old attack button still works from the keyboard and without a direction
    resetStick()
    let g = arena()
    hold(g, .sword(.iron))
    let z = put(g, .zombie, 1.8)
    let h0 = z.hp
    actState.held = true
    frames(g, 8)
    resetStick(); frame(g)
    check(z.hp < h0 && !actState.manual, "the F key still attacks with the old auto-aim")
}

// ---------------------------------------------------------------- multi-touch combinations
print("== at the same time")
do {
    // walk right and attack right at once
    resetStick()
    let g = arena()
    hold(g, .sword(.iron))
    let z = put(g, .zombie, 4.5)
    z.maxHP = 1000; z.hp = 1000
    let x0 = g.pb.x
    g.stick = 1.0
    actState.stickAt(1, 0)
    frames(g, 60)
    let moved = g.pb.x - x0
    check(moved > 1.5 && z.hp < 1000, "walking and swinging at the same time: moved \(String(format: "%.1f", moved)) blocks and hit the zombie")
    // release the attack: walking carries on
    release()
    let x1 = g.pb.x
    frames(g, 30)
    check(g.stick == 1.0 && g.pb.x - x1 > 0.8, "letting go of the attack does not stop the walk")
    // release the walk: the attack carries on
    g.stick = 1.0
    actState.stickAt(1, 0)
    frames(g, 5)
    g.stick = 0
    let hp0 = z.hp
    frames(g, 40)
    check(actState.held && z.hp <= hp0, "letting go of the walk does not stop the attack")
    release(); frame(g)
}
do {
    // jump and attack together
    resetStick()
    let g = arena()
    hold(g, .sword(.iron))
    let z = put(g, .zombie, 1.8)
    z.maxHP = 1000; z.hp = 1000
    g.jumpHeld = true
    actState.stickAt(1, 0)
    var peak = 100.0
    for _ in 0..<40 { frame(g); peak = min(peak, g.pb.y) }
    check(peak < 99.0 && z.hp < 1000, "jumping and swinging at the same time: rose \(String(format: "%.1f", 100 - peak)) blocks and hit")
    g.jumpHeld = false
    release(); frame(g)
}
do {
    // diagonal aim while moving, ranged while moving
    resetStick()
    let g = arena()
    hold(g, .bow)
    _ = g.inv.add(.ammo(.arrow), 40)
    g.stick = -1.0
    let x0 = g.pb.x
    actState.stickAt(0.7, -0.7)
    frames(g, 50)
    release(); frame(g)
    let moved = g.pb.x - x0
    let p = g.projectiles.first { $0.kind == .arrow }
    check(moved < -1.0 && p != nil && p!.vx > 0 && p!.vy < 0, "walking left while aiming a bow up-right: moved \(String(format: "%.1f", moved)), arrow goes the aimed way")
    g.stick = 0
}
do {
    // switching weapons while holding does not fire the new weapon in the same instant
    resetStick()
    let g = arena()
    hold(g, .tool(.pickaxe, .iron))
    g.inv.slots[1] = Stack(item: .sword(.iron), count: 1, extra: 0)
    let z = put(g, .zombie, 1.8)
    z.maxHP = 1000; z.hp = 1000
    actState.stickAt(0, 0)
    frames(g, 3)
    g.setSel(1)
    let before = z.hp
    frame(g)
    check(z.hp == before, "switching to a sword while holding does not swing it the same frame")
    frames(g, 45)
    check(z.hp < before, "...and it swings once the last weapon's cooldown is over, with the stick still held")
    release(); frame(g)
}
do {
    // opening the bag mid-attack drops everything: nothing is stuck when it closes
    resetStick()
    let g = arena()
    hold(g, .sword(.iron))
    g.stick = 0.8; g.jumpHeld = true
    actState.stickAt(1, 0)
    frames(g, 5)
    g.showInventory = true
    g.updateInputGate()
    check(!actState.held && !actState.manual && g.stick == 0 && !g.jumpHeld && !g.useHeld, "opening the inventory releases the walk, the jump and the attack")
    g.showInventory = false
    g.updateInputGate()
    let z = put(g, .zombie, 1.8)
    let h0 = z.hp
    frames(g, 30)
    check(z.hp == h0 && !actState.held, "after closing it nothing attacks by itself")
    // the same for pause and death
    actState.stickAt(1, 0)
    g.paused = true
    g.updateInputGate()
    check(!actState.held, "pausing releases the attack")
    g.paused = false
    g.updateInputGate()
}
do {
    // a finger on the world and the stick together: the finger aims, the stick keeps the action going
    resetStick()
    let g = arena()
    hold(g, .sword(.iron))
    let z = put(g, .zombie, 2.0)
    z.maxHP = 1000; z.hp = 1000
    g.pointerDown(g.pb.x + 2.0, z.b.cy)
    actState.stickAt(-1, 0)
    frames(g, 20)
    check(near(g.aimX, g.pb.x + 2.0, 0.01) && z.hp < 1000, "a finger on the world keeps its aim while the stick is held")
    g.pointerUp()
    check(g.useHeld, "lifting the world finger while the stick is held keeps the attack going")
    release(); frame(g)
    check(!g.useHeld, "...and lifting the stick ends it")
}

// ---------------------------------------------------------------- the view
print("== the view")
do {
    let v = CombatStickView(label: "ATTACK")
    _ = v.body
    check(v.box > 150 && v.box < 220, "the stick is a comfortable size on an iPad (\(Int(v.box)) pt across)")
    // the dial paints, idle and aiming, without trouble
    let t = RasterTarget(200, 200)
    GraphicsContext.target = t
    var ctx = GraphicsContext()
    CombatStickView.paint(&ctx, CGSize(width: 200, height: 200), 68, 0, 0, false, false)
    CombatStickView.paint(&ctx, CGSize(width: 200, height: 200), 68, 40, -40, true, true)
    GraphicsContext.target = nil
    check(true, "the dial paints idle and aiming")
}
do {
    // the world draws the aim dashes
    resetStick()
    let g = arena()
    hold(g, .sword(.iron))
    actState.stickAt(0.5, -0.8)
    frames(g, 2)
    let t = RasterTarget(640, 400)
    GraphicsContext.target = t
    var ctx = GraphicsContext()
    WorldRenderer.draw(&ctx, CGSize(width: 640, height: 400), g)
    GraphicsContext.target = nil
    check(true, "the world draws with the stick aiming")
    release(); frame(g)
}

print(fails == 0 ? "ALL \(passes) STICK TESTS PASSED" : "\(fails) STICK TESTS FAILED")
