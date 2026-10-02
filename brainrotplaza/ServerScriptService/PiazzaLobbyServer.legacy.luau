--[[ Piazza Brainrot lobby server
  - Safe zone (whole square): no damage in or from inside the square
  - Tokens, free lobby tokens, Brainrot Reactor rolls
  - Rare pulls: reactor erupts, lamps flash, giant hologram for 10s
  - Kill streaks, crowns, bounties (works with any weapon that uses the classic "creator" tag,
    or fire ServerStorage.BrainrotEvents.AwardKill:Fire(killerPlayer, victimPlayer) from your combat code)
  - Strongest Brainrot + Most Wanted boards, weekend tournament countdown
]]
local Players = game:GetService("Players")
local RS = game:GetService("ReplicatedStorage")
local SS = game:GetService("ServerStorage")
local CS = game:GetService("CollectionService")
local TweenService = game:GetService("TweenService")
local RunService = game:GetService("RunService")
local DataStoreService = game:GetService("DataStoreService")
local MarketplaceService = game:GetService("MarketplaceService")

local CONFIG = {
	StartingTokens = 3,
	RollCost = 1,
	RollCooldown = 7.0,       -- matches the client reveal animation
	RevealDelay = 6.25,
	KillReward = 3,
	CrownStreak = 3,
	BountyBase = 5,
	BountyPerStreak = 2,
	HologramSeconds = 10,
	HologramHeight = 55,
	EruptRarities = { Legendary = true, Mythic = true },
	SafeZoneHalfSize = 245,
	-- Weekend tournament: starts Saturday 17:00 UTC (10am Pacific), lasts 30 hours
	TournamentWday = 7, TournamentHourUTC = 17, TournamentHours = 30,
}
local Balance = require(RS:WaitForChild("GameBalance"))
local Design = require(RS:WaitForChild("ProgressionDesign"))
local function taggedInWorld(tag)
	local out = {}
	for _, inst in ipairs(CS:GetTagged(tag)) do if inst:IsDescendantOf(workspace) then table.insert(out, inst) end end
	return out
end
local Catalog = require(RS:WaitForChild("BrainrotCatalog"))
local RollConfig=require(RS:WaitForChild("BrainrotRollConfig"))
local RollPool=RollConfig.Build(Catalog.Entries)
local Inventory = require(SS:WaitForChild("BrainrotInventoryRules"))
local RARITIES = {
 {name="Common",weight=48,color=Color3.fromRGB(210,215,225)},
 {name="Rare",weight=25,color=Color3.fromRGB(80,160,255)},
 {name="Epic",weight=14,color=Color3.fromRGB(185,110,255)},
 {name="Legendary",weight=7,color=Color3.fromRGB(255,195,65)},
 {name="Mythic",weight=3,color=Color3.fromRGB(255,80,160)},
 {name="Brainrot God",weight=1.5,color=Color3.fromRGB(255,244,185)},
 {name="Secret",weight=0.8,color=Color3.fromRGB(155,255,222)},
 {name="OG",weight=0.2,color=Color3.fromRGB(255,118,77)},
 {name="Unrated",weight=0.5,color=Color3.fromRGB(148,163,184)},
}
local BRAINROTS = {}
local modelById={}
for _,r in ipairs(RARITIES) do BRAINROTS[r.name]={} end
for _,entry in ipairs(Catalog.Entries) do table.insert(BRAINROTS[entry.rarity],{entry.id,entry.power}) end
for _,g in ipairs(game:GetService("ServerStorage"):WaitForChild("BrainrotPack"):GetChildren()) do
 for _,m in ipairs(g:GetChildren()) do
  local id=m:GetAttribute("CatalogId")
  if id then modelById[id]=m end
 end
end
local function displayName(id)
 local e=Catalog.ById[id];return e and (e.variant.." "..e.name) or id
end
local rarityByName, rarityOfBrainrot = {}, {}
for _, r in ipairs(RARITIES) do rarityByName[r.name] = r end
for rname, list in pairs(BRAINROTS) do for _, b in ipairs(list) do rarityOfBrainrot[b[1]] = rname end end

-- Remotes / bindables ---------------------------------------------------------
local remotes = RS:FindFirstChild("BrainrotRemotes") or Instance.new("Folder")
remotes.Name = "BrainrotRemotes"; remotes.Parent = RS
local function remote(n) local r = remotes:FindFirstChild(n) or Instance.new("RemoteEvent"); r.Name = n; r.Parent = remotes; return r end
local RollReveal, BigPull, Notify = remote("RollReveal"), remote("BigPull"), remote("Notify")
local rosterFolder = remotes:FindFirstChild("Roster") or Instance.new("StringValue")
rosterFolder.Name = "Roster"; rosterFolder.Parent = remotes
do
	local names = {}
	for _, r in ipairs(RARITIES) do for _, b in ipairs(BRAINROTS[r.name]) do table.insert(names, b[1].."|"..r.name) end end
	rosterFolder.Value = table.concat(names, ";")
end
local variantInfo = remotes:FindFirstChild("Variants") or Instance.new("StringValue")
variantInfo.Name = "Variants"; variantInfo.Parent = remotes
local events = SS:FindFirstChild("BrainrotEvents") or Instance.new("Folder")
events.Name = "BrainrotEvents"; events.Parent = SS
local AwardKillEvent = events:FindFirstChild("AwardKill") or Instance.new("BindableEvent")
AwardKillEvent.Name = "AwardKill"; AwardKillEvent.Parent = events
local GiveTokensEvent = events:FindFirstChild("GiveTokens") or Instance.new("BindableEvent")
GiveTokensEvent.Name = "GiveTokens"; GiveTokensEvent.Parent = events

-- World refs ------------------------------------------------------------------
local piazza = workspace:WaitForChild("PiazzaBrainrot")
local reactor = piazza.Fountain:WaitForChild("Reactor")
local templates = SS:WaitForChild("BrainrotTemplates")
local showcase = piazza:WaitForChild("Showcase")

-- Data ------------------------------------------------------------------------
local store, powerStore
pcall(function() store = DataStoreService:GetDataStore("PiazzaBrainrot_v1") end)
pcall(function() powerStore = DataStoreService:GetOrderedDataStore("PiazzaBrainrot_Power_v1") end)
local data = {}

local function newData()
	return { Tokens = CONFIG.StartingTokens, Money = 0, Rebirths = 0, LuckRolls = 0, WheelSpins = 0, BestName = "", BestPower = 0, Kills = 0, Collection = {}, MoneyBoostUntil = 0, SpeedBoostUntil = 0, FusionLevels = {}, EggPity = {}, QuestProgress = {}, QuestCompleted = {}, ActiveQuest = "" }
end

local HttpService = game:GetService("HttpService")
local powerOf = {["Grissino Grigio"]=10,["Olivetta Oliva"]=12,["Panino Pigro"]=15,["Biscottino Bello"]=18,["Risottino Ribelle"]=40,["Lasagnone Lento"]=50,["Bruschettina Brava"]=60,["Spaghettone Polpetto"]=120,["Gelatone Occhialone"]=140,["Tortellino Turbo"]=150,["Cannolino Razzo"]=320,["Moka Motorino"]=380,["Pizzaflamingo Espressone"]=1000}
for _, list in pairs(BRAINROTS) do for _, b in ipairs(list) do powerOf[b[1]] = b[2] end end
local function capOf(d) return Inventory.Capacity + (d.ExtraSlots or 0) end
local function speedOf(d)
	local base = 16 + 3 * (d.SpeedLevel or 0)
	return base * ((d.SpeedBoostUntil or 0) > os.time() and 2 or 1)
end
local function multiplier(d) return 1 + 0.5 * (d.Rebirths or 0) end
local function recompute(d)
	local best, bestName = 0, ""
	for name, count in pairs(d.Collection) do
		if count > 0 and (powerOf[name] or 0) > best then best, bestName = powerOf[name], name end
	end
	d.BestPower = math.floor(best * multiplier(d)); d.BestName = bestName
end
-- Coins per second for one brainrot = rarity base x mutation multiplier
local COIN_RARITY = { Common = 5, Rare = 12, Epic = 30, Legendary = 75, Mythic = 200, ["Brainrot God"] = 600, Secret = 1500, OG = 5000, Unrated = 20 }
local COIN_MUTATION = { Normal = 1, Gold = 1.5, Diamond = 2, Cosmic = 3, Lava = 5, Toxic = 7, Glitch = 15 }
local function coinRate(id)
	local e = Catalog.ById[id]; if not e then return 0 end
	return (COIN_RARITY[e.rarity] or 1) * (COIN_MUTATION[e.variant] or 1)
end
_G.PlazaCoinRate = coinRate
local function syncStats(plr)
	local d = data[plr]; if not d then return end
	local ls = plr:FindFirstChild("leaderstats"); if not ls then return end
	ls.Money.Value = math.floor(d.Money)
	plr:SetAttribute("Tokens", d.Tokens)
	plr:SetAttribute("Money", math.floor(d.Money))
	plr:SetAttribute("Rebirths", d.Rebirths)
	plr:SetAttribute("LuckRolls", d.LuckRolls)
	plr:SetAttribute("Income", 0) -- active breakables replaced passive income
	plr:SetAttribute("Collection", HttpService:JSONEncode(d.Collection))
	plr:SetAttribute("WheelSpins", d.WheelSpins or 0)
	plr:SetAttribute("InventoryCapacity", capOf(d))
	if _G.PlazaSyncEquipped then _G.PlazaSyncEquipped(plr, d) end
	if _G.PlazaSyncIndex then _G.PlazaSyncIndex(plr, d) end
	plr:SetAttribute("SpeedLevel", d.SpeedLevel or 0)
	plr:SetAttribute("PowerLevel", d.PowerLevel or 0)
	plr:SetAttribute("CoinLevel", d.CoinLevel or 0)
	plr:SetAttribute("MoneyBoostUntil", d.MoneyBoostUntil or 0)
	plr:SetAttribute("SpeedBoostUntil", d.SpeedBoostUntil or 0)
	plr:SetAttribute("InventoryCount",Inventory.Count(d.Collection))
	plr:SetAttribute("InventoryCapacity",capOf(d))
	plr:SetAttribute("InventoryOverflow",Inventory.Count(d.InventoryOverflow))
	plr:SetAttribute("FusionLevels", HttpService:JSONEncode(d.FusionLevels or {}))
	plr:SetAttribute("EggPity", HttpService:JSONEncode(d.EggPity or {}))
	plr:SetAttribute("QuestProgress", HttpService:JSONEncode(d.QuestProgress or {}))
	plr:SetAttribute("QuestCompleted", HttpService:JSONEncode(d.QuestCompleted or {}))
	plr:SetAttribute("ActiveQuest", d.ActiveQuest or "")
	local collectionBonus, collectionTitle, discoveredCount = Design.CollectionBonus(d.Discovered)
	plr:SetAttribute("CollectionBonus", collectionBonus)
	plr:SetAttribute("CollectionTitle", collectionTitle)
	plr:SetAttribute("DiscoveredCount", discoveredCount)
	ls.Power.Value = d.BestPower
	ls.Streak.Value = d.Streak or 0
	plr:SetAttribute("BestBrainrot", d.BestName)
	plr:SetAttribute("Bounty", (d.Streak or 0) >= CONFIG.CrownStreak and (CONFIG.BountyBase + CONFIG.BountyPerStreak * d.Streak) * 100 or 0)
end

-- Public hooks used by the active breakable economy.
_G.PlazaAwardMoney = function(plr, baseAmount)
	local d = data[plr]
	if not d then return false, 0 end
	local bonus = multiplier(d)
	local collectionBonus = Design.CollectionBonus(d.Discovered)
	bonus *= 1 + collectionBonus
	if (d.MoneyBoostUntil or 0) > os.time() then bonus *= 2 end
	bonus *= 1 + 0.1 * (d.CoinLevel or 0) -- Coin Bonus upgrade
	if _G.PlazaStormActive then bonus *= 2 end -- Brainrot Storm (WildCaptureAndStorms)
	bonus *= 1 + (plr:GetAttribute("FriendBoost") or 0) -- friends in your server (SocialAndRewardsServer)
	local amount = math.max(0, math.floor((tonumber(baseAmount) or 0) * bonus))
	d.Money += amount
	syncStats(plr)
	return true, amount
end
_G.PlazaGetAttackTeam = function(plr)
	local d = data[plr]
	return d and table.clone(d.Equipped or {}) or {}
