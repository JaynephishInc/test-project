-- Active Pet Simulator-style breakable economy
local Players=game:GetService("Players")
local RS=game:GetService("ReplicatedStorage")
local Balance=require(RS:WaitForChild("GameBalance"))
local Damage=require(game.ServerStorage:WaitForChild("EquippedBreakableDamage"))
local Design=require(RS:WaitForChild("ProgressionDesign"))
local Notify=RS:WaitForChild("BrainrotRemotes"):WaitForChild("Notify")
local CombatFeedback=RS.BrainrotRemotes:FindFirstChild("CombatFeedback") or Instance.new("RemoteEvent")
CombatFeedback.Name="CombatFeedback";CombatFeedback.Parent=RS.BrainrotRemotes
-- Tells every client "this treasure just broke, here is who got what" so TreasureBreakClient can play
-- the spill / lid / vault-door animation and fly the coins to the players who helped.
local Burst=RS.BrainrotRemotes:FindFirstChild("BreakableBurst") or Instance.new("RemoteEvent")
Burst.Name="BreakableBurst";Burst.Parent=RS.BrainrotRemotes
local function fmt(n) local s=tostring(math.floor(n)):reverse():gsub("(%d%d%d)","%1,"):reverse() return (s:gsub("^,","")) end
local folder=workspace:WaitForChild("PiazzaBrainrot"):WaitForChild("Breakables")
local TICK=Balance.Breakables.AttackInterval
local MAX_DISTANCE=Balance.Breakables.MaxAttackDistance
local targets,damageBy,connections={},{},{}

local lastClick,nextAttack,combos={},{},{}
local promptConnections={}
local function allowed(plr,model)
 local character=plr.Character
 local humanoid=character and character:FindFirstChildOfClass("Humanoid")
 if not humanoid or humanoid.Health<=0 then return false end
 if model:GetAttribute("IsWildBrainrot") then
  local variant=model:GetAttribute("Variant")
  if variant~="Normal" and (not _G.PlazaIslandUnlocked or not _G.PlazaIslandUnlocked(plr,variant)) then return false end
 end
 return true
end
local applyDamage
local function attackPower(plr) return Damage.ForPlayer(plr) end
local function mutationOf(model)
	return model:GetAttribute("Mutation") or model:GetAttribute("Variant") or model.Name:match("^Island_([^_]+)_") or "Gold"
end
local function typeOf(model)
	return model:GetAttribute("BreakableType") or model.Name:match("_([^_]+)$") or "Breakable"
end
local function updateBillboard(model)
	local max=math.max(1,model:GetAttribute("MaxHealth") or 1)
	local hp=math.clamp(model:GetAttribute("Health") or 0,0,max)
	local bb=model:FindFirstChild("BreakableBillboard");local back=bb and bb:FindFirstChild("HealthBack")
	local fill=back and back:FindFirstChild("Fill");local label=back and back:FindFirstChild("Health")
	if fill then fill.Size=UDim2.fromScale(hp/max,1);fill.BackgroundColor3=(hp/max>.55 and Color3.fromRGB(75,220,100)) or (hp/max>.25 and Color3.fromRGB(255,190,50)) or Color3.fromRGB(255,76,76) end
	if label then label.Text=string.format("%d / %d",math.ceil(hp),max) end
end
local function setVisible(model,visible)
	model:SetAttribute("Active",visible)
	for _,d in ipairs(model:GetDescendants()) do
		if d:IsA("BasePart") then
			local original=d:GetAttribute("BreakableTransparency")
			if original==nil then original=d.Transparency;d:SetAttribute("BreakableTransparency",original) end
			d.Transparency=visible and original or 1;d.CanQuery=visible and d.Name=="Hitbox"
		elseif d:IsA("ProximityPrompt") then d.Enabled=visible
		elseif d:IsA("BillboardGui") or d:IsA("SurfaceGui") then d.Enabled=visible
		elseif d:IsA("ParticleEmitter") or d:IsA("Light") or d:IsA("Beam") or d:IsA("Trail") then
			local original=d:GetAttribute("BreakableEnabled")
			if original==nil then original=d.Enabled;d:SetAttribute("BreakableEnabled",original) end
			d.Enabled=visible and original or false
		end
	end
