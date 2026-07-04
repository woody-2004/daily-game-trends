local Players=game:GetService("Players")
local RS=game:GetService("ReplicatedStorage")
local RunService=game:GetService("RunService")
local Lighting=game:GetService("Lighting")
local Remotes=RS:WaitForChild("CodexNightShift")
local State=Remotes:WaitForChild("State")
local Action=Remotes:WaitForChild("Action")
local Game=workspace:WaitForChild("CodexGameplay")
local WardsFolder=Game:WaitForChild("Wards")
local Safe=Game:WaitForChild("SafeZone_Lamp")
local Watcher=Game:WaitForChild("The_Watcher")

-- ===== Diverse ward placement (built on the existing village/witchwood structures) =====
-- Moves the 5 generic Ward markers onto real, distinct locations already
-- in the map (Smithy, Mill, Dock, Bridge, the Witch Hut, the Rune Tower)
-- instead of leaving them as unlabeled floating parts. Falls back to the
-- original wards untouched if fewer than 3 of these are found.
local StructuresFolder=workspace:FindFirstChild("Structures")
local WitchwoodFolder=workspace:FindFirstChild("Codex_Expanded_Map_Witchwood")

local function findByName(container,name)
 if not container then return nil end
 for _,c in ipairs(container:GetChildren()) do
  if c.Name==name then return c end
 end
 return nil
end

local function findByNameContains(container,fragment)
 if not container then return nil end
 for _,c in ipairs(container:GetChildren()) do
  if string.find(c.Name,fragment,1,true) then return c end
 end
 return nil
end

local function anchorPointOf(inst)
 if not inst then return nil end
 if inst:IsA("Model") then
  local ok,cf=pcall(function() return inst:GetPivot() end)
  if ok then return cf.Position end
  return nil
 elseif inst:IsA("BasePart") then
  return inst.Position
 end
 return nil
end

local function groundSnap(pos)
 local rayParams=RaycastParams.new()
 rayParams.FilterType=Enum.RaycastFilterType.Exclude
 rayParams.FilterDescendantsInstances={Game}
 local result=workspace:Raycast(pos+Vector3.new(0,80,0),Vector3.new(0,-200,0),rayParams)
 if result then return result.Position end
 return pos
end

local DIVERSE_SITES={}
local function addSite(name,inst,offset)
 local p=anchorPointOf(inst)
 if p then table.insert(DIVERSE_SITES,{name=name,pos=groundSnap(p+(offset or Vector3.new(10,0,10)))}) end
end

addSite("Smithy",findByName(StructuresFolder,"Smithy"),Vector3.new(9,0,6))
addSite("Mill",findByName(StructuresFolder,"Mill"),Vector3.new(8,0,-8))
addSite("Dock",findByName(StructuresFolder,"Dock"),Vector3.new(0,0,10))
addSite("Bridge",findByName(StructuresFolder,"Bridge"),Vector3.new(6,0,0))
addSite("WitchHut",findByNameContains(WitchwoodFolder,"Witch_Hut"),Vector3.new(8,0,8))
addSite("RuneTower",findByNameContains(WitchwoodFolder,"Rune_Watch_Tower"),Vector3.new(10,0,-6))
do
 local houses={}
 for _,c in ipairs(StructuresFolder and StructuresFolder:GetChildren() or {}) do
  if c.Name=="House" then table.insert(houses,c) end
 end
 if houses[1] then addSite("Homestead",houses[1],Vector3.new(9,0,7)) end
end
do
 local cottages={}
 for _,c in ipairs(StructuresFolder and StructuresFolder:GetChildren() or {}) do
  if c.Name=="Cottage" then table.insert(cottages,c) end
 end
 if cottages[1] then addSite("Cottage",cottages[1],Vector3.new(-9,0,7)) end
end

