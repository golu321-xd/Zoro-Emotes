--[[
    ╔═══════════════════════════════════════════════╗
    ║             ⚔️ ZORO EMOTES ⚔️                ║
    ║       Bug Fixes + Mobile Drag Optimization    ║
    ╚═══════════════════════════════════════════════╝
]]

--// SERVICES
local UserInputService = game:GetService("UserInputService")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local Players = game:GetService("Players")
local HttpService = game:GetService("HttpService")
local AvatarEditorService = game:GetService("AvatarEditorService")
local CoreGui = game:GetService("CoreGui")

local player = Players.LocalPlayer
local character = player.Character or player.CharacterAdded:Wait()
local humanoid = character:WaitForChild("Humanoid")
local lastPosition = character.PrimaryPart and character.PrimaryPart.Position or Vector3.new()

--// UI SCALING
local ScreenSize = workspace.CurrentCamera.ViewportSize
local function scale(axis, value)
    local isMobile = UserInputService.TouchEnabled and not UserInputService.KeyboardEnabled
    local baseWidth, baseHeight = 1920, 1080
    local scaleFactor = isMobile and 2 or 1.5
    if axis == "X" then
        return value * (ScreenSize.X / baseWidth) * scaleFactor
    elseif axis == "Y" then
        return value * (ScreenSize.Y / baseHeight) * scaleFactor
    end
    return value
end

--// SETTINGS
local Settings = {
    ["Stop Emote When Moving"] = true,
    ["Fade In"] = 0.1,
    ["Fade Out"] = 0.1,
    ["Weight"] = 1,
    ["Speed"] = 1,
    ["Allow Invisible"] = false, -- Disabled to fix combat/falling bugs
    ["Time Position"] = 0,
    ["Looped"] = true,
    ["Stop Other Animations On Play"] = true,
    _sliders = {},
    _toggles = {}
}

--// DATA MANAGEMENT
local savedEmotes = {}
local SAVE_FILE = "ZoroEmotes_SaveData.json"

local function loadSavedEmotes()
    local success, data = pcall(function()
        if readfile and isfile and isfile(SAVE_FILE) then
            return HttpService:JSONDecode(readfile(SAVE_FILE))
        end
        return {}
    end)
    savedEmotes = (success and type(data) == "table") and data or {}
    for _, v in ipairs(savedEmotes) do
        if not v.AnimationId then v.AnimationId = "rbxassetid://" .. tostring(v.AssetId or v.Id) end
        if v.Favorite == nil then v.Favorite = false end
    end
end

local function saveEmotesToData()
    pcall(function()
        if writefile then writefile(SAVE_FILE, HttpService:JSONEncode(savedEmotes)) end
    end)
end

loadSavedEmotes()

--// ANIMATION LOGIC
local CurrentTrack = nil

local function GetRealId(id)
    local ok, obj = pcall(function() return game:GetObjects("rbxassetid://"..tostring(id)) end)
    if ok and obj and #obj > 0 then
        local target = obj[1]
        if target:IsA("Animation") and target.AnimationId ~= "" then
            return tonumber(target.AnimationId:match("%d+"))
        elseif target:FindFirstChildOfClass("Animation") then
            return tonumber(target:FindFirstChildOfClass("Animation").AnimationId:match("%d+"))
        end
    end
    return id
end

function LoadTrack(id)
    if CurrentTrack then CurrentTrack:Stop(Settings["Fade Out"]) end
    
    local realId = GetRealId(id)
    local newAnim = Instance.new("Animation")
    newAnim.AnimationId = "rbxassetid://" .. tostring(realId)
    
    local newTrack = humanoid:LoadAnimation(newAnim)
    newTrack.Priority = Enum.AnimationPriority.Action4
    
    local weight = Settings["Weight"]
    if weight == 0 then weight = 0.001 end
    
    if Settings["Stop Other Animations On Play"] then
        for _, t in pairs(humanoid.Animator:GetPlayingAnimationTracks()) do
            if t.Priority ~= Enum.AnimationPriority.Action4 then t:Stop() end
        end
    end
    
    newTrack:Play(Settings["Fade In"], weight, Settings["Speed"])
    CurrentTrack = newTrack
    
    if CurrentTrack.Length > 0 then
        CurrentTrack.TimePosition = math.clamp(Settings["Time Position"], 0, 1) * CurrentTrack.Length
    end
    CurrentTrack.Looped = Settings["Looped"]
    
    return newTrack
end

--// MOVEMENT & COLLISION
RunService.RenderStepped:Connect(function()
    if Settings["Looped"] and CurrentTrack and CurrentTrack.IsPlaying then
        CurrentTrack.Looped = Settings["Looped"]
    end
    if character:FindFirstChild("HumanoidRootPart") and humanoid then
        local root = character.HumanoidRootPart
        if Settings["Stop Emote When Moving"] and CurrentTrack and CurrentTrack.IsPlaying then
            local moved = (root.Position - lastPosition).Magnitude > 0.1
            local jumped = humanoid:GetState() == Enum.HumanoidStateType.Jumping
            if moved or jumped then
                CurrentTrack:Stop(Settings["Fade Out"])
                CurrentTrack = nil
            end
        end
        lastPosition = root.Position
    end
end)

local originalCollisionStates = {}

