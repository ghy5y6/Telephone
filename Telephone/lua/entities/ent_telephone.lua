AddCSLuaFile()



ENT.Type = "anim"

ENT.Base = "base_anim"



ENT.Editable = true

ENT.PrintName = "Telephone"

ENT.Category = "Telephone"

ENT.Spawnable = true

ENT.AdminOnly = false

ENT.DialBack = 0



TELEPHONE_NUMBERS = TELEPHONE_NUMBERS or {}



-- [FIXED] Number Formats

local TELEPHONE_FORMATS = {

{ Name = "Default (0-000)", Format = "#-###" },

{ Name = "USA / Canada",    Format = "###-###-####" },

{ Name = "Russia",          Format = "+7-###-###-##-##" },

{ Name = "Germany",         Format = "+49-###-#######" },

{ Name = "Czech Republic",  Format = "+420-###-###-###" },

{ Name = "UK",              Format = "+44-####-######" },

{ Name = "France",          Format = "+33-##-##-##-##" }

}



-- [FIXED] Model Options

local PHONE_MODELS = {

[0] = "models/props_trainstation/payphone001a.mdl", -- Default Payphone

[1] = "models/props/cs_office/phone.mdl",           -- Office Phone

[2] = "models/props/cs_militia/oldphone01.mdl"      -- Old Phone

}



-- Helper to strip non-numeric characters

local function CleanNumber(num)

return string.gsub(num, "%D", "")

end



function ENT:SetupDataTables()

-- [FIXED] Slot Assignments (Must be unique)
-- Slot 0: DialNumber
self:NetworkVar("String", 0, "DialNumber")

-- Slot 1: MultiStation
self:NetworkVar("Bool", 1, "MultiStation")


-- Property editing for Model
-- Slot 2: PhoneStyle
self:NetworkVar("Int", 2, "PhoneStyle", { 

KeyName = "phonestyle", 

Edit = { 

type = "Combo", 

order = 1, 

text = "Phone Model",

values = { 

["Payphone (Default)"] = 0, 

["Modern (Office)"] = 1, 

["Old (Militia)"] = 2 

} 

} 

})


-- [NEW] Call Duration Setting
-- Slot 3: CallDuration
self:NetworkVar("Int", 3, "CallDuration", {
    KeyName = "callduration",
    Edit = {
        type = "Int",
        min = 10,
        max = 600,
        order = 2,
        title = "Call Duration (Seconds)"
    }
})


-- [NEW] Distance Check Toggle
-- Slot 4: EnableDistanceCheck
self:NetworkVar("Bool", 4, "EnableDistanceCheck", {
    KeyName = "enabledistancecheck",
    Edit = {
        type = "Boolean",
        order = 3,
        title = "Enable Distance Check"
    }
})


if SERVER then

self:NetworkVarNotify("PhoneStyle", function(self, name, old, new)

local mdl = PHONE_MODELS[new] or PHONE_MODELS[0]

if self:GetModel() ~= mdl then

self:SetModel(mdl)

self:PhysicsInit(SOLID_VPHYSICS)

self:SetMoveType(MOVETYPE_VPHYSICS)

self:SetSolid(SOLID_VPHYSICS)

self:SetUseType(SIMPLE_USE)


local phys = self:GetPhysicsObject()

if IsValid(phys) then

-- Payphones are heavy, desk phones are light

if new == 0 then

phys:SetMass(550)

else

phys:SetMass(20)

end

phys:Wake()

end

end

end)

end

end



-- [FIXED] Moved these to global scope so ENT:Use can access them
local activeCalls = {}
local playerInCall = {}



if SERVER then

util.AddNetworkString("Telephone_DialMenu")

util.AddNetworkString("Telephone_DialNumber")

util.AddNetworkString("Telephone_Pickup")

util.AddNetworkString("Telephone_Hangup")

util.AddNetworkString("Telephone_UpdateCallState")

util.AddNetworkString("Telephone_ChatMessage")

util.AddNetworkString("Telephone_AdminMenu")

util.AddNetworkString("Telephone_UpdateNumber")


-- [UPDATED] Ring Sound Mapping based on PhoneStyle (Index)
-- These are the sounds TARGET hears
local RING_SOUNDS = {
    [0] = "telephone/payphone_ringing.wav",       -- Payphone (Index 0)
    [1] = "telephone/digital_phone_ringing.wav",  -- Modern/Office (Index 1)
    [2] = "telephone/old_phone_ringing.wav"       -- Old/Militia (Index 2)
}

-- [UPDATED] Precache sounds to ensure server/client recognizes them
for k, v in pairs(RING_SOUNDS) do
    util.PrecacheSound(v)
end

-- Precache generic dialing sound for caller
util.PrecacheSound("telephone/dialing.wav")


function Telephone_GenerateUniqueNumber()

local attempts = 0

local maxAttempts = 100


while attempts < maxAttempts do

-- Pick a random format

local formatData = table.Random(TELEPHONE_FORMATS)

local formatStr = formatData.Format

local formatted = ""