if #DIVERSE_SITES>=3 then
 for _,w in ipairs(WardsFolder:GetChildren()) do w:Destroy() end
 for _,site in ipairs(DIVERSE_SITES) do
  local ward=Instance.new("Part")
  ward.Name=site.name
  ward.Size=Vector3.new(2.4,3.6,2.4)
  ward.Anchored=true
  ward.CanCollide=true
  ward.Material=Enum.Material.Neon
  ward.Color=Color3.fromRGB(104,82,255)
  ward.Position=site.pos+Vector3.new(0,1.8,0)
  ward.Parent=WardsFolder
  ward:SetAttribute("Health",100)
  ward:SetAttribute("MaxHealth",100)
  local light=Instance.new("PointLight")
  light.Color=Color3.fromRGB(140,120,255)
  light.Range=22
  light.Brightness=1.6
  light.Parent=ward
  local prompt=Instance.new("ProximityPrompt")
  prompt.Name="RepairPrompt"
  prompt.ActionText="Repair"
  prompt.ObjectText=site.name.." Ward"
  prompt.HoldDuration=0.6
  prompt.MaxActivationDistance=10
  prompt.Parent=ward
  local billboard=Instance.new("BillboardGui")
  billboard.Name="WardLabel"
  billboard.Size=UDim2.fromOffset(140,26)
  billboard.StudsOffset=Vector3.new(0,3,0)
  billboard.AlwaysOnTop=true
  billboard.MaxDistance=70
  billboard.Parent=ward
  local label=Instance.new("TextLabel")
  label.Size=UDim2.fromScale(1,1)
  label.BackgroundTransparency=1
  label.Font=Enum.Font.GothamBold
  label.TextSize=15
  label.TextColor3=Color3.fromRGB(230,230,255)
  label.Text=site.name
  label.Parent=billboard
 end
end

local cfg={intermission=10,day=35,night=70,vote=20,nights=3,decay=2.4,repair=18,sabotage=45,safeRadius=42,watcherSpeed=18,catchDistance=7}
local phase="Waiting"; local timeLeft=0; local night=0; local roles={}; local alive={}; local ghosts={}; local sabotages={}; local votes={}; local feed={"Night Shift: Witchwood loaded."}; local running=false
local function addFeed(msg)table.insert(feed,1,msg) while #feed>6 do table.remove(feed) end end
local function players()return Players:GetPlayers() end
local function send(plr)
 local wardData={}; for _,w in ipairs(WardsFolder:GetChildren()) do table.insert(wardData,{name=w.Name,health=math.floor(w:GetAttribute("Health") or 0),max=w:GetAttribute("MaxHealth") or 100}) end
 local role=roles[plr] or "Crew"; State:FireClient(plr,{phase=phase,time=timeLeft,night=night,role=role,alive=alive[plr]~=false,ghost=ghosts[plr]==true,sabotages=sabotages[plr] or 0,wards=wardData,feed=feed})
end
local function broadcast()for _,p in ipairs(players()) do send(p) end end
local function setLighting(isNight)
 if isNight then Lighting.ClockTime=0.15; Lighting.FogEnd=150; Lighting.Brightness=.8 else Lighting.ClockTime=17.4; Lighting.FogEnd=280; Lighting.Brightness=1.6 end
end
local function root(plr)local c=plr.Character return c and c:FindFirstChild("HumanoidRootPart") end
local function inSafe(plr)local r=root(plr) return r and (r.Position-Safe.Position).Magnitude<cfg.safeRadius end
local function resetRound()
 roles={}; alive={}; ghosts={}; sabotages={}; votes={}; night=0
 for _,p in ipairs(players()) do alive[p]=true; ghosts[p]=false; sabotages[p]=2 end
 local ps=players(); if #ps>0 then local mole=ps[math.random(1,#ps)] roles[mole]="Mole" addFeed("A mole has infiltrated the crew.") end
 for _,p in ipairs(ps) do if not roles[p] then roles[p]="Crew" end end
 for _,w in ipairs(WardsFolder:GetChildren()) do w:SetAttribute("Health",100); w.Color=Color3.fromRGB(104,82,255) end
 Watcher.Position=Vector3.new(0,5,-90)
