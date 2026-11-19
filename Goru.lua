-- ==========================================
-- GORU.LUA - CORE LOGIC (SNIFFER + FARM)
-- ==========================================
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")
local VirtualUser = game:GetService("VirtualUser")
local Workspace = game:GetService("Workspace")
local LocalPlayer = Players.LocalPlayer
local PlayerGui = LocalPlayer:WaitForChild("PlayerGui")

getgenv().KerenBaristaState = getgenv().KerenBaristaState or {
    CurrentStage = "NO_GUI",
    CurrentText = "",
    SnifferLog = true,
    AntiAfk = false,
    AutoFarm = false,
    InstantPrompt = false,
    LastHandledStage = nil,
}

local State = getgenv().KerenBaristaState
local Goru = {}
local farmThread = nil
local lastLoggedText = nil
local connectedLabel = nil

local COORDS = {
    ShiftSpot     = CFrame.new(-4992.262, 4.287, -716.253),
    CoffeeMachine = CFrame.new(-4997.648, 4.287, -794.613),
    Customer      = CFrame.new(-4996.451, 4.287, -760.959),
}

-- ==========================================
-- SNIFFER ORDER TEXT
-- ==========================================
local function getOrderLabel()
    local baristaGui = PlayerGui:FindFirstChild("BaristaGUI")
    if not baristaGui then return nil end

    local statusFrame = baristaGui:FindFirstChild("StatusFrame")
    if not statusFrame then return nil end

    return statusFrame:FindFirstChild("OrderText")
end

local function detectStage(text)
    if not text or text == "" then
        return "IDLE"
    end

    local lower = string.lower(text)
    if string.find(lower, "npc", 1, true) then
        return "NPC"
    elseif string.find(lower, "brew", 1, true) then
        return "BREWING"
    elseif string.find(lower, "order", 1, true) then
        return "ORDER"
    elseif string.find(lower, "good", 1, true) then
        return "GOOD"
    else
        return "UNKNOWN"
    end
end

local function syncOrderState(label)
    if not label then
        State.CurrentStage = "NO_GUI"
        State.CurrentText = ""
        return
    end

    local rawText = label.Text or ""
    local stage = detectStage(rawText)

    State.CurrentText = rawText
    State.CurrentStage = stage

    if State.SnifferLog and rawText ~= lastLoggedText then
        lastLoggedText = rawText
        print("==========================================")
        print("[Goru.lua Sniffer] Stage : " .. stage)
        print("[Goru.lua Sniffer] Text  : " .. rawText)
        print("==========================================")
    end
end

function Goru.StartSniffer()
    if Goru._snifferRunning then return end
    Goru._snifferRunning = true

    task.spawn(function()
        while true do
            pcall(function()
                local label = getOrderLabel()
                if label then
                    if connectedLabel ~= label then
                        connectedLabel = label
                        label:GetPropertyChangedSignal("Text"):Connect(function()
                            syncOrderState(label)
                        end)
                    end
                    syncOrderState(label)
                else
                    connectedLabel = nil
                    syncOrderState(nil)
                end
            end)
            task.wait(0.25)
        end
    end)
end

-- ==========================================
-- UTILITY: ANTI-AFK & INSTANT PROMPT
-- ==========================================
function Goru.SetAntiAfk(enabled)
    State.AntiAfk = enabled and true or false
end

function Goru.SetInstantPrompt(enabled)
    State.InstantPrompt = enabled and true or false
end

LocalPlayer.Idled:Connect(function()
    if State.AntiAfk then
        VirtualUser:Button2Down(Vector2.new(0, 0), Workspace.CurrentCamera.CFrame)
        task.wait(1)
        VirtualUser:Button2Up(Vector2.new(0, 0), Workspace.CurrentCamera.CFrame)
    end
end)

task.spawn(function()
    while true do
        if State.InstantPrompt then
            pcall(function()
                local hrp = LocalPlayer.Character and LocalPlayer.Character:FindFirstChild("HumanoidRootPart")
                if hrp then
                    for _, v in pairs(Workspace:GetDescendants()) do
                        if v:IsA("ProximityPrompt") then
                            local part = v.Parent
                            local pos = part and (part:IsA("Model") and part.PrimaryPart and part.PrimaryPart.Position or (part:IsA("BasePart") and part.Position))
                            if pos and (pos - hrp.Position).Magnitude <= 30 then
                                v.HoldDuration = 0
                            end
                        end
                    end
                end
            end)
        end
        task.wait(1)
    end
end)

