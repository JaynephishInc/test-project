-- SocialAndRewardsServer
-- 1) Friend boost: +10% coins for every friend playing in your server (max +50%).
-- 2) While you were away: your squad keeps collecting while you're offline (5 min - 8 h); claim it on return.
-- 3) Achievements: 18 goals with rewards. Each can also award a real Roblox badge: create the badge on the
--    Creator Dashboard and paste its id into BADGES below.

local Players = game:GetService("Players")
local RS = game:GetService("ReplicatedStorage")
local SS = game:GetService("ServerStorage")
local BadgeService = game:GetService("BadgeService")
local HttpService = game:GetService("HttpService")

local remotes = RS:WaitForChild("BrainrotRemotes")
local Notify = remotes:WaitForChild("Notify")
local SocialAction = remotes:FindFirstChild("SocialAction") or Instance.new("RemoteFunction")
SocialAction.Name = "SocialAction"; SocialAction.Parent = remotes
local SocialEvent = remotes:FindFirstChild("SocialEvent") or Instance.new("RemoteEvent")
SocialEvent.Name = "SocialEvent"; SocialEvent.Parent = remotes
local okCat, Catalog = pcall(function() return require(RS:WaitForChild("BrainrotCatalog")) end)

local FRIEND_BONUS, FRIEND_MAX = 0.10, 5
local OFFLINE_MIN, OFFLINE_MAX = 300, 8 * 3600
local ISLANDS = { "Gold", "Diamond", "Cosmic", "Lava", "Toxic", "Glitch" }

local ACH = {
	{ id = "first_hatch", icon = "🥚", name = "First Steps", desc = "Hatch your first brainrot", stat = "hatch", goal = 1, reward = { coins = 250 } },
	{ id = "hatch_25", icon = "🐣", name = "Egg Enthusiast", desc = "Hatch 25 eggs", stat = "hatch", goal = 25, reward = { spins = 2 } },
	{ id = "hatch_250", icon = "🌟", name = "Egg Legend", desc = "Hatch 250 eggs", stat = "hatch", goal = 250, reward = { luck = 10 } },
	{ id = "break_100", icon = "💰", name = "Treasure Hunter", desc = "Break 100 treasures", stat = "breaks", goal = 100, reward = { coins = 2000 } },
	{ id = "break_1000", icon = "💎", name = "Treasure Tycoon", desc = "Break 1,000 treasures", stat = "breaks", goal = 1000, reward = { spins = 5 } },
	{ id = "vault_1", icon = "🏦", name = "Vault Cracker", desc = "Break into a vault", stat = "vaults", goal = 1, reward = { spins = 1 } },
	{ id = "event_vault", icon = "💥", name = "Team Player", desc = "Help crack a Giant Vault", stat = "eventVaults", goal = 1, reward = { spins = 3 } },
	{ id = "catch_1", icon = "🎯", name = "Gotcha!", desc = "Catch a wild brainrot", stat = "catches", goal = 1, reward = { luck = 3 } },
	{ id = "catch_25", icon = "🧲", name = "Brainrot Wrangler", desc = "Catch 25 wild brainrots", stat = "catches", goal = 25, reward = { spins = 5 } },
	{ id = "island_1", icon = "🌴", name = "Island Hopper", desc = "Unlock Gold Island", stat = "islands", goal = 1, reward = { coins = 1000 } },
	{ id = "island_6", icon = "🌍", name = "World Traveler", desc = "Unlock all 6 islands", stat = "islands", goal = 6, reward = { spins = 10, luck = 10 } },
	{ id = "index_50", icon = "📖", name = "Collector", desc = "Discover 50 brainrots", stat = "index", goal = 50, reward = { spins = 3 } },
	{ id = "index_200", icon = "📚", name = "Archivist", desc = "Discover 200 brainrots", stat = "index", goal = 200, reward = { spins = 8 } },
	{ id = "streak_7", icon = "🔥", name = "Loyal Fan", desc = "Reach a 7-day login streak", stat = "streak", goal = 7, reward = { spins = 5 } },
	{ id = "millionaire", icon = "🤑", name = "Millionaire", desc = "Hold 1,000,000 coins", stat = "money", goal = 1000000, reward = { spins = 3 } },
	{ id = "shiny", icon = "✨", name = "Shiny!", desc = "Fuse a brainrot to level 5", stat = "bestFusion", goal = 5, reward = { luck = 5 } },
	{ id = "rainbow", icon = "🌈", name = "Over the Rainbow", desc = "Fuse a brainrot to level 10", stat = "bestFusion", goal = 10, reward = { spins = 10 } },
	{ id = "friends", icon = "👥", name = "Better Together", desc = "Play with a friend", stat = "friends", goal = 1, reward = { spins = 2 } },
}
-- achievement id -> Roblox badge id (0 = no badge yet). Example: first_hatch = 1234567890,
local BADGES = {}