end
local function wardBrokenCount()local n=0 for _,w in ipairs(WardsFolder:GetChildren()) do if (w:GetAttribute("Health") or 0)<=0 then n+=1 end end return n end
local function allWardsAlive()for _,w in ipairs(WardsFolder:GetChildren()) do if (w:GetAttribute("Health") or 0)<=0 then return false end end return true end
local function livingCrewCount()local n=0 for _,p in ipairs(players()) do if alive[p]~=false then n+=1 end end return n end
local function repairWard(plr,ward)
 if not ward or not ward:IsDescendantOf(WardsFolder) or alive[plr]==false then return end
 local r=root(plr); if not r or (r.Position-ward.Position).Magnitude>18 then return end
 local h=math.clamp((ward:GetAttribute("Health") or 0)+cfg.repair,0,100); ward:SetAttribute("Health",h); ward.Color=h<=0 and Color3.fromRGB(38,35,45) or Color3.fromRGB(104,82,255); addFeed(plr.Name.." repaired "..ward.Name.."."); broadcast()
end
for _,w in ipairs(WardsFolder:GetChildren()) do local pr=w:FindFirstChild("RepairPrompt") if pr then pr.Triggered:Connect(function(plr)repairWard(plr,w)end) end end
Action.OnServerEvent:Connect(function(plr,kind,payload)
 if kind=="Sabotage" and roles[plr]=="Mole" and phase=="Night" and (sabotages[plr] or 0)>0 then
  local best=nil; local bh=-1; for _,w in ipairs(WardsFolder:GetChildren()) do local h=w:GetAttribute("Health") or 0 if h>bh then best=w; bh=h end end
  if best then best:SetAttribute("Health",math.max(0,bh-cfg.sabotage)); sabotages[plr]-=1; best.Color=(best:GetAttribute("Health") or 0)<=0 and Color3.fromRGB(38,35,45) or Color3.fromRGB(104,82,255); addFeed("A power surge damaged a ward."); broadcast() end
 elseif kind=="Vote" and phase=="Vote" and typeof(payload)=="string" then votes[plr]=payload; broadcast() end
end)
Players.PlayerAdded:Connect(function(p) alive[p]=true; ghosts[p]=false; p.CharacterAdded:Connect(function(c) task.wait(.5) if ghosts[p] then local h=c:FindFirstChildOfClass("Humanoid") if h then h.WalkSpeed=20 end end end); send(p) end)
Players.PlayerRemoving:Connect(function(p) roles[p]=nil; alive[p]=nil; ghosts[p]=nil; votes[p]=nil end)
local function knock(plr) if alive[plr]==false then return end alive[plr]=false; ghosts[plr]=true; addFeed(plr.Name.." was taken by The Watcher and will return at dawn."); local hum=plr.Character and plr.Character:FindFirstChildOfClass("Humanoid") if hum then hum.Health=0 end; broadcast() end
local function watcherStep(dt)
 local target=nil; local dist=math.huge
 for _,p in ipairs(players()) do local r=root(p); if alive[p]~=false and r and not inSafe(p) then local d=(r.Position-Watcher.Position).Magnitude if d<dist then dist=d; target=p end end end
 if target then local r=root(target); local speed=cfg.watcherSpeed+wardBrokenCount()*4; local dir=(r.Position-Watcher.Position); if dir.Magnitude>1 then Watcher.Position=Watcher.Position+dir.Unit*math.min(speed*dt,dir.Magnitude) end; if dist<cfg.catchDistance then knock(target) end end
end
local function voteResolve()
 local tally={}; for _,name in pairs(votes) do tally[name]=(tally[name] or 0)+1 end
 local top,score=nil,0; for name,n in pairs(tally) do if n>score then top=name; score=n end end
 if top then for _,p in ipairs(players()) do if p.Name==top then alive[p]=false; ghosts[p]=true; addFeed(top.." was exiled by vote."); if roles[p]=="Mole" then addFeed("The mole was exposed. Crew wins!"); return "Crew" end end end else addFeed("No exile. The crew remains divided.") end
 return nil