end
local function clearTarget(plr)
	targets[plr]=nil;nextAttack[plr]=nil
	if plr.Parent then plr:SetAttribute("AttackTarget",nil) end
end
local function chooseTarget(plr,model)
 if not model:GetAttribute("Active") or not allowed(plr,model) then return end
 local hrp=plr.Character and plr.Character:FindFirstChild("HumanoidRootPart")
 if not hrp or (hrp.Position-model:GetPivot().Position).Magnitude>MAX_DISTANCE then
  Notify:FireClient(plr,"Move closer to hit this target.");return
 end
 local power,count,profile=attackPower(plr)
 local now=os.clock()
 if lastClick[plr] and now-lastClick[plr]<.12 then return end
 lastClick[plr]=now
 if count==0 then
  clearTarget(plr)
  applyDamage(plr,model,Balance.Breakables.ManualClickDamage,{crit=0.05,shield=1,reward=1,roles={}})
 else
  local changed=targets[plr]~=model
  targets[plr]=model;plr:SetAttribute("AttackTarget",model.Name)
  if not nextAttack[plr] or now>=nextAttack[plr] then
   nextAttack[plr]=now+TICK;applyDamage(plr,model,power,profile)
  end
  if changed then Notify:FireClient(plr,"Brainrots attacking "..(model:GetAttribute("DisplayName") or model.Name).."!") end
 end
end
-- Random respawn ---------------------------------------------------------------------------------------
-- Coins, bags, chests and other treasure come back somewhere NEW instead of the same spot. They stay in their own
-- area: island treasure stays on its island, plaza treasure stays with the other plaza treasure. A spot must be
-- flat ground at the same height as the original (no rooftops, no water) with nothing solid in the way.
-- Bosses, vaults, event vaults and wild brainrots keep their spots. Set FixedSpawn = true on a model to keep it in place.
local SPAWN_TRIES=40
local SPAWN_GAP=9        -- studs between treasures
local AREA_LINK=120      -- plaza treasure this close together counts as one area
local AREA_MARGIN=25     -- treasure can appear this far past the outermost original spot
local homes={}           -- model -> {cf, groundY, height, size, area}
local rng=Random.new()
local function canMove(model)
	if model:GetAttribute("FixedSpawn") or model:GetAttribute("IsBoss") or model:GetAttribute("EventVault")
		or model:GetAttribute("OneShot") or model:GetAttribute("IsWildBrainrot") then return false end
	local t=typeOf(model)
	return t~="Vault" and t~="Boss"
end
local function ignoreList(withCharacters)
	local list={folder,workspace.Terrain}
	for _,name in ipairs({"PlazaFollowers","IslandEggs","IslandVaultEvent","IslandQuestGivers"}) do
		local f=workspace:FindFirstChild(name);if f then table.insert(list,f) end
	end
	if withCharacters then for _,p in ipairs(Players:GetPlayers()) do if p.Character then table.insert(list,p.Character) end end end
	return list
end
local rayParams=RaycastParams.new();rayParams.FilterType=Enum.RaycastFilterType.Exclude;rayParams.RespectCanCollide=true
local overlapParams=OverlapParams.new();overlapParams.FilterType=Enum.RaycastFilterType.Exclude;overlapParams.RespectCanCollide=true
local function groundBelow(x,z,fromY)
	local list=ignoreList(true);table.remove(list,2) -- keep Terrain for the ground ray
	rayParams.FilterDescendantsInstances=list
	return workspace:Raycast(Vector3.new(x,fromY,z),Vector3.new(0,-200,0),rayParams)
end
-- size of the visible treasure (the invisible Hitbox is often bigger than the treasure itself)
local function visibleSize(model)
	local lo,hi=Vector3.one*math.huge,-Vector3.one*math.huge
	for _,part in ipairs(model:GetDescendants()) do
		if part:IsA("BasePart") and part.Name~="Hitbox" then
			local half=part.Size/2
			for sx=-1,1,2 do for sy=-1,1,2 do for sz=-1,1,2 do
				local w=part.CFrame:PointToWorldSpace(Vector3.new(half.X*sx,half.Y*sy,half.Z*sz));lo=lo:Min(w);hi=hi:Max(w)
			end end end
		end
	end
	return lo.X<math.huge and (hi-lo) or model:GetExtentsSize()
