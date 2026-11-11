import SwiftUI
import Foundation
// The hand-drawn art: the packed pictures read back whole, every creature has a look (hand-drawn at 16
// pixels a block, or its older one at 8), poses and walks point at frames that exist, sprites stand on
// their soles and fit their hit boxes, the player's hair, scarf and armour colours, the frame the
// player shows for each thing they do, blocks at 16 pixels with their mirrored variants, the land
// painter, and a mod's repaint keeping the size of the drawing it was painted over.

var fails = 0
var passes = 0
func check(_ ok: Bool, _ msg: String) {
    print((ok ? "PASS " : "FAIL ") + msg)
    if ok { passes += 1 } else { fails += 1 }
}
let scratch: URL = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("prart-" + String(Int.random(in: 1000...999999)), isDirectory: true)
ModStore.overrideDir = scratch
ModRuntime.activate([], world: nil)

func opaque(_ b: PixelBuf) -> Int { return b.px.filter { ($0 >> 24) != 0 }.count }
/// A walking creature still drawn with its older picture (nil once every creature is redrawn)
let olderKind: MobKind? = MobKind.allCases.first { (k: MobKind) -> Bool in
    if k == .custom || k == .villager { return false }
    let l: CreatureLook = creatureLook(k, 0)
    return !l.fine && l.anim.cycle.isEmpty && !l.anim.hop && l.frames.count >= 3
}
func colours(_ b: PixelBuf) -> Set<UInt32> { return Set(b.px.filter { ($0 >> 24) != 0 }.map { $0 & 0xFFFFFF }) }

// ---- the packed pictures ----
do {
    let arts = CreatureSheet.arts
    check(arts.count >= 15, "the sheet holds the hand-drawn creatures (\(arts.count))")
    var whole: Bool = true
    var posesOK: Bool = true
    var solesOK: Bool = true
    for (name, a) in arts {
        let fr: [PixelBuf] = CreatureSheet.frames(name)
        if fr.isEmpty || fr.contains(where: { $0.w != a.w || $0.h != a.h || opaque($0) < 12 }) { whole = false; print("  broken frames: \(name)") }
        for (pose, idx) in a.poses where idx.isEmpty || idx.contains(where: { $0 < 0 || $0 >= fr.count }) { posesOK = false; print("  bad pose \(pose) of \(name)") }
        if a.poses["idle"]?.first != 0 { posesOK = false; print("  \(name) does not stand in frame 0") }
        // the soles' row holds pixels, and the row under it is the outline that sinks into the ground
        if a.foot < 4 || a.foot + 1 >= a.h { solesOK = false; print("  soles of \(name) at \(a.foot) of \(a.h)") }
        let floats: Bool = a.poses["fly"] != nil
        if let f0 = fr.first, !floats, !name.hasPrefix("player_") {
            let row: Int = a.foot + 1
            var any: Bool = false
            for x in 0..<f0.w where (f0.px[row * f0.w + x] >> 24) != 0 { any = true }
            if !any { solesOK = false; print("  \(name): nothing under its soles in row \(row)") }
        }
    }
    check(whole, "every frame unpacks to its full size with a picture in it")
    check(posesOK, "every pose points at frames that exist, and frame 0 is the standing one")
    check(solesOK, "every drawing says where its soles are, with its outline in the row below")
    // unpacking: counts, letters and clear pixels
    let pal: [UInt8: UInt32] = ArtSheet.palette("aFF0000,b00FF00")
    let b: PixelBuf = ArtSheet.unpack("3.2ab10.", 4, 4, pal)
    check(b.px[0] == 0 && b.px[2] == 0 && b.px[3] == 0xFFFF0000 && b.px[4] == 0xFFFF0000 && b.px[5] == 0xFF00FF00 && b.px[6] == 0 && b.px[15] == 0, "runs, single letters and clear pixels unpack in order")
}

