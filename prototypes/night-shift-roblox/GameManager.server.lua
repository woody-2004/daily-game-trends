--!strict
-- NIGHT SHIFT — co-op horror + hidden traitor (Roblox prototype)
--
-- 3-8 players survive 3 nights in a dark facility. Generators keep the
-- lights (and the central safe zone) running; a monster called the Watcher
-- hunts in the dark. One player is secretly THE MOLE: they win if the crew
-- fails, and they can quietly sabotage generators or lure the Watcher.
-- Each dawn, the crew votes on who to exile.
--
-- Place this Script in ServerScriptService. It builds the arena, monster,
-- flashlights, and all RemoteEvents at runtime — no manual setup needed.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Lighting = game:GetService("Lighting")
local Workspace = game:GetService("Workspace")
local SoundService = game:GetService("SoundService")
local MarketplaceService = game:GetService("MarketplaceService")

Players.CharacterAutoLoads = false

-- ===================== SOUND ASSETS =====================
-- PLACEHOLDERS — I can't verify live Roblox catalog IDs without network
-- access in this build session. Swap these for real free SFX in ~5 min:
-- Studio -> View tab -> Toolbox -> Audio -> search each term below ->
-- right-click a result -> "Copy Asset ID" -> paste the number here.
-- Until swapped, these play silently (invalid ID = no sound, no error).
local SOUND_IDS = {
	ambientDay = "rbxassetid://0", -- search: "wind ambience" / "forest day loop"
	ambientNight = "rbxassetid://0", -- search: "horror ambience" / "dark drone loop"
	generatorHum = "rbxassetid://0", -- search: "machine hum loop" / "generator running"
	generatorFail = "rbxassetid://0", -- search: "electrical zap" / "power down"
	monsterGrowl = "rbxassetid://0", -- search: "monster growl loop" / "creature breathing"
	heartbeat = "rbxassetid://0", -- search: "heartbeat loop"
	killStinger = "rbxassetid://0", -- search: "horror jumpscare stinger"
	dawnChime = "rbxassetid://0", -- search: "morning bell" / "success chime"
	voteBell = "rbxassetid://0", -- search: "dramatic bell" / "tension sting"
	repairTick = "rbxassetid://0", -- search: "mechanical click" / "tool tick"
}

local function makeSound(props: { [string]: any }): Sound
	local s = Instance.new("Sound")
	s.SoundId = props.SoundId or "rbxassetid://0"
	s.Looped = props.Looped or false
	s.Volume = props.Volume or 0.5
	s.RollOffMaxDistance = props.RollOffMaxDistance or 60
	s.RollOffMinDistance = props.RollOffMinDistance or 6
	for k, v in props do
		if k ~= "SoundId" then (s :: any)[k] = v end
	end
	s.Parent = props.Parent
	return s
end

-- ===================== CONFIG =====================
local MIN_PLAYERS = 3 -- 4+ recommended
local NIGHTS = 3
local DAY_SECONDS = 40
local NIGHT_SECONDS = 75
local VOTE_SECONDS = 20
local REVEAL_SECONDS = 20
local LOBBY_COUNTDOWN = 10

local GENERATOR_COUNT = 5
local GEN_DECAY_PER_SEC = 4 -- night only
local GEN_REPAIR_BOOST = 10
local GEN_REVIVE_THRESHOLD = 30 -- broken generator turns back on at this health

local MONSTER_BASE_SPEED = 9
local MONSTER_SPEED_PER_BROKEN_GEN = 3
local MONSTER_KILL_RADIUS = 4.5
local MONSTER_FEAST_PAUSE = 3

local SAFE_ZONE_RADIUS = 14

local MOLE_SABOTAGE_PER_NIGHT = 2
local MOLE_SABOTAGE_DAMAGE = 60
local MOLE_SABOTAGE_COOLDOWN = 20
local MOLE_LURE_PER_NIGHT = 1
local MOLE_LURE_DURATION = 8

local ARENA_SIZE = 220 -- big enough for the haunted town to spread out
local ARENA_CENTER = Vector3.new(0, 0, 0)
local GEN_CIRCLE_RADIUS = 80
local HAUNTED_OBSTACLE_COUNT = 95 -- density of the forest/town maze

-- ===================== REMOTES =====================
local remotes = Instance.new("Folder")
remotes.Name = "NightShiftRemotes"
remotes.Parent = ReplicatedStorage

local function makeRemote(name: string): RemoteEvent
	local r = Instance.new("RemoteEvent")
	r.Name = name
	r.Parent = remotes
	return r
end

local StateSync = makeRemote("StateSync")
local PrivateState = makeRemote("PrivateState")
local Feed = makeRemote("Feed")
local Toast = makeRemote("Toast")
local Reveal = makeRemote("Reveal")
local PlayStinger = makeRemote("PlayStinger") -- arg: sound key, one-shot, plays locally on every client
local SabotageRequest = makeRemote("SabotageRequest")
local LureRequest = makeRemote("LureRequest") -- arg: target UserId
local VoteCast = makeRemote("VoteCast") -- arg: suspect UserId (0 = skip)
local PurchasePass = makeRemote("PurchasePass") -- arg: pass key, opens the Roblox purchase prompt

local function stinger(key: string)
	PlayStinger:FireAllClients(key)
end

-- ===================== STATE =====================
type Crew = {
	player: Player,
	role: string, -- "crew" | "mole"
	ghost: boolean, -- dead or exiled
	exiled: boolean,
	sabotageCharges: number,
	sabotageCooldownUntil: number,
	lureCharges: number,
	vote: number?, -- suspect UserId this dawn
}

type Generator = {
	id: number,
	model: Model,
	body: Part,
	light: PointLight,
	health: number,
	broken: boolean,
	humSound: Sound,
	failSound: Sound,
	repairSound: Sound,
}

local phase = "lobby" -- lobby | day | night | vote | reveal
local nightNumber = 0
local timeLeft = 0
local crew: { [number]: Crew } = {} -- by UserId
local generators: { Generator } = {}
local matchActive = false

-- ===================== ARENA =====================
local arena = Instance.new("Folder")
arena.Name = "NightShiftArena"
arena.Parent = Workspace