-- Generate digits

for i = 1, #formatStr do

local char = string.sub(formatStr, i, i)

if char == "#" then

formatted = formatted .. math.random(0, 9)

else

formatted = formatted .. char

end

end


local available = true

for num, data in pairs(TELEPHONE_NUMBERS) do

if num == formatted then

if not data.multi then

available = false

end

break

end

end


if available then

TELEPHONE_NUMBERS[formatted] = {multi = false, phones = {}}

return formatted

end


attempts = attempts + 1

end


return "0-000" -- Fallback

end


function ENT:Initialize()

self:SetPhoneStyle(0) 

self:SetModel(PHONE_MODELS[0])

-- [NEW] Set default properties using correct slots
self:SetCallDuration(60)
self:SetEnableDistanceCheck(true)


self:PhysicsInit(SOLID_VPHYSICS)

self:SetMoveType(MOVETYPE_VPHYSICS)

self:SetSolid(SOLID_VPHYSICS)

self:SetUseType(SIMPLE_USE)


local phys = self:GetPhysicsObject()

if IsValid(phys) then

phys:SetMass(550)

phys:Wake()

end


self:Activate()


local num = Telephone_GenerateUniqueNumber()

self:SetNWString("DialNumber", num)

self:SetNWBool("MultiStation", false)

self:SetNWFloat("SpawnTime", CurTime())


if TELEPHONE_NUMBERS[num] then

table.insert(TELEPHONE_NUMBERS[num].phones, self)

else

TELEPHONE_NUMBERS[num] = {multi = false, phones = {self}}

end


self:SetNWBool("TelephoneDialing", false)

self:SetNWBool("TelephoneDialed", false)

self:SetNWBool("TelephoneInCall", false)

self:SetNWEntity("TelephoneCaller", nil)

self:SetNWEntity("TelephoneTarget", nil)

end


function ENT:OnRemove()

local num = self:GetNWString("DialNumber")


if TELEPHONE_NUMBERS[num] then

for i, phone in ipairs(TELEPHONE_NUMBERS[num].phones) do

if phone == self then

table.remove(TELEPHONE_NUMBERS[num].phones, i)

break

end

end


if #TELEPHONE_NUMBERS[num].phones == 0 then

TELEPHONE_NUMBERS[num] = nil

end

end


if activeCalls[self] then

self:EndCall()

end


for callerPhone, callData in pairs(activeCalls) do

if callData.target_phone == self then

callerPhone:EndCall()

break

end

end

end


function ENT:EndCall()

local callData = activeCalls[self]

if not callData then

for callerPhone, data in pairs(activeCalls) do

if data.target_phone == self then

callData = data

self = callerPhone

break

end

end

end


if not callData then return end


if IsValid(self) then
    -- [UPDATED] Stop specific stored sound
    if callData.caller_sound then
        self:StopSound(callData.caller_sound)
    end
self:SetNWBool("TelephoneDialing", false)

self:SetNWBool("TelephoneInCall", false)

self:SetNWEntity("TelephoneTarget", nil)

self:EmitSound("buttons/button10.wav")

end


if IsValid(callData.caller_ply) then

net.Start("Telephone_Hangup")

net.Send(callData.caller_ply)

playerInCall[callData.caller_ply] = nil

end


if IsValid(callData.target_ply) then

net.Start("Telephone_Hangup")

net.Send(callData.target_ply)

playerInCall[callData.target_ply] = nil

end


if IsValid(callData.target_phone) then
    -- [UPDATED] Stop specific stored sound
    if callData.target_sound then
        callData.target_phone:StopSound(callData.target_sound)
    end
callData.target_phone:SetNWBool("TelephoneDialed", false)

callData.target_phone:SetNWBool("TelephoneInCall", false)

callData.target_phone:SetNWEntity("TelephoneCaller", nil)

callData.target_phone:SetNWEntity("TelephoneTarget", nil)

callData.target_phone:EmitSound("buttons/button10.wav")

end


activeCalls[self] = nil


timer.Remove("TelephoneCall_" .. self:EntIndex())

end


function ENT:StartCall(targetPhone, callerPlayer)

if not IsValid(targetPhone) then return end


-- [UPDATED] Sound Logic Separation
-- Caller Sound: Generic dialing sound
local callerSound = "telephone/dialing.wav"

-- Target Sound: Specific ringtone based on the Target's Model Style
local tStyle = targetPhone:GetPhoneStyle()
local targetRing = RING_SOUNDS[tStyle] or "telephone/telephone.wav"


self:SetNWBool("TelephoneDialing", true)

self:SetNWEntity("TelephoneTarget", targetPhone)

self:SetNWEntity("TelephoneCaller", callerPlayer)


targetPhone:SetNWBool("TelephoneDialed", true)

targetPhone:SetNWEntity("TelephoneCaller", self)

targetPhone:SetNWEntity("TelephoneTarget", callerPlayer)


-- [UPDATED] Emit sounds
self:EmitSound(callerSound)
targetPhone:EmitSound(targetRing)


