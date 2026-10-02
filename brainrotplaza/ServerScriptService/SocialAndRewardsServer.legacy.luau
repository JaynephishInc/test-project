-- SocialAndRewardsServer
-- 1) Friend boost: +10% coins for every friend playing in your server (max +50%).
-- 2) While you were away: your squad keeps collecting while you're offline (5 min - 8 h); claim it on return.
-- 3) Achievements with rewards. Any achievement can also give a real Roblox badge:
--    a) Creator Dashboard > your experience > Associated Items > Badges > Create a Badge
--       (use the achievement's name, description and badge image)
--    b) copy the new badge's ID and paste it as `badge = ` on that achievement's line below.
--    Players who already earned the achievement get the badge the next time they join.

local Players = game:GetService("Players")
local RS = game:GetService("ReplicatedStorage")
local SS = game:GetService("ServerStorage")
local BadgeService = game:GetService("BadgeService")
local DataStoreService = game:GetService("DataStoreService")

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
local RARITY_RANK = { Common = 1, Rare = 2, Epic = 3, Legendary = 4, Mythic = 5, ["Brainrot God"] = 6, Secret = 7, OG = 8, Unrated = 0 }

-- stat: what is counted. goal: how much is needed. reward: coins / luck (lucky hatches). badge: Roblox badge ID (0 = none yet)
local ACH = {
	-- getting started
	{ id = "welcome", icon = "👋", name = "Welcome to the Plaza", desc = "Join Brainrot Plaza for the first time", stat = "joined", goal = 1, reward = { coins = 100 }, badge = 0 },
	{ id = "first_hatch", icon = "🥚", name = "First Steps", desc = "Hatch your first brainrot", stat = "hatch", goal = 1, reward = { coins = 250 }, badge = 0 },
	{ id = "friends", icon = "👥", name = "Better Together", desc = "Play in the same server as a friend", stat = "friends", goal = 1, reward = { luck = 3 }, badge = 0 },
	-- hatching
	{ id = "hatch_25", icon = "🐣", name = "Egg Enthusiast", desc = "Hatch 25 eggs", stat = "hatch", goal = 25, reward = { luck = 3 }, badge = 0 },
	{ id = "hatch_250", icon = "🌟", name = "Egg Legend", desc = "Hatch 250 eggs", stat = "hatch", goal = 250, reward = { luck = 10 }, badge = 0 },
	{ id = "hatch_1000", icon = "👑", name = "Egg Royalty", desc = "Hatch 1,000 eggs", stat = "hatch", goal = 1000, reward = { coins = 250000, luck = 25 }, badge = 0 },
	{ id = "lucky_legendary", icon = "🍀", name = "Lucky Pull", desc = "Hatch a Legendary (or rarer) brainrot", stat = "bestRarity", goal = 4, reward = { luck = 3 }, badge = 0 },
	{ id = "lucky_mythic", icon = "💜", name = "Mythic Moment", desc = "Hatch a Mythic (or rarer) brainrot", stat = "bestRarity", goal = 5, reward = { luck = 5 }, badge = 0 },
	{ id = "lucky_secret", icon = "🤫", name = "It's a Secret!", desc = "Hatch a Secret (or OG) brainrot", stat = "bestRarity", goal = 7, reward = { coins = 50000, luck = 10 }, badge = 0 },
	{ id = "lucky_og", icon = "🔥", name = "OG Status", desc = "Hatch an OG brainrot", stat = "bestRarity", goal = 8, reward = { coins = 100000, luck = 15 }, badge = 0 },
	{ id = "glitch", icon = "👾", name = "Glitch in the System", desc = "Hatch or catch a Glitch brainrot", stat = "glitch", goal = 1, reward = { luck = 5 }, badge = 0 },
	-- treasure
	{ id = "break_100", icon = "💰", name = "Treasure Hunter", desc = "Break 100 treasures", stat = "breaks", goal = 100, reward = { coins = 2000 }, badge = 0 },
	{ id = "break_1000", icon = "💎", name = "Treasure Tycoon", desc = "Break 1,000 treasures", stat = "breaks", goal = 1000, reward = { coins = 25000 }, badge = 0 },
	{ id = "break_10000", icon = "🏆", name = "Treasure Legend", desc = "Break 10,000 treasures", stat = "breaks", goal = 10000, reward = { coins = 250000, luck = 10 }, badge = 0 },
	{ id = "vault_1", icon = "🏦", name = "Vault Cracker", desc = "Break into a vault", stat = "vaults", goal = 1, reward = { coins = 1500 }, badge = 0 },
	{ id = "event_vault", icon = "💥", name = "Team Player", desc = "Help crack a Giant Vault", stat = "eventVaults", goal = 1, reward = { luck = 3 }, badge = 0 },
	{ id = "event_vault_10", icon = "🧨", name = "Heist Crew", desc = "Help crack 10 Giant Vaults", stat = "eventVaults", goal = 10, reward = { coins = 100000, luck = 10 }, badge = 0 },
	-- bosses
	{ id = "boss_1", icon = "⚔️", name = "Boss Slayer", desc = "Help defeat an island boss", stat = "bosses", goal = 1, reward = { coins = 5000, luck = 3 }, badge = 0 },
	{ id = "boss_25", icon = "🗡️", name = "Boss Hunter", desc = "Help defeat 25 island bosses", stat = "bosses", goal = 25, reward = { coins = 100000, luck = 10 }, badge = 0 },
	{ id = "boss_all", icon = "🏰", name = "King of the Islands", desc = "Defeat the boss on all 6 islands", stat = "bossIslands", goal = 6, reward = { coins = 500000, luck = 25 }, badge = 0 },
	-- wild brainrots
	{ id = "catch_1", icon = "🎯", name = "Gotcha!", desc = "Catch a wild brainrot", stat = "catches", goal = 1, reward = { luck = 3 }, badge = 0 },
	{ id = "catch_25", icon = "🧲", name = "Brainrot Wrangler", desc = "Catch 25 wild brainrots", stat = "catches", goal = 25, reward = { luck = 10 }, badge = 0 },
	{ id = "catch_100", icon = "🕸️", name = "Brainrot Whisperer", desc = "Catch 100 wild brainrots", stat = "catches", goal = 100, reward = { coins = 150000, luck = 15 }, badge = 0 },
	{ id = "storm_1", icon = "⛈️", name = "Storm Chaser", desc = "Be online during a Brainrot Storm", stat = "storms", goal = 1, reward = { luck = 3 }, badge = 0 },
	-- islands
	{ id = "island_1", icon = "🌴", name = "Island Hopper", desc = "Unlock Gold Island", stat = "islands", goal = 1, reward = { coins = 1000 }, badge = 0 },
	{ id = "island_3", icon = "🧭", name = "Explorer", desc = "Unlock 3 islands", stat = "islands", goal = 3, reward = { luck = 5 }, badge = 0 },
	{ id = "island_6", icon = "🌍", name = "World Traveler", desc = "Unlock all 6 islands", stat = "islands", goal = 6, reward = { coins = 250000, luck = 10 }, badge = 0 },
	-- collection
	{ id = "index_50", icon = "📖", name = "Collector", desc = "Discover 50 brainrots", stat = "index", goal = 50, reward = { luck = 5 }, badge = 0 },
	{ id = "index_200", icon = "📚", name = "Archivist", desc = "Discover 200 brainrots", stat = "index", goal = 200, reward = { luck = 15 }, badge = 0 },
	{ id = "first_fuse", icon = "🧪", name = "Mad Scientist", desc = "Fuse a brainrot", stat = "bestFusion", goal = 1, reward = { coins = 1000 }, badge = 0 },
	{ id = "shiny", icon = "✨", name = "Shiny!", desc = "Fuse a brainrot to level 5", stat = "bestFusion", goal = 5, reward = { luck = 5 }, badge = 0 },
	{ id = "rainbow", icon = "🌈", name = "Over the Rainbow", desc = "Fuse a brainrot to level 10", stat = "bestFusion", goal = 10, reward = { coins = 100000, luck = 10 }, badge = 0 },
	-- progress
	{ id = "rebirth_1", icon = "🔁", name = "Born Again", desc = "Rebirth for the first time", stat = "rebirths", goal = 1, reward = { luck = 5 }, badge = 0 },
	{ id = "rebirth_10", icon = "♾️", name = "Rebirth Legend", desc = "Rebirth 10 times", stat = "rebirths", goal = 10, reward = { luck = 25 }, badge = 0 },
	{ id = "millionaire", icon = "🤑", name = "Millionaire", desc = "Hold 1,000,000 coins", stat = "money", goal = 1000000, reward = { luck = 5 }, badge = 0 },
	{ id = "billionaire", icon = "💸", name = "Billionaire", desc = "Hold 1,000,000,000 coins", stat = "money", goal = 1000000000, reward = { luck = 25 }, badge = 0 },
	-- coming back
	{ id = "streak_7", icon = "📅", name = "Loyal Fan", desc = "Reach a 7-day login streak", stat = "streak", goal = 7, reward = { luck = 5 }, badge = 0 },
	{ id = "streak_30", icon = "🗓️", name = "Superfan", desc = "Reach a 30-day login streak", stat = "streak", goal = 30, reward = { coins = 100000, luck = 25 }, badge = 0 },
	{ id = "daily_10", icon = "🍌", name = "Banana's Helper", desc = "Finish 10 daily quests", stat = "dailyQuests", goal = 10, reward = { coins = 10000 }, badge = 0 },
	{ id = "daily_100", icon = "🏅", name = "Banana's Best Friend", desc = "Finish 100 daily quests", stat = "dailyQuests", goal = 100, reward = { luck = 20 }, badge = 0 },
	-- events
	{ id = "golden_egg", icon = "🔎", name = "Golden Find", desc = "Find a Golden Egg", stat = "goldenEggs", goal = 1, reward = { luck = 3 }, badge = 0 },
	{ id = "golden_egg_10", icon = "🕵️", name = "Egg Detective", desc = "Find 10 Golden Eggs", stat = "goldenEggs", goal = 10, reward = { coins = 50000, luck = 10 }, badge = 0 },
	{ id = "tournament_top10", icon = "🎖️", name = "Tournament Star", desc = "Finish in the top 10 of a Weekend Tournament", stat = "tournamentTop10", goal = 1, reward = { luck = 10 }, badge = 0 },
	-- collections
	{ id = "collection_1", icon = "🗂️", name = "Completionist", desc = "Complete a mutation collection", stat = "collections", goal = 1, reward = { luck = 10 }, badge = 0 },
	{ id = "collection_all", icon = "🌌", name = "Master Collector", desc = "Complete all 7 mutation collections", stat = "collections", goal = 7, reward = { coins = 1000000, luck = 50 }, badge = 0 },
	-- friends
	{ id = "invite_1", icon = "💌", name = "Recruiter", desc = "Invite a friend who joins for the first time", stat = "referrals", goal = 1, reward = { luck = 5 }, badge = 0 },
	{ id = "invite_10", icon = "📣", name = "Influencer", desc = "Invite 10 friends who join for the first time", stat = "referrals", goal = 10, reward = { coins = 100000, luck = 20 }, badge = 0 },
}