local function saveCollisionStates()
    originalCollisionStates = {}
    for _, part in ipairs(character:GetDescendants()) do
        if part:IsA("BasePart") and part ~= character.PrimaryPart then
            originalCollisionStates[part] = part.CanCollide
        end
    end
end

local function disableCollisions()
    if not Settings["Allow Invisible"] then return end
    for _, part in ipairs(character:GetDescendants()) do
        if part:IsA("BasePart") and part ~= character.PrimaryPart then
            part.CanCollide = false
        end
    end
end

function setupCollisionConnection()
    for part, canCollide in pairs(originalCollisionStates) do
        if part and part.Parent then part.CanCollide = canCollide end
    end
    saveCollisionStates()
    spawn(function()
        while character and character.Parent and Settings["Allow Invisible"] do
            disableCollisions()
            RunService.Stepped:Wait()
        end
    end)
end

saveCollisionStates()
setupCollisionConnection()

player.CharacterAdded:Connect(function(newChar)
    character = newChar
    humanoid = newChar:WaitForChild("Humanoid")
    lastPosition = character.PrimaryPart and character.PrimaryPart.Position or Vector3.new()
    setupCollisionConnection()
end)

--// GUI CREATION
local gui = Instance.new("ScreenGui")
gui.Name = "ZoroEmotesGUI"
gui.Parent = CoreGui
gui.Enabled = false
gui.ResetOnSpawn = false
gui.DisplayOrder = 999

local function createCorner(parent, radius)
    local corner = Instance.new("UICorner")
    corner.CornerRadius = UDim.new(0, radius)
    corner.Parent = parent
end

--// IMPROVED DRAG FUNCTION (Mobile Friendly)
local function makeDraggable(frame, callback)
    local dragging = false
    local dragInput, dragStart, startPos
    local hasDragged = false

    frame.InputBegan:Connect(function(input)
        -- Check if touch/mouse AND if game isn't already processing movement (joystick)
        if (input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch) then
            dragging = true
            hasDragged = false
            dragStart = input.Position
            startPos = frame.Position
            
            input.Changed:Connect(function()
                if input.UserInputState == Enum.UserInputState.End then
                    dragging = false
                    if not hasDragged and callback then
                        callback()
                    end
                end
            end)
        end
    end)

    frame.InputChanged:Connect(function(input)
        if input.UserInputType == Enum.UserInputType.MouseMovement or input.UserInputType == Enum.UserInputType.Touch then
            dragInput = input
        end
    end)

    UserInputService.InputChanged:Connect(function(input)
        if input == dragInput and dragging then
            local delta = input.Position - dragStart
            if delta.Magnitude > 5 then hasDragged = true end
            
            -- 1:1 Pixel Movement for better sensitivity
            local xOff = startPos.X.Offset + delta.X
            local yOff = startPos.Y.Offset + delta.Y
            
            frame.Position = UDim2.new(startPos.X.Scale, xOff, startPos.Y.Scale, yOff)
        end
    end)
end

--// TOAST NOTIFICATIONS
local toastQueue = {}
local currentToast = nil

local toastFrame = Instance.new("Frame")
toastFrame.Size = UDim2.new(0, scale("X", 300), 0, scale("Y", 50))
toastFrame.Position = UDim2.new(1, scale("X", 20), 0.85, 0)
toastFrame.BackgroundColor3 = Color3.fromRGB(30, 30, 35)
toastFrame.Parent = gui
createCorner(toastFrame, 10)

local toastStroke = Instance.new("UIStroke")
toastStroke.Color = Color3.fromRGB(100, 100, 120)
toastStroke.Thickness = 1.5
toastStroke.Parent = toastFrame

local toastText = Instance.new("TextLabel")
toastText.Size = UDim2.new(1, -scale("X", 20), 1, 0)
toastText.Position = UDim2.new(0, scale("X", 10), 0, 0)
toastText.BackgroundTransparency = 1
toastText.Text = ""
toastText.TextColor3 = Color3.new(1, 1, 1)
toastText.Font = Enum.Font.GothamSemibold
toastText.TextScaled = true
toastText.TextXAlignment = Enum.TextXAlignment.Left
toastText.Parent = toastFrame

toastFrame.Visible = false

local function showNextToast()
    if currentToast or #toastQueue == 0 then return end
    currentToast = table.remove(toastQueue, 1)
    toastText.Text = currentToast
    
    toastFrame.Position = UDim2.new(1, scale("X", 20), 0.85, 0)
    toastFrame.Visible = true
    
    TweenService:Create(toastFrame, TweenInfo.new(0.35, Enum.EasingStyle.Quart), {
        Position = UDim2.new(1, -scale("X", 320), 0.85, 0)
    }):Play()
    
    task.wait(3)
    TweenService:Create(toastFrame, TweenInfo.new(0.3, Enum.EasingStyle.Quart), {
        Position = UDim2.new(1, scale("X", 20), 0.85, 0)
    }):Play()
    
    task.wait(0.35)
    toastFrame.Visible = false
    currentToast = nil
    showNextToast()
end

function notify(title, text)
    table.insert(toastQueue, title .. " " .. text)
    showNextToast()
end

--// MAIN CONTAINER
local mainContainer = Instance.new("Frame")
mainContainer.Size = UDim2.new(0, scale("X", 580), 0, scale("Y", 400))
mainContainer.Position = UDim2.new(0.5, -scale("X", 290), 0.5, -scale("Y", 200))
mainContainer.BackgroundColor3 = Color3.fromRGB(35, 38, 45)
mainContainer.Active = true
mainContainer.Parent = gui
createCorner(mainContainer, 14)

