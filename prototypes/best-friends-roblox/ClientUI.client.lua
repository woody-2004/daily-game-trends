--!strict
-- BEST FRIENDS — client UI
-- Place this LocalScript in StarterPlayer > StarterPlayerScripts.
-- Builds all UI at runtime: nothing to design manually.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")

local remotes = ReplicatedStorage:WaitForChild("BestFriendsRemotes")
local StateSync = remotes:WaitForChild("StateSync") :: RemoteEvent
local PrivateState = remotes:WaitForChild("PrivateState") :: RemoteEvent
local Feed = remotes:WaitForChild("Feed") :: RemoteEvent
local Toast = remotes:WaitForChild("Toast") :: RemoteEvent
local Reveal = remotes:WaitForChild("Reveal") :: RemoteEvent
local SabotageRequest = remotes:WaitForChild("SabotageRequest") :: RemoteEvent
local AccuseRequest = remotes:WaitForChild("AccuseRequest") :: RemoteEvent

-- ===================== GUI SCAFFOLD =====================
local gui = Instance.new("ScreenGui")
gui.Name = "BestFriendsUI"
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
	f.BackgroundColor3 = Color3.fromRGB(20, 20, 28)
	f.BackgroundTransparency = 0.25
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

-- Top bar: timer + machine status
local topBar = panel(gui, { Size = UDim2.new(0, 340, 0, 46), Position = UDim2.new(0.5, -170, 0, 8) })
local timerLabel = label(topBar, { Size = UDim2.new(0.5, 0, 1, 0), Text = "—" })
local breaksLabel = label(topBar, {
	Size = UDim2.new(0.5, 0, 1, 0), Position = UDim2.new(0.5, 0, 0, 0),
	Text = "", TextColor3 = Color3.fromRGB(255, 195, 74),
})

-- Secret target panel
local targetPanel = panel(gui, { Size = UDim2.new(0, 250, 0, 62), Position = UDim2.new(0, 10, 0, 8) })
label(targetPanel, {
	Size = UDim2.new(1, -16, 0.42, 0), Position = UDim2.new(0, 8, 0, 2),
	Text = "🤫 SECRET TARGET", TextColor3 = Color3.fromRGB(255, 89, 89), TextXAlignment = Enum.TextXAlignment.Left,
})
local targetName = label(targetPanel, {
	Size = UDim2.new(1, -16, 0.5, 0), Position = UDim2.new(0, 8, 0.44, 0),
	Text = "waiting…", TextXAlignment = Enum.TextXAlignment.Left,
})

-- Feed (bottom left)
local feedPanel = panel(gui, { Size = UDim2.new(0, 330, 0, 150), Position = UDim2.new(0, 10, 1, -160), BackgroundTransparency = 0.45 })
local feedLayout = Instance.new("UIListLayout")
feedLayout.VerticalAlignment = Enum.VerticalAlignment.Bottom
feedLayout.Padding = UDim.new(0, 2)
feedLayout.Parent = feedPanel
local MAX_FEED = 6

-- Sabotage button (bottom right)
local sabotageBtn = Instance.new("TextButton")
sabotageBtn.Size = UDim2.new(0, 190, 0, 62)
sabotageBtn.Position = UDim2.new(1, -200, 1, -150)
sabotageBtn.BackgroundColor3 = Color3.fromRGB(140, 30, 30)
sabotageBtn.TextColor3 = Color3.new(1, 1, 1)
sabotageBtn.Font = Enum.Font.GothamBold
sabotageBtn.TextScaled = true
sabotageBtn.Text = "⚡ SABOTAGE"
sabotageBtn.Parent = gui
local sabCorner = Instance.new("UICorner")
sabCorner.CornerRadius = UDim.new(0, 10)
sabCorner.Parent = sabotageBtn

-- Accuse button + picker
local accuseBtn = Instance.new("TextButton")
accuseBtn.Size = UDim2.new(0, 190, 0, 50)
accuseBtn.Position = UDim2.new(1, -200, 1, -80)
accuseBtn.BackgroundColor3 = Color3.fromRGB(40, 70, 140)
accuseBtn.TextColor3 = Color3.new(1, 1, 1)
accuseBtn.Font = Enum.Font.GothamBold
accuseBtn.TextScaled = true
accuseBtn.Text = "🚨 ACCUSE (1)"
accuseBtn.Parent = gui
local accCorner = Instance.new("UICorner")
accCorner.CornerRadius = UDim.new(0, 10)
accCorner.Parent = accuseBtn

local accusePicker = panel(gui, {
	Size = UDim2.new(0, 220, 0, 240), Position = UDim2.new(1, -230, 0.5, -120),
	Visible = false, BackgroundTransparency = 0.1,
})
label(accusePicker, {
	Size = UDim2.new(1, 0, 0, 32), Text = "Who is targeting YOU?",
	TextColor3 = Color3.fromRGB(255, 195, 74),
})
local pickerList = Instance.new("ScrollingFrame")
pickerList.Size = UDim2.new(1, -12, 1, -40)
pickerList.Position = UDim2.new(0, 6, 0, 36)
pickerList.BackgroundTransparency = 1
pickerList.ScrollBarThickness = 4
pickerList.Parent = accusePicker
local pickerLayout = Instance.new("UIListLayout")
pickerLayout.Padding = UDim.new(0, 4)
pickerLayout.Parent = pickerList

-- Toast
local toastLabel = label(gui, {
	Size = UDim2.new(0, 460, 0, 40), Position = UDim2.new(0.5, -230, 0, 62),
	Text = "", TextColor3 = Color3.fromRGB(255, 230, 120), Visible = false,
})

