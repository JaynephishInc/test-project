-- IslandVaultEvent
-- Every so often a GIANT themed vault appears on one of the mutation islands. Everyone can help break it.
-- BreakableCoinSystem pays the pool out (70% by damage dealt, 30% split equally between everyone who helped)
-- and TreasureBreakClient plays the door swing + coin shower. If time runs out, helpers still get a
-- consolation share for the damage they dealt.
-- Testing: from the server command bar run  _G.StartIslandVaultEvent("Lava")

local Players = game:GetService("Players")
local RS = game:GetService("ReplicatedStorage")
local SS = game:GetService("ServerStorage")

local Balance = require(RS:WaitForChild("GameBalance"))
local CONFIG = Balance.VaultEvent
local ORDER = Balance.IslandOrder
local THEME = {
	Gold = Color3.fromRGB(255, 200, 60), Diamond = Color3.fromRGB(120, 220, 255), Cosmic = Color3.fromRGB(180, 120, 255),
	Lava = Color3.fromRGB(255, 110, 30), Toxic = Color3.fromRGB(150, 255, 60), Glitch = Color3.fromRGB(255, 60, 220),
}

local remotes = RS:WaitForChild("BrainrotRemotes")
local Notify = remotes:WaitForChild("Notify")
local VaultEvent = remotes:FindFirstChild("VaultEvent") or Instance.new("RemoteEvent")
VaultEvent.Name = "VaultEvent"
VaultEvent.Parent = remotes
local folder = workspace:WaitForChild("PiazzaBrainrot"):WaitForChild("Breakables")
local spots = SS:WaitForChild("IslandVaultSpots")
-- beacon + label live here; Persistent so everyone sees the beacon from anywhere on the map
local fxModel = workspace:FindFirstChild("IslandVaultEvent") or Instance.new("Model")
fxModel.Name = "IslandVaultEvent"
fxModel.ModelStreamingMode = Enum.ModelStreamingMode.Persistent
fxModel.Parent = workspace

local function fmt(n) local s = tostring(math.floor(n)):reverse():gsub("(%d%d%d)", "%1,"):reverse() return (s:gsub("^,", "")) end
local function canReach(plr, mut)
	if not _G.PlazaIslandUnlocked then return true end
	local ok, r = pcall(_G.PlazaIslandUnlocked, plr, mut)
	return ok and r == true
end
local function eligible()
	local list = {}
	for _, mut in ipairs(ORDER) do
		local n = 0
		for _, p in ipairs(Players:GetPlayers()) do if canReach(p, mut) then n += 1 end end
		if n > 0 and spots:FindFirstChild(mut) and folder:FindFirstChild("Island_" .. mut .. "_Vault") then table.insert(list, { mut = mut, n = n }) end
	end
	return list
end