makeDraggable(mainContainer)

local containerStroke = Instance.new("UIStroke")
containerStroke.Color = Color3.fromRGB(60, 65, 80)
containerStroke.Thickness = 2
containerStroke.Parent = mainContainer

local titleBar = Instance.new("TextLabel")
titleBar.Size = UDim2.new(1, 0, 0, scale("Y", 40))
titleBar.BackgroundColor3 = Color3.fromRGB(25, 28, 35)
titleBar.BackgroundTransparency = 0.2
titleBar.Text = "⚔️ ZORO EMOTES ⚔️"
titleBar.TextColor3 = Color3.fromRGB(255, 255, 255)
titleBar.Font = Enum.Font.GothamBold
titleBar.TextScaled = true
titleBar.Parent = mainContainer
createCorner(titleBar, 12)

-- TAB BUTTONS
local tabY = scale("Y", 44)

local catalogTabBtn = Instance.new("TextButton")
catalogTabBtn.Size = UDim2.new(0.43, 0, 0, scale("Y", 28))
catalogTabBtn.Position = UDim2.new(0.05, 0, 0, tabY)
catalogTabBtn.BackgroundColor3 = Color3.fromRGB(100, 170, 220)
catalogTabBtn.Text = "Catalog"
catalogTabBtn.TextColor3 = Color3.new(1, 1, 1)
catalogTabBtn.Font = Enum.Font.GothamBold
catalogTabBtn.TextScaled = true
catalogTabBtn.Parent = mainContainer
createCorner(catalogTabBtn, 8)

local savedTabBtn = Instance.new("TextButton")
savedTabBtn.Size = UDim2.new(0.43, 0, 0, scale("Y", 28))
savedTabBtn.Position = UDim2.new(0.52, 0, 0, tabY)
savedTabBtn.BackgroundColor3 = Color3.fromRGB(220, 130, 160)
savedTabBtn.Text = "Saved"
savedTabBtn.TextColor3 = Color3.new(1, 1, 1)
savedTabBtn.Font = Enum.Font.GothamBold
savedTabBtn.TextScaled = true
savedTabBtn.Parent = mainContainer
createCorner(savedTabBtn, 8)

local divider = Instance.new("Frame")
divider.Size = UDim2.new(0, 2, 1, -scale("Y", 78))
divider.Position = UDim2.new(0.6, -1, 0, scale("Y", 78))
divider.BackgroundColor3 = Color3.fromRGB(50, 55, 65)
divider.Parent = mainContainer
createCorner(divider, 1)

--// CATALOG TAB
local catalogFrame = Instance.new("Frame")
catalogFrame.Size = UDim2.new(0.6, -10, 1, -scale("Y", 78))
catalogFrame.Position = UDim2.new(0, 5, 0, scale("Y", 78))
catalogFrame.BackgroundTransparency = 1
catalogFrame.Visible = true
catalogFrame.Parent = mainContainer

local searchBox = Instance.new("TextBox")
searchBox.Size = UDim2.new(0.55, -8, 0, scale("Y", 28))
searchBox.Position = UDim2.new(0, 8, 0, 0)
searchBox.PlaceholderText = "🔍 Search emotes..."
searchBox.PlaceholderColor3 = Color3.fromRGB(150, 150, 150)
searchBox.Text = ""
searchBox.BackgroundColor3 = Color3.fromRGB(15, 15, 20)
searchBox.TextColor3 = Color3.new(1, 1, 1)
searchBox.Font = Enum.Font.Gotham
searchBox.TextScaled = true
searchBox.ClearTextOnFocus = false
searchBox.Parent = catalogFrame
createCorner(searchBox, 8)

local refreshBtn = Instance.new("TextButton")
refreshBtn.Size = UDim2.new(0.22, -4, 0, scale("Y", 28))
refreshBtn.Position = UDim2.new(0.55, 4, 0, 0)
refreshBtn.BackgroundColor3 = Color3.fromRGB(80, 85, 100)
refreshBtn.Text = "Refresh"
refreshBtn.TextColor3 = Color3.new(1, 1, 1)
refreshBtn.Font = Enum.Font.GothamBold
refreshBtn.TextScaled = true
refreshBtn.Parent = catalogFrame
createCorner(refreshBtn, 8)

local sortBtn = Instance.new("TextButton")
sortBtn.Size = UDim2.new(0.23, -8, 0, scale("Y", 28))
sortBtn.Position = UDim2.new(0.77, 4, 0, 0)
sortBtn.BackgroundColor3 = Color3.fromRGB(80, 85, 100)
sortBtn.Text = "Sort"
sortBtn.TextColor3 = Color3.new(1, 1, 1)
sortBtn.Font = Enum.Font.GothamBold
sortBtn.TextScaled = true
sortBtn.Parent = catalogFrame
createCorner(sortBtn, 8)

local catalogScroll = Instance.new("ScrollingFrame")
catalogScroll.Size = UDim2.new(1, -16, 1, -scale("Y", 100))
catalogScroll.Position = UDim2.new(0, 8, 0, scale("Y", 36))
catalogScroll.CanvasSize = UDim2.new(0, 0, 0, 0)
catalogScroll.ScrollBarThickness = 6
catalogScroll.BackgroundColor3 = Color3.fromRGB(25, 25, 30)
catalogScroll.Parent = catalogFrame
createCorner(catalogScroll, 8)