-- ==========================================
-- GERAK & INTERAKSI PROMPT
-- ==========================================
local function selectBaristaJob()
    pcall(function()
        local jobEvents = ReplicatedStorage:FindFirstChild("JobEvents")
        local teamEvent = jobEvents and jobEvents:FindFirstChild("TeamChangeRequest")
        if teamEvent then
            teamEvent:FireServer("Barista", 11378976, 1, 0, "Detector")
        end
    end)
end

local function smoothMoveTo(targetCFrame)
    pcall(function()
        local char = LocalPlayer.Character
        local hrp = char and char:FindFirstChild("HumanoidRootPart")
        if not hrp then return end

        local distance = (hrp.Position - targetCFrame.Position).Magnitude
        if distance <= 2 then return end

        local speed = 16
        local duration = math.clamp(distance / speed, 0.2, 10)
        local tweenInfo = TweenInfo.new(duration, Enum.EasingStyle.Linear, Enum.EasingDirection.Out)
        local tween = TweenService:Create(hrp, tweenInfo, { CFrame = targetCFrame })

        tween:Play()
        tween.Completed:Wait()
    end)
end

local function fireNearestPrompt()
    pcall(function()
        local hrp = LocalPlayer.Character and LocalPlayer.Character:FindFirstChild("HumanoidRootPart")
        if not hrp then return end

        local nearestPrompt = nil
        local shortestDist = 14

        for _, v in pairs(Workspace:GetDescendants()) do
            if v:IsA("ProximityPrompt") and v.Enabled and v.Parent then
                local partPos = v.Parent:IsA("Model") and v.Parent.PrimaryPart and v.Parent.PrimaryPart.Position or (v.Parent:IsA("BasePart") and v.Parent.Position)
                if partPos then
                    local dist = (partPos - hrp.Position).Magnitude
                    if dist <= shortestDist then
                        shortestDist = dist
                        nearestPrompt = v
                    end
                end
            end
        end

        if nearestPrompt then
            if fireproximityprompt then
                fireproximityprompt(nearestPrompt)
            else
                nearestPrompt:InputHoldBegin()
                task.wait(nearestPrompt.HoldDuration + 0.05)
                nearestPrompt:InputHoldEnd()
            end
        end
    end)
end

local function stepByStage(stage)
    if stage == "NO_GUI" then
        if State.LastHandledStage ~= "NO_GUI" then
            State.LastHandledStage = "NO_GUI"
            smoothMoveTo(COORDS.ShiftSpot)
            task.wait(0.4)
            fireNearestPrompt()
            task.wait(1.0)
        end

    elseif stage == "NPC" then
        if State.LastHandledStage ~= "NPC" then
            State.LastHandledStage = "NPC"
            smoothMoveTo(COORDS.CoffeeMachine)
            task.wait(0.4)
            fireNearestPrompt()
            task.wait(0.8)
        end

    elseif stage == "BREWING" then
        if State.LastHandledStage ~= "BREWING" then
            State.LastHandledStage = "BREWING"
            -- Slot auto-solve MinigameFrame
        end

    elseif stage == "ORDER" then
        if State.LastHandledStage ~= "ORDER" then
            State.LastHandledStage = "ORDER"
            smoothMoveTo(COORDS.Customer)
            task.wait(0.4)
            fireNearestPrompt()
            task.wait(0.8)
        end

    elseif stage == "GOOD" then
        if State.LastHandledStage ~= "GOOD" then
            State.LastHandledStage = "GOOD"
            task.wait(0.5)
            smoothMoveTo(COORDS.ShiftSpot)
        end
    end
end

function Goru.StartFarm()
    Goru.StartSniffer()
    if farmThread then task.cancel(farmThread) end
    State.AutoFarm = true
    State.LastHandledStage = nil

    farmThread = task.spawn(function()
        selectBaristaJob()
        task.wait(1.2)

        while State.AutoFarm do
            pcall(function()
                stepByStage(State.CurrentStage)
            end)
            task.wait(0.3)
        end
    end)
end

function Goru.StopFarm()
    State.AutoFarm = false
    State.LastHandledStage = nil
    if farmThread then
        task.cancel(farmThread)
        farmThread = nil
    end
end

-- Auto-sync kalau state AutoFarm sudah sempat aktif sebelum Goru selesai dimuat
if State.AutoFarm then
    task.spawn(Goru.StartFarm)
end

Goru.StartSniffer()
getgenv().GoruCore = Goru
print("[Goru.lua] Core logic siap!")
return Goru