local function fmt(n) local s = tostring(math.floor(n)):reverse():gsub("(%d%d%d)", "%1,"):reverse() return (s:gsub("^,", "")) end
local function dataOf(plr) for _ = 1, 150 do local d = _G.PlazaGetData and _G.PlazaGetData(plr) if d then return d end task.wait(0.1) end end
local function describe(r)
	local p = {}
	if r.coins then table.insert(p, fmt(r.coins) .. " coins") end
	if r.spins then table.insert(p, r.spins .. (r.spins == 1 and " spin" or " spins")) end
	if r.luck then table.insert(p, r.luck .. " lucky hatches") end
	return table.concat(p, " + ")
end
local function islandsOf(plr)
	local n = 0
	for _, v in ipairs(ISLANDS) do
		local ok, r = pcall(function() return _G.PlazaIslandUnlocked and _G.PlazaIslandUnlocked(plr, v) end)
		if ok and r then n += 1 end
	end
	return n
end

---------------------------------------------------------------- achievements
local function statValue(plr, d, stat)
	local s = d.AchStats or {}
	if stat == "islands" then return islandsOf(plr)
	elseif stat == "index" then local n = 0; for _ in pairs(d.Discovered or {}) do n += 1 end; return n
	elseif stat == "streak" then return type(d.Login) == "table" and d.Login.streak or 0
	elseif stat == "money" then return d.Money or 0
	elseif stat == "bestFusion" then local m = 0; for _, lv in pairs(d.FusionLevels or {}) do m = math.max(m, lv) end; return m
	elseif stat == "friends" then return plr:GetAttribute("FriendCount") or 0 end
	return s[stat] or 0
end
local function achState(plr, d)
	local list = {}
	for _, a in ipairs(ACH) do
		table.insert(list, { id = a.id, icon = a.icon, name = a.name, desc = a.desc, goal = a.goal, progress = math.min(a.goal, statValue(plr, d, a.stat)),
			done = d.Achievements and d.Achievements[a.id] == true, reward = describe(a.reward) })
	end
	return list