-- [NEW] Use custom duration from the phone properties
local duration = self:GetCallDuration()

activeCalls[self] = {

target_phone = targetPhone,

start_time = CurTime(),

caller_ply = callerPlayer,

target_ply = nil,
caller_sound = callerSound, -- Store sound for stopping
target_sound = targetRing -- Store sound for stopping

}


timer.Create("TelephoneCall_" .. self:EntIndex(), duration, 1, function()

if IsValid(self) then

self:EndCall()

end

end)

end


function ENT:Pickup(ply)

if not IsValid(ply) or not ply:IsPlayer() then return end


if self:GetNWBool("TelephoneDialed", false) and not self:GetNWBool("TelephoneInCall", false) then

local callerPhone = self:GetNWEntity("TelephoneCaller")


if IsValid(callerPhone) then

local callData = activeCalls[callerPhone]

if not callData then

for cPhone, data in pairs(activeCalls) do

if data.target_phone == self then

callData = data

callerPhone = cPhone

break

end

end

end


if not callData then

ply:ChatPrint("This call is no longer available.")

return

end


self:SetNWBool("TelephoneInCall", true)

self:SetNWBool("TelephoneDialed", false)

self:SetNWEntity("TelephoneTarget", ply)


callerPhone:SetNWBool("TelephoneInCall", true)

callerPhone:SetNWBool("TelephoneDialing", false)
callerPhone:StopSound(callData.caller_sound) -- Stop specific sound
self:StopSound(callData.target_sound) -- Stop specific sound


self:EmitSound("buttons/button9.wav")

callerPhone:EmitSound("buttons/button9.wav")


callData.target_ply = ply


playerInCall[ply] = true

playerInCall[callData.caller_ply] = true


net.Start("Telephone_UpdateCallState")
net.WriteEntity(self)
net.WriteString(self:GetNWString("DialNumber", "0-000"))
net.WriteFloat(callerPhone:GetCallDuration()) -- [NEW] Send duration to client
net.Send(callData.caller_ply)


net.Start("Telephone_UpdateCallState")
net.WriteEntity(callerPhone)
net.WriteString(callerPhone:GetNWString("DialNumber", "0-000"))
net.WriteFloat(callerPhone:GetCallDuration()) -- [NEW] Send duration to client
net.Send(ply)


callData.caller_ply:ChatPrint("Call connected!")

ply:ChatPrint("Call connected!")

end

end

end


function ENT:UpdateNumber(newNumber, multi, ply)

if not IsValid(ply) or not ply:IsAdmin() then return false end


local formatted = newNumber


if TELEPHONE_NUMBERS[formatted] then

if TELEPHONE_NUMBERS[formatted].multi and multi then

if self:GetNWBool("TelephoneDialing") or self:GetNWBool("TelephoneInCall") or self:GetNWBool("TelephoneDialed") then

ply:ChatPrint("Cannot change number while phone is in use.")

return false

end


table.insert(TELEPHONE_NUMBERS[formatted].phones, self)

self:SetNWString("DialNumber", formatted)

self:SetNWBool("MultiStation", true)

return true

elseif not TELEPHONE_NUMBERS[formatted].multi and not multi then

if #TELEPHONE_NUMBERS[formatted].phones > 0 then

ply:ChatPrint("That number is already in use.")

return false

else

if self:GetNWBool("TelephoneDialing") or self:GetNWBool("TelephoneInCall") or self:GetNWBool("TelephoneDialed") then

ply:ChatPrint("Cannot change number while phone is in use.")

return false

end


TELEPHONE_NUMBERS[formatted].phones = {self}

self:SetNWString("DialNumber", formatted)

self:SetNWBool("MultiStation", false)

return true

end

else

ply:ChatPrint("Cannot change number type conflict.")

return false

end

else

if self:GetNWBool("TelephoneDialing") or self:GetNWBool("TelephoneInCall") or self:GetNWBool("TelephoneDialed") then

ply:ChatPrint("Cannot change number while phone is in use.")

return false

end


TELEPHONE_NUMBERS[formatted] = {multi = multi, phones = {self}}

self:SetNWString("DialNumber", formatted)

self:SetNWBool("MultiStation", multi)

return true

end


return false

end


hook.Add("Think", "TelephoneDistanceCheck", function()

for callerPhone, callData in pairs(activeCalls) do

if not IsValid(callerPhone) or not IsValid(callData.target_phone) then

if IsValid(callerPhone) then

callerPhone:EndCall()

end

continue

end

-- [NEW] Check if distance checking is enabled
if not callerPhone:GetEnableDistanceCheck() then continue end


if callData.caller_ply and IsValid(callData.caller_ply) then

local dist = callData.caller_ply:GetPos():Distance(callerPhone:GetPos())

if dist > 200 then

callerPhone:EndCall()

callData.caller_ply:ChatPrint("You moved too far from the phone. Call ended.")

end

end


if callData.target_ply and IsValid(callData.target_ply) then

local dist = callData.target_ply:GetPos():Distance(callData.target_phone:GetPos())

if dist > 200 then

callerPhone:EndCall()

callData.target_ply:ChatPrint("You moved too far from the phone. Call ended.")

end

end

end

end)


