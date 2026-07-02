--!strict
-- NIGHT SHIFT — client UI
-- Place this LocalScript in StarterPlayer > StarterPlayerScripts.
-- Builds all UI at runtime: nothing to design manually.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local SoundService = game:GetService("SoundService")

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")

local remotes = ReplicatedStorage:WaitForChild("NightShiftRemotes")
local StateSync = remotes:WaitForChild("StateSync") :: RemoteEvent
local PrivateState = remotes:WaitForChild("PrivateState") :: RemoteEvent
local Feed = remotes:WaitForChild("Feed") :: RemoteEvent
local Toast = remotes:WaitForChild("Toast") :: RemoteEvent
local Reveal = remotes:WaitForChild("Reveal") :: RemoteEvent
local PlayStinger = remotes:WaitForChild("PlayStinger") :: RemoteEvent
local SabotageRequest = remotes:WaitForChild("SabotageRequest") :: RemoteEvent
local LureRequest = remotes:WaitForChild("LureRequest") :: RemoteEvent
local VoteCast = remotes:WaitForChild("VoteCast") :: RemoteEvent
local PurchasePass = remotes:WaitForChild("PurchasePass") :: RemoteEvent

-- PLACEHOLDERS — same caveat as the server: swap via Studio Toolbox (Audio
-- search terms in the comment), then these one-shot stingers play for real.
local STINGER_IDS = {
	killStinger = "rbxassetid://0", -- "horror jumpscare stinger"
	dawnChime = "rbxassetid://0", -- "morning bell" / "success chime"
	voteBell = "rbxassetid://0", -- "dramatic bell" / "tension sting"
}
local heartbeatSound = Instance.new("Sound")
heartbeatSound.SoundId = "rbxassetid://0" -- search: "heartbeat loop"
heartbeatSound.Looped = true
heartbeatSound.Volume = 0
heartbeatSound.Parent = SoundService

PlayStinger.OnClientEvent:Connect(function(key: string)
	local id = STINGER_IDS[key]
	if not id then return end
	local s = Instance.new("Sound")
	s.SoundId = id
	s.Volume = 0.8
	s.Parent = SoundService
	s.Ended:Connect(function() s:Destroy() end)
	s:Play()
	task.delay(6, function()
		if s.Parent then s:Destroy() end
	end)
end)

-- ===================== GUI HELPERS =====================
local gui = Instance.new("ScreenGui")
gui.Name = "NightShiftUI"
gui.ResetOnSpawn = false
gui.Parent = playerGui

local function label(parent: Instance, props: { [string]: any }): TextLabel
	local l = Instance.new("TextLabel")
	l.BackgroundTransparency = 1
	l.TextColor3 = Color3.new(1, 1, 1)
	l.Font = Enum.Font.GothamBold
	l.TextScaled = true
	for k, v in props do
		(l :: any)[k] = v
	end
	l.Parent = parent
	return l
end

local function panel(parent: Instance, props: { [string]: any }): Frame
	local f = Instance.new("Frame")
	f.BackgroundColor3 = Color3.fromRGB(12, 12, 18)
	f.BackgroundTransparency = 0.2
	f.BorderSizePixel = 0
	for k, v in props do
		(f :: any)[k] = v
	end
	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, 10)
	corner.Parent = f
	f.Parent = parent
	return f
end

local function button(parent: Instance, props: { [string]: any }): TextButton
	local b = Instance.new("TextButton")
	b.TextColor3 = Color3.new(1, 1, 1)
	b.Font = Enum.Font.GothamBold
	b.TextScaled = true
	for k, v in props do
		(b :: any)[k] = v
	end
	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, 8)
	corner.Parent = b
	b.Parent = parent
	return b
end

