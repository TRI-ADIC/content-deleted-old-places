-- ChunkGenerator (ServerScriptService)
-- ---------------------------------------------------------------

local RunService   = game:GetService("RunService")
local Players      = game:GetService("Players")
local Workspace    = game:GetService("Workspace")

-- -----------------------------------------------------------------
-- CONFIGURATION
-- -----------------------------------------------------------------
local CHUNK_SIZE      = 100
local LOAD_RADIUS     = 4
local UNLOAD_BUFFER   = 2
local UNLOAD_DISTANCE = LOAD_RADIUS + UNLOAD_BUFFER

local BIOME_NOISE_SCALE = 0.02
local BIOME_THRESHOLDS = {
	Grasslands   = 50,
	Desert       = 80,
	SnowyPlains  = 100,
}

local RANDOM_BIOME_OFFSET_RANGE = 10000   -- how far the offset can wander (studs)

-- Seed the RNG once when the script loads (tick() is a good unique value)
math.randomseed(tick())
local SERVER_BIOME_OFFSET_X = (math.random() * RANDOM_BIOME_OFFSET_RANGE)
local SERVER_BIOME_OFFSET_Z = (math.random() * RANDOM_BIOME_OFFSET_RANGE)

-- ── Base height‑map (large‑scale) ─────────────────────────────────────
local ENABLE_BASE_HEIGHTMAP = false
local BASE_NOISE_SCALE   = 0.02   -- lower = larger hills (covers many cells)
local BASE_AMPLITUDE     = 100      -- maximum vertical swing of the base map (studs)

local ENABLE_RAMPS        = false
local MAX_RAMP_HEIGHT     = 4                  -- studs added at the peak of a ramp
local RAMP_PROBABILITY    = 0.7               -- ~8 % of cells start a ramp
local RAMP_MIN_LENGTH     = 2                  -- at least 2 cells long
local RAMP_MAX_LENGTH     = 5                  -- at most 5 cells long

-- ── Tiny per‑cell jitter (adds texture, not noticeable as a hill) ───────
local ENABLE_JITTER      = false
local JITTER_NOISE_SCALE = 0.7    -- frequency of the fine‑grain noise
local JITTER_AMPLITUDE   = 5     -- ± studs

-- -----------------------------------------------------------------
-- INTERNAL STATE
-- -----------------------------------------------------------------
local generated = {}
local function cellKey(x, z) return x .. "_" .. z end

-----------------------------------------------------------------
-- GLOBAL tables (place them near the top of ChunkGenerator, replacing the old rampState)
-----------------------------------------------------------------
-- key = rampId (integer), value = {
--     startX, startZ   – integer cell coordinates where the ramp began
--     dirX, dirZ       – unit step in X/Z (one of {1,0}, {-1,0}, {0,1}, {0,-1})
--     length           – total cells the ramp occupies (2‑5)
--     step             – how many cells we have already emitted (0 on the first cell)
-- }
local activeRamps = {}
local nextRampId = 0

-----------------------------------------------------------------
-- 0️⃣ Base height map – low‑frequency noise that spans many cells
-----------------------------------------------------------------
local function baseHeightMap(cellX, cellZ)
    -- math.noise returns a value in [-1, 1]
    local n = math.noise(cellX * BASE_NOISE_SCALE, cellZ * BASE_NOISE_SCALE)
    -- Scale to the amplitude you want (both positive and negative)
    return n * BASE_AMPLITUDE
end