end
local function loop()
 while true do
  phase="Waiting"; timeLeft=8; setLighting(false); broadcast(); while timeLeft>0 do task.wait(1); timeLeft-=1; broadcast() end
  resetRound()
  for n=1,cfg.nights do
   night=n; phase="Day"; timeLeft=cfg.day; setLighting(false); addFeed("Day "..n..": repair wards and choose who to trust."); broadcast(); while timeLeft>0 do task.wait(1); timeLeft-=1; broadcast() end
   phase="Night"; timeLeft=cfg.night; setLighting(true); addFeed("Night "..n..": stay near the lamp or keep moving."); broadcast(); local last=os.clock(); while timeLeft>0 do local now=os.clock(); local dt=now-last; last=now; for _,w in ipairs(WardsFolder:GetChildren()) do local h=math.max(0,(w:GetAttribute("Health") or 0)-cfg.decay*dt); w:SetAttribute("Health",h); if h<=0 then w.Color=Color3.fromRGB(38,35,45) end end; watcherStep(dt); if livingCrewCount()==0 then phase="Reveal"; addFeed("The mole wins. Nobody survived the night."); broadcast(); task.wait(8); break end; task.wait(.25); timeLeft-=.25 end
   if phase=="Reveal" then break end
   for _,p in ipairs(players()) do if ghosts[p] then alive[p]=true; ghosts[p]=false; p:LoadCharacter() end end
   phase="Vote"; votes={}; timeLeft=cfg.vote; addFeed("Dawn vote: choose a suspect to exile."); broadcast(); while timeLeft>0 do task.wait(1); timeLeft-=1; broadcast() end
   local winner=voteResolve(); if winner then phase="Reveal"; broadcast(); task.wait(8); break end
  end
  if phase~="Reveal" then phase="Reveal"; addFeed("Crew survives the final night. Crew wins!"); broadcast(); task.wait(8) end
 end
end
task.spawn(loop)

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

-- ===== Flashlight tool: try the real Creator Store mesh first, fall back
-- to a procedural part-built flashlight (guaranteed, no external
-- dependency) if the load fails. Logs which path was used so the result
-- can be confirmed live from the Output window. =====
local FLASHLIGHT_ASSET_ID = 110700594151156
local flashlightTemplate = nil
local flashlightLoadDone = false
task.spawn(function()
	local ok, asset = pcall(function()
		return game:GetService("InsertService"):LoadAsset(FLASHLIGHT_ASSET_ID)
	end)
	if ok and asset then
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
	end
	if flashlightTemplate then
		print("[Flashlight] InsertService SUCCEEDED for asset " .. FLASHLIGHT_ASSET_ID)
	else
		print("[Flashlight] InsertService failed for asset " .. FLASHLIGHT_ASSET_ID .. ": " .. tostring(asset) .. " -- using procedural fallback")
	end
	flashlightLoadDone = true
end)

local function giveFlashlight(plr)
	local backpack = plr:FindFirstChildOfClass("Backpack")
	if not backpack then
		return
	end
	if backpack:FindFirstChild("Flashlight") or (plr.Character and plr.Character:FindFirstChild("Flashlight")) then
		return
	end
	local waited = 0
	while not flashlightLoadDone and waited < 3 do
		task.wait(0.1)
		waited += 0.1
	end
	local tool = Instance.new("Tool")
	tool.Name = "Flashlight"
	tool.RequiresHandle = true
	local handle = Instance.new("Part")
	handle.Name = "Handle"
	handle.Size = Vector3.new(0.5, 0.5, 1.8)
	handle.Material = Enum.Material.Metal
	handle.Color = Color3.fromRGB(45, 45, 48)
	handle.Parent = tool

	if flashlightTemplate then
		local ok = pcall(function()
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
			local spot = Instance.new("SpotLight")
			spot.Range = 45
			spot.Angle = 38
			spot.Brightness = 4
			spot.Face = Enum.NormalId.Front
			spot.Color = Color3.fromRGB(255, 255, 240)
			spot.Parent = handle
			mesh.Parent = tool
		end)
		if ok then
			tool.Parent = backpack
			return
		end
	end

	-- Procedural fallback: two-tone metal/rubber handle with a neon lens.
	local grip = Instance.new("Part")
	grip.Name = "Grip"
	grip.Size = Vector3.new(0.56, 0.56, 0.7)
	grip.Material = Enum.Material.Rubber
	grip.Color = Color3.fromRGB(20, 20, 20)
	grip.CFrame = handle.CFrame * CFrame.new(0, 0, 0.45)
	grip.Parent = tool
	local gripWeld = Instance.new("WeldConstraint")
	gripWeld.Part0 = handle
	gripWeld.Part1 = grip
	gripWeld.Parent = grip
	local lens = Instance.new("Part")
	lens.Name = "Lens"
	lens.Shape = Enum.PartType.Cylinder
	lens.Size = Vector3.new(0.15, 0.5, 0.5)
	lens.Material = Enum.Material.Neon
	lens.Color = Color3.fromRGB(255, 250, 220)
	lens.CFrame = handle.CFrame * CFrame.new(0, 0, -0.95) * CFrame.Angles(0, 0, math.rad(90))
	lens.Parent = tool
	local lensWeld = Instance.new("WeldConstraint")
	lensWeld.Part0 = handle
	lensWeld.Part1 = lens
	lensWeld.Parent = lens
	local spot = Instance.new("SpotLight")
	spot.Range = 45
	spot.Angle = 38
	spot.Brightness = 4
	spot.Face = Enum.NormalId.Front
	spot.Color = Color3.fromRGB(255, 255, 240)
	spot.Parent = lens
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

