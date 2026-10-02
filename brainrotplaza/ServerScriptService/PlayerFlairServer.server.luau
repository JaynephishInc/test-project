-- PlayerFlairServer
-- Things everyone can SEE you've earned:
-- 1) Collections: discover every brainrot of a mutation (Normal, Gold, Diamond, ...) for a big reward and a
--    trail in that mutation's colours (you wear the trail of your best completed collection).
-- 2) Title over your head, from your progress: Rookie > Explorer > Treasure Pro > Brainrot Master > Plaza Legend
--    (Master Collector for all collections, Weekend Champion for the tournament winner), plus your rebirths.
-- 3) Rebirth aura: sparkles around you that get bigger and more colourful the more you rebirth.

local Players = game:GetService("Players")
local RS = game:GetService("ReplicatedStorage")

local remotes = RS:WaitForChild("BrainrotRemotes")
local Notify = remotes:WaitForChild("Notify")
local Catalog = require(RS:WaitForChild("BrainrotCatalog"))

local ORDER = { "Normal", "Gold", "Diamond", "Cosmic", "Lava", "Toxic", "Glitch" } -- worst to best
local COLLECTION = {
	Normal = { coins = 5000, luck = 10, colors = { Color3.fromRGB(150, 220, 255), Color3.fromRGB(255, 255, 255) } },
	Gold = { coins = 15000, luck = 12, colors = { Color3.fromRGB(255, 200, 60), Color3.fromRGB(255, 245, 170) } },
	Diamond = { coins = 40000, luck = 15, colors = { Color3.fromRGB(120, 220, 255), Color3.fromRGB(230, 255, 255) } },
	Cosmic = { coins = 100000, luck = 18, colors = { Color3.fromRGB(180, 120, 255), Color3.fromRGB(255, 120, 230) } },
	Lava = { coins = 250000, luck = 20, colors = { Color3.fromRGB(255, 110, 30), Color3.fromRGB(255, 220, 60) } },
	Toxic = { coins = 600000, luck = 25, colors = { Color3.fromRGB(150, 255, 60), Color3.fromRGB(230, 255, 120) } },
	Glitch = { coins = 1500000, luck = 30, colors = { Color3.fromRGB(255, 60, 220), Color3.fromRGB(25, 255, 239) } },
}
local TITLES = { -- achievements needed -> title
	{ at = 35, text = "👑 Plaza Legend", color = Color3.fromRGB(255, 210, 70) },
	{ at = 25, text = "💎 Brainrot Master", color = Color3.fromRGB(120, 220, 255) },
	{ at = 15, text = "⭐ Treasure Pro", color = Color3.fromRGB(255, 140, 220) },
	{ at = 6, text = "🧭 Explorer", color = Color3.fromRGB(150, 255, 120) },
	{ at = 0, text = "🐣 Rookie", color = Color3.fromRGB(230, 230, 240) },
}
local WEEK = 7 * 86400

-- every brainrot id of each mutation
local idsOf = {}
for _, e in ipairs(Catalog.Entries) do
	local v = e.variant or "Normal"
	idsOf[v] = idsOf[v] or {}
	table.insert(idsOf[v], e.id)
end

local function fmt(n) local s = tostring(math.floor(n)):reverse():gsub("(%d%d%d)", "%1,"):reverse() return (s:gsub("^,", "")) end
local function count(t) local n = 0; if type(t) == "table" then for _ in pairs(t) do n += 1 end end; return n end
local function flairOf(d)
	d.Flair = type(d.Flair) == "table" and d.Flair or {}
	d.Flair.collections = type(d.Flair.collections) == "table" and d.Flair.collections or {}
	return d.Flair
end