end
local function rememberHome(model)
	if homes[model] or not canMove(model) then return end
	local cf=model:GetPivot()
	local hit=groundBelow(cf.X,cf.Z,cf.Y+3) -- start just above it so a roof or tree overhead doesn't count as ground
	if not hit then return end
	local size=visibleSize(model)
	local island=model.Name:match("^Island_([^_]+)_")
	homes[model]={cf=cf,groundY=hit.Position.Y,height=cf.Y-hit.Position.Y,size=size,area=island and ("island:"..island) or "plaza"}
end
-- the box (in X/Z) this model is allowed to respawn in: around every original spot in its area
local function areaBox(model)
	local h=homes[model]
	local members={h}
	if h.area=="plaza" then
		-- plaza-style treasure: grow the group from this model through treasure within AREA_LINK of each other
		local open,seen={h},{[h]=true}
		while #open>0 do
			local a=table.remove(open)
			for _,b in pairs(homes) do
				if not seen[b] and b.area=="plaza" and (Vector3.new(a.cf.X,0,a.cf.Z)-Vector3.new(b.cf.X,0,b.cf.Z)).Magnitude<=AREA_LINK then
					seen[b]=true;table.insert(open,b);table.insert(members,b)
				end
			end
		end
	else
		for _,b in pairs(homes) do if b~=h and b.area==h.area then table.insert(members,b) end end
	end
	local minX,maxX,minZ,maxZ=math.huge,-math.huge,math.huge,-math.huge
	for _,m in ipairs(members) do minX=math.min(minX,m.cf.X);maxX=math.max(maxX,m.cf.X);minZ=math.min(minZ,m.cf.Z);maxZ=math.max(maxZ,m.cf.Z) end
	return minX-AREA_MARGIN,maxX+AREA_MARGIN,minZ-AREA_MARGIN,maxZ+AREA_MARGIN
end
local function spotIsFree(model,h,ground)
	if math.abs(ground.Position.Y-h.groundY)>3 or ground.Normal.Y<0.9 or ground.Material==Enum.Material.Water then return false end
	local p=ground.Position
	for _,other in ipairs(folder:GetChildren()) do
		if other~=model and other:IsA("Model") and other:GetAttribute("Active")~=false then
			local o=other:GetPivot().Position
			if (Vector3.new(o.X,0,o.Z)-Vector3.new(p.X,0,p.Z)).Magnitude<SPAWN_GAP then return false end
		end
	end
	overlapParams.FilterDescendantsInstances=ignoreList(false)
	local box=Vector3.new(math.max(2,h.size.X*0.8),math.max(3,h.size.Y),math.max(2,h.size.Z*0.8))
	local blocked=workspace:GetPartBoundsInBox(CFrame.new(p+Vector3.new(0,box.Y/2+0.4,0)),box,overlapParams)
	return #blocked==0
end
local function moveToRandomSpot(model)
	local h=homes[model]
	if not h or not model.Parent then return end
	local minX,maxX,minZ,maxZ=areaBox(model)
	for _=1,SPAWN_TRIES do
		local x,z=rng:NextNumber(minX,maxX),rng:NextNumber(minZ,maxZ)
		local ground=groundBelow(x,z,h.groundY+60)
		if ground and spotIsFree(model,h,ground) then
			local spin=CFrame.Angles(0,rng:NextNumber(0,math.pi*2),0)
			model:PivotTo(CFrame.new(x,ground.Position.Y+h.height,z)*spin*h.cf.Rotation)
			model:SetAttribute("SpawnCF",model:GetPivot()) -- clients that animate treasure can re-read where it is
			return true
		end
	end
	return false -- no good spot found this time: it comes back where it was
end

