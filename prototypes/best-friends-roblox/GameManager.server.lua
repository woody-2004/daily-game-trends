--!strict
-- BEST FRIENDS — Roblox prototype
-- Everyone cooperates to keep the machine alive… but every player is
-- secretly assigned one other player to sabotage without getting caught.
--
-- Place this Script in ServerScriptService.
-- It builds the arena and all RemoteEvents at runtime — no manual setup needed.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

-- ===================== CONFIG =====================
local MIN_PLAYERS = 3
local MAX_PLAYERS = 8
local ROUND_SECONDS = 90
local LOBBY_COUNTDOWN = 10
local REVEAL_SECONDS = 18

local DECAY_PER_SEC = 6 -- station health lost per second
local REPAIR_BOOST = 8 -- health per repair prompt trigger
local SABOTAGE_DAMAGE = 35
local SABOTAGE_CHARGES = 3
local SABOTAGE_COOLDOWN = 12
local REBOOT_SECONDS = 4 -- downtime after a station breaks
local REBOOT_HEALTH = 60
local WRONG_ACCUSE_DAMAGE = 25
local GROUP_WIN_MAX_BREAKS = 3

local STATION_CIRCLE_RADIUS = 26
local ARENA_CENTER = Vector3.new(0, 0, 0)

-- ===================== REMOTES =====================
local remotes = Instance.new("Folder")
remotes.Name = "BestFriendsRemotes"
remotes.Parent = ReplicatedStorage

local function makeRemote(name: string): RemoteEvent
	local r = Instance.new("RemoteEvent")
	r.Name = name
	r.Parent = remotes
	return r
end

local StateSync = makeRemote("StateSync") -- server -> all: public game state
local PrivateState = makeRemote("PrivateState") -- server -> one player: target/charges
local Feed = makeRemote("Feed") -- server -> all: event feed line
local Toast = makeRemote("Toast") -- server -> one player: popup message
local Reveal = makeRemote("Reveal") -- server -> all: end-of-round reveal
local SabotageRequest = makeRemote("SabotageRequest") -- client -> server
local AccuseRequest = makeRemote("AccuseRequest") -- client -> server (arg: accused UserId)

-- ===================== GAME STATE =====================
type PlayerState = {
	player: Player,
	station: Model?,
	health: number,
	brokenUntil: number,
	breakCount: number,
	targetUserId: number?,
	charges: number,
	cooldownUntil: number,
	accusationUsed: boolean,
	exposed: boolean,
	personalWin: boolean,
}

local gamePhase: string = "lobby" -- lobby | playing | reveal
local timeLeft = 0
local totalBreaks = 0
local states: { [number]: PlayerState } = {} -- keyed by UserId

-- ===================== ARENA =====================
local arena = Instance.new("Folder")
arena.Name = "BestFriendsArena"
arena.Parent = Workspace

local STATION_COLORS = {
	Color3.fromRGB(255, 89, 89), Color3.fromRGB(89, 149, 255), Color3.fromRGB(97, 214, 116),
	Color3.fromRGB(255, 195, 74), Color3.fromRGB(199, 110, 255), Color3.fromRGB(84, 219, 219),
	Color3.fromRGB(255, 133, 199), Color3.fromRGB(214, 214, 96),
}

