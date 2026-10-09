# Graph Report - roblox game  (2026-10-08)

## Corpus Check
- Corpus is ~47,453 words - fits in a single context window. You may not need a graph.

## Summary
- 354 nodes · 675 edges · 29 communities (18 shown, 11 thin omitted)
- Extraction: 94% EXTRACTED · 6% INFERRED · 0% AMBIGUOUS · INFERRED: 39 edges (avg confidence: 0.85)
- Token cost: 0 input · 0 output

## Community Hubs (Navigation)
- Client HUD & Match UI
- Gunplay, Effects & HUD
- Weapons, Loadouts & Viewmodel
- Third-Person Body Animation
- Procedural Gun Models
- Server Abilities & Rounds
- Client Abilities & Deploy Arms
- Movement Controller
- Audio & Footsteps
- Map Loading & Test Arena
- House & Lobby Maps
- Bomb Objective Logic
- Dev Panel & Team Highlights
- Map Builder Primitives
- Knife Melee
- Spectate Camera
- Cover Model
- Lighting Setup

## God Nodes (most connected - your core abstractions)
1. `buildRifle()` - 13 edges
2. `buildSniper()` - 12 edges
3. `box()` - 11 edges
4. `buildSmg()` - 11 edges
5. `buildShotgun()` - 11 edges
6. `fire()` - 11 edges
7. `WeaponController.Start()` - 10 edges
8. `step()` - 10 edges
9. `DeployArms.Play()` - 8 edges
10. `GunModels.MakePart()` - 8 edges

## Surprising Connections (you probably didn't know these)
- `AbilityController.Start()` --calls--> `Sound3D.Play()`  [INFERRED]
  src/client/Abilities/AbilityController.luau → src/client/Audio/Sound3D.luau
- `WeaponController.Start()` --calls--> `Sound3D.Play()`  [INFERRED]
  src/client/Combat/WeaponController.luau → src/client/Audio/Sound3D.luau
- `Effects.Sound()` --calls--> `SoundCache.New()`  [INFERRED]
  src/client/Combat/Effects.luau → src/client/Audio/SoundCache.luau
- `swing()` --calls--> `Effects.Sound()`  [INFERRED]
  src/client/Combat/Melee.luau → src/client/Combat/Effects.luau
- `screen()` --calls--> `label()`  [INFERRED]
  src/server/Maps/Lobby.luau → src/client/Combat/Hud.luau

## Import Cycles
- None detected.

## Communities (29 total, 11 thin omitted)

### Community 0 - "Client HUD & Match UI"
Cohesion: 0.06
Nodes (16): addArrow(), build(), DamageIndicator.Start(), watchHealth(), isFree(), remember(), update(), wrapAngle() (+8 more)

### Community 1 - "Gunplay, Effects & HUD"
Cohesion: 0.13
Nodes (26): effectPart(), Effects.Impact(), Effects.Sound(), Effects.Tracer(), frame(), Hud.HitMarker(), Hud.SetAmmo(), Hud.SetCrosshair() (+18 more)

### Community 2 - "Weapons, Loadouts & Viewmodel"
Cohesion: 0.11
Nodes (19): Viewmodel:Update(), apply(), generateOptions(), keysOf(), LoadoutService.FinishRound(), LoadoutService.Reset(), LoadoutService.Start(), LoadoutService.StartRound() (+11 more)

### Community 3 - "Third-Person Body Animation"
Cohesion: 0.15
Nodes (18): GunModels.Build(), animate(), basis(), BodyAnimator.Start(), buildSide(), destroyGun(), easeInOut(), ensureGun() (+10 more)

### Community 4 - "Procedural Gun Models"
Cohesion: 0.37
Nodes (21): addGrip(), addSight(), attach(), beam(), box(), buildRevolver(), buildRifle(), buildShotgun() (+13 more)

### Community 5 - "Server Abilities & Rounds"
Cohesion: 0.11
Nodes (4): AbilityService.ClearDeployables(), AbilityService.Start(), aliveRoot(), getDeployables()

