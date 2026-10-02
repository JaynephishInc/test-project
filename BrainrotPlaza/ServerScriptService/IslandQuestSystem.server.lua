-- IslandQuestSystem: gate-side quest givers, persistent objectives and fusion endpoint.
-- The Gold-gate giver ("Banana's First Job") was removed on 2026-10-02; the other five islands keep theirs.
local REMOVED_GIVERS = { Gold = true }
local Players=game:GetService("Players")
local RS=game:GetService("ReplicatedStorage")
local SS=game:GetService("ServerStorage")
local Design=require(RS:WaitForChild("ProgressionDesign"))
local Balance=require(RS:WaitForChild("GameBalance"))

local remotes=RS:WaitForChild("BrainrotRemotes")
local QuestUpdate=remotes:FindFirstChild("QuestUpdate") or Instance.new("RemoteEvent")
QuestUpdate.Name="QuestUpdate";QuestUpdate.Parent=remotes
local FusionRequest=remotes:FindFirstChild("FusionRequest") or Instance.new("RemoteFunction")
FusionRequest.Name="FusionRequest";FusionRequest.Parent=remotes

local events=SS:FindFirstChild("ProgressionEvents") or Instance.new("Folder")
events.Name="ProgressionEvents";events.Parent=SS
local QuestProgress=events:FindFirstChild("QuestProgress") or Instance.new("BindableEvent")
QuestProgress.Name="QuestProgress";QuestProgress.Parent=events

local function dataOf(plr)
	for _=1,100 do
		local d=_G.PlazaGetData and _G.PlazaGetData(plr)
		if d then
			d.QuestProgress=type(d.QuestProgress)=="table" and d.QuestProgress or {}
			d.QuestCompleted=type(d.QuestCompleted)=="table" and d.QuestCompleted or {}
			d.ActiveQuest=type(d.ActiveQuest)=="string" and d.ActiveQuest or ""
			if REMOVED_GIVERS[d.ActiveQuest] then d.ActiveQuest="" end -- nobody left to claim it from
			return d
		end
		task.wait(.1)
	end
end
local function snapshot(plr)
	local d=_G.PlazaGetData and _G.PlazaGetData(plr)
	if not d then return end
	local active=d.ActiveQuest or ""
	local q=Design.Quests[active]
	QuestUpdate:FireClient(plr,{
		active=active,
		progress=q and (d.QuestProgress[active] or 0) or 0,
		target=q and q.target or 0,
		title=q and q.title or "",
		text=q and q.text or "",
		reward=q and q.reward or 0,
		completed=d.QuestCompleted,
	})
	if _G.PlazaSyncPlayer then _G.PlazaSyncPlayer(plr) end
end
local function notify(plr,text)
	local n=remotes:FindFirstChild("Notify");if n then n:FireClient(plr,text) end
end

local function claimOrAccept(plr,variant)
	local d=dataOf(plr);local q=Design.Quests[variant]
	if not d or not q then return end
	if d.QuestCompleted[variant] then notify(plr,"✅ You already finished "..q.title..".");return end
	local progress=d.QuestProgress[variant] or 0
	if progress>=q.target then
		d.QuestCompleted[variant]=true
		if d.ActiveQuest==variant then d.ActiveQuest="" end
		if _G.PlazaAwardMoney then _G.PlazaAwardMoney(plr,q.reward) end
		notify(plr,("🎉 QUEST COMPLETE: %s · +%s coins"):format(q.title,tostring(q.reward)))
	else
		d.ActiveQuest=variant
		notify(plr,("🍌 %s: %s Reward: %s coins."):format(q.title,q.text,tostring(q.reward)))
	end
	snapshot(plr)
end

QuestProgress.Event:Connect(function(plr,kind,source,amount,subtype)
	local d=_G.PlazaGetData and _G.PlazaGetData(plr)
	if not d then return end
	local variant=d.ActiveQuest
	local q=variant and Design.Quests[variant]
	if not q or d.QuestCompleted[variant] then return end
	local match=(q.kind==kind and (not q.source or q.source==source))
	if q.kind=="BreakType" then match=kind=="Break" and q.source==source and q.subtype==subtype end
	if match then
		d.QuestProgress[variant]=math.min(q.target,(d.QuestProgress[variant] or 0)+(amount or 1))
		snapshot(plr)
		if d.QuestProgress[variant]>=q.target then notify(plr,"✅ Objective complete! Return to Banana Dancana to claim your reward.") end
	end
end)

