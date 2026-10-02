-- TreasureHuntServer
-- Golden Egg hunt: every 8-14 minutes a glowing Golden Egg hides at a random spot in the plaza or on an island
-- someone in the server has unlocked. Everyone who can get there is told where to look. After 2 minutes a hint
-- (which side of the area) and a beam of light appear. The first player to grab it wins a free hatch
-- (that island's mutation), lucky hatches and coins. If nobody finds it in 5 minutes it vanishes.
-- Testing (server): ServerStorage.PlazaTestHooks.StartEggHunt:Invoke()  or  :Invoke("Lava")

local Players = game:GetService("Players")
local RS = game:GetService("ReplicatedStorage")
local SS = game:GetService("ServerStorage")
local TweenService = game:GetService("TweenService")

local CONFIG = {
	FirstDelay = { 240, 480 }, Every = { 480, 840 },
	Lifetime = 300, HintAfter = 120,
	PlazaHalfSize = 215, IslandHalfSize = 170,
	PrizeLuck = 3, PrizeCoins = 1500, -- coins get every coin boost the player has
}
local GOLD = Color3.fromRGB(255, 205, 60)
local ISLANDS = { "Gold", "Diamond", "Cosmic", "Lava", "Toxic", "Glitch" }

local remotes = RS:WaitForChild("BrainrotRemotes")
local Notify = remotes:WaitForChild("Notify")
local okStyles, EggStyles = pcall(function() return require(RS:WaitForChild("PremiumEggStyles", 10)) end)
local rng = Random.new()

local function fmt(n) local s = tostring(math.floor(n)):reverse():gsub("(%d%d%d)", "%1,"):reverse() return (s:gsub("^,", "")) end
local function canReach(plr, variant)
	if not variant or not _G.PlazaIslandUnlocked then return true end
	local ok, r = pcall(_G.PlazaIslandUnlocked, plr, variant)
	return ok and r == true
end
local function tell(variant, text)
	for _, p in ipairs(Players:GetPlayers()) do if canReach(p, variant) then Notify:FireClient(p, text) end end
end

---------------------------------------------------------------- where it can hide
-- area = { name, variant (nil for the plaza), center, half }
local function areas()
	local list = { { name = "the Plaza", variant = nil, center = Vector3.zero, half = CONFIG.PlazaHalfSize } }
	local islands = workspace:FindFirstChild("MutationIslands")
	for _, v in ipairs(ISLANDS) do
		local isl = islands and islands:FindFirstChild(v .. " Island")
		local reachable = false
		for _, p in ipairs(Players:GetPlayers()) do if canReach(p, v) then reachable = true break end end
		if isl and reachable then
			local cf, size = isl:GetBoundingBox()
			local half = math.min(CONFIG.IslandHalfSize, math.min(size.X, size.Z) / 2 - 25)
			if half > 20 then table.insert(list, { name = v .. " Island", variant = v, center = Vector3.new(cf.X, 0, cf.Z), half = half }) end
		end
	end
	return list
end
local rayParams = RaycastParams.new(); rayParams.FilterType = Enum.RaycastFilterType.Exclude; rayParams.RespectCanCollide = true
local boxParams = OverlapParams.new(); boxParams.FilterType = Enum.RaycastFilterType.Exclude; boxParams.RespectCanCollide = true
local function ignored(withTerrain)
	local list = {}
	for _, n in ipairs({ "PlazaFollowers", "IslandEggs", "IslandVaultEvent", "IslandBossTimers", "GoldenEggHunt" }) do
		local f = workspace:FindFirstChild(n); if f then table.insert(list, f) end
	end
	local pb = workspace:FindFirstChild("PiazzaBrainrot")
	local br = pb and pb:FindFirstChild("Breakables"); if br then table.insert(list, br) end
	for _, p in ipairs(Players:GetPlayers()) do if p.Character then table.insert(list, p.Character) end end
	if withTerrain then table.insert(list, workspace.Terrain) end
	return list
end
local function groundAt(x, z)
	local list = ignored(false)
	-- skip invisible barriers/ceilings: keep looking below them for real ground
	for _ = 1, 5 do
		rayParams.FilterDescendantsInstances = list
		local hit = workspace:Raycast(Vector3.new(x, 250, z), Vector3.new(0, -500, 0), rayParams)
		if not hit or not hit.Instance:IsA("BasePart") or hit.Instance:IsA("Terrain") or hit.Instance.Transparency < 0.9 then return hit end
		table.insert(list, hit.Instance)
	end
	return nil
end
local function findSpot(area)
	local c, h = area.center, area.half
	-- the area's normal ground height = the most common height of 15 sample points (rooftops are the odd ones out)
	local heights = {}
	for _ = 1, 15 do
		local hit = groundAt(c.X + rng:NextNumber(-h, h), c.Z + rng:NextNumber(-h, h))
		if hit and hit.Normal.Y > 0.9 then table.insert(heights, hit.Position.Y) end
	end
	if #heights < 5 then return nil end
	table.sort(heights)
	local groundY = heights[math.ceil(#heights / 2)]
	for _ = 1, 60 do
		local hit = groundAt(c.X + rng:NextNumber(-h, h), c.Z + rng:NextNumber(-h, h))
		if hit and hit.Normal.Y > 0.9 and math.abs(hit.Position.Y - groundY) < 3 and hit.Material ~= Enum.Material.Water then
			boxParams.FilterDescendantsInstances = ignored(true)
			local blocked = workspace:GetPartBoundsInBox(CFrame.new(hit.Position + Vector3.new(0, 3.6, 0)), Vector3.new(6, 6.5, 6), boxParams)
			local nearPlayer = false
			for _, p in ipairs(Players:GetPlayers()) do
				local hrp = p.Character and p.Character:FindFirstChild("HumanoidRootPart")
				if hrp and (hrp.Position - hit.Position).Magnitude < 25 then nearPlayer = true end
			end
			if #blocked == 0 and not nearPlayer then return hit.Position end
		end
	end
	return nil
end
local function sideOf(area, pos)
	local off = pos - area.center
	if math.abs(off.X) < area.half * 0.3 and math.abs(off.Z) < area.half * 0.3 then return "near the middle" end
	if math.abs(off.X) > math.abs(off.Z) then return off.X > 0 and "on the east side" or "on the west side" end
	return off.Z > 0 and "on the south side" or "on the north side"
end

---------------------------------------------------------------- the egg
local folder = workspace:FindFirstChild("GoldenEggHunt") or Instance.new("Model")
folder.Name = "GoldenEggHunt"
folder.ModelStreamingMode = Enum.ModelStreamingMode.Persistent
folder.Parent = workspace
folder:ClearAllChildren()

local function buildEgg(pos)
	local m = Instance.new("Model"); m.Name = "GoldenEgg"
	local built = okStyles and pcall(function() EggStyles.Build(m, "Gold", CFrame.new(pos + Vector3.new(0, 3, 0))) end)
	if not built or #m:GetChildren() == 0 then
		m:ClearAllChildren()
		local shell = Instance.new("Part"); shell.Name = "Shell"; shell.Shape = Enum.PartType.Ball; shell.Size = Vector3.new(4, 5, 4)
		shell.Material = Enum.Material.Metal; shell.Color = GOLD; shell.Position = pos + Vector3.new(0, 2.5, 0); shell.Parent = m
	end
	for _, d in ipairs(m:GetDescendants()) do
		if d:IsA("BasePart") then d.Anchored = true; d.CanCollide = false; d.CanQuery = false; d.CanTouch = false end
	end
	-- sit it on the ground, about 5 studs tall
	local cf, size = m:GetBoundingBox()
	m.WorldPivot = cf
	if size.Y > 0 then pcall(function() m:ScaleTo(m:GetScale() * 5 / size.Y) end) end
	cf, size = m:GetBoundingBox()
	m:PivotTo(m:GetPivot() + Vector3.new(pos.X - cf.X, pos.Y - (cf.Y - size.Y / 2) + 0.2, pos.Z - cf.Z))
	cf, size = m:GetBoundingBox()

	local core = Instance.new("Part"); core.Name = "Core"; core.Transparency = 1; core.Size = Vector3.new(5, 5, 5)
	core.Anchored = true; core.CanCollide = false; core.CanTouch = false; core.CanQuery = false; core.CFrame = cf; core.Parent = m
	local light = Instance.new("PointLight"); light.Color = GOLD; light.Brightness = 3; light.Range = 22; light.Parent = core
	local sparkles = Instance.new("ParticleEmitter"); sparkles.Name = "Sparkles"; sparkles.Color = ColorSequence.new(GOLD, Color3.new(1, 1, 1))
	sparkles.LightEmission = 1; sparkles.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.5), NumberSequenceKeypoint.new(1, 0) })
	sparkles.Transparency = NumberSequence.new(0.1); sparkles.Lifetime = NumberRange.new(0.8, 1.4); sparkles.Rate = 14
	sparkles.Speed = NumberRange.new(2, 4); sparkles.SpreadAngle = Vector2.new(180, 180); sparkles.Parent = core
	local bb = Instance.new("BillboardGui"); bb.Size = UDim2.fromOffset(200, 50); bb.StudsOffset = Vector3.new(0, size.Y / 2 + 2.5, 0)
	bb.AlwaysOnTop = true; bb.MaxDistance = 90; bb.LightInfluence = 0; bb.Parent = core
	local t = Instance.new("TextLabel"); t.Size = UDim2.fromScale(1, 1); t.BackgroundTransparency = 1; t.TextScaled = true
	t.Font = Enum.Font.FredokaOne; t.TextColor3 = GOLD; t.Text = "✨ GOLDEN EGG ✨"; t.Parent = bb
	local st = Instance.new("UIStroke"); st.Thickness = 3; st.Color = Color3.fromRGB(90, 50, 0); st.Parent = t
	local prompt = Instance.new("ProximityPrompt"); prompt.ActionText = "Grab!"; prompt.ObjectText = "✨ Golden Egg"
	prompt.HoldDuration = 0.3; prompt.MaxActivationDistance = 12; prompt.RequiresLineOfSight = false; prompt.Parent = core
	m.Parent = folder
	return m, core, prompt