// ---- every creature has a look ----
do {
    var allHave: Bool = true
    var fits: Bool = true
    var fine: Int = 0
    for k in MobKind.allCases where k != .custom && k != .villager {
        let l: CreatureLook = creatureLook(k, 0)
        if l.frames.isEmpty { allHave = false; continue }
        if l.fine { fine += 1 }
        let s: SpriteSet = creatureSpriteSet(k, 0)
        let bb = opaqueBounds(l.frames[0])
        let drawnH: Double = Double(bb.3 - bb.1 + 1) * s.scale
        let d: MobDef = mobDef(k)
        // a sprite is about as tall as its hit box: never under three quarters of it, never over twice
        // fliers are measured with their wings up; the mimic is drawn exactly as the chest it pretends to be
        let most: Double = l.anim.cycle.isEmpty ? 2.0 : 2.6
        let least: Double = k == .mimic ? 0.6 : 0.75
        if drawnH < d.h * least || drawnH > d.h * most { fits = false; print("  \(k): drawn \(drawnH) blocks tall, hit box \(d.h)") }
        if l.fine && abs(l.scale - 1.0 / 16.0) > 1e-9 { fits = false }
        if !l.fine && abs(l.scale - 0.125) > 1e-9 { fits = false }
        // (an older drawing with fewer frames than its walk wraps round, as it always did)
        for w in l.anim.walk where l.fine && (w < 0 || w >= l.frames.count) { allHave = false; print("  \(k): walk frame \(w) missing") }
    }
    check(allHave, "every creature has frames, and its walk stays inside them")
    check(fits, "every creature is drawn about the height of its hit box, at its own pixel size")
    check(fine >= 12, "the first creatures are hand-drawn (\(fine)); the rest keep their older look for now")
    check(creatureLook(.zombie, 1).fine && creatureLook(.zombie, 2).fine && creatureLook(.zombie, 0).frames[0].px != creatureLook(.zombie, 1).frames[0].px, "the husk and the drowned are their own drawings")
    check(creatureLook(.custom, 0).frames.count == creatureLook(.zombie, 0).frames.count, "a creature of a missing mod looks like a zombie")
    if let k = olderKind {
        let l: CreatureLook = creatureLook(k, 0)
        check(l.anim.walk == [1, 2] && l.anim.pose("strike", 4) == 4, "an older drawing (\(k)) keeps its two-step walk and its frame numbers")
    } else {
        check(true, "every creature is hand-drawn now")
    }
    let z: CreatureAnim = creatureLook(.zombie, 0).anim
    check(z.walk.count == 4 && z.pose("windup", -1) >= 0 && z.pose("strike", -1) >= 0, "the zombie has a four-step walk, a wind-up and a strike")
    let sk: CreatureAnim = creatureLook(.skeleton, 0).anim
    check(sk.pose("block", -1) >= 0 && sk.pose("shoot", -1) >= 0, "the skeleton has a blocking pose")
    let bear: CreatureAnim = creatureLook(.bear, 0).anim
    check(bear.attack >= 5 && bear.walk.count == 4, "the bear bites in its own frame")
    check(creatureLook(.pig, 0).anim.idleAlt >= 0 && creatureLook(.cow, 0).anim.idleAlt >= 0 && creatureLook(.chicken, 0).anim.idleAlt >= 0, "farm animals root, graze and peck")
    let sl: CreatureAnim = creatureLook(.slime, 0).anim
    check(sl.hop && sl.hopFrame == 1 && sl.attack == 2, "a slime sits, stretches in the air and lunges")
    check(creatureLook(.crow, 0).anim.cycle == [0, 1, 2, 1], "the crow's wings beat up, level, down, level")
    // walking: a whole cycle takes as long with four frames as with two
    var a2 = CreatureAnim(); a2.walk = [1, 2]
    var a4 = CreatureAnim(); a4.walk = [1, 2, 3, 4]
    check(a2.walkFrame(0.0) == 1 && a2.walkFrame(0.5) == 2 && a2.walkFrame(1.0) == 1, "two frames: one stride each half")
    check(a4.walkFrame(0.0) == 1 && a4.walkFrame(0.25) == 2 && a4.walkFrame(0.5) == 3 && a4.walkFrame(0.75) == 4 && a4.walkFrame(1.0) == 1, "four frames: the same stride in four steps")
    var a0 = CreatureAnim(); a0.walk = []
    check(a0.walkFrame(3.3) == 0, "a creature with no walk stands")
}

