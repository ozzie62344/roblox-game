# Rainbow Six Siege Mechanics Reference for Breachpoint

A reference for developers rebuilding Siege's core loop in Roblox. Researched October 2026. The live game is **Y11S3 "Operation Split Fire"** (launched 1 Sep 2026, latest patch Y11S3.1 on 22 Sep 2026). "Siege X" (Y10S1, June 2025) was the last big core overhaul.

**How sure each number is**

- **[P]**: taken from an Ubisoft patch or designer note, or a patch summary that quotes one. The season is given.
- **[W]**: taken from a community wiki (Fandom, wiki.gg, Liquipedia) or a stat site. Usually right, but it can be a few seasons out of date.
- **[~]**: approximate, community-measured, or from long-standing game knowledge that I could not check against a source this session. Treat it as a starting value to tune.

Ubisoft does not publish many base values, such as walk speed, lean angle, bleed-out time and drone speed. Where that is the case, the number is marked [~] and should be tuned in playtests. Don't treat it as canon.

**Roblox unit note.** By default, 1 stud is about 0.28 m (Roblox's character scale). If Breachpoint uses that scale, multiply metres by about 3.57 to get studs. Example: 5 m/s is about 17.9 studs/s. If the game uses its own scale, convert once in a shared `MatchConfig` constant. Don't scatter magic numbers.

---

## 1. Movement

### Speed tiers (speed rating vs health rating)

Siege trades speed against health. Each operator has a speed rating and a health rating that add up to 4: 3-speed/1-health, 2/2, or 1/3. Ubisoft re-rated many operators in Y7S4 and still moves them around; Y10S4 changed Mute from 1-speed to 2-speed and Ace from 2-speed to 1-speed [P].

| Rating | Health | Base movement (wiki approx.) | Relative |
|---|---|---|---|
| 3-speed | 100 HP | ~5.0 m/s | 100% [W] |
| 2-speed | 110 HP | ~4.5 m/s | 90% [W] |
| 1-speed | 125 HP | ~3.75 m/s | 75% [W] |
| Heavy shield up (Montagne, Fuze shield) | n/a | ~3.375 m/s | 67.5% [W] |
| Blitz (shield) | n/a | ~3.6 m/s | 71% [W] |
| Blackbeard, rifle shield out | n/a | ~3.125 m/s | 62.5% [W] |
| **Any operator while aiming down sights (ADS)** | n/a | **2.34 m/s, flat for everyone** | Y7S4 [P] |

- **ADS equalization (Y7S4).** Before Y7S4, 2-speed operators moved at 2.6 m/s while aiming and 3-speed operators at 2.73 m/s. Now every operator moves at 2.34 m/s while ADS, which was already the 1-speed value [P]. This matters a lot: speed helps you rotate between fights but gives no advantage once a gunfight starts.
- **Weapon and attachment modifiers.** LMGs give -10% movement speed (Y9S1) [P]. The horizontal grip gives +5% movement speed (Y9S1) [P].
- **Walk vs sprint vs crouch** [~]. The wiki's tier speeds behave like default run speeds. Sprint is about 1.3–1.4× run. Crouch-walk is about 50–60% of run. Prone is a slow crawl of about 0.6–1.0 m/s. A Y11S1.1 bug fix put prone speed back to its old, slower value, so prone is meant to be slow [P].
- **Acceleration** [~]. Siege has almost no momentum: you reach full speed in about 0.1–0.15 s and stop just as fast. That makes strafe-peeking (A-D spam) and quick stops very effective. There's no sliding and no bunny-hop, and jumping is replaced by vaulting.
- **Movement slowdowns.** Barbed wire slows attackers by 50% and blocks sprinting. It doesn't affect defenders [W]. Electrified surfaces slow you rather than damaging you (Y10S2) [P]. Clash's taser slows more the closer you are to her (Y10S2) [P].

### Lean

- Free lean (Q/E) works in any stance, while ADS, while holding a grenade, and while strafing [P, Ubisoft "Behind the Wall"]. Leaning without ADS has been on PC from the start and reached console in Y8 [W].
- Angle and offset [~]: roughly 15–20° of camera roll, with the head and gun moving about 0.4–0.5 m sideways. The transition takes about 0.15–0.2 s and can be canceled instantly by pressing the other lean.
- Leaning moves the hitbox, so a leaning player mostly shows head and shoulder. That is why one headshot from any gun kills, and why leaning is both strong and risky.

### Vaulting and climbing [~]

- You can vault anything up to about waist or hip height (about 1.0–1.1 m): tables, counters, low walls and open windows. Taller ledges up to about chest height (about 1.4–1.6 m) use a slower climb. Anything taller needs a ladder or rappel.
- A vault takes about 0.5–0.8 s and a climb about 1.0–1.3 s. A sprint-vault is noticeably faster and keeps momentum.
- You can vault through a damaged window barricade. Hitting the boards below the window twice makes it vaultable [W].
- Shield operators drop ADS while vaulting (Y10S2) [P].

### Rappel

- Attackers can rappel from rooftops and ledges outside the building. You can:
  - aim, shoot, reload and throw while hanging;
  - invert (hang upside down) to peek through windows from above;
  - rappel-breach through a window.
  [P, Ubisoft]
- **Siege X (Y10S1)** made rappel faster to start, let players sprint along walls, and let them rotate around corners onto the next wall [P/press].
- **Rappel breach (Y10S2).** You no longer need a breach charge or a pre-damaged barricade. You go through only if the barricade has enough damage by the end of the action. Otherwise you bounce off and damage it with your feet [P].
- Blackbeard can't ADS or break a full-health barricade while rappelling in (Y10S3) [P].

### Sprint-out time [~]

- Sprint-to-fire is about 0.2–0.35 s, depending on weapon class (pistol fastest, LMG slowest).
- ADS from a sprint is slower than ADS from a walk, by the same proportion as the Y9S1 ADS nerf [P]. See the weapon section for ADS times.

**How this should feel.** Movement is snappy and low-inertia, and gunfights happen at one shared slow ADS speed. Fast operators win rotations, not duels. Lean should be an instant, cancelable action you use constantly, never a slow animation.

Sources:
- https://tomclancy.wiki.gg/wiki/Rainbow_Six:Armor_and_Speed
- https://gameriv.com/rainbow-six-siege-y7s4-pre-season-designers-notes-speed-health-recoil-changes-and-more/
- https://siege.gg/news/y7s4-rainbow-six-siege-pre-season-designers-notes-alibi-loses-15x-scope-operator-speed-changes-tweaks-to-weapons
- https://www.ggrecon.com/guides/rainbow-six-siege-y9s1-patch-notes
- https://www.ubisoft.com/en-us/game/rainbow-six/siege/news-updates/8dJbwMqIt5Y8lZgwJRjWZ/y10s2-designers-notes
- https://www.ubisoft.com/en-gb/game/rainbow-six/siege/news-updates/1XzWbYPWo59u7NgZVDjaIm/y10s4-designers-notes
- https://www.ubisoft.com/en-us/game/rainbow-six/siege/news-updates/4MERFPCTtVYWfVgtrZX6iu/behind-the-wall-series-cover-and-lean
- https://siege.gg/news/how-to-lean-without-aiming-on-xbox-in-siege
- https://tomclancy.wiki.gg/wiki/Rainbow_Six:Barbed_Wire
- https://tomclancy.wiki.gg/wiki/Rainbow_Six:Barricade
- https://patched.gg/games/rainbow-six-siege/y11s11-patch-notes
- https://press-start.com.au/previews/2025/03/14/rainbow-six-siege-x-hands-on-preview-the-most-ambitious-update-yet/
- https://mp1st.com/title-updates-and-patches/rainbow-six-siege-x-y10s3-update-patch-3-08-1-000-113

---

## 2. Health and damage

### Health model: the current system and the old one

| | Before Y6S3 (armor era) | Y6S3 "Crystal Guard" to now (HP era) |
|---|---|---|
| 1-armor / light | 100 HP, 0% damage resistance | **100 HP** |
| 2-armor / medium | 100 HP, ~10% damage resistance | **110 HP** |
| 3-armor / heavy | 100 HP, ~20% damage resistance | **125 HP** (140 was tried on the test server) |
| Rook's armor pack | Raised the armor rating and guaranteed DBNO | **+20 HP max** (Y6S3 to Y11S1). **+25 HP from Y11S1.1 (Mar 2026)**. Also grants Withstand (Y7S3.3) |

[W] for the ratings. [P] for Rook's +25 (Y11S1.1) and for Withstand (Y7S3.3).

- **Use the HP version.** Damage resistance was removed in Crystal Guard. Armor is now simply extra health [W].
- **Withstand** (from Rook's plate) lets a downed player get back up on their own once. Revived players come back with **20 HP** (Y7S3.3) [P].
- **Overheal** is capped at **+20 HP** (Y7S3.3, down from 40) [P]. Doc's stim heals up to 200 HP, so in practice it's a full heal plus the overheal cap [P].

### Hit zones

| Zone | Multiplier |
|---|---|
| Head | **Instant kill from any bullet weapon at any range, including pistols** [P, Ubisoft] |
| Body (torso and arms) | 100% |
| Legs | **75%**. Y10S2 lowered it to 50–70% by class. **Y10S4.1 (Dec 2025) put it back to 75%** [P] |

- The Y10S2 limb values are kept here as a tuning reference. Handguns and machine pistols 50%. SMGs and ARs 50/60/65% (small, medium, high calibre). LMGs, DMRs, snipers and slugs 70%. Revolvers 60% [P].
- **Shotguns** [~]. Buckshot pellets don't get the guaranteed headshot kill the way rifle bullets do; each pellet does pellet damage with limited headshot bonus. Slugs behave like rifle rounds.
- **Shields.** Ballistic and deployable shields stop bullets entirely, so you need explosives, melee (stagger), flanks, or a headshot or foot past the edge of the shield. A Sledge hammer hit knocks shield operators back (Y10S2) [P]. A shield operator's melee does 65 HP (Y9S1) [P]. Shield operators can't be lethal while fully protected (Y10S2 design rule) [P].

### Damage drop-off [~]

These are long-standing community-measured shapes; Ubisoft doesn't publish curves.

| Class | Full damage to | Drops to minimum by | Minimum |
|---|---|---|---|
| ARs, most SMGs | ~25 m | ~35–40 m | ~60–70% |
| Handguns, machine pistols, small SMGs | ~12–15 m | ~25–30 m | ~55–65% |
| LMGs | ~25 m | ~40 m | ~70% |
| DMRs, snipers | No meaningful drop-off inside map ranges | n/a | n/a |
| Buckshot shotguns | ~5–10 m | ~20–25 m (pellets vanish around 40 m) | 68% at max range on some (2020 patch) [W] |

- The **extended barrel** doesn't push back the start of drop-off. It cuts the drop-off amount by about 15–20% [W].

### DBNO (down but not out)

- **What downs you.** Non-headshot damage that takes you to 0 HP. Headshots, big overkill, and most explosives kill outright [W].
- **One down per round.** A second down in the same round kills you [W].
- **Downed health.** You have a separate **20 HP** pool, and any further damage beyond that kills [W].
- **Bleed-out** is the same for every health rating [W]. Total time is about 20–30 s with no interaction [~]. Holding your wound halves the bleed rate, so it lasts about twice as long [W].
- **Crawling.** You can crawl at about 0.5 m/s [~] instead of holding the wound, and crawling leaves a blood trail [W]. Downed players can't shoot or use gadgets, but they can still talk and ping.
- **Reviving.** A teammate holds interact for about 5–6 s [~], and the bleed timer pauses while they do [W]. The player comes back with 20 HP [P]. Doc's stim pistol revives at range [P].
- **Self-revive** is limited to Withstand (Rook plates [P]) and similar operator abilities.
- **Finishing.** Shoot or melee the downed player. Their remaining 20 HP goes quickly.
- **Interrogation.** Caveira can kill a downed attacker with an interrogation, which reveals that attacker's teammates.

**How this should feel.** Every encounter is one click from death: whoever lands the headshot first wins, whatever their health or speed. Health tiers only decide body-shot TTK. A down should be a tense rescue chance, not a second life. Keep the downed state short, keep it clearly loud and visible, and kill on the second down.

Sources:
- https://tomclancy.wiki.gg/wiki/Rainbow_Six:Armor_and_Speed
- https://patched.gg/games/rainbow-six-siege/y11s11-patch-notes
- https://siege.gg/news/y7s33-maintenance-docs-stim-pistol-now-heals-200hp-dokkaebi-to-affect-dead-defenders-on-cameras-rooks-armor-plates-grant-withstand
- https://www.ubisoft.com/en-us/game/rainbow-six/siege/news-updates/8dJbwMqIt5Y8lZgwJRjWZ/y10s2-designers-notes
- https://mp1st.com/title-updates-and-patches/rainbow-six-siege-y10s4-1-update-patch-3-17-1-000-122
- https://www.ubisoft.com/en-us/game/rainbow-six/siege/news-updates/4MERFPCTtVYWfVgtrZX6iu/behind-the-wall-series-cover-and-lean
- https://rainbowsix.fandom.com/wiki/Down_But_Not_Out
- https://rainbowsix.fandom.com/wiki/Extended_Barrel
- https://liquipedia.net/rainbowsix/TCSG12

---

## 3. Weapons

### Representative stats (Liquipedia, read Oct 2026, plus newer patch overrides)

| Weapon | Class | Damage | RPM | Mag |
|---|---|---|---|---|
| R4-C | AR | 39 | 860 | 30 |
| AK-12 | AR | 45 (Y7S4 cut it to 40; check the live value) | 850 | 30 |
| F2 | AR | 37 | 980 | 25 |
| 552 / C8-SFW / M762 class | AR | 40–45 | 690–840 | 30 |
| MP5 | SMG | 27 | 800 | 30 |
| P90 | SMG | 22 | 970 | 50 |
| Vector .45 | SMG | 23 | 1200 | 25 |
| M12 | SMG | 42 (Y11S1.1, was 40) [P] | ~550 | 30 |
| POF-9 | AR | 37 (Y11S1.1, was 35) [P] | ~740 | 50 |
| M249 | LMG | 48 | 650 | 100 |
| 6P41 | LMG | 46 | 680 | 100 |
| 417 / CAMRS | DMR (semi-auto) | 69 | semi | 20 |
| M590A1 | Pump shotgun | 48 per pellet × 8 | pump | 7 |
| M1014 | Semi-auto shotgun | **30 per pellet (Y11S3.1, was 28)** [P] | semi | 8 |
| SPAS-15 | Semi-auto shotgun | **26 per pellet (Y11S3.1, was 24)** [P] | semi | 6–7 |
| P226 Mk 25 | Pistol | 50 | semi | 15 |
| D-50 | Hand cannon | 71 | semi | 7 |
| SMG-11 | Machine pistol | 32 | 1270 | 16 |
| SMG-12 | Machine pistol | 28 | 1270 | 32 |
| Super Shorty | Secondary shotgun | 35 per pellet | pump | 2 |

Values are [W] unless marked [P]. Liquipedia can trail live patches by a season or two.

**Breachpoint archetypes.** Use these as starting points:

- AR: ~40 damage, ~800 RPM, 30+1 rounds.
- SMG: ~28 damage, ~850 RPM, 30+1 rounds.
- LMG: ~47 damage, ~650 RPM, 100 rounds, -10% movement.
- DMR: ~65–70 damage, semi-auto, 20+1 rounds.
- Pump shotgun: ~45 × 8 pellets.
- Pistol: ~50 damage, 15+1 rounds.
- Machine pistol: ~30 damage, ~1200 RPM, 16–32 rounds.

At 100 HP, a 40-damage AR takes 3 body shots to down a 100 HP or 110 HP target and 4 for a 125 HP target.

### ADS time (Y9S1 values, from idle or walking) [P]

| Class | ADS (ms) | Before Y9S1 |
|---|---|---|
| Handgun, revolver, hand cannon | 240 | 200 |
| Shotgun (buckshot) | 340 | 250 |
| Machine pistol | 380 | 280 |
| SMG | 460 | 300 |
| AR, DMR, sniper, slug shotgun | 520 | 400 |
| LMG | 560 | 450 |
| Ballistic shield | 500 walking / 550 sprinting | 600 |

- **Sight modifiers.** Iron sights give +10% ADS speed, non-magnified optics +5%, and the laser +10% (Y9S1) [P].
- **ADS from sprint** is slower by the same proportion [P].

### Recoil

- **Structure.** A strong **first-shot kick**, then a mostly vertical climb with a horizontal "diamond" wobble. Each gun has a "worst part" that starts after N bullets. For example, the Type-89 got worse from bullet 15 instead of 12 in Y10S4 [P].
- **The pattern is learnable** and has very little random spread, which is why players aim for the head and let recoil pull them up. Ubisoft has adjusted patterns in several seasons so random headshots don't land outside the reticle tip.
- **Platform split.** PC got more vertical and horizontal recoil in Y7S3, with LMGs hit hardest, and console recoil is now tuned separately [P].

| Attachment | Effect (current) |
|---|---|
| Flash hider | Reduces vertical recoil (about -20%) [~] and hides most muzzle flash |
| Compensator | **-35% horizontal recoil** (Y8S1, up from 15%) [P] |
| Muzzle brake | **-50% first-shot kick** (Y8S1, up from 45%) and faster re-centering between taps. Best on semi-autos [P] |
| Suppressor | **No damage penalty since Y7S3** (it used to be -12.5%). Quieter, less flash, and no hit-marker sound giveaway [P] |
| Extended barrel | Less damage drop-off (about 15–20%) [W] |
| Vertical grip | **+20% vertical recoil control** (Y9S1, down from 25%) [P] |
| Angled grip | **+20% reload speed** (Y9S1). Its old ADS bonus (about -32% ADS time) was removed [P] |
| Horizontal grip (the old "none") | **+5% movement speed** (Y9S1) [P] |
| Laser | **+10% ADS speed** (Y9S1). It no longer helps hipfire [P] |

### Reloads

- **Tactical reload** (rounds still in the magazine) keeps the chambered round, so you get 30+1 on closed-bolt guns.
- **Empty reload** is about 1 s slower because the operator has to chamber a round [W]. The slowest AR empty reload is the 556xi at 3.7 s [W].
- **Typical times** [~]:

  | Class | Tactical | Empty |
  |---|---|---|
  | AR | ~2.3–2.6 s | ~3.0–3.4 s |
  | SMG | ~2.0–2.4 s | ~2.8–3.2 s |
  | LMG | ~4.5–6 s | slower than tactical |
  | Pump shotgun | ~0.5 s per shell | 0.5 s per shell |

- **Reload cancel (Y8S1).** Canceling mid-reload leaves you with one round in the chamber and no magazine. You can no longer bank a full magazine by canceling [P].

### Hipfire and bloom

- **Same hipfire spread in every stance** since Y7S4. Crouching or going prone no longer tightens hipfire [P].
- **Bloom.** Spread grows with sustained fire ("burst growth" is tuned per gun, Y7S4.2) and grows while moving [P/~].
- **Typical spread** [~]: SMG and shotgun hipfire is usable within about 5 m. AR and DMR hipfire is much wider; DMRs got their hipfire spread nerfed in Y7S4.2 [P].

### Scopes

- The available steps are 1.0× (red dot, holo, reflex), 1.5×, 2.0×, 2.5×, 3.0×, 3.5× and, for snipers, 8×. Kali's CSRX 300 got 3.5× and 8× options in Y11S3 [P].
- Ubisoft keeps limiting magnified scopes (2×+) on support operators. Y10S3 removed them from Goyo, Doc, Rook, Frost, Echo, Tachanka and Castle [P].
- **Field of view** [~]: zoom = baseFOV / magnification. Higher magnification should cost a little ADS time.

**How this should feel.** Time to kill is short. Bullets do high damage, there's a strong first-shot kick, and a learnable vertical pull rewards crosshair placement at head height. Attachments are small, readable trade-offs: horizontal or vertical recoil, reload, ADS, or movement. Reload is a commitment, and the chambered round is a small reward for reloading early.

Sources:
- https://liquipedia.net/rainbowsix/R4-C
- https://liquipedia.net/rainbowsix/AK-12
- https://liquipedia.net/rainbowsix/MP5
- https://liquipedia.net/rainbowsix/Vector_.45_ACP
- https://liquipedia.net/rainbowsix/P90
- https://liquipedia.net/rainbowsix/M249
- https://liquipedia.net/rainbowsix/417
- https://liquipedia.net/rainbowsix/M590A1
- https://liquipedia.net/rainbowsix/SMG-11
- https://liquipedia.net/rainbowsix/D-50
- https://www.ggrecon.com/guides/rainbow-six-siege-y9s1-patch-notes
- https://www.ubisoft.com/en-gb/game/rainbow-six/siege/game-info/seasons/commandingforce
- https://siege.gg/news/y7s3-pre-season-designers-notes-finka-to-lose-grenades-iana-to-lose-gonne-6-weapon-recoil-changes
- https://www.ubisoft.com/en-us/game/rainbow-six/siege/news-updates/1r7yfAmRYIeW6tDH75tuqs/y7s42-designers-notes
- https://www.ubisoft.com/en-gb/game/rainbow-six/siege/news-updates/1XzWbYPWo59u7NgZVDjaIm/y10s4-designers-notes
- https://tomclancy.wiki.gg/wiki/Rainbow_Six:Angled_Grip
- https://rainbowsix.fandom.com/wiki/Muzzle_Brake
- https://rainbowsix.fandom.com/wiki/Compensator
- https://www.nme.com/features/rainbow-six-siege-operation-commanding-force-will-make-the-game-more-tactical-3400618
- https://rainbowsix.fandom.com/wiki/556xi
- https://mp1st.com/?p=315087
- https://patched.gg/games/rainbow-six-siege/y11s11-patch-notes
- https://mp1st.com/title-updates-and-patches/rainbow-six-siege-x-y10s3-update-patch-3-08-1-000-113
- https://mp1st.com/title-updates-and-patches/rainbow-six-siege-split-fire-update-released-september-1-patch-3-46-1-000-151

---

## 4. Round flow (bomb mode)

### Phase timeline

| Phase | Length | What happens |
|---|---|---|
| Map ban and operator ban (ranked) | ~15–20 s per step [~] | Each team bans 1 map from a pool, then **2 operator bans per team** [W] |
| Operator select | ~30–45 s [~] | Unique operators per team. **Defenders choose the bomb site** and **attackers choose their spawn point** (usually 3–4 outside spawns). Attackers can repick after seeing the site in ranked ("attacking repick") [W] |
| Preparation (drone) phase | **45 s** [W] | Defenders reinforce, place gadgets and barricades, and can shoot drones. Attackers drone from spawn. **No friendly fire during prep** (Y7S4) [P] |
| Action phase | **3:00** [W] | Attackers enter the building. Defenders leaving the building are revealed after a short grace period (2 s historically) [W] |
| Plant | **7 s** plant (+0.5 s start animation) [W] | Attackers plant only inside a bomb site. A plant started before 0:00 can finish after the timer runs out [W] |
| Post-plant | **45 s** defuser countdown replaces the round timer [W] | Defenders must **disable** the defuser: **7 s** (+0.5 s), set since Ember Rise in 2019 [P/W] |

### Defuser

- At the start of the round, one random attacker carries it.
- If the carrier dies, it drops and any attacker can pick it up. Defenders can't pick it up, but they can hold the area around it.
- Once planted, it can only be disabled, not moved.

### Win conditions

- **Attackers win** if they:
  - kill all defenders, or
  - plant and the 45 s countdown finishes.
- **Defenders win** if:
  - all attackers die before a plant, or
  - time runs out with no plant and no plant in progress, or
  - they disable the planted defuser.
- After a plant, killing every attacker does **not** win the round. Defenders still have to disable the defuser.

### Match format (ranked, Y9–Y11)

- First to **4 rounds**. Sides **swap after round 3**.
- At **3–3, overtime** is first to 5, so up to **3 extra rounds**, with sides alternating [W]. Quick/unranked is shorter (historically first to 3).

### Economy and resources

- **Reinforcements.** A shared **pool of 10 per defending team** since Shadow Legacy (Y5S3). A failed or canceled reinforcement goes back into the pool [P/W]. Each one takes about **4.5 s** to place, and you have to hold the button for the whole time [W].
- **Drones.** **2 per attacker**: one for prep and one for action. If your prep drone survives, you keep it into the action phase [W]. Twitch swaps hers for 2 Shock Drones [W].
- **Barricades.** Defenders can put up unlimited wooden barricades on doors and windows [~].
- **Spawn-peek and spawn-kill rules.** Pro rules don't allow killing attackers in the first 2 s of the action phase (2025 Ubisoft rulebook) [W]. In matchmaking, defenders who leave the building get revealed to attackers [W].

**How this should feel.** The round is short and has a clear shape. Prep is information and fortification, the first 60 s of action is clearing outside and gathering information, and the last 60 s is a forced execute. The plant should be a long, interruptible, loud commitment. The 45 s post-plant should make defenders retake, not hide.

Sources:
- https://rainbowsix.fandom.com/wiki/Bomb_(Siege)
- https://siege.gg/news/ranked
- https://rainbowsix.fandom.com/wiki/Ranked
- https://pcgamer.com/a-basic-guide-ranked-play-in-rainbow-six-siege
- https://mp1st.com/news/rainbow-six-siege-update-1-71-patch-notes-operation-ember-rise-now-live-heres-whats-new
- https://mp1st.com/news/rainbow-6-siege-year-5-season-3-patch-notes-for-operation-shadow-legacy-revealed
- https://rainbowsix.fandom.com/wiki/Reinforcement
- https://siege.gg/news/how-to-drone-in-rainbow-six-siege
- https://gameriv.com/rainbow-six-siege-y7s4-pre-season-designers-notes-speed-health-recoil-changes-and-more/
- https://www.findershopping.com.au/ubisoft-weighs-in-on-rainbow-six-sieges-divisive-two-second-defender-exit-window
- https://staticctf.ubisoft.com/177v1kh0db6l/1XNmcTeiAklhke8ZakXGQP/175376ab02833893e1cee4d770f4f82b/Rainbow_Six_Siege_Rulebook_2025.pdf

---

## 5. Gadgets and the counter web

Siege balances most gadgets in **counter pairs**.

- Each attacker carries 1 unique gadget plus 1 secondary gadget from a short list: breach charges, hard breach charge, frags, flashbangs, smokes, claymore, impact EMP.
- Each defender carries 1 unique gadget plus 1 secondary gadget: barbed wire, deployable shield, nitro cell, impact grenades, bulletproof camera, proximity alarm, observation blocker.

### Counter system

| Defender tool | What it does | Countered by |
|---|---|---|
| **Mute's signal disruptors** (~4) | Since Y10S4 they jam **wireless signals** crossing a **2.475 m radius** (it was 2.225 m). That blocks drones and remotely triggered charges, such as Thermite's charge and Hibana's X-Kairos. It does **not** stop automatic or manual devices such as Ace's SELMA or Maverick's torch [P] | Thatcher's E.G.S. disruptor, impact EMP, shooting it, Twitch's drone, Ash or Zofia from range |
| **Bandit / Kaid electricity** | Electrifies reinforced walls, barbed wire, shields and (Y10S4) Castle panels. Since Y10S2 it **destroys electronic gadgets that touch it** but **doesn't damage operators**; it slows players who interact with or walk on electrified surfaces instead. It's neutral and affects both teams [P]. Kaid's claw activates in 3.5 s (Y11S1.3) [P] | EMP or Thatcher, shooting the battery, Maverick, Ace (SELMA isn't electronic-triggered), "Bandit tricking" (placing the battery after the charge so it zaps it) |
| Reinforced wall or hatch | Blocks soft breaching and melee | Hard breachers: Thermite (**3 charges since Y10S4**, damage 220, Y11S3.1), Hibana (X-Kairos, 4 s breach, Y10S4), Ace (SELMA), Maverick (torch), **hard breach charge** (2 s to place, 4 s fuse, not remote) [P/W] |
| Barbed wire | 50% slow, no sprint, noisy. 2 melee hits to clear (1 Sledge hit). Bullets don't destroy it [W] | Melee, explosives, Sledge |
| Deployable shield | Bulletproof cover | Explosives, Sledge, frags from above |
| Nitro cell (C4) | Remote-detonated, kills through soft walls and floors, 1 per defender [~] | Mute doesn't apply here (it's a defender device). Countered by Jäger-style threats and IQ-style detection |
| Defender impact grenades | Open hatches, floors and walls from inside | None |
| Bulletproof camera | Information, with an EMP pulse in the DSEG family | EMP |

