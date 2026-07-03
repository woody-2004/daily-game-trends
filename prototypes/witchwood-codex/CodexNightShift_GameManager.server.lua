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