-----------------------------------------------------------------
-- 1️⃣ Decide the ramp state for a cell (creates or continues a ramp)
-----------------------------------------------------------------
local function getRampInfo(cellX, cellZ)
    -- First, see if this cell belongs to any active ramp
    for id, ramp in pairs(activeRamps) do
        -- Compute the cell that the ramp would occupy at its current step
        local expectedX = ramp.startX + ramp.dirX * ramp.step
        local expectedZ = ramp.startZ + ramp.dirZ * ramp.step
        if expectedX == cellX and expectedZ == cellZ then
            -- This cell is the *next* step of this ramp
            local progress = ramp.step / (ramp.length - 1)   -- 0 → 1
            local direction = ramp.dirZ ~= 0 and ramp.dirZ or ramp.dirX   -- +1 or -1
            ramp.step = ramp.step + 1
            if ramp.step >= ramp.length then
                activeRamps[id] = nil                     -- ramp finished
            end
            return direction, progress
        end
    end

    -- No active ramp covers this cell – maybe start a brand‑new one?
    if math.random() < RAMP_PROBABILITY then
        nextRampId = nextRampId + 1
        local length = math.random(RAMP_MIN_LENGTH, RAMP_MAX_LENGTH)

        -- Pick a cardinal direction for the ramp to travel
        local dirs = {
            {dx = 1,  dz = 0},   -- East
            {dx = -1, dz = 0},   -- West
            {dx = 0,  dz = 1},   -- South
            {dx = 0,  dz = -1},  -- North
        }
        local choice = dirs[math.random(1, #dirs)]

        -- Store the new ramp; its first cell is the *starting* cell
        activeRamps[nextRampId] = {
            startX = cellX,
            startZ = cellZ,
            dirX   = choice.dx,
            dirZ   = choice.dz,
            length = length,
            step   = 1,               -- we have already placed the first cell
        }

        -- The first cell’s progress is 0 (bottom of the hill)
        return choice.dx ~= 0 and choice.dx or choice.dz, 0
    end

    -- No ramp at all
    return 0, nil
end

-----------------------------------------------------------------
-- 2️⃣ Smooth height with Perlin noise (unchanged)
-----------------------------------------------------------------
local function jitterNoise(cellX, cellZ)
    if not ENABLE_JITTER then
        return 0                         -- jitter disabled → no contribution
    end
    local n = math.noise(cellX * JITTER_NOISE_SCALE,
                         cellZ * JITTER_NOISE_SCALE)   -- [-1,1]
    return n * JITTER_AMPLITUDE          -- ±JITTER_AMPLITUDE studs
end

-----------------------------------------------------------------
-- 3️⃣ Compute the final Y offset for a cell
-----------------------------------------------------------------
local function computeElevation(cellX, cellZ)
    -- ① Base height (large‑scale hills) – only if the flag is true
    local base = 0
    if ENABLE_BASE_HEIGHTMAP then
        base = baseHeightMap(cellX, cellZ)
    end

    -- ② Optional ramp overlay (short steep segments)
    local rampContribution = 0
    if ENABLE_RAMPS then
        local rampDir, rampProgress = getRampInfo(cellX, cellZ)
        if rampDir ~= 0 then
            -- Linear ramp height (0 → MAX_RAMP_HEIGHT) multiplied by direction
            rampContribution = rampProgress * MAX_RAMP_HEIGHT * rampDir
        end
    end

    -- ③ Tiny jitter for texture
    local jitter = jitterNoise(cellX, cellZ)

    -- ④ Sum the layers
    local final = base + rampContribution + jitter

    -- ⑤ Optional flat‑threshold – keep only bumps larger than this
    local MIN_VISIBLE_HEIGHT = 0.4
    if math.abs(final) < MIN_VISIBLE_HEIGHT then
        return 0
    end
    return final
end

-- ------------------------------------------------------------------
-- Helper – pick a random Y‑rotation
---------------------------------------------------------------------
local function randomCardinalRotation()
    -- 0 = North, 90 = East, 180 = South, 270 = West
    local angles = {0, 90, 180, 270}
    local idx = math.random(1, #angles)   -- uniform 1‑4
    return math.rad(angles[idx])          -- convert to radians for CFrame
end

-- -----------------------------------------------------------------
-- 1️⃣ Deterministic base biome map
-- -----------------------------------------------------------------
local function getBaseBiome(cellX, cellZ)
    -- Apply the server‑wide random offset
    local ox, oz = SERVER_BIOME_OFFSET_X, SERVER_BIOME_OFFSET_Z

    -- Noise input (offset added BEFORE scaling)
    local n = math.noise((cellX + ox) * BIOME_NOISE_SCALE,
                         (cellZ + oz) * BIOME_NOISE_SCALE)

    local pct = (n + 1) * 50   -- maps [-1,1] → [0,100]

    for biome, threshold in pairs(BIOME_THRESHOLDS) do
		if pct <= threshold then
			return biome
		end
	end

    return "Grasslands"
end

-- -----------------------------------------------------------------
-- 2️⃣ Chunk creation
-- -----------------------------------------------------------------
local ChunkPicker = require(game.ServerStorage.ChunkPicker)

local function createChunkAt(cellX, cellZ)
    local key = cellKey(cellX, cellZ)
    if generated[key] then return end

    local biome = getBaseBiome(cellX, cellZ)
    local chunk, pickedBiome, category = ChunkPicker:generateChunkForBiome(cellX, cellZ, biome)

    if pickedBiome ~= biome then
        warn(("Biome mismatch at %s: map=%s, picker=%s"):format(key, biome, pickedBiome))
    end

    -- ---------- NEW ELEVATION ----------
    local basePos   = Vector3.new(cellX * CHUNK_SIZE, 0, cellZ * CHUNK_SIZE)
    local elev      = computeElevation(cellX, cellZ)   -- <-- our new function
    local targetPos = basePos + Vector3.new(0, elev, 0)
    -- -------------------------------------

    -- Existing random rotation (25 % N/E/S/W)
    local yRot   = randomCardinalRotation()
    local finalCF = CFrame.new(targetPos) * CFrame.Angles(0, yRot, 0)

    chunk:SetPrimaryPartCFrame(finalCF)

    local parentFolder = Workspace:FindFirstChild("Chunks") or Workspace
    chunk.Parent = parentFolder
    generated[key] = chunk
end

-- -----------------------------------------------------------------
-- 3️⃣ Unload far cells
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
-- 4️⃣ Per‑player generation loop
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
-- 5️⃣ Player connection handling
-- -----------------------------------------------------------------
Players.PlayerAdded:Connect(function(plr)
	spawn(function() runGenerationLoop(plr) end)
end)

Players.PlayerRemoving:Connect(function(plr) end)

print("[ChunkGenerator] World‑generation system (biome‑consistent) initialized.")