end
local function addBeam(core)
	local beam = Instance.new("Part"); beam.Name = "Beacon"; beam.Shape = Enum.PartType.Cylinder; beam.Material = Enum.Material.Neon
	beam.Color = GOLD; beam.Transparency = 0.6; beam.Size = Vector3.new(160, 3, 3)
	beam.Anchored = true; beam.CanCollide = false; beam.CanQuery = false; beam.CanTouch = false; beam.CastShadow = false
	beam.CFrame = CFrame.new(core.Position + Vector3.new(0, 80, 0)) * CFrame.Angles(0, 0, math.pi / 2)
	beam.Parent = core.Parent
end
local function poof(core)
	local burst = core:FindFirstChild("Sparkles")
	if burst then burst.Rate = 0; burst.Speed = NumberRange.new(10, 18); burst:Emit(80) end
	for _, d in ipairs(core.Parent:GetDescendants()) do
		if d:IsA("BasePart") and d ~= core then TweenService:Create(d, TweenInfo.new(0.5), { Transparency = 1 }):Play() end
	end
end

---------------------------------------------------------------- one hunt
local running = false
local function giveFirstPrize(plr, area)
	local hatched = _G.PlazaFreeHatch and _G.PlazaFreeHatch(plr, area.variant)
	local d = _G.PlazaGetData and _G.PlazaGetData(plr)
	if d then d.LuckRolls = (d.LuckRolls or 0) + CONFIG.PrizeLuck end
	local coins = CONFIG.PrizeCoins * (hatched and 1 or 3) -- a full backpack gets extra coins instead of the hatch
	local paid = 0
	if _G.PlazaAwardMoney then local ok, amount = _G.PlazaAwardMoney(plr, coins); paid = ok and amount or 0 end
	if _G.PlazaSyncPlayer then _G.PlazaSyncPlayer(plr) end
	local egg = area.variant and (area.variant .. " egg") or "egg"
	Notify:FireClient(plr, ("✨ You found the GOLDEN EGG! %s+%d lucky hatches + %s coins!"):format(
		hatched and ("Free " .. egg .. " hatch + ") or "Your backpack is full, so here's extra coins: ", CONFIG.PrizeLuck, fmt(paid)))
	if _G.PlazaAchievementEvent then task.spawn(_G.PlazaAchievementEvent, plr, "goldenEgg") end