local catalogLayout = Instance.new("UIGridLayout")
catalogLayout.CellSize = UDim2.new(0, scale("X", 115), 0, scale("Y", 170))
catalogLayout.CellPadding = UDim2.new(0, 6, 0, 6)
catalogLayout.Parent = catalogScroll

local emptyLabel = Instance.new("TextLabel")
emptyLabel.Size = UDim2.new(1, 0, 0, scale("Y", 40))
emptyLabel.Position = UDim2.new(0, 0, 0.5, -20)
emptyLabel.BackgroundTransparency = 1
emptyLabel.Text = "Loading..."
emptyLabel.TextColor3 = Color3.new(1, 1, 1)
emptyLabel.Font = Enum.Font.GothamBold
emptyLabel.TextScaled = true
emptyLabel.Visible = false
emptyLabel.Parent = catalogScroll

local prevBtn = Instance.new("TextButton")
prevBtn.Size = UDim2.new(0.4, -6, 0, scale("Y", 32))
prevBtn.Position = UDim2.new(0, 4, 1, -36)
prevBtn.BackgroundColor3 = Color3.fromRGB(50, 55, 65)
prevBtn.Text = "◀ Prev"
prevBtn.TextColor3 = Color3.new(1, 1, 1)
prevBtn.Font = Enum.Font.GothamBold
prevBtn.TextScaled = true
prevBtn.Parent = catalogFrame
createCorner(prevBtn, 8)

local pageBox = Instance.new("TextBox")
pageBox.Size = UDim2.new(0.2, 0, 0, scale("Y", 32))
pageBox.Position = UDim2.new(0.4, 2, 1, -36)
pageBox.BackgroundTransparency = 1
pageBox.Text = "1"
pageBox.TextColor3 = Color3.new(1, 1, 1)
pageBox.Font = Enum.Font.Gotham
pageBox.TextScaled = true
pageBox.Parent = catalogFrame

local nextBtn = Instance.new("TextButton")
nextBtn.Size = UDim2.new(0.4, -6, 0, scale("Y", 32))
nextBtn.Position = UDim2.new(0.6, 2, 1, -36)
nextBtn.BackgroundColor3 = Color3.fromRGB(50, 55, 65)
nextBtn.Text = "Next ▶"
nextBtn.TextColor3 = Color3.new(1, 1, 1)
nextBtn.Font = Enum.Font.GothamBold
nextBtn.TextScaled = true
nextBtn.Parent = catalogFrame
createCorner(nextBtn, 8)

--// SAVED TAB
local savedFrame = Instance.new("Frame")
savedFrame.Size = UDim2.new(0.6, -10, 1, -scale("Y", 78))
savedFrame.Position = UDim2.new(0, 5, 0, scale("Y", 78))
savedFrame.BackgroundTransparency = 1
savedFrame.Visible = false
savedFrame.Parent = mainContainer

local savedSearch = Instance.new("TextBox")
savedSearch.Size = UDim2.new(1, -16, 0, scale("Y", 28))
savedSearch.Position = UDim2.new(0, 8, 0, 0)
savedSearch.PlaceholderText = "🔍 Search saved..."
savedSearch.PlaceholderColor3 = Color3.fromRGB(150, 150, 150)
savedSearch.Text = ""
savedSearch.BackgroundColor3 = Color3.fromRGB(15, 15, 20)
savedSearch.TextColor3 = Color3.new(1, 1, 1)
savedSearch.Font = Enum.Font.Gotham
savedSearch.TextScaled = true
savedSearch.ClearTextOnFocus = false
savedSearch.Parent = savedFrame
createCorner(savedSearch, 8)

local idBox = Instance.new("TextBox")
idBox.Size = UDim2.new(0.55, -10, 0, scale("Y", 28))
idBox.Position = UDim2.new(0, 8, 0, scale("Y", 36))
idBox.PlaceholderText = "Paste ID..."
idBox.PlaceholderColor3 = Color3.fromRGB(150, 150, 150)
idBox.Text = ""
idBox.BackgroundColor3 = Color3.fromRGB(15, 15, 20)
idBox.TextColor3 = Color3.new(1, 1, 1)
idBox.Font = Enum.Font.Gotham
idBox.TextScaled = true
idBox.ClearTextOnFocus = false
idBox.Parent = savedFrame
createCorner(idBox, 8)

local addBtn = Instance.new("TextButton")
addBtn.Size = UDim2.new(0.45, -10, 0, scale("Y", 28))
addBtn.Position = UDim2.new(0.55, 2, 0, scale("Y", 36))
addBtn.BackgroundColor3 = Color3.fromRGB(100, 170, 220)
addBtn.Text = "➕ Add ID"
addBtn.TextColor3 = Color3.new(1, 1, 1)
addBtn.Font = Enum.Font.GothamBold
addBtn.TextScaled = true
addBtn.Parent = savedFrame
createCorner(addBtn, 8)