| Attacker tool | Numbers |
|---|---|
| Soft breach charge (~2–3 per op) | ~2 s to place [~]. Opens a person-sized hole in a soft wall, a door or window barricade, or an unreinforced hatch. Kills anyone standing right behind it |
| Frag grenade (2) | ~3 s fuse [~], lethal within ~2–3 m and damaging out to ~5 m [~]. Breaks barricades [W] |
| Stun / flashbang (2–3) | Fuse ~2–3 s (sources disagree). **Blinds and deafens for 5 s**: full blind out to **11 m** if facing it, **3 m** if facing away [W] |
| Smoke grenade (2) | ~10–12 s cloud [~]. Hides planting |
| Claymore (1) | Tripwire laser. **155 damage** (Y11S3) [P] |
| Impact EMP (2) | Disables electronics. Since Y10S4 the DSEG family also disables **all** sights and optics and blocks remote triggering. Re-applying refreshes the timer [P] |
| Thatcher E.G.S. disruptor (Y10S4) | 6 charges, 10 m range, **3.5 m × 10 m beam** (it was a 5.2 m sphere EMP). Shows each gadget's disable time [P] |
| Kapkan trap (defender) | **62 damage** (Y11S3) [P] |

### HUD indicators and timing

- **Thrown gadgets show a HUD warning icon** to players nearby: frags, impact grenades, flashbangs, nitro cells, Fenrir gas. The icon points toward the device when it lands near you [~].
- **Arming or ticking gadgets beep** (breach charges, Thermite's burn).
- Pinged gadgets stay marked for the team while they stay in view [W].
- **Throw** [~]:

  | Action | Time |
  |---|---|
  | Quick throw | ~0.6–0.8 s |
  | Overhand throw | ~0.8–1.0 s |
  | Underhand roll | ~0.8–1.0 s |
  | Placed gadget (batteries, jammers, claymores) | ~1.0–1.5 s |
  | Reinforcement | 4.5 s |

- Two-handed actions, such as placing a breach charge, can be canceled instantly back to shooting [P, Ubisoft].

**How this should feel.** Each gadget should answer something specific, and each should have a counter both sides can see. Teams should feel they're "using up" the enemy's counters, for example killing the Thatcher before the Thermite can breach. Keep counts small (2–4) so every use matters.

Sources:
- https://www.ubisoft.com/en-gb/game/rainbow-six/siege/news-updates/1XzWbYPWo59u7NgZVDjaIm/y10s4-designers-notes
- https://www.ubisoft.com/en-us/game/rainbow-six/siege/news-updates/8dJbwMqIt5Y8lZgwJRjWZ/y10s2-designers-notes
- https://alviran.net/blog/r6-mute-guide-2026/
- https://alviran.net/blog/r6-bandit-guide-2026/
- https://mp1st.com/?p=315087
- https://mp1st.com/title-updates-and-patches/rainbow-six-siege-split-fire-update-released-september-1-patch-3-46-1-000-151
- https://mp1st.com/title-updates-and-patches/rainbow-six-siege-update-may-5-delivers-y11s1-3-balance-changes-patch-3-36-1-000-141
- https://www.ubisoft.com/en-us/game/rainbow-six/siege/news-updates/1iA0mBrzRBQjtnEhHSlC5G/launch-game-guide-part-2
- https://tomclancy.wiki.gg/wiki/Rainbow_Six:Barbed_Wire
- https://siege.gg/news/stun-grenade
- https://liquipedia.net/rainbowsix/Portal:Equipment
- https://www.windowscentral.com/rainbow-six-siege-ping-system-finally-getting-apex-legends-style-overhaul
- https://www.ubisoft.com/en-us/game/rainbow-six/siege/news-updates/4MERFPCTtVYWfVgtrZX6iu/behind-the-wall-series-cover-and-lean

---

## 6. Destruction

### Surface types

| Surface | Breakable by | Notes |
|---|---|---|
| **Soft wall** (drywall or wood) | Bullets make pinholes. Melee makes round holes [W]. Shotguns make fist-sized holes. Explosives open it fully | Split into about 2–3 reinforceable sections [W] |
| **Reinforced wall** | Hard breach only (Thermite, Hibana, Ace, Maverick, hard breach charge). Ash's rounds don't work; they're also blocked by electricity since Y10S4 [P] | Since Y10S4 a full line has to be cut before the reinforcement comes away [P] |
| **Floors and ceilings** (soft, inside) | Explosives and Sledge open them. Bullets and shotguns make holes for vertical play | Only a few floors per map are breakable |
| **Hatch** (floor trapdoor) | Unreinforced: breach charge, nitro cell, impact grenade, frag, Sledge, Buck. Melee is possible but very slow [W]. Reinforced: needs a hard breach (Thermite, Ace, Hibana, Maverick, hard breach charge) [W] | Uses the same reinforcement pool |
| **Barricade** (door or window) | **3 melee hits** anywhere on the fabric, or **about 20 rifle, SMG or pistol rounds**. Shotguns break it in 2–3 close shells. Explosives always break it [W] | Defenders can pull it down; attackers can vault or rappel through a damaged one [W/P] |
| **Castle armor panel** | **10 melee hits** (Y11S3.1, was 9). Explosives and electricity destroy it [P] | Max 3 per Castle [P] |
| **Hard cover** (concrete, metal, outside walls) | Indestructible | |

### Murder holes and rotation holes

- **Murder hole.** A small hole (fist to head size) cut through a soft wall or a reinforcement seam with bullets, melee or a shotgun, used for sightlines. Players open these during prep.
- **Rotation hole.** A crouch-height or person-sized gap made with melee (6–10 hits), a shotgun, an impact grenade or a breach charge, used to move between rooms without doors.
- **Vertical holes** (from above or below) through floors and ceilings, opened by Buck's or Sledge's tools or by shotguns, are a core attacker tactic.

### Damage needed [~]

| Method | Soft wall |
|---|---|
| Melee | ~10 cm round hole per hit; ~4–6 hits for a peek hole |
| Buckshot shell | ~25–40 cm hole up close |
| Breach charge or impact grenade | Opens the whole section or a person-sized hole |
| Rifle round | ~2–3 cm pinhole each |

### Bullet penetration

- Bullets go through soft walls, wooden floors, furniture and barricades. Overturned tables don't stop fire [P, Ubisoft].
- They don't go through reinforced walls, concrete, metal or shields.
- Siege doesn't clearly scale damage down through soft material; penetration acts roughly binary with a small loss [~]. Don't be generous here: wallbangs should hurt.

### Siege X additions (Y10S1)

- **Explosive gas pipes** make a fire wall that blocks rotations.
- **Fire extinguishers** stun and disorient when shot.
- Smoke detectors and other breakable props also count as "destruction ingredients."

[press/P]

**How this should feel.** Walls are information and weapons, not just geometry. Every bullet hole reveals something, and a site's layout changes during the round. Make destruction progressive (holes grow from many small hits), keep it consistent per material, and replicate it on the server so everyone sees the same holes.

Sources:
- https://tomclancy.wiki.gg/wiki/Rainbow_Six:Barricade
- https://rainbowsix.fandom.com/wiki/Destruction
- https://rainbowsix.fandom.com/wiki/Reinforcement
- https://rainbowsix.fandom.com/wiki/Breach_Charge/Siege
- https://www.ubisoft.com/en-gb/game/rainbow-six/siege/news-updates/1XzWbYPWo59u7NgZVDjaIm/y10s4-designers-notes
- https://www.ubisoft.com/en-us/game/rainbow-six/siege/news-updates/8dJbwMqIt5Y8lZgwJRjWZ/y10s2-designers-notes
- https://mp1st.com/?p=315087
- https://www.ubisoft.com/en-us/game/rainbow-six/siege/news-updates/1iA0mBrzRBQjtnEhHSlC5G/launch-game-guide-part-2
- https://www.ubisoft.com/en-us/game/rainbow-six/siege/news-updates/4MERFPCTtVYWfVgtrZX6iu/behind-the-wall-series-cover-and-lean
- https://press-start.com.au/previews/2025/03/14/rainbow-six-siege-x-hands-on-preview-the-most-ambitious-update-yet/
- https://lootlevelchill.com/news/rainbow-six-siege-x-year-10-roadmap-revealed/

---

## 7. Sound

Sound is Siege's second radar, and Ubisoft rebuilt it for Siege X ("Audio 2.0"). The rebuild reworked how sound travels and echoes so that walls, height and distance change what you hear, which makes direction and range easier to read [press/P].

### Footsteps [~]

These ranges are community-observed, not official.

| Movement | Audible to an attentive listener |
|---|---|
| Sprint | ~20–25 m, and clearly through one floor |
| Walk | ~12–15 m |
| Crouch-walk | ~5–8 m; masked by gunfire, audible in quiet 1v1s [W] |
| Prone, standing still | Silent |

- **1-speed (heavy) operators and shield operators are louder** [W].
- **Surfaces.** Debris, glass and metal are louder than carpet. Barbed wire rustles [W]. Electrified surfaces crackle.
- **Through floors.** Sound is muffled and lower-pitched. Siege X also reworked occlusion levels, with exceptions that keep gameplay sounds like footsteps and door kicks readable [press].

### Combat sounds [~]

- **Gunfire.** Unsuppressed fire carries map-wide. The suppressor reduces the range and the flash, and with no damage penalty since Y7S3 it's a pure trade-off [P].
- **Reload.** Magazine-out and bolt sounds carry about 10 m and tell the enemy to push.
- **Gadgets.** Placing a breach charge, Thermite's burn, a drone's whine, a reinforcement going up and a barricade breaking each have a distinct, readable sound. Breaking a barricade gives a defender away [W].
- **Locating enemies.** Players use stereo direction, how loud a sound is, floor muffling, and familiar triggers (vault, reinforcement, barricade break, hatch, reload) to place enemies before they see them.

**How this should feel.** You should be able to close your eyes and know "someone is sprinting above me, top-left." Crouch-walk should be a real stealth tool, and sprinting should always be a risk. Map each movement state to a clear, loud-enough sound bank per surface. Use Roblox's 3D falloff plus an occlusion low-pass filter when a floor or wall is between source and listener.

Sources:
- https://www.ginx.tv/en/interview-creative-director-siege-x-changes
- https://press-start.com.au/previews/2025/03/14/rainbow-six-siege-x-hands-on-preview-the-most-ambitious-update-yet/
- https://siege.gg/news/siege-x-how-to-fix-audio
- https://gamersdecide.com/articles/rainbow-6-siege-best-audio-settings
- https://steamcommunity.com/app/359550/discussions/0/154643795212375790
- https://steamdb.info/patchnotes/6420364
- https://tomclancy.wiki.gg/wiki/Rainbow_Six:Barricade
- https://tomclancy.wiki.gg/wiki/Rainbow_Six:Barbed_Wire

---

## 8. Spotting, drones and cameras

- **Drones** (2 per attacker [W])
  - **Movement** [~]: small, fast, low. About 3–4 m/s, with a hop on a ~3 s cooldown [W].
  - **Durability:** they die to almost any single bullet or melee [~].
  - **Line of sight:** they fit under door barricades through the bottom gap [W], but electrified barbed wire stops them [P].
  - **Death:** the attacker gets a static screen. Shooting a drone gives away the shooter's position [W].
  - **Count and recharge:** each attacker is limited to their own drones. Some special drones recharge; Echo's Yokai has a 2 s hop cooldown [W] and he has 3 of them since Y10S4.2 [P].
- **Pinging and spotting**
  - **Enemy players:** spotting one through a drone or camera puts a marker on them for your team. The marker is short-lived, about **3–5 s**, and refreshes while they stay in view [~]. It also flags their operator icon in the top bar [W].
  - **Gadgets:** under Ping 2.0, pinged gadgets stay marked as long as teammates can see them [W].
  - **Location:** location pings are neutral yellow markers [W].
- **Defender cameras** [~]
  - Each map has about 4–8 fixed building cameras. They're destructible, and attackers shoot them early.
  - Any defender can cycle through them (live or dead), and dead players act as camera operators. Bulletproof cameras are a defender secondary gadget.
- **Defender extras**
  - Valkyrie: 3 sticky Black Eye cameras that any defender can watch [P, Ubisoft].
  - Maestro: 2 bulletproof Evil Eye laser turret cameras with a **9 s battery** (Y11S3.1) [P].
  - Pulse: heartbeat sensor, 10 m range through walls [P, Ubisoft].
- **Attacker extras**
  - Twitch's Shock Drones can zap gadgets [W].
  - Jackal tracks footprints: blue (oldest) prints last 120 s and no prints are made during prep (Y10S2) [P]. In Y11S1.2 he gained the ability to scan prints from below through broken ceilings [P].

**How this should feel.** Information is spent and destroyed. Defenders kill drones in prep, and attackers shoot cameras on entry. Spotted markers should be brief and must be refreshed, so a call goes stale fast. Never give a permanent wallhack.

Sources:
- https://siege.gg/news/how-to-drone-in-rainbow-six-siege
- https://rainbowsix.fandom.com/wiki/Drone
- https://www.ubisoft.com/en-us/game/rainbow-six/siege/news-updates/1iA0mBrzRBQjtnEhHSlC5G/launch-game-guide-part-2
- https://tomclancy.wiki.gg/wiki/Rainbow_Six:Barricade
- https://www.ubisoft.com/en-us/game/rainbow-six/siege/game-info/operators/valkyrie
- https://mp1st.com/?p=315087
- https://siege.gg/news/y10s42-patch-notes-revealed-echo-to-have-three-yokai-drones-mozzie-gets-shorty-back-and-more-confirmed-buffs
- https://rainbowsix.fandom.com/wiki/Rainbow_Six_Siege_patches/Patch_5.4.3
- https://www.ubisoft.com/en-us/game/rainbow-six/siege/news-updates/8dJbwMqIt5Y8lZgwJRjWZ/y10s2-designers-notes
- https://www.strafe.com/news/read/r6s-y11s1-1-new-changes-designers-notes/
- https://www.windowscentral.com/rainbow-six-siege-ping-system-finally-getting-apex-legends-style-overhaul
- https://www.gamestar.de/artikel/rainbow-six-siege-zukunft-ping-system,3354545.html
- https://gamersdecide.com/articles/rainbow-6-siege-best-interface-settings

---

## 9. HUD and feedback

- **Top bar.** The round timer is in the centre with the scores on each side. Five operator portraits per team sit beside them, showing alive, downed (pulsing) or dead (greyed). Enemies show as unknown until they're identified or killed. Spotted enemies light up their portrait [W].
- **Kill feed** (top right) shows killer, weapon icon, headshot icon and victim. It also notes downs and gadget kills.
- **Hit markers.** A small white X on hit and a distinct marker or sound on a kill, with a headshot sound. Downing someone gives different feedback from killing them [~].
- **Damage direction.** A red arc around the crosshair points toward the source. Gadget warning icons also point toward nearby grenades or charges [~].
- **Objective markers.** Bomb-site icons with distance (attackers see them after site selection or droning). After a plant, there's a defuser icon and a 45 s countdown in place of the timer [W].
- **Lower HUD.** Health (number plus bar), ammo as magazine plus reserve (shown as 30+1), gadget counts, drone count for attackers, and the team's remaining reinforcements for defenders.
- **Crosshair.** A small dynamic hipfire crosshair that grows with bloom and movement. Many players turn it off, and it disappears on ADS [~].
- **Spectating dead players.** Defenders use cameras. Attackers see their team's drones and their teammates' points of view.

**How this should feel.** The HUD stays quiet until something matters. The top bar is the main source of information (who's alive, who's spotted). Hits should read instantly through sound, and a headshot kill needs its own unmistakable sound.

Sources:
- https://gamersdecide.com/articles/rainbow-6-siege-best-interface-settings
- https://www.ubisoft.com/en-us/game/rainbow-six/siege/news-updates/1iA0mBrzRBQjtnEhHSlC5G/launch-game-guide-part-2
- https://rainbowsix.fandom.com/wiki/Bomb_(Siege)
- https://mp1st.com/title-updates-and-patches/rainbow-six-siege-y11s1-silent-hunt-solid-snake-patch-3-28-1-000-133

---

## 10. Feel details veteran players notice

1. **Peeker's advantage is real, and Ubisoft accepts it as a design fact.**
   - The server checks every shot. The victim's reaction window is roughly the peeker's reaction time minus the *victim's* ping. Peeker's advantage depends only on the victim's connection [P, Ubisoft dev blog].
   - Movement is client-predicted ("ghosting"), because server-authoritative movement would add input lag [P].
   - For Breachpoint: predict movement on the client, check hits on the server with lag compensation (rewind about 100–200 ms), and cap the rewind so high-ping players can't abuse it.
2. **Holding an angle beats wide swings, except when someone peeks fast.** Defenders hold off-angles and use murder holes. Attackers counter with quick jiggle-peeks and lean taps.
3. **Lean spam** (fast Q-E-Q while strafing) moves the head hitbox constantly. Lean needs to be instant and cancelable, and the hitbox has to follow the animation on the server. If remote clients see the lean late, it feels unfair.
4. **Prefiring angles.** Because one headshot kills and recoil starts with a kick, players shoot at common head-height spots before seeing anyone, and wallbang through soft walls. This only works if bullets go through walls and do full damage.
5. **Vertical play.** Attackers open floors from above (Sledge or Buck, shotguns, impact grenades) and shoot down through holes. Defenders shoot up through soft ceilings at feet. Breakable floors and ceilings are what make Siege feel different from other shooters.
6. **Crosshair at head height while clearing.** All ADS movement runs at the same 2.34 m/s, so duels come down to crosshair placement and the first headshot, not strafe speed [P].
7. **Information first.** Drones, cameras, pings and sound decide most rounds before a shot is fired. If Breachpoint's drones are fragile but plentiful and cameras are easy to shoot, the round shape follows naturally.
8. **Gadget trades.** Attackers kill electronics before the hard breach, and defenders kill the hard breacher before they reach the wall. Every counter needs visible tells: beeps, sparks, a jammer's glow.
9. **The sound of the round:** a reinforcement going up, a barricade being smashed, a breach charge beeping, a defuser being planted. Each needs a unique, loud sample the whole team learns.
10. **Things that feel wrong if you miss them:**
    - Floaty acceleration.
    - Slow lean.
    - Random spread while ADS.
    - Headshots that don't kill.
    - Walls bullets can't pass through.
    - Long downed states.
    - Long, uncancelable gadget animations.
    - Spawn-killing at the start of the round. Siege handles this with the 2 s rule in pro play, defender reveal outside the building, and attacker spawn choice.

**How this should feel.** Tense, quiet and lethal: you gather information slowly, then the fight is over in 300 ms. The player should always feel they died because of where they stood or what they heard, not because of random spread or netcode.

Sources:
- https://mp1st.com/news/rainbow-6-siege-ping-abuse-explained-by-devs-and-the-steps-to-fix-it
- https://www.ubisoft.com/fr-fr/game/rainbow-six/siege/news-updates/1su64agGqZZQWb0mBeJUem/blog-des-dveloppeurs-abus-de-ping-peekers-advantage-et-prochaines-tapes
- https://www.ubisoft.com/en-us/game/rainbow-six/siege/news-updates/4MERFPCTtVYWfVgtrZX6iu/behind-the-wall-series-cover-and-lean
- https://gameriv.com/rainbow-six-siege-y7s4-pre-season-designers-notes-speed-health-recoil-changes-and-more/
- https://www.findershopping.com.au/ubisoft-weighs-in-on-rainbow-six-sieges-divisive-two-second-defender-exit-window
- https://www.ginx.tv/en/r6-siege-y5s4-2-patch-notes-spawn-peeks-fixed-among-numerous-bug-fixes

---

## Quick-start constants for Breachpoint

Proposed defaults. Speeds are in m/s; multiply by about 3.57 for studs/s at 1 stud ≈ 0.28 m.

```
HP            = {Light = 100, Medium = 110, Heavy = 125}; ArmorPackBonus = 25; OverhealCap = 20
Speed (run)   = {3 = 5.0, 2 = 4.5, 1 = 3.75}; SprintMult = 1.35; CrouchMult = 0.55; ProneSpeed = 0.8
ADSMoveSpeed  = 2.34 (flat for all); LMGMoveMult = 0.90; ShieldMoveMult = 0.675
HeadMult      = instant kill (bullets); BodyMult = 1.0; LimbMult = 0.75
ADS_ms        = {Pistol = 240, Shotgun = 340, MachinePistol = 380, SMG = 460, AR = 520, DMR = 520, LMG = 560}
DBNO          = {Pool = 20, BleedSeconds = 25, HoldWoundMult = 0.5, ReviveSeconds = 5.5, RevivedHP = 20, SecondDownKills = true}
Round         = {PrepSeconds = 45, ActionSeconds = 180, PlantSeconds = 7, DefuserSeconds = 45, DisableSeconds = 7}
Match         = {WinRounds = 4, SwapAfter = 3, OvertimeAt = 3, OvertimeWin = 5}
Team          = {Reinforcements = 10, ReinforceSeconds = 4.5, DronesPerAttacker = 2}
Barricade     = {MeleeHits = 3, BulletHits = 20}
Stun          = {BlindSeconds = 5, FacingRange = 11, AwayRange = 3}
BarbedWire    = {SlowMult = 0.5, NoSprint = true, MeleeHits = 2}
Attachments   = {Compensator_HRecoil = -0.35, MuzzleBrake_FirstShot = -0.50, VertGrip_VRecoil = -0.20,
                 AngledGrip_Reload = +0.20, HorizGrip_Move = +0.05, Laser_ADS = +0.10, Suppressor_Damage = 0}
```