// ---- frames in play ----
do {
    let g = Game(mode: .survival, infinite: true, seed: 77, settings: Settings())
    g.monstersEnabled = false; g.pauseSpawning = true
    g.mobs.removeAll()
    let art: Art = Art.shared
    let z: Mob = g.addMob(.zombie, g.pb.x + 5, g.pb.y)
    let zs: SpriteSet = art.mobSet(z)
    z.b.vx = 1.0; z.anim = 0.3
    let f1: Int = WorldRenderer.mobFrame(z, zs, 0)
    z.anim = 0.8
    let f2: Int = WorldRenderer.mobFrame(z, zs, 0)
    check(zs.anim.walk.contains(f1) && zs.anim.walk.contains(f2) && f1 != f2, "a walking zombie steps through its walk frames")
    z.b.vx = 0
    check(WorldRenderer.mobFrame(z, zs, 0) == 0, "a still zombie stands")
    z.atkT = 0.2
    check(WorldRenderer.mobFrame(z, zs, 0) == zs.anim.pose("strike", -1), "a zombie that lands a blow shows its strike")
    z.atkT = 0
    let k: Mob = g.addMob(.skeleton, g.pb.x + 8, g.pb.y)
    let ks: SpriteSet = art.mobSet(k)
    k.blocking = true
    check(WorldRenderer.mobFrame(k, ks, 0) == ks.anim.pose("block", -1), "a skeleton behind its shield shows the blocking pose")
    k.blocking = false; k.st = 3
    check(WorldRenderer.mobFrame(k, ks, 0) == ks.anim.pose("windup", -1), "a skeleton winding up raises its sword")
    k.st = 4
    check(WorldRenderer.mobFrame(k, ks, 0) == ks.anim.pose("strike", -1), "and thrusts as it strikes")
    let b: Mob = g.addMob(.bear, g.pb.x + 12, g.pb.y)
    let bs: SpriteSet = art.mobSet(b)
    b.atkT = 0.2
    check(WorldRenderer.mobFrame(b, bs, 0) == bs.anim.attack, "a bear's bite shows its biting frame")
    if let ok = olderKind {
        let s: Mob = g.addMob(ok, g.pb.x + 16, g.pb.y)
        let ss: SpriteSet = art.mobSet(s)
        s.b.vx = 1; s.anim = 0.3
        let sf: Int = WorldRenderer.mobFrame(s, ss, 0)
        check(sf == 1 || sf == 2, "an older drawing still walks on its two frames")
        check(abs(zs.scale - 1.0 / 16.0) < 1e-9 && abs(ss.scale - 0.125) < 1e-9, "each sprite set carries its own pixel size")
    }
    // a hand-drawn sprite stands with its soles on the ground and its middle over its hit box
    let za = CreatureSheet.arts["zombie"]
    check(zs.footRow == (za?.foot ?? -9) + 1 && abs(zs.centerCol - (za?.cx ?? -9)) < 0.01, "the set stands where the drawing says its soles and its middle are")
    // mutants keep the look's size
    z.mut = 2
    let ms: SpriteSet = art.mutantSet(z)
    check(abs(ms.scale - zs.scale) < 1e-9 && ms.right.count == zs.right.count, "a mutated creature keeps its drawing's size and frames")
}

