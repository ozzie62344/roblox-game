# What to test in Studio (overnight-2)

## 1. Weak tables

- [ ] Reinforce a wall, then thermite it: the steel plate disappears and the hole opens. Do it a
      few minutes into a round too (the old bug was random).
- [ ] Barricade a doorway, then take it down (G on the boards as a defender): the boards come off.
      Repeat in a later round.
- [ ] Throw a frag and place a breach charge: each beeps at its normal pace (frag about twice a
      second, breach charge about once a second), not every frame.
- [ ] Breach charge: place it, press X again: it goes off (try late in a round as well).
- [ ] Nitro cell (a defender's B): throw it, press B again: it goes off.
- [ ] Heartbeat sensor: X starts the scan, X again puts it away early.
- [ ] Assists: hurt an enemy, let a teammate finish them: you get the assist on the scoreboard.
- [ ] End of a match: the MVP screen shows the MVP's body.

## 2. Small gameplay bugs (already fixed earlier; re-check if you haven't yet)

- [ ] An EMP thrown just before a round ends doesn't fry the next round's cameras.
- [ ] After dying and respawning, other players see you aim up/down straight away.
- [ ] With lean set to toggle: lean, get downed, get revived: you're not leaning.
- [ ] Thermite on a wall that's already burning: "A CHARGE IS ALREADY BURNING THERE", no charge used.
- [ ] A defender holding G to reinforce can't also start disabling the defuser.

## 3. No shooting while scanning, droning or on cams (already in place)

- [ ] With the heartbeat sensor out, while driving a drone, and while on cameras: clicking fires
      nothing (and no hit lands on a target in front of your body).

## 4. Lune tests

- [ ] From the repo root, run each and see "all passed":
      `lune run tests/Ranked.test.luau`, `tests/Progression.test.luau`, `tests/Clans.test.luau`,
      `tests/CustomMatch.test.luau`, `tests/PickTeams.test.luau`.
- [ ] Nothing to check in Studio: no game code changed for this item.

## 5. CLAUDE.md

- [ ] Read it once and correct anything that doesn't match how you think of the game; it's what
      Claude Code will read first in every new session.
