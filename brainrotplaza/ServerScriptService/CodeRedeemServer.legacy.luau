-- Redeem codes at the Code Tower.
-- Add a code by putting a line inside CODES. The name must be UPPERCASE. A code can give any mix of:
--   coins = 500       spins = 2       luck = 3   (lucky hatches)
-- Example:
--   SPINS2 = { spins = 2 },
--   LAUNCH = { coins = 1000, spins = 1 },
local CODES = {
}

local Players = game:GetService("Players")
local DSS = game:GetService("DataStoreService")
local HttpService = game:GetService("HttpService")

local okStore, store = pcall(function() return DSS:GetDataStore("PlazaCodes_v1") end)
if not okStore then store = nil end
local used = {}   -- player -> { [CODE] = true }, nil until loaded
local busy = {}

local function fmt(n) local s = tostring(math.floor(n)):reverse():gsub("(%d%d%d)", "%1,"):reverse() return (s:gsub("^,", "")) end
local function describe(r)
	local parts = {}
	if r.coins then table.insert(parts, "+" .. fmt(r.coins) .. " coins") end
	if r.spins then table.insert(parts, "+" .. r.spins .. (r.spins == 1 and " wheel spin" or " wheel spins")) end
	if r.luck then table.insert(parts, "+" .. r.luck .. " lucky hatches") end
	return table.concat(parts, ", ")
end

local function load(plr)
	if not store then used[plr] = used[plr] or {}; return true end
	for attempt = 1, 3 do
		local ok, v = pcall(function() return store:GetAsync("u" .. plr.UserId) end)
		if ok then
			used[plr] = type(v) == "table" and v or {}
			plr:SetAttribute("RedeemedCodes", HttpService:JSONEncode(used[plr]))
			return true
		end
		task.wait(attempt * 2)
	end
	return false -- try again the next time they redeem
end
Players.PlayerAdded:Connect(load)
for _, p in Players:GetPlayers() do task.spawn(load, p) end
Players.PlayerRemoving:Connect(function(p) used[p] = nil; busy[p] = nil end)

-- Marks the code as used in the DataStore. Returns true only if THIS call added it.
local function markUsed(plr, code)
	if not store then return true end
	local added = false
	local ok = pcall(function()
		store:UpdateAsync("u" .. plr.UserId, function(old)
			added = false
			old = type(old) == "table" and old or {}
			if old[code] then return nil end
			old[code] = true
			added = true
			return old
		end)
	end)
	return ok and added, ok
end

local remotes = game.ReplicatedStorage:WaitForChild("BrainrotRemotes")
local rf = remotes:FindFirstChild("RedeemCode") or Instance.new("RemoteFunction")
rf.Name = "RedeemCode"; rf.Parent = remotes
rf.OnServerInvoke = function(plr, code)
	if type(code) ~= "string" or #code > 40 then return false, "Invalid code" end
	code = code:upper():gsub("%s", "")
	local info = CODES[code]
	if not info then return false, "That code doesn't exist" end
	if busy[plr] then return false, "One sec..." end
	busy[plr] = true
	local ran, result, message = pcall(function()
		if not used[plr] and not load(plr) then return false, "Codes aren't working right now. Try again in a minute!" end
		if used[plr][code] then return false, "You already redeemed this code" end
		local d = _G.PlazaGetData and _G.PlazaGetData(plr)
		if not d then return false, "Still loading, try again" end
		local added, reached = markUsed(plr, code)
		if not reached then return false, "Codes aren't working right now. Try again in a minute!" end
		used[plr][code] = true
		plr:SetAttribute("RedeemedCodes", HttpService:JSONEncode(used[plr]))
		if not added then return false, "You already redeemed this code" end
		if info.coins then d.Money = (d.Money or 0) + info.coins end
		if info.spins then d.WheelSpins = (d.WheelSpins or 0) + info.spins end
		if info.luck then d.LuckRolls = (d.LuckRolls or 0) + info.luck end
		if _G.PlazaSyncPlayer then _G.PlazaSyncPlayer(plr) end
		return true, describe(info) .. "!"
	end)
	busy[plr] = nil
	if not ran then warn("CodeRedeemServer:", result) return false, "Something went wrong" end
	return result, message
end
