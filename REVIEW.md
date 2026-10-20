# What to test in Studio (overnight-fixes)

## 1. Downed players, dev End Round / Stop Match, defender site pick

- [ ] Get downed in a match (2 players, or a dummy): you stay on the floor for everyone, and R
      (reload) does nothing while down. After a revive you stand up normally and can reload.
- [ ] Dev panel **End Round** during operator select: the round ends within a second (skips prep).
- [ ] Dev panel **End Round** during prep: same.
- [ ] Dev panel **Stop Match** during operator select and during prep: back to free roam within a
      second, not after the timer.
- [ ] End Round pressed in free roam, then start a match: the first round plays normally.
- [ ] As a defender in operator select: pick a site (team moves there), pick another (ignored),
      a teammate can still change it once, but not within 2 s of the last change.

## 2. Party team-picking test

- [ ] Run `lune run tests/PickTeams.test.luau` from the repo root: it should print "all passed".
- [ ] In Studio, queue a match as before: matchmaking still starts (Matchmaker now loads the team
      picker from `PickTeams`).

## 3. First map built once

- [ ] Start a match: round 1's map is complete (outside doors and windows boarded up, cameras on
      the walls, the right lighting) and appears without a second hitch after the vote.
- [ ] Break some walls in round 1: round 2 starts with them repaired.
- [ ] A custom match (no vote) starts with the host's map intact too.

## 4a. Shared helpers

- [ ] In a match: defenders can watch cameras (Z) in prep and action, attackers can drone in
      prep, a defender stepping outside during prep is snapped back, and later revealed.
- [ ] Placed gadgets (charges, jammers, cover) and drones all clear at the start of each round.

## 4b. Map helpers shared

- [ ] Load each map from the dev panel (House, Warehouse, Bank, Flight 9): walls, doors,
      windows and arches are where they were, outside doors / windows start barricaded, and
      decoration (trim, signs) is see-through to bullets as before.

## 4d. Tutorial reward

- [ ] NEW HERE? prompt and the tutorial's last step both say +250 credits, and finishing the
      tutorial for the first time pays 250.

## 4e. Unused code removed

- [ ] Spawning into a match and the defender perimeter push-back don't trigger anti-cheat
      "put back" messages (they use the ServerTeleport attribute, unchanged).
- [ ] Getting downed and revived works as before.

## 4f. graphify-out

- [ ] `graphify-out/` still exists on disk, and `git status` doesn't list it.
