# Critique: smells and a rework procedure

Run this on a plan before building, and on the result after playing it.

## Smells

**Loops**
- The action alone is not pleasant (fails the isolation test).
- Rewards that feed nothing (a number that only grows).
- No natural stopping point, or no reason to start again.
- Grind: the same pattern repeated with nothing new to learn.

**Choices**
- A dominant option: one weapon, tool or path is always best.
- Blind choices: the player can't know the result before choosing.
- Invisible results: the choice changes nothing the player can see.
- Free power: an upgrade with no cost or trade-off.

**Difficulty and failure**
- Unfair hits: danger that wasn't telegraphed or couldn't be avoided.
- Failure that costs far more than how often it happens.
- A wall: one spike much harder than the ramp before it.
- Flat: nothing gets harder, so nothing is learned.

**Clarity**
- The player doesn't know what to do next.
- Information only in colour, only in sound, or too small to read.
- Too many new things at once.
- A wall of text instead of a first try.
- An input that does nothing and shows no reason.

**Feel**
- Delay between input and response.
- Hits without weight (no stop, sound or knockback).
- Effects so big they hide the game.

**Scope**
- A feature that serves no pillar.
- A new verb where deepening an old one would do.
- Content that has to be made by hand where a rule would make it.

**Ethics**
- Pressure to return (streaks, timers, losses for missing a day).
- Anything that would feel bad if the player understood how it works.

## Rework procedure

1. **Name the symptom** from play ("players stop after the first night").
2. **Find the loop** it lives in (action, goal, session, arc).
3. **Find the broken atom**: which step (reason, decision, feedback, reward) fails.
4. **List three fixes** of different kinds: subtract something, change a rule, change feedback.
   Prefer subtracting.
5. **Pick the cheapest one that could work**, build it small, and play it.
6. **Check it didn't break another loop**; write down what was learned.

## Feature review template

- Pillar served:
- Verb deepened:
- Loops touched (action / goal / session / arc):
- Kinds of fun:
- Decision it adds, and its cost:
- Feedback (sight, sound, feel):
- How it is taught:
- How it can be turned off or skipped:
- What it costs (code, build memory, attention):
- How it is tested:
