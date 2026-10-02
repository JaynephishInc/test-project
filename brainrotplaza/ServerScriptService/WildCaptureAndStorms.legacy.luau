-- WildCaptureAndStorms
-- 1) Wild brainrot captures: everyone who helped defeat a wild brainrot rolls a chance to catch that exact
--    brainrot (species + mutation, from its CatalogId). Rarer brainrots are harder to catch.
-- 2) Brainrot Storms: every 25-40 minutes the sky turns stormy for 3 minutes. During a storm all coins are
--    doubled, catch chances are tripled, and everyone online gets 3 lucky hatches when it starts.
-- Testing (server): ServerStorage.PlazaTestHooks.StartStorm:Invoke()

local Players = game:GetService("Players")
local RS = game:GetService("ReplicatedStorage")
local SS = game:GetService("ServerStorage")

local remotes = RS:WaitForChild("BrainrotRemotes")
local Notify = remotes:WaitForChild("Notify")
local Inventory = require(SS:WaitForChild("BrainrotInventoryRules"))
local Catalog = require(RS:WaitForChild("BrainrotCatalog"))
local function remote(name)
	local r = remotes:FindFirstChild(name) or Instance.new("RemoteEvent")
	r.Name = name; r.Parent = remotes
	return r
end
local WildCaught = remote("WildCaught")
local StormEvent = remote("StormEvent")

local CATCH = { Common = 0.12, Rare = 0.08, Epic = 0.05, Legendary = 0.03, Mythic = 0.015, ["Brainrot God"] = 0.008, Secret = 0.004, OG = 0.002, Unrated = 0.05 }
local STORM = { FirstDelay = { 420, 900 }, Every = { 1500, 2400 }, Duration = 180, CatchMult = 3, LuckyHatches = 3 }
local stormActive = false

---------------------------------------------------------------- captures
local function grant(plr, id, model)
	local d = _G.PlazaGetData and _G.PlazaGetData(plr)
	local entry = Catalog.ById[id]
	if not d or not entry then return end
	local cap = plr:GetAttribute("InventoryCapacity") or 25
	local label = (entry.variant and entry.variant ~= "Normal" and (entry.variant .. " ") or "") .. entry.name
	if not Inventory.Add(d.Collection, id, cap) then
		Notify:FireClient(plr, ("🎒 Your backpack is full, so the wild %s got away! Sell some brainrots at the market."):format(label))
		return
	end
	if type(d.Discovered) ~= "table" then d.Discovered = {} end
	local isNew = not d.Discovered[id]
	d.Discovered[id] = true
	if _G.PlazaSyncPlayer then _G.PlazaSyncPlayer(plr) end
	if _G.PlazaSyncIndex then pcall(_G.PlazaSyncIndex, plr, d) end
	Notify:FireClient(plr, ("🎯 You caught a wild %s!%s"):format(label, isNew and " (NEW in your Index!)" or ""))
	if _G.PlazaAchievementEvent then task.spawn(_G.PlazaAchievementEvent, plr, "catch", id) end
	WildCaught:FireClient(plr, { id = id, name = entry.name, variant = entry.variant, rarity = entry.rarity, isNew = isNew, pos = model:GetPivot().Position })
end

_G.PlazaOnBroken = function(model, ledger)
	if not model:GetAttribute("IsWildBrainrot") or type(ledger) ~= "table" then return end
	local id = model:GetAttribute("CatalogId")
	if not id or not Catalog.ById[id] then return end
	local chance = math.min(0.9, (CATCH[model:GetAttribute("Rarity")] or 0.05) * (stormActive and STORM.CatchMult or 1))
	for plr, dmg in pairs(ledger) do
		if typeof(plr) == "Instance" and plr.Parent and (dmg or 0) > 0 and math.random() < chance then
			grant(plr, id, model)
		end
	end
end

---------------------------------------------------------------- storms
local function startStorm()
	if stormActive then return false end
	stormActive = true
	_G.PlazaStormActive = true
	local endsAt = os.time() + STORM.Duration
	RS:SetAttribute("StormEndsAt", endsAt)
	StormEvent:FireAllClients("start", { endsAt = endsAt, catchMult = STORM.CatchMult, luck = STORM.LuckyHatches })
	for _, plr in ipairs(Players:GetPlayers()) do
		local d = _G.PlazaGetData and _G.PlazaGetData(plr)
		if d then
			d.LuckRolls = (d.LuckRolls or 0) + STORM.LuckyHatches
			if _G.PlazaSyncPlayer then _G.PlazaSyncPlayer(plr) end
		end
		Notify:FireClient(plr, ("⛈️ BRAINROT STORM! 2x coins, %dx wild catch chance, and your next %d hatches are lucky!"):format(STORM.CatchMult, STORM.LuckyHatches))
	end
	task.delay(STORM.Duration, function()
		stormActive = false
		_G.PlazaStormActive = false
		RS:SetAttribute("StormEndsAt", nil)
		StormEvent:FireAllClients("end", {})
		for _, plr in ipairs(Players:GetPlayers()) do Notify:FireClient(plr, "🌤️ The storm has passed. See you at the next one!") end
	end)
	return true
end

local hooks = SS:FindFirstChild("PlazaTestHooks") or Instance.new("Folder")
hooks.Name = "PlazaTestHooks"; hooks.Parent = SS
local startHook = hooks:FindFirstChild("StartStorm") or Instance.new("BindableFunction")
startHook.Name = "StartStorm"; startHook.OnInvoke = startStorm; startHook.Parent = hooks

task.spawn(function()
	task.wait(math.random(STORM.FirstDelay[1], STORM.FirstDelay[2]))
	while true do
		while RS:GetAttribute("VaultEventIsland") do task.wait(10) end -- let a giant vault event finish first
		if #Players:GetPlayers() > 0 then pcall(startStorm) end
		task.wait(math.random(STORM.Every[1], STORM.Every[2]))
	end
end)
