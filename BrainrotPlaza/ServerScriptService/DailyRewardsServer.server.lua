-- DailyRewardsServer
-- Banana Dancana's daily quests, the 7-day login streak and the new-player tutorial rewards.
-- Saved in the player's data (d.Daily, d.Login, d.TutorialDone, d.TutorialGift) by PiazzaLobbyServer.
-- Days roll over at 00:00 UTC. Rewards grow with how many islands the player has unlocked.

local Players = game:GetService("Players")
local RS = game:GetService("ReplicatedStorage")
local SS = game:GetService("ServerStorage")

local remotes = RS:WaitForChild("BrainrotRemotes")
local Notify = remotes:WaitForChild("Notify")
local DailyAction = remotes:FindFirstChild("DailyAction") or Instance.new("RemoteFunction")
DailyAction.Name = "DailyAction"
DailyAction.Parent = remotes
local DailyUpdate = remotes:FindFirstChild("DailyUpdate") or Instance.new("RemoteEvent")
DailyUpdate.Name = "DailyUpdate"
DailyUpdate.Parent = remotes
local okCat, Catalog = pcall(function() return require(RS:WaitForChild("BrainrotCatalog")) end)

local ISLANDS = { "Gold", "Diamond", "Cosmic", "Lava", "Toxic", "Glitch" }

-- Daily quest pool. "Break"/"Fuse" come from ServerStorage.ProgressionEvents.QuestProgress;
-- Hatch, Coins, Spin and Play are counted here.
local POOL = {
	{ id = "break30", kind = "Break", target = 30, text = "Break 30 treasures", reward = 600 },
	{ id = "chest3", kind = "Break", subtype = "Chest", target = 3, text = "Crack open 3 chests", reward = 700 },
	{ id = "bags10", kind = "Break", subtype = "CoinBag", target = 10, text = "Burst 10 coin bags", reward = 600 },
	{ id = "vault1", kind = "Break", subtype = "Vault", target = 1, text = "Break into a vault", reward = 900 },
	{ id = "wild5", kind = "Break", subtype = "WildBrainrot", target = 5, text = "Defeat 5 wild brainrots", reward = 900, island = true },
	{ id = "hatch3", kind = "Hatch", target = 3, text = "Hatch 3 eggs", reward = 800 },
	{ id = "coins", kind = "Coins", target = 5000, text = "Earn %s coins", reward = 700, scaleTarget = true },
	{ id = "spin1", kind = "Spin", target = 1, text = "Spin the Lucky Wheel", reward = 400 },
	{ id = "play10", kind = "Play", target = 600, text = "Hang out for 10 minutes", reward = 500, time = true },
	{ id = "fuse1", kind = "Fuse", target = 1, text = "Fuse a brainrot", reward = 1200, island = true },
}
local BY_ID = {}
for _, q in ipairs(POOL) do BY_ID[q.id] = q end

-- 7-day login calendar (repeats). Coin amounts are multiplied by the player's island progress.
local LOGIN = {
	{ coins = 500 },
	{ spins = 2 },
	{ coins = 2500 },
	{ luck = 5 },
	{ coins = 7500, spins = 2 },
	{ coins = 15000 },
	{ coins = 30000, spins = 5, luck = 10, big = true },
}
local BONUS = { spins = 3, luck = 5 } -- finishing all three daily quests
local TUTORIAL_GIFT = 150 -- Banana's welcome coins (a Regular Egg costs 100)
local TUTORIAL_PRIZE = { spins = 1, luck = 3 }

local function today() return math.floor(os.time() / 86400) end
local function fmt(n)
	local s = tostring(math.floor(n)):reverse():gsub("(%d%d%d)", "%1,"):reverse()
	return (s:gsub("^,", ""))
end
local function dataOf(plr)
	for _ = 1, 150 do
		local d = _G.PlazaGetData and _G.PlazaGetData(plr)
		if d then return d end
		task.wait(0.1)
	end
end
local function islandsUnlocked(plr)
	local n = 0
	for _, v in ipairs(ISLANDS) do
		local ok, r = pcall(function() return _G.PlazaIslandUnlocked and _G.PlazaIslandUnlocked(plr, v) end)
		if ok and r then n += 1 end
	end
	return n
end
local function describe(r, mult)
	local parts = {}
	if r.coins then table.insert(parts, fmt(r.coins * (mult or 1)) .. " coins") end
	if r.spins then table.insert(parts, r.spins .. (r.spins == 1 and " spin" or " spins")) end
	if r.luck then table.insert(parts, r.luck .. " lucky hatches") end
	return table.concat(parts, " + ")