local function breakModel(model,finisher)
	if not model:GetAttribute("Active") then return end
	local ledger=damageBy[model] or {};local total=0
	for _,amount in pairs(ledger) do total+=amount end
	if total<=0 and finisher then ledger[finisher]=1;total=1 end
	-- health = coins it pays out, unless the model sets a bigger RewardPool (island vault events)
	local reward=model:GetAttribute("RewardPool") or model:GetAttribute("MaxHealth") or model:GetAttribute("Reward") or 10
	if mutationOf(model)=="Glitch" and model:GetAttribute("GlitchModifier")=="Rich" then reward*=1.5 end
	local helpers=0
	for plr in pairs(ledger) do if plr.Parent then helpers+=1 end end
	-- EqualSplit (0..1): that part of the pool is shared equally by everyone who helped, the rest by damage dealt
	local equal=math.clamp(model:GetAttribute("EqualSplit") or 0,0,1)
	local name=model:GetAttribute("DisplayName") or "Breakable"
	local paidOut={}
	for plr,amount in pairs(ledger) do
		if plr.Parent then
			local frac=(1-equal)*(amount/total)+equal/math.max(1,helpers)
			local _,_,profile=attackPower(plr)
			local share=math.max(1,math.floor(reward*frac*(profile and profile.reward or 1)))
			local ok,paid
			if _G.PlazaAwardMoney then ok,paid=_G.PlazaAwardMoney(plr,share) end
			if ok then
				paidOut[tostring(plr.UserId)]=paid
				local msg=model:GetAttribute("EventVault")
					and string.format("🏦 %s cracked! You did %d%% of the damage · +%s coins",name,math.floor(amount/total*100+.5),fmt(paid))
					or string.format("%s %s! +%s coins",name,model:GetAttribute("IsWildBrainrot") and "defeated" or "broken",fmt(paid))
				task.delay(1.1,function() if plr.Parent then Notify:FireClient(plr,msg) end end) -- lands as the coins arrive
			end
		end
	end
	local events=game.ServerStorage:FindFirstChild("ProgressionEvents")
	local progressEvent=events and events:FindFirstChild("QuestProgress")
	if progressEvent then
		local mutation=mutationOf(model)
		local targetType=typeOf(model)
		for plr in pairs(ledger) do if plr.Parent then progressEvent:Fire(plr,"Break",mutation,1,targetType) end end
	end
	Burst:FireAllClients(model,paidOut)
	if _G.PlazaOnBroken then task.spawn(_G.PlazaOnBroken,model,ledger) end -- wild captures (WildCaptureAndStorms)
	setVisible(model,false)
	damageBy[model]={}
	for plr,target in pairs(targets) do if target==model then clearTarget(plr) end end
	if model:GetAttribute("OneShot") then -- event vaults don't respawn
		if connections[model] then connections[model]:Disconnect();connections[model]=nil end
		task.delay(4,function() damageBy[model]=nil;if model.Parent then model:Destroy() end end)
		return
	end
	local respawnIn=model:GetAttribute("RespawnTime") or 10
	model:SetAttribute("RespawnAt",workspace:GetServerTimeNow()+respawnIn) -- boss timers / clients can count down to it
	task.delay(respawnIn,function()
		if not model.Parent then return end
		model:SetAttribute("RespawnAt",nil)
		local max=model:GetAttribute("MaxHealth") or 100
		model:SetAttribute("Health",max)
		local mutation=mutationOf(model)
		model:SetAttribute("ShieldHealth",mutation=="Diamond" and math.floor(max*0.35) or 0)
		if mutation=="Glitch" then model:SetAttribute("GlitchModifier",({"Fragile","Rich","Frenzy"})[math.random(1,3)]) end
		pcall(moveToRandomSpot,model)
		updateBillboard(model);setVisible(model,true)
	end)