end
local function runHunt(forcedVariant)
	if running or #Players:GetPlayers() == 0 then return false, "already running or nobody online" end
	local list = areas()
	local area
	if forcedVariant then
		for _, a in ipairs(list) do if a.variant == forcedVariant or (forcedVariant == "Plaza" and not a.variant) then area = a end end
	end
	area = area or list[rng:NextInteger(1, #list)]
	local pos = findSpot(area)
	if not pos then return false, "no free spot found in " .. area.name end
	running = true
	local m, core, prompt = buildEgg(pos)
	local found = false
	tell(area.variant, ("✨ A GOLDEN EGG is hiding somewhere in %s! First to find it wins a free hatch!"):format(area.name))
	prompt.Triggered:Connect(function(plr)
		if found or not canReach(plr, area.variant) then return end
		found = true
		prompt.Enabled = false
		giveFirstPrize(plr, area)
		for _, p in ipairs(Players:GetPlayers()) do
			if p ~= plr then Notify:FireClient(p, ("✨ %s found the Golden Egg in %s!"):format(plr.DisplayName, area.name)) end
		end
	end)
	local started = os.clock()
	local hinted = false
	while not found and os.clock() - started < CONFIG.Lifetime do
		if not hinted and os.clock() - started >= CONFIG.HintAfter then
			hinted = true
			addBeam(core)
			tell(area.variant, ("✨ Hint: the Golden Egg is %s of %s. Look for the golden light!"):format(sideOf(area, pos), area.name))
		end
		task.wait(1)
	end
	if not found then
		prompt.Enabled = false
		tell(area.variant, "✨ The Golden Egg vanished... watch out for the next one!")
	end
	poof(core)
	task.wait(1.5)
	m:Destroy()
	running = false
	return true
end

---------------------------------------------------------------- schedule + test hook
local hooks = SS:FindFirstChild("PlazaTestHooks") or Instance.new("Folder")
hooks.Name = "PlazaTestHooks"; hooks.Parent = SS
local hook = hooks:FindFirstChild("StartEggHunt") or Instance.new("BindableFunction")
hook.Name = "StartEggHunt"; hook.Parent = hooks
hook.OnInvoke = function(variant)
	task.spawn(function()
		local ok, a, b = pcall(runHunt, variant)
		if not ok then warn("TreasureHuntServer:", a) elseif a == false then warn("TreasureHuntServer:", b) end
	end)
	return true
end

task.spawn(function()
	task.wait(rng:NextInteger(CONFIG.FirstDelay[1], CONFIG.FirstDelay[2]))
	while true do
		local ok, err = pcall(runHunt)
		if not ok then warn("TreasureHuntServer:", err); running = false end
		task.wait(rng:NextInteger(CONFIG.Every[1], CONFIG.Every[2]))
	end
end)
