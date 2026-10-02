-- IslandBossServer
-- A huge themed brainrot boss roams every mutation island. When it spots you it gets angry (aggro),
-- charges, rears up (wind-up) and slams: anyone in range gets knocked flying back a few metres
-- (the flight itself is played by IslandBossClient on the hit player's own character, which also draws the
-- danger ring during the wind-up, the shockwave, roars and camera shake).
-- Bosses live in the Breakables folder, so squads can fight them like any treasure; the reward pool is
-- shared by everyone who helped (70% by damage, 30% equally). Defeated bosses come back after 4 minutes.
-- The server only moves the invisible Hitbox (and the BossCF attribute); clients draw the body smoothly.

local Players = game:GetService("Players")
local RS = game:GetService("ReplicatedStorage")

local CONFIG = {
	Height = 22, -- studs
	RoamSpeed = 7, ChaseSpeed = 17, -- players walk at 16 (boots make you faster)
	SenseRange = 24, -- notices you from any side this close
	SightRange = 62, -- notices you in front of it this far away
	GiveUpRange = 95, ChaseTime = 14, -- stops chasing
	AttackRange = 13, WindUp = 0.8, Recover = 2.2,
	KnockH = 42, KnockV = 58, -- knockback velocity (about 20 studs of flight)
	HealthMult = 8, RewardMult = 6, -- x the island's vault
	Respawn = 240,
	Bounds = 170, -- roams this far from the island centre
	Tick = 0.1,
}
local ORDER = { "Gold", "Diamond", "Cosmic", "Lava", "Toxic", "Glitch" }
local RANK = { Secret = 1, ["Brainrot God"] = 2, OG = 3, Mythic = 4, Legendary = 5 }

local remotes = RS:WaitForChild("BrainrotRemotes")
local Notify = remotes:WaitForChild("Notify")
local BossHit = remotes:FindFirstChild("BossHit") or Instance.new("RemoteEvent")
BossHit.Name = "BossHit"; BossHit.Parent = remotes
local folder = workspace:WaitForChild("PiazzaBrainrot"):WaitForChild("Breakables")
local islands = workspace:WaitForChild("MutationIslands")
local previews = RS:WaitForChild("BrainrotPreviews")

local rng = Random.new()
local function flat(v) return Vector3.new(v.X, 0, v.Z) end
local rayParams = RaycastParams.new()
rayParams.FilterType = Enum.RaycastFilterType.Exclude
local function groundAt(x, z, fallback)
	local ex = { folder }
	for _, p in ipairs(Players:GetPlayers()) do if p.Character then table.insert(ex, p.Character) end end
	rayParams.FilterDescendantsInstances = ex
	local r = workspace:Raycast(Vector3.new(x, 120, z), Vector3.new(0, -240, 0), rayParams)
	return r and r.Position.Y or fallback
end
local function worldBox(model)
	local lo, hi = Vector3.one * math.huge, -Vector3.one * math.huge
	for _, p in ipairs(model:GetDescendants()) do
		if p:IsA("BasePart") then
			local cf, h = p.CFrame, p.Size / 2
			for sx = -1, 1, 2 do for sy = -1, 1, 2 do for sz = -1, 1, 2 do
				local w = cf:PointToWorldSpace(Vector3.new(h.X * sx, h.Y * sy, h.Z * sz)); lo = lo:Min(w); hi = hi:Max(w)
			end end end
		end
	end
	return lo, hi
end

local function pickSpecies(variant)
	local best, bestRank
	for _, m in ipairs(previews:GetChildren()) do
		if m:IsA("Model") and m:GetAttribute("Variant") == variant then
			local r = RANK[m:GetAttribute("Rarity")] or 9
			local key = r * 1000 + (string.byte(m.Name, -1) or 0)
			if not bestRank or key < bestRank then best, bestRank = m, key end
		end
	end
	return best
end

local bosses = {}