local function part(props: { [string]: any }): Part
	local p = Instance.new("Part")
	p.Anchored = true
	p.TopSurface = Enum.SurfaceType.Smooth
	p.BottomSurface = Enum.SurfaceType.Smooth
	for k, v in props do
		(p :: any)[k] = v
	end
	p.Parent = arena
	return p
end

-- Woodland terrain ground: voxel mud with mossy grass and dirt patches.
-- Real terrain (not a flat part) picks up Future-phase lighting, and
-- Decoration = true grows animated grass blades on the Grass material.
local terrain = Workspace.Terrain
terrain.Decoration = true
terrain:FillBlock(CFrame.new(0, -2.5, 0), Vector3.new(ARENA_SIZE + 24, 7, ARENA_SIZE + 24), Enum.Material.Mud)
do
	local random = Random.new(7) -- fixed seed: ground stays stable across matches
	for _ = 1, 140 do
		local x = random:NextNumber(-ARENA_SIZE / 2, ARENA_SIZE / 2)
		local z = random:NextNumber(-ARENA_SIZE / 2, ARENA_SIZE / 2)
		local mat = random:NextInteger(1, 3) == 1 and Enum.Material.Ground or Enum.Material.Grass
		terrain:FillBlock(CFrame.new(x, -1, z), Vector3.new(random:NextNumber(10, 26), 4, random:NextNumber(10, 26)), mat)
	end
	-- Trampled leaf litter around the safe-zone lamp.
	terrain:FillBlock(CFrame.new(0, -1, 0), Vector3.new(SAFE_ZONE_RADIUS * 2.4, 4, SAFE_ZONE_RADIUS * 2.4), Enum.Material.LeafyGrass)
end
for _, w in {
	{ Vector3.new(ARENA_SIZE, 14, 2), Vector3.new(0, 7, ARENA_SIZE / 2) },
	{ Vector3.new(ARENA_SIZE, 14, 2), Vector3.new(0, 7, -ARENA_SIZE / 2) },
	{ Vector3.new(2, 14, ARENA_SIZE), Vector3.new(ARENA_SIZE / 2, 7, 0) },
	{ Vector3.new(2, 14, ARENA_SIZE), Vector3.new(-ARENA_SIZE / 2, 7, 0) },
} do
	part({ Name = "Wall", Size = w[1], Position = w[2], Color = Color3.fromRGB(25, 25, 30), Material = Enum.Material.Slate })
end

-- Scattered interior cover walls (fixed layout so everyone learns the map)
for i, spec in {
	{ Vector3.new(18, 9, 2), Vector3.new(-30, 4.5, 18) }, { Vector3.new(2, 9, 22), Vector3.new(24, 4.5, -26) },
	{ Vector3.new(14, 9, 2), Vector3.new(34, 4.5, 30) }, { Vector3.new(2, 9, 16), Vector3.new(-40, 4.5, -22) },
	{ Vector3.new(12, 9, 2), Vector3.new(6, 4.5, -44) }, { Vector3.new(2, 9, 14), Vector3.new(-8, 4.5, 40) },
} do
	part({ Name = "Cover" .. i, Size = spec[1], Position = spec[2], Color = Color3.fromRGB(30, 30, 36), Material = Enum.Material.Slate })
end

-- Central safe-zone lamp
local lampPost = part({ Name = "LampPost", Size = Vector3.new(1.2, 12, 1.2), Position = Vector3.new(0, 6, 0),
	Color = Color3.fromRGB(60, 60, 60), Material = Enum.Material.Metal })
local lampHead = part({ Name = "LampHead", Size = Vector3.new(3, 1.4, 3), Position = Vector3.new(0, 12.6, 0),
	Color = Color3.fromRGB(255, 235, 180), Material = Enum.Material.Neon })
local lampLight = Instance.new("PointLight")
lampLight.Range = SAFE_ZONE_RADIUS + 8
lampLight.Brightness = 2.5
lampLight.Color = Color3.fromRGB(255, 230, 170)
lampLight.Shadows = true
lampLight.Parent = lampHead

-- Subtle flicker sells the "old bulb" look under Future lighting.
task.spawn(function()
	local rng = Random.new()
	while true do
		task.wait(rng:NextNumber(0.06, 0.2))
		lampLight.Brightness = 2.3 + rng:NextNumber(-0.5, 0.7)
	end
end)

local safeRing = part({ Name = "SafeRing", Shape = Enum.PartType.Cylinder,
	Size = Vector3.new(0.2, SAFE_ZONE_RADIUS * 2, SAFE_ZONE_RADIUS * 2),
	CFrame = CFrame.new(0, 1.4, 0) * CFrame.Angles(0, 0, math.rad(90)),
	Color = Color3.fromRGB(255, 230, 170), Material = Enum.Material.Neon, Transparency = 0.7, CanCollide = false })

local spawnPoint = Instance.new("SpawnLocation")
spawnPoint.Size = Vector3.new(6, 1, 6)
spawnPoint.Position = Vector3.new(0, 1.1, 6)
spawnPoint.Anchored = true
spawnPoint.Transparency = 1
spawnPoint.CanCollide = false
spawnPoint.Parent = arena

-- ===================== HAUNTED ENVIRONMENT GENERATOR =====================
-- Fills the void between the safe zone and the generator ring with a dense
-- maze of dead trees, crumbling brick walls, and rusted debris. Blocks
-- line-of-sight everywhere, so stepping out of the light means isolation.
-- Regenerated every match so no one memorizes the maze.
local hauntedFolder: Folder? = nil

-- A dead tree: leaning cylindrical trunk plus gnarled branches, not a box.
local function makeTree(folder: Folder, random: Random, pos: Vector3)
	local height = random:NextNumber(16, 30)
	local trunkWidth = random:NextNumber(1.6, 3.2)
	local yaw = math.rad(random:NextNumber(0, 360))
	local lean = math.rad(random:NextNumber(-6, 6))
	local trunk = Instance.new("Part")
	trunk.Name = "GnarledTree"
	trunk.Shape = Enum.PartType.Cylinder
	trunk.Size = Vector3.new(height, trunkWidth, trunkWidth)
	trunk.CFrame = CFrame.new(pos + Vector3.new(0, height / 2, 0))
		* CFrame.Angles(0, yaw, math.rad(90) + lean)
	trunk.Anchored = true
	trunk.Material = Enum.Material.Wood
	trunk.Color = Color3.fromRGB(52, 41, 33)
	trunk.Parent = folder
	for _ = 1, random:NextInteger(2, 4) do
		local branchLen = random:NextNumber(5, 10)
		local branchWidth = math.max(0.6, trunkWidth * 0.4)
		local branch = Instance.new("Part")
		branch.Name = "Branch"
		branch.Shape = Enum.PartType.Cylinder
		branch.Size = Vector3.new(branchLen, branchWidth, branchWidth)
		branch.CFrame = CFrame.new(pos + Vector3.new(0, height * random:NextNumber(0.45, 0.9), 0))
			* CFrame.Angles(0, math.rad(random:NextNumber(0, 360)), math.rad(random:NextNumber(15, 55)))
			* CFrame.new(branchLen / 2, 0, 0)
		branch.Anchored = true
		branch.CanCollide = false
		branch.Material = Enum.Material.Wood
		branch.Color = Color3.fromRGB(45, 35, 28)
		branch.Parent = folder
	end
