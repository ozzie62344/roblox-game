# Night log 2 (overnight-2)

Decisions and reasoning, item by item. Nothing was run in Roblox; every change was type-checked
with luau-lsp (Roblox definitions + a Rojo sourcemap), and Lune tests were run where noted. What to
test in Studio is in REVIEW_2.md.

## 1. Weak tables

Background (NIGHT_LOG.md item 5): a weak table can lose an entry keyed by a game object even while
that object still exists, so each was replaced with a normal table plus explicit clean-up.

### 1a. FortifyService `reinforcements` / `barricades`, GadgetWarnings `lastBeep`

Every read and write, traced before changing:
- `reinforcements` (section → steel model), `server/FortifyService.luau`:
  - written in `buildReinforcement`;
  - read and cleared in `RemoveReinforcement` (thermite, called from GadgetService.luau:358).
  - Nothing removed an entry when the map reloaded, so the fix adds the same `Destroying`
    clean-up the barricades already had.
- `barricades` (doorway → boards), `server/FortifyService.luau`:
  - read in the reach check (Unbarricade) and in `finish` (Unbarricade);
  - written in `buildBarricade`, which `Prepare` calls for exterior slots at every map load;
  - cleared by the boards' existing `Destroying` handler. Only the table type changed.
- `lastBeep` (device → time of last beep), `client/Abilities/GadgetWarnings.luau`:
  - read and written only in `update`.
  - Now pruned at the top of `update`: any device no longer in the Deployables folder is dropped
    (went off, shot, or a new round swept it away; also everything if the folder is gone).

"Cleaned up when the gadget is destroyed or the round ends": a new round reloads the map, which
destroys every plate and barricade (their `Destroying` runs) and the Deployables folder (the beep
pruning sees it gone).