local function buildVault(mut, reachable)
	local src = folder:FindFirstChild("Island_" .. mut .. "_Vault")
	local spot = spots[mut]
	local m = src:Clone()
	m.Name = "EventVault_" .. mut
	-- the source may be mid-break (hidden): restore how it normally looks
	for _, d in ipairs(m:GetDescendants()) do
		if d:IsA("BasePart") then
			local t = d:GetAttribute("BreakableTransparency")
			if t ~= nil then d.Transparency = t end
			d.CanQuery = d.Name == "Hitbox"
		elseif d:IsA("BillboardGui") or d:IsA("SurfaceGui") then d.Enabled = true
		elseif d:IsA("ParticleEmitter") or d:IsA("Light") then
			local e = d:GetAttribute("BreakableEnabled"); if e ~= nil then d.Enabled = e end
		end
	end
	-- Replace the old three hard rings before measuring or scaling the gameplay object.
	local oldAura = m:FindFirstChild("PremiumAura")
	if oldAura then oldAura:Destroy() end
	local oldHit = m:FindFirstChild("Hitbox")
	if oldHit then oldHit:Destroy() end
	m:ScaleTo(m:GetScale() * CONFIG.Scale)
	-- With old gameplay/decorative bounds removed, this is the true visible vault footprint.
	local visualCF, visualSize = m:GetBoundingBox()
	local lift = m:GetPivot().Position.Y - (visualCF.Position.Y - visualSize.Y / 2)
	m:PivotTo(CFrame.lookAt(spot.Position, spot.Position + spot.CFrame.LookVector) + Vector3.new(0, lift, 0))
	visualCF, visualSize = m:GetBoundingBox()

	-- The clickable volume follows the visible vault, with a forgiving front/depth margin.
	local hit = Instance.new("Part")
	hit.Name = "Hitbox"
	hit.Parent = m
	hit.Size = visualSize + CONFIG.HitboxPadding
	hit.CFrame = visualCF
	hit.Transparency = 1
	hit.Anchored = true
	hit.CanCollide = false
	hit.CanTouch = false
	hit.CanQuery = true
	hit.CastShadow = false
	local click = hit:FindFirstChildOfClass("ClickDetector") or Instance.new("ClickDetector")
	click.MaxActivationDistance = 120
	click.Parent = hit

	-- One soft pool of light reads more naturally than three sharp yellow outlines.
	local glow = Instance.new("Part")
	glow.Name = "NaturalGroundGlow"
	glow.Shape = Enum.PartType.Cylinder
	glow.Size = Vector3.new(0.08, visualSize.X * 1.45, visualSize.Z * 1.45)
	glow.CFrame = CFrame.new(visualCF.Position.X, spot.Position.Y + 0.06, visualCF.Position.Z) * CFrame.Angles(0, 0, math.pi / 2)
	glow.Color = THEME[mut] or Color3.fromRGB(255, 210, 70)
	glow.Material = Enum.Material.Neon
	glow.Transparency = CONFIG.GlowTransparency
	glow.Anchored = true
	glow.CanCollide = false
	glow.CanTouch = false
	glow.CanQuery = false
	glow.CastShadow = false
	glow.Parent = m
	local light = Instance.new("PointLight")
	light.Color = glow.Color
	light.Brightness = 1.1
	light.Range = math.max(18, visualSize.X * 0.85)
	light.Shadows = false
	light.Parent = glow

	local baseHP = src:GetAttribute("MaxHealth") or 10000
	local baseReward = src:GetAttribute("Reward") or baseHP
	local hp = math.floor(baseHP * (CONFIG.HealthMult + CONFIG.HealthPerExtra * math.max(0, reachable - 1)))
	for _, a in ipairs({ "SpreadCopy", "Health", "AttackPulse" }) do m:SetAttribute(a, nil) end
	m:SetAttribute("MaxHealth", hp)
	m:SetAttribute("Reward", hp)
	m:SetAttribute("RewardPool", math.floor(baseReward * CONFIG.RewardMult))
	m:SetAttribute("EqualSplit", CONFIG.EqualSplit)
	m:SetAttribute("OneShot", true)
	m:SetAttribute("EventVault", true)
	m:SetAttribute("RespawnTime", 999999)
	m:SetAttribute("DisplayName", "GIANT " .. mut:upper() .. " VAULT")
	m:SetAttribute("BarOffset", visualSize.Y * 0.5 + 4)
	m:SetAttribute("BarShowDistance", 90)
	m:SetAttribute("Active", true)
	return m, hp, math.floor(baseReward * CONFIG.RewardMult), visualSize
end