end

-- A crumbling brick wall: 2-3 segments of uneven height, like real ruins.
local function makeRuinedWall(folder: Folder, random: Random, pos: Vector3)
	local width = random:NextNumber(12, 22)
	local height = random:NextNumber(6, 11)
	local base = CFrame.new(pos) * CFrame.Angles(0, math.rad(random:NextNumber(0, 360)), 0)
	local segments = random:NextInteger(2, 3)
	local xOffset = -width / 2
	for _ = 1, segments do
		local segWidth = (width / segments) * random:NextNumber(0.75, 1)
		local segHeight = height * random:NextNumber(0.55, 1)
		local seg = Instance.new("Part")
		seg.Name = "RuinedWall"
		seg.Size = Vector3.new(segWidth, segHeight, 2.4)
		seg.CFrame = base * CFrame.new(xOffset + segWidth / 2, segHeight / 2, 0)
		seg.Anchored = true
		seg.Material = Enum.Material.Brick
		seg.Color = Color3.fromRGB(72, 62, 58)
		seg.Parent = folder
		xOffset += width / segments
	end
end

-- A rusty corrugated shelter with a collapsed, leaning roof sheet.
local function makeDebris(folder: Folder, random: Random, pos: Vector3)
	local base = CFrame.new(pos) * CFrame.Angles(0, math.rad(random:NextNumber(0, 360)), 0)
	local wallHeight = random:NextNumber(7, 11)
	local junk = Instance.new("Part")
	junk.Name = "TownDebris"
	junk.Size = Vector3.new(8, wallHeight, 0.8)
	junk.CFrame = base * CFrame.new(0, wallHeight / 2, 0)
	junk.Anchored = true
	junk.Material = Enum.Material.CorrodedMetal
	junk.Color = Color3.fromRGB(74, 46, 38)
	junk.Parent = folder
	local roof = Instance.new("Part")
	roof.Name = "DebrisRoof"
	roof.Size = Vector3.new(8, 0.6, random:NextNumber(6, 9))
	roof.CFrame = base * CFrame.new(0, wallHeight, roof.Size.Z / 2 - 0.4)
		* CFrame.Angles(math.rad(random:NextNumber(-28, -12)), 0, 0)
	roof.Anchored = true
	roof.Material = Enum.Material.CorrodedMetal
	roof.Color = Color3.fromRGB(60, 40, 34)
	roof.Parent = folder
end

-- A mossy boulder, half-buried in the mud.
local function makeBoulder(folder: Folder, random: Random, pos: Vector3)
	local size = random:NextNumber(2, 6)
	local rock = Instance.new("Part")
	rock.Name = "Boulder"
	rock.Size = Vector3.new(size * random:NextNumber(0.8, 1.4), size, size * random:NextNumber(0.8, 1.4))
	rock.CFrame = CFrame.new(pos + Vector3.new(0, size * 0.25, 0))
		* CFrame.Angles(math.rad(random:NextNumber(0, 360)), math.rad(random:NextNumber(0, 360)), math.rad(random:NextNumber(0, 360)))
	rock.Anchored = true
	rock.CanCollide = size > 3.5
	rock.Material = Enum.Material.Rock
	rock.Color = Color3.fromRGB(68, 74, 66)
	rock.Parent = folder
end

local function generateHauntedMap()
	if hauntedFolder then
		hauntedFolder:Destroy()
	end
	local folder = Instance.new("Folder")
	folder.Name = "HauntedMap"
	folder.Parent = arena
	hauntedFolder = folder

	local random = Random.new()
	for _ = 1, HAUNTED_OBSTACLE_COUNT do
		-- Pick a random spot on the map grid.
		local x = random:NextNumber(-90, 90)
		local z = random:NextNumber(-90, 90)
		local pos = ARENA_CENTER + Vector3.new(x, 0, z)

		-- Don't spawn obstacles on the safe zone or the generator ring.
		if pos.Magnitude > SAFE_ZONE_RADIUS + 2 and pos.Magnitude < GEN_CIRCLE_RADIUS - 12 then
			local choice = random:NextInteger(1, 3)
			if choice == 1 then
				makeTree(folder, random, pos)
			elseif choice == 2 then
				makeRuinedWall(folder, random, pos)
			else
				makeDebris(folder, random, pos)
			end
		end
	end

	-- Boulders scatter the whole arena, including outside the generator ring.
	for _ = 1, 45 do
		local x = random:NextNumber(-ARENA_SIZE / 2 + 8, ARENA_SIZE / 2 - 8)
		local z = random:NextNumber(-ARENA_SIZE / 2 + 8, ARENA_SIZE / 2 - 8)
		local pos = ARENA_CENTER + Vector3.new(x, 0, z)
		if pos.Magnitude > SAFE_ZONE_RADIUS + 2 then
			makeBoulder(folder, random, pos)
		end
	end
end
generateHauntedMap()