-- ===================== HUD =====================
local topBar = panel(gui, { Size = UDim2.new(0, 430, 0, 46), Position = UDim2.new(0.5, -215, 0, 8) })
local phaseLabel = label(topBar, { Size = UDim2.new(0.42, 0, 1, 0), Text = "—" })
local timerLabel = label(topBar, { Size = UDim2.new(0.24, 0, 1, 0), Position = UDim2.new(0.42, 0, 0, 0), Text = "" })
local genLabel = label(topBar, {
	Size = UDim2.new(0.34, 0, 1, 0), Position = UDim2.new(0.66, 0, 0, 0),
	Text = "", TextColor3 = Color3.fromRGB(140, 230, 140),
})

-- Role panel
local rolePanel = panel(gui, { Size = UDim2.new(0, 250, 0, 62), Position = UDim2.new(0, 10, 0, 8) })
local roleTitle = label(rolePanel, {
	Size = UDim2.new(1, -16, 0.42, 0), Position = UDim2.new(0, 8, 0, 2),
	Text = "ROLE", TextColor3 = Color3.fromRGB(160, 160, 180), TextXAlignment = Enum.TextXAlignment.Left,
})
local roleText = label(rolePanel, {
	Size = UDim2.new(1, -16, 0.5, 0), Position = UDim2.new(0, 8, 0.44, 0),
	Text = "waiting…", TextXAlignment = Enum.TextXAlignment.Left,
})

-- Feed
local feedPanel = panel(gui, { Size = UDim2.new(0, 340, 0, 150), Position = UDim2.new(0, 10, 1, -160), BackgroundTransparency = 0.45 })
local feedLayout = Instance.new("UIListLayout")
feedLayout.VerticalAlignment = Enum.VerticalAlignment.Bottom
feedLayout.Padding = UDim.new(0, 2)
feedLayout.Parent = feedPanel
local MAX_FEED = 6