local function buildBeacon(mut, pos, height)
	local color = THEME[mut] or Color3.new(1, 1, 1)
	local beam = Instance.new("Part")
	beam.Name = "Beacon"; beam.Shape = Enum.PartType.Cylinder; beam.Material = Enum.Material.Neon; beam.Color = color
	beam.Anchored = true; beam.CanCollide = false; beam.CanQuery = false; beam.CanTouch = false; beam.CastShadow = false
	beam.Size = Vector3.new(420, 6, 6); beam.Transparency = 0.55
	beam.CFrame = CFrame.new(pos + Vector3.new(0, 210, 0)) * CFrame.Angles(0, 0, math.pi / 2)
	beam.Parent = fxModel
	local anchor = Instance.new("Part")
	anchor.Name = "LabelAnchor"; anchor.Transparency = 1; anchor.Size = Vector3.new(1, 1, 1)
	anchor.Anchored = true; anchor.CanCollide = false; anchor.CanQuery = false; anchor.CanTouch = false
	anchor.Position = pos + Vector3.new(0, height + 16, 0)
	anchor.Parent = fxModel
	local g = Instance.new("BillboardGui")
	g.Name = "EventLabel"; g.AlwaysOnTop = true; g.LightInfluence = 0; g.MaxDistance = 1400; g.Size = UDim2.fromOffset(340, 86); g.Parent = anchor
	local f = Instance.new("Frame"); f.Size = UDim2.fromScale(1, 1); f.BackgroundColor3 = Color3.fromRGB(16, 18, 30); f.BackgroundTransparency = 0.15; f.Parent = g
	Instance.new("UICorner", f).CornerRadius = UDim.new(0, 16)
	local st = Instance.new("UIStroke"); st.Color = color; st.Thickness = 3; st.Parent = f
	local title = Instance.new("TextLabel")
	title.Name = "Title"; title.BackgroundTransparency = 1; title.Size = UDim2.new(1, -16, 0.55, 0); title.Position = UDim2.fromOffset(8, 4)
	title.Font = Enum.Font.FredokaOne; title.TextScaled = true; title.TextColor3 = color; title.Text = "🏦 GIANT " .. mut:upper() .. " VAULT"; title.Parent = f
	local sub = Instance.new("TextLabel")
	sub.Name = "Sub"; sub.BackgroundTransparency = 1; sub.Size = UDim2.new(1, -16, 0.38, 0); sub.Position = UDim2.new(0, 8, 0.58, 0)
	sub.Font = Enum.Font.GothamBold; sub.TextScaled = true; sub.TextColor3 = Color3.new(1, 1, 1); sub.Text = ""; sub.Parent = f
	return sub
end