end
_G.PlazaGetData = function(plr) return data[plr] end
_G.PlazaSyncPlayer = function(plr) if data[plr] then recompute(data[plr]); syncStats(plr) end end
_G.PlazaGetFusionLevel = function(plr, id)
	local d = data[plr]
	return d and (d.FusionLevels and d.FusionLevels[id] or 0) or 0
end
_G.PlazaFuse = function(plr, id)
	local d = data[plr]
	if not d or type(id) ~= "string" or not Catalog.ById[id] then return false, "Unknown brainrot" end
	d.FusionLevels = type(d.FusionLevels) == "table" and d.FusionLevels or {}
	local level = d.FusionLevels[id] or 0
	if level >= Design.MaxFusionLevel then return false, "Already max fusion" end
	if (d.Collection[id] or 0) < Design.FusionCopies then return false, ("Need %d copies"):format(Design.FusionCopies) end
	d.Collection[id] -= Design.FusionCopies - 1
	d.FusionLevels[id] = level + 1
	recompute(d); syncStats(plr)
	-- fusion milestones change how the brainrot looks (BrainrotLifeClient): level 5 = Shiny, level 10 = Rainbow
	local newLevel = level + 1
	if newLevel == 5 or newLevel == Design.MaxFusionLevel then
		local remotesFolder = RS:FindFirstChild("BrainrotRemotes")
		local notify = remotesFolder and remotesFolder:FindFirstChild("Notify")
		if notify then notify:FireClient(plr, (newLevel == 5 and "\u{2728} Your %s is now SHINY!" or "\u{1F308} Your %s is now RAINBOW!"):format(Catalog.ById[id].name)) end
	end
	local events = SS:FindFirstChild("ProgressionEvents")
	local progress = events and events:FindFirstChild("QuestProgress")
	if progress then progress:Fire(plr, "Fuse", Catalog.ById[id].variant, 1) end
	return true, d.FusionLevels[id]
end

local GiftProgress=require(RS:WaitForChild("GiftProgress"))

-- Session lock: one server at a time owns a player's save. When someone hops servers, the new server waits for
-- the old one to finish its last save before loading, and a server that has lost the lock never writes again.
-- That stops fast server hops from loading old progress or overwriting newer progress.
local SESSION_ID = game.JobId ~= "" and game.JobId or HttpService:GenerateGUID(false)
local LOCK_STALE = math.max(300, (Balance.SaveInterval or 60) * 4) -- nobody refreshed it this long: that server crashed
local LOCK_WAIT = RunService:IsStudio() and 5 or 20 -- wait this long for the old server, then take over
-- removed features (hats, coin collectors) + bookkeeping: never loaded into play data, cleared from saves
local REMOVED_KEYS = { "Hats", "EquippedHat", "Pending", "SessionLock", "CanSave" }
local isRemovedKey = {}
for _, k in ipairs(REMOVED_KEYS) do isRemovedKey[k] = true end
local function keyOf(plr) return "u" .. plr.UserId end
local function ownsLock(old) return type(old.SessionLock) == "table" and old.SessionLock.Id == SESSION_ID end

-- Returns the saved table (nil for a brand new player), or false if it couldn't be loaded.
local function loadData(plr)
	local started, failures = os.clock(), 0
	while plr.Parent do
		local result, locked = nil, false
		local ok, err = pcall(function()
			store:UpdateAsync(keyOf(plr), function(old)
				result, locked = nil, false
				old = type(old) == "table" and old or {}
				local lock = old.SessionLock
				if type(lock) == "table" and lock.Id ~= SESSION_ID and os.time() - (tonumber(lock.Time) or 0) < LOCK_STALE
					and os.clock() - started < LOCK_WAIT then
					locked = true
					return nil -- another server is still saving this player: don't write, try again in a moment
				end
				old.SessionLock = { Id = SESSION_ID, Time = os.time() }
				result = old
				return old
			end)
		end)
		if ok and not locked then return result end
		if not ok then
			failures += 1
			warn(("PiazzaLobbyServer: load failed for %s (try %d): %s"):format(plr.Name, failures, tostring(err)))
			if failures >= 5 then return false end
		end
		task.wait(locked and 2 or math.min(2 ^ failures, 8))
	end
	return false
end

local activeSaves = 0
local function save(plr, release)
	local d = data[plr]
	if not d or not store or not d.CanSave or d.Released then return false end
	if release then d.Released = true end
	local payload = {
		DataVersion = Balance.Version, LastSavedAt = os.time(),
		Tokens = d.Tokens, Money = d.Money, Rebirths = d.Rebirths, LuckRolls = d.LuckRolls,
		BestName = d.BestName, BestPower = d.BestPower, Kills = d.Kills,
		Equipped = d.Equipped, Discovered = d.Discovered, EggHatches = d.EggHatches,
		Islands = d.Islands, ExtraSlots = d.ExtraSlots,
		SpeedLevel = d.SpeedLevel, PowerLevel = d.PowerLevel, CoinLevel = d.CoinLevel,
		Collection = d.Collection, InventoryOverflow = d.InventoryOverflow,
		WheelSpins = d.WheelSpins,
		MoneyBoostUntil = d.MoneyBoostUntil, SpeedBoostUntil = d.SpeedBoostUntil,
		FusionLevels = d.FusionLevels, EggPity = d.EggPity,
		QuestProgress = d.QuestProgress, QuestCompleted = d.QuestCompleted, ActiveQuest = d.ActiveQuest,
		GiftPlaySeconds = GiftProgress.Elapsed(d, os.time()), GiftsClaimed = d.GiftsClaimed,
		Daily = d.Daily, Login = d.Login, Achievements = d.Achievements, AchStats = d.AchStats, TutorialDone = d.TutorialDone, TutorialGift = d.TutorialGift, -- DailyRewardsServer
	}
	activeSaves += 1
	local lost = false
	local ok, err = pcall(function()
		store:UpdateAsync(keyOf(plr), function(old)
			old = type(old) == "table" and old or {}
			lost = not ownsLock(old)
			if lost then return nil end -- another server owns this save now: never overwrite it
			for key, value in pairs(payload) do old[key] = value end
			for _, key in ipairs(REMOVED_KEYS) do old[key] = nil end
			if not release then old.SessionLock = { Id = SESSION_ID, Time = os.time() } end
			return old
		end)
	end)
	activeSaves -= 1
	if not ok then warn(("PiazzaLobbyServer: save failed for %s: %s"):format(plr.Name, tostring(err))) end
	if lost then
		d.CanSave = false
		warn(("PiazzaLobbyServer: %s's save is owned by another server now; this server stops saving it"):format(plr.Name))
	end
	if release and not ok then d.Released = false end -- the lock goes stale on its own if every retry fails
	if powerStore and d.BestPower > 0 then pcall(function() powerStore:SetAsync(tostring(plr.UserId), d.BestPower) end) end
	ok = ok and not lost
	if plr.Parent then plr:SetAttribute("LastSaveSucceeded", ok) end
	return ok
end
-- Let go of the lock without writing (player left while their data was still loading).
local function releaseLock(plr)
	pcall(function()
		store:UpdateAsync(keyOf(plr), function(old)
			if type(old) ~= "table" or not ownsLock(old) then return nil end
			old.SessionLock = nil
			return old
		end)
	end)
end

-- Safe zone -------------------------------------------------------------------
local function inSquare(pos)
	local h = CONFIG.SafeZoneHalfSize
	if math.abs(pos.X) < 250 and pos.Z < -230 and pos.Z > -3700 and pos.Y > -80 and pos.Y < 250 then return true end -- mutation islands are safe too
	if pos.X < -235 and pos.X > -725 and math.abs(pos.Z) < 245 and pos.Y > -80 and pos.Y < 250 then return true end -- treasure arena is safe (PvP arena is not)
	return math.abs(pos.X) < h and math.abs(pos.Z) < h and pos.Y < 250
end
local function isSafe(plr)
	return plr and plr:GetAttribute("InSafeZone") == true
end

local function creatorOf(hum)
	local tag = hum:FindFirstChild("creator")
	return tag and tag:IsA("ObjectValue") and tag.Value and tag.Value:IsA("Player") and tag.Value or nil
end

-- Crown -----------------------------------------------------------------------
local function removeCrown(char)
	if char then local c = char:FindFirstChild("BountyCrown"); if c then c:Destroy() end end
end
local function giveCrown(plr)
	local char = plr.Character; if not char then return end
	local head = char:FindFirstChild("Head"); if not head then return end
	removeCrown(char)
	local m = Instance.new("Model"); m.Name = "BountyCrown"
	local gold = Color3.fromRGB(255,200,40)
	local base = Instance.new("Part"); base.Name = "Band"; base.Shape = Enum.PartType.Cylinder
	base.Size = Vector3.new(0.6, 2.2, 2.2); base.Color = gold; base.Material = Enum.Material.Neon
	base.CanCollide = false; base.Massless = true
	base.CFrame = head.CFrame * CFrame.new(0, 1.2, 0) * CFrame.Angles(0, 0, math.rad(90)); base.Parent = m
	for i = 0, 4 do
		local a = i * math.pi * 2 / 5
		local sp = Instance.new("Part"); sp.Name = "Spike"; sp.Size = Vector3.new(0.35, 0.8, 0.35)
		sp.Color = gold; sp.Material = Enum.Material.Neon; sp.CanCollide = false; sp.Massless = true
		sp.CFrame = head.CFrame * CFrame.new(math.cos(a) * 0.9, 1.8, math.sin(a) * 0.9); sp.Parent = m
		local w = Instance.new("WeldConstraint"); w.Part0 = base; w.Part1 = sp; w.Parent = sp
	end
	local w = Instance.new("WeldConstraint"); w.Part0 = head; w.Part1 = base; w.Parent = base
	local bb = Instance.new("BillboardGui"); bb.Size = UDim2.fromOffset(180, 44); bb.StudsOffset = Vector3.new(0, 3.2, 0)
	bb.AlwaysOnTop = true; bb.MaxDistance = 250; bb.Parent = base
	local t = Instance.new("TextLabel"); t.Size = UDim2.fromScale(1, 1); t.BackgroundTransparency = 1; t.TextScaled = true
	t.Font = Enum.Font.FredokaOne; t.TextColor3 = gold; t.Name = "BountyText"
	local st = Instance.new("UIStroke"); st.Thickness = 2; st.Parent = t; t.Parent = bb
	t.Text = "👑 BOUNTY " .. (plr:GetAttribute("Bounty") or 0)
	m.Parent = char
end

-- Kills / streaks / bounty ----------------------------------------------------
local function awardKill(killer, victim)
	if not (killer and victim) or killer == victim then return end
	local kd, vd = data[killer], data[victim]
	if not kd or not vd then return end
	local bounty = victim:GetAttribute("Bounty") or 0
	vd.Streak = 0
	removeCrown(victim.Character)
	syncStats(victim)
	kd.Kills += 1
	kd.Streak = (kd.Streak or 0) + 1
	local reward = CONFIG.KillReward * 100 + bounty
	kd.Money += reward
	syncStats(killer)
	Notify:FireClient(killer, ("⚔ You beat %s! +%d coins%s"):format(victim.DisplayName, reward, bounty > 0 and (" (bounty " .. bounty .. ")") or ""))
	if kd.Streak >= CONFIG.CrownStreak then
		giveCrown(killer)
		if kd.Streak == CONFIG.CrownStreak then
			for _, p in ipairs(Players:GetPlayers()) do
				Notify:FireClient(p, ("👑 %s is on a %d streak! Bounty: %d coins"):format(killer.DisplayName, kd.Streak, killer:GetAttribute("Bounty")))
			end
		end
	end
end
AwardKillEvent.Event:Connect(awardKill)
GiveTokensEvent.Event:Connect(function(plr, n)
	local d = data[plr]; if d then d.Tokens += n; syncStats(plr) end
end)

local function hookCharacter(plr, char)
	local hum = char:WaitForChild("Humanoid", 10); if not hum then return end
	local playerData = data[plr]
	if playerData then hum.WalkSpeed = speedOf(playerData) end
	local last = hum.Health
	hum.HealthChanged:Connect(function(h)
		if h < last then
			local attacker = creatorOf(hum)
			if attacker and attacker ~= plr and (isSafe(plr) or isSafe(attacker)) then
				-- no fighting in (or from) the Piazza
				hum.Health = last
				local tag = hum:FindFirstChild("creator"); if tag then tag:Destroy() end
				return
			end
		end
		last = hum.Health
	end)
	hum.Died:Connect(function()
		local killer = creatorOf(hum)
		if killer and killer ~= plr then
			awardKill(killer, plr)
		else
			local d = data[plr]; if d then d.Streak = 0; syncStats(plr) end
		end
	end)
	local d = data[plr]
	if d and (d.Streak or 0) >= CONFIG.CrownStreak then task.delay(1, giveCrown, plr) end