### Community 6 - "Client Abilities & Deploy Arms"
Cohesion: 0.16
Nodes (15): AbilityController.Start(), endDeploy(), pulseWave(), revealCharacters(), startDeploy(), build(), DeployArms.Play(), DeployArms.Stop() (+7 more)

### Community 7 - "Movement Controller"
Cohesion: 0.31
Nodes (17): canStandUp(), cleanupCharacter(), endSlide(), findWall(), flat(), hasAbility(), isGrounded(), lookDirection() (+9 more)

### Community 8 - "Audio & Footsteps"
Cohesion: 0.18
Nodes (9): isGrounded(), update(), isOccluded(), Sound3D.Play(), collectIds(), getFolder(), SoundCache.New(), SoundCache.PreloadAll() (+1 more)

### Community 9 - "Map Loading & Test Arena"
Cohesion: 0.17
Nodes (8): Dummies.ClearAll(), Dummies.ClearSpawned(), Dummies.Spawn(), getFolder(), MapService.Load(), MapService.Start(), block(), TestArena.Build()

### Community 10 - "House & Lobby Maps"
Cohesion: 0.29
Nodes (12): buildGroundFloor(), buildOutside(), buildUpstairs(), car(), door(), House.Build(), prop(), tree() (+4 more)

### Community 11 - "Bomb Objective Logic"
Cohesion: 0.30
Nodes (12): aliveRoot(), canInteract(), clearInteractors(), defuse(), detonate(), getSites(), ObjectiveService.BeginRound(), ObjectiveService.EndRound() (+4 more)

### Community 12 - "Dev Panel & Team Highlights"
Cohesion: 0.29
Nodes (10): build(), button(), choiceGrid(), DevPanel.Start(), heading(), refreshAll(), setOpen(), styleButton() (+2 more)

### Community 13 - "Map Builder Primitives"
Cohesion: 0.26
Nodes (6): MapBuilder.Box(), MapBuilder.Floor(), MapBuilder.FloorWithHole(), MapBuilder.Light(), MapBuilder.Part(), MapBuilder.StairsZ()

### Community 15 - "Knife Melee"
Cohesion: 0.36
Nodes (6): buildKnife(), findTarget(), knifeOffset(), makePart(), Melee.Start(), swing()

### Community 16 - "Spectate Camera"
Cohesion: 0.47
Nodes (8): candidates(), cycle(), humanoidOf(), Spectate.Start(), spectateMode(), startSpectating(), stopSpectating(), update()

### Community 17 - "Cover Model"
Cohesion: 0.67
Nodes (6): attach(), block(), CoverModel.Build(), cylinder(), placed(), wedge()

### Community 18 - "Lighting Setup"
Cohesion: 0.60
Nodes (5): LightingService.Start(), setupAtmosphere(), setupLighting(), setupPostEffects(), setupSky()

## Knowledge Gaps
- **11 thin communities (<3 nodes) omitted from report** — run `graphify query` to explore isolated nodes.

## Suggested Questions
_Questions this graph is uniquely positioned to answer:_

- **Why does `GunModels.Build()` connect `Third-Person Body Animation` to `Procedural Gun Models`?**
  _High betweenness centrality (0.101) - this node is a cross-community bridge._
- **Should `Client HUD & Match UI` be split into smaller, more focused modules?**
  _Cohesion score 0.06464646464646465 - nodes in this community are weakly interconnected._
- **Why does `label()` connect `Gunplay, Effects & HUD` to `House & Lobby Maps`?**
  _High betweenness centrality (0.053) - this node is a cross-community bridge._
- **Should `Gunplay, Effects & HUD` be split into smaller, more focused modules?**
  _Cohesion score 0.12903225806451613 - nodes in this community are weakly interconnected._
- **Should `Weapons, Loadouts & Viewmodel` be split into smaller, more focused modules?**
  _Cohesion score 0.11494252873563218 - nodes in this community are weakly interconnected._
- **Should `Third-Person Body Animation` be split into smaller, more focused modules?**
  _Cohesion score 0.14666666666666667 - nodes in this community are weakly interconnected._
- **Should `Server Abilities & Rounds` be split into smaller, more focused modules?**
  _Cohesion score 0.10952380952380952 - nodes in this community are weakly interconnected._