net.Receive("Telephone_DialNumber", function(len, ply)

local telephone = net.ReadEntity()

local dialedNumRaw = net.ReadString()


if not IsValid(telephone) or not IsValid(ply) then return end


local foundKey = nil

local dialedClean = CleanNumber(dialedNumRaw)


for storedNum, _ in pairs(TELEPHONE_NUMBERS) do

if CleanNumber(storedNum) == dialedClean then

foundKey = storedNum

break

end

end


if telephone:GetNWBool("TelephoneDialing", false) or 

   telephone:GetNWBool("TelephoneInCall", false) or

   telephone:GetNWBool("TelephoneDialed", false) then

ply:ChatPrint("This phone is currently in use.")

return

end


if playerInCall[ply] then

ply:ChatPrint("You are already in a call.")

return

end


local targetPhones = {}


if foundKey and TELEPHONE_NUMBERS[foundKey] then

if TELEPHONE_NUMBERS[foundKey].multi then

local callerPos = telephone:GetPos()


for _, phone in ipairs(TELEPHONE_NUMBERS[foundKey].phones) do

if IsValid(phone) then

if not phone:GetNWBool("TelephoneDialed", false) and

   not phone:GetNWBool("TelephoneInCall", false) and

   not phone:GetNWBool("TelephoneDialing", false) then


local dist = callerPos:Distance(phone:GetPos())

table.insert(targetPhones, {phone = phone, dist = dist})

end

end

end


table.sort(targetPhones, function(a, b) return a.dist < b.dist end)


if #targetPhones > 0 then

telephone:StartCall(targetPhones[1].phone, ply)

ply:ChatPrint("Dialing " .. foundKey .. "...")

else

ply:ChatPrint(foundKey .. " is currently busy in all stations. Try again later.")

telephone:EmitSound("buttons/button8.wav")

end

else

local targetPhone = nil

for _, phone in ipairs(TELEPHONE_NUMBERS[foundKey].phones) do

if IsValid(phone) then

targetPhone = phone

break

end

end


if targetPhone then

if targetPhone:GetNWBool("TelephoneDialed", false) or

   targetPhone:GetNWBool("TelephoneInCall", false) or

   targetPhone:GetNWBool("TelephoneDialing", false) then

ply:ChatPrint("That number is busy.")

telephone:EmitSound("buttons/button8.wav")

return

end


telephone:StartCall(targetPhone, ply)

ply:ChatPrint("Dialing " .. foundKey .. "...")

else

ply:ChatPrint("That number is not in service.")

telephone:EmitSound("buttons/button8.wav")

end

end

else

ply:ChatPrint("That number is not in service.")

telephone:EmitSound("buttons/button8.wav")

end

end)


net.Receive("Telephone_Pickup", function(len, ply)

local telephone = net.ReadEntity()

if IsValid(telephone) and IsValid(ply) then

telephone:Pickup(ply)

end

end)


net.Receive("Telephone_UpdateNumber", function(len, ply)

local telephone = net.ReadEntity()

local newNumber = net.ReadString()

local multi = net.ReadBool()


if IsValid(telephone) and IsValid(ply) and ply:IsAdmin() then

local success = telephone:UpdateNumber(newNumber, multi, ply)

if success then

ply:ChatPrint("Phone number updated successfully.")

else

ply:ChatPrint("Failed to update phone number.")

end

end

end)


hook.Add("PlayerSay", "TelephonePrivateChat", function(ply, text, team)

if playerInCall[ply] then

for callerPhone, callData in pairs(activeCalls) do

if callData.caller_ply == ply or callData.target_ply == ply then

local otherPlayer = (callData.caller_ply == ply) and callData.target_ply or callData.caller_ply


if IsValid(otherPlayer) then

net.Start("Telephone_ChatMessage")

net.WriteEntity(ply)

net.WriteString(text)

net.WriteBool(callData.caller_ply == ply)

net.Send(otherPlayer)


net.Start("Telephone_ChatMessage")

net.WriteEntity(ply)

net.WriteString(text)

net.WriteBool(callData.caller_ply == ply)

net.Send(ply)


return ""

end

end

end

end

end)


hook.Add("EntityRemoved", "TelephoneCleanupPlayerCall", function(ent)

if ent:IsPlayer() then

playerInCall[ent] = nil

end

end)

end



function ENT:Use(ply)

if not IsValid(ply) or not ply:IsPlayer() then return end

-- [FIXED] Wrap all logic in SERVER check to prevent Client errors and to allow accessing activeCalls
if SERVER then

-- Admin Check
if ply:KeyDown(IN_WALK) and ply:IsAdmin() then

net.Start("Telephone_AdminMenu")

net.WriteEntity(self)

net.WriteString(self:GetNWString("DialNumber", "0-000"))

net.WriteBool(self:GetNWBool("MultiStation", false))

net.Send(ply)

return

end