-- ===== Landmark buildings: try the real Creator Store models first, fall
-- back to procedural shells (guaranteed, no external dependency) for any
-- that fail to load. Positioned by scanning the ACTUAL footprint of the
-- pre-existing scene (Structures + Witchwood + CodexGameplay) and placing
-- each building outside that footprint in a distinct compass direction
-- (N / NE / SE / SW), so they never clump with or overlap the original
-- hand-placed hamlet, however large or wherever centered it turns out to
-- be. Logs which path (real asset vs fallback) each building used. =====
task.spawn(function()
	local InsertService = game:GetService("InsertService")
	local terrainInst = workspace:FindFirstChildOfClass("Terrain")

	local function groundSnap(pos)
		local rayParams = RaycastParams.new()
		rayParams.FilterType = Enum.RaycastFilterType.Include
		rayParams.FilterDescendantsInstances = terrainInst and { terrainInst } or {}
		local result = workspace:Raycast(pos + Vector3.new(0, 300, 0), Vector3.new(0, -600, 0), rayParams)
		return result and result.Position.Y or pos.Y
	end

	-- ---- Map the footprint of everything already in the scene, so the
	-- new buildings can be kept clear of it regardless of its real size. ----
	local minX, maxX, minZ, maxZ = math.huge, -math.huge, math.huge, -math.huge
	local function scan(container)
		if not container then
			return
		end
		for _, inst in ipairs(container:GetDescendants()) do
			if inst:IsA("BasePart") then
				local p = inst.Position
				minX, maxX = math.min(minX, p.X), math.max(maxX, p.X)
				minZ, maxZ = math.min(minZ, p.Z), math.max(maxZ, p.Z)
			end
		end
	end
	scan(workspace:FindFirstChild("Structures"))
	scan(workspace:FindFirstChild("Codex_Expanded_Map_Witchwood"))
	scan(workspace:FindFirstChild("CodexGameplay"))
	if minX == math.huge then
		minX, maxX, minZ, maxZ = -60, 60, -60, 60
	end
	local sceneCenter = Vector3.new((minX + maxX) / 2, 0, (minZ + maxZ) / 2)
	local MARGIN = 55
	local reachX = (maxX - minX) / 2 + MARGIN
	local reachZ = (maxZ - minZ) / 2 + MARGIN
	print(string.format(
		"[Landmarks] existing scene footprint X[%.0f,%.0f] Z[%.0f,%.0f] -- placing buildings +-%.0f/+-%.0f beyond it",
		minX, maxX, minZ, maxZ, reachX, reachZ
	))

	local function loadModel(assetId)
		local model, err = nil, nil
		local ok, e = pcall(function()
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
		if not ok then
			err = e
		end
		return model, err
	end

	local function placeModel(model, pos, footprint, yawDeg)
		local ext = model:GetExtentsSize()
		local widest = math.max(ext.X, ext.Z, 0.1)
		pcall(function()
			model:ScaleTo(footprint / widest)
		end)
		model:PivotTo(CFrame.new(pos) * CFrame.Angles(0, math.rad(yawDeg), 0))
		local bbCF, bbSize = model:GetBoundingBox()
		local floorY = groundSnap(pos)
		model:PivotTo(model:GetPivot() + Vector3.new(0, floorY - (bbCF.Position.Y - bbSize.Y / 2) - 0.4, 0))
	end

	-- ---- Procedural fallback shells (used only for buildings whose real
	-- asset fails to load) ----
	local function part(props)
		local p = Instance.new("Part")
		p.Anchored = true
		p.TopSurface = Enum.SurfaceType.Smooth
		p.BottomSurface = Enum.SurfaceType.Smooth
		for k, v in pairs(props) do
			p[k] = v
		end
		p.Parent = props.Parent
		return p
	end

	local function wallSeg(folder, a, b, yBottom, yTop, mat, color)
		local delta = Vector3.new(b.X - a.X, 0, b.Z - a.Z)
		local len = delta.Magnitude
		if len < 0.4 or yTop - yBottom < 0.4 then
			return
		end
		local mid = (a + b) / 2
		local yaw = math.atan2(delta.X, delta.Z)
		part({
			Name = "Wall",
			Size = Vector3.new(0.9, yTop - yBottom, len),
			CFrame = CFrame.new(mid.X, (yBottom + yTop) / 2, mid.Z) * CFrame.Angles(0, yaw, 0),
			Material = mat,
			Color = color,
			Parent = folder,
		})
	end

	local function buildShell(name, center, w, d, h, doorSide, mat, color, roofColor)
		local base = groundSnap(center)
		local f = Instance.new("Folder")
		f.Name = name
		part({
			Name = "Pad",
			Size = Vector3.new(w + 1.5, 0.4, d + 1.5),
			Position = Vector3.new(center.X, base + 0.2, center.Z),
			Color = Color3.fromRGB(70, 68, 64),
			Material = Enum.Material.Concrete,
			Parent = f,
		})
		local x0, x1, z0, z1 = center.X - w / 2, center.X + w / 2, center.Z - d / 2, center.Z + d / 2
		local bottom, top = base, base + h
		local sides = {
			N = { Vector3.new(x0, 0, z1), Vector3.new(x1, 0, z1) },
			S = { Vector3.new(x0, 0, z0), Vector3.new(x1, 0, z0) },
			E = { Vector3.new(x1, 0, z0), Vector3.new(x1, 0, z1) },
			W = { Vector3.new(x0, 0, z0), Vector3.new(x0, 0, z1) },
		}
		for side, ab in pairs(sides) do
			local a, b = ab[1], ab[2]
			if side == doorSide then
				local mid = (a + b) / 2
				local dir = (b - a).Unit
				local doorHalf = math.min(4, w / 4)
				wallSeg(f, a, mid - dir * doorHalf, bottom, top, mat, color)
				wallSeg(f, mid + dir * doorHalf, b, bottom, top, mat, color)
				wallSeg(f, mid - dir * doorHalf, mid + dir * doorHalf, bottom + h * 0.7, top, mat, color)
			else
				wallSeg(f, a, b, bottom, top, mat, color)
			end
		end
		part({
			Name = "RoofN",
			Size = Vector3.new(w + 2, 0.7, d / 2 + 2),
			CFrame = CFrame.new(center.X, top + 1.6, center.Z + d / 4) * CFrame.Angles(math.rad(18), 0, 0),
			Color = roofColor,
			Material = Enum.Material.Slate,
			Parent = f,
		})
		part({
			Name = "RoofS",
			Size = Vector3.new(w + 2, 0.7, d / 2 + 2),
			CFrame = CFrame.new(center.X, top + 1.6, center.Z - d / 4) * CFrame.Angles(math.rad(-18), 0, 0),
			Color = roofColor,
			Material = Enum.Material.Slate,
			Parent = f,
		})
		return f, base
	end

	local buildingsFolder = Instance.new("Folder")
	buildingsFolder.Name = "LandmarkBuildings"
	buildingsFolder.Parent = workspace

	local BUILDINGS = {
		{ id = 109175553546833, name = "CampHouse", dir = Vector3.new(0, 0, 1), footprint = 52, yaw = 180,
			shell = { w = 56, d = 44, h = 13, door = "S", mat = Enum.Material.Wood, color = Color3.fromRGB(96, 68, 44), roof = Color3.fromRGB(50, 38, 30) } },
		{ id = 12129034740, name = "FarmHouseAndLake", dir = Vector3.new(1, 0, -1), footprint = 58, yaw = 20,
			shell = { w = 30, d = 22, h = 12, door = "N", mat = Enum.Material.WoodPlanks, color = Color3.fromRGB(120, 40, 34), roof = Color3.fromRGB(50, 46, 42) } },
		{ id = 128655727108731, name = "Warehouse", dir = Vector3.new(-1, 0, -1), footprint = 54, yaw = 200,
			shell = { w = 26, d = 20, h = 10, door = "E", mat = Enum.Material.Concrete, color = Color3.fromRGB(58, 58, 56), roof = Color3.fromRGB(30, 30, 30) } },
		{ id = 112448492652447, name = "Factory", dir = Vector3.new(1, 0, 1), footprint = 62, yaw = 300,
			shell = { w = 34, d = 26, h = 14, door = "W", mat = Enum.Material.CorrodedMetal, color = Color3.fromRGB(70, 60, 52), roof = Color3.fromRGB(40, 40, 40) } },
	}

	for _, b in ipairs(BUILDINGS) do
		local pos = sceneCenter + Vector3.new(b.dir.X * reachX, 0, b.dir.Z * reachZ)
		local model, err = loadModel(b.id)
		if model then
			model.Name = b.name
			placeModel(model, pos, b.footprint, b.yaw)
			model.Parent = buildingsFolder
			print("[Landmarks] " .. b.name .. ": InsertService SUCCEEDED (asset " .. b.id .. ")")
		else
			print("[Landmarks] " .. b.name .. ": InsertService failed (asset " .. b.id .. "): " .. tostring(err) .. " -- using procedural fallback")
			local sh = b.shell
			local shellFolder, base = buildShell(b.name, pos, sh.w, sh.d, sh.h, sh.door, sh.mat, sh.color, sh.roof)
			shellFolder.Parent = buildingsFolder
			if b.name == "FarmHouseAndLake" then
				part({ Name = "Silo", Shape = Enum.PartType.Cylinder, Size = Vector3.new(14, 5, 5),
					CFrame = CFrame.new(pos.X + 20, base + 7, pos.Z) * CFrame.Angles(0, 0, math.rad(90)),
					Color = Color3.fromRGB(150, 150, 150), Material = Enum.Material.Metal, Parent = shellFolder })
			elseif b.name == "Factory" then
				for i = 1, 8 do
					if i ~= 2 and i ~= 5 and i ~= 7 then
						local angle = (i / 8) * math.pi * 2
						local px = pos.X + math.cos(angle) * 26
						local pz = pos.Z + math.sin(angle) * 26
						local py = groundSnap(Vector3.new(px, 0, pz))
						part({ Name = "FenceLink", Size = Vector3.new(0.3, 6, 8), Position = Vector3.new(px, py + 3, pz),
							Orientation = Vector3.new(0, math.deg(angle) + 90, 0), Transparency = 0.4,
							Color = Color3.fromRGB(140, 140, 140), Material = Enum.Material.DiamondPlate, Parent = shellFolder })
					end
				end
				for _, off in ipairs({ Vector3.new(6, 0, 4), Vector3.new(-4, 0, -6) }) do
					local px, pz = pos.X + off.X, pos.Z + off.Z
					local py = groundSnap(Vector3.new(px, 0, pz))
					part({ Name = "Pipe", Shape = Enum.PartType.Cylinder, Size = Vector3.new(9, 1.4, 1.4),
						CFrame = CFrame.new(px, py + 1.5, pz) * CFrame.Angles(0, 0, math.rad(90)),
						Color = Color3.fromRGB(90, 70, 50), Material = Enum.Material.CorrodedMetal, Parent = shellFolder })
				end
			end
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
