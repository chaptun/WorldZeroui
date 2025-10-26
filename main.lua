
-- ========================================
-- 🎮 SCRIPT (ห้ามแก้ด้านล่างนี้)
-- ========================================

-- Credits To The Original Devs @xz, @goof
-- Modified Auto Farm System
local TweenService = game:GetService("TweenService")
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")
local Config = _G.CONFIG or {}

local player = Players.LocalPlayer
local character = player.Character or player.CharacterAdded:Wait()
local humanoidRootPart = character:WaitForChild("HumanoidRootPart")
local humanoid = character:WaitForChild("Humanoid")

getgenv().Config = {
	Invite = "informant.wtf",
	Version = "1.0",
}

getgenv().luaguardvars = {
	DiscordName = "username#0000",
}

-- CONFIG - Default Values
local DEFAULT_CONFIG = {
    AUTO_FARM = false,
    AUTO_FARM_ALL = false,
    SELECTED_MOB = nil,
    KILL_AURA = false,
    KILL_AURA_RANGE = 50,
    AUTO_COLLECT_COINS = true,
    COIN_COLLECTION_RANGE = 100,
    AUTO_NEXT = false,
    AUTO_START = false,
    AUTO_SPAWN_BOSS = false,
    TELEPORT_METHOD = "TWEEN",
    TWEEN_SPEED = 100,
    ORBIT_RADIUS = 20,
    ORBIT_SPEED = 2,
    ORBIT_HEIGHT = 15,
    ATTACK_RANGE = 15,
    BURST_ATTACK_SPEED = 0.15,
    BURST_MIN = 30,
    BURST_MAX = 60,
    REST_DURATION = 5,
    USE_SKILLS = true,
    SKILL_COOLDOWN = 3,
    AUTO_CHEST = false,
    CHEST_BOX_1 = {X = 619, Y = 704},
    CHEST_BOX_2 = {X = 945, Y = 704},
    CHEST_BOX_3 = {X = 1287, Y = 704},
    CHEST_OPEN_BUTTON = {X = 950, Y = 455},
    CHEST_CLOSE_BUTTON = {X = 822, Y = 1010},
    CHEST_WAIT_BEFORE_START = 2,
    CHEST_WAIT_BEFORE_OPEN = 2,
    CHEST_WAIT_BEFORE_CLOSE = 2,
    CHEST_OPEN_CLICKS = 10,
    CHEST_OPEN_CLICK_DELAY = 0.01,
}

-- Merge with existing _G.CONFIG
if not _G.CONFIG then
    _G.CONFIG = {}
end

for key, value in pairs(DEFAULT_CONFIG) do
    if _G.CONFIG[key] == nil then
        _G.CONFIG[key] = value
    end
end

-- STATE
local State = {
    enabled = false,
    currentMob = nil,
    orbitAngle = 0,
    inBurst = false,
    burstAttacks = 0,
    isResting = false,
    totalAttacks = 0,
    totalSkills = 0,
    totalKills = 0,
    currentSkillIndex = 1,
    lastSkillTime = 0,
    startTime = tick(),
    killedMobs = {},
}

local noclipConnection = nil
local currentTween = nil
local killAuraConnection = nil
local autoFarmConnection = nil
local coinCollectionConnection = nil
local autoNextConnection = nil
local autoStartConnection = nil
local autoSpawnBossConnection = nil
local Remotes = {}

-- INIT REMOTES
local function InitRemotes()
    if Remotes.Attack then return true end
    local success = pcall(function()
        local combat = ReplicatedStorage.Shared.Combat
        Remotes.SetTrails = combat.SetTrails
        Remotes.Attack = combat.Attack
        local skillsets = combat.Skillsets
        Remotes.MagePrimary = skillsets.Mage.Primary
        Remotes.MageFireball = skillsets.Mage.Fireball
        pcall(function() Remotes.LeviathanBubble = skillsets.Leviathan.PoppingBubbleDamage end)
    end)
    return success
end

-- NOCLIP
local function StartNoclip()
    if noclipConnection then return end
    noclipConnection = RunService.Stepped:Connect(function()
        if (_G.CONFIG.AUTO_FARM or _G.CONFIG.AUTO_FARM_ALL or _G.CONFIG.KILL_AURA or _G.CONFIG.AUTO_COLLECT_COINS) and character then
            for _, part in pairs(character:GetDescendants()) do
                if part:IsA("BasePart") then 
                    part.CanCollide = false 
                end
            end
        end
    end)
end

local function StopNoclip()
    if noclipConnection then 
        noclipConnection:Disconnect() 
        noclipConnection = nil
    end
    if character then
        for _, part in pairs(character:GetDescendants()) do
            if part:IsA("BasePart") and part.Name ~= "HumanoidRootPart" then
                part.CanCollide = true
            end
        end
    end
end

local autoChestConnection = nil
local ChestState = {
    isRunning = false,
    currentRound = 0,
    selectedChests = {},
}

local function IsChestGUIVisible()
    local success, result = pcall(function()
        return player.PlayerGui:FindFirstChild("MissionRewards") 
            and player.PlayerGui.MissionRewards:FindFirstChild("MissionRewards")
            and player.PlayerGui.MissionRewards.MissionRewards.Chests.Visible == true
    end)
    return success and result
end

local function WaitForChestGUI(timeout)
    timeout = timeout or 30
    local startTime = tick()
    
    print("⏳ รอ MissionRewards GUI...")
    
    while not IsChestGUIVisible() do
        if tick() - startTime > timeout then
            warn("❌ Timeout: GUI ไม่ปรากฏภายใน " .. timeout .. " วินาที")
            return false
        end
        task.wait(0.5)
    end
    
    print("✅ พบ MissionRewards GUI!")
    return true
end

local function ClickAtPosition(x, y)
    print(string.format("🎯 คลิกที่: X=%d, Y=%d", x, y))
    
    mousemoveabs(x, y)
    task.wait(0.1)
    mouse1click()
    task.wait(0.05)
    mouse1click()
    task.wait(0.1)
    
    print("✅ คลิกสำเร็จ!")
    task.wait(0.2)