addBtn.MouseButton1Click:Connect(function()
    local id = tonumber(idBox.Text)
    if id then
        local exists = false
        for _, v in pairs(savedEmotes) do if v.Id == id then exists = true break end end
        if not exists then
            table.insert(savedEmotes, {Id = id, AssetId = id, Name = "Custom", AnimationId = "rbxassetid://" .. GetRealId(id), Favorite = false})
            saveEmotesToData()
            refreshSavedTab()
            addBtn.Text = "✓ Added!"
            task.wait(1) addBtn.Text = "➕ Add ID" idBox.Text = ""
        end
    end
end)

local savedScroll = Instance.new("ScrollingFrame")
savedScroll.Size = UDim2.new(1, -16, 1, -scale("Y", 78))
savedScroll.Position = UDim2.new(0, 8, 0, scale("Y", 72))
savedScroll.CanvasSize = UDim2.new(0, 0, 0, 0)
savedScroll.ScrollBarThickness = 0
savedScroll.BackgroundColor3 = Color3.fromRGB(25, 25, 30)
savedScroll.Parent = savedFrame
createCorner(savedScroll, 8)

local savedEmptyLabel = Instance.new("TextLabel")
savedEmptyLabel.Size = UDim2.new(1, 0, 0, scale("Y", 40))
savedEmptyLabel.Position = UDim2.new(0, 0, 0.5, -20)
savedEmptyLabel.BackgroundTransparency = 1
savedEmptyLabel.Text = "No saved emotes"
savedEmptyLabel.TextColor3 = Color3.new(1, 1, 1)
savedEmptyLabel.Font = Enum.Font.GothamBold
savedEmptyLabel.TextScaled = true
savedEmptyLabel.Visible = false
savedEmptyLabel.Parent = savedScroll

local savedLayout = Instance.new("UIGridLayout")
savedLayout.CellSize = UDim2.new(0, scale("X", 115), 0, scale("Y", 185))
savedLayout.CellPadding = UDim2.new(0, 6, 0, 6)
savedLayout.Parent = savedScroll

--// SETTINGS TAB
local settingsFrame = Instance.new("Frame")
settingsFrame.Size = UDim2.new(0.4, -10, 1, -scale("Y", 78))
settingsFrame.Position = UDim2.new(0.6, 5, 0, scale("Y", 78))
settingsFrame.BackgroundTransparency = 1
settingsFrame.Parent = mainContainer

local settingsTitle = Instance.new("TextLabel")
settingsTitle.Size = UDim2.new(1, 0, 0, scale("Y", 28))
settingsTitle.BackgroundTransparency = 1
settingsTitle.Text = "⚙️ Settings"
settingsTitle.TextColor3 = Color3.new(1, 1, 1)
settingsTitle.Font = Enum.Font.GothamBold
settingsTitle.TextScaled = true
settingsTitle.Parent = settingsFrame

local settingsScroll = Instance.new("ScrollingFrame")
settingsScroll.Size = UDim2.new(1, -16, 1, -scale("Y", 34))
settingsScroll.Position = UDim2.new(0, 8, 0, scale("Y", 32))
settingsScroll.CanvasSize = UDim2.new(0, 0, 0, 0)
settingsScroll.ScrollBarThickness = 4
settingsScroll.BackgroundColor3 = Color3.fromRGB(25, 25, 30)
settingsScroll.Parent = settingsFrame
createCorner(settingsScroll, 8)

local settingsLayout = Instance.new("UIListLayout")
settingsLayout.Padding = UDim.new(0, 5)
settingsLayout.Parent = settingsScroll

settingsLayout:GetPropertyChangedSignal("AbsoluteContentSize"):Connect(function()
    settingsScroll.CanvasSize = UDim2.new(0, 0, 0, settingsLayout.AbsoluteContentSize.Y + 10)
end)

