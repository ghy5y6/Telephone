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

if SERVER then
	TELEPHONE_NUMBERS = {}
	
	util.AddNetworkString("Telephone_DialMenu")
	util.AddNetworkString("Telephone_DialNumber")
	util.AddNetworkString("Telephone_Pickup")
	util.AddNetworkString("Telephone_Hangup")
	util.AddNetworkString("Telephone_UpdateCallState")
	util.AddNetworkString("Telephone_ChatMessage")
	util.AddNetworkString("Telephone_AdminMenu")
	util.AddNetworkString("Telephone_UpdateNumber")
	
	local activeCalls = {}
	local playerInCall = {}
	
	function Telephone_GenerateUniqueNumber()
		local attempts = 0
		local maxAttempts = 100
		
		while attempts < maxAttempts do
			local number = math.random(0, 9999)
			
			local formatted = tostring(number)
			while #formatted < 4 do
				formatted = "0" .. formatted
			end
			formatted = string.sub(formatted, 1, 1) .. "-" .. string.sub(formatted, 2, 4)
			
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
		
		return "0-000"
	end
	
	function ENT:Initialize()
		self:SetModel("models/props_trainstation/payphone001a.mdl")
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
			self:StopSound("telephone/ringing.wav")
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
			callData.target_phone:StopSound("telephone/telephone.wav")
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
		
		self:SetNWBool("TelephoneDialing", true)
		self:SetNWEntity("TelephoneTarget", targetPhone)
		self:SetNWEntity("TelephoneCaller", callerPlayer)
		
		targetPhone:SetNWBool("TelephoneDialed", true)
		targetPhone:SetNWEntity("TelephoneCaller", self)
		targetPhone:SetNWEntity("TelephoneTarget", callerPlayer)
		
		self:EmitSound("telephone/ringing.wav")
		targetPhone:EmitSound("telephone/telephone.wav")
		
		activeCalls[self] = {
			target_phone = targetPhone,
			start_time = CurTime(),
			caller_ply = callerPlayer,
			target_ply = nil
		}
		
		timer.Create("TelephoneCall_" .. self:EntIndex(), 60, 1, function()
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
				print("t")
				callerPhone:StopSound("telephone/ringing.wav")
				self:StopSound("telephone/telephone.wav")
				
				self:EmitSound("buttons/button9.wav")
				callerPhone:EmitSound("buttons/button9.wav")
				
				callData.target_ply = ply
				
				playerInCall[ply] = true
				playerInCall[callData.caller_ply] = true
				
				net.Start("Telephone_UpdateCallState")
					net.WriteEntity(self)
					net.WriteString(self:GetNWString("DialNumber", "0-000"))
				net.Send(callData.caller_ply)
				
				net.Start("Telephone_UpdateCallState")
					net.WriteEntity(callerPhone)
					net.WriteString(callerPhone:GetNWString("DialNumber", "0-000"))
				net.Send(ply)
				
				callData.caller_ply:ChatPrint("Call connected!")
				ply:ChatPrint("Call connected!")
			end
		end
	end
	
	function ENT:UpdateNumber(newNumber, multi, ply)
		if not IsValid(ply) or not ply:IsAdmin() then return false end
		
		local oldNumber = self:GetNWString("DialNumber")
		
		local formatted = newNumber
		if #newNumber == 4 then
			formatted = string.sub(newNumber, 1, 1) .. "-" .. string.sub(newNumber, 2, 4)
		end
		
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
		local dialedNum = net.ReadString()
		
		if not IsValid(telephone) or not IsValid(ply) then return end
		
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
		
		if TELEPHONE_NUMBERS[dialedNum] then
			if TELEPHONE_NUMBERS[dialedNum].multi then
				local callerPos = telephone:GetPos()
				
				for _, phone in ipairs(TELEPHONE_NUMBERS[dialedNum].phones) do
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
					ply:ChatPrint("Dialing " .. dialedNum .. "...")
				else
					ply:ChatPrint(dialedNum .. " is currently busy in all stations. Try again later.")
					telephone:EmitSound("buttons/button8.wav")
				end
			else
				local targetPhone = nil
				for _, phone in ipairs(TELEPHONE_NUMBERS[dialedNum].phones) do
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
					ply:ChatPrint("Dialing " .. dialedNum .. "...")
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
	
	if ply:KeyDown(IN_WALK) and ply:IsAdmin() then
		net.Start("Telephone_AdminMenu")
			net.WriteEntity(self)
			net.WriteString(self:GetNWString("DialNumber", "0-000"))
			net.WriteBool(self:GetNWBool("MultiStation", false))
		net.Send(ply)
		return
	end
	
	if self:GetNWBool("TelephoneDialed", false) and not self:GetNWBool("TelephoneInCall", false) then
		self:Pickup(ply)
		return
	end
	
	if self:GetNWBool("TelephoneDialing", false) or 
	   self:GetNWBool("TelephoneInCall", false) then
		ply:ChatPrint("This phone is currently in use.")
		return
	end
	
	net.Start("Telephone_DialMenu")
		net.WriteEntity(self)
		net.WriteString(self:GetNWString("DialNumber", "0-000"))
	net.Send(ply)
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
	local callDuration = 60
	
	local dialSounds = {
		"telephone/dial1.wav",
		"telephone/dial2.wav",
		"telephone/dial3.wav",
		"telephone/dial4.wav",
		"telephone/dial5.wav",
		"telephone/dial6.wav",
		"telephone/dial7.wav"
	}
	
	local function PlayRandomDialSound()
		surface.PlaySound(table.Random(dialSounds))
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
			if enteredDigits == "" then
				display:SetText("")
			else
				if string.len(enteredDigits) == 4 then
					local formatted = string.sub(enteredDigits, 1, 1) .. "-" .. string.sub(enteredDigits, 2, 4)
					display:SetText(formatted)
				else
					display:SetText(enteredDigits)
				end
			end
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
				if string.len(enteredDigits) < 4 then
					enteredDigits = enteredDigits .. tostring(i)
					UpdateDisplay()
					PlayRandomDialSound()
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
			if string.len(enteredDigits) < 4 then
				enteredDigits = enteredDigits .. "0"
				UpdateDisplay()
				PlayRandomDialSound()
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
			PlayRandomDialSound()
		end
		
		local dialBtn = vgui.Create("DButton", dialMenu)
		dialBtn:SetSize(80, 60)
		dialBtn:SetPos(235, buttonY + 210)
		dialBtn:SetText("DIAL")
		dialBtn:SetFont("TelephoneButton")
		dialBtn:SetTextColor(Color(100, 255, 100))
		
		dialBtn.Paint = zeroBtn.Paint
		
		dialBtn.DoClick = function()
			if string.len(enteredDigits) == 3 or string.len(enteredDigits) == 4 then
				local dialedNum = enteredDigits
				if string.len(enteredDigits) == 4 then
					dialedNum = string.sub(enteredDigits, 1, 1) .. "-" .. string.sub(enteredDigits, 2, 4)
				end
				net.Start("Telephone_DialNumber")
					net.WriteEntity(telephone)
					net.WriteString(dialedNum)
				net.SendToServer()
				dialMenu:Remove()
				surface.PlaySound("buttons/button14.wav")
			else
				display:SetText("ENTER 3 OR 4 DIGITS")
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
			if enteredDigits == "" then
				display:SetText("")
			else
				local formatted = enteredDigits
				if string.len(enteredDigits) == 4 then
					formatted = string.sub(enteredDigits, 1, 1) .. "-" .. string.sub(enteredDigits, 2, 4)
				end
				display:SetText(formatted)
			end
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
				if string.len(enteredDigits) < 4 then
					enteredDigits = enteredDigits .. tostring(i)
					UpdateDisplay()
					PlayRandomDialSound()
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
			if string.len(enteredDigits) < 4 then
				enteredDigits = enteredDigits .. "0"
				UpdateDisplay()
				PlayRandomDialSound()
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
			PlayRandomDialSound()
		end
		
		local multiCheck = vgui.Create("DCheckBoxLabel", adminMenu)
		multiCheck:SetPos(70, buttonY + 290)
		multiCheck:SetText("Multi Station")
		multiCheck:SetTextColor(Color(255, 255, 255))
		multiCheck:SetValue(multiStation)
		multiCheck:SizeToContents()
		
		multiCheck.OnChange = function(self, val)
			multiStation = val
		end
		
		local genBtn = vgui.Create("DButton", adminMenu)
		genBtn:SetSize(175, 40)
		genBtn:SetPos(70, buttonY + 320)
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
			enteredDigits = tostring(math.random(0, 9999))
			while #enteredDigits < 4 do
				enteredDigits = "0" .. enteredDigits
			end
			UpdateDisplay()
			PlayRandomDialSound()
		end
		
		local confirmBtn = vgui.Create("DButton", adminMenu)
		confirmBtn:SetSize(175, 40)
		confirmBtn:SetPos(255, buttonY + 320)
		confirmBtn:SetText("CONFIRM")
		confirmBtn:SetFont("TelephoneButton")
		confirmBtn:SetTextColor(Color(100, 255, 100))
		
		confirmBtn.Paint = genBtn.Paint
		
		confirmBtn.DoClick = function()
			if string.len(enteredDigits) == 3 or string.len(enteredDigits) == 4 then
				net.Start("Telephone_UpdateNumber")
					net.WriteEntity(telephone)
					net.WriteString(enteredDigits)
					net.WriteBool(multiStation)
				net.SendToServer()
				adminMenu:Remove()
				surface.PlaySound("buttons/button14.wav")
			else
				display:SetText("ENTER 3 OR 4 DIGITS")
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