end

-- Players ---------------------------------------------------------------------
local function onPlayer(plr)
	local d = newData()
	d.CanSave = false
	if store then
		local saved = loadData(plr)
		if not plr.Parent then -- left while loading
			if saved ~= false then releaseLock(plr) end
			return
		end
		if saved == false then
			if not RunService:IsStudio() then
				plr:Kick("Brainrot Plaza couldn't load your save right now. Your progress is safe, please rejoin in a minute!")
				return
			end
			warn("PiazzaLobbyServer: couldn't load " .. plr.Name .. "'s save in Studio; playing WITHOUT saving")
		else
			d.CanSave = true
			if type(saved) == "table" then
				for k, v in pairs(saved) do if not isRemovedKey[k] then d[k] = v end end
			end
		end
	end
	d.Collection,d.InventoryOverflow=Inventory.Normalize(type(d.Collection)=="table" and d.Collection or {},type(d.InventoryOverflow)=="table" and d.InventoryOverflow or {},capOf(d))
	d.Streak = 0
	d.JoinTime = os.time()
	GiftProgress.Restore(d,os.time())
	plr:SetAttribute("JoinTime", d.JoinTime)
	plr:SetAttribute("GiftsClaimed", HttpService:JSONEncode(d.GiftsClaimed))
	plr:SetAttribute("GiftPlaySeconds",d.GiftPlaySeconds)
	plr:SetAttribute("GiftSessionStarted",d.GiftSessionStarted)
	-- Hats, free tokens and free wheel spins were removed. These stay empty so older UI that reads them doesn't break.
	plr:SetAttribute("Hats", "{}")
	plr:SetAttribute("EquippedHat", "")
	plr:SetAttribute("NextFreeToken", -1)
	plr:SetAttribute("NextWheelSpin", -1)
	recompute(d)
	data[plr] = d
	local ls = Instance.new("Folder"); ls.Name = "leaderstats"
	local t = Instance.new("IntValue"); t.Name = "Money"; t.Parent = ls
	local p = Instance.new("IntValue"); p.Name = "Power"; p.Parent = ls
	local s = Instance.new("IntValue"); s.Name = "Streak"; s.Parent = ls
	ls.Parent = plr
	syncStats(plr)
	plr.CharacterAdded:Connect(function(c) hookCharacter(plr, c) end)
	if plr.Character then task.spawn(hookCharacter, plr, plr.Character) end
end
Players.PlayerAdded:Connect(onPlayer)
for _, p in ipairs(Players:GetPlayers()) do task.spawn(onPlayer, p) end
-- other parts of this script (the wheel) finish anything owed to the player here, before the last save
local beforeLeave = {}
Players.PlayerRemoving:Connect(function(plr)
	for _, fn in ipairs(beforeLeave) do pcall(fn, plr) end
	save(plr, true)
	data[plr] = nil
end)
game:BindToClose(function()
	for _, p in ipairs(Players:GetPlayers()) do
		task.spawn(function()
			for _, fn in ipairs(beforeLeave) do pcall(fn, p) end
			save(p, true)
		end)
	end
	-- wait for every save (these and the ones PlayerRemoving started) before the server shuts down
	local started = os.clock()
	task.wait(0.1)
	while activeSaves > 0 and os.clock() - started < 25 do task.wait(0.2) end
end)

task.spawn(function()
	while task.wait(1) do
		for plr, d in pairs(data) do
			local hum = plr.Character and plr.Character:FindFirstChildOfClass("Humanoid")
			if hum and hum.WalkSpeed ~= speedOf(d) then hum.WalkSpeed = speedOf(d) end
			plr:SetAttribute("MoneyBoostUntil", d.MoneyBoostUntil or 0)
			plr:SetAttribute("SpeedBoostUntil", d.SpeedBoostUntil or 0)
		end
	end
end)
task.spawn(function() while true do task.wait(Balance.SaveInterval); for _, p in ipairs(Players:GetPlayers()) do save(p) end end end)

-- Safe zone tick -----------------------------------------------------------------
task.spawn(function()
	while true do
		task.wait(0.25)
		for _, plr in ipairs(Players:GetPlayers()) do
			local char = plr.Character
			local hrp = char and char:FindFirstChild("HumanoidRootPart")
			local safe = hrp ~= nil and inSquare(hrp.Position)
			if plr:GetAttribute("InSafeZone") ~= safe then
				plr:SetAttribute("InSafeZone", safe)
				if char then char:SetAttribute("InSafeZone", safe) end
			end
			if char then
				local ff = char:FindFirstChild("SafeZoneShield")
				if safe and not ff then
					ff = Instance.new("ForceField"); ff.Name = "SafeZoneShield"; ff.Visible = false; ff.Parent = char
				elseif not safe and ff then ff:Destroy() end
			end
		end
	end
end)

-- Reactor effects ---------------------------------------------------------------
local core = reactor.Core
local coreLight = core:FindFirstChild("CoreLight")
local baseGlow = reactor.BaseGlow
local tip = reactor.Tip
local eruption = reactor.EruptionPoint.Eruption
local anchor = reactor.HologramAnchor
local CORE_COLOR = core.Color

local lanterns = {}
for _, d in ipairs(piazza.StreetLife:GetDescendants()) do
	if d:IsA("BasePart") and d.Name == "Lantern" then table.insert(lanterns, d) end
end
local LANTERN_COLOR = lanterns[1] and lanterns[1].Color or Color3.new(1,1,1)

local function pulse(color, t)
	core.Color = color; baseGlow.Color = color; if coreLight then coreLight.Color = color end
	task.delay(t or 0.6, function()
		core.Color = CORE_COLOR; baseGlow.Color = CORE_COLOR; if coreLight then coreLight.Color = CORE_COLOR end
	end)
end

local function makeHologram(brainrotName, color)
	local tpl = modelById[brainrotName] or templates:FindFirstChild(brainrotName); if not tpl then return nil end
	local m = tpl:Clone()
	for _, d in ipairs(m:GetDescendants()) do
		if d:IsA("BasePart") then
			d.Anchored = true; d.CanCollide = false; d.CanTouch = false; d.CanQuery = false; d.CastShadow = false
			d.Material = Enum.Material.Neon; d.Transparency = 0.3
			d.Color = d.Color:Lerp(color, 0.35)
		elseif d:IsA("LuaSourceContainer") or d:IsA("SurfaceGui") or d:IsA("BillboardGui") then
			d:Destroy()
		end
	end
	local cf, size = m:GetBoundingBox()
	m.WorldPivot = cf
	m:ScaleTo(m:GetScale() * CONFIG.HologramHeight / math.max(size.Y, 1))
	return m
end