-- Mole ability buttons (hidden unless you're the mole)
local sabotageBtn = button(gui, {
	Size = UDim2.new(0, 200, 0, 56), Position = UDim2.new(1, -210, 1, -140),
	BackgroundColor3 = Color3.fromRGB(140, 30, 30), Text = "⚡ SABOTAGE", Visible = false,
})
local lureBtn = button(gui, {
	Size = UDim2.new(0, 200, 0, 56), Position = UDim2.new(1, -210, 1, -76),
	BackgroundColor3 = Color3.fromRGB(90, 40, 130), Text = "🐺 LURE", Visible = false,
})

local lurePicker = panel(gui, {
	Size = UDim2.new(0, 220, 0, 240), Position = UDim2.new(1, -230, 0.5, -120),
	Visible = false, BackgroundTransparency = 0.1,
})
label(lurePicker, {
	Size = UDim2.new(1, 0, 0, 32), Text = "Send the Watcher after…",
	TextColor3 = Color3.fromRGB(220, 150, 255),
})
local lureList = Instance.new("ScrollingFrame")
lureList.Size = UDim2.new(1, -12, 1, -40)
lureList.Position = UDim2.new(0, 6, 0, 36)
lureList.BackgroundTransparency = 1
lureList.ScrollBarThickness = 4
lureList.Parent = lurePicker
local lureLayout = Instance.new("UIListLayout")
lureLayout.Padding = UDim.new(0, 4)
lureLayout.Parent = lureList

-- Flashlight skins shop (cosmetic Game Passes)
local skinsBtn = button(gui, {
	Size = UDim2.new(0, 110, 0, 36), Position = UDim2.new(0, 10, 0, 78),
	BackgroundColor3 = Color3.fromRGB(50, 45, 80), Text = "🎨 SKINS",
})
local skinsPanel = panel(gui, {
	Size = UDim2.new(0, 240, 0, 190), Position = UDim2.new(0, 10, 0, 120),
	Visible = false, BackgroundTransparency = 0.1,
})
label(skinsPanel, {
	Size = UDim2.new(1, 0, 0, 30), Text = "Flashlight Skins",
	TextColor3 = Color3.fromRGB(200, 180, 255),
})
local SKIN_NAMES = { "Ember Beam 🔥", "Spectral Beam 👻", "Bloodhunter Beam 🩸" }
for i, skinName in SKIN_NAMES do
	local btn = button(skinsPanel, {
		Size = UDim2.new(1, -16, 0, 40), Position = UDim2.new(0, 8, 0, 30 + (i - 1) * 48),
		BackgroundColor3 = Color3.fromRGB(60, 55, 90), Text = skinName, Font = Enum.Font.Gotham,
	})
	btn.Activated:Connect(function()
		PurchasePass:FireServer(i)
	end)
end
skinsBtn.Activated:Connect(function()
	skinsPanel.Visible = not skinsPanel.Visible
end)

-- Vote overlay
local voteOverlay = panel(gui, {
	Size = UDim2.new(0, 340, 0, 320), Position = UDim2.new(0.5, -170, 0.5, -160),
	Visible = false, BackgroundTransparency = 0.05,
})
label(voteOverlay, {
	Size = UDim2.new(1, 0, 0, 40), Text = "🗳 WHO IS THE MOLE?",
	TextColor3 = Color3.fromRGB(255, 195, 74),
})
local voteList = Instance.new("ScrollingFrame")
voteList.Size = UDim2.new(1, -16, 1, -96)
voteList.Position = UDim2.new(0, 8, 0, 44)
voteList.BackgroundTransparency = 1
voteList.ScrollBarThickness = 4
voteList.Parent = voteOverlay
local voteLayout = Instance.new("UIListLayout")
voteLayout.Padding = UDim.new(0, 4)
voteLayout.Parent = voteList
local skipBtn = button(voteOverlay, {
	Size = UDim2.new(1, -16, 0, 40), Position = UDim2.new(0, 8, 1, -48),
	BackgroundColor3 = Color3.fromRGB(60, 60, 70), Text = "Skip vote",
})

-- Toast
local toastLabel = label(gui, {
	Size = UDim2.new(0, 520, 0, 42), Position = UDim2.new(0.5, -260, 0, 62),
	Text = "", TextColor3 = Color3.fromRGB(255, 230, 120), Visible = false,
})

-- Reveal overlay
local revealOverlay = panel(gui, {
	Size = UDim2.new(0, 460, 0, 300), Position = UDim2.new(0.5, -230, 0.5, -150),
	Visible = false, BackgroundTransparency = 0.05,
})
local revealTitle = label(revealOverlay, { Size = UDim2.new(1, -20, 0, 56), Position = UDim2.new(0, 10, 0, 8), Text = "" })
local revealMole = label(revealOverlay, {
	Size = UDim2.new(1, -20, 0, 40), Position = UDim2.new(0, 10, 0, 72),
	Text = "", TextColor3 = Color3.fromRGB(255, 89, 89),
})
local revealDetail = label(revealOverlay, {
	Size = UDim2.new(1, -20, 0, 150), Position = UDim2.new(0, 10, 0, 120),
	Text = "", Font = Enum.Font.Gotham, TextScaled = false, TextSize = 17, TextWrapped = true,
	TextYAlignment = Enum.TextYAlignment.Top,
})

-- ===================== STATE =====================
local myRole = "crew"
local myGhost = false
local sabotageCharges = 0
local sabotageCooldownEndsAt = 0
local lureCharges = 0
local currentPlayers: { { userId: number, name: string, ghost: boolean } } = {}
local phase = "lobby"
local votedThisDawn = false

local function refreshMoleButtons()
	local isActiveMole = myRole == "mole" and not myGhost and phase == "night"
	sabotageBtn.Visible = myRole == "mole"
	lureBtn.Visible = myRole == "mole"

	local cd = math.max(0, sabotageCooldownEndsAt - os.clock())
	if not isActiveMole or sabotageCharges <= 0 then
		sabotageBtn.BackgroundColor3 = Color3.fromRGB(60, 60, 60)
		sabotageBtn.Text = ("⚡ SABOTAGE (%d)"):format(math.max(0, sabotageCharges))
	elseif cd > 0 then
		sabotageBtn.BackgroundColor3 = Color3.fromRGB(90, 60, 30)
		sabotageBtn.Text = ("⚡ … %ds"):format(math.ceil(cd))
	else
		sabotageBtn.BackgroundColor3 = Color3.fromRGB(140, 30, 30)
		sabotageBtn.Text = ("⚡ SABOTAGE (%d)"):format(sabotageCharges)
	end

	if not isActiveMole or lureCharges <= 0 then
		lureBtn.BackgroundColor3 = Color3.fromRGB(60, 60, 60)
		lureBtn.Text = ("🐺 LURE (%d)"):format(math.max(0, lureCharges))
	else
		lureBtn.BackgroundColor3 = Color3.fromRGB(90, 40, 130)
		lureBtn.Text = ("🐺 LURE (%d)"):format(lureCharges)
	end
end

task.spawn(function()
	while true do
		task.wait(0.25)
		refreshMoleButtons()
	end
end)

sabotageBtn.Activated:Connect(function()
	SabotageRequest:FireServer()
end)

lureBtn.Activated:Connect(function()
	if myRole ~= "mole" or phase ~= "night" or lureCharges <= 0 then return end
	lurePicker.Visible = not lurePicker.Visible
	if not lurePicker.Visible then return end
	for _, child in lureList:GetChildren() do
		if child:IsA("TextButton") then child:Destroy() end
	end
	for _, p in currentPlayers do
		if p.userId ~= player.UserId and not p.ghost then
			local btn = button(lureList, {
				Size = UDim2.new(1, -8, 0, 36),
				BackgroundColor3 = Color3.fromRGB(50, 40, 65), Text = p.name, Font = Enum.Font.Gotham,
			})
			btn.Activated:Connect(function()
				lurePicker.Visible = false
				LureRequest:FireServer(p.userId)
			end)
		end
	end
end)

local function rebuildVoteList()
	for _, child in voteList:GetChildren() do
		if child:IsA("TextButton") then child:Destroy() end
	end
	for _, p in currentPlayers do
		if p.userId ~= player.UserId and not p.ghost then
			local btn = button(voteList, {
				Size = UDim2.new(1, -8, 0, 38),
				BackgroundColor3 = Color3.fromRGB(50, 50, 65), Text = p.name, Font = Enum.Font.Gotham,
			})
			btn.Activated:Connect(function()
				votedThisDawn = true
				voteOverlay.Visible = false
				VoteCast:FireServer(p.userId)
			end)
		end
	end
end

skipBtn.Activated:Connect(function()
	votedThisDawn = true
	voteOverlay.Visible = false
	VoteCast:FireServer(0)
end)

-- ===================== REMOTE HANDLERS =====================
-- Heartbeat: volume and speed rise as the Watcher closes in (night only).
local latestMonsterPos: Vector3? = nil

RunService.Heartbeat:Connect(function()
	if phase ~= "night" or myGhost or not latestMonsterPos then
		if heartbeatSound.Volume > 0 then heartbeatSound.Volume = 0 end
		if heartbeatSound.IsPlaying then heartbeatSound:Stop() end
		return
	end
	local char = player.Character
	local hrp = char and char:FindFirstChild("HumanoidRootPart") :: Part?
	if not hrp then return end
	local dist = (hrp.Position - latestMonsterPos).Magnitude
	local HEAR_RANGE = 55
	if dist > HEAR_RANGE then
		heartbeatSound.Volume = 0
		if heartbeatSound.IsPlaying then heartbeatSound:Stop() end
		return
	end
	local closeness = 1 - (dist / HEAR_RANGE) -- 0 far … 1 on top of you
	heartbeatSound.Volume = closeness * 0.9
	heartbeatSound.PlaybackSpeed = 0.9 + closeness * 0.8 -- races as it closes in
	if not heartbeatSound.IsPlaying then heartbeatSound:Play() end
end)

StateSync.OnClientEvent:Connect(function(state)
	local prevPhase = phase
	phase = state.phase
	if state.monsterPos then
		latestMonsterPos = Vector3.new(state.monsterPos.x, state.monsterPos.y, state.monsterPos.z)
	else
		latestMonsterPos = nil
	end
	currentPlayers = {}
	for _, p in state.players do
		table.insert(currentPlayers, { userId = p.userId, name = p.name, ghost = p.ghost })
		if p.userId == player.UserId then
			myGhost = p.ghost
		end
	end

	if phase == "lobby" then
		phaseLabel.Text = "LOBBY"
		timerLabel.Text = ""
		genLabel.Text = ("%d here"):format(#state.players)
		roleText.Text = "waiting…"
		revealOverlay.Visible = false
		voteOverlay.Visible = false
	elseif phase == "day" then
		phaseLabel.Text = ("☀ DAY %d/%d"):format(state.night, state.totalNights)
		timerLabel.Text = ("%ds"):format(state.timeLeft)
		genLabel.Text = ("⚙ %d/%d up"):format(state.totalGens - state.brokenGens, state.totalGens)
		voteOverlay.Visible = false
		revealOverlay.Visible = false
	elseif phase == "night" then
		phaseLabel.Text = ("🌑 NIGHT %d/%d"):format(state.night, state.totalNights)
		timerLabel.Text = ("%ds"):format(state.timeLeft)
		local safe = state.safeZone and "🏮 lamp SAFE" or "🏮 lamp OUT"
		genLabel.Text = ("⚙ %d/%d — %s"):format(state.totalGens - state.brokenGens, state.totalGens, safe)
		genLabel.TextColor3 = state.safeZone and Color3.fromRGB(140, 230, 140) or Color3.fromRGB(255, 89, 89)
	elseif phase == "vote" then
		phaseLabel.Text = "🗳 DAWN VOTE"
		timerLabel.Text = ("%ds"):format(state.timeLeft)
		if prevPhase ~= "vote" then
			votedThisDawn = false
			rebuildVoteList()
		end
		voteOverlay.Visible = not votedThisDawn and not myGhost
	end
end)

PrivateState.OnClientEvent:Connect(function(priv)
	myRole = priv.role
	myGhost = priv.ghost
	sabotageCharges = priv.sabotageCharges
	sabotageCooldownEndsAt = os.clock() + (priv.sabotageCooldownLeft or 0)
	lureCharges = priv.lureCharges
	if myRole == "mole" then
		roleTitle.Text = "🤫 SECRET ROLE"
		roleText.Text = "🔪 THE MOLE"
		roleText.TextColor3 = Color3.fromRGB(255, 89, 89)
	else
		roleTitle.Text = "ROLE"
		roleText.Text = "🔦 CREW"
		roleText.TextColor3 = Color3.fromRGB(140, 230, 140)
	end
	refreshMoleButtons()
end)

Feed.OnClientEvent:Connect(function(text: string)
	local line = label(feedPanel, {
		Size = UDim2.new(1, -12, 0, 22), Text = text,
		Font = Enum.Font.Gotham, TextXAlignment = Enum.TextXAlignment.Left,
		TextTruncate = Enum.TextTruncate.AtEnd, TextScaled = false, TextSize = 15,
	})
	line.Position = UDim2.new(0, 6, 0, 0)
	local lines = {}
	for _, child in feedPanel:GetChildren() do
		if child:IsA("TextLabel") then table.insert(lines, child) end
	end
	if #lines > MAX_FEED then
		lines[1]:Destroy()
	end
end)

Toast.OnClientEvent:Connect(function(text: string)
	toastLabel.Text = text
	toastLabel.Visible = true
	task.delay(5, function()
		if toastLabel.Text == text then toastLabel.Visible = false end
	end)
end)

Reveal.OnClientEvent:Connect(function(data)
	revealTitle.Text = data.crewWin and "🏆 CREW WINS" or "🔪 THE MOLE WINS"
	revealTitle.TextColor3 = data.crewWin and Color3.fromRGB(97, 214, 116) or Color3.fromRGB(255, 89, 89)
	revealMole.Text = ("The mole was: %s"):format(data.moleName)
	local survivors = #data.survivors > 0 and table.concat(data.survivors, ", ") or "no one"
	revealDetail.Text = ("%s\n\nSurvivors: %s"):format(data.reason, survivors)
	voteOverlay.Visible = false
	revealOverlay.Visible = true
end)