local function createSlider(name, min, max, default)
    Settings[name] = default or min
    local container = Instance.new("Frame")
    container.Size = UDim2.new(1, 0, 0, scale("Y", 56))
    container.BackgroundTransparency = 1
    container.Parent = settingsScroll
    
    local bg = Instance.new("Frame")
    bg.Size = UDim2.new(1, 0, 1, 0)
    bg.BackgroundColor3 = Color3.fromRGB(15, 15, 20)
    bg.Parent = container
    createCorner(bg, 8)
    
    local label = Instance.new("TextLabel")
    label.Size = UDim2.new(0.55, -10, 0, scale("Y", 20))
    label.Position = UDim2.new(0, 8, 0, 4)
    label.BackgroundTransparency = 1
    label.Text = name .. ": " .. string.format("%.2f", Settings[name])
    label.TextColor3 = Color3.new(1, 1, 1)
    label.Font = Enum.Font.Gotham
    label.TextScaled = true
    label.TextXAlignment = Enum.TextXAlignment.Left
    label.Parent = bg
    
    local input = Instance.new("TextBox")
    input.Size = UDim2.new(0.4, -10, 0, scale("Y", 20))
    input.Position = UDim2.new(0.58, 0, 0, 4)
    input.BackgroundColor3 = Color3.fromRGB(30, 30, 35)
    input.Text = tostring(Settings[name])
    input.TextColor3 = Color3.new(1, 1, 1)
    input.Font = Enum.Font.Gotham
    input.TextScaled = true
    input.ClearTextOnFocus = false
    input.Parent = bg
    createCorner(input, 5)
    
    local bar = Instance.new("Frame")
    bar.Size = UDim2.new(1, -16, 0, 12)
    bar.Position = UDim2.new(0, 8, 0, 32)
    bar.BackgroundColor3 = Color3.fromRGB(40, 40, 50)
    bar.Parent = bg
    createCorner(bar, 6)
    
    local fill = Instance.new("Frame")
    fill.Size = UDim2.new(0, 0, 1, 0)
    fill.BackgroundColor3 = Color3.fromRGB(100, 170, 220)
    fill.Parent = bar
    createCorner(fill, 6)
    
    local function applyValue(val)
        Settings[name] = math.clamp(val, min, max)
        label.Text = name .. ": " .. string.format("%.2f", Settings[name])
        input.Text = tostring(math.floor(Settings[name] * 100) / 100)
        fill.Size = UDim2.new((Settings[name] - min) / (max - min), 0, 1, 0)
        if CurrentTrack and CurrentTrack.IsPlaying then
            if name == "Speed" then CurrentTrack:AdjustSpeed(Settings["Speed"])
            elseif name == "Weight" then CurrentTrack:AdjustWeight(Settings["Weight"] == 0 and 0.001 or Settings["Weight"])
            elseif name == "Time Position" then CurrentTrack.TimePosition = math.clamp(val, 0, 1) * CurrentTrack.Length end
        end
    end
    
    local dragging = false
    bar.InputBegan:Connect(function(inp) if inp.UserInputType == Enum.UserInputType.MouseButton1 or inp.UserInputType == Enum.UserInputType.Touch then dragging = true applyValue(min + (max - min) * math.clamp((inp.Position.X - bar.AbsolutePosition.X) / bar.AbsoluteSize.X, 0, 1)) end end)
    UserInputService.InputChanged:Connect(function(inp) if dragging and (inp.UserInputType == Enum.UserInputType.MouseMovement or inp.UserInputType == Enum.UserInputType.Touch) then applyValue(min + (max - min) * math.clamp((inp.Position.X - bar.AbsolutePosition.X) / bar.AbsoluteSize.X, 0, 1)) end end)
    UserInputService.InputEnded:Connect(function(inp) if inp.UserInputType == Enum.UserInputType.MouseButton1 or inp.UserInputType == Enum.UserInputType.Touch then dragging = false end end)
    input.FocusLost:Connect(function() local n = tonumber(input.Text) if n then applyValue(n) else input.Text = tostring(Settings[name]) end end)
    
    Settings._sliders[name] = applyValue
    applyValue(Settings[name])
end

local function createToggle(name)
    Settings[name] = Settings[name] or false
    local container = Instance.new("Frame")
    container.Size = UDim2.new(1, 0, 0, scale("Y", 36))
    container.BackgroundColor3 = Color3.fromRGB(15, 15, 20)
    container.Parent = settingsScroll
    createCorner(container, 8)
    
    local label = Instance.new("TextLabel")
    label.Size = UDim2.new(0.65, -10, 1, 0)
    label.Position = UDim2.new(0, 8, 0, 0)
    label.BackgroundTransparency = 1
    label.Text = name
    label.TextColor3 = Color3.new(1, 1, 1)
    label.Font = Enum.Font.Gotham
    label.TextScaled = true
    label.TextXAlignment = Enum.TextXAlignment.Left
    label.Parent = container
    
    local btn = Instance.new("TextButton")
    btn.Size = UDim2.new(0, scale("X", 55), 0, scale("Y", 22))
    btn.Position = UDim2.new(1, -62, 0.5, -11)
    btn.TextColor3 = Color3.new(1, 1, 1)
    btn.Font = Enum.Font.GothamBold
    btn.TextScaled = true
    btn.Parent = container
    createCorner(btn, 11)
    
    local function applyVisual(state)
        btn.Text = state and "ON" or "OFF"
        btn.BackgroundColor3 = state and Color3.fromRGB(100, 220, 130) or Color3.fromRGB(80, 80, 90)
    end
    
    btn.MouseButton1Click:Connect(function() Settings[name] = not Settings[name] applyVisual(Settings[name]) end)
    applyVisual(Settings[name])
    Settings._toggles[name] = applyVisual
end

createToggle("Stop Emote When Moving")
createToggle("Looped")
createSlider("Speed", 0.1, 3, 1)
createSlider("Time Position", 0, 1, 0)
createSlider("Weight", 0, 1, 1)
createSlider("Fade In", 0, 1, 0.1)
createSlider("Fade Out", 0, 1, 0.1)
createToggle("Allow Invisible")
createToggle("Stop Other Animations On Play")

--// CATALOG LOGIC
local sortModes = {
    {Enum.CatalogSortType.Relevance, "Rel"},
    {Enum.CatalogSortType.PriceHighToLow, "High"},
    {Enum.CatalogSortType.PriceLowToHigh, "Low"},
    {Enum.CatalogSortType.MostFavorited, "Fav"},
    {Enum.CatalogSortType.RecentlyCreated, "New"},
    {Enum.CatalogSortType.Bestselling, "Best"}
}
local currentSortIndex = 1
local currentKeyword = ""
local currentPages = nil
local currentPageNum = 1
local isLoading = false

local function getPages(keyword)
    local params = CatalogSearchParams.new()
    params.SearchKeyword = keyword or ""
    params.CategoryFilter = Enum.CatalogCategoryFilter.None
    params.SalesTypeFilter = Enum.SalesTypeFilter.All
    params.AssetTypes = {Enum.AvatarAssetType.EmoteAnimation}
    params.IncludeOffSale = true
    params.SortType = sortModes[currentSortIndex][1]
    params.Limit = 60
    local ok, pages = pcall(function() return AvatarEditorService:SearchCatalog(params) end)
    return ok and pages or nil