-- Incoming Call Pickup
if self:GetNWBool("TelephoneDialed", false) and not self:GetNWBool("TelephoneInCall", false) then

self:Pickup(ply)

return

end

-- Check if this phone is currently in an active call
local callerPhone = nil
local callData = nil

if activeCalls[self] then
callerPhone = self
callData = activeCalls[self]
else
-- Check if this phone is the target
for cp, cd in pairs(activeCalls) do
if cd.target_phone == self then
callerPhone = cp
callData = cd
break
end
end
end

if callData then
-- The phone is busy. Check if the user is the one using it.
local isCaller = (callData.caller_ply == ply)
local isTarget = IsValid(callData.target_ply) and (callData.target_ply == ply)

if isCaller or isTarget then
-- The user is in the call, so pressing E hangs up.
callerPhone:EndCall()
ply:ChatPrint("You hung up the phone.")
else
-- The user is someone else.
ply:ChatPrint("This phone is currently in use.")
end
return
end

-- Default to Dial Menu
net.Start("Telephone_DialMenu")
net.WriteEntity(self)
net.WriteString(self:GetNWString("DialNumber", "0-000"))
net.Send(ply)

end -- End SERVER check

end



if CLIENT then

surface.CreateFont("TelephoneTitle", {

font = "Arial",

size = 24,

weight = 800,

antialias = true

})


surface.CreateFont("TelephoneDigits", {

font = "Arial",

size = 32,

weight = 700,

antialias = true

})


surface.CreateFont("TelephoneButton", {

font = "Arial",

size = 20,

weight = 600,

antialias = true

})


surface.CreateFont("TelephoneHint", {

font = "Arial",

size = 50,

weight = 800,

antialias = true

})


local dialMenu

local adminMenu

local phoneModel = nil

local phoneAttachment = nil

local isInCall = false

local callPartner = nil

local callStartTime = 0

local callDuration = 60 -- Will be updated dynamically


-- [UPDATED] Sound Map

local dialSoundMap = {

["0"] = "telephone/dial0.wav",

["1"] = "telephone/dial1.wav",

["2"] = "telephone/dial2.wav",

["3"] = "telephone/dial3.wav",

["4"] = "telephone/dial4.wav",

["5"] = "telephone/dial5.wav",

["6"] = "telephone/dial6.wav",

["7"] = "telephone/dial7.wav",

["8"] = "telephone/dial8.wav",

["9"] = "telephone/dial9.wav"

}


local function PlayDialSound(digit)

local soundPath = dialSoundMap[tostring(digit)]

if soundPath then

surface.PlaySound(soundPath)

else

surface.PlaySound("telephone/dial5.wav")

end

end


local function CreatePhoneAttachment()

if IsValid(phoneModel) then

phoneModel:Remove()

end


phoneModel = ClientsideModel("models/props/cs_office/phone.mdl")

phoneModel:SetNoDraw(true)


phoneAttachment = {

model = phoneModel,

bone = "ValveBiped.Bip01_R_Hand",

pos = Vector(3, 2, 0),

ang = Angle(0, 0, 0)

}

end


local function RemovePhoneAttachment()

if IsValid(phoneModel) then

phoneModel:Remove()

phoneModel = nil

end

phoneAttachment = nil

isInCall = false

callPartner = nil

end


function ENT:Draw()

self:DrawModel()


local spawnTime = self:GetNWFloat("SpawnTime", 0)

if CurTime() - spawnTime < 5 then

local pos = self:GetPos() + Vector(25, 0, 15)

local ang = Angle(0, 0, 0)

ang:RotateAroundAxis(Vector(0, 0, 1), 90)


local ply = LocalPlayer()

if IsValid(ply) then

local plyPos = ply:GetPos()

ang = (plyPos - pos):Angle()

ang.p = 0

ang.y = ang.y + 90

ang.r = 90

end


cam.Start3D2D(pos, ang, 0.1)

local text1 = "E: Dial"

local text2 = "Alt + E: Edit (admin)"


surface.SetFont("TelephoneHint")

local eWidth = surface.GetTextSize("E")

local altWidth = surface.GetTextSize("Alt + E")

local text1Width = surface.GetTextSize(text1)

local text2Width = surface.GetTextSize(text2)


surface.SetTextColor(Color(100, 200, 255))

surface.SetTextPos(-text1Width/2, -30)

surface.DrawText("E")


surface.SetTextColor(Color(255, 255, 255))

surface.SetTextPos(-text1Width/2 + eWidth, -30)

surface.DrawText(": Dial")


surface.SetTextColor(Color(100, 200, 255))

surface.SetTextPos(-text2Width/2, 10)

surface.DrawText("Alt + E")


surface.SetTextColor(Color(255, 255, 255))

surface.SetTextPos(-text2Width/2 + altWidth, 10)

surface.DrawText(": Edit (admin)")

cam.End3D2D()

end

end


