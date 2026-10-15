-- DOWN BUT NOT OUT, like Siege (docs/R6_REFERENCE.md, section 2 "DBNO"): a hit that would kill you
-- in a match puts you on the floor instead, unless it's a headshot, a big overkill (a blast needs
-- less) or your second down this round, or nobody on your team is left standing to pick you up.
-- Downed, your health is a separate small pool that bleeds away; you crawl, or hold your wound to
-- bleed slower. A teammate holds Interact next to you to get you back up. The tunables live here
-- so the server (DBNOService) and the client (DBNOController, MovementController) agree.
-- Character attributes (set by the server):
--   Downed        true while down
--   WasDowned     true once you've been down this life (a second down kills)
--   DownedBy      UserId of whoever put you down (they get the kill if you bleed out)
--   HoldingWound  true while you hold your wound (slower bleed, no crawling)
--   ReviveEndsAt  server time the revive in progress finishes (nil: nobody's on you)
--   RevivedBy     UserId of the teammate picking you up

return {
	DownHealth = 20, -- the down pool: every hit while downed comes off this, 0 = dead
	BleedTime = 25, -- seconds to bleed out from a full pool when nobody touches you
	HoldWoundScale = 0.5, -- holding your wound bleeds this fast (so it lasts twice as long)
	ReviveTime = 5.5, -- seconds a teammate holds Interact to pick you up (the bleed pauses meanwhile)
	ReviveRange = 5, -- studs between the reviver's and the downed player's middles to start
	ReviveBreakRange = 7, -- ...and how far apart they can get before it breaks off
	RevivedHealth = 20, -- what you get back up with (Siege Y7S3.3)
	CrawlSpeed = 1.8, -- studs/s crawling while downed (~0.5 m/s; healthy prone is 2.5)
	KillOverkill = 50, -- a hit this far past your health kills outright (no down)
	BlastKillOverkill = 20, -- explosions kill outright from much less ("most explosives kill")
	LivePhases = { Prep = true, Action = true, Planted = true }, -- you can go down (and bleed) in these
}