end
applyDamage=function(plr,model,power,profile)
	if not model:GetAttribute("Active") then return end
	profile=profile or select(3,attackPower(plr)) or {crit=0.05,shield=1,reward=1,roles={}}
	local now=os.clock()
	local combo=combos[plr]
	if not combo or combo.model~=model or now-combo.last>2.2 then combo={model=model,count=0,last=now};combos[plr]=combo end
	combo.count=math.min(20,combo.count+1);combo.last=now
	local mutation=mutationOf(model)
	local max=math.max(1,model:GetAttribute("MaxHealth") or 1)
	local hp=math.max(0,model:GetAttribute("Health") or 0)
	local multiplier=1
	local weak=false
	if mutation=="Gold" then multiplier*=1+math.min(combo.count,10)*0.03 end
	if mutation=="Cosmic" then
		weak=math.floor(workspace:GetServerTimeNow())%6<2
		multiplier*=weak and 1.75 or 0.85
	end
	if mutation=="Lava" and combo.count>=6 then multiplier*=1.5 end
	if mutation=="Glitch" then
		local mod=model:GetAttribute("GlitchModifier")
		if mod=="Fragile" then multiplier*=1.5 elseif mod=="Frenzy" then multiplier*=1.2 end
	end
	local stage=model:GetAttribute("EventVault") and (model:GetAttribute("VaultStage") or 1) or 0
	if stage==1 then multiplier*=0.7 elseif stage==2 then multiplier*=1.15 elseif stage==3 then multiplier*=1.4 end
	local crit=math.random()<math.clamp(profile.crit or 0.05,0,0.6)
	if crit then multiplier*=2 end
	power*=multiplier

	local ledger=damageBy[model] or {};damageBy[model]=ledger
	local shield=model:GetAttribute("ShieldHealth") or 0
	if shield>0 then
		local absorbed=math.min(shield,power*(profile.shield or 1))
		model:SetAttribute("ShieldHealth",shield-absorbed)
		ledger[plr]=(ledger[plr] or 0)+absorbed
		model:SetAttribute("AttackPulse",(model:GetAttribute("AttackPulse") or 0)+1)
		CombatFeedback:FireClient(plr,{damage=math.floor(absorbed),crit=crit,combo=combo.count,shield=true,weak=weak,mutation=mutation})
		return
	end

	local dealt=math.min(hp,power)
	if dealt<=0 then return end
	hp-=dealt
	model:SetAttribute("Health",hp)
	model:SetAttribute("LastDamagedAt",now)
	model:SetAttribute("AttackPulse",(model:GetAttribute("AttackPulse") or 0)+1)
	ledger[plr]=(ledger[plr] or 0)+dealt

	if model:GetAttribute("EventVault") then
		local ratio=hp/max
		local newStage=ratio>0.66 and 1 or (ratio>0.33 and 2 or 3)
		if newStage~=stage then
			model:SetAttribute("VaultStage",newStage)
			CombatFeedback:FireAllClients({stage=newStage,mutation=mutation,eventVault=true})
			if newStage==3 then
				local events=game.ServerStorage:FindFirstChild("ProgressionEvents")
				local progress=events and events:FindFirstChild("QuestProgress")
				if progress then for helper in pairs(ledger) do if helper.Parent then progress:Fire(helper,"VaultStage",mutation,1,"Vault") end end end
			end
		end
	end
	CombatFeedback:FireClient(plr,{damage=math.floor(dealt),crit=crit,combo=combo.count,shield=false,weak=weak,mutation=mutation,stage=model:GetAttribute("VaultStage")})
	updateBillboard(model)
	if hp<=0 then breakModel(model,plr) end
end
local function prepare(model)
	if connections[model] then return end
	local max=model:GetAttribute("MaxHealth") or 100
	model:SetAttribute("Health",max);model:SetAttribute("Reward",max);model:SetAttribute("Active",true);damageBy[model]={}
	local mutation=mutationOf(model)
	model:SetAttribute("IslandMechanic",Design.IslandMechanics[mutation] and Design.IslandMechanics[mutation].name or "")
	model:SetAttribute("ShieldHealth",mutation=="Diamond" and math.floor(max*0.35) or 0)
	model:SetAttribute("VaultStage",model:GetAttribute("EventVault") and 1 or nil)
	if mutation=="Glitch" then model:SetAttribute("GlitchModifier",({"Fragile","Rich","Frenzy"})[math.random(1,3)]) end
	for _,d in ipairs(model:GetDescendants()) do if d:IsA("BasePart") and d:GetAttribute("BreakableTransparency")==nil then d:SetAttribute("BreakableTransparency",d.Transparency) end end
	updateBillboard(model)
	pcall(rememberHome,model)
	local hit=model:FindFirstChild("Hitbox");local click=hit and hit:FindFirstChildOfClass("ClickDetector")
	if click then connections[model]=click.MouseClick:Connect(function(plr) chooseTarget(plr,model) end) end
	local prompt=hit and hit:FindFirstChild("FightPrompt")
	if prompt then promptConnections[model]=prompt.Triggered:Connect(function(plr) chooseTarget(plr,model) end) end