// ---- the pirates, the deep monsters and the bosses: each pose by what the creature is doing ----
do {
    var all: Bool = true
    for k in MobKind.allCases where k != .custom && k != .villager && !creatureLook(k, 0).fine { all = false; print("  still on older art: \(k)") }
    check(all, "every creature in the game is hand-drawn")
    let g = Game(mode: .survival, infinite: true, seed: 79, settings: Settings())
    g.monstersEnabled = false; g.pauseSpawning = true
    g.mobs.removeAll()
    let art: Art = Art.shared
    func at(_ k: MobKind, _ dx: Double) -> (Mob, SpriteSet) {
        let m: Mob = g.addMob(k, g.pb.x + dx, g.pb.y)
        return (m, art.mobSet(m))
    }
    // swordsmen: the deckhand and the captain wind up, cut and parry like the skeleton
    for k in [MobKind.pirate, .pirateCaptain] {
        let (m, s) = at(k, 4)
        let w: Int = s.anim.pose("windup", -1), st: Int = s.anim.pose("strike", -1), bl: Int = s.anim.pose("block", -1)
        var ok: Bool = w > 0 && st > 0 && bl > 0 && Set([w, st, bl]).count == 3 && s.anim.walk.count == 4
        m.st = 3; ok = ok && WorldRenderer.mobFrame(m, s, 0) == w
        m.st = 4; ok = ok && WorldRenderer.mobFrame(m, s, 0) == st
        m.st = 0; m.blocking = true; ok = ok && WorldRenderer.mobFrame(m, s, 0) == bl
        check(ok, "\(k): a cutlass raised, swung and held up to parry")
    }
    do {
        let (m, s) = at(.pirateGunner, 6)
        let aim: Int = s.anim.pose("shoot", -1), fire: Int = s.anim.pose("fire", -1)
        m.st = 3
        let f3: Int = WorldRenderer.mobFrame(m, s, 0)
        m.st = 6
        let f6: Int = WorldRenderer.mobFrame(m, s, 0)
        check(aim > 0 && fire > 0 && aim != fire && f3 == aim && f6 == fire, "the gunner levels the pistol to aim, then shows the flash of the shot")
    }
    do {
        let (m, s) = at(.golem, 8)
        m.st = 3
        let a: Int = WorldRenderer.mobFrame(m, s, 0)
        m.st = 4
        let b: Int = WorldRenderer.mobFrame(m, s, 0)
        m.st = 5
        let c: Int = WorldRenderer.mobFrame(m, s, 0)
        m.st = 0; m.b.vx = 1; m.anim = 0.3
        let w: Int = WorldRenderer.mobFrame(m, s, 0)
        check(a == s.anim.pose("windup", -1) && b == s.anim.pose("strike", -1) && c == s.anim.pose("throw", -1) && Set([a, b, c]).count == 3 && s.anim.walk.contains(w), "the golem raises its fists, slams, hurls a rock, and plods on four steps")
    }
    do {
        let (m, s) = at(.sentinel, 10)
        m.st = 1
        let ch: Int = WorldRenderer.mobFrame(m, s, 0)
        m.st = 5
        let sk: Int = WorldRenderer.mobFrame(m, s, 0)
        m.st = 0; m.atkT = 0
        m.anim = 0.1
        let h0: Int = WorldRenderer.mobFrame(m, s, 0)
        m.anim = 0.6
        let h1: Int = WorldRenderer.mobFrame(m, s, 0)
        check(ch == s.anim.pose("charge", -1) && sk == s.anim.pose("strike", -1) && h0 != h1 && h0 < 2 && h1 < 2, "the sentinel bobs as it hovers, flares to charge and flings its shards")
    }
    do {
        let (m, s) = at(.warden, 12)
        m.atk = WardenAtk.sweep.rawValue
        m.st = 1
        let back: Int = WorldRenderer.mobFrame(m, s, 0)
        m.st = 2; m.atkT = 0.2
        let cut: Int = WorldRenderer.mobFrame(m, s, 0)
        m.atk = WardenAtk.bolts.rawValue; m.st = 1; m.atkT = 0
        let cast: Int = WorldRenderer.mobFrame(m, s, 0)
        check(back == s.anim.pose("windup", -1) && cut == s.anim.pose("strike", -1) && cast == s.anim.pose("cast", -1) && Set([back, cut, cast]).count == 3, "the Warden draws its scythe back, sweeps it, and casts with a raised hand")
    }
    do {
        let (m, s) = at(.bearBoss, 14)
        m.st = 1
        let rear: Int = WorldRenderer.mobFrame(m, s, 0)
        m.st = 2; m.atk = BossAtk.melee.rawValue
        let swipe: Int = WorldRenderer.mobFrame(m, s, 0)
        m.atk = BossAtk.roar.rawValue
        let roar: Int = WorldRenderer.mobFrame(m, s, 0)
        m.st = 0; m.b.vx = 0
        let still: Int = WorldRenderer.mobFrame(m, s, 0)
        m.b.vx = 2; m.anim = 0.4
        let walk: Int = WorldRenderer.mobFrame(m, s, 0)
        check(rear == s.anim.pose("rear", -1) && roar == rear && swipe == s.anim.pose("strike", -1) && still == 0 && s.anim.walk.count == 4 && s.anim.walk.contains(walk), "Ursavor prowls on four steps, rears up to roar and slam, and swipes")
    }
    do {
        let (m, s) = at(.rex, 18)
        m.st = 1; m.atk = BossAtk.melee.rawValue
        let wind: Int = WorldRenderer.mobFrame(m, s, 0)
        m.st = 2
        let bite: Int = WorldRenderer.mobFrame(m, s, 0)
        m.st = 0; m.b.vx = 2; m.anim = 0.7
        let walk: Int = WorldRenderer.mobFrame(m, s, 0)
        check(wind == s.anim.pose("windup", -1) && bite == s.anim.pose("strike", -1) && wind != bite && s.anim.walk.contains(walk), "Tyrannax draws its head back, lunges with its jaws wide, and strides on four steps")
    }
    // the hand-drawn bosses keep the older pictures' frame numbers where the older code still asks by number
    let older: (Int, Int) = (CreatureAnim().pose("rear", 2), CreatureAnim().pose("cast", 4))
    check(older == (2, 4), "an older drawing without named poses still gets its old frame numbers")
}

