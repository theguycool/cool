# Game feel and juice

Game feel (Steve Swink) is the moment-to-moment sensation of control: real-time response, a
simulated space, and polish that makes contact readable. If the action loop feels bad, nothing
built on top of it will feel good.

## Response

- Answer every input within about 100 ms with something visible and, ideally, audible.
- Input that arrives slightly early or late should still count:
  - **Coyote time**: a jump pressed just after leaving a ledge still works (about 0.1 s).
  - **Jump buffering**: a jump pressed just before landing happens on landing (about 0.1 s).
  - **Variable jump**: holding jump goes higher; letting go cuts the rise.
  - **Apex hang**: less gravity near the top of a jump while jump is held (Celeste halves it).
  - **Corner correction**: a head bump on the corner of a block nudges the player round it.
  - **Generous hit boxes for the player's attacks, tight ones for enemies' attacks.**
- Never let the game eat an input silently; if an action cannot happen, show why.

## Weight and impact (Juice It or Lose It; The Art of Screenshake)

Layer these, then turn down whatever hides the game:

1. **Anticipation**: a short wind-up before a big action.
2. **Squash and stretch** on jumps, landings and hits.
3. **Hit stop**: freeze for 30 to 80 ms on a solid hit (longer for heavier blows).
4. **Screen shake** on big impacts, small and short; let players turn it down.
5. **Camera kick** toward the direction of a shot or blow.
6. **Knockback** on whatever is hit, and a little on the attacker.
7. **Particles**: dust on landing, chips on mining, sparks on metal, the colour of the material.
8. **Flash**: the hit thing flashes white for a frame or two.
9. **Sound**: a distinct sound per material and per weapon, slightly varied in pitch each time.
10. **Permanence**: marks that stay a while (cracks, debris, shells, scorch).
11. **Bigger, brighter projectiles** and muzzle flashes than seems realistic.
12. **Tweening**: UI and objects ease in and out, never pop.

Over-juicing is real: shake on every small thing tires players and hides information. Big effects
for big moments; small things get small effects.

## Camera (Itay Keren, *Scroll Back*)

- Lead the player: show more space in the direction they are moving or aiming.
- Use a dead zone so small moves don't shake the view.
- Smooth with a lerp, but snap fast enough that the player never loses themselves.
- Frame what matters: a boss, a target, the landing spot of a fall.
- On a pixel-art game, keep the camera on whole pixels at the art's scale to avoid shimmer.

## Sound

- Every action has a sound; every material has its own break and step sound.
- Vary pitch and volume a little so repeats don't drone.
- Layers: a short click for response, a body for weight, a tail for space.
- Quiet sounds for frequent actions, loud ones for rare events.

## Tuning knobs

Expose the feel numbers (speeds, gravity, buffers, hit stop lengths, shake sizes) in one place and
tune them by playing, not by reasoning. Change one at a time. Record values that felt right.