local function fmt(n) local s = tostring(math.floor(n)):reverse():gsub("(%d%d%d)", "%1,"):reverse() return (s:gsub("^,", "")) end
local function dataOf(plr) -- loading can wait for the player's previous server to finish saving
	for _ = 1, 600 do
		if not plr.Parent then return end
		local d = _G.PlazaGetData and _G.PlazaGetData(plr)
		if d then return d end
		task.wait(0.1)
	end
end
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
local function count(t) local n = 0; if type(t) == "table" then for _ in pairs(t) do n += 1 end end; return n end

---------------------------------------------------------------- badges
-- Remembers which badges we already know a player has, so we only ask Roblox once per session.
local hasBadge = {}
local function giveBadge(plr, badgeId)
	if type(badgeId) ~= "number" or badgeId <= 0 or not plr.Parent then return end
	hasBadge[plr] = hasBadge[plr] or {}
	if hasBadge[plr][badgeId] then return end
	local okHas, owned = pcall(BadgeService.UserHasBadgeAsync, BadgeService, plr.UserId, badgeId)
	if okHas and owned then hasBadge[plr][badgeId] = true; return end
	for attempt = 1, 2 do
		local ok, err = pcall(BadgeService.AwardBadge, BadgeService, plr.UserId, badgeId)
		if ok then hasBadge[plr][badgeId] = true; return end
		if attempt == 2 then warn(("SocialAndRewardsServer: couldn't award badge %d to %s: %s"):format(badgeId, plr.Name, tostring(err))) end
		task.wait(2)
	end