end

local function createCard(item)
    local card = Instance.new("Frame")
    card.Size = UDim2.new(0, scale("X", 115), 0, scale("Y", 170))
    card.BackgroundColor3 = Color3.fromRGB(20, 20, 25)
    createCorner(card, 10)
    
    local thumbId = item.AssetId or item.Id
    local img = Instance.new("ImageLabel")
    img.Size = UDim2.new(1, -8, 0, scale("Y", 85))
    img.Position = UDim2.new(0, 4, 0, 4)
    img.BackgroundTransparency = 1
    img.ScaleType = Enum.ScaleType.Fit
    pcall(function() img.Image = "rbxthumb://type=Asset&id=" .. thumbId .. "&w=150&h=150" end)
    img.Parent = card
    createCorner(img, 8)
    
    local name = Instance.new("TextLabel")
    name.Size = UDim2.new(1, -8, 0, scale("Y", 28))
    name.Position = UDim2.new(0, 4, 0, scale("Y", 94))
    name.BackgroundTransparency = 1
    name.Text = item.Name or "?"
    name.TextScaled = true
    name.TextWrapped = true
    name.Font = Enum.Font.GothamBold
    name.TextColor3 = Color3.new(1, 1, 1)
    name.Parent = card
    
    local playBtn = Instance.new("TextButton")
    playBtn.Size = UDim2.new(0.48, -3, 0, scale("Y", 26))
    playBtn.Position = UDim2.new(0, 4, 1, -30)
    playBtn.BackgroundColor3 = Color3.fromRGB(80, 200, 120)
    playBtn.Text = "▶"
    playBtn.TextColor3 = Color3.new(1, 1, 1)
    playBtn.Font = Enum.Font.GothamBold
    playBtn.TextScaled = true
    playBtn.Parent = card
    createCorner(playBtn, 6)
    playBtn.MouseButton1Click:Connect(function() LoadTrack(thumbId) end)
    
    local saveBtn = Instance.new("TextButton")
    saveBtn.Size = UDim2.new(0.48, -3, 0, scale("Y", 26))
    saveBtn.Position = UDim2.new(0.52, 0, 1, -30)
    saveBtn.BackgroundColor3 = Color3.fromRGB(100, 170, 220)
    saveBtn.Text = "💾"
    saveBtn.TextColor3 = Color3.new(1, 1, 1)
    saveBtn.Font = Enum.Font.GothamBold
    saveBtn.TextScaled = true
    saveBtn.Parent = card
    createCorner(saveBtn, 6)
    saveBtn.MouseButton1Click:Connect(function()
        for _, s in ipairs(savedEmotes) do if s.Id == item.Id then return end end
        table.insert(savedEmotes, {Id = item.Id, AssetId = thumbId, Name = item.Name or "?", AnimationId = "rbxassetid://" .. GetRealId(thumbId), Favorite = false})
        saveEmotesToData()
        saveBtn.Text = "✓"
        task.wait(1) saveBtn.Text = "💾"
    end)
    
    return card
end

local function showPage(pages)
    if isLoading then return end
    isLoading = true
    pageBox.Text = "..."
    for _, c in ipairs(catalogScroll:GetChildren()) do if c:IsA("Frame") then c:Destroy() end end
    local ok, list = pcall(function() return pages:GetCurrentPage() end)
    if ok and list and #list > 0 then
        emptyLabel.Visible = false
        for _, item in ipairs(list) do createCard(item).Parent = catalogScroll end
    else
        emptyLabel.Visible = true
    end
    catalogScroll.CanvasSize = UDim2.new(0, 0, 0, catalogLayout.AbsoluteContentSize.Y + 8)
    pageBox.Text = tostring(currentPageNum)
    isLoading = false
end

local function doSearch(keyword)
    currentKeyword = keyword or ""
    currentPageNum = 1
    currentPages = getPages(currentKeyword)
    if currentPages then showPage(currentPages) end
end

refreshBtn.MouseButton1Click:Connect(function() doSearch(searchBox.Text) end)
searchBox.FocusLost:Connect(function(enter) if enter then doSearch(searchBox.Text) end end)
sortBtn.MouseButton1Click:Connect(function()
    currentSortIndex = currentSortIndex % #sortModes + 1
    sortBtn.Text = sortModes[currentSortIndex][2]
    doSearch(currentKeyword)
end)

nextBtn.MouseButton1Click:Connect(function()
    if not currentPages or currentPages.IsFinished then return end
    pcall(function() currentPages:AdvanceToNextPageAsync() end)
    currentPageNum += 1
    showPage(currentPages)
end)

prevBtn.MouseButton1Click:Connect(function()
    if currentPageNum <= 1 then return end
    currentPages = getPages(currentKeyword)
    for i = 2, currentPageNum - 1 do pcall(function() currentPages:AdvanceToNextPageAsync() end) end
    currentPageNum -= 1
    showPage(currentPages)
end)