local function buildStation(ps: PlayerState, index: number, count: number)
	local angle = (index / count) * math.pi * 2
	local pos = ARENA_CENTER + Vector3.new(math.cos(angle), 0, math.sin(angle)) * STATION_CIRCLE_RADIUS

	local model = Instance.new("Model")
	model.Name = "Station_" .. ps.player.Name

	local body = Instance.new("Part")
	body.Name = "Body"
	body.Size = Vector3.new(4, 5, 4)
	body.Position = pos + Vector3.new(0, 2.5, 0)
	body.Anchored = true
	body.Color = STATION_COLORS[((index - 1) % #STATION_COLORS) + 1]
	body.Material = Enum.Material.Neon
	body.Parent = model

	local prompt = Instance.new("ProximityPrompt")
	prompt.ActionText = "Repair"
	prompt.ObjectText = ps.player.Name .. "'s station"
	prompt.HoldDuration = 0
	prompt.MaxActivationDistance = 10
	prompt.RequiresLineOfSight = false
	prompt.Parent = body

	prompt.Triggered:Connect(function(who: Player)
		-- Only the owner repairs their own station (others must watch… or sabotage).
		if gamePhase ~= "playing" then return end
		if who ~= ps.player then return end
		if os.clock() < ps.brokenUntil then return end
		ps.health = math.min(100, ps.health + REPAIR_BOOST)
	end)

	local billboard = Instance.new("BillboardGui")
	billboard.Size = UDim2.fromOffset(160, 44)
	billboard.StudsOffset = Vector3.new(0, 4.2, 0)
	billboard.AlwaysOnTop = true
	billboard.Parent = body

	local nameLabel = Instance.new("TextLabel")
	nameLabel.Name = "NameLabel"
	nameLabel.Size = UDim2.new(1, 0, 0.5, 0)
	nameLabel.BackgroundTransparency = 1
	nameLabel.TextColor3 = Color3.new(1, 1, 1)
	nameLabel.TextStrokeTransparency = 0.3
	nameLabel.TextScaled = true
	nameLabel.Font = Enum.Font.GothamBold
	nameLabel.Text = ps.player.Name
	nameLabel.Parent = billboard

	local barBack = Instance.new("Frame")
	barBack.Name = "BarBack"
	barBack.Position = UDim2.new(0, 0, 0.55, 0)
	barBack.Size = UDim2.new(1, 0, 0.35, 0)
	barBack.BackgroundColor3 = Color3.fromRGB(30, 30, 30)
	barBack.BorderSizePixel = 0
	barBack.Parent = billboard

	local barFill = Instance.new("Frame")
	barFill.Name = "BarFill"
	barFill.Size = UDim2.new(1, 0, 1, 0)
	barFill.BackgroundColor3 = Color3.fromRGB(97, 214, 116)
	barFill.BorderSizePixel = 0
	barFill.Parent = barBack

	model.Parent = arena
	ps.station = model
end

local function updateStationVisual(ps: PlayerState)
	local model = ps.station
	if not model then return end
	local body = model:FindFirstChild("Body") :: Part?
	if not body then return end
	local billboard = body:FindFirstChildOfClass("BillboardGui")
	if not billboard then return end
	local barBack = billboard:FindFirstChild("BarBack") :: Frame?
	local barFill = barBack and barBack:FindFirstChild("BarFill") :: Frame?
	if not barFill then return end

	local frac = math.clamp(ps.health / 100, 0, 1)
	barFill.Size = UDim2.new(frac, 0, 1, 0)
	if os.clock() < ps.brokenUntil then
		barFill.BackgroundColor3 = Color3.fromRGB(120, 120, 120)
		body.Material = Enum.Material.CorrodedMetal
	else
		body.Material = Enum.Material.Neon
		barFill.BackgroundColor3 = frac > 0.5 and Color3.fromRGB(97, 214, 116)
			or frac > 0.25 and Color3.fromRGB(255, 195, 74)
			or Color3.fromRGB(255, 89, 89)
	end
end

local function clearArena()
	for _, ps in states do
		if ps.station then
			ps.station:Destroy()
			ps.station = nil
		end
	end
end

-- ===================== HELPERS =====================
local function feed(text: string)
	Feed:FireAllClients(text)
end

local function publicState()
	local list = {}
	for _, ps in states do
		table.insert(list, {
			userId = ps.player.UserId,
			name = ps.player.Name,
			health = math.floor(ps.health + 0.5),
			broken = os.clock() < ps.brokenUntil,
			exposed = ps.exposed,
		})
	end
	return {
		phase = gamePhase,
		timeLeft = math.ceil(timeLeft),
		totalBreaks = totalBreaks,
		maxBreaks = GROUP_WIN_MAX_BREAKS,
		players = list,
	}
end

local function syncAll()
	StateSync:FireAllClients(publicState())
end

local function sendPrivate(ps: PlayerState)
	local targetName = nil
	if ps.targetUserId then
		local t = states[ps.targetUserId]
		targetName = t and t.player.Name or nil
	end
	PrivateState:FireClient(ps.player, {
		targetName = targetName,
		charges = ps.charges,
		cooldownLeft = math.max(0, ps.cooldownUntil - os.clock()),
		accusationUsed = ps.accusationUsed,
		exposed = ps.exposed,
		personalWin = ps.personalWin,
	})
end

local function breakStation(ps: PlayerState, cause: string)
	ps.health = 0
	ps.brokenUntil = os.clock() + REBOOT_SECONDS
	ps.breakCount += 1
	totalBreaks += 1
	feed("💥 " .. ps.player.Name .. "'s station BROKE (" .. cause .. ")!")

	for _, q in states do
		if q.targetUserId == ps.player.UserId and not q.personalWin then
			q.personalWin = true
			sendPrivate(q)
			Toast:FireClient(q.player, "🎯 Your target's station broke. Secret objective complete!")
		end
	end
end

-- ===================== SABOTAGE & ACCUSE =====================
SabotageRequest.OnServerEvent:Connect(function(player: Player)
	local ps = states[player.UserId]
	if not ps or gamePhase ~= "playing" then return end
	if ps.exposed or ps.charges <= 0 or os.clock() < ps.cooldownUntil then return end
	local target = ps.targetUserId and states[ps.targetUserId]
	if not target or os.clock() < target.brokenUntil then return end

	ps.charges -= 1
	ps.cooldownUntil = os.clock() + SABOTAGE_COOLDOWN
	target.health -= SABOTAGE_DAMAGE

	-- Disguised as a random malfunction: no attribution in the feed.
	feed("⚡ A power surge hit " .. target.player.Name .. "'s station!")
	local body = target.station and target.station:FindFirstChild("Body") :: Part?
	if body then
		local original = body.Color
		body.Color = Color3.new(1, 1, 1)
		task.delay(0.3, function()
			body.Color = original
		end)
	end

	if target.health <= 0 then
		breakStation(target, "power surge")
	end
	sendPrivate(ps)
end)

AccuseRequest.OnServerEvent:Connect(function(player: Player, accusedUserId: unknown)
	local ps = states[player.UserId]
	if not ps or gamePhase ~= "playing" or ps.accusationUsed then return end
	if typeof(accusedUserId) ~= "number" or accusedUserId == player.UserId then return end
	local accused = states[accusedUserId :: number]
	if not accused then return end

	ps.accusationUsed = true
	if accused.targetUserId == player.UserId then
		accused.exposed = true
		ps.health = 100
		feed("🚨 " .. player.Name .. " EXPOSED " .. accused.player.Name .. " as their saboteur! Sabotage disabled.")
		Toast:FireClient(accused.player, "🚨 You were exposed! No more sabotage for you.")
		sendPrivate(accused)
	else
		ps.health -= WRONG_ACCUSE_DAMAGE
		feed("🤡 " .. player.Name .. " accused " .. accused.player.Name .. "… wildly wrong. Paranoia damage!")
		if ps.health <= 0 then
			breakStation(ps, "paranoia meltdown")
		end
	end
	sendPrivate(ps)
end)

-- ===================== PLAYER LIFECYCLE =====================
Players.PlayerRemoving:Connect(function(player)
	local ps = states[player.UserId]
	if not ps then return end
	if gamePhase == "playing" then
		feed(player.Name .. " disconnected — their station is unmanned!")
		-- Leave the state in place so targets/reveal stay coherent; station just decays.
		ps.player = player -- keep reference for names in reveal
	else
		if ps.station then ps.station:Destroy() end
		states[player.UserId] = nil
	end
end)

-- ===================== ROUND FLOW =====================
local function assignTargets()
	-- Single random cycle: everyone targets someone, everyone is targeted by exactly one.
	local list = {}
	for _, ps in states do
		table.insert(list, ps)
	end
	for i = #list, 2, -1 do
		local j = math.random(i)
		list[i], list[j] = list[j], list[i]
	end
	for i, ps in list do
		ps.targetUserId = list[(i % #list) + 1].player.UserId
	end
end

local function runRound()
	gamePhase = "playing"
	timeLeft = ROUND_SECONDS
	totalBreaks = 0

	-- Reset per-player state and build stations.
	clearArena()
	local roster = {}
	for _, ps in states do
		table.insert(roster, ps)
	end
	for i, ps in roster do
		ps.health = 100
		ps.brokenUntil = 0
		ps.breakCount = 0
		ps.charges = SABOTAGE_CHARGES
		ps.cooldownUntil = 0
		ps.accusationUsed = false
		ps.exposed = false
		ps.personalWin = false
		buildStation(ps, i, #roster)
	end
	assignTargets()

	feed("The machine is live. Keep your station green… and watch your friends. 👀")
	for _, ps in states do
		sendPrivate(ps)
	end

	local TICK = 0.25
	while timeLeft > 0 do
		task.wait(TICK)
		timeLeft -= TICK
		local now = os.clock()
		for _, ps in states do
			if now < ps.brokenUntil then
				-- rebooting
			else
				if ps.brokenUntil ~= 0 and ps.health <= 0 then
					ps.brokenUntil = 0
					ps.health = REBOOT_HEALTH
					feed("🔧 " .. ps.player.Name .. "'s station rebooted.")
				end
				ps.health -= DECAY_PER_SEC * TICK
				if ps.health <= 0 and ps.brokenUntil == 0 then
					breakStation(ps, "wore down")
				end
			end
			updateStationVisual(ps)
		end
		syncAll()
	end

	-- ===== Reveal =====
	gamePhase = "reveal"
	local edges = {}
	for _, ps in states do
		local target = ps.targetUserId and states[ps.targetUserId]
		if target then
			table.insert(edges, {
				from = ps.player.Name,
				to = target.player.Name,
				succeeded = ps.personalWin,
				exposed = ps.exposed,
			})
		end
	end
	Reveal:FireAllClients({
		groupWin = totalBreaks <= GROUP_WIN_MAX_BREAKS,
		totalBreaks = totalBreaks,
		maxBreaks = GROUP_WIN_MAX_BREAKS,
		edges = edges,
	})
	syncAll()
	task.wait(REVEAL_SECONDS)

	-- Drop players who left during the round.
	for userId, ps in states do
		if ps.player.Parent == nil then
			if ps.station then ps.station:Destroy() end
			states[userId] = nil
		end
	end
	clearArena()
	gamePhase = "lobby"
end

-- ===================== MAIN LOOP =====================
task.spawn(function()
	while true do
		-- Lobby: register present players, wait for quorum.
		for _, player in Players:GetPlayers() do
			if not states[player.UserId] and #Players:GetPlayers() <= MAX_PLAYERS then
				states[player.UserId] = {
					player = player, station = nil,
					health = 100, brokenUntil = 0, breakCount = 0,
					targetUserId = nil, charges = 0, cooldownUntil = 0,
					accusationUsed = false, exposed = false, personalWin = false,
				}
			end
		end

		local count = 0
		for _ in states do
			count += 1
		end

		if gamePhase == "lobby" then
			if count >= MIN_PLAYERS then
				for i = LOBBY_COUNTDOWN, 1, -1 do
					feed("Round starts in " .. i .. "…")
					task.wait(1)
				end
				runRound()
			else
				syncAll()
				task.wait(1)
			end
		else
			task.wait(1)
		end
	end
end)