local running = false
local function runEvent(forced)
	if running then return false, "an event is already running" end
	local list = eligible()
	local pick
	if forced then
		for _, e in ipairs(list) do if e.mut == forced then pick = e end end
		if not pick and spots:FindFirstChild(forced) then pick = { mut = forced, n = math.max(1, #Players:GetPlayers()) } end
	else
		pick = list[math.random(1, math.max(1, #list))]
	end
	if not pick then return false, "no island anyone can reach" end
	running = true
	local mut = pick.mut
	local m, hp, pool, size = buildVault(mut, pick.n)
	local endsAt = os.time() + CONFIG.Duration
	m:SetAttribute("EndsAt", endsAt)
	m.Parent = folder
	local function paintStage()
		local stage=m:GetAttribute("VaultStage") or 1
		local names={"LOCKS","WEAK POINTS","DOOR CORE"}
		m:SetAttribute("DisplayName","GIANT "..mut:upper().." VAULT · "..names[stage])
		local glow=m:FindFirstChild("NaturalGroundGlow")
		if glow then
			glow.Transparency=stage==1 and .86 or (stage==2 and .78 or .68)
			local light=glow:FindFirstChildOfClass("PointLight");if light then light.Brightness=stage end
		end
		for _,part in ipairs(m:GetDescendants()) do
			if part:IsA("BasePart") and (part.Name:lower():find("lock") or part.Name:lower():find("handle")) then
				part.Material=Enum.Material.Neon
				part.Color=stage==1 and Color3.fromRGB(255,85,55) or (THEME[mut] or Color3.new(1,1,1))
			end
		end
	end
	paintStage();m:GetAttributeChangedSignal("VaultStage"):Connect(paintStage)
	local sub = buildBeacon(mut, spots[mut].Position, size.Y)
	RS:SetAttribute("VaultEventIsland", mut)
	RS:SetAttribute("VaultEventEndsAt", endsAt)
	VaultEvent:FireAllClients("start", { island = mut, endsAt = endsAt, pool = pool })
	for _, p in ipairs(Players:GetPlayers()) do
		if canReach(p, mut) then
			Notify:FireClient(p, ("🏦 A GIANT %s VAULT appeared on %s Island! Help crack it for a share of %s coins."):format(mut:upper(), mut, fmt(pool)))
		else
			Notify:FireClient(p, ("🏦 A GIANT %s VAULT appeared on %s Island! Unlock %s Island to join in."):format(mut:upper(), mut, mut))
		end
	end

	local cracked, lastLedger = false, {}
	while true do
		task.wait(1)
		if not m.Parent or m:GetAttribute("Active") == false then cracked = true break end
		local ledger = _G.PlazaBreakableLedger and _G.PlazaBreakableLedger(m)
		if ledger then lastLedger = table.clone(ledger) end
		local helpers = 0
		for plr in pairs(lastLedger) do if plr.Parent then helpers += 1 end end
		local left = math.max(0, endsAt - os.time())
		sub.Text = ("⏱ %d:%02d  ·  👥 %d helping  ·  ❤️ %s"):format(left // 60, left % 60, helpers, fmt(m:GetAttribute("Health") or hp))
		if left <= 0 then break end
	end

	local helpers, top, topDmg = 0, nil, 0
	for plr, dmg in pairs(lastLedger) do
		if plr.Parent then helpers += 1; if dmg > topDmg then top, topDmg = plr, dmg end end
	end
	if cracked then
		VaultEvent:FireAllClients("end", { island = mut, cracked = true, helpers = helpers, top = top and top.DisplayName or nil })
		local msg = ("💥 The Giant %s Vault was cracked by %d player%s!%s"):format(mut, helpers, helpers == 1 and "" or "s", top and (" Top hitter: " .. top.DisplayName) or "")
		for _, p in ipairs(Players:GetPlayers()) do Notify:FireClient(p, msg) end
	else
		-- time's up: consolation shares for the damage everyone dealt, then it fades away
		m:SetAttribute("Active", false)
		for plr, dmg in pairs(lastLedger) do
			if plr.Parent and _G.PlazaAwardMoney then
				local share = math.floor(pool * CONFIG.Consolation * math.clamp(dmg / hp, 0, 1))
				if share > 0 then
					local ok, paid = _G.PlazaAwardMoney(plr, share)
					if ok then Notify:FireClient(plr, ("⌛ The vault slipped away, but you kept +%s coins for your %d%% of the damage."):format(fmt(paid), math.floor(dmg / hp * 100 + 0.5))) end
				end
			end
		end
		VaultEvent:FireAllClients("end", { island = mut, cracked = false, helpers = helpers })
		for _, d in ipairs(m:GetDescendants()) do if d:IsA("BasePart") then d.Transparency = 1; d.CanQuery = false end end
		task.delay(1, function() if m.Parent then m:Destroy() end end)
	end
	RS:SetAttribute("VaultEventIsland", nil)
	RS:SetAttribute("VaultEventEndsAt", nil)
	fxModel:ClearAllChildren()
	running = false
	return true
end

_G.StartIslandVaultEvent = function(mut) -- for testing from the server command bar
	task.spawn(function()
		local ok, a, b = pcall(runEvent, mut)
		if not ok then warn("IslandVaultEvent:", a) elseif a == false then warn("IslandVaultEvent:", b) end
	end)
end

-- Admin/test hooks (server-only: clients can't reach ServerStorage)
--   ServerStorage.PlazaTestHooks.StartVaultEvent:Invoke("Lava")
--   ServerStorage.PlazaTestHooks.BreakNow:Invoke(breakableModel, player)
--   ServerStorage.PlazaTestHooks.GiveCoins:Invoke(player, amount)
local hooks = SS:FindFirstChild("PlazaTestHooks") or Instance.new("Folder")
hooks.Name = "PlazaTestHooks"
hooks.Parent = SS
local function hook(name, fn)
	local b = hooks:FindFirstChild(name) or Instance.new("BindableFunction")
	b.Name = name
	b.OnInvoke = fn
	b.Parent = hooks
end
hook("StartVaultEvent", function(mut) _G.StartIslandVaultEvent(mut) return true end)
hook("BreakNow", function(model, plr) if _G.PlazaBreakNow then _G.PlazaBreakNow(model, plr) return true end return false end)
hook("GiveCoins", function(plr, n) if _G.PlazaAwardMoney then return _G.PlazaAwardMoney(plr, n) end return false end)

task.spawn(function()
	task.wait(math.random(CONFIG.FirstDelay[1], CONFIG.FirstDelay[2]))
	while true do
		if #Players:GetPlayers() > 0 then
			while RS:GetAttribute("StormEndsAt") do task.wait(10) end -- wait for a Brainrot Storm to pass
			local ok, err = pcall(runEvent)
			if not ok then warn("IslandVaultEvent:", err); running = false end
		end
		task.wait(math.random(CONFIG.Every[1], CONFIG.Every[2]))
	end
end)