end
local function give(plr, d, r, mult)
	if r.coins then d.Money = (d.Money or 0) + math.floor(r.coins * (mult or 1)) end
	if r.spins then d.WheelSpins = (d.WheelSpins or 0) + r.spins end
	if r.luck then d.LuckRolls = (d.LuckRolls or 0) + r.luck end
	if _G.PlazaSyncPlayer then _G.PlazaSyncPlayer(plr) end
	return describe(r, mult)
end

local function ensureDaily(plr, d)
	local day = today()
	if type(d.Daily) ~= "table" or d.Daily.day ~= day or type(d.Daily.quests) ~= "table" then
		local islands = islandsUnlocked(plr)
		local rng = Random.new(day * 7919 + plr.UserId % 100003)
		local options = {}
		for _, q in ipairs(POOL) do if islands > 0 or not q.island then table.insert(options, q.id) end end
		local picked = {}
		for _ = 1, 3 do
			local k = rng:NextInteger(1, #options)
			table.insert(picked, { id = table.remove(options, k), progress = 0, claimed = false })
		end
		d.Daily = { day = day, quests = picked, bonus = false, mult = 2.5 ^ islands }
	end
	return d.Daily
end
local function targetOf(q, daily) return q.scaleTarget and math.floor(q.target * daily.mult) or q.target end
local function loginState(d)
	if type(d.Login) ~= "table" then d.Login = { streak = 0, last = -1 } end
	local L = d.Login
	local day = today()
	local canClaim = L.last ~= day
	local nextStreak = canClaim and ((L.last == day - 1) and L.streak + 1 or 1) or L.streak
	return L, canClaim, nextStreak
end

local function stateFor(plr, d)
	local daily = ensureDaily(plr, d)
	local L, canClaim, nextStreak = loginState(d)
	local quests, ready, allClaimed = {}, 0, true
	for i, e in ipairs(daily.quests) do
		local q = BY_ID[e.id]
		if q then
			local target = targetOf(q, daily)
			local row = { i = i, id = e.id, text = q.text:format(fmt(target)), progress = math.min(e.progress, target), target = target,
				reward = math.floor(q.reward * daily.mult), claimed = e.claimed, time = q.time }
			if not e.claimed then allClaimed = false; if row.progress >= target then ready += 1 end end
			table.insert(quests, row)
		end
	end
	local bonusReady = allClaimed and not daily.bonus
	if bonusReady then ready += 1 end
	if canClaim then ready += 1 end
	local week = {}
	for i, r in ipairs(LOGIN) do week[i] = { label = describe(r, daily.mult), big = r.big == true } end
	return {
		resetIn = (daily.day + 1) * 86400 - os.time(), quests = quests, bonus = daily.bonus, bonusReady = bonusReady,
		bonusLabel = describe(BONUS), streak = L.streak, canClaim = canClaim, nextStreak = nextStreak, week = week, ready = ready,
	}
end
local function push(plr)
	local d = _G.PlazaGetData and _G.PlazaGetData(plr)
	if not d then return end
	local s = stateFor(plr, d)
	plr:SetAttribute("DailyReady", s.ready)
	DailyUpdate:FireClient(plr, s)
end
local pending = {}
local function pushSoon(plr)
	if pending[plr] then return end
	pending[plr] = true
	task.delay(0.4, function() pending[plr] = nil; if plr.Parent then push(plr) end end)
end

local function addProgress(plr, kind, amount, subtype)
	local d = _G.PlazaGetData and _G.PlazaGetData(plr)
	if not d then return end
	local daily = ensureDaily(plr, d)
	local changed = false
	for _, e in ipairs(daily.quests) do
		local q = BY_ID[e.id]
		if q and not e.claimed and q.kind == kind and (not q.subtype or q.subtype == subtype) then
			local target = targetOf(q, daily)
			if e.progress < target then
				e.progress = math.min(target, e.progress + (amount or 1))
				changed = true
				if e.progress >= target then
					Notify:FireClient(plr, "🍌 Daily quest done: " .. q.text:format(fmt(target)) .. "! Claim it from Banana Dancana.")
				end
			end
		end
	end
	if changed then pushSoon(plr) end
end

-- progress sources ---------------------------------------------------------
task.spawn(function()
	local events = SS:WaitForChild("ProgressionEvents", 60)
	local qp = events and events:WaitForChild("QuestProgress", 60)
	if not qp then return end
	qp.Event:Connect(function(plr, kind, source, amount, subtype)
		if typeof(plr) ~= "Instance" then return end
		if kind == "Break" then addProgress(plr, "Break", amount or 1, subtype)
		elseif kind == "Fuse" then addProgress(plr, "Fuse", 1) end
	end)
end)
task.spawn(function() -- every hatch (regular and island eggs) goes through _G.PlazaOnHatch
	while not _G.PlazaOnHatch do task.wait(0.5) end
	local original = _G.PlazaOnHatch
	_G.PlazaOnHatch = function(plr, ...)
		local results = table.pack(original(plr, ...))
		task.defer(addProgress, plr, "Hatch", 1)
		return table.unpack(results, 1, results.n)
	end
end)
task.spawn(function() -- time played
	while true do
		task.wait(10)
		for _, plr in ipairs(Players:GetPlayers()) do addProgress(plr, "Play", 10) end
	end
end)

local function onPlayer(plr)
	local d = dataOf(plr)
	if not d then return end
	-- returning players never see the tutorial
	if not d.TutorialDone and ((type(d.Collection) == "table" and next(d.Collection)) or (d.Rebirths or 0) > 0 or (d.Money or 0) > 2000) then
		d.TutorialDone = true
	end
	plr:SetAttribute("TutorialDone", d.TutorialDone == true)
	local lastMoney, lastSpins = plr:GetAttribute("Money") or 0, plr:GetAttribute("WheelSpins") or 0
	plr:GetAttributeChangedSignal("Money"):Connect(function()
		local m = plr:GetAttribute("Money") or 0
		if m > lastMoney then addProgress(plr, "Coins", m - lastMoney) end
		lastMoney = m
	end)
	plr:GetAttributeChangedSignal("WheelSpins"):Connect(function()
		local s = plr:GetAttribute("WheelSpins") or 0
		if s < lastSpins then addProgress(plr, "Spin", lastSpins - s) end
		lastSpins = s
	end)
	push(plr)
end
Players.PlayerAdded:Connect(function(plr) task.spawn(onPlayer, plr) end)
for _, plr in ipairs(Players:GetPlayers()) do task.spawn(onPlayer, plr) end

-- client actions --------------------------------------------------------------
local busy = {}
DailyAction.OnServerInvoke = function(plr, action, arg)
	local d = dataOf(plr)
	if not d then return false, "Still loading…" end
	if action == "state" then return true, stateFor(plr, d) end
	if busy[plr] then return false, "One moment…" end
	busy[plr] = true
	local ok, a, b = pcall(function()
		if action == "claimLogin" then
			local L, canClaim, nextStreak = loginState(d)
			if not canClaim then return false, "Already claimed today. Come back tomorrow!" end
			L.streak = nextStreak
			L.last = today()
			local idx = (L.streak - 1) % 7 + 1
			local text = give(plr, d, LOGIN[idx], ensureDaily(plr, d).mult)
			return true, { day = idx, streak = L.streak, text = text }
		elseif action == "claimQuest" then
			local daily = ensureDaily(plr, d)
			local e = daily.quests[tonumber(arg) or 0]
			local q = e and BY_ID[e.id]
			if not q then return false, "That quest is gone. New ones arrived!" end
			if e.claimed then return false, "Already claimed" end
			if e.progress < targetOf(q, daily) then return false, "Not finished yet" end
			e.claimed = true
			return true, { text = give(plr, d, { coins = q.reward }, daily.mult) }
		elseif action == "claimBonus" then
			local daily = ensureDaily(plr, d)
			if daily.bonus then return false, "Already claimed" end
			for _, e in ipairs(daily.quests) do if not e.claimed then return false, "Finish all three quests first" end end
			daily.bonus = true
			return true, { text = give(plr, d, BONUS) }
		elseif action == "tutorial" then
			if arg == "start" then
				if d.TutorialDone or d.TutorialGift then return false, "done" end
				d.TutorialGift = true
				return true, { text = give(plr, d, { coins = TUTORIAL_GIFT }) }
			elseif arg == "equip" then
				if type(d.Equipped) == "table" and #d.Equipped > 0 then return true, "already" end
				local bestId, bestPower
				for id, n in pairs(d.Collection or {}) do
					local e = okCat and Catalog.ById and Catalog.ById[id]
					local p = e and e.power or 0
					if n > 0 and (not bestPower or p > bestPower) then bestId, bestPower = id, p end
				end
				if not bestId or not _G.PlazaEquipAction then return false, "nothing to equip" end
				return _G.PlazaEquipAction(plr, d, "equip", bestId)
			elseif arg == "done" or arg == "skip" then
				if d.TutorialDone then return false, "done" end
				d.TutorialDone = true
				plr:SetAttribute("TutorialDone", true)
				if arg == "skip" then return true, {} end
				return true, { text = give(plr, d, TUTORIAL_PRIZE) }
			end
		end
		return false, "?"
	end)
	busy[plr] = nil
	pushSoon(plr)
	if not ok then warn("DailyRewardsServer:", a) return false, "Something went wrong" end
	return a, b
end
Players.PlayerRemoving:Connect(function(plr) busy[plr] = nil; pending[plr] = nil end)