-- Reveal overlay
local revealOverlay = panel(gui, {
	Size = UDim2.new(0, 480, 0, 360), Position = UDim2.new(0.5, -240, 0.5, -180),
	Visible = false, BackgroundTransparency = 0.05,
})
local revealTitle = label(revealOverlay, { Size = UDim2.new(1, 0, 0, 52), Text = "" })
local revealList = Instance.new("ScrollingFrame")
revealList.Size = UDim2.new(1, -20, 1, -70)
revealList.Position = UDim2.new(0, 10, 0, 60)
revealList.BackgroundTransparency = 1
revealList.ScrollBarThickness = 4
revealList.Parent = revealOverlay
local revealLayout = Instance.new("UIListLayout")
revealLayout.Padding = UDim.new(0, 4)
revealLayout.Parent = revealList

-- ===================== STATE =====================
local myCharges = 0
local myCooldownEndsAt = 0
local myAccusationUsed = false
local myExposed = false
local currentPlayers: { { userId: number, name: string } } = {}
local phase = "lobby"

local function refreshSabotageBtn()
	local cd = math.max(0, myCooldownEndsAt - os.clock())
	if phase ~= "playing" or myExposed or myCharges <= 0 then
		sabotageBtn.BackgroundColor3 = Color3.fromRGB(60, 60, 60)
		sabotageBtn.Text = myExposed and "🚨 EXPOSED" or "⚡ SABOTAGE (0)"
	elseif cd > 0 then
		sabotageBtn.BackgroundColor3 = Color3.fromRGB(90, 60, 30)
		sabotageBtn.Text = ("⚡ … %ds"):format(math.ceil(cd))
	else
		sabotageBtn.BackgroundColor3 = Color3.fromRGB(140, 30, 30)
		sabotageBtn.Text = ("⚡ SABOTAGE (%d)"):format(myCharges)
	end
end

task.spawn(function()
	while true do
		task.wait(0.25)
		refreshSabotageBtn()
	end
end)

sabotageBtn.Activated:Connect(function()
	SabotageRequest:FireServer()
end)

accuseBtn.Activated:Connect(function()
	if phase ~= "playing" or myAccusationUsed then return end
	accusePicker.Visible = not accusePicker.Visible
	if not accusePicker.Visible then return end
	for _, child in pickerList:GetChildren() do
		if child:IsA("TextButton") then child:Destroy() end
	end
	for _, p in currentPlayers do
		if p.userId ~= player.UserId then
			local btn = Instance.new("TextButton")
			btn.Size = UDim2.new(1, -8, 0, 36)
			btn.BackgroundColor3 = Color3.fromRGB(50, 50, 65)
			btn.TextColor3 = Color3.new(1, 1, 1)
			btn.Font = Enum.Font.Gotham
			btn.TextScaled = true
			btn.Text = p.name
			btn.Parent = pickerList
			local c = Instance.new("UICorner")
			c.CornerRadius = UDim.new(0, 6)
			c.Parent = btn
			btn.Activated:Connect(function()
				accusePicker.Visible = false
				AccuseRequest:FireServer(p.userId)
			end)
		end
	end
end)

-- ===================== REMOTE HANDLERS =====================
StateSync.OnClientEvent:Connect(function(state)
	phase = state.phase
	currentPlayers = {}
	for _, p in state.players do
		table.insert(currentPlayers, { userId = p.userId, name = p.name })
	end
	if state.phase == "playing" then
		timerLabel.Text = ("⏱ %ds"):format(state.timeLeft)
		breaksLabel.Text = ("💥 %d/%d"):format(state.totalBreaks, state.maxBreaks)
		revealOverlay.Visible = false
	elseif state.phase == "lobby" then
		timerLabel.Text = "LOBBY"
		breaksLabel.Text = ("%d joined"):format(#state.players)
		targetName.Text = "waiting…"
	end
end)

PrivateState.OnClientEvent:Connect(function(priv)
	targetName.Text = priv.targetName and ("➡ " .. priv.targetName) or "waiting…"
	myCharges = priv.charges
	myCooldownEndsAt = os.clock() + (priv.cooldownLeft or 0)
	myAccusationUsed = priv.accusationUsed
	myExposed = priv.exposed
	accuseBtn.Text = myAccusationUsed and "🚨 ACCUSED" or "🚨 ACCUSE (1)"
	accuseBtn.BackgroundColor3 = myAccusationUsed and Color3.fromRGB(60, 60, 60) or Color3.fromRGB(40, 70, 140)
	refreshSabotageBtn()
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
	task.delay(4, function()
		if toastLabel.Text == text then toastLabel.Visible = false end
	end)
end)

Reveal.OnClientEvent:Connect(function(data)
	revealTitle.Text = data.groupWin
		and ("🏆 MACHINE SURVIVED — %d/%d breaks"):format(data.totalBreaks, data.maxBreaks)
		or ("💀 MACHINE FAILED — %d breaks (max %d)"):format(data.totalBreaks, data.maxBreaks)
	revealTitle.TextColor3 = data.groupWin and Color3.fromRGB(97, 214, 116) or Color3.fromRGB(255, 89, 89)

	for _, child in revealList:GetChildren() do
		if child:IsA("TextLabel") then child:Destroy() end
	end
	for _, edge in data.edges do
		local status = edge.exposed and "🚨 exposed!" or edge.succeeded and "✅ succeeded" or "❌ failed"
		label(revealList, {
			Size = UDim2.new(1, -8, 0, 30),
			Text = ("%s was secretly targeting %s — %s"):format(edge.from, edge.to, status),
			Font = Enum.Font.Gotham, TextXAlignment = Enum.TextXAlignment.Left,
			TextScaled = false, TextSize = 17,
		})
	end
	revealOverlay.Visible = true
end)