// ---- the player ----
do {
    let s0: Settings = Settings()
    let plain: CreatureLook = playerLook(PlayerLookChoice(s0))
    check(plain.fine && plain.frames.count == 10 && plain.anim.pose("front", -1) == 9, "the player is hand-drawn: nine side frames and one from the front")
    var drawn: Bool = CreatureSheet.has("player") && CreatureSheet.has("player_scarf") && CreatureSheet.has("player_helm")
    for i in hairStyleNames.indices where !CreatureSheet.has("player_hair_\(i)") { drawn = false; print("  no hair style \(i)") }
    for i in shirtStyleNames.indices where !CreatureSheet.has("player_shirt_\(i)") { drawn = false; print("  no shirt style \(i)") }
    for i in pantsStyleNames.indices where !CreatureSheet.has("player_pants_\(i)") { drawn = false; print("  no trouser style \(i)") }
    check(drawn, "every hair, shirt and trouser style on the character screen has its drawing")
    check(hairChoices[0] == 0x0A0A14 && shirtChoices[0] == 0x4B2A31 && pantsChoices[0] == 0x25385B && scarfChoices[0] == 0, "the first choices are the player's own drawing: black hair, a dark red shirt, navy trousers, no scarf")
    let cs: Set<UInt32> = colours(plain.frames[0])
    check(cs.contains(lookRamp(hairChoices[0])[1]) && cs.contains(lookRamp(shirtChoices[0])[1]) && cs.contains(lookRamp(pantsChoices[0])[1]), "the default look wears the chosen colours' tones")
    // no marker colour is ever left on screen, whatever is chosen
    let markers: Set<UInt32> = Set(PlayerInk.hair + PlayerInk.shirt + PlayerInk.pants + PlayerInk.shoe + PlayerInk.scarf + PlayerInk.helm)
    var leftover: Int = 0
    var looks: [PlayerLookChoice] = []
    for h in hairStyleNames.indices {
        for sh in shirtStyleNames.indices {
            var s: Settings = Settings()
            s.hairStyle = h; s.shirtStyle = sh; s.pantsStyle = (h + sh) % pantsStyleNames.count
            s.hair = h % hairChoices.count; s.shirtColor = sh; s.pantsColor = h % pantsChoices.count; s.scarf = (h + sh) % scarfChoices.count
            looks.append(PlayerLookChoice(s))
        }
    }
    looks.append(PlayerLookChoice(s0, head: .iron, chest: .gold, legs: .copper))
    for c in looks {
        for f in playerFrames(c) { leftover += colours(f).intersection(markers).count }
    }
    check(leftover == 0, "no marker colour is left in any look (\(looks.count) looks tried)")
    // each choice changes what it should
    var s1: Settings = s0
    s1.hair = 1
    let red: Set<UInt32> = colours(playerLook(PlayerLookChoice(s1)).frames[0])
    check(red.contains(lookRamp(hairChoices[1])[1]) && !red.contains(lookRamp(hairChoices[0])[1]) && red.contains(lookRamp(shirtChoices[0])[1]), "another hair colour replaces only the hair")
    var differ: Bool = true
    for i in 1..<hairStyleNames.count {
        var s: Settings = s0; s.hairStyle = i
        if playerLook(PlayerLookChoice(s)).frames[0].px == plain.frames[0].px { differ = false }
    }
    for i in 1..<shirtStyleNames.count {
        var s: Settings = s0; s.shirtStyle = i
        if playerLook(PlayerLookChoice(s)).frames[9].px == plain.frames[9].px { differ = false }
    }
    for i in 1..<pantsStyleNames.count {
        var s: Settings = s0; s.pantsStyle = i
        if playerLook(PlayerLookChoice(s)).frames[0].px == plain.frames[0].px { differ = false }
    }
    check(differ, "every style changes the figure")
    var shorts: Settings = s0
    shorts.pantsStyle = 1
    var longs: Settings = s0
    longs.shirtStyle = 1
    let skinT: UInt32 = artGrade(0xC19573)
    let shortLegs: PixelBuf = playerLook(PlayerLookChoice(shorts)).frames[9]
    let fullLegs: PixelBuf = plain.frames[9]
    func skinIn(_ b: PixelBuf, _ y0: Int, _ y1: Int) -> Int {
        var n: Int = 0
        for y in y0..<y1 { for x in 0..<b.w where (b.px[y * b.w + x] & 0xFFFFFF) == skinT && (b.px[y * b.w + x] >> 24) != 0 { n += 1 } }
        return n
    }
    check(skinIn(shortLegs, 27, 32) > skinIn(fullLegs, 27, 32) + 4, "shorts show bare shins")
    check(skinIn(playerLook(PlayerLookChoice(longs)).frames[9], 19, 24) < skinIn(plain.frames[9], 19, 24), "long sleeves cover the forearms")
    var sc: Settings = s0
    sc.scarf = 1
    check(colours(playerLook(PlayerLookChoice(sc)).frames[0]).contains(lookRamp(scarfChoices[1])[1]) && colours(playerLook(PlayerLookChoice(sc)).frames[9]).contains(lookRamp(scarfChoices[1])[1]), "a chosen scarf shows from the side and the front")
    let iron: CreatureLook = playerLook(PlayerLookChoice(s0, head: .iron, chest: .iron, legs: .iron))
    let ic: Set<UInt32> = colours(iron.frames[0])
    check(!ic.contains(lookRamp(shirtChoices[0])[1]) && !ic.contains(lookRamp(pantsChoices[0])[1]) && ic.contains(lookRamp(Tier.iron.color)[1]), "armour takes the place of the shirt and trousers, in its metal")
    let bare: CreatureLook = playerLook(PlayerLookChoice(s0, chest: .iron, legs: .iron))
    check(bare.frames[0].px != iron.frames[0].px && bare.frames[9].px != iron.frames[9].px, "a helmet goes over the hair, from the side and from the front")
    var sizes: Bool = true
    for f in iron.frames where f.w != plain.frames[0].w || f.h != plain.frames[0].h { sizes = false }
    check(sizes, "worn things keep the frame size")
    check(PlayerLookChoice(s1).key != PlayerLookChoice(s0).key && PlayerLookChoice(s0, head: .iron).key != PlayerLookChoice(s0).key, "every choice has its own sprite key")
    // settings: the new choices are saved; settings from before them start the look afresh
    var full: Settings = Settings()
    full.hair = 3; full.hairStyle = 2; full.shirtColor = 4; full.shirtStyle = 3; full.pantsColor = 2; full.pantsStyle = 1; full.scarf = 2
    let back: Settings? = try? JSONDecoder().decode(Settings.self, from: (try? JSONEncoder().encode(full)) ?? Data())
    check(back?.hairStyle == 2 && back?.shirtColor == 4 && back?.shirtStyle == 3 && back?.pantsColor == 2 && back?.pantsStyle == 1 && back?.hair == 3 && back?.scarf == 2, "the look's choices are saved with the settings")
    let older: Settings? = try? JSONDecoder().decode(Settings.self, from: Data("{\"hair\": 3, \"scarf\": 2, \"tilePx\": 32}".utf8))
    check(older?.hair == 0 && older?.scarf == 0 && older?.hairStyle == 0 && older?.tilePx == 32, "settings saved before the styles start the look as the player's drawing, keeping the rest")
    // what the player shows for what they do
    let g = Game(mode: .survival, infinite: true, seed: 78, settings: Settings())
    let s: SpriteSet = Art.shared.playerSet(g)
    g.pb.onGround = true
    g.restT = 0
    check(WorldRenderer.playerSpriteFrame(s, g, 0) == 0, "standing: the side view")
    g.restT = 2
    check(WorldRenderer.playerSpriteFrame(s, g, 0) == s.anim.pose("front", -1), "after a moment at rest the player faces out of the screen")
    g.walkAnim = 0.3
    let w1: Int = WorldRenderer.playerSpriteFrame(s, g, 1)
    g.walkAnim = 0.6
    let w2: Int = WorldRenderer.playerSpriteFrame(s, g, 1)
    check(s.anim.walk.contains(w1) && s.anim.walk.contains(w2) && w1 != w2, "walking steps through the four frames")
    g.pb.onGround = false
    check(WorldRenderer.playerSpriteFrame(s, g, 1) == s.anim.walk[0], "in the air: the stride")
    g.pb.onGround = true
    check(WorldRenderer.playerSpriteFrame(s, g, 3) == s.anim.pose("windup", -1) && WorldRenderer.playerSpriteFrame(s, g, 4) == s.anim.pose("strike", -1) && WorldRenderer.playerSpriteFrame(s, g, 6) == s.anim.pose("shoot", -1), "winding up, striking and shooting have their poses")
    g.restT = 0
    for _ in 0..<90 { g.tick(1.0 / 60.0) }
    check(g.restT > 0.9, "standing still, the rest timer runs (\(g.restT))")
    g.swingT = 0.2
    g.tick(1.0 / 60.0)
    check(g.restT == 0, "swinging something ends the rest")
    let st: HumanStyle = playerStyle(hairIdx: 0, scarfIdx: 0, head: nil, chest: nil, legs: nil)
    check(st.hair == 0x0A0A14 && st.scarf == 0 && st.shirt == 0x4B2A31 && st.pants == 0x25385B, "the figure under a suit wears the same colours")
    let front: PixelBuf = plain.frames[plain.anim.pose("front", 0)]
    var mirror: Int = 0
    for y in 0..<front.h { for x in 0..<front.w where (front.px[y * front.w + x] >> 24 != 0) != (front.px[y * front.w + (front.w - 1 - x)] >> 24 != 0) { mirror += 1 } }
    check(mirror < 30, "the front view (shown on the character screen) is the same shape on both sides (\(mirror) pixels differ)")
}