end
local function check(plr)
	local d = _G.PlazaGetData and _G.PlazaGetData(plr)
	if not d then return end
	d.Achievements = type(d.Achievements) == "table" and d.Achievements or {}
	local unlocked = 0
	for _, a in ipairs(ACH) do
		if d.Achievements[a.id] then
			unlocked += 1
		elseif statValue(plr, d, a.stat) >= a.goal then
			d.Achievements[a.id] = true
			unlocked += 1
			local r = a.reward
			if r.coins then d.Money = (d.Money or 0) + r.coins end
			if r.spins then d.WheelSpins = (d.WheelSpins or 0) + r.spins end
			if r.luck then d.LuckRolls = (d.LuckRolls or 0) + r.luck end
			if _G.PlazaSyncPlayer then _G.PlazaSyncPlayer(plr) end
			SocialEvent:FireClient(plr, "achievement", { icon = a.icon, name = a.name, desc = a.desc, reward = describe(r) })
			local badge = BADGES[a.id]
			if badge and badge > 0 then task.spawn(pcall, BadgeService.AwardBadge, BadgeService, plr.UserId, badge) end
		end
	end
	plr:SetAttribute("Achievements", unlocked)
	plr:SetAttribute("AchievementsTotal", #ACH)
end
local function bump(plr, stat, n)
	local d = _G.PlazaGetData and _G.PlazaGetData(plr)
	if not d then return end
	d.AchStats = type(d.AchStats) == "table" and d.AchStats or {}
	d.AchStats[stat] = (d.AchStats[stat] or 0) + (n or 1)
	check(plr)
end
_G.PlazaAchievementEvent = function(plr, what) if what == "catch" then bump(plr, "catches") end end

-- event sources
task.spawn(function()
	local events = SS:WaitForChild("ProgressionEvents", 60)
	local qp = events and events:WaitForChild("QuestProgress", 60)
	if not qp then return end
	qp.Event:Connect(function(plr, kind, _, amount, subtype)
		if typeof(plr) ~= "Instance" then return end
		if kind == "Break" then
			bump(plr, "breaks", amount or 1)
			if subtype == "Vault" then bump(plr, "vaults", 1) end
		end
	end)
end)
task.spawn(function() -- hatches (all eggs go through _G.PlazaOnHatch)
	while not _G.PlazaOnHatch do task.wait(0.5) end
	task.wait(2) -- let DailyRewardsServer wrap it first; we just chain on top
	local original = _G.PlazaOnHatch
	_G.PlazaOnHatch = function(plr, ...)
		local results = table.pack(original(plr, ...))
		task.defer(bump, plr, "hatch", 1)
		return table.unpack(results, 1, results.n)
	end
end)
task.spawn(function() -- giant vault helpers (chain onto the capture hook)
	while not _G.PlazaOnBroken do task.wait(0.5) end
	local original = _G.PlazaOnBroken
	_G.PlazaOnBroken = function(model, ledger)
		if model:GetAttribute("EventVault") and type(ledger) == "table" then
			for plr in pairs(ledger) do if typeof(plr) == "Instance" and plr.Parent then task.spawn(bump, plr, "eventVaults", 1) end end
		end
		return original(model, ledger)
	end
end)
task.spawn(function() -- money / islands / streak / fusion / index are read live; re-check now and then
	while true do
		task.wait(6)
		for _, plr in ipairs(Players:GetPlayers()) do pcall(check, plr) end
	end
end)

---------------------------------------------------------------- friend boost
local friendCache = {}
local function areFriends(a, b)
	local key = math.min(a.UserId, b.UserId) .. ":" .. math.max(a.UserId, b.UserId)
	if friendCache[key] == nil then
		local ok, r = pcall(function() return a:IsFriendsWith(b.UserId) end)
		friendCache[key] = ok and r == true
	end
	return friendCache[key]
end
local function refreshFriends()
	for _, p in ipairs(Players:GetPlayers()) do
		local n = 0
		for _, q in ipairs(Players:GetPlayers()) do if q ~= p and areFriends(p, q) then n += 1 end end
		p:SetAttribute("FriendCount", n)
		p:SetAttribute("FriendBoost", math.min(n, FRIEND_MAX) * FRIEND_BONUS)
	end
end

---------------------------------------------------------------- while you were away
local pendingOffline = {}
local function offlineOffer(plr, d)
	local last = tonumber(d.LastSavedAt)
	if not last then return end
	local away = os.time() - last
	if away < OFFLINE_MIN then return end
	local seconds = math.min(away, OFFLINE_MAX)
	local squad = type(d.Equipped) == "table" and #d.Equipped or 0
	if squad == 0 then return end
	local perMinute = 20 * (2.5 ^ islandsOf(plr)) * (1 + 0.25 * squad)
	local coins = math.floor(perMinute * seconds / 60)
	if coins <= 0 then return end
	pendingOffline[plr] = coins
	SocialEvent:FireClient(plr, "offline", { coins = coins, seconds = seconds, capped = away > OFFLINE_MAX })
end

---------------------------------------------------------------- players
Players.PlayerAdded:Connect(function(plr)
	task.spawn(function()
		local d = dataOf(plr)
		refreshFriends()
		-- tell friends (and the new player) about each other
		for _, q in ipairs(Players:GetPlayers()) do
			if q ~= plr and areFriends(plr, q) then
				SocialEvent:FireClient(q, "friend", { userId = plr.UserId, name = plr.DisplayName, count = q:GetAttribute("FriendCount"), boost = q:GetAttribute("FriendBoost") })
				SocialEvent:FireClient(plr, "friend", { userId = q.UserId, name = q.DisplayName, count = plr:GetAttribute("FriendCount"), boost = plr:GetAttribute("FriendBoost") })
			end
		end
		if d then
			check(plr)
			task.wait(6) -- after the join screen
			if plr.Parent then offlineOffer(plr, d) end
		end
	end)
end)
for _, plr in ipairs(Players:GetPlayers()) do task.spawn(function() local d = dataOf(plr); refreshFriends(); if d then check(plr) end end) end
Players.PlayerRemoving:Connect(function(plr)
	pendingOffline[plr] = nil
	task.defer(refreshFriends)
end)

SocialAction.OnServerInvoke = function(plr, action)
	local d = dataOf(plr)
	if not d then return false, "Loading…" end
	if action == "achievements" then return true, achState(plr, d) end
	if action == "claimOffline" then
		local coins = pendingOffline[plr]
		if not coins then return false, "Nothing to claim" end
		pendingOffline[plr] = nil
		d.Money = (d.Money or 0) + coins
		if _G.PlazaSyncPlayer then _G.PlazaSyncPlayer(plr) end
		return true, coins
	end
	return false, "?"
end

-- testing (server): ServerStorage.PlazaTestHooks.OfferOffline:Invoke(player, seconds)
local hooks = SS:FindFirstChild("PlazaTestHooks") or Instance.new("Folder")
hooks.Name = "PlazaTestHooks"; hooks.Parent = SS
local h = hooks:FindFirstChild("OfferOffline") or Instance.new("BindableFunction")
h.Name = "OfferOffline"; h.Parent = hooks
h.OnInvoke = function(plr, seconds)
	local d = _G.PlazaGetData and _G.PlazaGetData(plr)
	if not d then return false end
	d.LastSavedAt = os.time() - (seconds or 7200)
	offlineOffer(plr, d)
	return pendingOffline[plr]
end
