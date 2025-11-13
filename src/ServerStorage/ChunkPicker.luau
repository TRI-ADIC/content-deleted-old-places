-- ChunkPicker (ServerStorage)
-- ---------------------------------------------------------------
-- This module now expects the caller to supply the biome that
-- should be used for the cell.  It only handles:
--   • picking a category inside that biome
--   • picking a concrete model inside that category
--   • cloning the model and returning it
-- ---------------------------------------------------------------

local ChunkConfig = require(game.ServerStorage.ChunkConfig)   -- keep path as you had
local Replicated  = game:GetService("ReplicatedStorage")
local TemplatesRoot = Replicated:WaitForChild("ChunkTemplates")

local ChunkPicker = {}

-- -----------------------------------------------------------------
-- Helper: weighted random picker (re‑exposed for convenience)
-- -----------------------------------------------------------------
local function weightedPick(weightTable)
	local total = 0
	for _, w in pairs(weightTable) do
		total = total + w
	end
	if total == 0 then return nil end

	local roll = math.random() * total
	local accum = 0
	for item, w in pairs(weightTable) do
		accum = accum + w
		if roll <= accum then
			return item
		end
	end
end

-- -----------------------------------------------------------------
-- 1️⃣ Pick a *category* inside the supplied biome
-- -----------------------------------------------------------------
function ChunkPicker:pickCategory(biomeName)
	local biomeInfo = assert(ChunkConfig.Biomes[biomeName],
		("Biome %q not defined in ChunkConfig"):format(biomeName))
	return weightedPick(biomeInfo.CategoryWeights)
end

-- -----------------------------------------------------------------
-- 2️⃣ Pick a concrete model name inside that biome+category
-- -----------------------------------------------------------------
function ChunkPicker:pickModelName(biomeName, categoryName)
	local biomeInfo = ChunkConfig.Biomes[biomeName]
	local categoryTable = assert(biomeInfo.Categories[categoryName],
		("Category %q missing for biome %q"):format(categoryName, biomeName))
	return weightedPick(categoryTable)
end

-- -----------------------------------------------------------------
-- 3️⃣ Retrieve the template Model from ReplicatedStorage
-- -----------------------------------------------------------------
function ChunkPicker:getTemplate(biomeName, categoryName, modelName)
	local biomeFolder   = TemplatesRoot:FindFirstChild(biomeName)
	assert(biomeFolder, ("Missing biome folder %q"):format(biomeName))

	local categoryFolder = biomeFolder:FindFirstChild(categoryName)
	assert(categoryFolder,
		("Missing category folder %q under biome %q"):format(categoryName, biomeName))

	local template = categoryFolder:FindFirstChild(modelName)
	assert(template,
		("Missing model %q in %s/%s"):format(modelName, biomeName, categoryName))

	return template
end

-- -----------------------------------------------------------------
-- PUBLIC API – generate a chunk **for a known biome**
-- Returns: cloned Model, biome name (echoed back), category name
-- -----------------------------------------------------------------
function ChunkPicker:generateChunkForBiome(cellX, cellZ, biomeName)
	-- 1️⃣ Choose a category inside the given biome
	local category = self:pickCategory(biomeName)

	-- 2️⃣ Choose a concrete model inside that category
	local modelName = self:pickModelName(biomeName, category)

	-- 3️⃣ Clone the template
	local template = self:getTemplate(biomeName, category, modelName)
	local chunk = template:Clone()

	-- Store a few handy attributes (useful for later gameplay logic)
	chunk:SetAttribute("Biome", biomeName)
	chunk:SetAttribute("Category", category)
	chunk:SetAttribute("CellX", cellX)
	chunk:SetAttribute("CellZ", cellZ)

	return chunk, biomeName, category
end

return ChunkPicker