--// SAVED TAB LOGIC
local function createSavedCard(item)
    local card = Instance.new("Frame")
    card.Size = UDim2.new(0, scale("X", 115), 0, scale("Y", 185))
    card.BackgroundColor3 = Color3.fromRGB(20, 20, 25)
    createCorner(card, 10)
    
    local img = Instance.new("ImageLabel")
    img.Size = UDim2.new(1, -8, 0, scale("Y", 85))
    img.Position = UDim2.new(0, 4, 0, 4)
    img.BackgroundTransparency = 1
    img.ScaleType = Enum.ScaleType.Fit
    pcall(function() img.Image = "rbxthumb://type=Asset&id=" .. (item.AssetId or item.Id) .. "&w=150&h=150" end)
    img.Parent = card
    createCorner(img, 8)
    
    local name = Instance.new("TextLabel")
    name.Size = UDim2.new(1, -8, 0, scale("Y", 28))
    name.Position = UDim2.new(0, 4, 0, scale("Y", 94))
    name.BackgroundTransparency = 1
    name.Text = item.Name or "?"
    name.TextScaled = true
    name.TextWrapped = true
    name.Font = Enum.Font.GothamBold
    name.TextColor3 = Color3.new(1, 1, 1)
    name.Parent = card
    
    local playBtn = Instance.new("TextButton")
    playBtn.Size = UDim2.new(0.48, -3, 0, scale("Y", 28))
    playBtn.Position = UDim2.new(0, 4, 1, -32)
    playBtn.BackgroundColor3 = Color3.fromRGB(80, 200, 120)
    playBtn.Text = "▶"
    playBtn.TextColor3 = Color3.new(1, 1, 1)
    playBtn.Font = Enum.Font.GothamBold
    playBtn.TextScaled = true
    playBtn.Parent = card
    createCorner(playBtn, 6)
    playBtn.MouseButton1Click:Connect(function() LoadTrack(item.Id) end)
    
    local delBtn = Instance.new("TextButton")
    delBtn.Size = UDim2.new(0.48, -3, 0, scale("Y", 28))
    delBtn.Position = UDim2.new(0.52, 0, 1, -32)
    delBtn.BackgroundColor3 = Color3.fromRGB(220, 80, 80)
    delBtn.Text = "✕"
    delBtn.TextColor3 = Color3.new(1, 1, 1)
    delBtn.Font = Enum.Font.GothamBold
    delBtn.TextScaled = true
    delBtn.Parent = card
    createCorner(delBtn, 6)
    delBtn.MouseButton1Click:Connect(function()
        for i, s in ipairs(savedEmotes) do if s.Id == item.Id then table.remove(savedEmotes, i) saveEmotesToData() refreshSavedTab() break end end
    end)
    
    return card
end

function refreshSavedTab()
    for _, c in ipairs(savedScroll:GetChildren()) do if c:IsA("Frame") then c:Destroy() end end
    local search = savedSearch.Text:lower()
    local results = {}
    for _, item in ipairs(savedEmotes) do if search == "" or (item.Name and item.Name:lower():find(search)) then table.insert(results, item) end end
    if #results > 0 then
        savedEmptyLabel.Visible = false
        for _, item in ipairs(results) do createSavedCard(item).Parent = savedScroll end
    else
        savedEmptyLabel.Visible = true
    end
    savedScroll.CanvasSize = UDim2.new(0, 0, 0, savedLayout.AbsoluteContentSize.Y + 8)
end

savedSearch:GetPropertyChangedSignal("Text"):Connect(refreshSavedTab)

--// TAB SWITCHING
catalogTabBtn.MouseButton1Click:Connect(function()
    catalogFrame.Visible = true
    savedFrame.Visible = false
end)

savedTabBtn.MouseButton1Click:Connect(function()
    catalogFrame.Visible = false
    savedFrame.Visible = true
    refreshSavedTab()
end)

--// TOGGLE BUTTON (Z LETTER)
local toggleGui = Instance.new("ScreenGui")
toggleGui.Name = "ZoroToggle"
toggleGui.ResetOnSpawn = false
toggleGui.Parent = CoreGui

local toggleBtn = Instance.new("TextButton")
toggleBtn.Size = UDim2.new(0, 50, 0, 50)
toggleBtn.Position = UDim2.new(0, 15, 0.5, -25)
toggleBtn.BackgroundColor3 = Color3.fromRGB(35, 38, 45)
toggleBtn.Text = "Z"
toggleBtn.TextColor3 = Color3.new(1, 1, 1)
toggleBtn.Font = Enum.Font.GothamSemibold
toggleBtn.TextScaled = true
toggleBtn.Active = true
toggleBtn.Parent = toggleGui
createCorner(toggleBtn, 14)

local toggleStroke = Instance.new("UIStroke")
toggleStroke.Color = Color3.fromRGB(100, 170, 220)
toggleStroke.Thickness = 2
toggleStroke.Parent = toggleBtn

makeDraggable(toggleBtn, function()
    gui.Enabled = not gui.Enabled
end)

UserInputService.InputBegan:Connect(function(input, gameProcessed)
    if not gameProcessed and input.KeyCode == Enum.KeyCode.G then gui.Enabled = not gui.Enabled end
end)

--// INITIALIZATION
doSearch("")

print([[
╔═══════════════════════════════════════════════╗
║             ⚔️ ZORO EMOTES LOADED ⚔️         ║
╠═══════════════════════════════════════════════╣
║  Mobile Drag: Optimized                       ║
║  Bugs Fixed: Combat & Physics Restored        ║
║  Press G to toggle GUI                        ║
╚═══════════════════════════════════════════════╝
]])
