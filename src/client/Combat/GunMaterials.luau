-- A fine-grain surface texture for gun metal, so it doesn't look like flat paint up close: a
-- MaterialVariant in MaterialService (default.project.json; made with Studio's AI material
-- generator, the textures are images on the game owner's account). Scripts can't create
-- MaterialVariants, so it has to be part of the place. GunModels and SkinPainter put Metal parts
-- on "GunFinishMetal"; the texture is tinted by each part's color, so gun colors and skins still
-- show. Its StudsPerTile is tiny because guns are small: the grain has to read on a 0.1-stud pin.
-- (A generated polymer texture was tried for Plastic too: too coarse and too dark, it made
-- stocks look like snakeskin.)

local GunMaterials = {}

local BY_MATERIAL: { [Enum.Material]: string } = {
	[Enum.Material.Metal] = "GunFinishMetal",
}

-- The gun texture for a material ("" = the plain Roblox material)
function GunMaterials.VariantFor(material: Enum.Material): string
	return BY_MATERIAL[material] or ""
end

return GunMaterials