// ---- blocks ----
do {
    check(tileArtPx == 16, "blocks are 16 pixels a side")
    var sized: Bool = true
    for t in Tile.allCases {
        let b: PixelBuf = tileBuf(t)
        if b.w != 16 || b.h != 16 || b.px.count != 256 { sized = false; print("  \(t) is \(b.w)x\(b.h)") }
    }
    check(sized, "every block's picture is 16 x 16, hand-drawn or the older one doubled")
    check(TileSheet.bufs.count >= 40, "the first blocks are hand-drawn (\(TileSheet.bufs.count))")
    let old: PixelBuf = olderTileBuf(.chair)
    let fit: PixelBuf = fitTileArt(old)
    var doubled: Bool = old.w == 8 && fit.w == 16
    for y in 0..<16 { for x in 0..<16 where fit.px[y * 16 + x] != old.px[(y / 2) * 8 + x / 2] { doubled = false } }
    check(doubled, "an older 8 x 8 block is drawn with every pixel doubled")
    check(tileBuf(.grass).px != fitTileArt(olderTileBuf(.grass)).px, "grass is the hand-drawn one")
    check(opaque(tileBuf(.torch)) < 120 && opaque(tileBuf(.torch)) > 20 && opaque(tileBuf(.stone)) == 256, "a torch is a small thing with clear space round it; stone fills its block")
    check(TileSheet.flips[Tile.stone.rawValue] == 3 && TileSheet.flips[Tile.grass.rawValue] == 1 && (TileSheet.flips[Tile.log.rawValue] ?? 0) == 0 && (TileSheet.flips[Tile.planks.rawValue] ?? 0) == 0, "stone may be mirrored and turned, grass only mirrored, trunks and planks never")
    // the painter's four pictures of a block
    let p: SectionPainter = SectionPainter.shared
    let n: Int = 256
    let raw: Int = Int(Tile.stone.rawValue)
    var mirrors: Bool = true
    for y in 0..<16 { for x in 0..<16 {
        let c: UInt32 = p.tilePx[raw * 4 * n + y * 16 + x]
        if p.tilePx[raw * 4 * n + n + y * 16 + (15 - x)] != c { mirrors = false }
        if p.tilePx[raw * 4 * n + 2 * n + (15 - y) * 16 + x] != c { mirrors = false }
        if p.tilePx[raw * 4 * n + 3 * n + (15 - y) * 16 + (15 - x)] != c { mirrors = false }
    } }
    check(mirrors, "the painter keeps each block as drawn, mirrored, turned over and both")
    // a painted section: its size, the same land always paints the same, a wall of stone is not one picture repeated
    let g = Game(mode: .creative, infinite: true, seed: 79, settings: Settings())
    g.monstersEnabled = false; g.pauseSpawning = true
    let w = g.world
    let cx: Int = floorDiv(Int(g.pb.x), chunkW)
    w.loadAround(centerX: Int(g.pb.x), radius: 3)
    guard let ch = w.chunks[cx] else { fatalError("no chunk") }
    for lx in 0..<chunkW { for y in 96..<112 { w.set(cx * chunkW + lx, y, .stone) } }
    let a: [UInt32] = p.paint(w, ch, 6)
    let b: [UInt32] = p.paint(w, ch, 6)
    check(a.count == chunkW * 16 * 16 * 16 && a == b, "a section paints to 256 x 256 pixels, the same every time")
    func cell(_ px: [UInt32], _ lx: Int, _ ly: Int) -> [UInt32] {
        var out: [UInt32] = []
        for yy in 2..<14 { for xx in 2..<14 { out.append(px[(ly * 16 + yy) * (chunkW * 16) + lx * 16 + xx]) } }
        return out
    }
    var kinds: Set<[UInt32]> = []
    for lx in 2..<14 { for ly in 4..<12 { kinds.insert(cell(a, lx, ly)) } }
    check(kinds.count >= 3 && kinds.count <= 4, "a wall of stone mixes the block's four pictures (\(kinds.count) seen)")
    // edges: a lit top and dark lines where ground meets open space
    for lx in 0..<chunkW { for y in 80..<96 { w.set(cx * chunkW + lx, y, .air); w.setWall(cx * chunkW + lx, y, 0) } }
    w.set(cx * chunkW + 5, 95, .stone)
    let e: [UInt32] = p.paint(w, ch, 5)
    let W: Int = chunkW * 16
    func lum(_ c: UInt32) -> Int { return Int((c >> 16) & 255) + Int((c >> 8) & 255) + Int(c & 255) }
    let leftEdge: Int = lum(e[(15 * 16 + 8) * W + 5 * 16]), inside: Int = lum(e[(15 * 16 + 8) * W + 5 * 16 + 1]), rightEdge: Int = lum(e[(15 * 16 + 8) * W + 5 * 16 + 15])
    check(leftEdge < inside + 40 && rightEdge < lum(e[(15 * 16 + 8) * W + 5 * 16 + 14]) + 40, "a lone block has darker pixels down its open sides")
    // mod blocks: 16 x 16 like the game's, or 8 x 8 drawn doubled as they always were
    let copied: ModBlock = ModBlock.fromGame(.grass)
    check(copied.art.w == 16 && copied.art.buf().px == tileBuf(.grass).px, "a custom block copied from a game block gets its 16 x 16 picture")
    var small = ModPixels(w: 8, h: 8)
    small.setARGB(1, 1, 0xFFC02040)
    let big: ModPixels = small.stretched(16, 16)
    check(big.w == 16 && big.argb(2, 2) == 0xFFC02040 && big.argb(3, 3) == 0xFFC02040 && big.argb(4, 4) == 0 && big.stretched(8, 8) == small, "a block's picture switches between 8 x 8 and 16 x 16 and back without loss")
    var odd = ModPixels(w: 12, h: 12)
    odd.setARGB(5, 11, 0xFF102030)
    check(ModBlock.fitArt(odd).w == 8 && ModBlock.fitArt(big).w == 16 && ModBlock.fitArt(small).w == 8, "a block's picture is 16 x 16 or 8 x 8; another size is cut to 8 x 8")
    var pk = ModPack(); pk.id = "fineblock"; pk.name = "Fine block"
    var fb = ModBlock(); fb.id = "f"; fb.name = "Fine"; fb.art = ModPixels(buf: tileBuf(.planks))
    var cb = ModBlock(); cb.id = "c"; cb.name = "Coarse"; cb.art = small
    pk.blocks = [fb, cb]
    _ = ModValidator.check(&pk, known: [:])
    check(pk.blocks[0].art.w == 16 && pk.blocks[1].art.w == 8, "the checks keep both sizes")
    ModRuntime.activate([pk], world: nil)
    if let ft = ModRuntime.shared.tileForKey["fineblock:f"], let ct = ModRuntime.shared.tileForKey["fineblock:c"] {
        check(tileBuf(ft).px == tileBuf(.planks).px, "a 16 x 16 custom block is drawn pixel for pixel")
        check(tileBuf(ct).px[2 * 16 + 2] == 0xFFC02040 && tileBuf(ct).px[3 * 16 + 3] == 0xFFC02040 && tileBuf(ct).w == 16, "an 8 x 8 one is drawn doubled")
    } else {
        check(false, "custom blocks get tile numbers")
    }
    ModRuntime.activate([], world: nil)
}