hook.Add("PostPlayerDraw", "DrawPlayerPhone", function(ply)

if ply ~= LocalPlayer() then return end

if not isInCall or not IsValid(phoneModel) or not phoneAttachment then return end


local bone = ply:LookupBone(phoneAttachment.bone)

if not bone then return end


local pos, ang = ply:GetBonePosition(bone)

if not pos or not ang then return end


pos = pos + ang:Forward() * phoneAttachment.pos.x

pos = pos + ang:Right() * phoneAttachment.pos.y

pos = pos + ang:Up() * phoneAttachment.pos.z


ang:RotateAroundAxis(ang:Forward(), phoneAttachment.ang.p)

ang:RotateAroundAxis(ang:Right(), phoneAttachment.ang.y)

ang:RotateAroundAxis(ang:Up(), phoneAttachment.ang.r)


phoneModel:SetPos(pos)

phoneModel:SetAngles(ang)

phoneModel:DrawModel()

end)


local function DialMenu(telephone, num)

if IsValid(dialMenu) then

dialMenu:Remove()

end


local enteredDigits = ""


dialMenu = vgui.Create("DFrame")

dialMenu:SetSize(350, 500)

dialMenu:SetTitle("")

dialMenu:Center()

dialMenu:MakePopup()

dialMenu:SetDraggable(false)

dialMenu:ShowCloseButton(false)

dialMenu.Paint = function(self, w, h)

draw.RoundedBox(8, 0, 0, w, h, Color(40, 40, 45))

draw.RoundedBoxEx(8, 0, 0, w, 60, Color(30, 30, 35), true, true, false, false)

draw.SimpleText("TELEPHONE - " .. num, "TelephoneTitle", w/2, 30, Color(255, 255, 255), TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)

draw.RoundedBox(6, 25, 80, 300, 60, Color(20, 20, 25))


if isInCall then

local timeLeft = callDuration - (CurTime() - callStartTime)

if timeLeft < 0 then timeLeft = 0 end

draw.SimpleText("Call Time: " .. math.floor(timeLeft) .. "s", "TelephoneButton", w/2, 150, Color(255, 200, 50), TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)

end

end


local display = vgui.Create("DLabel", dialMenu)

display:SetSize(290, 50)

display:SetPos(30, 85)

display:SetContentAlignment(5)

display:SetFont("TelephoneDigits")

display:SetText("")

display:SetTextColor(Color(0, 200, 255))


local function UpdateDisplay()

display:SetText(enteredDigits)

end


local buttonY = 160

local buttonColors = {

Color(60, 60, 70),

Color(80, 80, 90),

Color(100, 100, 110)

}


for i = 1, 9 do

local btn = vgui.Create("DButton", dialMenu)

btn:SetSize(80, 60)

btn:SetPos(((i-1) % 3) * 100 + 35, math.floor((i-1) / 3) * 70 + buttonY)

btn:SetText(tostring(i))

btn:SetFont("TelephoneDigits")

btn:SetTextColor(Color(255, 255, 255))


btn.Paint = function(self, w, h)

local col = buttonColors[1]

if self:IsHovered() then col = buttonColors[2] end

if self:IsDown() then col = buttonColors[3] end

draw.RoundedBox(6, 0, 0, w, h, col)

end


btn.DoClick = function()

if string.len(enteredDigits) < 15 then 

enteredDigits = enteredDigits .. tostring(i)

UpdateDisplay()

PlayDialSound(i) 

end

end

end


local zeroBtn = vgui.Create("DButton", dialMenu)

zeroBtn:SetSize(80, 60)

zeroBtn:SetPos(135, buttonY + 210)

zeroBtn:SetText("0")

zeroBtn:SetFont("TelephoneDigits")

zeroBtn:SetTextColor(Color(255, 255, 255))


zeroBtn.Paint = function(self, w, h)

local col = buttonColors[1]

if self:IsHovered() then col = buttonColors[2] end

if self:IsDown() then col = buttonColors[3] end

draw.RoundedBox(6, 0, 0, w, h, col)

end


zeroBtn.DoClick = function()

if string.len(enteredDigits) < 15 then 

enteredDigits = enteredDigits .. "0"

UpdateDisplay()

PlayDialSound(0) 

end

end


local clearBtn = vgui.Create("DButton", dialMenu)

clearBtn:SetSize(80, 60)

clearBtn:SetPos(35, buttonY + 210)

clearBtn:SetText("CLEAR")

clearBtn:SetFont("TelephoneButton")

clearBtn:SetTextColor(Color(255, 100, 100))


clearBtn.Paint = zeroBtn.Paint


clearBtn.DoClick = function()

enteredDigits = ""

UpdateDisplay()

surface.PlaySound("buttons/button14.wav")

end


local dialBtn = vgui.Create("DButton", dialMenu)

dialBtn:SetSize(80, 60)

dialBtn:SetPos(235, buttonY + 210)

dialBtn:SetText("DIAL")

dialBtn:SetFont("TelephoneButton")

dialBtn:SetTextColor(Color(100, 255, 100))


dialBtn.Paint = zeroBtn.Paint


dialBtn.DoClick = function()

if string.len(enteredDigits) > 0 then