local function build(variant)
	local isl = islands:FindFirstChild(variant .. " Island")
	local template = pickSpecies(variant)
	if not (isl and template) then warn("IslandBossServer: no island/species for", variant) return end
	local icf = isl:GetBoundingBox()
	local center = Vector3.new(icf.X, 0, icf.Z)
	local vault = folder:FindFirstChild("Island_" .. variant .. "_Vault")
	local baseHP = vault and vault:GetAttribute("MaxHealth") or 50000
	local baseReward = vault and (vault:GetAttribute("RewardPool") or vault:GetAttribute("Reward")) or baseHP
	local name = template:GetAttribute("BrainrotName") or template.Name

	local old = folder:FindFirstChild("IslandBoss_" .. variant); if old then old:Destroy() end
	local model = Instance.new("Model"); model.Name = "IslandBoss_" .. variant
	-- the body: an upright copy of the preview (keep the preview's own pivot turn, add our facing)
	local body = template:Clone(); body.Name = "Body"
	for _, d in ipairs(body:GetDescendants()) do
		if d:IsA("LuaSourceContainer") or d:IsA("ProximityPrompt") or d:IsA("ClickDetector") or d:IsA("BillboardGui") then d:Destroy()
		elseif d:IsA("BasePart") then d.Anchored = true; d.CanCollide = false; d.CanQuery = false; d.CanTouch = false end
	end
	body.Parent = model
	local home = center + Vector3.new(0, 0, 0)
	local yaw = CFrame.Angles(0, rng:NextNumber() * math.pi * 2, 0)
	body:PivotTo(CFrame.new(home + Vector3.new(0, 200, 0)) * yaw * template:GetPivot().Rotation)
	local lo, hi = worldBox(body)
	body:ScaleTo(body:GetScale() * CONFIG.Height / math.max(0.1, hi.Y - lo.Y))
	lo, hi = worldBox(body)
	local gy = groundAt(home.X, home.Z, 1.3)
	body:PivotTo(body:GetPivot() + Vector3.new(home.X - (lo.X + hi.X) / 2, gy - lo.Y, home.Z - (lo.Z + hi.Z) / 2))
	lo, hi = worldBox(body)
	local size = hi - lo
	-- hitbox: what gets clicked, carries the health bar, and is what the server moves around
	local hit = Instance.new("Part")
	hit.Name = "Hitbox"; hit.Anchored = true; hit.CanCollide = false; hit.CanTouch = false; hit.CanQuery = true; hit.Transparency = 1
	hit.Size = Vector3.new(math.max(size.X, size.Z) * 0.75, size.Y * 0.9, math.max(size.X, size.Z) * 0.75)
	local hitCF = CFrame.new((lo + hi) / 2) * yaw
	hit.CFrame = hitCF; hit.Parent = model
	local click = Instance.new("ClickDetector"); click.MaxActivationDistance = 120; click.Parent = hit
	local prompt = Instance.new("ProximityPrompt"); prompt.Name = "FightPrompt"; prompt.ActionText = "Fight"; prompt.ObjectText = "👑 " .. name
	prompt.HoldDuration = 0; prompt.MaxActivationDistance = 30; prompt.RequiresLineOfSight = false; prompt.Parent = hit
	local bb = vault and vault:FindFirstChild("BreakableBillboard")
	if bb then local c = bb:Clone(); for _, x in ipairs(c:GetChildren()) do x:Destroy() end; c.Adornee = hit; c.Parent = model end
	model.PrimaryPart = hit
	model.ModelStreamingMode = Enum.ModelStreamingMode.Atomic -- body + hitbox arrive together (IslandBossClient needs both)
	for k, v in pairs({
		IsBoss = true, BreakableType = "Boss", DisplayName = "👑 " .. name:upper(), Variant = variant, Rarity = template:GetAttribute("Rarity"),
		MaxHealth = math.floor(baseHP * CONFIG.HealthMult), RewardPool = math.floor(baseReward * CONFIG.RewardMult), EqualSplit = 0.3,
		RespawnTime = CONFIG.Respawn, BarOffset = size.Y * 0.5 + 4, BarShowDistance = 120, FXColor = Color3.fromRGB(255, 80, 80),
		BossHome = hitCF, BossCF = hitCF, BossState = "roam",
		-- for the clients: size of the boss, danger ring, wind-up time, and where squads stand when attacking it
		BossHalfHeight = size.Y / 2, SlamRadius = CONFIG.AttackRange + 3, WindUp = CONFIG.WindUp,
		AttackRadius = math.max(size.X, size.Z) * 0.42 + 3, AttackY = 3.5 - size.Y / 2,
	}) do model:SetAttribute(k, v) end
	model.Parent = folder
	bosses[variant] = {
		model = model, hit = hit, center = center, home = hitCF, halfH = (hitCF.Position.Y - gy), name = name,
		pos = flat(hitCF.Position), yaw = math.atan2(-hitCF.LookVector.X, -hitCF.LookVector.Z), state = "roam", waypoint = nil, waitUntil = 0,
		target = nil, chaseStart = 0, stateT = 0, hitCooldown = {},
	}
end

---------------------------------------------------------------- brain
local function onIsland(b, pos)
	return math.abs(pos.X - b.center.X) < 240 and math.abs(pos.Z - b.center.Z) < 240
end
local function clampToBounds(b, p)
	local r = CONFIG.Bounds
	return Vector3.new(math.clamp(p.X, b.center.X - r, b.center.X + r), 0, math.clamp(p.Z, b.center.Z - r, b.center.Z + r))
end
local function facing(b) return Vector3.new(-math.sin(b.yaw), 0, -math.cos(b.yaw)) end
local function turnTo(b, dir, dt, rate)
	if dir.Magnitude < 0.01 then return end
	local want = math.atan2(-dir.X, -dir.Z)
	local d = (want - b.yaw + math.pi) % (2 * math.pi) - math.pi
	b.yaw += d * math.min(1, dt * (rate or 4))
end
local function moveToward(b, goal, speed, dt)
	local d = flat(goal - b.pos)
	local dist = d.Magnitude
	if dist < 0.5 then return true end
	turnTo(b, d, dt, 5)
	local step = math.min(dist, speed * dt)
	b.pos = clampToBounds(b, b.pos + d.Unit * step)
	return false
end
local function setState(b, s) b.state = s; b.stateT = os.clock(); b.model:SetAttribute("BossState", s) end
local function findTarget(b)
	local best, bd
	local fwd = facing(b)
	for _, p in ipairs(Players:GetPlayers()) do
		local char = p.Character
		local hrp = char and char:FindFirstChild("HumanoidRootPart")
		local hum = char and char:FindFirstChildOfClass("Humanoid")
		if hrp and hum and hum.Health > 0 and onIsland(b, hrp.Position) then
			local off = flat(hrp.Position - b.pos)
			local d = off.Magnitude
			local sees = d < CONFIG.SenseRange or (d < CONFIG.SightRange and d > 0 and off.Unit:Dot(fwd) > 0.3)
			if sees and (not bd or d < bd) then best, bd = p, d end
		end
	end
	return best
end

local function slam(b)
	local now = os.clock()
	for _, p in ipairs(Players:GetPlayers()) do
		local hrp = p.Character and p.Character:FindFirstChild("HumanoidRootPart")
		if hrp and (not b.hitCooldown[p] or now > b.hitCooldown[p]) then
			local off = flat(hrp.Position - b.pos)
			if off.Magnitude < CONFIG.AttackRange + 3 and math.abs(hrp.Position.Y - (b.home.Position.Y - b.halfH)) < 18 then
				b.hitCooldown[p] = now + 2
				local dir = off.Magnitude > 0.1 and off.Unit or facing(b)
				BossHit:FireClient(p, { dir = dir, h = CONFIG.KnockH, v = CONFIG.KnockV, from = b.pos, name = b.name })
			end
		end
	end
end

local function step(b, dt)
	local m = b.model
	if not m.Parent then return end
	if m:GetAttribute("Active") == false then -- defeated: go home while invisible and wait for the respawn there
		if not b.down then
			b.down = true
			b.pos = flat(b.home.Position); b.target = nil; b.waypoint = nil; setState(b, "roam")
			local home = CFrame.new(b.pos.X, b.home.Position.Y, b.pos.Z) * CFrame.Angles(0, b.yaw, 0)
			b.hit.CFrame = home
			m:SetAttribute("BossCF", home)
		end
		return
	end
	if b.down then
		b.down = false
		b.waitUntil = os.clock() + 2 -- a moment to pop back in before it wanders off
	end
	local now = os.clock()
	if b.state == "roam" then
		local t = findTarget(b)
		if t then b.target = t; b.chaseStart = now; setState(b, "chase") end
		if b.state == "roam" then
			if now < b.waitUntil then
				-- idling: look around a little
				b.yaw += math.sin(now * 0.7) * dt * 0.4
			else
				if not b.waypoint then
					local r = CONFIG.Bounds
					b.waypoint = b.center + Vector3.new(rng:NextNumber(-r, r), 0, rng:NextNumber(-r, r))
				end
				if moveToward(b, b.waypoint, CONFIG.RoamSpeed, dt) then b.waypoint = nil; b.waitUntil = now + rng:NextNumber(2, 5) end
			end
		end
	elseif b.state == "chase" then
		local hrp = b.target and b.target.Parent and b.target.Character and b.target.Character:FindFirstChild("HumanoidRootPart")
		local d = hrp and flat(hrp.Position - b.pos).Magnitude
		if not hrp or not onIsland(b, hrp.Position) or d > CONFIG.GiveUpRange or now - b.chaseStart > CONFIG.ChaseTime then
			b.target = nil; b.waitUntil = now + 1.5; setState(b, "roam")
		elseif d <= CONFIG.AttackRange then
			setState(b, "windup")
		else
			moveToward(b, hrp.Position, CONFIG.ChaseSpeed, dt)
		end
	elseif b.state == "windup" then
		local hrp = b.target and b.target.Character and b.target.Character:FindFirstChild("HumanoidRootPart")
		if hrp then turnTo(b, flat(hrp.Position - b.pos), dt, 6) end
		if now - b.stateT >= CONFIG.WindUp then slam(b); setState(b, "slam") end
	elseif b.state == "slam" then
		if now - b.stateT >= 0.35 then setState(b, "recover") end
	elseif b.state == "recover" then
		if now - b.stateT >= CONFIG.Recover then
			local t = findTarget(b)
			if t then b.target = t; b.chaseStart = now; setState(b, "chase") else b.target = nil; setState(b, "roam") end
		end
	end
	-- move the hitbox (= what the clients draw the body around)
	local gy = b.home.Position.Y - b.halfH -- islands are flat: walk at the home ground height (no climbing onto trees)
	local cf = CFrame.new(b.pos.X, gy + b.halfH, b.pos.Z) * CFrame.Angles(0, b.yaw, 0)
	b.hit.CFrame = cf
	m:SetAttribute("BossCF", cf)
end

---------------------------------------------------------------- defeat: news + achievement
task.spawn(function()
	while not _G.PlazaOnBroken do task.wait(0.5) end
	local original = _G.PlazaOnBroken
	_G.PlazaOnBroken = function(model, ledger)
		if model:GetAttribute("IsBoss") and type(ledger) == "table" then
			local helpers = 0
			for plr in pairs(ledger) do
				if typeof(plr) == "Instance" and plr.Parent then
					helpers += 1
					if _G.PlazaAchievementEvent then task.spawn(_G.PlazaAchievementEvent, plr, "boss", model:GetAttribute("Variant")) end
				end
			end
			local msg = ("👑 The %s boss on %s Island was defeated by %d player%s! It returns in %d minutes."):format(
				tostring(model:GetAttribute("DisplayName")):gsub("^👑 ", ""), tostring(model:GetAttribute("Variant")), helpers, helpers == 1 and "" or "s", CONFIG.Respawn // 60)
			for _, p in ipairs(Players:GetPlayers()) do Notify:FireClient(p, msg) end
		end
		return original(model, ledger)
	end
end)

for _, v in ipairs(ORDER) do pcall(build, v) end
task.spawn(function()
	local last = os.clock()
	while true do
		task.wait(CONFIG.Tick)
		local now = os.clock()
		local dt = math.min(0.25, now - last); last = now
		for _, b in pairs(bosses) do
			local ok, err = pcall(step, b, dt)
			if not ok then warn("IslandBossServer:", err) end
		end
	end
end)
Players.PlayerRemoving:Connect(function(p) for _, b in pairs(bosses) do b.hitCooldown[p] = nil; if b.target == p then b.target = nil end end end)
