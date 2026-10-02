-- TournamentServer
-- The Weekend Tournament: every Saturday 17:00 UTC (10am Pacific) for 30 hours, everything you break earns points.
-- Points count across ALL servers. The TournamentScreen in the plaza shows the live top players, and when it ends
-- the best players get prizes the next time they're in the game (right away if they're online).
--   treasure = 1 point, chests and vaults = 3, island bosses = 10

local Players = game:GetService("Players")
local RS = game:GetService("ReplicatedStorage")
local SS = game:GetService("ServerStorage")
local DSS = game:GetService("DataStoreService")

local WDAY, HOUR_UTC, HOURS = 7, 17, 30 -- Saturday (os.date: Sunday = 1), start hour (UTC), how many hours it lasts
local WEEK, DURATION = 7 * 86400, HOURS * 3600
local POINTS = { Chest = 3, Vault = 3, Boss = 10 }
local MIN_POINTS = 50 -- needed for the "thanks for playing" prize
-- rank -> prize. coins grow with islands unlocked, like daily rewards
local PRIZES = {
	{ rank = 1, luck = 30, coins = 10000, label = "🥇" },
	{ rank = 2, luck = 20, coins = 6000, label = "🥈" },
	{ rank = 3, luck = 15, coins = 4000, label = "🥉" },
	{ rank = 10, luck = 8, coins = 2000, label = "🏅" },
}
local PLAY_PRIZE = { luck = 3, coins = 500 }
local ISLANDS = { "Gold", "Diamond", "Cosmic", "Lava", "Toxic", "Glitch" }

local remotes = RS:WaitForChild("BrainrotRemotes")
local Notify = remotes:WaitForChild("Notify")

local function fmt(n) local s = tostring(math.floor(n)):reverse():gsub("(%d%d%d)", "%1,"):reverse() return (s:gsub("^,", "")) end
local function dataOf(plr)
	for _ = 1, 600 do
		if not plr.Parent then return nil end
		local d = _G.PlazaGetData and _G.PlazaGetData(plr)
		if d then return d end
		task.wait(0.1)
	end
	return nil
end

-- start of the most recent tournament that has started (it may still be live, or already over)
local function lastStart(now)
	local t = os.date("!*t", now)
	local midnight = now - (t.hour * 3600 + t.min * 60 + t.sec)
	local start = midnight - ((t.wday - WDAY) % 7) * 86400 + HOUR_UTC * 3600
	if start > now then start -= WEEK end
	return start
end
local function state()
	local now = os.time()
	local s = lastStart(now)
	local live = now < s + DURATION
	return live, s, live and (s + DURATION - now) or (s + WEEK - now)
end
local function storeFor(week)
	local ok, store = pcall(function() return DSS:GetOrderedDataStore("PlazaTournament_" .. week) end)
	return ok and store or nil
end
local function timeText(sec)
	local d, h, m = sec // 86400, sec % 86400 // 3600, sec % 3600 // 60
	if d > 0 then return ("%dd %02dh %02dm"):format(d, h, m) end
	return ("%dh %02dm %02ds"):format(h, m, sec % 60)
end

---------------------------------------------------------------- scoring
local pending = {} -- player -> points not written to the DataStore yet
local function tourneyOf(d, week)
	d.Tournament = type(d.Tournament) == "table" and d.Tournament or {}
	if d.Tournament.week ~= week then d.Tournament.week = week; d.Tournament.score = 0 end
	return d.Tournament