net.Start("Telephone_DialNumber")

net.WriteEntity(telephone)

net.WriteString(enteredDigits)

net.SendToServer()

dialMenu:Remove()

surface.PlaySound("buttons/button14.wav")

else

display:SetText("ENTER NUMBER")

display:SetTextColor(Color(255, 50, 50))

timer.Simple(1, function()

if IsValid(display) then

UpdateDisplay()

display:SetTextColor(Color(0, 200, 255))

end

end)

end

end


local closeBtn = vgui.Create("DButton", dialMenu)

closeBtn:SetSize(30, 30)

closeBtn:SetPos(310, 15)

closeBtn:SetText("X")

closeBtn:SetFont("TelephoneButton")

closeBtn:SetTextColor(Color(255, 100, 100))


closeBtn.Paint = function(self, w, h)

if self:IsHovered() then

draw.RoundedBox(4, 0, 0, w, h, Color(255, 50, 50, 100))

end

end


closeBtn.DoClick = function()

dialMenu:Remove()

end

end


local function AdminMenu(telephone, num, multi)

if IsValid(adminMenu) then

adminMenu:Remove()

end


local enteredDigits = string.Replace(num, "-", "")

local multiStation = multi


adminMenu = vgui.Create("DFrame")

adminMenu:SetSize(500, 600)

adminMenu:SetTitle("")

adminMenu:Center()

adminMenu:MakePopup()

adminMenu:SetDraggable(false)

adminMenu:ShowCloseButton(false)

adminMenu.Paint = function(self, w, h)

draw.RoundedBox(8, 0, 0, w, h, Color(40, 40, 45))

draw.RoundedBoxEx(8, 0, 0, w, 60, Color(30, 30, 35), true, true, false, false)

draw.SimpleText("TELEPHONE ADMIN - " .. num, "TelephoneTitle", w/2, 30, Color(255, 255, 255), TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)

draw.RoundedBox(6, 50, 80, 400, 60, Color(20, 20, 25))

end


local display = vgui.Create("DLabel", adminMenu)

display:SetSize(390, 50)

display:SetPos(55, 85)

display:SetContentAlignment(5)

display:SetFont("TelephoneDigits")

display:SetText(num)

display:SetTextColor(Color(0, 200, 255))


local function UpdateDisplay()

display:SetText(enteredDigits)

end


local buttonY = 160

local buttonColors = {

Color(60, 60, 70),

Color(80, 80, 90),

Color(100, 100, 110)

}


for i = 1, 9 do

local btn = vgui.Create("DButton", adminMenu)

btn:SetSize(100, 60)

btn:SetPos(((i-1) % 3) * 120 + 70, math.floor((i-1) / 3) * 70 + buttonY)

btn:SetText(tostring(i))

btn:SetFont("TelephoneDigits")

btn:SetTextColor(Color(255, 255, 255))


btn.Paint = function(self, w, h)

local col = buttonColors[1]

if self:IsHovered() then col = buttonColors[2] end

if self:IsDown() then col = buttonColors[3] end

draw.RoundedBox(6, 0, 0, w, h, col)

end


btn.DoClick = function()

if string.len(enteredDigits) < 15 then 

enteredDigits = enteredDigits .. tostring(i)

UpdateDisplay()

PlayDialSound(i) 

end

end

end


local zeroBtn = vgui.Create("DButton", adminMenu)

zeroBtn:SetSize(100, 60)

zeroBtn:SetPos(190, buttonY + 210)

zeroBtn:SetText("0")

zeroBtn:SetFont("TelephoneDigits")

zeroBtn:SetTextColor(Color(255, 255, 255))


zeroBtn.Paint = function(self, w, h)

local col = buttonColors[1]

if self:IsHovered() then col = buttonColors[2] end

if self:IsDown() then col = buttonColors[3] end

draw.RoundedBox(6, 0, 0, w, h, col)

end


zeroBtn.DoClick = function()

if string.len(enteredDigits) < 15 then 

enteredDigits = enteredDigits .. "0"

UpdateDisplay()

PlayDialSound(0) 

end

end


local clearBtn = vgui.Create("DButton", adminMenu)

clearBtn:SetSize(100, 60)

clearBtn:SetPos(70, buttonY + 210)

clearBtn:SetText("CLEAR")

clearBtn:SetFont("TelephoneButton")

clearBtn:SetTextColor(Color(255, 100, 100))


clearBtn.Paint = zeroBtn.Paint


clearBtn.DoClick = function()

enteredDigits = ""

UpdateDisplay()

surface.PlaySound("buttons/button14.wav")

end


local multiCheck = vgui.Create("DCheckBoxLabel", adminMenu)

multiCheck:SetPos(70, buttonY + 280)

multiCheck:SetText("Multi Station")

multiCheck:SetTextColor(Color(255, 255, 255))

multiCheck:SetValue(multiStation)

multiCheck:SizeToContents()


multiCheck.OnChange = function(self, val)

multiStation = val

end


-- [UPDATED] Dropdown Menu

local formatCombo = vgui.Create("DComboBox", adminMenu)

