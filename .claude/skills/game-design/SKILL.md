---
name: game-design
description: Game design know-how for planning, building and critiquing games, especially big ones built in steps. Use when designing or reviewing a feature, a system, a loop, a level, a HUD or menu, onboarding, pixel art, an economy or progression, or monetization; when asked "is this fun", "why do players quit", "how do I make this feel better", "how should this screen look", or "how do I make the game bigger"; and before planning a new step of PixelRealm.
---

# Game design

A working method and reference library for making games that are fun to learn, good to touch, clear
to read and worth coming back to. It is a synthesis of well-known talks, books and open knowledge
bases (see `references/sources.md`). Use the method below; open a reference file only for the part
of the work in front of you.

## The method

Work through these in order for any new feature, system or game. Write the answers down (in the plan
or the commit message) before building.

1. **Player fantasy and verb.** One sentence: what the player gets to be and do. Name the one verb
   the feature deepens (mine, build, fight, fly, explore). A feature that adds a new verb must earn it.
2. **Loops at every scale.** Say what the player does in 30 seconds (the action), 5 to 15 minutes (a
   goal: a trip, a build, a fight), one session (a milestone) and many sessions (the arc). Each loop
   needs a reason to start, a decision, feedback, and a reward that feeds the next loop.
   (`references/loops-and-retention.md`)
3. **Where the fun is.** Which kinds of fun it serves (challenge, discovery, expression, fantasy,
   fellowship, story, sensation, pastime), and what the player learns. Fun is learning a pattern;
   when nothing is left to learn, it needs a twist or it becomes a chore. (`references/fun-and-motivation.md`)
4. **Interesting decisions.** Each choice should have a visible cost and no single right answer.
   If one option always wins, cut the others or give them a reason. (`references/systems-and-progression.md`)
5. **Feel.** The action must answer within 100 ms with sight and sound. Add forgiveness (coyote time,
   input buffering), weight (anticipation, hit stop, shake) and permanence (marks that stay), then
   take away what hides the game. (`references/game-feel.md`)
6. **Reading it.** What the player must see, in what order, at what size. One focal point per
   screen; never colour alone; touch targets at least 44 points on a tablet.
   (`references/ui-ux.md`)
7. **Teaching it.** Let the player do it before telling them; introduce, develop, twist, test.
   Words on screen are the last resort, and short. (`references/onboarding.md`)
8. **Looks.** One pixel size, a palette with jobs, readable silhouettes, values that put the player
   and danger first. (`references/pixel-art.md`)
9. **Scope.** Make the smallest version that tests the fun, then grow it in steps the player can
   check. Systems that combine beat content that has to be made by hand.
   (`references/bigger-games.md`)
10. **Critique.** Run the smell list in `references/critique.md` on the plan and again on the result.

## Rules of thumb (the short list)

- Write rules, not encounters: a few elements that react with each other (fire burns wood, water
  puts out fire, wind carries both) make more play than many scripted set pieces.
- Every resource should be a verb: something to spend it on, not just a number that grows.
- Power should cost something (time, risk, weight, energy, a slot). Free power flattens choices.
- Push players to use their things: consumables they hoard are wasted design.
- New mechanics late in the game keep it fresh; teaching should not stop after the first hour.
- Failure should cost in proportion to how often it happens; frequent failure, cheap retry.
- Show the next goal and the way to it. A player who does not know what to do next quits.
- Respect the player's time: no padding, no waits that exist only to sell skips.
- Let players subtract: skip, turn off, undo, reset. Undo beats a confirmation box.
- Telegraph honestly: a danger the player could not have seen is unfair, not hard.
- Restrictions breed identity: the thing the game cannot do shapes what it is.
- Players spot problems well and solutions badly. Watch what they do; ask what bothered them.
- Monetize only what you would be proud to explain to a child's parent
  (`references/monetization-ethics.md`).

## Using it on PixelRealm

`docs/design-plan.md` applies this method to PixelRealm: what the game already does well, the gaps,
and a list of steps in order of value for effort. Read it before proposing a new step, keep it up to
date when a step lands, and respect the project's rules in `CLAUDE.md` (six parts, build memory,
saved enums append-only, mods as data only).

## Studying talks and videos

`references/studying-talks.md` lists the tools for turning YouTube talks into notes (transcript
tools, the extract-wisdom workflow, MCP servers) and a reading list of the best-known talks per
topic. In a cloud session YouTube may refuse transcript requests; study the written versions
(slides, articles, books by the same speakers) instead and say so.