---------------------------------------------------------------- collections
local function checkCollections(plr, d)
	local flair = flairOf(d)
	local discovered = type(d.Discovered) == "table" and d.Discovered or {}
	local progress = {}
	for _, v in ipairs(ORDER) do
		local ids = idsOf[v]
		if ids and #ids > 0 then
			local have = 0
			for _, id in ipairs(ids) do if discovered[id] then have += 1 end end
			progress[v] = { have = have, total = #ids }
			if have >= #ids and not flair.collections[v] then
				flair.collections[v] = true
				local r = COLLECTION[v] or COLLECTION.Normal
				d.Money = (d.Money or 0) + r.coins
				d.LuckRolls = (d.LuckRolls or 0) + r.luck
				if _G.PlazaSyncPlayer then _G.PlazaSyncPlayer(plr) end
				Notify:FireClient(plr, ("📚 %s COLLECTION COMPLETE! +%s coins + %d lucky hatches + a %s trail!"):format(v:upper(), fmt(r.coins), r.luck, v))
				for _, p in ipairs(Players:GetPlayers()) do
					if p ~= plr then Notify:FireClient(p, ("📚 %s completed the %s collection!"):format(plr.DisplayName, v)) end
				end
			end
		end
	end
	-- for menus: { Gold = "12/20", ... }
	local text = {}
	for v, p in pairs(progress) do text[v] = p.have .. "/" .. p.total end
	plr:SetAttribute("CollectionProgress", game:GetService("HttpService"):JSONEncode(text))
end
local function bestCollection(d)
	local best
	for _, v in ipairs(ORDER) do if d.Flair and d.Flair.collections and d.Flair.collections[v] then best = v end end
	return best
end

---------------------------------------------------------------- title
local function isChampion(d)
	local t = type(d.Tournament) == "table" and d.Tournament
	-- the champion keeps the title for a week after their tournament ended
	return t and t.champion and os.time() - t.champion < WEEK + 30 * 3600
end
local function titleOf(d)
	if isChampion(d) then return "🏆 Weekend Champion", Color3.fromRGB(255, 210, 70) end
	local all = true
	for _, v in ipairs(ORDER) do if idsOf[v] and not (d.Flair and d.Flair.collections[v]) then all = false end end
	if all then return "📚 Master Collector", Color3.fromRGB(255, 120, 230) end
	local achievements = count(d.Achievements)
	for _, t in ipairs(TITLES) do if achievements >= t.at then return t.text, t.color end end
	return TITLES[#TITLES].text, TITLES[#TITLES].color
end

---------------------------------------------------------------- what goes on the character
local function rainbow()
	return ColorSequence.new({
		ColorSequenceKeypoint.new(0, Color3.fromRGB(255, 80, 80)), ColorSequenceKeypoint.new(0.25, Color3.fromRGB(255, 220, 60)),
		ColorSequenceKeypoint.new(0.5, Color3.fromRGB(90, 255, 120)), ColorSequenceKeypoint.new(0.75, Color3.fromRGB(80, 170, 255)),
		ColorSequenceKeypoint.new(1, Color3.fromRGB(220, 90, 255)),
	})
end
local function applyTitle(char, text, color, rebirths)
	local head = char:FindFirstChild("Head") or char:FindFirstChild("HumanoidRootPart")
	if not head then return end
	local gui = head:FindFirstChild("PlazaTitle")
	if not gui then
		gui = Instance.new("BillboardGui"); gui.Name = "PlazaTitle"; gui.Size = UDim2.fromOffset(190, 46)
		gui.StudsOffset = Vector3.new(0, 3.3, 0); gui.MaxDistance = 70; gui.LightInfluence = 0
		local title = Instance.new("TextLabel"); title.Name = "Title"; title.BackgroundTransparency = 1; title.Size = UDim2.fromScale(1, 0.6)
		title.Font = Enum.Font.FredokaOne; title.TextScaled = true; title.Parent = gui
		local s1 = Instance.new("UIStroke"); s1.Thickness = 2; s1.Color = Color3.fromRGB(15, 12, 28); s1.Parent = title
		local sub = Instance.new("TextLabel"); sub.Name = "Rebirths"; sub.BackgroundTransparency = 1; sub.Position = UDim2.fromScale(0, 0.6)
		sub.Size = UDim2.fromScale(1, 0.4); sub.Font = Enum.Font.GothamBold; sub.TextScaled = true; sub.TextColor3 = Color3.fromRGB(120, 235, 255); sub.Parent = gui
		local s2 = Instance.new("UIStroke"); s2.Thickness = 1.5; s2.Color = Color3.fromRGB(15, 12, 28); s2.Parent = sub
		gui.Parent = head
	end
	gui.Title.Text = text
	gui.Title.TextColor3 = color
	gui.Rebirths.Text = rebirths > 0 and ("🔁 Rebirth " .. rebirths) or ""
end
local function applyTrail(char, variant)
	local hrp = char:FindFirstChild("HumanoidRootPart")
	if not hrp then return end
	local old = hrp:FindFirstChild("CollectionTrail")
	if not variant then if old then old:Destroy() end return end
	if old and old:GetAttribute("Variant") == variant then return end
	if old then old:Destroy() end
	local holder = Instance.new("Folder"); holder.Name = "CollectionTrail"; holder:SetAttribute("Variant", variant)
	local a0 = Instance.new("Attachment"); a0.Name = "TrailTop"; a0.Position = Vector3.new(0, 0.9, 0.3); a0.Parent = hrp
	local a1 = Instance.new("Attachment"); a1.Name = "TrailBottom"; a1.Position = Vector3.new(0, -1.1, 0.3); a1.Parent = hrp
	local trail = Instance.new("Trail"); trail.Attachment0 = a0; trail.Attachment1 = a1
	local c = (COLLECTION[variant] or COLLECTION.Normal).colors
	trail.Color = variant == "Glitch" and rainbow() or ColorSequence.new(c[1], c[2])
	trail.Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.15), NumberSequenceKeypoint.new(1, 1) })
	trail.Lifetime = 0.45; trail.MinLength = 0.1; trail.LightEmission = 0.6; trail.FaceCamera = true
	trail.WidthScale = NumberSequence.new({ NumberSequenceKeypoint.new(0, 1), NumberSequenceKeypoint.new(1, 0.2) })
	trail.Parent = holder
	-- the attachments are cleaned up with the folder
	holder.Destroying:Connect(function() a0:Destroy(); a1:Destroy() end)
	holder.Parent = hrp
