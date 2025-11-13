-- ChunkGenerator (ServerScriptService)
-- ---------------------------------------------------------------
-- Same script as before, but now it calls
-- ChunkPicker:generateChunkForBiome(cellX, cellZ, biome)
-- ---------------------------------------------------------------

local RunService   = game:GetService("RunService")
local Players      = game:GetService("Players")
local Workspace    = game:GetService("Workspace")
local Replicated   = game:GetService("ReplicatedStorage")

-- -----------------------------------------------------------------
-- CONFIGURATION (unchanged)
-- -----------------------------------------------------------------
local CHUNK_SIZE      = 100
local LOAD_RADIUS     = 4
local UNLOAD_BUFFER   = 2
local UNLOAD_DISTANCE = LOAD_RADIUS + UNLOAD_BUFFER

local NOISE_SCALE = 0.02
local BIOME_THRESHOLDS = {
	Grasslands   = 55,
	Desert       = 85,
	SnowyPlains  = 100,
}

-- -----------------------------------------------------------------
-- INTERNAL STATE
-- -----------------------------------------------------------------
local generated = {}
local function cellKey(x, z) return x .. "_" .. z end

-- -----------------------------------------------------------------
-- 1️⃣ Deterministic base biome map (unchanged)
-- -----------------------------------------------------------------
local function getBaseBiome(cellX, cellZ)
	local n = math.noise(cellX * NOISE_SCALE, cellZ * NOISE_SCALE)
	local pct = (n + 1) * 50
	for biome, threshold in pairs(BIOME_THRESHOLDS) do
		if pct <= threshold then
			return biome
		end
	end
	return "Grasslands"
end

-- -----------------------------------------------------------------
-- 2️⃣ Chunk creation (now passes the biome to the picker)
-- -----------------------------------------------------------------
local ChunkPicker = require(game.ServerStorage.ChunkPicker)

local function createChunkAt(cellX, cellZ)
	local key = cellKey(cellX, cellZ)
	if generated[key] then return end   -- already present

	local biome = getBaseBiome(cellX, cellZ)   -- <-- deterministic biome

	-- Ask the picker **for this specific biome**
	local chunk, pickedBiome, category = ChunkPicker:generateChunkForBiome(cellX, cellZ, biome)

	-- The biome should always match now; keep the warning just in case something goes wrong.
	if pickedBiome ~= biome then
		warn(("Biome mismatch at %s: map=%s, picker=%s"):format(key, biome, pickedBiome))
	end

	chunk:SetPrimaryPartCFrame(
		CFrame.new(cellX * CHUNK_SIZE, 0, cellZ * CHUNK_SIZE)
	)
	local parentFolder = Workspace:FindFirstChild("Chunks") or Workspace
	chunk.Parent = parentFolder
	generated[key] = chunk
end

-- -----------------------------------------------------------------
-- 3️⃣ Unload far cells (unchanged)
-- -----------------------------------------------------------------
local function unloadFarCells(playerPos)
	local pcx = math.floor(playerPos.X / CHUNK_SIZE + 0.5)
	local pcz = math.floor(playerPos.Z / CHUNK_SIZE + 0.5)

	for key, model in pairs(generated) do
		local sx, sz = string.match(key, "(%-?%d+)_(%-?%d+)")
		local gx, gz = tonumber(sx), tonumber(sz)

		if math.abs(gx - pcx) > UNLOAD_DISTANCE or math.abs(gz - pcz) > UNLOAD_DISTANCE then
			model:Destroy()
			generated[key] = nil
		end
	end
end

-- -----------------------------------------------------------------
-- 4️⃣ Per‑player generation loop (unchanged)
-- -----------------------------------------------------------------
local function runGenerationLoop(player)
	while player.Parent do
		local character = player.Character
		if character and character.PrimaryPart then
			local pos = character.PrimaryPart.Position
			local cx = math.floor(pos.X / CHUNK_SIZE + 0.5)
			local cz = math.floor(pos.Z / CHUNK_SIZE + 0.5)

			for dx = -LOAD_RADIUS, LOAD_RADIUS do
				for dz = -LOAD_RADIUS, LOAD_RADIUS do
					local gx, gz = cx + dx, cz + dz
					createChunkAt(gx, gz)   -- now biome‑consistent
				end
			end

			unloadFarCells(pos)
		end
		RunService.Heartbeat:Wait()
	end
end

-- -----------------------------------------------------------------
-- 5️⃣ Player connection handling (unchanged)
-- -----------------------------------------------------------------
Players.PlayerAdded:Connect(function(plr)
	spawn(function() runGenerationLoop(plr) end)
end)

Players.PlayerRemoving:Connect(function(plr) end)

print("[ChunkGenerator] World‑generation system (biome‑consistent) initialized.")