// ---- a mod's repaint of a game creature ----
do {
    func painted(_ w: Int, _ h: Int, _ c: UInt32) -> ModPixels {
        var p = ModPixels(w: w, h: h)
        for y in 0..<h { for x in 0..<w { p.setARGB(x, y, 0xFF000000 | c) } }
        return p
    }
    // painted over the older drawing: its size and its seven frames
    var oldMod = ModPack(); oldMod.id = "oldpaint"; oldMod.name = "Old paint"
    var o = ModOverride(); o.id = "z"; o.kind = .creature; o.mob = MobKind.zombie.rawValue
    o.frames = (0..<7).map { _ in painted(12, 17, 0x30A030) }
    oldMod.overrides = [o]
    ModRuntime.activate([oldMod], world: nil)
    Art.shared.refreshModArt()
    let a: SpriteSet = Art.shared.buildMobSet(.zombie, 0)
    check(abs(a.scale - 0.125) < 1e-9 && a.anim.walk == [1, 2] && a.anim.pose("strike", 4) == 4, "a repaint made on the older drawing keeps that one's size and frame order")
    // painted over the hand-drawn one
    var newMod = ModPack(); newMod.id = "newpaint"; newMod.name = "New paint"
    var n = ModOverride(); n.id = "z"; n.kind = .creature; n.mob = MobKind.zombie.rawValue
    let look: CreatureLook = creatureLook(.zombie, 0)
    n.frames = look.frames.map { ModPixels(buf: $0) }
    n.fine = true
    newMod.overrides = [n]
    ModRuntime.activate([newMod], world: nil)
    Art.shared.refreshModArt()
    let b: SpriteSet = Art.shared.buildMobSet(.zombie, 0)
    check(abs(b.scale - 1.0 / 16.0) < 1e-9 && b.anim.walk.count == 4, "a repaint started from the hand-drawn creature is drawn at its finer size")
    // the flag is saved with the mod, and older mods read as "not fine"
    let data: Data = (try? JSONEncoder().encode(newMod)) ?? Data()
    let back: ModPack? = try? JSONDecoder().decode(ModPack.self, from: data)
    check(back?.overrides.first?.fine == true, "which drawing a repaint follows is saved in the mod")
    let json: String = String(data: (try? JSONEncoder().encode(oldMod)) ?? Data(), encoding: .utf8) ?? ""
    let stripped: String = json.replacingOccurrences(of: "\"fine\":false,", with: "").replacingOccurrences(of: ",\"fine\":false", with: "")
    let older: ModPack? = try? JSONDecoder().decode(ModPack.self, from: Data(stripped.utf8))
    check(!stripped.contains("fine") && older?.overrides.first?.fine == false, "a mod saved before this reads as painted on the older drawing")
    // a custom creature that wears a game creature's look follows that look's size
    var m = ModMob(); m.id = "big"; m.name = "Big"; m.base = MobKind.zombie.rawValue; m.scale = 1.5
    ModRuntime.activate([], world: nil)
    let ms: SpriteSet = modMobSpriteSet(m)
    check(abs(ms.scale - 1.5 / 16.0) < 1e-9, "a custom creature with the zombie's body is the hand-drawn zombie, half as big again")
    if let ok = olderKind {
        var sh = ModMob(); sh.id = "ram"; sh.name = "Ram"; sh.base = ok.rawValue
        check(abs(modMobSpriteSet(sh).scale - 0.125) < 1e-9, "and one with an older body keeps the older size")
    }
}

ModRuntime.activate([], world: nil)
try? FileManager.default.removeItem(at: scratch)
print("art: \(passes) passed, \(fails) failed")
exit(fails == 0 ? 0 : 1)