end
-- players who earned achievements before a badge existed get it when they join
local function catchUpBadges(plr, d)
	for _, a in ipairs(ACH) do
		if (a.badge or 0) > 0 and d.Achievements and d.Achievements[a.id] then
			giveBadge(plr, a.badge)
			task.wait(0.25) -- stay well under Roblox's badge request limits
		end
	end
end

---------------------------------------------------------------- achievements
local function statValue(plr, d, stat)
	local s = type(d.AchStats) == "table" and d.AchStats or {}
	if stat == "joined" then return 1
	elseif stat == "islands" then return islandsOf(plr)
	elseif stat == "index" then return count(d.Discovered)
	elseif stat == "streak" then return type(d.Login) == "table" and d.Login.streak or 0
	elseif stat == "money" then return d.Money or 0
	elseif stat == "rebirths" then return d.Rebirths or 0
	elseif stat == "bestFusion" then local m = 0; for _, lv in pairs(d.FusionLevels or {}) do m = math.max(m, lv) end; return m
	elseif stat == "bossIslands" then return count(s.bossIslands)
	elseif stat == "collections" then return count(type(d.Flair) == "table" and d.Flair.collections)
	elseif stat == "referrals" then return type(d.Referral) == "table" and tonumber(d.Referral.count) or 0
	elseif stat == "friends" then return plr:GetAttribute("FriendCount") or 0 end
	return tonumber(s[stat]) or 0
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
			if (a.badge or 0) > 0 then task.spawn(giveBadge, plr, a.badge) end
		end
	end
	plr:SetAttribute("Achievements", unlocked)
	plr:SetAttribute("AchievementsTotal", #ACH)
end
local function statsOf(plr)
	local d = _G.PlazaGetData and _G.PlazaGetData(plr)
	if not d then return end
	d.AchStats = type(d.AchStats) == "table" and d.AchStats or {}
	return d.AchStats, d
end
local function bump(plr, stat, n)
	local s = statsOf(plr); if not s then return end
	s[stat] = (tonumber(s[stat]) or 0) + (n or 1)
	check(plr)
end
local function noteBrainrot(plr, id) -- rarest hatch so far + Glitch brainrots
	local s = statsOf(plr); if not s then return end
	local e = okCat and Catalog.ById and Catalog.ById[id]
	if not e then return end
	s.bestRarity = math.max(tonumber(s.bestRarity) or 0, RARITY_RANK[e.rarity] or 0)
	if e.variant == "Glitch" then s.glitch = (tonumber(s.glitch) or 0) + 1 end
end
-- other scripts report events here: "catch" (WildCaptureAndStorms), "boss" (IslandBossServer), "dailyQuest" (DailyRewardsServer),
-- "goldenEgg" (TreasureHuntServer), "tournamentTop10" (TournamentServer)
_G.PlazaAchievementEvent = function(plr, what, arg)
	if what == "catch" then
		noteBrainrot(plr, arg)
		bump(plr, "catches")
	elseif what == "boss" then
		local s = statsOf(plr); if not s then return end
		if type(arg) == "string" then
			s.bossIslands = type(s.bossIslands) == "table" and s.bossIslands or {}
			s.bossIslands[arg] = true
		end
		bump(plr, "bosses")
	elseif what == "dailyQuest" then
		bump(plr, "dailyQuests")
	elseif what == "goldenEgg" then
		bump(plr, "goldenEggs")
	elseif what == "tournamentTop10" then
		bump(plr, "tournamentTop10")
	end
end

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
	_G.PlazaOnHatch = function(plr, d, id, ...)
		local results = table.pack(original(plr, d, id, ...))
		task.defer(function() noteBrainrot(plr, id); bump(plr, "hatch", 1) end)
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
-- Brainrot Storms (WildCaptureAndStorms): everyone online counts once per storm
local function countStorm(plr)
	local endsAt = RS:GetAttribute("StormEndsAt")
	local s = statsOf(plr)
	if not endsAt or not s or s.lastStorm == endsAt then return end
	s.lastStorm = endsAt
	bump(plr, "storms", 1)
end
RS:GetAttributeChangedSignal("StormEndsAt"):Connect(function()
	for _, plr in ipairs(Players:GetPlayers()) do task.spawn(countStorm, plr) end
end)
task.spawn(function() -- money / islands / streak / fusion / index / rebirths are read live; re-check now and then
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

---------------------------------------------------------------- invite a friend
-- A player who joins Brainrot Plaza for the FIRST time through a friend's invite (Roblox menu > Invite Friends,
-- or a shared link) gets a welcome gift, and the friend who invited them gets a reward: right away if they're in
-- the same server, otherwise the next time they play. Rewards stop after INVITE_MAX invites (stops alt farming).
local INVITE_NEW = { coins = 500, luck = 3 }
local INVITE_FRIEND = { coins = 2500, luck = 5 }
local INVITE_MAX = 25
local okRef, refStore = pcall(function() return DataStoreService:GetDataStore("PlazaReferrals_v1") end)
if not okRef then refStore = nil end
local function referralOf(d)
	d.Referral = type(d.Referral) == "table" and d.Referral or {}
	return d.Referral
end
local function rewardInviter(plr, d, invites, newName)
	local ref = referralOf(d)
	local before = ref.count or 0
	ref.count = before + invites
	local paid = math.max(0, math.min(invites, INVITE_MAX - before))
	if paid > 0 then
		d.Money = (d.Money or 0) + INVITE_FRIEND.coins * paid
		d.LuckRolls = (d.LuckRolls or 0) + INVITE_FRIEND.luck * paid
		if _G.PlazaSyncPlayer then _G.PlazaSyncPlayer(plr) end
	end
	local who = newName and (newName .. " joined from your invite") or (invites == 1 and "A friend joined from your invite" or (invites .. " friends joined from your invites"))
	Notify:FireClient(plr, paid > 0 and ("💌 %s! +%s coins + %d lucky hatches!"):format(who, fmt(INVITE_FRIEND.coins * paid), INVITE_FRIEND.luck * paid)
		or ("💌 %s! Thanks for sharing Brainrot Plaza!"):format(who))
	check(plr)
end
local function handleInvites(plr, d)
	local ref = referralOf(d)
	-- 1) did this brand-new player come from someone's invite?
	local okJoin, joinData = pcall(function() return plr:GetJoinData() end)
	local by = okJoin and type(joinData) == "table" and tonumber(joinData.ReferredByPlayerId) or 0
	if by > 0 and by ~= plr.UserId and d.LastSavedAt == nil and not ref.by then
		ref.by = by
		d.Money = (d.Money or 0) + INVITE_NEW.coins
		d.LuckRolls = (d.LuckRolls or 0) + INVITE_NEW.luck
		if _G.PlazaSyncPlayer then _G.PlazaSyncPlayer(plr) end
		task.delay(7, function()
			if plr.Parent then Notify:FireClient(plr, ("🎁 Your friend invited you! Welcome gift: +%s coins + %d lucky hatches!"):format(fmt(INVITE_NEW.coins), INVITE_NEW.luck)) end
		end)
		local inviter = Players:GetPlayerByUserId(by)
		local inviterData = inviter and _G.PlazaGetData and _G.PlazaGetData(inviter)
		if inviterData then
			rewardInviter(inviter, inviterData, 1, plr.DisplayName)
		elseif refStore then
			pcall(function() refStore:UpdateAsync(tostring(by), function(old) return (tonumber(old) or 0) + 1 end) end)
		end
	end
	-- 2) did friends join from MY invites while I was away?
	if refStore then
		local waiting = 0
		local ok = pcall(function()
			refStore:UpdateAsync(tostring(plr.UserId), function(old)
				waiting = tonumber(old) or 0
				if waiting == 0 then return nil end
				return 0
			end)
		end)
		if ok and waiting > 0 then rewardInviter(plr, d, waiting) end
	end
end

---------------------------------------------------------------- players
Players.PlayerAdded:Connect(function(plr)
	task.spawn(function()
		local d = dataOf(plr)
		if d then pcall(handleInvites, plr, d) end
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
			countStorm(plr)
			task.spawn(catchUpBadges, plr, d)
			task.wait(6) -- after the join screen
			if plr.Parent then offlineOffer(plr, d) end
		end
	end)
end)
for _, plr in ipairs(Players:GetPlayers()) do task.spawn(function() local d = dataOf(plr); refreshFriends(); if d then check(plr) end end) end
Players.PlayerRemoving:Connect(function(plr)
	pendingOffline[plr] = nil
	hasBadge[plr] = nil
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
