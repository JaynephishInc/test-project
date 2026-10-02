-- Redeem codes at the Code Tower. Add/remove codes in CODES below (keys are UPPERCASE).
local Players=game:GetService("Players")
local DSS=game:GetService("DataStoreService")
local HttpService=game:GetService("HttpService")

local CODES={
	TUNGTUNG={coins=500},
	BRAINROT={coins=250},
	RELEASE={coins=1000},
}

local ok,store=pcall(function() return DSS:GetDataStore("PlazaCodes_v1") end)
if not ok then store=nil end
local used={}
local busy={}

local function load(plr)
	local t={}
	if store then local s,v=pcall(function() return store:GetAsync("u"..plr.UserId) end) if s and type(v)=="table" then t=v end end
	used[plr]=t
	plr:SetAttribute("RedeemedCodes",HttpService:JSONEncode(t))
end
Players.PlayerAdded:Connect(load)
for _,p in Players:GetPlayers() do task.spawn(load,p) end
Players.PlayerRemoving:Connect(function(p) used[p]=nil busy[p]=nil end)

local remotes=game.ReplicatedStorage:WaitForChild("BrainrotRemotes")
local rf=remotes:FindFirstChild("RedeemCode") or Instance.new("RemoteFunction")
rf.Name="RedeemCode" rf.Parent=remotes
rf.OnServerInvoke=function(plr,code)
	if type(code)~="string" or #code>40 then return false,"Invalid code" end
	code=code:upper():gsub("%s","")
	local info=CODES[code]
	if not info then return false,"That code doesn't exist" end
	if busy[plr] then return false,"One sec..." end
	local t=used[plr] if not t then return false,"Still loading, try again" end
	if t[code] then return false,"You already redeemed this code" end
	busy[plr]=true
	t[code]=true
	if store then pcall(function() store:SetAsync("u"..plr.UserId,t) end) end
	local paid=0
	if info.coins and _G.PlazaAwardMoney then local s,a=_G.PlazaAwardMoney(plr,info.coins) paid=s and a or 0 end
	plr:SetAttribute("RedeemedCodes",HttpService:JSONEncode(t))
	busy[plr]=nil
	return true,("+%d coins!"):format(paid)
end