end
for _,model in ipairs(folder:GetChildren()) do if model:IsA("Model") then prepare(model) end end
folder.ChildAdded:Connect(function(model) if model:IsA("Model") then task.defer(prepare,model) end end)
Players.PlayerRemoving:Connect(function(plr) clearTarget(plr);lastClick[plr]=nil;combos[plr]=nil;for _,ledger in pairs(damageBy) do ledger[plr]=nil end end)
-- models removed from the folder (event vaults) leave nothing behind
folder.ChildRemoved:Connect(function(model)
	damageBy[model]=nil;homes[model]=nil
	if promptConnections[model] then promptConnections[model]:Disconnect();promptConnections[model]=nil end
	if connections[model] then connections[model]:Disconnect();connections[model]=nil end
	for plr,target in pairs(targets) do if target==model then clearTarget(plr) end end
end)
-- IslandVaultEvent reads this to show who is helping and to pay consolation shares on a timeout
_G.PlazaChooseCombatTarget=chooseTarget
-- A click/tap that lands on your own character or squad (they often stand in front of the treasure) is passed on
-- by BreakableFXClient as "the breakable behind it". Same checks as a real click (chooseTarget: active, allowed,
-- distance, 0.12 s rate limit), and only for models that are clickable in the first place.
local TapBreakable=RS.BrainrotRemotes:FindFirstChild("TapBreakable") or Instance.new("RemoteEvent")
TapBreakable.Name="TapBreakable";TapBreakable.Parent=RS.BrainrotRemotes
TapBreakable.OnServerEvent:Connect(function(plr,model)
	if typeof(model)~="Instance" or not model:IsA("Model") or model.Parent~=folder then return end
	local hit=model:FindFirstChild("Hitbox")
	if not (hit and hit:FindFirstChildOfClass("ClickDetector")) then return end
	chooseTarget(plr,model)
end)
_G.PlazaBreakableLedger=function(model) return damageBy[model] end
-- testing / admin: break a treasure right now on behalf of a player (server command bar only)
_G.PlazaBreakNow=function(model,plr) if model and plr then applyDamage(plr,model,math.huge) end end
task.spawn(function()
	while true do
		task.wait(TICK)
		for _,model in ipairs(folder:GetChildren()) do
			if model:IsA("Model") and model:GetAttribute("Active") and mutationOf(model)=="Toxic" then
				local last=model:GetAttribute("LastDamagedAt") or 0
				local hp,max=model:GetAttribute("Health") or 0,model:GetAttribute("MaxHealth") or 1
				if os.clock()-last>2 and hp>0 and hp<max then
					model:SetAttribute("Health",math.min(max,hp+max*0.004*TICK));updateBillboard(model)
				end
			end
		end
		for plr,model in pairs(targets) do
			if not plr.Parent or not model.Parent or not model:GetAttribute("Active") then clearTarget(plr) else
				local hrp=plr.Character and plr.Character:FindFirstChild("HumanoidRootPart")
				local power,count,profile=attackPower(plr)
				if not allowed(plr,model) or not hrp or count==0 or (hrp.Position-model:GetPivot().Position).Magnitude>MAX_DISTANCE+25 then clearTarget(plr) else
					local now=os.clock()
                    if now>=(nextAttack[plr] or 0) then nextAttack[plr]=now+TICK;applyDamage(plr,model,power,profile) end
				end
			end
		end
	end
end)