-- ===================== AMBIENT VFX =====================
-- Rolling ground mist and drifting fireflies, using textures that ship
-- with the Roblox client (rbxasset://) so nothing needs the catalog.
local function makeEmitterAnchor(name: string, pos: Vector3): Part
	local anchor = Instance.new("Part")
	anchor.Name = name
	anchor.Size = Vector3.new(1, 1, 1)
	anchor.Position = pos
	anchor.Anchored = true
	anchor.CanCollide = false
	anchor.Transparency = 1
	anchor.Parent = arena
	return anchor
end

do
	local rng = Random.new(11)
	for i = 1, 10 do
		local angle = (i / 10) * math.pi * 2
		local radius = rng:NextNumber(20, ARENA_SIZE / 2 - 20)
		local anchor = makeEmitterAnchor("MistEmitter", Vector3.new(math.cos(angle) * radius, 2.5, math.sin(angle) * radius))
		local mist = Instance.new("ParticleEmitter")
		mist.Texture = "rbxasset://textures/particles/smoke_main.dds"
		mist.Size = NumberSequence.new(rng:NextNumber(14, 20), rng:NextNumber(20, 26))
		mist.Transparency = NumberSequence.new({
			NumberSequenceKeypoint.new(0, 1),
			NumberSequenceKeypoint.new(0.3, 0.72),
			NumberSequenceKeypoint.new(1, 1),
		})
		mist.Color = ColorSequence.new(Color3.fromRGB(160, 170, 175))
		mist.Lifetime = NumberRange.new(6, 11)
		mist.Rate = 2
		mist.Speed = NumberRange.new(0.4, 1.2)
		mist.SpreadAngle = Vector2.new(180, 15)
		mist.Rotation = NumberRange.new(0, 360)
		mist.RotSpeed = NumberRange.new(-4, 4)
		mist.LightInfluence = 1
		mist.Parent = anchor
	end
	for _ = 1, 6 do
		local anchor = makeEmitterAnchor("FireflyEmitter",
			Vector3.new(rng:NextNumber(-70, 70), rng:NextNumber(3, 6), rng:NextNumber(-70, 70)))
		local flies = Instance.new("ParticleEmitter")
		flies.Texture = "rbxasset://textures/particles/sparkles_main.dds"
		flies.Size = NumberSequence.new(0.25)
		flies.Color = ColorSequence.new(Color3.fromRGB(180, 220, 120))
		flies.Transparency = NumberSequence.new({
			NumberSequenceKeypoint.new(0, 1),
			NumberSequenceKeypoint.new(0.2, 0.2),
			NumberSequenceKeypoint.new(0.8, 0.3),
			NumberSequenceKeypoint.new(1, 1),
		})
		flies.Lifetime = NumberRange.new(4, 8)
		flies.Rate = 3
		flies.Speed = NumberRange.new(0.3, 0.9)
		flies.SpreadAngle = Vector2.new(180, 180)
		flies.LightEmission = 1
		flies.LightInfluence = 0
		flies.Parent = anchor
	end
end

-- ===================== AMBIENT SOUND =====================
local ambientDaySound = makeSound({
	SoundId = SOUND_IDS.ambientDay, Looped = true, Volume = 0.35, Parent = SoundService,
})
local ambientNightSound = makeSound({
	SoundId = SOUND_IDS.ambientNight, Looped = true, Volume = 0.4, Parent = SoundService,
})

-- Generators
local function buildGenerators()
	for i = 1, GENERATOR_COUNT do
		local angle = (i / GENERATOR_COUNT) * math.pi * 2
		local pos = Vector3.new(math.cos(angle), 0, math.sin(angle)) * GEN_CIRCLE_RADIUS

		local model = Instance.new("Model")
		model.Name = "Generator_" .. i

		local body = Instance.new("Part")
		body.Name = "Body"
		body.Size = Vector3.new(5, 4, 3.5)
		body.Position = pos + Vector3.new(0, 2, 0)
		body.Anchored = true
		body.Color = Color3.fromRGB(70, 110, 70)
		body.Material = Enum.Material.DiamondPlate
		body.Parent = model

		local light = Instance.new("PointLight")
		light.Range = 26
		light.Brightness = 1.6
		light.Color = Color3.fromRGB(200, 255, 200)
		light.Shadows = true
		light.Parent = body

		local prompt = Instance.new("ProximityPrompt")
		prompt.ActionText = "Repair"
		prompt.ObjectText = "Generator G-" .. i
		prompt.HoldDuration = 0.6
		prompt.MaxActivationDistance = 9
		prompt.RequiresLineOfSight = false
		prompt.Parent = body

		local billboard = Instance.new("BillboardGui")
		billboard.Size = UDim2.fromOffset(120, 24)
		billboard.StudsOffset = Vector3.new(0, 3.4, 0)
		billboard.AlwaysOnTop = true
		billboard.Parent = body
		local barBack = Instance.new("Frame")
		barBack.Name = "BarBack"
		barBack.Size = UDim2.new(1, 0, 1, 0)
		barBack.BackgroundColor3 = Color3.fromRGB(20, 20, 20)
		barBack.BorderSizePixel = 0
		barBack.Parent = billboard
		local barFill = Instance.new("Frame")
		barFill.Name = "BarFill"
		barFill.Size = UDim2.new(1, 0, 1, 0)
		barFill.BackgroundColor3 = Color3.fromRGB(120, 220, 120)
		barFill.BorderSizePixel = 0
		barFill.Parent = barBack

		local humSound = makeSound({
			SoundId = SOUND_IDS.generatorHum, Looped = true, Volume = 0.5,
			RollOffMaxDistance = 40, RollOffMinDistance = 4, Parent = body,
		})
		local failSound = makeSound({
			SoundId = SOUND_IDS.generatorFail, Looped = false, Volume = 0.7,
			RollOffMaxDistance = 60, RollOffMinDistance = 4, Parent = body,
		})
		local repairSound = makeSound({
			SoundId = SOUND_IDS.repairTick, Looped = false, Volume = 0.4,
			RollOffMaxDistance = 20, RollOffMinDistance = 3, Parent = body,
		})

		model.Parent = arena
		local gen: Generator = {
			id = i, model = model, body = body, light = light, health = 100, broken = false,
			humSound = humSound, failSound = failSound, repairSound = repairSound,
		}

		prompt.Triggered:Connect(function(who: Player)
			local c = crew[who.UserId]
			if not matchActive or not c or c.ghost then return end
			gen.health = math.min(100, gen.health + GEN_REPAIR_BOOST)
			repairSound:Play()
			if gen.broken and gen.health >= GEN_REVIVE_THRESHOLD then
				gen.broken = false
				Feed:FireAllClients("💡 Generator G-" .. i .. " is back online.")
			end
		end)

		table.insert(generators, gen)
	end
end
buildGenerators()

local function updateGeneratorVisual(gen: Generator)
	gen.light.Enabled = not gen.broken
	gen.body.Color = gen.broken and Color3.fromRGB(90, 45, 45) or Color3.fromRGB(70, 110, 70)
	local billboard = gen.body:FindFirstChildOfClass("BillboardGui")
	local barBack = billboard and billboard:FindFirstChild("BarBack") :: Frame?
	local barFill = barBack and barBack:FindFirstChild("BarFill") :: Frame?
	if barFill then
		local frac = math.clamp(gen.health / 100, 0, 1)
		barFill.Size = UDim2.new(frac, 0, 1, 0)
		barFill.BackgroundColor3 = gen.broken and Color3.fromRGB(160, 60, 60)
			or frac > 0.4 and Color3.fromRGB(120, 220, 120)
			or Color3.fromRGB(255, 195, 74)
	end

	local shouldHum = matchActive and phase == "night" and not gen.broken
	if shouldHum and not gen.humSound.IsPlaying then
		gen.humSound:Play()
	elseif not shouldHum and gen.humSound.IsPlaying then
		gen.humSound:Stop()
	end
end

-- Call exactly once at the moment a generator's health hits zero.
local function markGeneratorBroken(gen: Generator, cause: string)
	gen.health = 0
	gen.broken = true
	gen.humSound:Stop()
	gen.failSound:Play()
	Feed:FireAllClients("🔻 Generator G-" .. gen.id .. " went DARK (" .. cause .. ").")
end

local function brokenCount(): number
	local n = 0
	for _, g in generators do
		if g.broken then n += 1 end
	end
	return n
end

local function safeZoneActive(): boolean
	return brokenCount() < math.ceil(GENERATOR_COUNT / 2)
end

-- ===================== ATMOSPHERE & POST-PROCESSING =====================
-- Showcase-grade visuals: volumetric Atmosphere (replaces classic fog,
-- which Roblox ignores once an Atmosphere exists), filmic color grading,
-- soft bloom, and far-field depth of field. Lighting.Technology is set to
-- Future in the place file (scripts can't change it) so every light here
-- casts real per-pixel shadows.
local atmosphere = Instance.new("Atmosphere")
atmosphere.Parent = Lighting

local colorGrade = Instance.new("ColorCorrectionEffect")
colorGrade.Parent = Lighting

local bloom = Instance.new("BloomEffect")
bloom.Intensity = 0.45
bloom.Size = 28
bloom.Threshold = 1.1
bloom.Parent = Lighting

local depthOfField = Instance.new("DepthOfFieldEffect")
depthOfField.FocusDistance = 25
depthOfField.InFocusRadius = 45
depthOfField.NearIntensity = 0
depthOfField.FarIntensity = 0.3
depthOfField.Parent = Lighting

local sunRays = Instance.new("SunRaysEffect")
sunRays.Intensity = 0.1
sunRays.Spread = 0.6
sunRays.Parent = Lighting

local clouds = Instance.new("Clouds")
clouds.Parent = terrain

-- ===================== LIGHTING =====================
local function setDay()
	-- Overcast woodland afternoon: soft light, thin haze, drifting clouds.
	Lighting.ClockTime = 13
	Lighting.Ambient = Color3.fromRGB(70, 72, 70)
	Lighting.OutdoorAmbient = Color3.fromRGB(96, 100, 96)
	atmosphere.Density = 0.32
	atmosphere.Offset = 0.25
	atmosphere.Color = Color3.fromRGB(199, 199, 190)
	atmosphere.Decay = Color3.fromRGB(106, 112, 125)
	atmosphere.Haze = 1.8
	atmosphere.Glare = 0.3
	colorGrade.Saturation = -0.12
	colorGrade.Contrast = 0.05
	colorGrade.TintColor = Color3.fromRGB(255, 250, 240)
	sunRays.Intensity = 0.12
	clouds.Cover = 0.65
	clouds.Density = 0.25
	clouds.Color = Color3.fromRGB(210, 210, 215)
	if ambientNightSound.IsPlaying then ambientNightSound:Stop() end
	if not ambientDaySound.IsPlaying then ambientDaySound:Play() end
end

local function setNight()
	-- Dead by Daylight midnight: pitch black, shrouded in dense cold mist.
	Lighting.ClockTime = 0
	Lighting.Ambient = Color3.fromRGB(0, 0, 0)
	Lighting.OutdoorAmbient = Color3.fromRGB(15, 15, 20)
	atmosphere.Density = 0.55 -- the treeline dissolves into the murk
	atmosphere.Offset = 0
	atmosphere.Color = Color3.fromRGB(31, 36, 38)
	atmosphere.Decay = Color3.fromRGB(12, 14, 18)
	atmosphere.Haze = 3
	atmosphere.Glare = 0
	colorGrade.Saturation = -0.4
	colorGrade.Contrast = 0.15
	colorGrade.TintColor = Color3.fromRGB(205, 215, 235)
	sunRays.Intensity = 0
	clouds.Cover = 0.85
	clouds.Density = 0.4
	clouds.Color = Color3.fromRGB(25, 28, 34)
	if ambientDaySound.IsPlaying then ambientDaySound:Stop() end
	if not ambientNightSound.IsPlaying then ambientNightSound:Play() end
end
setDay()

-- ===================== FLASHLIGHT + COSMETIC GAME PASSES =====================
-- PLACEHOLDER PASS IDS — create the passes in the Creator Dashboard
-- (your experience -> Monetization -> Passes -> Create), then paste each
-- pass's numeric ID here. IDs of 0 are skipped safely (nothing breaks,
-- nobody owns pass 0). Cosmetic only — no gameplay advantage, so the
-- horror stays fair.
local GAME_PASSES = {
	{ id = 0, name = "Ember Beam", beamColor = Color3.fromRGB(255, 140, 60), handleColor = Color3.fromRGB(120, 50, 20) },
	{ id = 0, name = "Spectral Beam", beamColor = Color3.fromRGB(120, 255, 235), handleColor = Color3.fromRGB(40, 90, 85) },
	{ id = 0, name = "Bloodhunter Beam", beamColor = Color3.fromRGB(255, 60, 80), handleColor = Color3.fromRGB(90, 20, 25) },
}

local ownershipCache: { [number]: { [number]: boolean } } = {} -- userId -> passId -> owns

local function ownsPass(player: Player, passId: number): boolean
	if passId == 0 then return false end
	local userCache = ownershipCache[player.UserId]
	if userCache and userCache[passId] ~= nil then
		return userCache[passId]
	end
	local ok, owns = pcall(function()
		return MarketplaceService:UserOwnsGamePassAsync(player.UserId, passId)
	end)
	local result = ok and owns == true
	ownershipCache[player.UserId] = ownershipCache[player.UserId] or {}
	ownershipCache[player.UserId][passId] = result
	return result
end

local function giveFlashlight(player: Player)
	local backpack = player:FindFirstChildOfClass("Backpack")
	if not backpack or backpack:FindFirstChild("Flashlight") then return end

	-- Default beam; the last owned pass in the list wins.
	local beamColor = Color3.fromRGB(255, 255, 240)
	local handleColor = Color3.fromRGB(40, 40, 40)
	for _, pass in GAME_PASSES do
		if ownsPass(player, pass.id) then
			beamColor = pass.beamColor
			handleColor = pass.handleColor
		end
	end

	local tool = Instance.new("Tool")
	tool.Name = "Flashlight"
	tool.RequiresHandle = true
	local handle = Instance.new("Part")
	handle.Name = "Handle"
	handle.Size = Vector3.new(0.5, 0.5, 1.6)
	handle.Color = handleColor
	handle.Parent = tool
	local spot = Instance.new("SpotLight")
	spot.Range = 45
	spot.Angle = 38
	spot.Brightness = 4
	spot.Face = Enum.NormalId.Front
	spot.Color = beamColor
	spot.Shadows = true -- trees and ruins throw moving shadows in the beam
	spot.Parent = handle
	tool.Parent = backpack
end

PurchasePass.OnServerEvent:Connect(function(player: Player, passIndex: unknown)
	if typeof(passIndex) ~= "number" then return end
	local pass = GAME_PASSES[passIndex :: number]
	if not pass or pass.id == 0 then return end
	MarketplaceService:PromptGamePassPurchase(player, pass.id)
end)

MarketplaceService.PromptGamePassPurchaseFinished:Connect(function(player: Player, passId: number, purchased: boolean)
	if purchased then
		ownershipCache[player.UserId] = ownershipCache[player.UserId] or {}
		ownershipCache[player.UserId][passId] = true
		-- Refresh their flashlight with the new skin.
		local backpack = player:FindFirstChildOfClass("Backpack")
		local oldTool = backpack and backpack:FindFirstChild("Flashlight")
		if oldTool then oldTool:Destroy() end
		local char = player.Character
		local held = char and char:FindFirstChild("Flashlight")
		if held then held:Destroy() end
		giveFlashlight(player)
	end
end)

Players.PlayerRemoving:Connect(function(player)
	ownershipCache[player.UserId] = nil
end)

-- ===================== MONSTER (The Watcher) =====================
local monster = Instance.new("Model")
monster.Name = "TheWatcher"
local core = Instance.new("Part")
core.Name = "Core"
core.Size = Vector3.new(2.4, 6.5, 1.8)
core.Color = Color3.fromRGB(5, 5, 8)
core.Material = Enum.Material.Slate
core.Anchored = true
core.CanCollide = false
core.Parent = monster
for _, offset in { Vector3.new(-0.45, 2.5, -0.95), Vector3.new(0.45, 2.5, -0.95) } do
	local eye = Instance.new("Part")
	eye.Shape = Enum.PartType.Ball
	eye.Size = Vector3.new(0.35, 0.35, 0.35)
	eye.Color = Color3.fromRGB(255, 40, 40)
	eye.Material = Enum.Material.Neon
	eye.Anchored = true
	eye.CanCollide = false
	eye.CFrame = core.CFrame * CFrame.new(offset)
	eye.Parent = monster
end
monster.PrimaryPart = core

local monsterGrowlSound = makeSound({
	SoundId = SOUND_IDS.monsterGrowl, Looped = true, Volume = 0.6,
	RollOffMaxDistance = 70, RollOffMinDistance = 8, Parent = core,
})

local monsterHome = CFrame.new(0, -80, 0) -- hidden below the map by day
monster:PivotTo(monsterHome)
monster.Parent = Workspace

local monsterPos = Vector3.new(0, 3.5, 0)
local feastUntil = 0
local lureTargetUserId: number? = nil
local lureUntil = 0

local function charPos(player: Player): Vector3?
	local char = player.Character
	local hrp = char and char:FindFirstChild("HumanoidRootPart") :: Part?
	return hrp and hrp.Position or nil
end

local function livingCrew(): { Crew }
	local out = {}
	for _, c in crew do
		if not c.ghost and c.player.Parent ~= nil and charPos(c.player) then
			table.insert(out, c)
		end
	end
	return out
end

local function killPlayer(c: Crew, cause: string)
	c.ghost = true
	local char = c.player.Character
	local hum = char and char:FindFirstChildOfClass("Humanoid")
	if hum then hum.Health = 0 end
	Feed:FireAllClients("🩸 " .. c.player.Name .. " " .. cause)
	Toast:FireClient(c.player, "💀 The Watcher took you. You are a ghost until dawn.")
	stinger("killStinger")
end

local function monsterStep(dt: number)
	local now = os.clock()
	if now < feastUntil then return end

	-- Pick target: lured player overrides; otherwise nearest living crew outside the safe zone.
	local target: Crew? = nil
	if lureTargetUserId and now < lureUntil then
		local c = crew[lureTargetUserId :: number]
		if c and not c.ghost then target = c end
	end
	if not target then
		local best, bestDist = nil, math.huge
		local safeOn = safeZoneActive()
		for _, c in livingCrew() do
			local pos = charPos(c.player)
			if pos then
				local inSafe = (Vector3.new(pos.X, 0, pos.Z) - Vector3.zero).Magnitude < SAFE_ZONE_RADIUS
				if not (safeOn and inSafe) then
					local d = (pos - monsterPos).Magnitude
					if d < bestDist then
						best, bestDist = c, d
					end
				end
			end
		end
		target = best
	end

	local speed = MONSTER_BASE_SPEED + MONSTER_SPEED_PER_BROKEN_GEN * brokenCount()
	if brokenCount() >= GENERATOR_COUNT then
		speed *= 2 -- total blackout: enrage
	end

	local goal: Vector3
	if target then
		goal = charPos(target.player) or monsterPos
	else
		-- Everyone is huddled in the safe zone: circle the lamp menacingly.
		local angle = now * 0.5
		goal = Vector3.new(math.cos(angle), 0, math.sin(angle)) * (SAFE_ZONE_RADIUS + 6)
	end

	local delta = Vector3.new(goal.X - monsterPos.X, 0, goal.Z - monsterPos.Z)
	if delta.Magnitude > 0.1 then
		local step = delta.Unit * math.min(speed * dt, delta.Magnitude)
		monsterPos = Vector3.new(monsterPos.X + step.X, 3.5, monsterPos.Z + step.Z)
		monster:PivotTo(CFrame.lookAt(monsterPos, monsterPos + delta.Unit))
	end

	if target then
		local pos = charPos(target.player)
		if pos and (pos - monsterPos).Magnitude < MONSTER_KILL_RADIUS then
			local inSafe = (Vector3.new(pos.X, 0, pos.Z)).Magnitude < SAFE_ZONE_RADIUS
			if not (safeZoneActive() and inSafe) then
				killPlayer(target, "was taken by the Watcher…")
				feastUntil = os.clock() + MONSTER_FEAST_PAUSE
				lureTargetUserId = nil
			end
		end
	end
end

-- ===================== SYNC =====================
local function publicState()
	local genList = {}
	for _, g in generators do
		table.insert(genList, { id = g.id, health = math.floor(g.health + 0.5), broken = g.broken })
	end
	local playerList = {}
	for _, c in crew do
		table.insert(playerList, {
			userId = c.player.UserId, name = c.player.Name,
			ghost = c.ghost, exiled = c.exiled,
		})
	end
	return {
		phase = phase, night = nightNumber, totalNights = NIGHTS,
		timeLeft = math.ceil(timeLeft),
		safeZone = safeZoneActive(),
		brokenGens = brokenCount(), totalGens = GENERATOR_COUNT,
		players = playerList, generators = genList,
		monsterPos = phase == "night" and { x = monsterPos.X, y = monsterPos.Y, z = monsterPos.Z } or nil,
	}
end

local function syncAll()
	StateSync:FireAllClients(publicState())
end

local function sendPrivate(c: Crew)
	PrivateState:FireClient(c.player, {
		role = c.role,
		sabotageCharges = c.sabotageCharges,
		sabotageCooldownLeft = math.max(0, c.sabotageCooldownUntil - os.clock()),
		lureCharges = c.lureCharges,
		ghost = c.ghost,
	})
end

-- ===================== MOLE ACTIONS =====================
SabotageRequest.OnServerEvent:Connect(function(player: Player)
	local c = crew[player.UserId]
	if not c or c.role ~= "mole" or c.ghost or phase ~= "night" then return end
	if c.sabotageCharges <= 0 or os.clock() < c.sabotageCooldownUntil then return end

	-- Hit the healthiest running generator (looks like natural failure).
	local best: Generator? = nil
	for _, g in generators do
		if not g.broken and (not best or g.health > best.health) then best = g end
	end
	if not best then return end

	c.sabotageCharges -= 1
	c.sabotageCooldownUntil = os.clock() + MOLE_SABOTAGE_COOLDOWN
	best.health -= MOLE_SABOTAGE_DAMAGE
	Feed:FireAllClients("⚠ Generator G-" .. best.id .. " is failing fast!")
	if best.health <= 0 then
		markGeneratorBroken(best, "power surge")
	end
	sendPrivate(c)
end)

LureRequest.OnServerEvent:Connect(function(player: Player, targetUserId: unknown)
	local c = crew[player.UserId]
	if not c or c.role ~= "mole" or c.ghost or phase ~= "night" then return end
	if c.lureCharges <= 0 or typeof(targetUserId) ~= "number" then return end
	local victim = crew[targetUserId :: number]
	if not victim or victim.ghost or victim.player.UserId == player.UserId then return end

	c.lureCharges -= 1
	lureTargetUserId = victim.player.UserId
	lureUntil = os.clock() + MOLE_LURE_DURATION
	Toast:FireClient(c.player, "🐺 The Watcher turns toward " .. victim.player.Name .. "…")
	sendPrivate(c)
end)

VoteCast.OnServerEvent:Connect(function(player: Player, suspectUserId: unknown)
	local c = crew[player.UserId]
	if not c or c.ghost or phase ~= "vote" then return end
	if typeof(suspectUserId) ~= "number" then return end
	c.vote = suspectUserId :: number -- 0 = skip
end)

-- ===================== MATCH FLOW =====================
local function moleAlive(): (Crew?, boolean)
	for _, c in crew do
		if c.role == "mole" then
			return c, not c.ghost
		end
	end
	return nil, false
end

local function endMatch(crewWin: boolean, reason: string)
	matchActive = false
	phase = "reveal"
	local mole = moleAlive()
	local survivors = {}
	for _, c in crew do
		if not c.ghost then table.insert(survivors, c.player.Name) end
	end
	Reveal:FireAllClients({
		crewWin = crewWin,
		reason = reason,
		moleName = mole and mole.player.Name or "?",
		survivors = survivors,
	})
	syncAll()
	monster:PivotTo(monsterHome)
	monsterGrowlSound:Stop()
	setDay()
	task.wait(REVEAL_SECONDS)

	for userId, c in crew do
		if c.player.Parent == nil then crew[userId] = nil end
	end
	crew = {}
	phase = "lobby"
	nightNumber = 0
end

local function runVote(): boolean -- returns true if match ended
	phase = "vote"
	timeLeft = VOTE_SECONDS
	for _, c in crew do
		c.vote = nil
	end
	Feed:FireAllClients("🗳 DAWN VOTE — who is the mole? (or skip)")
	while timeLeft > 0 do
		task.wait(0.5)
		timeLeft -= 0.5
		syncAll()
	end

	local tally: { [number]: number } = {}
	local votesCast = 0
	for _, c in crew do
		if not c.ghost and c.vote and c.vote ~= 0 then
			tally[c.vote] = (tally[c.vote] or 0) + 1
			votesCast += 1
		end
	end
	local topId, topVotes, tie = nil, 0, false
	for userId, n in tally do
		if n > topVotes then
			topId, topVotes, tie = userId, n, false
		elseif n == topVotes then
			tie = true
		end
	end

	local living = #livingCrew()
	if topId and not tie and topVotes > living / 2 then
		local exiledC = crew[topId :: number]
		if exiledC then
			exiledC.ghost = true
			exiledC.exiled = true
			local char = exiledC.player.Character
			local hum = char and char:FindFirstChildOfClass("Humanoid")
			if hum then hum.Health = 0 end
			if exiledC.role == "mole" then
				Feed:FireAllClients("🚨 " .. exiledC.player.Name .. " was exiled — THEY WERE THE MOLE!")
				endMatch(true, "The crew found the mole.")
				return true
			else
				Feed:FireAllClients("💔 " .. exiledC.player.Name .. " was exiled… they were innocent.")
			end
		end
	else
		Feed:FireAllClients("🗳 No one was exiled.")
	end
	return false
end

local function runMatch()
	matchActive = true
	nightNumber = 0

	-- Enroll players & assign the mole.
	crew = {}
	local roster = {}
	for _, player in Players:GetPlayers() do
		local c: Crew = {
			player = player, role = "crew", ghost = false, exiled = false,
			sabotageCharges = 0, sabotageCooldownUntil = 0, lureCharges = 0, vote = nil,
		}
		crew[player.UserId] = c
		table.insert(roster, c)
	end
	roster[math.random(#roster)].role = "mole"

	for _, g in generators do
		g.health = 100
		g.broken = false
		updateGeneratorVisual(g)
	end

	-- Fresh haunted maze every match.
	generateHauntedMap()

	for _, c in roster do
		c.player:LoadCharacter()
		sendPrivate(c)
		if c.role == "mole" then
			Toast:FireClient(c.player, "🔪 You are THE MOLE. The crew must not survive 3 nights. Don't get caught.")
		else
			Toast:FireClient(c.player, "🔦 You are CREW. Keep the generators running. Survive 3 nights. Trust no one.")
		end
	end
	task.wait(1)
	for _, c in roster do
		giveFlashlight(c.player)
	end

	for night = 1, NIGHTS do
		nightNumber = night

		-- ===== DAY =====
		phase = "day"
		setDay()
		monster:PivotTo(monsterHome)
		timeLeft = DAY_SECONDS
		Feed:FireAllClients("☀ Day " .. night .. ". Repair everything. Night is coming.")

		-- Revive ghosts (not exiled) each dawn after night 1+.
		for _, c in crew do
			if c.ghost and not c.exiled and c.player.Parent ~= nil then
				c.ghost = false
				c.player:LoadCharacter()
				task.delay(1, function()
					giveFlashlight(c.player)
				end)
			end
			-- Reset mole charges for the coming night.
			if c.role == "mole" then
				c.sabotageCharges = MOLE_SABOTAGE_PER_NIGHT
				c.lureCharges = MOLE_LURE_PER_NIGHT
				c.sabotageCooldownUntil = 0
			end
			sendPrivate(c)
		end

		while timeLeft > 0 do
			task.wait(0.5)
			timeLeft -= 0.5
			for _, g in generators do
				updateGeneratorVisual(g)
			end
			syncAll()
		end

		-- ===== NIGHT =====
		phase = "night"
		setNight()
		local spawnAngle = math.random() * math.pi * 2
		monsterPos = Vector3.new(math.cos(spawnAngle), 0, math.sin(spawnAngle)) * (ARENA_SIZE / 2 - 8)
		monsterPos = Vector3.new(monsterPos.X, 3.5, monsterPos.Z)
		timeLeft = NIGHT_SECONDS
		Feed:FireAllClients("🌑 NIGHT " .. night .. ". It is here. Stay in the light.")
		if not monsterGrowlSound.IsPlaying then monsterGrowlSound:Play() end

		local TICK = 0.1
		local sinceSync = 0
		while timeLeft > 0 do
			task.wait(TICK)
			timeLeft -= TICK
			sinceSync += TICK

			for _, g in generators do
				if not g.broken then
					g.health -= GEN_DECAY_PER_SEC * TICK
					if g.health <= 0 then
						markGeneratorBroken(g, "wore down")
					end
				end
				updateGeneratorVisual(g)
			end

			monsterStep(TICK)

			if #livingCrew() == 0 or (#livingCrew() == 1 and select(2, moleAlive()) and livingCrew()[1].role == "mole") then
				endMatch(false, "The Watcher took everyone.")
				return
			end

			if sinceSync >= 0.5 then
				sinceSync = 0
				syncAll()
			end
		end

		Feed:FireAllClients("🌅 You survived night " .. night .. ".")
		monster:PivotTo(monsterHome)
		monsterGrowlSound:Stop()
		setDay()
		stinger("dawnChime")

		-- ===== DAWN VOTE (after every night except the last) =====
		if night < NIGHTS then
			stinger("voteBell")
			if runVote() then return end
		end
	end

	-- Survived all nights.
	local survivors = 0
	for _, c in crew do
		if not c.ghost and c.role == "crew" then survivors += 1 end
	end
	local _, moleIsAlive = moleAlive()
	if survivors > 0 then
		endMatch(true, moleIsAlive and "The crew survived 3 nights — but the mole walked free." or "The crew survived 3 nights.")
	else
		endMatch(false, "No crew left standing.")
	end
end

-- ===================== PLAYER LIFECYCLE =====================
Players.PlayerAdded:Connect(function(player)
	player:LoadCharacter()
	if matchActive then
		Toast:FireClient(player, "A match is in progress — you'll join the next one.")
	end
end)

Players.PlayerRemoving:Connect(function(player)
	local c = crew[player.UserId]
	if not c or not matchActive then return end
	c.ghost = true
	Feed:FireAllClients(player.Name .. " vanished into the dark…")
	if c.role == "mole" then
		endMatch(true, "The mole fled the facility.")
	end
end)

-- ===================== MAIN LOOP =====================
task.spawn(function()
	while true do
		if phase == "lobby" then
			local count = #Players:GetPlayers()
			syncAll()
			if count >= MIN_PLAYERS then
				for i = LOBBY_COUNTDOWN, 1, -1 do
					Feed:FireAllClients("Night shift starts in " .. i .. "…")
					task.wait(1)
				end
				runMatch()
			else
				task.wait(1)
			end
		else
			task.wait(1)
		end
	end
end)
