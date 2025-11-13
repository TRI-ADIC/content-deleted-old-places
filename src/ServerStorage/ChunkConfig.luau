--[[ --------------------------------------------------------------
   ChunkConfig – central definition of biomes, categories,
   and individual chunk weights.
   All probabilities are expressed as integer “weights”.  
   Higher weight → higher chance.  
   Changing a number here instantly changes generation odds –
   no other script needs to be edited.
--------------------------------------------------------------- ]]

local ChunkConfig = {}

--------------------------------------------------------------------
-- 1️⃣ Global biome weights (how likely a biome is chosen overall)
-- (Not used anymore)
--------------------------------------------------------------------
-- ChunkConfig.BiomeWeights = {
--	Grasslands   = 70,
-- 	Desert       = 20,
-- 	SnowyPlains  = 30,
-- }

--------------------------------------------------------------------
-- 2️⃣ Per‑biome definitions
--------------------------------------------------------------------
ChunkConfig.Biomes = {

	----------------------------------------------------------------
	-- Grasslands
	----------------------------------------------------------------
	Grasslands = {
		-- Relative chance of each *category* inside this biome
		CategoryWeights = {
			GrassChunks    = 90,
			HoleChunks     = 1,
			LandmarkChunks = 10,
			RuinsChunks    = 5,
		},

		-- Individual chunk models inside each category.
		-- The keys must match the exact Model names that sit under
		-- ReplicatedStorage → ChunkTemplates → Grasslands → <Category>.
		Categories = {
			GrassChunks = {
				GrassChunk01 = 80,
				GrassChunk02 = 20,
				GrassChunk03 = 30,
				GrassChunk04 = 1,
				GrassChunk05 = 20,
				GrassChunk06 = 20,
				GrassChunk07 = 40,
				GrassChunk08 = 40,
			},
			HoleChunks = {
				HoleChunk01 = 100,
			},
			LandmarkChunks = {
				LandmarkChunk01 = 5,
				LandmarkChunk02 = 60,
				LandmarkChunk03 = 20,
				LandmarkChunk04 = 1,
			},
			RuinsChunks = {
				RuinsChunk01 = 1,
				RuinsChunk02 = 1,
				RuinsChunk03 = 1,
				RuinsChunk04 = 60,
				RuinsChunk05 = 60,
			},
		},
	},

	----------------------------------------------------------------
	-- Desert
	----------------------------------------------------------------
	Desert = {
		CategoryWeights = {
			DesertChunks   = 95,
			HoleChunks     = 1,
			LandmarkChunks = 10,
			RuinsChunks    = 5,
		},
		Categories = {
			DesertChunks = {
				DesertChunk01 = 95,
				DesertChunk02 = 20,
				DesertChunk03 = 40,
				DesertChunk04 = 1,
				DesertChunk05 = 20,
				DesertChunk06 = 20,
				DesertChunk07 = 40,
			},
			HoleChunks = {
				HoleChunk01 = 100,
			},
			LandmarkChunks = {
				LandmarkChunk01 = 5,
				LandmarkChunk02 = 60,
				LandmarkChunk03 = 20,
				LandmarkChunk04 = 1,
			},
			RuinsChunks = {
				RuinsChunk01 = 1,
				RuinsChunk02 = 1,
				RuinsChunk03 = 1,
				RuinsChunk04 = 60,
				RuinsChunk05 = 60,
			},
		},
	},

	----------------------------------------------------------------
	-- SnowyPlains
	----------------------------------------------------------------
	SnowyPlains = {
		CategoryWeights = {
			SnowChunks     = 90,
			HoleChunks     = 1,
			LandmarkChunks = 15,
			RuinsChunks    = 5,
		},
		Categories = {
			SnowChunks = {
				SnowChunk01 = 90,
				SnowChunk02 = 20,
				SnowChunk03 = 30,
				SnowChunk04 = 1,
				SnowChunk05 = 20,
				SnowChunk06 = 20,
				SnowChunk07 = 40,
				SnowChunk08 = 40,
			},
			HoleChunks = {
				HoleChunk01 = 100,
			},
			LandmarkChunks = {
				LandmarkChunk01 = 5,
				LandmarkChunk02 = 60,
				LandmarkChunk03 = 20,
				LandmarkChunk04 = 1,
			},
			RuinsChunks = {
				RuinsChunk01 = 1,
				RuinsChunk02 = 1,
				RuinsChunk03 = 1,
				RuinsChunk04 = 60,
				RuinsChunk05 = 60,
			},
		},
	},
}

--------------------------------------------------------------------
-- 3️⃣ Utility: weighted random picker (used by later steps)
--------------------------------------------------------------------
--- Returns a random key from a table where values are integer weights.
--- Example: weightedPick({A = 70, B = 30}) → "A" most of the time.
function ChunkConfig.weightedPick(weightTable)
	local total = 0
	for _, w in pairs(weightTable) do
		total = total + w
	end
	-- Guard against empty tables
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

return ChunkConfig