end

local function GetRandomChest(excludeChest)
    local availableChests = {}
    
    for i = 1, 3 do
        if i ~= excludeChest then
            table.insert(availableChests, i)
        end
    end
    
    return availableChests[math.random(1, #availableChests)]
end

local function OpenChestRound(chestNumber, roundNumber)
    print("\n" .. string.rep("=", 60))
    print(string.format("🎲 [รอบที่ %d] กล่องที่: %d", roundNumber, chestNumber))
    print(string.rep("=", 60))
    
    local boxPosition
    if chestNumber == 1 then
        boxPosition = _G.CONFIG.CHEST_BOX_1
    elseif chestNumber == 2 then
        boxPosition = _G.CONFIG.CHEST_BOX_2
    else
        boxPosition = _G.CONFIG.CHEST_BOX_3
    end
    
    print("🎁 [ขั้นที่ 1] กำลังคลิกเลือกกล่อง...")
    ClickAtPosition(boxPosition.X, boxPosition.Y)
    
    print(string.format("⏳ [ขั้นที่ 2] รอ %d วินาที...", _G.CONFIG.CHEST_WAIT_BEFORE_OPEN))
    task.wait(_G.CONFIG.CHEST_WAIT_BEFORE_OPEN)
    
    print(string.format("🔓 [ขั้นที่ 3] กำลังคลิกเปิดกล่อง (%d ครั้ง)...", _G.CONFIG.CHEST_OPEN_CLICKS))
    for i = 1, _G.CONFIG.CHEST_OPEN_CLICKS do
        if not _G.CONFIG.AUTO_CHEST then break end
        ClickAtPosition(_G.CONFIG.CHEST_OPEN_BUTTON.X, _G.CONFIG.CHEST_OPEN_BUTTON.Y)
        task.wait(_G.CONFIG.CHEST_OPEN_CLICK_DELAY)
    end
    
    print(string.format("⏳ [ขั้นที่ 4] รอ %d วินาที...", _G.CONFIG.CHEST_WAIT_BEFORE_CLOSE))
    task.wait(_G.CONFIG.CHEST_WAIT_BEFORE_CLOSE)
    
    print("❌ [ขั้นที่ 5] กำลังกดปิด...")
    ClickAtPosition(_G.CONFIG.CHEST_CLOSE_BUTTON.X, _G.CONFIG.CHEST_CLOSE_BUTTON.Y)
    
    print(string.rep("-", 60))
    print(string.format("✅ รอบที่ %d เสร็จสิ้น!", roundNumber))
    print(string.rep("-", 60))
end

local function AutoOpenChests()
    if ChestState.isRunning then
        print("⚠️ Auto Chest กำลังทำงานอยู่แล้ว")
        return
    end
    
    ChestState.isRunning = true
    ChestState.selectedChests = {}
    
    print("\n" .. string.rep("=", 60))
    print("🎮 เริ่มระบบเปิดกล่องอัตโนมัติ")
    print(string.rep("=", 60))
    
    if not WaitForChestGUI(30) then
        warn("❌ ไม่พบ MissionRewards GUI")
        ChestState.isRunning = false
        return false
    end
    
    print(string.format("⏳ รอ %d วินาที (ป้องกันบัค)...", _G.CONFIG.CHEST_WAIT_BEFORE_START))
    task.wait(_G.CONFIG.CHEST_WAIT_BEFORE_START)
    
    local firstChest = math.random(1, 3)
    ChestState.selectedChests[1] = firstChest
    ChestState.currentRound = 1
    OpenChestRound(firstChest, 1)
    
    if not _G.CONFIG.AUTO_CHEST then
        ChestState.isRunning = false
        return false
    end
    
    task.wait(0.5)
    
    local secondChest = GetRandomChest(firstChest)
    ChestState.selectedChests[2] = secondChest
    ChestState.currentRound = 2
    OpenChestRound(secondChest, 2)
    
    print("\n" .. string.rep("=", 60))
    print("🎉 เสร็จสิ้นทั้งหมด 2 รอบ!")
    print(string.format("📦 กล่องที่เลือก: รอบ 1 = Box%d, รอบ 2 = Box%d", firstChest, secondChest))
    print(string.rep("=", 60))
    
    ChestState.isRunning = false
    ChestState.currentRound = 0
    return true
end

local function StartAutoChest()
    if autoChestConnection then return end
    
    autoChestConnection = task.spawn(function()
        while true do
            task.wait(2)
            
            if not _G.CONFIG.AUTO_CHEST then 
                task.wait(1)
                continue 
            end
            
            if IsChestGUIVisible() and not ChestState.isRunning then
                print("🎁 พบ MissionRewards GUI! เริ่มเปิดกล่อง...")
                AutoOpenChests()
                
                while IsChestGUIVisible() and _G.CONFIG.AUTO_CHEST do
                    task.wait(1)
                end
                
                print("✅ GUI หายแล้ว รอรอบถัดไป...")
            end
            
            task.wait(3)
        end
    end)
end

local function StopAutoChest()
    _G.CONFIG.AUTO_CHEST = false
    ChestState.isRunning = false
end

local function GetMobPosition(mob)
    if mob:FindFirstChild("HumanoidRootPart") then 
        return mob.HumanoidRootPart
    elseif mob:FindFirstChild("Collider") then 
        return mob.Collider
    elseif mob:FindFirstChild("Model") and mob.Model:FindFirstChild("HumanoidRootPart") then 
        return mob.Model.HumanoidRootPart
    end
    return nil
end

local function GetMobHealth(mob)
    local hp = mob:FindFirstChild("HealthProperties")
    if hp then hp = hp:FindFirstChild("Health") end
    if not hp then hp = mob:FindFirstChild("Health") end
    if not hp then
        local model = mob:FindFirstChild("Model") or mob
        hp = model:FindFirstChild("Humanoid")
    end
    return hp
end

local function IsMobAlive(mob)
    if not mob or not mob.Parent then return false end
    local health = GetMobHealth(mob)
    if not health then return false end
    local hp = health.Value or health.Health
    return hp > 0
end

local function FindNearestMob()
    if not _G.CONFIG.SELECTED_MOB or not Workspace:FindFirstChild("Mobs") then return nil end
    
    local nearest, shortestDist = nil, math.huge
    
    for _, mob in pairs(Workspace.Mobs:GetChildren()) do
        if mob.Name == _G.CONFIG.SELECTED_MOB and IsMobAlive(mob) then
            local mobPart = GetMobPosition(mob)
            if mobPart then
                local dist = (humanoidRootPart.Position - mobPart.Position).Magnitude
                if dist < shortestDist then
                    shortestDist = dist
                    nearest = mob
                end
            end
        end
    end
    
    return nearest
end

local function FindAllMobs()
    if not Workspace:FindFirstChild("Mobs") then return {} end
    
    local mobs = {}
    for _, mob in pairs(Workspace.Mobs:GetChildren()) do
        if IsMobAlive(mob) and not State.killedMobs[mob] then
            table.insert(mobs, mob)
        end
    end
    
    return mobs
end

local function TeleportTo(position)
    if character and humanoidRootPart then
        humanoidRootPart.CFrame = CFrame.new(position)
    end
end

local function TweenTo(position)
    if not character or not humanoidRootPart then return end
    if currentTween then currentTween:Cancel() end
    local distance = (humanoidRootPart.Position - position).Magnitude
    local duration = distance / _G.CONFIG.TWEEN_SPEED
    local tweenInfo = TweenInfo.new(duration, Enum.EasingStyle.Linear)
    currentTween = TweenService:Create(humanoidRootPart, tweenInfo, {CFrame = CFrame.new(position)})
    currentTween:Play()
end

local function OrbitMob(mob)
    local mobPart = GetMobPosition(mob)
    if not mobPart then return end
    
    State.orbitAngle = State.orbitAngle + _G.CONFIG.ORBIT_SPEED
    if State.orbitAngle >= 360 then State.orbitAngle = 0 end
    
    local angle = math.rad(State.orbitAngle)
    local x = mobPart.Position.X + math.cos(angle) * _G.CONFIG.ORBIT_RADIUS
    local z = mobPart.Position.Z + math.sin(angle) * _G.CONFIG.ORBIT_RADIUS
    local y = mobPart.Position.Y + _G.CONFIG.ORBIT_HEIGHT
    
    local targetPos = Vector3.new(x, y, z)
    
    if _G.CONFIG.TELEPORT_METHOD == "TP" then
        humanoidRootPart.CFrame = CFrame.new(targetPos, mobPart.Position)
    else
        if currentTween then currentTween:Cancel() end
        local distance = (humanoidRootPart.Position - targetPos).Magnitude
        local duration = distance / _G.CONFIG.TWEEN_SPEED
        local tweenInfo = TweenInfo.new(duration, Enum.EasingStyle.Linear)
        currentTween = TweenService:Create(humanoidRootPart, tweenInfo, {CFrame = CFrame.new(targetPos, mobPart.Position)})
        currentTween:Play()
    end
end

local function UseSkill1(mob)
    if not mob or not InitRemotes() then return false end
    local mobPart = GetMobPosition(mob)
    if not mobPart then return false end
    pcall(function()
        if Remotes.MageFireball then Remotes.MageFireball:FireServer(mob) end
        task.wait(0.02)
        Remotes.Attack:FireServer("ArcaneBlastAOE", mobPart.Position, nil, 67)
        task.wait(0.02)
        Remotes.Attack:FireServer("ArcaneBlast", mobPart.Position, nil, 67)
    end)
    return true
end

local function UseSkill2(mob)
    if not mob or not InitRemotes() then return false end
    local mobPart = GetMobPosition(mob)
    if not mobPart then return false end
    pcall(function()
        Remotes.SetTrails:FireServer(true)
        task.wait(0.02)
        Remotes.SetTrails:FireServer(false)
        task.wait(0.02)
        for i = 1, 12 do
            Remotes.Attack:FireServer("ArcaneWave" .. i, mobPart.Position, nil, 67)
            task.wait(0.01)
        end
    end)
    return true
end

local function UseSkill3(mob)
    if not mob or not InitRemotes() then return false end
    local mobPart = GetMobPosition(mob)
    if not mobPart then return false end
    pcall(function()
        Remotes.SetTrails:FireServer(true)
        task.wait(0.02)
        Remotes.SetTrails:FireServer(false)
        task.wait(0.02)
        Remotes.Attack:FireServer("ArcaneWave1", mobPart.Position, nil, 67)
        task.wait(0.01)
        if Remotes.LeviathanBubble then Remotes.LeviathanBubble:FireServer(Instance.new("Model")) end
        task.wait(0.01)
        for i = 2, 6 do
            Remotes.Attack:FireServer("ArcaneWave" .. i, mobPart.Position, nil, 67)
            task.wait(0.01)
        end
        if Remotes.LeviathanBubble then Remotes.LeviathanBubble:FireServer(Instance.new("Model")) end
        task.wait(0.01)
        for i = 7, 12 do
            Remotes.Attack:FireServer("ArcaneWave" .. i, mobPart.Position, nil, 67)
            task.wait(0.01)
        end
    end)
    return true
end

local function UseNextSkill(mob)
    if not _G.CONFIG.USE_SKILLS or not mob then return false end
    
    local currentTime = tick()
    if currentTime - State.lastSkillTime < _G.CONFIG.SKILL_COOLDOWN then
        return false
    end
    
    local success = false
    
    if State.currentSkillIndex == 1 then
        success = UseSkill1(mob)
        State.currentSkillIndex = 2
    elseif State.currentSkillIndex == 2 then
        success = UseSkill2(mob)
        State.currentSkillIndex = 3
    else
        success = UseSkill3(mob)
        State.currentSkillIndex = 1
    end
    
    if success then
        State.totalSkills = State.totalSkills + 1
        State.lastSkillTime = currentTime
    end
    
    return success
end

local function Attack(mob)
    if not mob or not InitRemotes() or not IsMobAlive(mob) then return false end
    local mobPart = GetMobPosition(mob)
    if not mobPart then return false end
    
    local success = pcall(function()
        if Remotes.MagePrimary then 
            Remotes.MagePrimary:FireServer(mob) 
        end
        if Remotes.Attack then 
            Remotes.Attack:FireServer("Mage1", mobPart.Position, nil, 67) 
        end
    end)
    
    if success then
        State.burstAttacks = State.burstAttacks + 1
        State.totalAttacks = State.totalAttacks + 1
    end
    
    return success
end

local function StartKillAura()
    if killAuraConnection then return end
    
    killAuraConnection = RunService.Heartbeat:Connect(function()
        if not _G.CONFIG.KILL_AURA or not Workspace:FindFirstChild("Mobs") then return end
        
        for _, mob in pairs(Workspace.Mobs:GetChildren()) do
            if IsMobAlive(mob) then
                local mobPart = GetMobPosition(mob)
                if mobPart then
                    local distance = (humanoidRootPart.Position - mobPart.Position).Magnitude
                    if distance <= _G.CONFIG.KILL_AURA_RANGE then
                        Attack(mob)
                    end
                end
            end
        end
    end)
end

local function StopKillAura()
    if killAuraConnection then
        killAuraConnection:Disconnect()
        killAuraConnection = nil
    end
end

local function StartCoinCollection()
    if coinCollectionConnection then return end
    
    coinCollectionConnection = RunService.Heartbeat:Connect(function()
        if not _G.CONFIG.AUTO_COLLECT_COINS or not Workspace:FindFirstChild("Coins") then return end
        
        for _, coin in pairs(Workspace.Coins:GetChildren()) do
            if coin.Name == "CoinPart" and coin:IsA("BasePart") then
                local distance = (humanoidRootPart.Position - coin.Position).Magnitude
                
                if distance <= _G.CONFIG.COIN_COLLECTION_RANGE then
                    coin.CanCollide = false
                    coin.CFrame = humanoidRootPart.CFrame
                end
            end
        end
    end)
end

local function StopCoinCollection()
    if coinCollectionConnection then
        coinCollectionConnection:Disconnect()
        coinCollectionConnection = nil
    end
end

local function CheckMobsRemaining()
    if not Workspace:FindFirstChild("Mobs") then return 0 end
    local count = 0
    for _, mob in pairs(Workspace.Mobs:GetChildren()) do
        if IsMobAlive(mob) then
            count = count + 1
        end
    end
    return count
end

local function GetNextCabbage()
    if not Workspace:FindFirstChild("MissionObjects") then return nil end
    if not Workspace.MissionObjects:FindFirstChild("Cabbages") then return nil end
    
    for _, cabbage in pairs(Workspace.MissionObjects.Cabbages:GetChildren()) do
        if cabbage:FindFirstChild("Main") then
            return cabbage.Main
        end
    end
    return nil
end

local function GetMissionStart()
    if not Workspace:FindFirstChild("MissionObjects") then return nil end
    if not Workspace.MissionObjects:FindFirstChild("MissionStart") then return nil end
    if not Workspace.MissionObjects.MissionStart:FindFirstChild("MissionTimer") then return nil end
    return Workspace.MissionObjects.MissionStart.MissionTimer
end

local function GetCaveTrigger()
    if not Workspace:FindFirstChild("MissionObjects") then 
        print("⚠️ MissionObjects not found for CaveTrigger!")
        return nil 
    end
    if not Workspace.MissionObjects:FindFirstChild("CaveTrigger") then 
        print("⚠️ CaveTrigger not found!")
        return nil 
    end
    print("🗿 CaveTrigger found!")
    return Workspace.MissionObjects.CaveTrigger
end

local function StartAutoNext()
    if autoNextConnection then return end
    
    autoNextConnection = task.spawn(function()
        while true do
            task.wait(1)
            
            if not _G.CONFIG.AUTO_NEXT then 
                task.wait(1)
                continue 
            end
            
            local mobCount = CheckMobsRemaining()
            
            if mobCount == 0 then
                local nextCabbage = GetNextCabbage()
                
                if nextCabbage then
                    print("🥬 Found next cabbage! Teleporting...")
                    
                    if _G.CONFIG.TELEPORT_METHOD == "TP" then
                        TeleportTo(nextCabbage.Position)
                    else
                        TweenTo(nextCabbage.Position)
                        if currentTween then
                            currentTween.Completed:Wait()
                        end
                    end
                    
                    task.wait(2)
                    print("✅ Arrived! Resuming farm...")
                else
                    print("⚠️ No more cabbages found!")
                end
            end
            
            task.wait(2)
        end
    end)
end

local function StopAutoNext()
    _G.CONFIG.AUTO_NEXT = false
end

local function StartAutoStart()
    if autoStartConnection then return end
    
    autoStartConnection = task.spawn(function()
        while true do
            task.wait(1)
            
            if not _G.CONFIG.AUTO_START then 
                task.wait(1)
                continue 
            end
            
            local missionStart = GetMissionStart()
            
            if missionStart then
                print("🎬 Mission Start found! Teleporting...")
                
                if _G.CONFIG.TELEPORT_METHOD == "TP" then
                    TeleportTo(missionStart.Position)
                else
                    TweenTo(missionStart.Position)
                    if currentTween then
                        currentTween.Completed:Wait()
                    end
                end
                task.wait(3)
                
                while GetMissionStart() and _G.CONFIG.AUTO_START do
                    task.wait(1)
                end
                
                print("✅ Mission started! Resuming farm...")
            end
            
            task.wait(2)
        end
    end)
end

local function StopAutoStart()
    _G.CONFIG.AUTO_START = false
end

local function FarmMob(mob)
    if not mob then return end
    State.orbitAngle = 0
    State.lastSkillTime = 0
    
    while IsMobAlive(mob) and (_G.CONFIG.AUTO_FARM or _G.CONFIG.AUTO_FARM_ALL) do
        if not character or not character.Parent then
            character = player.Character
            if character then
                humanoidRootPart = character:WaitForChild("HumanoidRootPart", 5)
                humanoid = character:WaitForChild("Humanoid", 5)
            end
            task.wait(1)
            continue
        end
        
        local mobPart = GetMobPosition(mob)
        if not mobPart then break end
        
        local distance = (humanoidRootPart.Position - mobPart.Position).Magnitude
        
        if distance > _G.CONFIG.ATTACK_RANGE then
            if _G.CONFIG.TELEPORT_METHOD == "TP" then
                TeleportTo(mobPart.Position)
            else
                TweenTo(mobPart.Position)
            end
            task.wait(0.3)
            continue
        end
        
        OrbitMob(mob)
        
        if _G.CONFIG.USE_SKILLS then
            local timeSinceLastSkill = tick() - State.lastSkillTime
            if timeSinceLastSkill >= _G.CONFIG.SKILL_COOLDOWN then
                UseNextSkill(mob)
            end
        end
        
        if not State.inBurst and not State.isResting then
            State.inBurst = true
            State.burstAttacks = 0
            local burstMax = math.random(_G.CONFIG.BURST_MIN, _G.CONFIG.BURST_MAX)
            
            while State.burstAttacks < burstMax and IsMobAlive(mob) and (_G.CONFIG.AUTO_FARM or _G.CONFIG.AUTO_FARM_ALL) do
                Attack(mob)
                OrbitMob(mob)
                task.wait(_G.CONFIG.BURST_ATTACK_SPEED)
            end
            
            State.inBurst = false
            
            if _G.CONFIG.USE_SKILLS then
                task.wait(0.5)
                UseNextSkill(mob)
            end
            
            State.isResting = true
            for i = _G.CONFIG.REST_DURATION, 1, -1 do
                if not IsMobAlive(mob) or not (_G.CONFIG.AUTO_FARM or _G.CONFIG.AUTO_FARM_ALL) then break end
                OrbitMob(mob)
                task.wait(1)
            end
            State.isResting = false
        end
        
        task.wait(0.1)
    end
    
    if not IsMobAlive(mob) then
        State.totalKills = State.totalKills + 1
        State.killedMobs[mob] = true
    end
end

local function StartAutoFarm()
    if autoFarmConnection then return end
    
    task.spawn(function()
        task.wait(2)
        if not InitRemotes() then 
            warn("❌ Remotes failed") 
            return 
        end
        
        while true do
            task.wait(0.1)
            
            if not _G.CONFIG.AUTO_FARM and not _G.CONFIG.AUTO_FARM_ALL then 
                task.wait(0.1) 
                continue 
            end
            
            if _G.CONFIG.AUTO_FARM then
                if not _G.CONFIG.SELECTED_MOB then 
                    task.wait(0.1) 
                    continue 
                end
                
                local mob = FindNearestMob()
                if not mob then 
                    print("⏸️ No mobs found! Waiting 5 seconds...")
                    task.wait(5)
                    continue 
                end
                
                State.currentMob = mob
                FarmMob(mob)
                State.currentMob = nil
                
            elseif _G.CONFIG.AUTO_FARM_ALL then
                local mobs = FindAllMobs()
                if #mobs == 0 then
                    State.killedMobs = {}
                    print("⏸️ All mobs cleared! Resting 12 seconds...")
                    task.wait(12)
                    print("✅ Resuming farm...")
                    continue
                end
                
                for _, mob in pairs(mobs) do
                    if not (_G.CONFIG.AUTO_FARM_ALL) or not IsMobAlive(mob) then break end
                    State.currentMob = mob
                    FarmMob(mob)
                    State.currentMob = nil
                    task.wait(0.5)
                end
            end
            
            task.wait(0.5)
        end
    end)
end

local function StopAutoFarm()
    if autoFarmConnection then
        autoFarmConnection:Disconnect()
        autoFarmConnection = nil
    end
    if currentTween then
        currentTween:Cancel()
    end
    State.killedMobs = {}
end

local function GetMobList()
    if not Workspace:FindFirstChild("Mobs") then return {} end
    local mobNames = {}
    for _, mob in pairs(Workspace.Mobs:GetChildren()) do
        if not table.find(mobNames, mob.Name) then
            table.insert(mobNames, mob.Name)
        end
    end
    table.sort(mobNames)
    return mobNames
end

local function CheckProgressionBlocker()
    if not Workspace:FindFirstChild("MissionObjects") then 
        print("⚠️ MissionObjects not found!")
        return true
    end
    
    local blocker = Workspace.MissionObjects:FindFirstChild("ProgressionBlocker3")
    
    if blocker then
        print("🚫 ProgressionBlocker3 still exists - Not ready to spawn boss")
        return true
    else
        print("✅ ProgressionBlocker3 removed - Ready to spawn boss!")
        return false
    end
end

local function StartAutoSpawnBoss()
    if autoSpawnBossConnection then return end
    
    autoSpawnBossConnection = task.spawn(function()
        print("🎮 Auto Spawn Boss started!")
        
        while true do
            task.wait(2)
            
            if not _G.CONFIG.AUTO_SPAWN_BOSS then 
                task.wait(1)
                continue 
            end
            
            local hasBlocker = CheckProgressionBlocker()
            
            if not hasBlocker then
                print("✅ ProgressionBlocker3 removed! Going to spawn boss...")
                
                local caveTrigger = GetCaveTrigger()
                
                if caveTrigger then
                    print("🗿 Teleporting to Cave Trigger...")
                    
                    if _G.CONFIG.TELEPORT_METHOD == "TP" then
                        TeleportTo(caveTrigger.Position)
                        print("⚡ Teleported!")
                    else
                        TweenTo(caveTrigger.Position)
                        if currentTween then
                            print("🚶 Tweening to Cave...")
                            currentTween.Completed:Wait()
                            print("✅ Arrived!")
                        end
                    end
                    
                    task.wait(3)
                    print("👹 Boss should be spawned! Resuming farm...")
                    task.wait(10)
                else
                    print("❌ CaveTrigger not found! Waiting...")
                    task.wait(5)
                end
            else
                task.wait(3)
            end
        end
    end)
end

local function StopAutoSpawnBoss()
    _G.CONFIG.AUTO_SPAWN_BOSS = false
end

-- LOAD UI
local library = loadstring(game:HttpGet("https://raw.githubusercontent.com/drillygzzly/Other/main/1"))()
library:init()

local Window = library.NewWindow({
	title = "Informant.Wtf | Auto Farm",
	size = UDim2.new(0, 525, 0, 650)
})

local tabs = {
    AutoFarm = Window:AddTab("Auto Farm"),
    Combat = Window:AddTab("Combat"),
    Mission = Window:AddTab("Mission"),
    Misc = Window:AddTab("Misc"),
    Settings = Window:AddTab("Settings"),
    ConfigTab = library:CreateSettingsTab(Window),
}

local sections = {
    MainFarm = tabs.AutoFarm:AddSection("Main Farm", 1),
    MobSelection = tabs.AutoFarm:AddSection("Mob Selection", 2),
    KillAura = tabs.Combat:AddSection("Kill Aura", 1),
    Skills = tabs.Combat:AddSection("Skills", 1),
    Burst = tabs.Combat:AddSection("Burst Settings", 2),
    MissionAuto = tabs.Mission:AddSection("Mission Automation", 1),
    MissionInfo = tabs.Mission:AddSection("Mission Info", 2),
    CoinCollection = tabs.Misc:AddSection("Coin Collection", 1),
    ChestOpener = tabs.Misc:AddSection("Chest Opener", 1),
    Movement = tabs.Settings:AddSection("Movement", 1),
    Position = tabs.Settings:AddSection("Position", 1),
    Stats = tabs.Settings:AddSection("Stats", 2),
}

sections.MainFarm:AddToggle({
	enabled = true,
	text = "Auto Farm (Selected Mob)",
	flag = "AutoFarm",
	tooltip = "Farm selected mob automatically",
	risky = false,
	callback = function(v)
	    _G.CONFIG.AUTO_FARM = v
	    if v then
	        _G.CONFIG.AUTO_FARM_ALL = false
	        StartNoclip()
	        StartAutoFarm()
	        library:SendNotification("Auto Farm Started!", 3, Color3.fromRGB(0, 255, 0))
	    else
	        StopAutoFarm()
	        if not _G.CONFIG.KILL_AURA then
	            StopNoclip()
	        end
	        library:SendNotification("Auto Farm Stopped!", 3, Color3.fromRGB(255, 0, 0))
	    end
	end
})

sections.MainFarm:AddToggle({
	enabled = true,
	text = "Auto Farm All Mobs",
	flag = "AutoFarmAll",
	tooltip = "Farm all mobs in dungeon",
	risky = true,
	callback = function(v)
	    _G.CONFIG.AUTO_FARM_ALL = v
	    if v then
	        _G.CONFIG.AUTO_FARM = false
	        StartNoclip()
	        StartAutoFarm()
	        library:SendNotification("Auto Farm All Started!", 3, Color3.fromRGB(0, 255, 0))
	    else
	        StopAutoFarm()
	        if not _G.CONFIG.KILL_AURA then
	            StopNoclip()
	        end
	        library:SendNotification("Auto Farm All Stopped!", 3, Color3.fromRGB(255, 0, 0))
	    end
	end
})

sections.MainFarm:AddButton({
	enabled = true,
	text = "Refresh Mob List",
	flag = "RefreshMobs",
	tooltip = "Refresh available mobs",
	risky = false,
	callback = function()
	    local mobList = GetMobList()
	    library:SendNotification("Found " .. #mobList .. " mob types!", 3, Color3.fromRGB(0, 200, 255))
	end
})

local mobList = GetMobList()
sections.MobSelection:AddList({
	enabled = true,
	text = "Select Mob",
	flag = "MobList",
	multi = false,
	tooltip = "Choose mob to farm",
    risky = false,
	value = mobList[1] or "None",
	values = mobList,
	callback = function(v)
	    _G.CONFIG.SELECTED_MOB = v
	    library:SendNotification("Selected: " .. v, 2, Color3.fromRGB(255, 255, 0))
	end
})

sections.MissionAuto:AddToggle({
	enabled = true,
	text = "Auto Start Mission",
	flag = "AutoStart",
	tooltip = "Auto teleport to mission start and wait for mission to begin",
	risky = false,
	callback = function(v)
	    _G.CONFIG.AUTO_START = v
	    if v then
	        StartAutoStart()
	        library:SendNotification("Auto Start Enabled!", 3, Color3.fromRGB(0, 255, 100))
	    else
	        StopAutoStart()
	        library:SendNotification("Auto Start Disabled!", 3, Color3.fromRGB(255, 100, 0))
	    end
	end
})

sections.MissionAuto:AddToggle({
	enabled = true,
	text = "Auto Next Cabbage",
	flag = "AutoNext",
	tooltip = "Auto teleport to next cabbage when mobs are cleared",
	risky = false,
	callback = function(v)
	    _G.CONFIG.AUTO_NEXT = v
	    if v then
	        StartAutoNext()
	        library:SendNotification("Auto Next Enabled!", 3, Color3.fromRGB(0, 255, 100))
	    else
	        StopAutoNext()
	        library:SendNotification("Auto Next Disabled!", 3, Color3.fromRGB(255, 100, 0))
	    end
	end
})

sections.MissionAuto:AddToggle({
	enabled = true,
	text = "Auto Spawn Boss",
	flag = "AutoSpawnBoss",
	tooltip = "Auto trigger boss spawn when ProgressionBlocker3 removed",
	risky = false,
	callback = function(v)
	    _G.CONFIG.AUTO_SPAWN_BOSS = v
	    if v then
	        StartAutoSpawnBoss()
	        library:SendNotification("Auto Spawn Boss Enabled!", 3, Color3.fromRGB(255, 50, 50))
	    else
	        StopAutoSpawnBoss()
	        library:SendNotification("Auto Spawn Boss Disabled!", 3, Color3.fromRGB(100, 100, 100))
	    end
	end
})

sections.MissionInfo:AddButton({
	enabled = true,
	text = "Check Mobs Remaining",
	flag = "CheckMobs",
	tooltip = "Show remaining mobs count",
	risky = false,
	callback = function()
	    local count = CheckMobsRemaining()
	    library:SendNotification("Mobs Remaining: " .. count, 3, Color3.fromRGB(100, 200, 255))
	end
})

sections.MissionInfo:AddButton({
	enabled = true,
	text = "Check Next Cabbage",
	flag = "CheckCabbage",
	tooltip = "Check if next cabbage exists",
	risky = false,
	callback = function()
	    local cabbage = GetNextCabbage()
	    if cabbage then
	        library:SendNotification("Next cabbage found!", 3, Color3.fromRGB(0, 255, 0))
	    else
	        library:SendNotification("No cabbage found!", 3, Color3.fromRGB(255, 0, 0))
	    end
	end
})

sections.MissionInfo:AddButton({
	enabled = true,
	text = "Check Progression Blocker",
	flag = "CheckBlocker",
	tooltip = "Check if ProgressionBlocker3 exists",
	risky = false,
	callback = function()
	    local hasBlocker = CheckProgressionBlocker()
	    if hasBlocker then
	        library:SendNotification("ProgressionBlocker3 still exists!", 3, Color3.fromRGB(255, 200, 0))
	    else
	        library:SendNotification("ProgressionBlocker3 removed! Ready to spawn boss!", 3, Color3.fromRGB(0, 255, 0))
	    end
	end
})

sections.CoinCollection:AddToggle({
	enabled = true,
	text = "Auto Collect Coins",
	flag = "AutoCollectCoins",
	tooltip = "Automatically collect nearby coins",
	risky = false,
	callback = function(v)
	    _G.CONFIG.AUTO_COLLECT_COINS = v
	    if v then
	        StartNoclip()
	        StartCoinCollection()
	        library:SendNotification("Auto Collect Coins Enabled!", 3, Color3.fromRGB(255, 215, 0))
	    else
	        StopCoinCollection()
	        if not _G.CONFIG.AUTO_FARM and not _G.CONFIG.AUTO_FARM_ALL and not _G.CONFIG.KILL_AURA then
	            StopNoclip()
	        end
	        library:SendNotification("Auto Collect Coins Disabled!", 3, Color3.fromRGB(100, 100, 100))
	    end
	end
})

sections.CoinCollection:AddSlider({
	text = "Collection Range", 
	flag = 'CoinRange', 
	suffix = " studs", 
	value = 25,
	min = 10, 
	max = 100,
	increment = 5,
	tooltip = "Range to collect coins",
	risky = false,
	callback = function(v) 
		_G.CONFIG.COIN_COLLECTION_RANGE = v
	end
})

sections.ChestOpener:AddToggle({
    enabled = true,
    text = "Auto Open Chests",
    flag = "AutoChest",
    tooltip = "Auto open mission reward chests (2 rounds, random, no duplicate)",
    risky = false,
    callback = function(v)
        _G.CONFIG.AUTO_CHEST = v
        if v then
            StartAutoChest()
            library:SendNotification("Auto Chest Enabled!", 3, Color3.fromRGB(255, 200, 50))
        else
            StopAutoChest()
            library:SendNotification("Auto Chest Disabled!", 3, Color3.fromRGB(100, 100, 100))
        end
    end
})

sections.ChestOpener:AddButton({
    enabled = true,
    text = "Open Chests Now (Manual)",
    flag = "ManualChest",
    tooltip = "Manually trigger chest opening",
    risky = false,
    callback = function()
        if ChestState.isRunning then
            library:SendNotification("Already running!", 2, Color3.fromRGB(255, 100, 0))
        else
            task.spawn(AutoOpenChests)
            library:SendNotification("Opening chests...", 3, Color3.fromRGB(100, 200, 255))
        end
    end
})

sections.ChestOpener:AddSlider({
    text = "Wait Before Open", 
    flag = 'ChestWaitOpen', 
    suffix = "s", 
    value = 2,
    min = 1, 
    max = 5,
    increment = 0.5,
    tooltip = "Wait time after selecting chest",
    risky = false,
    callback = function(v) 
        _G.CONFIG.CHEST_WAIT_BEFORE_OPEN = v
    end
})

sections.ChestOpener:AddSlider({
    text = "Open Clicks", 
    flag = 'ChestOpenClicks', 
    suffix = " clicks", 
    value = 10,
    min = 2, 
    max = 20,
    increment = 1,
    tooltip = "Number of clicks to open chest",
    risky = false,
    callback = function(v) 
        _G.CONFIG.CHEST_OPEN_CLICKS = v
    end
})

sections.KillAura:AddToggle({
	enabled = true,
	text = "Kill Aura",
	flag = "KillAura",
	tooltip = "Auto attack nearby mobs",
	risky = true,
	callback = function(v)
	    _G.CONFIG.KILL_AURA = v
	    if v then
	        StartNoclip()
	        StartKillAura()
	        library:SendNotification("Kill Aura Enabled!", 3, Color3.fromRGB(255, 50, 50))
	    else
	        StopKillAura()
	        if not _G.CONFIG.AUTO_FARM and not _G.CONFIG.AUTO_FARM_ALL then
	            StopNoclip()
	        end
	        library:SendNotification("Kill Aura Disabled!", 3, Color3.fromRGB(100, 100, 100))
	    end
	end
})

sections.KillAura:AddSlider({
	text = "Kill Aura Range", 
	flag = 'KillAuraRange', 
	suffix = " studs", 
	value = 50,
	min = 10, 
	max = 200,
	increment = 5,
	tooltip = "Range to attack mobs",
	risky = false,
	callback = function(v) 
		_G.CONFIG.KILL_AURA_RANGE = v
	end
})

sections.Skills:AddToggle({
	enabled = true,
	text = "Use Skills",
	flag = "UseSkills",
	tooltip = "Auto use skills",
	risky = false,
	callback = function(v)
	    _G.CONFIG.USE_SKILLS = v
	end
})

sections.Skills:AddSlider({
	text = "Skill Cooldown", 
	flag = 'SkillCooldown', 
	suffix = "s", 
	value = 3,
	min = 1, 
	max = 10,
	increment = 0.5,
	tooltip = "Time between skills",
	risky = false,
	callback = function(v) 
		_G.CONFIG.SKILL_COOLDOWN = v
	end
})

sections.Burst:AddSlider({
	text = "Burst Min Attacks", 
	flag = 'BurstMin', 
	suffix = "", 
	value = 30,
	min = 10, 
	max = 100,
	increment = 5,
	tooltip = "Minimum burst attacks",
	risky = false,
	callback = function(v) 
		_G.CONFIG.BURST_MIN = v
	end
})

sections.Burst:AddSlider({
	text = "Burst Max Attacks", 
	flag = 'BurstMax', 
	suffix = "", 
	value = 60,
	min = 20, 
	max = 150,
	increment = 5,
	tooltip = "Maximum burst attacks",
	risky = false,
	callback = function(v) 
		_G.CONFIG.BURST_MAX = v
	end
})

sections.Burst:AddSlider({
	text = "Burst Speed", 
	flag = 'BurstSpeed', 
	suffix = "s", 
	value = 0.15,
	min = 0.05, 
	max = 0.5,
	increment = 0.05,
	tooltip = "Attack speed during burst",
	risky = false,
	callback = function(v) 
		_G.CONFIG.BURST_ATTACK_SPEED = v
	end
})

sections.Burst:AddSlider({
	text = "Rest Duration", 
	flag = 'RestDuration', 
	suffix = "s", 
	value = 5,
	min = 1, 
	max = 15,
	increment = 1,
	tooltip = "Rest time after burst",
	risky = false,
	callback = function(v) 
		_G.CONFIG.REST_DURATION = v
	end
})

sections.Movement:AddList({
	enabled = true,
	text = "Movement Method",
	flag = "MovementMethod",
	multi = false,
	tooltip = "How to move to mobs",
    risky = false,
	value = "TP",
	values = {"TP", "Tween"},
	callback = function(v)
	    _G.CONFIG.TELEPORT_METHOD = v
	end
})

sections.Movement:AddSlider({
	text = "Tween Speed", 
	flag = 'TweenSpeed', 
	suffix = "", 
	value = 80,
	min = 50, 
	max = 300,
	increment = 10,
	tooltip = "Speed when using Tween",
	risky = false,
	callback = function(v) 
		_G.CONFIG.TWEEN_SPEED = v
	end
})

sections.Position:AddSlider({
	text = "Orbit Radius", 
	flag = 'OrbitRadius', 
	suffix = " studs", 
	value = 15,
	min = 5, 
	max = 30,
	increment = 1,
	tooltip = "Distance from mob",
	risky = false,
	callback = function(v) 
		_G.CONFIG.ORBIT_RADIUS = v
	end
})

sections.Position:AddSlider({
	text = "Orbit Height", 
	flag = 'OrbitHeight', 
	suffix = " studs", 
	value = 5,
	min = 0, 
	max = 20,
	increment = 1,
	tooltip = "Height above mob",
	risky = false,
	callback = function(v) 
		_G.CONFIG.ORBIT_HEIGHT = v
	end
})

sections.Position:AddSlider({
	text = "Orbit Speed", 
	flag = 'OrbitSpeed', 
	suffix = "", 
	value = 2,
	min = 1, 
	max = 10,
	increment = 0.5,
	tooltip = "Speed of orbiting",
	risky = false,
	callback = function(v) 
		_G.CONFIG.ORBIT_SPEED = v
	end
})

sections.Position:AddSlider({
	text = "Attack Range", 
	flag = 'AttackRange', 
	suffix = " studs", 
	value = 15,
	min = 5, 
	max = 50,
	increment = 1,
	tooltip = "Range to start attacking",
	risky = false,
	callback = function(v) 
		_G.CONFIG.ATTACK_RANGE = v
	end
})

sections.Stats:AddText({
    enabled = true,
    text = "Stats will appear here...",
    flag = "StatsText",
    risky = false,
})

task.spawn(function()
    while true do
        task.wait(1)
        if _G.CONFIG.AUTO_FARM or _G.CONFIG.AUTO_FARM_ALL or _G.CONFIG.KILL_AURA then
            local time = tick() - State.startTime
            local status = State.inBurst and "🔥 BURSTING" or (State.isResting and "😴 Resting" or (State.currentMob and "⚔️ Fighting" or "🔍 Searching"))
            local statsText = string.format(
                "⏱️ Time: %dm %ds\n💀 Kills: %d\n⚔️ Attacks: %d\n✨ Skills: %d\n📊 %s", 
                math.floor(time/60), 
                math.floor(time%60), 
                State.totalKills, 
                State.totalAttacks, 
                State.totalSkills, 
                status
            )
        end
    end
end)

library:SendNotification("Auto Farm Loaded!", 5, Color3.fromRGB(0, 255, 0))
