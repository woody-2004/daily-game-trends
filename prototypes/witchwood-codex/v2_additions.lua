
-- ===== Diagnostic: why the diverse-site placement may not have shown =====
print("[Wards] diverse sites found: "..#DIVERSE_SITES.." (need >=3 to replace the original 5 wards)")

-- ===== Fix: Witchwood expansion sitting underground/underwater =====
-- Computes how far the whole Codex_Expanded_Map_Witchwood group is off
-- the real terrain surface (via one reference part) and shifts every
-- part in the group by that same delta, so relative spacing between
-- pieces (e.g. the Witch Hut's base and roof) stays intact.
task.spawn(function()
	local witchwood = workspace:FindFirstChild("Codex_Expanded_Map_Witchwood")
	if not witchwood then
		return
	end
	local reference = witchwood:FindFirstChild("Spawn_Plaza_Base") or witchwood:FindFirstChildWhichIsA("BasePart", true)
	if not reference then
		return
	end
	local rayParams = RaycastParams.new()
	rayParams.FilterType = Enum.RaycastFilterType.Exclude
	rayParams.FilterDescendantsInstances = { witchwood }
	local origin = reference.Position + Vector3.new(0, 400, 0)
	local result = workspace:Raycast(origin, Vector3.new(0, -800, 0), rayParams)
	if not result then
		print("[Witchwood] could not raycast terrain under the reference part; leaving positions unchanged")
		return
	end
	local desiredSurfaceY = result.Position.Y
	local currentBottomY = reference.Position.Y - reference.Size.Y / 2
	local delta = desiredSurfaceY - currentBottomY
	if math.abs(delta) < 0.5 then
		print("[Witchwood] already sitting on terrain, no shift needed")
		return
	end
	for _, inst in ipairs(witchwood:GetDescendants()) do
		if inst:IsA("BasePart") then
			inst.Position = inst.Position + Vector3.new(0, delta, 0)
		end
	end
	print("[Witchwood] shifted the whole expansion by " .. tostring(delta) .. " studs to sit on terrain")
end)

-- ===== Flashlight tool (Creator Store mesh, players had none before) =====
local FLASHLIGHT_ASSET_ID = 110700594151156 -- "Flashlight Handheld Lamp Dark Tool Light"
local flashlightTemplate = nil
task.spawn(function()
	local ok, asset = pcall(function()
		return game:GetService("InsertService"):LoadAsset(FLASHLIGHT_ASSET_ID)
	end)
	if not ok or not asset then
		return
	end
	for _, d in ipairs(asset:GetDescendants()) do
		if d:IsA("LuaSourceContainer") then
			d:Destroy()
		elseif d:IsA("BasePart") then
			d.Anchored = false
		end
	end
	for _, c in ipairs(asset:GetChildren()) do
		if c:IsA("Model") or c:IsA("Tool") then
			flashlightTemplate = c
			break
		end
	end
end)

local function giveFlashlight(plr)
	local backpack = plr:FindFirstChildOfClass("Backpack")
	if not backpack then
		return
	end
	if backpack:FindFirstChild("Flashlight") or (plr.Character and plr.Character:FindFirstChild("Flashlight")) then
		return
	end
	local tool = Instance.new("Tool")
	tool.Name = "Flashlight"
	tool.RequiresHandle = true
	local handle = Instance.new("Part")
	handle.Name = "Handle"
	handle.Size = Vector3.new(0.5, 0.5, 1.6)
	handle.Color = Color3.fromRGB(40, 40, 40)
	handle.Parent = tool
	local spot = Instance.new("SpotLight")
	spot.Range = 45
	spot.Angle = 38
	spot.Brightness = 4
	spot.Face = Enum.NormalId.Front
	spot.Color = Color3.fromRGB(255, 255, 240)
	spot.Parent = handle
	if flashlightTemplate then
		pcall(function()
			local mesh = flashlightTemplate:Clone()
			local ext = mesh:GetExtentsSize()
			pcall(function()
				mesh:ScaleTo(1.8 / math.max(ext.X, ext.Y, ext.Z, 0.1))
			end)
			mesh:PivotTo(handle.CFrame)
			for _, d in ipairs(mesh:GetDescendants()) do
				if d:IsA("BasePart") then
					d.Anchored = false
					d.CanCollide = false
					d.Massless = true
					local w = Instance.new("WeldConstraint")
					w.Part0 = handle
					w.Part1 = d
					w.Parent = d
				end
			end
			handle.Transparency = 1
			mesh.Parent = tool
		end)
	end
	tool.Parent = backpack
end

for _, p in ipairs(Players:GetPlayers()) do
	if p.Character then
		giveFlashlight(p)
	end
	p.CharacterAdded:Connect(function()
		task.wait(1)
		giveFlashlight(p)
	end)
end
Players.PlayerAdded:Connect(function(p)
	p.CharacterAdded:Connect(function()
		task.wait(1)
		giveFlashlight(p)
	end)
end)

-- ===== Landmark buildings (Creator Store): Camp House / Farm House / Warehouse / Factory =====
task.spawn(function()
	local InsertService = game:GetService("InsertService")
	local terrainInst = workspace:FindFirstChildOfClass("Terrain")

	local function loadModel(assetId)
		local model = nil
		pcall(function()
			local asset = InsertService:LoadAsset(assetId)
			for _, d in ipairs(asset:GetDescendants()) do
				if d:IsA("LuaSourceContainer") then
					d:Destroy()
				elseif d:IsA("BasePart") then
					d.Anchored = true
				end
			end
			local best, bestVol = nil, 0
			for _, c in ipairs(asset:GetChildren()) do
				if c:IsA("Model") then
					local s = c:GetExtentsSize()
					local v = s.X * s.Y * s.Z
					if v > bestVol then
						best, bestVol = c, v
					end
				end
			end
			if not best then
				local wrap = Instance.new("Model")
				for _, c in ipairs(asset:GetChildren()) do
					if c:IsA("BasePart") then
						c.Parent = wrap
					end
				end
				if #wrap:GetChildren() > 0 then
					best = wrap
				end
			end
			model = best
		end)
		return model
	end

	local function groundSnap(pos)
		local rayParams = RaycastParams.new()
		rayParams.FilterType = Enum.RaycastFilterType.Include
		rayParams.FilterDescendantsInstances = terrainInst and { terrainInst } or {}
		local result = workspace:Raycast(pos + Vector3.new(0, 300, 0), Vector3.new(0, -600, 0), rayParams)
		return result and result.Position or pos
	end

	local function place(model, pos, footprint, yawDeg)
		local ext = model:GetExtentsSize()
		local widest = math.max(ext.X, ext.Z, 0.1)
		pcall(function()
			model:ScaleTo(footprint / widest)
		end)
		model:PivotTo(CFrame.new(pos) * CFrame.Angles(0, math.rad(yawDeg), 0))
		local bbCF, bbSize = model:GetBoundingBox()
		local floorY = groundSnap(pos).Y
		model:PivotTo(model:GetPivot() + Vector3.new(0, floorY - (bbCF.Position.Y - bbSize.Y / 2) - 0.4, 0))
	end

	local center = Safe.Position
	local buildingsFolder = Instance.new("Folder")
	buildingsFolder.Name = "LandmarkBuildings"
	buildingsFolder.Parent = workspace

	local BUILDINGS = {
		{ id = 109175553546833, name = "CampHouse", pos = center, footprint = 52, yaw = 180 }, -- "Big Log Cabin (UNFURNISHED)" -- Discussion Hall, spans the ward cluster
		{ id = 12129034740, name = "FarmHouseAndLake", pos = center + Vector3.new(85, 0, -85), footprint = 58, yaw = 20 }, -- "abandoned barn" -- SE, riverbank
		{ id = 128655727108731, name = "Warehouse", pos = center + Vector3.new(-85, 0, -85), footprint = 54, yaw = 200 }, -- "Abandoned building" -- SW, roofed ruins
		{ id = 112448492652447, name = "Factory", pos = center + Vector3.new(85, 0, 85), footprint = 62, yaw = 300 }, -- "Industrial Factory Building" -- NE, elevated clearing
	}
	for _, b in ipairs(BUILDINGS) do
		local model = loadModel(b.id)
		if model then
			model.Name = b.name
			place(model, b.pos, b.footprint, b.yaw)
			model.Parent = buildingsFolder
			print("[Landmarks] placed " .. b.name)
		else
			print("[Landmarks] failed to load " .. b.name .. " (asset " .. b.id .. ")")
		end
	end
end)

-- The Camp House brief calls for "a high-intensity, flickering
-- industrial Safe-Zone Lamp" -- the existing SafeLight gets that now.
task.spawn(function()
	local safeLight = Safe:FindFirstChild("SafeLight")
	if not safeLight then
		return
	end
	local rng = Random.new()
	while true do
		task.wait(rng:NextNumber(0.06, 0.2))
		safeLight.Brightness = rng:NextNumber(1.6, 3.2)
	end
end)