end
local function applyAura(char, rebirths)
	local hrp = char:FindFirstChild("HumanoidRootPart")
	if not hrp then return end
	local aura = hrp:FindFirstChild("RebirthAura")
	if rebirths <= 0 then if aura then aura:Destroy() end return end
	local tier = rebirths >= 10 and 3 or rebirths >= 5 and 2 or 1
	if aura and aura:GetAttribute("Tier") == tier and aura:GetAttribute("Rebirths") == rebirths then return end
	if not aura then
		aura = Instance.new("ParticleEmitter"); aura.Name = "RebirthAura"
		aura.LightEmission = 1; aura.SpreadAngle = Vector2.new(180, 180); aura.Speed = NumberRange.new(0.4, 1.4)
		aura.Lifetime = NumberRange.new(0.9, 1.6); aura.Acceleration = Vector3.new(0, 1.5, 0)
		aura.Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.2), NumberSequenceKeypoint.new(1, 1) })
		aura.Parent = hrp
	end
	aura:SetAttribute("Tier", tier); aura:SetAttribute("Rebirths", rebirths)
	aura.Rate = 3 + math.min(rebirths, 15)
	aura.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.18 + 0.08 * tier), NumberSequenceKeypoint.new(1, 0) })
	aura.Color = tier == 3 and rainbow() or tier == 2 and ColorSequence.new(Color3.fromRGB(190, 120, 255), Color3.fromRGB(255, 150, 240))
		or ColorSequence.new(Color3.fromRGB(110, 230, 255), Color3.new(1, 1, 1))
end

---------------------------------------------------------------- refresh loop
local lastKey = {}
local function refresh(plr)
	local d = _G.PlazaGetData and _G.PlazaGetData(plr)
	local char = plr.Character
	if not d or not char then return end
	checkCollections(plr, d)
	local title, color = titleOf(d)
	local rebirths = d.Rebirths or 0
	local trail = bestCollection(d)
	local key = table.concat({ title, rebirths, trail or "" }, "|")
	local head = char:FindFirstChild("Head") or char:FindFirstChild("HumanoidRootPart")
	if lastKey[plr] == key and head and head:FindFirstChild("PlazaTitle") then return end
	lastKey[plr] = key
	applyTitle(char, title, color, rebirths)
	applyTrail(char, trail)
	applyAura(char, rebirths)
end
local function hook(plr)
	plr.CharacterAdded:Connect(function(char)
		char:WaitForChild("HumanoidRootPart", 10)
		lastKey[plr] = nil
		task.wait(0.5)
		pcall(refresh, plr)
	end)
end
Players.PlayerAdded:Connect(hook)
for _, plr in ipairs(Players:GetPlayers()) do hook(plr) end
Players.PlayerRemoving:Connect(function(plr) lastKey[plr] = nil end)
task.spawn(function()
	while true do
		task.wait(4)
		for _, plr in ipairs(Players:GetPlayers()) do
			local ok, err = pcall(refresh, plr)
			if not ok then warn("PlayerFlairServer:", err) end
		end
	end
end)