end
local function addPoints(plr, points)
	local live, week = state()
	if not live then return end
	local d = _G.PlazaGetData and _G.PlazaGetData(plr)
	if not d then return end
	local t = tourneyOf(d, week)
	local before = t.score or 0
	t.score = before + points
	pending[plr] = (pending[plr] or 0) + points
	plr:SetAttribute("TournamentScore", t.score)
	if before // 100 < t.score // 100 then
		Notify:FireClient(plr, ("🏆 %s tournament points! Keep breaking treasure!"):format(fmt(t.score // 100 * 100)))
	end
end
local function flush(plr)
	local points = pending[plr]
	if not points or points <= 0 then return end
	local live, week = state()
	local d = _G.PlazaGetData and _G.PlazaGetData(plr)
	local scoredWeek = d and type(d.Tournament) == "table" and d.Tournament.week or week
	if not live and scoredWeek ~= week then pending[plr] = nil; return end
	local store = storeFor(scoredWeek)
	if not store then return end
	pending[plr] = nil
	local ok = pcall(function() store:IncrementAsync(tostring(plr.UserId), points) end)
	if not ok then pending[plr] = (pending[plr] or 0) + points end -- try again next flush
end
task.spawn(function()
	local events = SS:WaitForChild("ProgressionEvents", 60)
	local qp = events and events:WaitForChild("QuestProgress", 60)
	if not qp then return end
	qp.Event:Connect(function(plr, kind, _, amount, subtype)
		if kind == "Break" and typeof(plr) == "Instance" and plr:IsA("Player") then
			addPoints(plr, (POINTS[subtype] or 1) * (amount or 1))
		end
	end)
end)
task.spawn(function()
	while true do
		task.wait(30)
		for plr in pairs(pending) do if plr.Parent then task.spawn(flush, plr) end end
	end
end)

---------------------------------------------------------------- leaderboard
local names = {}
local function nameOf(uid)
	if names[uid] then return names[uid] end
	local p = Players:GetPlayerByUserId(uid)
	if p then names[uid] = p.DisplayName return names[uid] end
	local ok, n = pcall(function() return Players:GetNameFromUserIdAsync(uid) end)
	names[uid] = ok and n or ("Player " .. uid)
	return names[uid]
end
local tops = {} -- week -> { {userId, score}, ... } (best first)
local function fetchTop(week)
	local store = storeFor(week)
	if not store then return nil end
	local ok, pages = pcall(function() return store:GetSortedAsync(false, 10) end)
	if not ok or not pages then return nil end
	local list = {}
	for _, e in ipairs(pages:GetCurrentPage()) do table.insert(list, { userId = tonumber(e.key), score = e.value }) end
	tops[week] = list
	return list
end
-- in Studio (or if DataStores fail) the board still works with the players in this server
local function localTop(week)
	local list = {}
	for _, p in ipairs(Players:GetPlayers()) do
		local d = _G.PlazaGetData and _G.PlazaGetData(p)
		local t = d and type(d.Tournament) == "table" and d.Tournament
		if t and t.week == week and (t.score or 0) > 0 then table.insert(list, { userId = p.UserId, score = t.score }) end
	end
	table.sort(list, function(a, b) return a.score > b.score end)
	return list
end

---------------------------------------------------------------- screen in the plaza
local GOLD, SILVER, BRONZE = Color3.fromRGB(255, 210, 70), Color3.fromRGB(215, 225, 240), Color3.fromRGB(235, 150, 90)
local screen = workspace:WaitForChild("PiazzaBrainrot"):WaitForChild("Showcase", 30)
screen = screen and screen:FindFirstChild("TournamentScreen")
local ui
if screen and screen:IsA("BasePart") then
	for _, old in ipairs(screen:GetChildren()) do -- replace the old countdown text on the front of the screen
		if old:IsA("SurfaceGui") and old.Face == Enum.NormalId.Front then old:Destroy() end
	end
	local sg = Instance.new("SurfaceGui"); sg.Name = "TournamentBoard"; sg.Face = Enum.NormalId.Front
	sg.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud; sg.PixelsPerStud = 30; sg.LightInfluence = 0; sg.Parent = screen
	local root = Instance.new("Frame"); root.Size = UDim2.fromScale(1, 1); root.BackgroundColor3 = Color3.fromRGB(18, 16, 32); root.BorderSizePixel = 0; root.Parent = sg
	local grad = Instance.new("UIGradient"); grad.Rotation = 90
	grad.Color = ColorSequence.new(Color3.fromRGB(40, 30, 70), Color3.fromRGB(14, 12, 26)); grad.Parent = root
	local pad = Instance.new("UIPadding"); pad.PaddingLeft = UDim.new(0.03, 0); pad.PaddingRight = UDim.new(0.03, 0)
	pad.PaddingTop = UDim.new(0.04, 0); pad.PaddingBottom = UDim.new(0.04, 0); pad.Parent = root
	local function label(name, y, h, font, color)
		local l = Instance.new("TextLabel"); l.Name = name; l.BackgroundTransparency = 1; l.Position = UDim2.fromScale(0, y); l.Size = UDim2.fromScale(1, h)
		l.Font = font; l.TextScaled = true; l.TextColor3 = color; l.Text = ""; l.Parent = root
		local st = Instance.new("UIStroke"); st.Thickness = 2; st.Color = Color3.fromRGB(10, 8, 20); st.Parent = l
		return l
	end
	local wide = screen.Size.X / math.max(screen.Size.Y, 0.1) > 4 -- a thin banner only has room for one line + the top 3
	ui = { wide = wide }
	if wide then
		ui.title = label("Title", 0, 0.5, Enum.Font.FredokaOne, GOLD)
		ui.status = label("Status", 0.52, 0.48, Enum.Font.GothamBold, Color3.new(1, 1, 1))
	else
		ui.title = label("Title", 0, 0.16, Enum.Font.FredokaOne, GOLD)
		ui.status = label("Status", 0.17, 0.09, Enum.Font.GothamBold, Color3.new(1, 1, 1))
		ui.rows = {}
		for i = 1, 8 do
			local r = label("Row" .. i, 0.29 + (i - 1) * 0.085, 0.075, Enum.Font.GothamBold, Color3.new(1, 1, 1))
			r.TextXAlignment = Enum.TextXAlignment.Left
			ui.rows[i] = r
		end
	end
end
local function rowColor(i) return i == 1 and GOLD or i == 2 and SILVER or i == 3 and BRONZE or Color3.new(1, 1, 1) end
local function drawBoard()
	if not ui then return end
	local live, week, left = state()
	local list = live and (tops[week] or localTop(week)) or (tops[week] or {})
	ui.title.Text = live and "🏆 WEEKEND TOURNAMENT · LIVE!" or "🏆 WEEKEND TOURNAMENT"
	if ui.wide then
		local top3 = {}
		for i = 1, math.min(3, #list) do table.insert(top3, ("%s %s"):format(({ "🥇", "🥈", "🥉" })[i], nameOf(list[i].userId))) end
		ui.status.Text = live and ("Ends in %s%s"):format(timeText(left), #top3 > 0 and ("  ·  " .. table.concat(top3, "  ")) or "")
			or ("Starts in %s%s"):format(timeText(left), #top3 > 0 and ("  ·  Last winners: " .. table.concat(top3, "  ")) or "")
		return
	end
	ui.status.Text = live and ("Break treasure for points! Ends in %s"):format(timeText(left)) or ("Starts in %s"):format(timeText(left))
	if live or #list > 0 then
		for i = 1, 8 do
			local e = list[i]
			local r = ui.rows[i]
			if e then
				r.Text = ("%s %s — %s pts"):format(i <= 3 and ({ "🥇", "🥈", "🥉" })[i] or (i .. "."), nameOf(e.userId), fmt(e.score))
				r.TextColor3 = rowColor(i)
			else
				r.Text = (i == 1 and #list == 0) and "Be the first on the board!" or ""
				r.TextColor3 = Color3.new(1, 1, 1)
			end
		end
		if not live then ui.rows[1].Text = "Last winners: " .. ui.rows[1].Text end
	else
		local lines = { "Break the most treasure during the weekend!", "🥇 30 lucky hatches + coins", "🥈 20 lucky hatches + coins",
			"🥉 15 lucky hatches + coins", "🏅 Top 10: 8 lucky hatches + coins", ("Everyone with %d+ points wins a prize too!"):format(MIN_POINTS), "", "" }
		for i = 1, 8 do ui.rows[i].Text = lines[i]; ui.rows[i].TextColor3 = i == 1 and GOLD or Color3.new(1, 1, 1) end
	end
end

---------------------------------------------------------------- prizes
local claiming = {}
local function prizeFor(rank, score)
	for _, p in ipairs(PRIZES) do if rank and rank <= p.rank then return p end end
	if score >= MIN_POINTS then return PLAY_PRIZE end
	return nil
end
local function islandMult(plr)
	local n = 0
	for _, v in ipairs(ISLANDS) do
		local ok, r = pcall(function() return _G.PlazaIslandUnlocked and _G.PlazaIslandUnlocked(plr, v) end)
		if ok and r then n += 1 end
	end
	return 2.5 ^ n
end
-- gives the prize for the last finished tournament, once
local function claim(plr)
	if claiming[plr] then return end
	local d = dataOf(plr)
	if not d then return end
	local live, week = state()
	local finished = live and (week - WEEK) or week
	d.Tournament = type(d.Tournament) == "table" and d.Tournament or {}
	if d.Tournament.claimed == finished then return end
	claiming[plr] = true
	local store = storeFor(finished)
	local okScore, score = false, nil
	if store then okScore, score = pcall(function() return store:GetAsync(tostring(plr.UserId)) end) end
	if not okScore then claiming[plr] = nil; return end -- DataStore trouble: try again next time
	score = tonumber(score) or 0
	local rank
	if score > 0 then
		local list = fetchTop(finished)
		if not list then claiming[plr] = nil; return end
		for i, e in ipairs(list) do if e.userId == plr.UserId then rank = i end end
	end
	d.Tournament.claimed = finished
	local prize = prizeFor(rank, score)
	if prize and plr.Parent then
		local coins = math.floor(prize.coins * islandMult(plr))
		d.Money = (d.Money or 0) + coins
		d.LuckRolls = (d.LuckRolls or 0) + prize.luck
		if rank == 1 then d.Tournament.champion = finished end
		if _G.PlazaSyncPlayer then _G.PlazaSyncPlayer(plr) end
		local place = rank and ("%s You finished #%d"):format(prize.label, rank) or "🎉 Thanks for playing"
		Notify:FireClient(plr, ("🏆 Weekend Tournament results! %s with %s points: +%d lucky hatches + %s coins!"):format(place, fmt(score), prize.luck, fmt(coins)))
		if rank and rank <= 10 and _G.PlazaAchievementEvent then task.spawn(_G.PlazaAchievementEvent, plr, "tournamentTop10") end
	end
	claiming[plr] = nil
end

---------------------------------------------------------------- players
local function onJoin(plr)
	local d = dataOf(plr)
	if not d then return end
	local live, week = state()
	if live then plr:SetAttribute("TournamentScore", tourneyOf(d, week).score or 0) end
	task.wait(8) -- after the join screen
	if not plr.Parent then return end
	if live then
		Notify:FireClient(plr, ("🏆 The Weekend Tournament is LIVE! Break treasure to earn points. You have %s."):format(fmt(tourneyOf(d, week).score or 0)))
	end
	claim(plr)
end
Players.PlayerAdded:Connect(onJoin)
for _, p in ipairs(Players:GetPlayers()) do task.spawn(onJoin, p) end
Players.PlayerRemoving:Connect(function(plr)
	flush(plr)
	pending[plr] = nil
	claiming[plr] = nil
end)
game:BindToClose(function()
	for plr in pairs(pending) do task.spawn(flush, plr) end
	task.wait(3)
end)

---------------------------------------------------------------- clock: board, start/end announcements, top list refresh
task.spawn(function()
	local wasLive, lastFetch = state(), 0
	while true do
		local live, week = state()
		if live ~= wasLive then
			if live then
				for _, p in ipairs(Players:GetPlayers()) do
					Notify:FireClient(p, "🏆 The WEEKEND TOURNAMENT has started! Break treasure for points. Bosses are worth 10! Top players win huge prizes!")
				end
			else
				for _, p in ipairs(Players:GetPlayers()) do task.spawn(flush, p) end
				for _, p in ipairs(Players:GetPlayers()) do Notify:FireClient(p, "🏆 The Weekend Tournament is over! Prizes arrive in a minute...") end
				task.delay(90, function() -- give every server time to send its last points
					for _, p in ipairs(Players:GetPlayers()) do task.spawn(claim, p) end
				end)
			end
			wasLive = live
		end
		if os.clock() - lastFetch > (live and 45 or 300) then
			lastFetch = os.clock()
			task.spawn(fetchTop, week)
		end
		pcall(drawBoard)
		task.wait(1)
	end
end)