formatCombo:SetPos(70, buttonY + 310)

formatCombo:SetSize(360, 25)

formatCombo:SetValue("Select Country Format...")


for _, data in ipairs(TELEPHONE_FORMATS) do

formatCombo:AddChoice(data.Name, data.Format)

end


-- Default to first

formatCombo:ChooseOptionID(1)


local genBtn = vgui.Create("DButton", adminMenu)

genBtn:SetSize(175, 40)

genBtn:SetPos(70, buttonY + 350)

genBtn:SetText("GENERATE")

genBtn:SetFont("TelephoneButton")

genBtn:SetTextColor(Color(200, 200, 100))


genBtn.Paint = function(self, w, h)

local col = buttonColors[1]

if self:IsHovered() then col = buttonColors[2] end

if self:IsDown() then col = buttonColors[3] end

draw.RoundedBox(6, 0, 0, w, h, col)

end


genBtn.DoClick = function()

local _, selectedFormat = formatCombo:GetSelected()

if not selectedFormat then 

selectedFormat = TELEPHONE_FORMATS[1].Format 

end


enteredDigits = ""

for i = 1, #selectedFormat do

local char = string.sub(selectedFormat, i, i)

if char == "#" then

enteredDigits = enteredDigits .. math.random(0, 9)

else

enteredDigits = enteredDigits .. char

end

end

UpdateDisplay()

PlayDialSound(5)

end


local confirmBtn = vgui.Create("DButton", adminMenu)

confirmBtn:SetSize(175, 40)

confirmBtn:SetPos(255, buttonY + 350)

confirmBtn:SetText("CONFIRM")

confirmBtn:SetFont("TelephoneButton")

confirmBtn:SetTextColor(Color(100, 255, 100))


confirmBtn.Paint = genBtn.Paint


confirmBtn.DoClick = function()

if string.len(enteredDigits) > 0 then

net.Start("Telephone_UpdateNumber")

net.WriteEntity(telephone)

net.WriteString(enteredDigits)

net.WriteBool(multiStation)

net.SendToServer()

adminMenu:Remove()

surface.PlaySound("buttons/button14.wav")

else

display:SetText("ENTER DIGITS")

display:SetTextColor(Color(255, 50, 50))

timer.Simple(1, function()

if IsValid(display) then

UpdateDisplay()

display:SetTextColor(Color(0, 200, 255))

end

end)

end

end


local closeBtn = vgui.Create("DButton", adminMenu)

closeBtn:SetSize(30, 30)

closeBtn:SetPos(460, 15)

closeBtn:SetText("X")

closeBtn:SetFont("TelephoneButton")

closeBtn:SetTextColor(Color(255, 100, 100))


closeBtn.Paint = function(self, w, h)

if self:IsHovered() then

draw.RoundedBox(4, 0, 0, w, h, Color(255, 50, 50, 100))

end

end


closeBtn.DoClick = function()

adminMenu:Remove()

end

end


net.Receive("Telephone_DialMenu", function()

local telephone = net.ReadEntity()

local num = net.ReadString()


DialMenu(telephone, num)

end)


net.Receive("Telephone_AdminMenu", function()

local telephone = net.ReadEntity()

local num = net.ReadString()

local multi = net.ReadBool()


if LocalPlayer():IsAdmin() then

AdminMenu(telephone, num, multi)

end

end)


net.Receive("Telephone_UpdateCallState", function()

local otherPhone = net.ReadEntity()

local phoneNumber = net.ReadString()


callDuration = net.ReadFloat() -- [NEW] Update call duration from server


if IsValid(otherPhone) then

CreatePhoneAttachment()

isInCall = true

callStartTime = CurTime()

callPartner = otherPhone


chat.AddText(Color(255, 100, 100), "[Phone] ", Color(0, 200, 255), "You are now in a call with " .. phoneNumber)

chat.AddText(Color(255, 100, 100), "[Phone] ", Color(255, 255, 100), "Your chat messages are now private. Type to talk!")

end

end)


net.Receive("Telephone_Hangup", function()

RemovePhoneAttachment()

chat.AddText(Color(255, 100, 100), "[Phone] ", Color(255, 100, 100), "Call ended.")


if IsValid(dialMenu) then

dialMenu:Remove()

end

if IsValid(adminMenu) then

adminMenu:Remove()

end

end)


net.Receive("Telephone_ChatMessage", function()

local sender = net.ReadEntity()

local message = net.ReadString()

local isCaller = net.ReadBool()


if IsValid(sender) then

local nameColor = Color(255, 200, 100)

local messageColor = (sender == LocalPlayer()) and Color(0, 150, 255) or Color(255, 255, 50)


chat.AddText(Color(255, 100, 100), "[", nameColor, sender:Name(), Color(255, 100, 100), "] ", messageColor, message)

end

end)


hook.Add("PreRender", "CleanupPhoneModel", function()

if not LocalPlayer():Alive() or LocalPlayer():Health() <= 0 then

RemovePhoneAttachment()

end

end)

end