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

