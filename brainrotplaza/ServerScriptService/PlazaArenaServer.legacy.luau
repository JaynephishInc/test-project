-- Rarity arenas: plaza portals open an arena picker; entry needs an equipped brainrot of that rarity (or better).
-- In the arenas you get a Bonker for PvP; kills use the classic "creator" tag so streaks/bounties/tokens work.
local Players = game:GetService("Players")
local RS = game:GetService("ReplicatedStorage")
local CS = game:GetService("CollectionService")
local Debris = game:GetService("Debris")
local HttpService = game:GetService("HttpService")
local RollConfig = require(RS:WaitForChild("BrainrotRollConfig"))
local remotes = RS:WaitForChild("BrainrotRemotes")
local function remote(n) local r = remotes:FindFirstChild(n) or Instance.new("RemoteEvent"); r.Name = n; r.Parent = remotes; return r end
local EnterArena, OpenArenaPicker = remote("EnterArena"), remote("OpenArenaPicker")
local Notify = remotes:WaitForChild("Notify")

local arenas, info = {}, {}
for _, m in ipairs(CS:GetTagged("RarityArena")) do
	local r = m:GetAttribute("Rarity")
	local spawns = {}
	for _, sp in ipairs(m:GetChildren()) do if sp.Name == "ArenaSpawn" then table.insert(spawns, sp) end end
	arenas[r] = { model = m, rank = m:GetAttribute("Rank"), spawns = spawns }
end
for i, r in ipairs(RollConfig.RarityOrder) do
	local a = arenas[r]
	if a then
		local floor = a.model:FindFirstChild("Emblem")
		table.insert(info, { rarity = r, rank = r == "Unrated" and 1 or i, color = floor and floor.Color:ToHex() or "ffffff" })
		a.rank = r == "Unrated" and 1 or i
	end
end
local infoValue = remotes:FindFirstChild("ArenaInfo") or Instance.new("StringValue")
infoValue.Name = "ArenaInfo"; infoValue.Value = HttpService:JSONEncode(info); infoValue.Parent = remotes

local function hrpOf(plr) return plr.Character and plr.Character:FindFirstChild("HumanoidRootPart") end

EnterArena.OnServerEvent:Connect(function(plr, rarity)
	local a = type(rarity) == "string" and arenas[rarity]; if not a then return end
	local rank = plr:GetAttribute("EquippedRank") or 0
	if a.rank > 1 and rank < a.rank then
		Notify:FireClient(plr, ("🔒 Equip a %s (or rarer) brainrot to enter the %s Arena."):format(rarity, rarity)); return
	end
	local hrp = hrpOf(plr); if not hrp then return end
	local sp = a.spawns[math.random(1, #a.spawns)]
	hrp.CFrame = sp.CFrame + Vector3.new(0, 4, 0)
	Notify:FireClient(plr, ("⚔ Welcome to the %s Arena! Click to bonk. Walk into the green portal to go back."):format(rarity))
end)

-- plaza portals open the picker
local lastOpen = {}
for _, field in ipairs(CS:GetTagged("ArenaPortal")) do
	field.Touched:Connect(function(hit)
		local plr = Players:GetPlayerFromCharacter(hit.Parent); if not plr then return end
		if lastOpen[plr] and os.clock() - lastOpen[plr] < 3 then return end
		lastOpen[plr] = os.clock()
		OpenArenaPicker:FireClient(plr)
		local hrp = hrpOf(plr)
		if hrp then hrp.CFrame = hrp.CFrame - field.CFrame.LookVector * -0 + (Vector3.new(0, 0, 0) - Vector3.new(hrp.Position.X, 0, hrp.Position.Z)).Unit * 6 end
	end)
end
-- return portals
local plazaSpawn = workspace:WaitForChild("PiazzaBrainrot"):WaitForChild("SpawnLocation")
for _, field in ipairs(CS:GetTagged("ArenaReturn")) do
	field.Touched:Connect(function(hit)
		local plr = Players:GetPlayerFromCharacter(hit.Parent); if not plr then return end
		local hrp = hrpOf(plr); if hrp then hrp.CFrame = plazaSpawn.CFrame + Vector3.new(math.random(-4, 4), 5, math.random(-4, 4)) end
	end)
end

-- ===== Bonker tool =====
local function makeBonker()
	local tool = Instance.new("Tool"); tool.Name = "Bonker"; tool.RequiresHandle = true; tool.CanBeDropped = false
	tool.ToolTip = "Click to bonk!"; tool.GripPos = Vector3.new(0, -1.6, 0)
	local h = Instance.new("Part"); h.Name = "Handle"; h.Size = Vector3.new(0.6, 5, 0.6); h.Color = Color3.fromRGB(120,80,50); h.Material = Enum.Material.Wood
	h.CanCollide = false; h.Massless = true; h.Parent = tool
	local head = Instance.new("Part"); head.Name = "BonkHead"; head.Size = Vector3.new(1.6, 2, 1.6); head.Color = Color3.fromRGB(255,60,200); head.Material = Enum.Material.Neon
	head.CanCollide = false; head.Massless = true; head.CFrame = h.CFrame * CFrame.new(0, 2.6, 0); head.Parent = tool
	local w = Instance.new("WeldConstraint"); w.Part0 = h; w.Part1 = head; w.Parent = head
	return tool
end
local lastSwing = {}
local function hookTool(plr, tool)
	tool.Activated:Connect(function()
		local now = os.clock()
		if lastSwing[plr] and now - lastSwing[plr] < 0.45 then return end
		lastSwing[plr] = now
		if plr:GetAttribute("InSafeZone") then return end
		local hrp = hrpOf(plr); if not hrp then return end
		local power = plr:FindFirstChild("leaderstats") and plr.leaderstats:FindFirstChild("Power") and plr.leaderstats.Power.Value or 0
		local dmg = math.clamp(15 + math.floor(power / 250), 15, 45)
		for _, other in ipairs(Players:GetPlayers()) do
			if other ~= plr and not other:GetAttribute("InSafeZone") then
				local ohrp = hrpOf(other)
				local hum = other.Character and other.Character:FindFirstChildOfClass("Humanoid")
				if ohrp and hum and hum.Health > 0 then
					local off = ohrp.Position - hrp.Position
					if off.Magnitude <= 8 and hrp.CFrame.LookVector:Dot(off.Unit) > 0.25 then
						local old = hum:FindFirstChild("creator"); if old then old:Destroy() end
						local tag = Instance.new("ObjectValue"); tag.Name = "creator"; tag.Value = plr; tag.Parent = hum
						Debris:AddItem(tag, 3)
						hum:TakeDamage(dmg)
						ohrp.AssemblyLinearVelocity = off.Unit * 45 + Vector3.new(0, 25, 0)
					end
				end
			end
		end
	end)
end
task.spawn(function()
	while true do
		task.wait(0.5)
		for _, plr in ipairs(Players:GetPlayers()) do
			local char = plr.Character
			local hrp = char and char:FindFirstChild("HumanoidRootPart")
			if hrp then
				if hrp.Position.Y < -60 then local hum = char:FindFirstChildOfClass("Humanoid"); if hum then hum.Health = 0 end end
				local has = char:FindFirstChild("Bonker") or plr.Backpack:FindFirstChild("Bonker")
				local inArena = not plr:GetAttribute("InSafeZone")
				if inArena and not has then
					local t = makeBonker(); t.Parent = plr.Backpack; hookTool(plr, t)
				elseif not inArena and has then
					has:Destroy()
				end
			end
		end
	end
end)