local queue, busy = {}, false
local function runEruption(ev)
	-- ev = {player=, name=, rarity=, color=}
	BigPull:FireAllClients(ev.playerName, ev.name, ev.rarity, ev.color)
	eruption:Emit(ev.rarity == "Mythic" and 500 or 250)
	pulse(ev.color, 2.5)
	tip.Color = ev.color
	-- lamps flash across the whole square
	task.spawn(function()
		local cols = { ev.color, Color3.new(1,1,1), Color3.fromRGB(0,255,210), ev.color }
		for i = 1, 14 do
			for _, l in ipairs(lanterns) do
				l.Color = cols[(i % #cols) + 1]
				local pl = l:FindFirstChildOfClass("PointLight"); if pl then pl.Color = l.Color; pl.Brightness = (i % 2 == 0) and 5 or 1 end
			end
			task.wait(0.18)
		end
		for _, l in ipairs(lanterns) do
			l.Color = LANTERN_COLOR
			local pl = l:FindFirstChildOfClass("PointLight"); if pl then pl.Color = Color3.fromRGB(255,200,130); pl.Brightness = 1.5 end
		end
	end)
	-- giant hologram
	local holo = makeHologram(ev.base or ev.name, ev.color)
	if holo then
		local base = anchor.CFrame
		holo:PivotTo(base * CFrame.new(0, -30, 0))
		holo.Parent = workspace
		local start = os.clock()
		while os.clock() - start < CONFIG.HologramSeconds do
			local e = os.clock() - start
			local rise = math.min(e / 1.2, 1)
			holo:PivotTo(base * CFrame.new(0, -30 * (1 - rise) + math.sin(e * 2) * 2, 0) * CFrame.Angles(0, e * 0.8, 0))
			task.wait()
		end
		holo:Destroy()
	else
		task.wait(3)
	end
	tip.Color = Color3.fromRGB(255,60,200)
end

local function enqueueEruption(ev)
	table.insert(queue, ev)
	if busy then return end
	busy = true
	task.spawn(function()
		while #queue > 0 do
			local nextEv = table.remove(queue, 1)
			local ok, err = pcall(runEruption, nextEv)
			if not ok then warn("Eruption error:", err) end
			task.wait(0.5)
		end
		busy = false
	end)
end

-- Rolling -------------------------------------------------------------------------
local rng = Random.new()
local lastRoll = {}
local function doRoll(plr, forceRarity, forceVariant, costOverride)
	local d = data[plr]; if not d then return end
	local now = os.clock()
	if lastRoll[plr] and now - lastRoll[plr] < CONFIG.RollCooldown then return end
	if Inventory.Count(d.Collection)>=capOf(d) then
		Notify:FireClient(plr,("Inventory full (%d/%d). Sell a brainrot or buy more slots in the Shop."):format(Inventory.Count(d.Collection), capOf(d)))
		return
	end
	local cost = costOverride or CONFIG.RollCost
	if d.Tokens < cost then
		Notify:FireClient(plr, "🪙 You're out of tokens!")
		return
	end
	lastRoll[plr] = now
	d.Tokens -= cost
	local lucky = (d.LuckRolls or 0) > 0
	if lucky then d.LuckRolls -= 1 end
	local entry,variant
	if forceVariant and not forceRarity and RollPool[forceVariant] then
		-- mutation egg: pick a rarity by weight from what this mutation has
		local bins = RollPool[forceVariant]; local total, w = 0, {}
		for i, r in ipairs(RollConfig.RarityOrder) do
			local x = (bins[r] and #bins[r] > 0) and (RollConfig.RarityWeights[r] or 0) or 0
			if lucky and i >= 3 and r ~= "Unrated" then x *= 2 end
			w[r] = x; total += x
		end
		local t = rng:NextNumber() * total
		for _, r in ipairs(RollConfig.RarityOrder) do if w[r] > 0 then t -= w[r]; if t <= 0 then forceRarity = r; break end end end
	end
	local forcedList = forceVariant and forceRarity and RollPool[forceVariant] and RollPool[forceVariant][forceRarity]
	if forcedList and #forcedList > 0 then
		entry = forcedList[rng:NextInteger(1, #forcedList)]
		for _, vv in ipairs(RollConfig.Variants) do if vv.name == forceVariant then variant = vv end end
	else
		entry,variant=RollConfig.Pick(RollPool,rng,lucky,forceRarity)
	end
	local r=rarityByName[entry.rarity]
	local name,power=entry.id,entry.power
	local isNew = (d.Collection[name] or 0) == 0
	assert(Inventory.Add(d.Collection,name,capOf(d)),"Inventory limit exceeded")
	if _G.PlazaOnHatch then _G.PlazaOnHatch(plr, d, name, forceRarity or entry.rarity) end
	recompute(d)
	syncStats(plr)
	RollReveal:FireClient(plr, name, r.name, variant.color, power, isNew, forceVariant or variant.name)
	pulse(r.color, 0.8)
	if CONFIG.EruptRarities[r.name] then
		task.delay(CONFIG.RevealDelay, enqueueEruption, { playerName = plr.DisplayName, name = name, rarity = r.name, color = r.color })
	end
end
for _, console in ipairs(taggedInWorld("RollConsole")) do
	local prompt = console:FindFirstChild("RollPrompt", true)
	if prompt then prompt.Triggered:Connect(function(plr) doRoll(plr) end) end
end
-- Studio testing helper: ServerStorage.BrainrotEvents.TestRoll:Fire(player, "Mythic")
local TestRoll = events:FindFirstChild("TestRoll") or Instance.new("BindableEvent")
TestRoll.Name = "TestRoll"; TestRoll.Parent = events
TestRoll.Event:Connect(function(plr, rarity, variant) if data[plr] then data[plr].Tokens += 1; lastRoll[plr] = nil; doRoll(plr, rarity, variant) end end)

-- Brainrot identity is shown only in inventory hover details.

-- Training dummies -----------------------------------------------------------------
for _, dummy in ipairs(taggedInWorld("TrainingDummy")) do
	local label = dummy:FindFirstChild("Label", true)
	local text = label and label:FindFirstChild("Text")
	local pivot = dummy:GetPivot()
	local combos, lastHit = {}, {}
	local wobbleT = 0
	local function hit(plr)
		local now = os.clock()
		if lastHit[plr] and now - lastHit[plr] < 0.12 then return end
		combos[plr] = (lastHit[plr] and now - lastHit[plr] < 1.5) and (combos[plr] + 1) or 1
		lastHit[plr] = now
		local dmg = rng:NextInteger(8, 25) + math.floor(combos[plr] / 5) * 5
		if text then text.Text = ("🥊 %s  x%d COMBO"):format(plr.DisplayName, combos[plr]) end
		-- floating damage number
		local head = dummy:FindFirstChild("Head")
		if head then
			local bb = Instance.new("BillboardGui"); bb.Size = UDim2.fromOffset(80, 40); bb.StudsOffset = Vector3.new(rng:NextNumber(-2, 2), 1, 0); bb.MaxDistance = 60
			local t = Instance.new("TextLabel"); t.Size = UDim2.fromScale(1,1); t.BackgroundTransparency = 1; t.TextScaled = true; t.Font = Enum.Font.FredokaOne
			t.Text = "-" .. dmg; t.TextColor3 = combos[plr] >= 10 and Color3.fromRGB(255,200,40) or Color3.fromRGB(255,80,80)
			local s = Instance.new("UIStroke"); s.Thickness = 2; s.Parent = t; t.Parent = bb; bb.Parent = head
			TweenService:Create(bb, TweenInfo.new(0.8), { StudsOffset = bb.StudsOffset + Vector3.new(0, 4, 0) }):Play()
			TweenService:Create(t, TweenInfo.new(0.8), { TextTransparency = 1 }):Play()
			task.delay(0.85, function() bb:Destroy() end)
		end
		wobbleT = now
	end
	for _, cd in ipairs(dummy:GetDescendants()) do
		if cd:IsA("ClickDetector") then cd.MouseClick:Connect(hit) end
	end
	task.spawn(function()
		while dummy.Parent do
			local e = os.clock() - wobbleT
			if e < 0.6 then
				dummy:PivotTo(pivot * CFrame.Angles(math.sin(e * 30) * math.rad(12) * (1 - e / 0.6), 0, 0))
				task.wait()
			else
				dummy:PivotTo(pivot)
				if text and e > 4 then text.Text = "🥊 TAP TO TRAIN" end
				task.wait(0.2)
			end
		end
	end)
end

-- Kick balls go home if they leave the square -------------------------------------
task.spawn(function()
	while true do
		task.wait(3)
		for _, b in ipairs(taggedInWorld("KickBall")) do
			local home = b:GetAttribute("Home")
			if home and (not inSquare(b.Position) or b.Position.Y < -10 or b.Position.Y > 200) then
				b.AssemblyLinearVelocity = Vector3.zero; b.AssemblyAngularVelocity = Vector3.zero
				b.CFrame = CFrame.new(home)
			end
		end
	end
end)

-- Boards ------------------------------------------------------------------------
local function makeBoardGui(boardModel)
	local part = boardModel:FindFirstChild("Board")
	-- one face of the board: a title and 8 rows. `framed` = the back of the coloured frame, which gets a dark panel
	-- with a border in the frame's colour (it used to be a bare neon slab, the first thing you saw coming back from Gold Island)
	local function build(host, face, framed)
		local sg = Instance.new("SurfaceGui"); sg.Face = face; sg.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud; sg.PixelsPerStud = 25; sg.LightInfluence = 0; sg.Parent = host
		local root = sg
		if framed then
			local border = Instance.new("Frame"); border.Size = UDim2.fromScale(1, 1); border.BackgroundColor3 = host.Color; border.BorderSizePixel = 0; border.Parent = sg
			local panel = Instance.new("Frame"); panel.AnchorPoint = Vector2.new(0.5, 0.5); panel.Position = UDim2.fromScale(0.5, 0.5); panel.Size = UDim2.new(1, -50, 1, -50)
			panel.BackgroundColor3 = Color3.fromRGB(18, 16, 32); panel.BorderSizePixel = 0; panel.Parent = border
			Instance.new("UICorner", panel).CornerRadius = UDim.new(0, 18)
			root = panel
		end
		local title = Instance.new("TextLabel"); title.Size = UDim2.new(1, 0, 0.18, 0); title.BackgroundTransparency = 1; title.TextScaled = true
		title.Font = Enum.Font.FredokaOne; title.TextColor3 = Color3.fromRGB(255,220,120); title.Text = part:GetAttribute("Title") or ""; title.Parent = root
		local rows = {}
		for i = 1, 8 do
			local r = Instance.new("TextLabel"); r.Size = UDim2.new(0.94, 0, 0.09, 0); r.Position = UDim2.new(0.03, 0, 0.19 + (i - 1) * 0.1, 0)
			r.BackgroundTransparency = 1; r.TextScaled = true; r.Font = Enum.Font.GothamBold; r.TextXAlignment = Enum.TextXAlignment.Left
			r.TextColor3 = Color3.new(1,1,1); r.Text = ""; r.Parent = root
			rows[i] = r
		end
		return rows, title
	end
	local frontRows, frontTitle = build(part, Enum.NormalId.Front)
	local frame = boardModel:FindFirstChild("Frame")
	if not frame then return frontRows, frontTitle end
	local backRows, backTitle = build(frame, Enum.NormalId.Back, true)
	-- writes go to both faces, so the code below can keep treating each row as a single TextLabel
	local function both(a, b)
		return setmetatable({}, { __index = function(_, k) return a[k] end, __newindex = function(_, k, v) a[k] = v; b[k] = v end })
	end
	local rows = {}
	for i = 1, 8 do rows[i] = both(frontRows[i], backRows[i]) end
	return rows, both(frontTitle, backTitle)
end
local strongestRows = makeBoardGui(showcase.StrongestBrainrotBoard)
local wantedRows = makeBoardGui(showcase.MostWantedBoard)
local nameCache = {}
local globalTop = nil
local function nameOf(uid)
	if nameCache[uid] then return nameCache[uid] end
	local ok, n = pcall(function() return Players:GetNameFromUserIdAsync(uid) end)
	nameCache[uid] = ok and n or ("Player " .. uid)
	return nameCache[uid]
end
task.spawn(function()
	while true do
		if powerStore then
			local ok, pages = pcall(function() return powerStore:GetSortedAsync(false, 8) end)
			if ok and pages then
				local list = {}
				for _, e in ipairs(pages:GetCurrentPage()) do table.insert(list, { name = nameOf(tonumber(e.key)), power = e.value }) end
				globalTop = list
			end
		end
		task.wait(60)
	end
end)

local function tournamentText()
	local now = os.time()
	local t = os.date("!*t", now)
	-- start of this week's tournament day
	local daysUntil = (CONFIG.TournamentWday - t.wday) % 7
	local startToday = now - (t.hour * 3600 + t.min * 60 + t.sec) + CONFIG.TournamentHourUTC * 3600
	local start = startToday + daysUntil * 86400
	local prevStart = start - 7 * 86400
	if now >= prevStart and now < prevStart + CONFIG.TournamentHours * 3600 then return "🏆 WEEKEND TOURNAMENT IS LIVE!", true end
	if now >= start and now < start + CONFIG.TournamentHours * 3600 then return "🏆 WEEKEND TOURNAMENT IS LIVE!", true end
	if now >= start + CONFIG.TournamentHours * 3600 then start += 7 * 86400 end
	local left = start - now
	local d, h, m, s = math.floor(left / 86400), math.floor(left % 86400 / 3600), math.floor(left % 3600 / 60), left % 60
	return ("🏆 WEEKEND TOURNAMENT IN %dd %02dh %02dm %02ds"):format(d, h, m, s), false
end
local tScreen = showcase:FindFirstChild("TournamentScreen")
local tLabel
if tScreen then
	local sg = Instance.new("SurfaceGui"); sg.Face = Enum.NormalId.Front; sg.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud; sg.PixelsPerStud = 20; sg.LightInfluence = 0; sg.Parent = tScreen
	tLabel = Instance.new("TextLabel"); tLabel.Size = UDim2.fromScale(1, 1); tLabel.BackgroundTransparency = 1; tLabel.TextScaled = true
	tLabel.Font = Enum.Font.FredokaOne; tLabel.TextColor3 = Color3.fromRGB(255,220,120); tLabel.Parent = sg
end

task.spawn(function()
	while true do
		-- Strongest Brainrots: global top if the DataStore works, otherwise this server
		local rows = {}
		if globalTop and #globalTop > 0 then
			for _, e in ipairs(globalTop) do table.insert(rows, ("%s — %d power"):format(e.name, e.power)) end
		else
			local list = {}
			for p, d in pairs(data) do if d.BestPower > 0 then table.insert(list, { p = p, d = d }) end end
			table.sort(list, function(a, b) return a.d.BestPower > b.d.BestPower end)
			for _, e in ipairs(list) do
				table.insert(rows, ("%s — %s (%d)"):format(e.p.DisplayName, displayName(e.d.BestName), e.d.BestPower))
			end
		end
		for i = 1, 8 do
			strongestRows[i].Text = rows[i] and (i .. ". " .. rows[i]) or (i == 1 and "Hatch eggs to get on the board!" or "")
		end
		-- Most Wanted: current streaks
		local w = {}
		for p, d in pairs(data) do if (d.Streak or 0) > 0 then table.insert(w, { p = p, d = d }) end end
		table.sort(w, function(a, b) return a.d.Streak > b.d.Streak end)
		for i = 1, 8 do
			local e = w[i]
			if e then
				local crown = e.d.Streak >= CONFIG.CrownStreak
				wantedRows[i].Text = ("%s%s — %d streak%s"):format(crown and "👑 " or "", e.p.DisplayName, e.d.Streak, crown and (" · bounty " .. (e.p:GetAttribute("Bounty") or 0)) or "")
				wantedRows[i].TextColor3 = crown and Color3.fromRGB(255,200,40) or Color3.new(1,1,1)
			else
				wantedRows[i].Text = (i == 1 and #w == 0) and ("Win " .. CONFIG.CrownStreak .. " fights in a row to wear the 👑") or ""
				wantedRows[i].TextColor3 = Color3.new(1,1,1)
			end
		end
		if tLabel then local txt = tournamentText(); tLabel.Text = txt end
		-- keep crown bounty text fresh
		for _, p in ipairs(Players:GetPlayers()) do
			local c = p.Character and p.Character:FindFirstChild("BountyCrown")
			local t = c and c:FindFirstChild("BountyText", true)
			if t then t.Text = "👑 BOUNTY " .. (p:GetAttribute("Bounty") or 0) end
		end
		task.wait(1)
	end
end)

-- ================= MENUS: Store, Gifts, Rebirth, Inventory (sell) =================
local function addTime(d, field, secs) d[field] = math.max(os.time(), d[field] or 0) + secs end
-- levelled items get pricier each level: price * growth ^ level
local function priceOf(it, d) return it.growth and math.floor(it.price * it.growth ^ (d[it.level] or 0)) or it.price end
local STORE = {
	{ id = "lucky5", name = "🧪 Luck Potion (2x luck, 5 hatches)", price = 1500, give = function(d) d.LuckRolls = (d.LuckRolls or 0) + 5 end },
	{ id = "lucky20", name = "🧪 Mega Luck Potion (2x luck, 20 hatches)", price = 5000, give = function(d) d.LuckRolls = (d.LuckRolls or 0) + 20 end },
	{ id = "boots", name = "👟 Speed Boots (+3 speed, max 5)", price = 750, can = function(d) return (d.SpeedLevel or 0) < 5 end, give = function(d) d.SpeedLevel = (d.SpeedLevel or 0) + 1 end },
	{ id = "slots5", name = "🎒 +5 Inventory Slots (max +50)", price = 1000, can = function(d) return (d.ExtraSlots or 0) < 50 end, give = function(d) d.ExtraSlots = (d.ExtraSlots or 0) + 5 end },
	-- market stall additions
	{ id = "coinpotion", name = "🪙 Coin Potion (2x coins, 3 min)", price = 2500, give = function(d) addTime(d, "MoneyBoostUntil", 180) end },
	{ id = "speedpotion", name = "💨 Speed Potion (2x speed, 3 min)", price = 1200, speed = true, give = function(d) addTime(d, "SpeedBoostUntil", 180) end },
	{ id = "megaboost", name = "⚡ Mega Boost (2x coins + 2x speed, 10 min)", price = 20000, speed = true, give = function(d) addTime(d, "MoneyBoostUntil", 600); addTime(d, "SpeedBoostUntil", 600) end },
	{ id = "power", name = "💪 Brainrot Power (+10% damage)", price = 2500, growth = 2.2, level = "PowerLevel", max = 10, can = function(d) return (d.PowerLevel or 0) < 10 end, give = function(d) d.PowerLevel = (d.PowerLevel or 0) + 1 end },
	{ id = "coinbonus", name = "🪙 Coin Bonus (+10% coins)", price = 4000, growth = 2.2, level = "CoinLevel", max = 10, can = function(d) return (d.CoinLevel or 0) < 10 end, give = function(d) d.CoinLevel = (d.CoinLevel or 0) + 1 end },
}
-- Set these to the Developer Product IDs created for this experience before publishing.
local BOOST_PRODUCTS = {
	{ id = "boost30", name = "2x Money + 2x Speed", duration = 30 * 60, robux = 60, productId = 0 },
	{ id = "boost60", name = "2x Money + 2x Speed", duration = 60 * 60, robux = 80, productId = 0 },
}
local GIFTS = { -- seconds played this session -> reward
	{ at = GiftProgress.Times[1], text = "+1 Wheel Spin",  give = function(d) d.WheelSpins = (d.WheelSpins or 0) + 1 end },
	{ at = GiftProgress.Times[2], text = "+300 Money",     give = function(d) d.Money += 300 end },
	{ at = GiftProgress.Times[3], text = "+2 Wheel Spins", give = function(d) d.WheelSpins = (d.WheelSpins or 0) + 2 end },
	{ at = GiftProgress.Times[4], text = "Lucky x3 rolls", give = function(d) d.LuckRolls = (d.LuckRolls or 0) + 3 end },
	{ at = GiftProgress.Times[5], text = "+1500 Money",    give = function(d) d.Money += 1500 end },
	{ at = GiftProgress.Times[6], text = "+5 Wheel Spins", give = function(d) d.WheelSpins = (d.WheelSpins or 0) + 5 end },
}
local function rebirthCost(d)
 local rebirths=d.Rebirths or 0
 -- Starts at 75k, then grows 1.85x and rounds to a readable 2.5k step.
 local raw=75000*(1.85^rebirths)
 return math.floor((raw+1250)/2500)*2500
end

local catalog = {}
for i, it in ipairs(STORE) do catalog[i] = { id = it.id, name = it.name, price = it.price, growth = it.growth, level = it.level, max = it.max } end
local giftList = {}
for i, g in ipairs(GIFTS) do giftList[i] = { at = g.at, text = g.text } end
local catalogValue = remotes:FindFirstChild("Catalog") or Instance.new("StringValue")
catalogValue.Name = "Catalog"; catalogValue.Value = HttpService:JSONEncode({ store = catalog, gifts = giftList, boosts = BOOST_PRODUCTS }); catalogValue.Parent = remotes

local MenuAction = remotes:FindFirstChild("MenuAction") or Instance.new("RemoteFunction")
MenuAction.Name = "MenuAction"; MenuAction.Parent = remotes

local function applyTimedBoost(plr, seconds)
	local d = data[plr]; if not d then return false end
	local now = os.time()
	d.MoneyBoostUntil = math.max(now, d.MoneyBoostUntil or 0) + seconds
	d.SpeedBoostUntil = math.max(now, d.SpeedBoostUntil or 0) + seconds
	local hum = plr.Character and plr.Character:FindFirstChildOfClass("Humanoid")
	if hum then hum.WalkSpeed = speedOf(d) end
	syncStats(plr); save(plr)
	Notify:FireClient(plr, ("⚡ 2x Money + 2x Speed active for %d minutes!"):format(seconds / 60))
	return true
end
MarketplaceService.ProcessReceipt = function(receipt)
	local chosen
	for _, product in ipairs(BOOST_PRODUCTS) do
		if product.productId > 0 and product.productId == receipt.ProductId then chosen = product; break end
	end
	if not chosen then return Enum.ProductPurchaseDecision.NotProcessedYet end
	local plr = Players:GetPlayerByUserId(receipt.PlayerId)
	if not plr or not applyTimedBoost(plr, chosen.duration) then return Enum.ProductPurchaseDecision.NotProcessedYet end
	return Enum.ProductPurchaseDecision.PurchaseGranted
end

local menuHandler
menuHandler = function(plr, action, arg)
	local d = data[plr]; if not d then return false, "Loading..." end
	if action == "buy" then
		for _, it in ipairs(STORE) do
			if it.id == arg then
				if it.can and not it.can(d) then return false, "Already maxed out!" end
				local price = priceOf(it, d)
				if d.Money < price then return false, "Not enough coins!" end
				d.Money -= price; it.give(d)
				if it.id == "slots5" then Inventory.Restore(d.Collection, d.InventoryOverflow or {}, capOf(d)) end
				if it.id == "boots" or it.speed then local h = plr.Character and plr.Character:FindFirstChildOfClass("Humanoid"); if h then h.WalkSpeed = speedOf(d) end end
				syncStats(plr)
				return true, "Bought " .. it.name .. "!"
			end
		end
	elseif action == "gift" then
		local idx = tonumber(arg) or 0
		local g = GIFTS[idx]; if not g then return false, "?" end
		local key = tostring(idx)
		if d.GiftsClaimed[key] then return false, "Already claimed" end
		if GiftProgress.Elapsed(d,os.time()) < g.at then return false, "Not ready yet" end
		d.GiftsClaimed[key] = true; g.give(d); syncStats(plr)
		plr:SetAttribute("GiftsClaimed", HttpService:JSONEncode(d.GiftsClaimed))
        save(plr)
		return true, "🎁 " .. g.text
	elseif action == "rebirth" then
		local cost = rebirthCost(d)
		if d.Money < cost then return false, ("Need %d money to rebirth"):format(cost) end
		d.Money = 0; d.Collection = {}; d.InventoryOverflow={}; d.Rebirths += 1
		recompute(d); syncStats(plr)
		for _, p in ipairs(Players:GetPlayers()) do Notify:FireClient(p, ("🔁 %s rebirthed! (x%.1f boost)"):format(plr.DisplayName, multiplier(d))) end
		return true, ("Rebirth %d! Money & power now x%.1f"):format(d.Rebirths, multiplier(d))
	elseif action == "sell" then
		if type(arg) ~= "string" then return false, "?" end
		local n = d.Collection[arg]
		if not n or n <= 0 then return false, "You don't have that" end
		local value = math.floor((powerOf[arg] or 0) * 5 * multiplier(d))
		Inventory.Remove(d.Collection,arg,d.InventoryOverflow,capOf(d))
		d.Money += value; recompute(d); syncStats(plr)
		return true, ("Sold one brainrot for %d"):format(value)
	elseif action == "sellMany" then
		-- arg = { [brainrotId] = count }. Copies you have equipped are always kept.
		if type(arg) ~= "table" then return false, "?" end
		local keep = {}
		for _, id in ipairs(d.Equipped or {}) do keep[id] = (keep[id] or 0) + 1 end
		local total, sold, seen = 0, 0, 0
		for id, want in pairs(arg) do
			seen += 1; if seen > 400 then break end
			if type(id) == "string" and type(want) == "number" and want == want then
				local n = math.clamp(math.floor(want), 0, math.max(0, (d.Collection[id] or 0) - (keep[id] or 0)))
				for _ = 1, n do
					Inventory.Remove(d.Collection, id, d.InventoryOverflow, capOf(d))
					total += math.floor((powerOf[id] or 0) * 5 * multiplier(d)); sold += 1
				end
			end
		end
		if sold == 0 then return false, "Nothing to sell" end
		d.Money += total; recompute(d); syncStats(plr)
		return true, { sold = sold, coins = total }
	elseif action == "rebirthInfo" then
		return true, { cost = rebirthCost(d), rebirths = d.Rebirths, mult = multiplier(d), nextMult = 1 + 0.5 * (d.Rebirths + 1) }
	end
	return false, "Unknown action"
end

-- ================= VARIANT INFO for clients =================
do
	local list = {}
	for _, v in ipairs(RollConfig.Variants) do table.insert(list, { name = v.name, chance = v.weight/100, color = v.color:ToHex() }) end
	variantInfo.Value = HttpService:JSONEncode({ variants = list, hats = {} }) -- hats were removed; empty so older UI doesn't break
end

-- ================= COIN WHEEL =================
local wheel = piazza:FindFirstChild("CoinWheel")
local WHEEL = Balance.Wheel -- clockwise from the pointer; must match the seven physical labels
local WHEEL_WINDUP_TIME = Balance.WheelTiming.Windup
local WHEEL_SPIN_TIME = Balance.WheelTiming.Spin
local WheelSpin = remotes:FindFirstChild("WheelSpin") or Instance.new("RemoteEvent")
WheelSpin.Name = "WheelSpin"; WheelSpin.Parent = remotes
local wheelBusy = false
local wheelAngle = 0
local wheelCF = wheel and wheel:GetAttribute("WheelCF")
local wheelSpinner = wheel and wheel:FindFirstChild("Spinner")
local wheelParts, wheelRels = {}, {}
if wheelCF and wheelSpinner then
	for _, part in ipairs(wheelSpinner:GetDescendants()) do
		if part:IsA("BasePart") then
			table.insert(wheelParts, part)
			table.insert(wheelRels, wheelCF:ToObjectSpace(part.CFrame))
		end
	end
end
local function placeWheel(a)
	if not wheelCF then return end
	local base = wheelCF * CFrame.Angles(0, 0, math.rad(a))
	for i, part in ipairs(wheelParts) do
		part.CFrame = base * wheelRels[i]
	end
end
local function animateWheel(idx)
	if #wheelParts == 0 then return end
	task.wait(1.21) -- brainrot reaches and strikes the wheel
	local segments = #WHEEL
	local target = (idx - 0.5) * 360 / segments
	local current = wheelAngle % 360
	local delta = (target - current) % 360
	local from, to = wheelAngle, wheelAngle + 360 * 9 + delta
	local recoilStart = os.clock()
	while true do
		local e = math.min((os.clock() - recoilStart) / 0.2, 1)
		placeWheel(from - math.sin(e * math.pi) * 12)
		if e >= 1 then break end
		RunService.Heartbeat:Wait()
	end
	local started = os.clock()
	while true do
		local e = math.min((os.clock() - started) / WHEEL_SPIN_TIME, 1)
		local k
		if e < 0.14 then
			local q = e / 0.14
			k = 0.1 * q * q * q
		elseif e < 0.58 then
			k = 0.1 + ((e - 0.14) / 0.44) * 0.62
		else
			local q = (e - 0.58) / 0.42
			k = 0.72 + 0.28 * (1 - (1 - q) ^ 4)
		end
		wheelAngle = from + (to - from) * k
		placeWheel(wheelAngle)
		if e >= 1 then break end
		RunService.Heartbeat:Wait()
	end
	wheelAngle = to
	placeWheel(wheelAngle)
end
if wheel then
	local prompt = wheel:FindFirstChild("SpinPrompt", true)
	local clickPart = wheel:FindFirstChild("Button", true) or wheel:FindFirstChild("SpinButton", true)
	local click = clickPart and (clickPart:FindFirstChildOfClass("ClickDetector") or Instance.new("ClickDetector"))
	if click then click.MaxActivationDistance = 24; click.Parent = clickPart end
	local wTotal = 0; for _, s in ipairs(WHEEL) do wTotal += s.w end

	-- the prize of the spin that is still animating; paid when the wheel stops, or right away if the player leaves first
	local pendingPrize = {}
	local function payPrize(plr, spin, present)
		if pendingPrize[plr] ~= spin then return end
		pendingPrize[plr] = nil
		local d, s = spin.d, spin.s
		if s.coins then d.Money += s.coins end
		if s.spins then d.WheelSpins = (d.WheelSpins or 0) + s.spins end
		if not present then
			if s.egg then d.Money += 1000 end -- can't hatch for someone who left: the egg becomes coins
			return
		end
		syncStats(plr)
		Notify:FireClient(plr, "🎡 You won " .. s.label .. "!")
		if s.egg then
			if Inventory.Count(d.Collection) >= capOf(d) then
				d.Money += 1000; syncStats(plr)
				Notify:FireClient(plr, "🎒 Inventory full, so your free egg became 1,000 coins.")
			else
				lastRoll[plr] = nil
				doRoll(plr, nil, s.egg, 0)
			end
		end
		if s.egg or (s.coins or 0) >= 1000 then
			for _, p in ipairs(Players:GetPlayers()) do if p ~= plr then Notify:FireClient(p, ("🎡 %s won %s on the wheel!"):format(plr.DisplayName, s.label)) end end
		end
	end
	table.insert(beforeLeave, function(plr) local spin = pendingPrize[plr]; if spin then payPrize(plr, spin, false) end end)

	local function spinWheel(plr)
		local d = data[plr]; if not d then return end
		if wheelBusy then Notify:FireClient(plr, "🎡 The wheel is spinning... wait a sec!"); return end
		if (d.WheelSpins or 0) <= 0 then
			Notify:FireClient(plr, "🎡 No spins left! Claim Gifts to get more spins.")
			return
		end
		d.WheelSpins -= 1
		syncStats(plr) -- immediately updates the on-screen spin balance
		local x = math.random() * wTotal
		local idx = 1
		for i, s in ipairs(WHEEL) do x -= s.w; if x <= 0 then idx = i; break end end
		wheelBusy = true
		local spin = { d = d, s = WHEEL[idx] }
		pendingPrize[plr] = spin
		WheelSpin:FireAllClients(idx, WHEEL_SPIN_TIME, plr.DisplayName, WHEEL[idx].label)
		task.spawn(function() animateWheel(idx) end)
		task.delay(WHEEL_WINDUP_TIME + WHEEL_SPIN_TIME, function()
			wheelBusy = false
			payPrize(plr, spin, plr.Parent ~= nil)
		end)
	end

	if prompt then prompt.Triggered:Connect(spinWheel) end
	if click then click.MouseClick:Connect(spinWheel) end
end
-- equip brainrots from the Inventory menu
local baseInvoke = menuHandler
MenuAction.OnServerInvoke = function(plr, action, arg)
	if (action == "equip" or action == "unequip") and _G.PlazaEquipAction then return _G.PlazaEquipAction(plr, data[plr], action, arg) end
	if action == "equipHat" then return false, "Hats were removed from the game" end
	return baseInvoke(plr, action, arg)
end

-- ================= SPEED BOOTS applied on spawn =================
local function applySpeed(plr)
	local d = data[plr]; local h = plr.Character and plr.Character:FindFirstChildOfClass("Humanoid")
	if d and h then h.WalkSpeed = speedOf(d) end
end
local function hookSpeed(plr)
	plr.CharacterAdded:Connect(function(c) c:WaitForChild("Humanoid", 10); task.wait(0.2); applySpeed(plr) end)
	if plr.Character then task.spawn(applySpeed, plr) end
end
Players.PlayerAdded:Connect(hookSpeed)
for _, p in ipairs(Players:GetPlayers()) do hookSpeed(p) end

-- ================= EGGS: one per rarity, each hatches that rarity =================
local EGG_COST = { Common = 1, Rare = 2, Epic = 4, Legendary = 8, Mythic = 15, ["Brainrot God"] = 30, Secret = 50, OG = 100, Unrated = 3 }
local eggCostValue = remotes:FindFirstChild("EggCosts") or Instance.new("StringValue")
eggCostValue.Name = "EggCosts"; eggCostValue.Value = HttpService:JSONEncode(EGG_COST); eggCostValue.Parent = remotes
for _, egg in ipairs(taggedInWorld("RarityEgg")) do
	local rarity = egg:GetAttribute("Rarity")
	local prompt = egg:FindFirstChild("HatchPrompt", true)
	if rarity == "Any" then rarity = nil end
	if prompt then
		local variant = egg:GetAttribute("Variant")
		local cost = egg:GetAttribute("Cost") or EGG_COST[rarity] or 1
		prompt.Triggered:Connect(function(plr)
			if variant and variant ~= "Normal" and _G.PlazaIslandUnlocked and not _G.PlazaIslandUnlocked(plr, variant) then
				Notify:FireClient(plr, "🔒 Unlock " .. variant .. " Island first!"); return
			end
			doRoll(plr, rarity, variant, cost)
		end)
	end
end

-- ================= EQUIP 3 BRAINROTS THAT FOLLOW YOU =================
local MAX_EQUIPPED = 3
local RANK = {}
for i, r in ipairs(RollConfig.RarityOrder) do RANK[r] = i end
RANK.Unrated = 1
local followersFolder = workspace:FindFirstChild("PlazaFollowers") or Instance.new("Folder")
followersFolder.Name = "PlazaFollowers"; followersFolder.Parent = workspace
local lastEquipKey = {}
local function refreshFollowers(plr, d)
	local old = followersFolder:FindFirstChild(tostring(plr.UserId)); if old then old:Destroy() end
	local f = Instance.new("Folder"); f.Name = tostring(plr.UserId); f.Parent = followersFolder
	for slot, id in ipairs(d.Equipped or {}) do
		local src = modelById[id]
		if src then
			local m = src:Clone()
			for _, x in ipairs(m:GetDescendants()) do
				if x:IsA("LuaSourceContainer") or x:IsA("ProximityPrompt") or x:IsA("ClickDetector") then x:Destroy()
				elseif x:IsA("BasePart") then x.Anchored = true; x.CanCollide = false; x.CanQuery = false; x.CanTouch = false; x.Massless = true end
			end
			local cf, size = m:GetBoundingBox()
			m.WorldPivot = cf
			local h = math.max(size.X, size.Y, size.Z)
			if h > 0 then m:ScaleTo(m:GetScale() * 4.5 / h) end
			m.Name = "Follower" .. slot
			m:SetAttribute("Owner", plr.UserId); m:SetAttribute("Slot", slot)
			local hrp = plr.Character and plr.Character:FindFirstChild("HumanoidRootPart")
			if hrp then m:PivotTo(hrp.CFrame * CFrame.new(0, 0, 6)) else m:PivotTo(CFrame.new(0, -500, 0)) end
			m.Parent = f
		end
	end
end
_G.PlazaSyncEquipped = function(plr, d)
	d.Equipped = type(d.Equipped) == "table" and d.Equipped or {}
	-- drop anything you no longer own enough copies of
	local used, clean = {}, {}
	for _, id in ipairs(d.Equipped) do
		used[id] = (used[id] or 0) + 1
		if (d.Collection[id] or 0) >= used[id] and #clean < MAX_EQUIPPED then table.insert(clean, id) end
	end
	d.Equipped = clean
	local best = 0
	for _, id in ipairs(clean) do local e = Catalog.ById[id]; if e then best = math.max(best, RANK[e.rarity] or 1) end end
	local key = table.concat(clean, ",")
	plr:SetAttribute("Equipped", HttpService:JSONEncode(clean))
	plr:SetAttribute("EquippedRank", best)
	if lastEquipKey[plr] ~= key then lastEquipKey[plr] = key; task.defer(refreshFollowers, plr, d) end
end
_G.PlazaEquipAction = function(plr, d, action, id)
	if not d then return false, "Loading..." end
	d.Equipped = type(d.Equipped) == "table" and d.Equipped or {}
	if type(id) ~= "string" then return false, "?" end
	if action == "unequip" then
		for i, x in ipairs(d.Equipped) do if x == id then table.remove(d.Equipped, i); break end end
		syncStats(plr); return true, "Unequipped"
	end
	local have, used = d.Collection[id] or 0, 0
	for _, x in ipairs(d.Equipped) do if x == id then used += 1 end end
	if have <= used then return false, "You don't have another one of those" end
	if #d.Equipped >= MAX_EQUIPPED then return false, "You can equip 3 brainrots. Unequip one first." end
	table.insert(d.Equipped, id)
	syncStats(plr)
	local e = Catalog.ById[id]
	return true, "Equipped " .. (e and (e.variant ~= "Normal" and (e.variant .. " ") or "") .. e.name or id)
end
Players.PlayerRemoving:Connect(function(plr)
	lastEquipKey[plr] = nil
	local f = followersFolder:FindFirstChild(tostring(plr.UserId)); if f then f:Destroy() end
end)
for plr, d in pairs(data) do _G.PlazaSyncEquipped(plr, d) end

-- ================= INDEX + EGG MASTERY =================
local MASTERY = { -- hatches from one egg -> level + reward
	{ at = 10,  name = "Bronze",  coins = 500 },
	{ at = 50,  name = "Silver",  coins = 2500 },
	{ at = 150, name = "Gold",    coins = 10000 },
	{ at = 500, name = "Diamond", coins = 50000 },
}
local masteryValue = remotes:FindFirstChild("EggMastery") or Instance.new("StringValue")
masteryValue.Name = "EggMastery"; masteryValue.Parent = remotes
do
	local list = {}
	for i, m in ipairs(MASTERY) do list[i] = { at = m.at, name = m.name, reward = m.coins and (m.coins .. " coins") or (m.tokens .. " tokens") } end
	masteryValue.Value = HttpService:JSONEncode(list)
end
local lastIndexKey = {}
_G.PlazaSyncIndex = function(plr, d)
	if type(d.Discovered) ~= "table" then d.Discovered = {} end
	if type(d.EggHatches) ~= "table" then d.EggHatches = {} end
	for id, n in pairs(d.Collection) do if n > 0 then d.Discovered[id] = true end end
	local ids = {}
	for id in pairs(d.Discovered) do table.insert(ids, id) end
	table.sort(ids)
	local key = #ids .. "|" .. HttpService:JSONEncode(d.EggHatches)
	if lastIndexKey[plr] ~= key then
		lastIndexKey[plr] = key
		plr:SetAttribute("Discovered", HttpService:JSONEncode(ids))
		plr:SetAttribute("EggHatches", HttpService:JSONEncode(d.EggHatches))
	end
end
_G.PlazaOnHatch = function(plr, d, id, eggRarity, eggVariant)
	if type(d.Discovered) ~= "table" then d.Discovered = {} end
	if type(d.EggHatches) ~= "table" then d.EggHatches = {} end
	local first = not d.Discovered[id]
	d.Discovered[id] = true
	-- Keep historical rarity totals; island records use separate, unambiguous keys.
	local masteryKey=eggVariant and ("Island:"..eggVariant) or eggRarity
	if eggVariant then d.EggHatches[eggRarity]=(d.EggHatches[eggRarity] or 0)+1 end
	local before = d.EggHatches[masteryKey] or 0
	local after = before + 1
	d.EggHatches[masteryKey] = after
	for _, m in ipairs(MASTERY) do
		if before < m.at and after >= m.at then
			if m.coins then d.Money += m.coins end
			if m.tokens then d.Tokens += m.tokens end
			task.delay(3, function()
				Notify:FireClient(plr, ("🏅 %s EGG MASTERY: %s! +%s"):format(string.upper(eggVariant or eggRarity), m.name, m.coins and (m.coins .. " coins") or (m.tokens .. " tokens")))
			end)
		end
	end
	if first then task.delay(2.5, function() Notify:FireClient(plr, "📖 New Index entry!") end) end
end
Players.PlayerRemoving:Connect(function(plr) lastIndexKey[plr] = nil end)
for plr, d in pairs(data) do _G.PlazaSyncIndex(plr, d) end

-- ================= MUTATION ISLANDS (unlock in order with coins) =================
local islands = {}
for _, m in ipairs(taggedInWorld("MutationIsland")) do
	local variant = m:GetAttribute("Variant")
	islands[variant] = {
		model = m,
		price = Balance.IslandPrices[variant] or m:GetAttribute("Price") or 0,
		order = m:GetAttribute("Order") or 1,
		z = m:GetAttribute("CenterZ") or 0,
	}
end
local islandByOrder = {}
for v, info in pairs(islands) do islandByOrder[info.order] = v end
local function unlocked(d, v)
	local info = islands[v]
	if not info or info.price <= 0 then return true end
	return type(d.Islands) == "table" and d.Islands[v] == true
end
_G.PlazaIslandUnlocked = function(plr, v) local d = data[plr]; return d and unlocked(d, v) end
local function syncIslands(plr, d)
	if type(d.Islands) ~= "table" then d.Islands = {} end
	local list = {}
	for v in pairs(islands) do if unlocked(d, v) then table.insert(list, v) end end
	plr:SetAttribute("UnlockedIslands", HttpService:JSONEncode(list))
end
for _, con in ipairs(workspace:WaitForChild("MutationIslands"):GetDescendants()) do
	if con:IsA("ProximityPrompt") and con.Name == "UnlockPrompt" then
		local v = con.Parent:GetAttribute("Variant")
		con.Triggered:Connect(function(plr)
			local d = data[plr]; local info = islands[v]; if not d or not info then return end
			if unlocked(d, v) then Notify:FireClient(plr, "✅ " .. v .. " Island is already unlocked!"); return end
			local prev = islandByOrder[info.order - 1]
			if prev and not unlocked(d, prev) then Notify:FireClient(plr, "🔒 Unlock " .. prev .. " Island first!"); return end
			if d.Money < info.price then Notify:FireClient(plr, ("🔒 You need %d coins to unlock %s Island."):format(info.price, v)); return end
			d.Money -= info.price
			d.Islands[v] = true
			syncStats(plr); syncIslands(plr, d)
			for _, p in ipairs(Players:GetPlayers()) do Notify:FireClient(p, ("🏝 %s unlocked %s Island!"):format(plr.DisplayName, v)) end
		end)
	end
end
-- Pet-Sim style doors: walk into the door -> client popup -> BuyIsland
local buyIsland = remotes:FindFirstChild("BuyIsland") or Instance.new("RemoteFunction")
buyIsland.Name = "BuyIsland"; buyIsland.Parent = remotes
buyIsland.OnServerInvoke = function(plr, v)
	local d = data[plr]; local info = islands[v]
	if not d or not info then return false, "Unknown island" end
	if unlocked(d, v) then syncIslands(plr, d); return true, "Already unlocked" end
	local prev = islandByOrder[info.order - 1]
	if prev and not unlocked(d, prev) then return false, "Unlock " .. prev .. " Island first!" end
	if d.Money < info.price then return false, "Not enough coins" end
	d.Money -= info.price
	d.Islands[v] = true
	syncStats(plr); syncIslands(plr, d)
	for _, p in ipairs(Players:GetPlayers()) do if p ~= plr then Notify:FireClient(p, ("🏝 %s unlocked %s Island!"):format(plr.DisplayName, v)) end end
	return true, "Unlocked"
end
-- keep players off islands they haven't unlocked
task.spawn(function()
	while true do
		task.wait(0.5)
		for plr, d in pairs(data) do
			syncIslands(plr, d)
			local hrp = plr.Character and plr.Character:FindFirstChild("HumanoidRootPart")
			if hrp then
				local p = hrp.Position
				for v, info in pairs(islands) do
					if not unlocked(d, v) and math.abs(p.X) < 238 and p.Z < info.z + 236 and p.Z > info.z - 240 then
						hrp.CFrame = CFrame.new(0, 5, info.z + 262)
						Notify:FireClient(plr, "🔒 " .. v .. " Island is locked. Walk into its gate to unlock it!")
					end
				end
			end
		end
	end
end)

-- ================= COIN INFO for clients =================
-- Passive income and coin collector pads were removed: coins come from breaking treasure with your squad.
local coinRatesValue = remotes:FindFirstChild("CoinRates") or Instance.new("StringValue")
coinRatesValue.Name = "CoinRates"; coinRatesValue.Value = HttpService:JSONEncode({ rarity = COIN_RARITY, mutation = COIN_MUTATION }); coinRatesValue.Parent = remotes
_G.PlazaAccrue = function() end -- kept as a no-op in case another script still calls it
do
	local ev = remotes:FindFirstChild("CoinCollected") or Instance.new("RemoteEvent"); ev.Name = "CoinCollected"; ev.Parent = remotes
end

-- ================= ONE THEMED EGG PER ISLAND (rarity roll + mutation pricing) =================
local ISLAND_EGG_SPEED = 0
local ISLAND_EGG_REFRESH = Balance.IslandEggs.RefreshDelay
local ISLAND_EGG_WEIGHTS = Balance.IslandEggs.Weights
local EGG_RARITY_PRICE = Balance.IslandEggs.BasePrices
local EGG_MUTATION_MULT = Balance.IslandEggs.MutationMultipliers
local RCOL = { Common = Color3.fromRGB(210,215,225), Rare = Color3.fromRGB(80,160,255), Epic = Color3.fromRGB(185,110,255), Legendary = Color3.fromRGB(255,195,65),
	Mythic = Color3.fromRGB(255,80,160), ["Brainrot God"] = Color3.fromRGB(255,244,185), Secret = Color3.fromRGB(155,255,222), OG = Color3.fromRGB(255,118,77), Unrated = Color3.fromRGB(148,163,184) }
local MUTATION_EGG_STYLE = {
	Gold={shell=Color3.fromRGB(255,190,28),accent=Color3.fromRGB(255,242,137),material=Enum.Material.Metal},
	Diamond={shell=Color3.fromRGB(76,220,255),accent=Color3.fromRGB(224,253,255),material=Enum.Material.Glass},
	Cosmic={shell=Color3.fromRGB(132,57,235),accent=Color3.fromRGB(255,99,231),material=Enum.Material.Neon},
	Lava={shell=Color3.fromRGB(255,71,20),accent=Color3.fromRGB(255,217,59),material=Enum.Material.CrackedLava},
	Toxic={shell=Color3.fromRGB(65,245,78),accent=Color3.fromRGB(215,255,72),material=Enum.Material.Neon},
	Glitch={shell=Color3.fromRGB(242,49,210),accent=Color3.fromRGB(25,255,239),material=Enum.Material.Neon},
}
local eggFolder = workspace:FindFirstChild("IslandEggs") or workspace:FindFirstChild("ConveyorBrainrots") or Instance.new("Folder")
eggFolder.Name = "IslandEggs"; eggFolder.Parent = workspace
local function fmtN(n) local s2 = tostring(math.floor(n)):reverse():gsub("(%d%d%d)", "%1,"):reverse(); return (s2:gsub("^,", "")) end
local function playersNear(z, half)
	for _, p in ipairs(Players:GetPlayers()) do
		local hrp = p.Character and p.Character:FindFirstChild("HumanoidRootPart")
		if hrp and math.abs(hrp.Position.X) < half + 20 and math.abs(hrp.Position.Z - z) < half + 80 then return true end
	end
	return false
end
local function spawnIslandEgg(conv, variant, isl)
	local bins = RollPool[variant]; if not bins then return end
	local total = 0
	for r, w in pairs(ISLAND_EGG_WEIGHTS) do if bins[r] and #bins[r] > 0 then total += w end end
	local t, rarity = rng:NextNumber() * total, "Common"
	for _, r in ipairs(RollConfig.RarityOrder) do local w = (bins[r] and #bins[r] > 0) and ISLAND_EGG_WEIGHTS[r] or 0; if w > 0 then t -= w; if t <= 0 then rarity = r; break end end end
	local list = bins[rarity]; if not list or #list == 0 then return end
	local entry = list[rng:NextInteger(1, #list)]
	local x = conv:GetAttribute("EggX") or -70
	local y = conv:GetAttribute("EggY") or 8
	local startZ = conv:GetAttribute("EggZ") or (isl and isl.z) or 0
	local endZ = startZ
	local existingName = variant .. "IslandEgg"
	if eggFolder:FindFirstChild(existingName) then return end
	local price = math.floor((EGG_RARITY_PRICE[rarity] or 150) * (EGG_MUTATION_MULT[variant] or 1))
	local fx = {
		Common={shell=Color3.fromRGB(225,228,235),crack=Color3.fromRGB(255,255,255),light=Color3.fromRGB(230,235,255),bright=.7},
		Rare={shell=Color3.fromRGB(72,145,255),crack=Color3.fromRGB(145,210,255),light=Color3.fromRGB(70,165,255),bright=1.0},
		Epic={shell=Color3.fromRGB(163,78,235),crack=Color3.fromRGB(225,145,255),light=Color3.fromRGB(184,88,255),bright=1.25},
		Legendary={shell=Color3.fromRGB(232,145,28),crack=Color3.fromRGB(255,225,80),light=Color3.fromRGB(255,190,38),bright=1.7},
		Mythic={shell=Color3.fromRGB(119,52,182),crack=Color3.fromRGB(205,115,255),light=Color3.fromRGB(170,70,255),bright=2.1},
		["Brainrot God"]={shell=Color3.fromRGB(245,228,166),crack=Color3.fromRGB(255,255,255),light=Color3.fromRGB(255,235,155),bright=2.5},
		Secret={shell=Color3.fromRGB(28,29,35),crack=Color3.fromRGB(3,3,5),light=Color3.fromRGB(255,255,255),bright=3.0},
		OG={shell=Color3.fromRGB(235,82,42),crack=Color3.fromRGB(255,196,84),light=Color3.fromRGB(255,98,45),bright=2.7},
		Unrated={shell=Color3.fromRGB(115,123,140),crack=Color3.fromRGB(205,214,232),light=Color3.fromRGB(150,165,195),bright=.8},
	}
	local style=fx[rarity] or fx.Common
	local theme=MUTATION_EGG_STYLE[variant] or {shell=style.shell,accent=style.crack,material=Enum.Material.Glass}
	local m=Instance.new("Model");m.Name=existingName
	local base=CFrame.new(x,y,startZ)*CFrame.Angles(0,math.pi,0)
	local shell=require(RS:WaitForChild("PremiumEggStyles")).Build(m,variant,base)
	m:SetAttribute("EggRarity",rarity);m:SetAttribute("CatalogId",entry.id);m:SetAttribute("SpawnTime",workspace:GetServerTimeNow());m:SetAttribute("Speed",ISLAND_EGG_SPEED)
	m:SetAttribute("StartZ",startZ);m:SetAttribute("EndZ",endZ);m:SetAttribute("X",x);m:SetAttribute("EggY",y);m:SetAttribute("StaticIslandEgg",true);m:SetAttribute("Mutation",variant);m:SetAttribute("Price",price);m:SetAttribute("BaseBrightness",style.bright);m:SetAttribute("RotatesAt",os.time()+Design.EggRotationSeconds)
	m:PivotTo(base)
	-- label + prompt on an invisible anchor that rides with the model
	local anchor = Instance.new("Part"); anchor.Name = "BuyAnchor"; anchor.Size = Vector3.new(6, 6, 6); anchor.Transparency = 1; anchor.Anchored = true; anchor.CanCollide = false; anchor.CanTouch = false
	anchor.CFrame = CFrame.new(x, y, startZ); anchor.Parent = m
	require(RS:WaitForChild("EggBillboard")).Build(anchor, { title = variant .. " Egg", inside = rarity .. " inside", insideColor = RCOL[rarity], price = price, accent = theme.accent, accent2 = theme.shell, height = 6.6 })
	local pp = Instance.new("ProximityPrompt"); pp.ActionText = "Hatch · " .. fmtN(price) .. " coins"; pp.ObjectText = rarity .. " Egg"
	pp.HoldDuration = 0.2; pp.MaxActivationDistance = 14; pp.RequiresLineOfSight = false; pp.Parent = anchor
	local bought = false
	m.Parent = eggFolder
	task.delay(Design.EggRotationSeconds, function()
		if m.Parent and not bought then
			m:Destroy()
			if conv.Parent then pcall(spawnIslandEgg, conv, variant, isl) end
		end
	end)
	pp.Triggered:Connect(function(plr)
		if bought then return end
		local d = data[plr]; if not d then return end
		if not unlocked(d, variant) then Notify:FireClient(plr, "🔒 Unlock " .. variant .. " Island first!"); return end
		if Inventory.Count(d.Collection) >= capOf(d) then Notify:FireClient(plr, "🎒 Inventory full! Sell one or buy slots in the Shop."); return end
		if d.Money < price then Notify:FireClient(plr, ("Not enough coins (%s needed)"):format(fmtN(price))); return end
		bought = true
		d.EggPity = type(d.EggPity) == "table" and d.EggPity or {}
		local awardedEntry, awardedRarity = entry, rarity
		local pity = d.EggPity[variant] or 0
		if pity >= Design.PityAt - 1 and not ({Legendary=true, Mythic=true, ["Brainrot God"]=true, Secret=true, OG=true})[rarity] then
			for _, guaranteed in ipairs({"Legendary","Mythic","Brainrot God","Secret","OG"}) do
				local choices = bins[guaranteed]
				if choices and #choices > 0 then awardedRarity = guaranteed; awardedEntry = choices[rng:NextInteger(1,#choices)]; break end
			end
		end
		local high = ({Legendary=true, Mythic=true, ["Brainrot God"]=true, Secret=true, OG=true})[awardedRarity]
		d.EggPity[variant] = high and 0 or (pity + 1)
		local isNew=(d.Collection[awardedEntry.id] or 0)==0
		d.Money -= price
		Inventory.Add(d.Collection, awardedEntry.id, capOf(d))
		if type(d.Discovered) == "table" then d.Discovered[awardedEntry.id] = true end
		if _G.PlazaOnHatch then _G.PlazaOnHatch(plr, d, awardedEntry.id, awardedRarity, variant) end
		recompute(d); syncStats(plr)
		Notify:FireClient(plr, ("🥚 Hatched %s %s from the %s Egg! Pity: %d/%d"):format(variant, awardedEntry.name, variant, d.EggPity[variant], Design.PityAt))
		local events = SS:FindFirstChild("ProgressionEvents")
		local progress = events and events:FindFirstChild("QuestProgress")
		if progress then progress:Fire(plr, "Hatch", variant, 1) end
		remotes.RegularEggHatched:FireClient(plr,m)
		RollReveal:FireClient(plr,awardedEntry.id,awardedRarity,theme.accent,awardedEntry.power,isNew,variant,"IslandEgg")
		pp.Enabled=false
		task.delay(.9,function() if m.Parent then m:Destroy() end end)
		task.delay(ISLAND_EGG_REFRESH, function() if conv.Parent then pcall(spawnIslandEgg, conv, variant, isl) end end)
	end)
end
for _, pedestal in ipairs(taggedInWorld("BrainrotEggPedestal")) do
	local variant = pedestal:GetAttribute("Variant")
	local isl = islands[variant]
	if isl then pcall(spawnIslandEgg, pedestal, variant, isl) end
end

-- ================= REGULAR EGG (starter plaza): costs coins, hatches regular (Normal) brainrots =================
local regularEggHatched = Instance.new("RemoteEvent")
regularEggHatched.Name = "RegularEggHatched"; regularEggHatched.Parent = remotes
local regularEggLast = {}
Players.PlayerRemoving:Connect(function(plr) regularEggLast[plr] = nil end)
local function hatchRegularEgg(plr, egg)
	local d = data[plr]; if not d then return end
	local price = egg:GetAttribute("Price") or 100
	local now = os.clock()
	if regularEggLast[plr] and now - regularEggLast[plr] < 1 then return end
	if Inventory.Count(d.Collection) >= capOf(d) then Notify:FireClient(plr, "🎒 Inventory full! Sell one or buy slots in the Shop."); return end
	if (d.Money or 0) < price then Notify:FireClient(plr, ("Not enough coins (%s needed)"):format(fmtN(price))); return end
	local bins = RollPool.Normal; if not bins then return end
	local total, w = 0, {}
	for _, r in ipairs(RollConfig.RarityOrder) do
		local x = (bins[r] and #bins[r] > 0) and (RollConfig.RarityWeights[r] or 0) or 0
		w[r] = x; total += x
	end
	if total <= 0 then return end
	local t, rarity = rng:NextNumber() * total, nil
	for _, r in ipairs(RollConfig.RarityOrder) do if w[r] > 0 then t -= w[r]; if t <= 0 then rarity = r; break end end end
	rarity = rarity or "Common"
	local list = bins[rarity]; if not list or #list == 0 then return end
	local entry = list[rng:NextInteger(1, #list)]
	regularEggLast[plr] = now
	local isNew = (d.Collection[entry.id] or 0) == 0
	d.Money -= price
	if not Inventory.Add(d.Collection, entry.id, capOf(d)) then d.Money += price; return end
	if type(d.Discovered) == "table" then d.Discovered[entry.id] = true end
	if _G.PlazaOnHatch then _G.PlazaOnHatch(plr, d, entry.id, rarity, "Normal") end
	recompute(d); syncStats(plr)
	local normalColor = Color3.fromRGB(215, 225, 241)
	for _, vv in ipairs(RollConfig.Variants) do if vv.name == "Normal" then normalColor = vv.color end end
	local r = rarityByName[entry.rarity]
	remotes.RegularEggHatched:FireClient(plr, egg)
	RollReveal:FireClient(plr, entry.id, r and r.name or rarity, normalColor, entry.power, isNew, "Normal", "RegularEgg")
	Notify:FireClient(plr, ("🥚 Hatched %s from the Regular Egg!"):format(entry.name or entry.id))
end
for _, egg in ipairs(taggedInWorld("RegularEgg")) do
	local prompt = egg:FindFirstChild("HatchPrompt", true)
	if prompt then prompt.Triggered:Connect(function(plr) hatchRegularEgg(plr, egg) end) end
end

-- Loose floor coins were removed. Money now comes from brainrots breaking coin piles, bags, chests, and vaults.
local oldFloorCoins=workspace:FindFirstChild("FloorCoins");if oldFloorCoins then oldFloorCoins:ClearAllChildren() end

-- ================= MEGA VAULT (Gold Island): lots of health, pays out gold to everyone who helped =================
local EquippedBreakableDamage=require(game.ServerStorage:WaitForChild("EquippedBreakableDamage"))
local VAULT_HP = 25000
local VAULT_POOL = 50000        -- coins split by damage share
local VAULT_MIN_REWARD = 1000   -- anyone who helped gets at least this
local VAULT_RESPAWN = 180
for _, vault in ipairs(taggedInWorld("MegaVault")) do
	local body = vault:FindFirstChild("Body")
	local bar = body and body:FindFirstChild("HealthBar")
	local fill = bar and bar:FindFirstChild("Fill", true)
	local hpText = bar and bar:FindFirstChild("HP", true)
	local title = bar and bar:FindFirstChild("Title", true)
	local hub = vault:FindFirstChild("WheelHub")
	local door = vault:FindFirstChild("Door")
	local hp, broken = VAULT_HP, false
	local damage, lastHit = {}, {}
	local function refresh()
		if fill then fill.Size = UDim2.fromScale(math.max(hp, 0) / VAULT_HP, 1) end
		if hpText then hpText.Text = ("%s / %s"):format(fmtN(math.max(hp, 0)), fmtN(VAULT_HP)) end
	end
	local function hit(plr)
		if broken then return end
		local d = data[plr]; if not d then return end
		if not unlocked(d, "Gold") then return end
		local now = os.clock()
		if lastHit[plr] and now - lastHit[plr] < 0.12 then return end
		lastHit[plr] = now
		local root=plr.Character and plr.Character:FindFirstChild("HumanoidRootPart")
		if not root or (root.Position-vault:GetPivot().Position).Magnitude>125 then return end
		local dmg = math.min(hp,EquippedBreakableDamage.ForTeam(d.Equipped))
		hp -= dmg
		damage[plr] = (damage[plr] or 0) + dmg
		if hub and hub:FindFirstChild("HitSparks") then hub.HitSparks:Emit(8) end
		refresh()
		if hp <= 0 then
			broken = true
			if hub and hub:FindFirstChild("GoldBurst") then hub.GoldBurst:Emit(250) end
			if door then door.Transparency = 0.6 end
			local total = 0; for _, v in pairs(damage) do total += v end
			for p, v in pairs(damage) do
				local pd = data[p]
				if pd and p.Parent then
					local reward = math.max(VAULT_MIN_REWARD, math.floor(VAULT_POOL * v / math.max(total, 1)))
					pd.Money += reward; syncStats(p)
					Notify:FireClient(p, ("💰 MEGA VAULT CRACKED! You did %d%% of the damage: +%s coins"):format(math.floor(v / total * 100 + 0.5), fmtN(reward)))
					local fx = remotes:FindFirstChild("CoinCollected"); if fx then fx:FireClient(p, reward, "Gold") end
				end
			end
			for _, p in ipairs(Players:GetPlayers()) do if not damage[p] then Notify:FireClient(p, "💰 The Mega Vault on Gold Island was just cracked!") end end
			damage = {}
			task.spawn(function()
				for t = VAULT_RESPAWN, 1, -1 do
					if title then title.Text = ("💰 VAULT CRACKED · refills in %d:%02d"):format(t // 60, t % 60) end
					task.wait(1)
				end
				hp = VAULT_HP; broken = false
				if door then door.Transparency = 0 end
				if title then title.Text = "💰 MEGA VAULT · click to crack it!" end
				refresh()
			end)
		end
	end
	for _, cd in ipairs(vault:GetDescendants()) do if cd:IsA("ClickDetector") then cd.MouseClick:Connect(hit) end end
	Players.PlayerRemoving:Connect(function(p) damage[p] = nil; lastHit[p] = nil end)
	refresh()
end

-- ================= GIANT TREASURE CHEST (Treasure Arena): 100k HP, huge gold payout =================
local CHEST_HP = 100000
local CHEST_POOL = 300000
local CHEST_MIN = 10000
local CHEST_RESPAWN = 300
for _, chest in ipairs(taggedInWorld("GiantChest")) do
	local body = chest:FindFirstChild("Body")
	local bar = body and body:FindFirstChild("HealthBar")
	local fill = bar and bar:FindFirstChild("Fill", true)
	local hpText = bar and bar:FindFirstChild("HP", true)
	local title = bar and bar:FindFirstChild("Title", true)
	local lock = chest:FindFirstChild("Padlock")
	local glow = chest:FindFirstChild("TreasureGlow")
	local lid = chest:FindFirstChild("Lid")
	local lidHome = lid and lid:GetPivot()
	local hp, broken = CHEST_HP, false
	local dmgBy, last = {}, {}
	local function refresh()
		if fill then fill.Size = UDim2.fromScale(math.max(hp, 0) / CHEST_HP, 1) end
		if hpText then hpText.Text = ("%s / %s"):format(fmtN(math.max(hp, 0)), fmtN(CHEST_HP)) end
	end
	local function hit(plr)
		if broken then return end
		local d = data[plr]; if not d then return end
		local now = os.clock()
		if last[plr] and now - last[plr] < 0.12 then return end
		last[plr] = now
		local root=plr.Character and plr.Character:FindFirstChild("HumanoidRootPart")
		if not root or (root.Position-chest:GetPivot().Position).Magnitude>125 then return end
		local dmg = math.min(hp,EquippedBreakableDamage.ForTeam(d.Equipped))
		hp -= dmg
		dmgBy[plr] = (dmgBy[plr] or 0) + dmg
		if lock and lock:FindFirstChild("HitSparks") then lock.HitSparks:Emit(10) end
		refresh()
		if hp <= 0 then
			broken = true
			if glow and glow:FindFirstChild("GoldBurst") then glow.GoldBurst:Emit(400) end
			if lid and lidHome then lid:PivotTo(lidHome * CFrame.new(0, 0, 0) * CFrame.Angles(math.rad(-60), 0, 0)) end
			local total = 0; for _, v in pairs(dmgBy) do total += v end
			for p, v in pairs(dmgBy) do
				local pd = data[p]
				if pd and p.Parent then
					local reward = math.max(CHEST_MIN, math.floor(CHEST_POOL * v / math.max(total, 1)))
					pd.Money += reward; syncStats(p)
					Notify:FireClient(p, ("🏴‍☠️ TREASURE CHEST BROKEN! You did %d%% of the damage: +%s coins"):format(math.floor(v / total * 100 + 0.5), fmtN(reward)))
					local fx = remotes:FindFirstChild("CoinCollected"); if fx then fx:FireClient(p, reward, "Gold") end
				end
			end
			for _, p in ipairs(Players:GetPlayers()) do if not dmgBy[p] then Notify:FireClient(p, "🏴‍☠️ The Giant Treasure Chest was just broken open!") end end
			dmgBy = {}
			task.spawn(function()
				for t = CHEST_RESPAWN, 1, -1 do
					if title then title.Text = ("🏴‍☠️ CHEST EMPTY · refills in %d:%02d"):format(t // 60, t % 60) end
					task.wait(1)
				end
				hp = CHEST_HP; broken = false
				if lid and lidHome then lid:PivotTo(lidHome) end
				if title then title.Text = "🏴‍☠️ GIANT TREASURE CHEST · team up to break it!" end
				refresh()
			end)
		end
	end
	for _, cd in ipairs(chest:GetDescendants()) do if cd:IsA("ClickDetector") then cd.MouseClick:Connect(hit) end end
	Players.PlayerRemoving:Connect(function(p) dmgBy[p] = nil; last[p] = nil end)
	refresh()
end