FusionRequest.OnServerInvoke=function(plr,id)
	if not _G.PlazaFuse then return false,"Fusion is still loading" end
	local ok,result=_G.PlazaFuse(plr,id)
	if ok then notify(plr,("✨ Fusion level %d! This brainrot now deals more damage."):format(result));snapshot(plr) end
	return ok,result
end

local npcFolder=workspace:FindFirstChild("IslandQuestGivers") or Instance.new("Folder")
npcFolder.Name="IslandQuestGivers";npcFolder.Parent=workspace
npcFolder:ClearAllChildren()
local template
local previews=RS:FindFirstChild("BrainrotPreviews")
if previews then
	for _,m in ipairs(previews:GetChildren()) do
		if m:IsA("Model") and (m:GetAttribute("BrainrotName") or m.Name)=="Banana Dancana" and (m:GetAttribute("Variant")=="Normal" or not template) then
			template=m
			if m:GetAttribute("Variant")=="Normal" then break end
		end
	end
end

local function groundY(x,z)
	local result=workspace:Raycast(Vector3.new(x,100,z),Vector3.new(0,-200,0),RaycastParams.new())
	return result and result.Position.Y or 0
end
local islands=workspace:WaitForChild("MutationIslands")
for _,variant in ipairs(Design.IslandOrder) do
	local island=islands:FindFirstChild(variant.." Island")
	local center=island and island:GetAttribute("CenterZ")
	local q=Design.Quests[variant]
	if center and q then
	  if not REMOVED_GIVERS[variant] then
		local x,z=-62,center+270
		local y=1.3 -- island roads and gate approaches share this surface height
		local stand=Instance.new("Part")
		stand.Name=variant.."QuestAnchor";stand.Size=Vector3.new(4,1,4);stand.Transparency=1
		stand.Anchored=true;stand.CanCollide=false;stand.CanTouch=false;stand.CanQuery=false
		stand.Position=Vector3.new(x,y+2.5,z);stand.Parent=npcFolder
		if template then
			local npc=template:Clone();npc.Name=variant.." Quest Giver"
			for _,p in ipairs(npc:GetDescendants()) do if p:IsA("BasePart") then p.Anchored=true;p.CanCollide=false;p.CanTouch=false;p.CanQuery=false end end
			npc.Parent=npcFolder
			-- The preview model stands upright only because its pivot is turned 90 degrees about X; a clone placed
			-- with a plain lookAt loses that turn and lies on its back. Keep the turn, scale him to 7 studs tall
			-- (measured in world space) and put his feet on the ground.
			local function worldBox(model)
				local lo,hi=Vector3.one*math.huge,-Vector3.one*math.huge
				for _,p in ipairs(model:GetDescendants()) do
					if p:IsA("BasePart") then
						local pc,h=p.CFrame,p.Size/2
						for sx=-1,1,2 do for sy=-1,1,2 do for sz=-1,1,2 do
							local w=pc:PointToWorldSpace(Vector3.new(h.X*sx,h.Y*sy,h.Z*sz));lo=lo:Min(w);hi=hi:Max(w)
						end end end
					end
				end
				return lo,hi
			end
			local face=CFrame.lookAt(Vector3.new(x,0,z),Vector3.new(0,0,z-20)).Rotation
			npc:PivotTo(CFrame.new(x,60,z)*face*CFrame.Angles(math.rad(90),0,0))
			local lo,hi=worldBox(npc)
			pcall(function() npc:ScaleTo(npc:GetScale()*7/math.max(hi.Y-lo.Y,.1)) end)
			lo,hi=worldBox(npc)
			local feet=groundY(x,z)
			if feet<-5 or feet>12 then feet=y end
			npc:PivotTo(npc:GetPivot()+Vector3.new(x-(lo.X+hi.X)/2,(feet+0.05)-lo.Y,z-(lo.Z+hi.Z)/2))
			npc:SetAttribute("DancingNPC",true) -- PlazaLifeClient makes him dance
			stand.Position=Vector3.new(x,feet+4,z)
		end
		local prompt=Instance.new("ProximityPrompt")
		prompt.Name="QuestPrompt";prompt.ActionText="Talk";prompt.ObjectText="🍌 Banana Dancana · "..variant.." Quest"
		prompt.HoldDuration=0;prompt.MaxActivationDistance=14;prompt.RequiresLineOfSight=false;prompt.Parent=stand
		prompt.Triggered:Connect(function(plr) claimOrAccept(plr,variant) end)
		local gui=Instance.new("BillboardGui")
		gui.Name="QuestLabel";gui.Size=UDim2.fromOffset(250,86);gui.StudsOffset=Vector3.new(0,5,0)
		gui.AlwaysOnTop=true;gui.MaxDistance=130;gui.Parent=stand
		local frame=Instance.new("Frame");frame.Size=UDim2.fromScale(1,1);frame.BackgroundColor3=Color3.fromRGB(22,18,37);frame.BackgroundTransparency=.08;frame.Parent=gui
		Instance.new("UICorner",frame).CornerRadius=UDim.new(0,14)
		local stroke=Instance.new("UIStroke");stroke.Color=Design.IslandColors[variant];stroke.Thickness=3;stroke.Parent=frame
		local title=Instance.new("TextLabel");title.BackgroundTransparency=1;title.Position=UDim2.fromOffset(8,5);title.Size=UDim2.new(1,-16,0,34)
		title.Font=Enum.Font.FredokaOne;title.TextScaled=true;title.TextColor3=Design.IslandColors[variant];title.Text="🍌 "..q.title;title.Parent=frame
		local body=Instance.new("TextLabel");body.BackgroundTransparency=1;body.Position=UDim2.fromOffset(9,41);body.Size=UDim2.new(1,-18,0,36)
		body.Font=Enum.Font.GothamBold;body.TextWrapped=true;body.TextScaled=true;body.TextColor3=Color3.new(1,1,1);body.Text=q.short.." · +"..q.reward;body.Parent=frame
	  end

		local mechanic=Design.IslandMechanics[variant]
		local sign=Instance.new("Part");sign.Name=variant.."MechanicSign";sign.Size=Vector3.new(1,1,1);sign.Transparency=1;sign.Anchored=true;sign.CanCollide=false;sign.CanTouch=false;sign.CanQuery=false
		sign.Position=Vector3.new(64,5.3,center+210);sign.Parent=npcFolder
		local sg=Instance.new("BillboardGui");sg.Size=UDim2.fromOffset(300,92);sg.AlwaysOnTop=true;sg.MaxDistance=145;sg.Parent=sign
		local sf=Instance.new("Frame");sf.Size=UDim2.fromScale(1,1);sf.BackgroundColor3=Color3.fromRGB(18,20,34);sf.BackgroundTransparency=.12;sf.Parent=sg
		Instance.new("UICorner",sf).CornerRadius=UDim.new(0,15)
		local ss=Instance.new("UIStroke");ss.Color=Design.IslandColors[variant];ss.Thickness=3;ss.Parent=sf
		local st=Instance.new("TextLabel");st.BackgroundTransparency=1;st.Position=UDim2.fromOffset(10,7);st.Size=UDim2.new(1,-20,0,32);st.Font=Enum.Font.FredokaOne;st.TextScaled=true;st.TextColor3=Design.IslandColors[variant];st.Text=Design.IslandIcons[variant].." "..mechanic.name;st.Parent=sf
		local sd=Instance.new("TextLabel");sd.BackgroundTransparency=1;sd.Position=UDim2.fromOffset(10,42);sd.Size=UDim2.new(1,-20,0,40);sd.Font=Enum.Font.GothamBold;sd.TextWrapped=true;sd.TextScaled=true;sd.TextColor3=Color3.new(1,1,1);sd.Text=mechanic.description;sd.Parent=sf
	end
end

Players.PlayerAdded:Connect(function(plr)
	task.spawn(function()
		local d=dataOf(plr);if not d then return end
		task.wait(1);snapshot(plr)
		while plr.Parent do
			local active=d.ActiveQuest
			local q=active and Design.Quests[active]
			if q and q.kind=="ReachCoins" and not d.QuestCompleted[active] then
				local value=math.min(q.target,plr:GetAttribute("Money") or 0)
				if value~=(d.QuestProgress[active] or 0) then
					d.QuestProgress[active]=value;snapshot(plr)
					if value>=q.target then notify(plr,"✅ Objective complete! Return to Banana Dancana.") end
				end
			end
			task.wait(1)
		end
	end)
end)
for _,plr in ipairs(Players:GetPlayers()) do task.defer(function() local d=dataOf(plr);if d then snapshot(plr) end end) end
