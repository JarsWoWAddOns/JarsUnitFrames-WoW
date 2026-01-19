-- Jar's Unit Frames for WoW 12.0.1
-- Demonstrates proper handling of secret values for unit frame data

-- Saved variables with defaults
JarUnitFramesDB = JarUnitFramesDB or {}

-- Default values (will be applied in PLAYER_LOGIN after SavedVariables load)
local defaults = {
    showPlayerFrame = true,
    showTargetFrame = true,
    showPetFrame = true,
    frameScale = 1.0,
    showPercentages = true,
    unlocked = false,
    texture = "Interface\\TargetingFrame\\UI-StatusBar",
    font = "Fonts\\FRIZQT__.TTF",
    fontSize = 12,
    showLevel = false,
    bgAlpha = 0.8,
    mirrorTargetPosition = false,
    playerPos = { point = "TOPLEFT", x = 20, y = -20 },
    targetPos = { point = "TOPLEFT", x = 260, y = -20 },
    hidePlayerPermanentBuffs = false,  -- Hide player buffs without timers
    hideTargetPermanentBuffs = false,  -- Hide target buffs without timers
}

-- Frame references
local playerFrame, targetFrame, petFrame, configFrame

-- Lookup table for player's units (used to avoid secret value comparison errors)
local myUnits = { player = true, pet = true, vehicle = true }

-- Available textures
local TEXTURES = {
    ["Blizzard"] = "Interface\\TargetingFrame\\UI-StatusBar",
    ["Smooth"] = "Interface\\Buttons\\WHITE8X8",
    ["Gradient"] = "Interface\\RaidFrame\\Raid-Bar-Hp-Fill",
    ["Minimalist"] = "Interface\\PaperDollInfoFrame\\UI-Character-Skills-Bar",
}

-- Available fonts (will be populated from LSM if available)
local FONTS = {
    ["Friz Quadrata (Default)"] = "Fonts\\FRIZQT__.TTF",
    ["Arial"] = "Fonts\\ARIALN.TTF",
    ["Skurri"] = "Fonts\\SKURRI.TTF",
    ["Morpheus"] = "Fonts\\MORPHEUS.TTF",
}

-- Function to load fonts from LibSharedMedia-3.0
local function LoadSharedMediaFonts()
    local LSM = LibStub and LibStub("LibSharedMedia-3.0", true)
    if LSM then
        -- Get all registered fonts from SharedMedia
        local fontList = LSM:List("font")
        if fontList and #fontList > 0 then
            -- Clear and repopulate FONTS table
            FONTS = {}
            for _, fontName in ipairs(fontList) do
                local fontPath = LSM:Fetch("font", fontName)
                if fontPath then
                    FONTS[fontName] = fontPath
                end
            end
            print("|".."|cff00ff00JARUNITFRAMES:|r Loaded " .. #fontList .. " fonts from LibSharedMedia-3.0")
            
            -- Ensure built-in fonts are always available as fallback
            if not FONTS["Friz Quadrata (Default)"] then
                FONTS["Friz Quadrata (Default)"] = "Fonts\\FRIZQT__.TTF"
            end
            if not FONTS["Arial"] then
                FONTS["Arial"] = "Fonts\\ARIALN.TTF"
            end
            if not FONTS["Skurri"] then
                FONTS["Skurri"] = "Fonts\\SKURRI.TTF"
            end
            if not FONTS["Morpheus"] then
                FONTS["Morpheus"] = "Fonts\\MORPHEUS.TTF"
            end
            return true
        end
    end
    return false
end

-- Helper function to make frames draggable
local function MakeFrameDraggable(frame, savedPosTable)
    frame:SetMovable(true)
    frame:EnableMouse(true)
    frame:RegisterForDrag("LeftButton")
    
    frame:SetScript("OnDragStart", function(self)
        if JarUnitFramesDB.unlocked then
            self:StartMoving()
        end
    end)
    
    frame:SetScript("OnDragStop", function(self)
        self:StopMovingOrSizing()
        -- Save position
        local point, _, _, x, y = self:GetPoint()
        savedPosTable.point = point
        savedPosTable.x = x
        savedPosTable.y = y
    end)
end

-- Helper function to restore frame position
local function RestoreFramePosition(frame, savedPosTable)
    if not savedPosTable then return end
    frame:ClearAllPoints()
    frame:SetPoint(savedPosTable.point, UIParent, savedPosTable.point, savedPosTable.x, savedPosTable.y)
end

-- Helper function to update bar textures
local function UpdateFrameTextures(frame)
    local texture = JarUnitFramesDB.texture or "Interface\\TargetingFrame\\UI-StatusBar"
    frame.healthBar:SetStatusBarTexture(texture)
    frame.healthBar.bg:SetTexture(texture)
    frame.powerBar:SetStatusBarTexture(texture)
    frame.powerBar.bg:SetTexture(texture)
end

local function UpdateFrameFonts(frame)
    local font = JarUnitFramesDB.font or "Fonts\\FRIZQT__.TTF"
    local fontSize = JarUnitFramesDB.fontSize or 12
    
    -- Apply fonts directly
    if frame.healthText then
        frame.healthText:SetFont(font, fontSize, "OUTLINE")
    end
    if frame.name then
        frame.name:SetFont(font, fontSize, "OUTLINE")
    end
    if frame.levelText then
        frame.levelText:SetFont(font, fontSize, "OUTLINE")
    end
end

-- Update frequency throttle (seconds)
local UPDATE_INTERVAL = 0.1
local timeSinceLastUpdate = 0

-- Forward declarations for update functions
local UpdatePlayerFrame, UpdatePlayerBuffs, UpdatePlayerDebuffs, UpdateTargetFrame, UpdateTargetBuffs, UpdateTargetDebuffs

-- Create a custom player frame
local function CreatePlayerFrame()
    -- Get font settings early so they can be used throughout frame creation
    local font = JarUnitFramesDB.font or "Fonts\\FRIZQT__.TTF"
    local fontSize = JarUnitFramesDB.fontSize or 12
    
    local frame = CreateFrame("Button", "JUF_PlayerFrame", UIParent, "SecureUnitButtonTemplate")
    frame:SetSize(220, 45)
    frame:SetAttribute("unit", "player")
    frame:SetAttribute("type1", "target")
    frame:SetAttribute("type2", "togglemenu")
    frame:RegisterForClicks("AnyUp")
    
    -- Register basic events
    frame:RegisterEvent("UNIT_HEALTH")
    frame:RegisterEvent("UNIT_MAXHEALTH")
    frame:RegisterEvent("UNIT_POWER_UPDATE")
    frame:RegisterEvent("UNIT_MAXPOWER")
    frame:RegisterEvent("UNIT_AURA")  -- Must manually register for player!
    frame:RegisterEvent("PLAYER_ENTERING_WORLD")
    
    -- Set up event handler
    frame:SetScript("OnEvent", function(self, event, eventUnit)
        if event == "UNIT_AURA" and eventUnit == "player" then
            UpdatePlayerBuffs()
            UpdatePlayerDebuffs()
        elseif event:match("^UNIT_") then
            if not eventUnit or eventUnit == "player" then
                UpdatePlayerFrame()
            end
        elseif event == "PLAYER_ENTERING_WORLD" then
            UpdatePlayerFrame()
            UpdatePlayerBuffs()
            UpdatePlayerDebuffs()
        end
    end)
    
    -- RegisterUnitWatch handles UNIT_AURA and other events automatically
    if not InCombatLockdown() then
        RegisterUnitWatch(frame)
    end
    
    -- Restore position or use default
    if JarUnitFramesDB.playerPos then
        RestoreFramePosition(frame, JarUnitFramesDB.playerPos)
    else
        frame:SetPoint("TOPLEFT", 20, -20)
    end
    
    frame:SetScale(JarUnitFramesDB.frameScale)
    
    -- Make draggable (modified for SecureUnitButtonTemplate)
    frame:SetMovable(true)
    frame:RegisterForDrag("LeftButton")
    frame:SetScript("OnDragStart", function(self)
        if JarUnitFramesDB.unlocked then
            self:StartMoving()
        end
    end)
    frame:SetScript("OnDragStop", function(self)
        if JarUnitFramesDB.unlocked then
            self:StopMovingOrSizing()
            local point, _, _, x, y = self:GetPoint()
            JarUnitFramesDB.playerPos.point = point
            JarUnitFramesDB.playerPos.x = x
            JarUnitFramesDB.playerPos.y = y
            
            -- Mirror target frame position if enabled
            if JarUnitFramesDB.mirrorTargetPosition and targetFrame then
                local mirroredX = -x
                local mirroredY = y
                -- Use the same anchor point, just flip the X coordinate
                local mirroredPoint = point
                
                JarUnitFramesDB.targetPos.point = mirroredPoint
                JarUnitFramesDB.targetPos.x = mirroredX
                JarUnitFramesDB.targetPos.y = mirroredY
                
                targetFrame:ClearAllPoints()
                targetFrame:SetPoint(mirroredPoint, UIParent, mirroredPoint, mirroredX, mirroredY)
            end
        end
    end)
    
    -- Drop shadow
    frame.shadow = frame:CreateTexture(nil, "BACKGROUND")
    frame.shadow:SetPoint("TOPLEFT", -3, 3)
    frame.shadow:SetPoint("BOTTOMRIGHT", 3, -3)
    frame.shadow:SetColorTexture(0, 0, 0, JarUnitFramesDB.bgAlpha)
    
    -- Health bar
    frame.healthBar = CreateFrame("StatusBar", nil, frame)
    frame.healthBar:SetSize(220, 20)
    frame.healthBar:SetPoint("TOP", 0, 0)
    frame.healthBar:EnableMouse(false)  -- Allow clicks to pass through
    local texture = JarUnitFramesDB.texture or "Interface\\TargetingFrame\\UI-StatusBar"
    frame.healthBar:SetStatusBarTexture(texture)
    
    -- Get class color for player
    local _, class = UnitClass("player")
    local classColor = RAID_CLASS_COLORS[class]
    if classColor then
        frame.healthBar:SetStatusBarColor(classColor.r, classColor.g, classColor.b)
    else
        frame.healthBar:SetStatusBarColor(0, 0.9, 0.8)  -- Fallback
    end
    
    frame.healthBar:SetMinMaxValues(0, 100)
    frame.healthBar:SetValue(100)
    
    -- Health bar border
    frame.healthBar.border = CreateFrame("Frame", nil, frame.healthBar, "BackdropTemplate")
    frame.healthBar.border:SetAllPoints()
    frame.healthBar.border:SetBackdrop({
        edgeFile = "Interface\\Buttons\\WHITE8X8",
        edgeSize = 1,
    })
    frame.healthBar.border:SetBackdropBorderColor(0, 0, 0, 1)
    
    -- Health bar background
    frame.healthBar.bg = frame.healthBar:CreateTexture(nil, "BACKGROUND")
    frame.healthBar.bg:SetAllPoints(frame.healthBar)
    frame.healthBar.bg:SetTexture(texture)
    if classColor then
        frame.healthBar.bg:SetVertexColor(classColor.r * 0.3, classColor.g * 0.3, classColor.b * 0.3)
    else
        frame.healthBar.bg:SetVertexColor(0, 0.3, 0.3)
    end
    
    -- Health text (right side)
    frame.healthText = frame.healthBar:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    frame.healthText:SetPoint("RIGHT", frame.healthBar, "RIGHT", -5, 0)
    frame.healthText:SetText("100")
    frame.healthText:SetJustifyH("RIGHT")
    frame.healthText:SetFont(font, fontSize, "OUTLINE")
    
    -- Power bar
    frame.powerBar = CreateFrame("StatusBar", nil, frame)
    frame.powerBar:SetSize(220, 8)
    frame.powerBar:SetPoint("TOP", 0, -22)
    frame.powerBar:EnableMouse(false)  -- Allow clicks to pass through
    frame.powerBar:SetStatusBarTexture(texture)
    frame.powerBar:SetStatusBarColor(0, 0.4, 1)  -- Blue
    frame.powerBar:SetMinMaxValues(0, 100)
    frame.powerBar:SetValue(100)
    
    -- Power bar border
    frame.powerBar.border = CreateFrame("Frame", nil, frame.powerBar, "BackdropTemplate")
    frame.powerBar.border:SetAllPoints()
    frame.powerBar.border:SetBackdrop({
        edgeFile = "Interface\\Buttons\\WHITE8X8",
        edgeSize = 1,
    })
    frame.powerBar.border:SetBackdropBorderColor(0, 0, 0, 1)
    
    -- Power bar background
    frame.powerBar.bg = frame.powerBar:CreateTexture(nil, "BACKGROUND")
    frame.powerBar.bg:SetAllPoints(frame.powerBar)
    frame.powerBar.bg:SetTexture(texture)
    frame.powerBar.bg:SetVertexColor(0, 0, 0.4)
    frame.powerBar.bg:SetAlpha(JarUnitFramesDB.bgAlpha)
    
    -- Status icons (combat, resting, role)
    frame.statusIcons = CreateFrame("Frame", nil, frame)
    frame.statusIcons:SetSize(40, 16)
    frame.statusIcons:SetPoint("LEFT", frame.healthBar, "LEFT", 2, 0)
    
    -- Combat icon
    frame.combatIcon = frame.statusIcons:CreateTexture(nil, "OVERLAY")
    frame.combatIcon:SetSize(16, 16)
    frame.combatIcon:SetPoint("LEFT", 0, 0)
    frame.combatIcon:SetTexture("Interface\\CharacterFrame\\UI-StateIcon")
    frame.combatIcon:SetTexCoord(0.5, 1.0, 0.0, 0.49)
    frame.combatIcon:Hide()
    
    -- Resting icon
    frame.restingIcon = frame.statusIcons:CreateTexture(nil, "OVERLAY")
    frame.restingIcon:SetSize(16, 16)
    frame.restingIcon:SetPoint("LEFT", 18, 0)
    frame.restingIcon:SetTexture("Interface\\CharacterFrame\\UI-StateIcon")
    frame.restingIcon:SetTexCoord(0.0, 0.5, 0.0, 0.49)
    frame.restingIcon:Hide()
    
    -- Level text (optional)
    frame.levelText = frame.healthBar:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    frame.levelText:SetPoint("LEFT", frame.healthBar, "LEFT", 5, 0)
    frame.levelText:SetFont(font, fontSize, "OUTLINE")
    if JarUnitFramesDB.showLevel then
        frame.levelText:SetText(UnitLevel("player"))
    else
        frame.levelText:SetText("")
    end
    
    -- Name text (below the frame)
    frame.name = frame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    frame.name:SetPoint("TOPLEFT", frame.powerBar, "BOTTOMLEFT", 0, -5)
    frame.name:SetText("Player")
    frame.name:SetJustifyH("LEFT")
    frame.name:SetFont(font, fontSize, "OUTLINE")
    
    -- Buff container (above the frame)
    frame.buffs = {}
    for i = 1, 40 do  -- Max 40 buff icons
        local buff = CreateFrame("Frame", nil, frame)
        buff:SetSize(20, 20)  -- Small icons
        
        -- Calculate position: 10 per row, growing upward
        local row = math.floor((i - 1) / 10)
        local col = (i - 1) % 10
        buff:SetPoint("BOTTOMLEFT", frame.healthBar, "TOPLEFT", col * 22, 2 + (row * 22))
        
        buff.icon = buff:CreateTexture(nil, "ARTWORK")
        buff.icon:SetAllPoints()
        buff.icon:SetTexCoord(0.07, 0.93, 0.07, 0.93)  -- Crop edges
        
        buff.border = buff:CreateTexture(nil, "OVERLAY")
        buff.border:SetAllPoints()
        buff.border:SetTexture("Interface\\Buttons\\UI-Debuff-Overlays")
        buff.border:SetTexCoord(0.296875, 0.5703125, 0, 0.515625)
        
        buff.count = buff:CreateFontString(nil, "OVERLAY", "NumberFontNormal")
        buff.count:SetPoint("BOTTOMRIGHT", 2, 0)
        
        -- Enable mouse interaction for tooltips
        buff:EnableMouse(true)
        buff:SetScript("OnEnter", function(self)
            if self.auraInstanceID then
                pcall(function()
                    GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
                    GameTooltip:SetUnitBuffByAuraInstanceID("player", self.auraInstanceID)
                    GameTooltip:Show()
                end)
            end
        end)
        buff:SetScript("OnLeave", function(self)
            GameTooltip:Hide()
        end)
        
        buff:Hide()
        frame.buffs[i] = buff
    end
    
    -- Debuff container (below the frame)
    frame.debuffs = {}
    for i = 1, 40 do  -- Max 40 debuff icons
        local debuff = CreateFrame("Frame", nil, frame)
        debuff:SetSize(20, 20)  -- Same icon size
        
        -- Calculate position: 10 per row, growing downward
        local row = math.floor((i - 1) / 10)
        local col = (i - 1) % 10
        debuff:SetPoint("TOPLEFT", frame.healthBar, "BOTTOMLEFT", col * 22, -35 - (row * 22))
        
        debuff.icon = debuff:CreateTexture(nil, "ARTWORK")
        debuff.icon:SetAllPoints()
        debuff.icon:SetTexCoord(0.07, 0.93, 0.07, 0.93)  -- Crop edges
        
        debuff.border = debuff:CreateTexture(nil, "OVERLAY")
        debuff.border:SetAllPoints()
        debuff.border:SetTexture("Interface\\Buttons\\UI-Debuff-Overlays")
        debuff.border:SetTexCoord(0.296875, 0.5703125, 0, 0.515625)
        
        debuff.count = debuff:CreateFontString(nil, "OVERLAY", "NumberFontNormal")
        debuff.count:SetPoint("BOTTOMRIGHT", 2, 0)
        
        -- Enable mouse interaction for tooltips
        debuff:EnableMouse(true)
        debuff:SetScript("OnEnter", function(self)
            if self.auraInstanceID then
                pcall(function()
                    GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
                    GameTooltip:SetUnitDebuffByAuraInstanceID("player", self.auraInstanceID)
                    GameTooltip:Show()
                end)
            end
        end)
        debuff:SetScript("OnLeave", function(self)
            GameTooltip:Hide()
        end)
        
        debuff:Hide()
        frame.debuffs[i] = debuff
    end
    
    -- Register unit watch for automatic show/hide
    if not InCombatLockdown() then
        RegisterUnitWatch(frame)
    end
    
    -- Register unit watch for automatic UNIT_AURA events
    if not InCombatLockdown() then
        RegisterUnitWatch(frame)
    end
    
    frame:Show()
    
    return frame
end

-- Create a custom target frame
local function CreateTargetFrame()
    -- Get font settings early so they can be used throughout frame creation
    local font = JarUnitFramesDB.font or "Fonts\\FRIZQT__.TTF"
    local fontSize = JarUnitFramesDB.fontSize or 12
    
    local frame = CreateFrame("Button", "JUF_TargetFrame", UIParent, "SecureUnitButtonTemplate")
    frame:SetSize(220, 45)
    frame:SetAttribute("unit", "target")
    frame:SetAttribute("type1", "target")
    frame:SetAttribute("type2", "togglemenu")
    frame:RegisterForClicks("AnyUp")
    
    -- Register events
    frame:RegisterEvent("UNIT_HEALTH")
    frame:RegisterEvent("UNIT_MAXHEALTH")
    frame:RegisterEvent("UNIT_POWER_UPDATE")
    frame:RegisterEvent("UNIT_MAXPOWER")
    frame:RegisterEvent("UNIT_AURA")
    frame:RegisterEvent("PLAYER_TARGET_CHANGED")
    frame:RegisterEvent("PLAYER_ENTERING_WORLD")
    
    -- Set up event handler
    frame:SetScript("OnEvent", function(self, event, eventUnit)
        if event == "UNIT_AURA" and eventUnit == "target" then
            UpdateTargetBuffs()
            UpdateTargetDebuffs()
        elseif event:match("^UNIT_") then
            if not eventUnit or eventUnit == "target" then
                UpdateTargetFrame()
            end
        elseif event == "PLAYER_TARGET_CHANGED" or event == "PLAYER_ENTERING_WORLD" then
            UpdateTargetFrame()
            UpdateTargetBuffs()
            UpdateTargetDebuffs()
        end
    end)
    
    -- RegisterUnitWatch for automatic show/hide
    if not InCombatLockdown() then
        RegisterUnitWatch(frame)
    end
    
    -- Restore position or use default
    if JarUnitFramesDB.targetPos then
        RestoreFramePosition(frame, JarUnitFramesDB.targetPos)
    else
        frame:SetPoint("TOPLEFT", 260, -20)
    end
    
    frame:SetScale(JarUnitFramesDB.frameScale)
    
    -- Make draggable (modified for SecureUnitButtonTemplate)
    frame:SetMovable(true)
    frame:RegisterForDrag("LeftButton")
    frame:SetScript("OnDragStart", function(self)
        if JarUnitFramesDB.unlocked then
            self:StartMoving()
        end
    end)
    frame:SetScript("OnDragStop", function(self)
        if JarUnitFramesDB.unlocked then
            self:StopMovingOrSizing()
            local point, _, _, x, y = self:GetPoint()
            JarUnitFramesDB.targetPos.point = point
            JarUnitFramesDB.targetPos.x = x
            JarUnitFramesDB.targetPos.y = y
        end
    end)
    
    -- Drop shadow
    frame.shadow = frame:CreateTexture(nil, "BACKGROUND")
    frame.shadow:SetPoint("TOPLEFT", -3, 3)
    frame.shadow:SetPoint("BOTTOMRIGHT", 3, -3)
    frame.shadow:SetColorTexture(0, 0, 0, JarUnitFramesDB.bgAlpha)
    
    -- Health bar
    frame.healthBar = CreateFrame("StatusBar", nil, frame)
    frame.healthBar:SetSize(220, 20)
    frame.healthBar:SetPoint("TOP", 0, 0)
    frame.healthBar:EnableMouse(false)  -- Allow clicks to pass through
    local texture = JarUnitFramesDB.texture or "Interface\\TargetingFrame\\UI-StatusBar"
    frame.healthBar:SetStatusBarTexture(texture)
    frame.healthBar:SetStatusBarColor(1, 0, 0)
    frame.healthBar:SetMinMaxValues(0, 100)
    frame.healthBar:SetValue(0)
    frame.healthBar:SetReverseFill(true)  -- Fill from right to left
    
    -- Health bar border
    frame.healthBar.border = CreateFrame("Frame", nil, frame.healthBar, "BackdropTemplate")
    frame.healthBar.border:SetAllPoints()
    frame.healthBar.border:SetBackdrop({
        edgeFile = "Interface\\Buttons\\WHITE8X8",
        edgeSize = 1,
    })
    frame.healthBar.border:SetBackdropBorderColor(0, 0, 0, 1)
    
    -- Health bar background
    frame.healthBar.bg = frame.healthBar:CreateTexture(nil, "BACKGROUND")
    frame.healthBar.bg:SetAllPoints(frame.healthBar)
    frame.healthBar.bg:SetTexture(texture)
    frame.healthBar.bg:SetVertexColor(0.3, 0, 0)
    
    -- Health text (left side)
    frame.healthText = frame.healthBar:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    frame.healthText:SetPoint("LEFT", frame.healthBar, "LEFT", 5, 0)
    frame.healthText:SetText("0")
    frame.healthText:SetJustifyH("LEFT")
    frame.healthText:SetFont(font, fontSize, "OUTLINE")
    
    -- Level text (optional)
    frame.levelText = frame.healthBar:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    frame.levelText:SetPoint("RIGHT", frame.healthBar, "RIGHT", -5, 0)
    frame.levelText:SetFont(font, fontSize, "OUTLINE")
    frame.levelText:SetText("")
    
    -- Power bar
    frame.powerBar = CreateFrame("StatusBar", nil, frame)
    frame.powerBar:SetSize(220, 8)
    frame.powerBar:SetPoint("TOP", 0, -22)
    frame.powerBar:EnableMouse(false)  -- Allow clicks to pass through
    frame.powerBar:SetStatusBarTexture(texture)
    frame.powerBar:SetStatusBarColor(0, 0.4, 1)
    frame.powerBar:SetMinMaxValues(0, 100)
    frame.powerBar:SetValue(0)
    frame.powerBar:SetReverseFill(true)  -- Fill from right to left
    
    -- Power bar border
    frame.powerBar.border = CreateFrame("Frame", nil, frame.powerBar, "BackdropTemplate")
    frame.powerBar.border:SetAllPoints()
    frame.powerBar.border:SetBackdrop({
        edgeFile = "Interface\\Buttons\\WHITE8X8",
        edgeSize = 1,
    })
    frame.powerBar.border:SetBackdropBorderColor(0, 0, 0, 1)
    
    -- Power bar background
    frame.powerBar.bg = frame.powerBar:CreateTexture(nil, "BACKGROUND")
    frame.powerBar.bg:SetAllPoints(frame.powerBar)
    frame.powerBar.bg:SetTexture(texture)
    frame.powerBar.bg:SetVertexColor(0, 0, 0.4)
    frame.powerBar.bg:SetAlpha(JarUnitFramesDB.bgAlpha)
    
    -- Name text (below the frame, right side)
    frame.name = frame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    frame.name:SetPoint("TOPRIGHT", frame.powerBar, "BOTTOMRIGHT", 0, -5)
    frame.name:SetText("No Target")
    frame.name:SetJustifyH("RIGHT")
    frame.name:SetFont(font, fontSize, "OUTLINE")
    
    -- Buff container (above the frame)
    frame.buffs = {}
    for i = 1, 40 do  -- Max 40 buff icons
        local buff = CreateFrame("Frame", nil, frame)
        buff:SetSize(20, 20)  -- Small icons
        
        -- Calculate position: 10 per row, growing upward and right to left
        local row = math.floor((i - 1) / 10)
        local col = (i - 1) % 10
        buff:SetPoint("BOTTOMRIGHT", frame.healthBar, "TOPRIGHT", -col * 22, 2 + (row * 22))
        
        buff.icon = buff:CreateTexture(nil, "ARTWORK")
        buff.icon:SetAllPoints()
        buff.icon:SetTexCoord(0.07, 0.93, 0.07, 0.93)  -- Crop edges
        
        buff.border = buff:CreateTexture(nil, "OVERLAY")
        buff.border:SetAllPoints()
        buff.border:SetTexture("Interface\\Buttons\\UI-Debuff-Overlays")
        buff.border:SetTexCoord(0.296875, 0.5703125, 0, 0.515625)
        
        buff.count = buff:CreateFontString(nil, "OVERLAY", "NumberFontNormal")
        buff.count:SetPoint("BOTTOMRIGHT", 2, 0)
        
        -- Enable mouse interaction for tooltips
        buff:EnableMouse(true)
        buff:SetScript("OnEnter", function(self)
            if self.auraInstanceID then
                pcall(function()
                    GameTooltip:SetOwner(self, "ANCHOR_LEFT")
                    GameTooltip:SetUnitBuffByAuraInstanceID("target", self.auraInstanceID)
                    GameTooltip:Show()
                end)
            end
        end)
        buff:SetScript("OnLeave", function(self)
            GameTooltip:Hide()
        end)
        
        buff:Hide()
        frame.buffs[i] = buff
    end
    
    -- Debuff container (below the frame, will swap with buffs for enemies)
    frame.debuffs = {}
    for i = 1, 40 do  -- Max 40 debuff icons
        local debuff = CreateFrame("Frame", nil, frame)
        debuff:SetSize(20, 20)  -- Same icon size
        
        -- Calculate position: 10 per row, growing downward and right to left
        local row = math.floor((i - 1) / 10)
        local col = (i - 1) % 10
        debuff:SetPoint("TOPRIGHT", frame.healthBar, "BOTTOMRIGHT", -col * 22, -35 - (row * 22))
        
        debuff.icon = debuff:CreateTexture(nil, "ARTWORK")
        debuff.icon:SetAllPoints()
        debuff.icon:SetTexCoord(0.07, 0.93, 0.07, 0.93)  -- Crop edges
        
        debuff.border = debuff:CreateTexture(nil, "OVERLAY")
        debuff.border:SetAllPoints()
        debuff.border:SetTexture("Interface\\Buttons\\UI-Debuff-Overlays")
        debuff.border:SetTexCoord(0.296875, 0.5703125, 0, 0.515625)
        
        debuff.count = debuff:CreateFontString(nil, "OVERLAY", "NumberFontNormal")
        debuff.count:SetPoint("BOTTOMRIGHT", 2, 0)
        
        -- Enable mouse interaction for tooltips
        debuff:EnableMouse(true)
        debuff:SetScript("OnEnter", function(self)
            if self.auraInstanceID then
                pcall(function()
                    GameTooltip:SetOwner(self, "ANCHOR_LEFT")
                    GameTooltip:SetUnitDebuffByAuraInstanceID("target", self.auraInstanceID)
                    GameTooltip:Show()
                end)
            end
        end)
        debuff:SetScript("OnLeave", function(self)
            GameTooltip:Hide()
        end)
        
        debuff:Hide()
        frame.debuffs[i] = debuff
    end
    
    frame:Show()
    return frame
end

-- Update player buffs
function UpdatePlayerBuffs()
    if not playerFrame or not playerFrame.buffs then return end
    
    -- Use GetUnitAuras for more efficient batch retrieval
    local auras = C_UnitAuras.GetUnitAuras("player", "HELPFUL", 40) or {}
    local buffIndex = 1
    
    for _, auraData in ipairs(auras) do
        if buffIndex > 40 then break end
        
        -- Skip permanent buffs if option is enabled (only check out of combat to avoid secret value errors)
        local skipBuff = false
        if JarUnitFramesDB.hidePlayerPermanentBuffs and not UnitAffectingCombat("player") then
            local hasTimer = auraData.expirationTime and auraData.expirationTime > 0
            skipBuff = not hasTimer
        end
        
        if not skipBuff then
            local buff = playerFrame.buffs[buffIndex]
            buff.icon:SetTexture(auraData.icon)
            buff.auraInstanceID = auraData.auraInstanceID
            
            -- Don't show count (matches Blizzard default behavior)
            buff.count:SetText("")
            
            buff:Show()
            buffIndex = buffIndex + 1
        end
    end
    
    -- Hide unused buff frames
    for i = buffIndex, 40 do
        playerFrame.buffs[i]:Hide()
    end 
end

-- Update target buffs (only for friendly targets)
function UpdateTargetBuffs()
    if not targetFrame or not targetFrame.buffs then return end
    
    -- Hide all buffs if no target
    if not UnitExists("target") then
        for i = 1, 40 do
            targetFrame.buffs[i]:Hide()
        end
        return
    end
    
    -- Use GetUnitAuras for more efficient batch retrieval
    local auras = C_UnitAuras.GetUnitAuras("target", "HELPFUL", 40) or {}
    local buffIndex = 1
    
    for _, auraData in ipairs(auras) do
        if buffIndex > 40 then break end
        
        -- Skip permanent buffs if option is enabled (only check out of combat to avoid secret value errors)
        local skipBuff = false
        if JarUnitFramesDB.hideTargetPermanentBuffs and not UnitAffectingCombat("player") then
            local hasTimer = auraData.expirationTime and auraData.expirationTime > 0
            skipBuff = not hasTimer
        end
        
        if not skipBuff then
            local buff = targetFrame.buffs[buffIndex]
            buff.icon:SetTexture(auraData.icon)
            buff.auraInstanceID = auraData.auraInstanceID
            
            -- Don't show count (matches Blizzard default behavior)
            buff.count:SetText("")
            
            buff:Show()
            buffIndex = buffIndex + 1
        end
    end
    
    -- Hide unused buff frames
    for i = buffIndex, 40 do
        targetFrame.buffs[i]:Hide()
    end
end

-- Update player debuffs
function UpdatePlayerDebuffs()
    if not playerFrame or not playerFrame.debuffs then return end
    
    -- Use GetUnitAuras for harmful effects
    local auras = C_UnitAuras.GetUnitAuras("player", "HARMFUL", 40) or {}
    local debuffIndex = 1
    
    for _, auraData in ipairs(auras) do
        if debuffIndex > 40 then break end
        
        local debuff = playerFrame.debuffs[debuffIndex]
        debuff.icon:SetTexture(auraData.icon)
        debuff.auraInstanceID = auraData.auraInstanceID
        
        -- Don't show count (matches Blizzard default behavior)
        debuff.count:SetText("")
        
        debuff:Show()
        debuffIndex = debuffIndex + 1
    end
    
    -- Hide unused debuff frames
    for i = debuffIndex, 40 do
        playerFrame.debuffs[i]:Hide()
    end
end

-- Update target debuffs (with position swapping for enemies)
function UpdateTargetDebuffs()
    if not targetFrame or not targetFrame.debuffs then return end
    
    -- Hide all debuffs if no target
    if not UnitExists("target") then
        for i = 1, 40 do
            targetFrame.debuffs[i]:Hide()
        end
        return
    end
    
    -- Use GetUnitAuras for harmful effects
    local auras = C_UnitAuras.GetUnitAuras("target", "HARMFUL", 40) or {}
    local debuffIndex = 1
    
    for _, auraData in ipairs(auras) do
        if debuffIndex > 40 then break end
        
        local debuff = targetFrame.debuffs[debuffIndex]
        debuff.icon:SetTexture(auraData.icon)
        debuff.auraInstanceID = auraData.auraInstanceID
        
        -- Don't show count (matches Blizzard default behavior)
        debuff.count:SetText("")
        
        debuff:Show()
        debuffIndex = debuffIndex + 1
    end
    
    -- Hide unused debuff frames
    for i = debuffIndex, 40 do
        targetFrame.debuffs[i]:Hide()
    end
end

-- Update player frame
function UpdatePlayerFrame()
    if not playerFrame then return end
    
    -- Get player name (NOT secret for player unit)
    local name = UnitName("player")
    if name then
        playerFrame.name:SetText(name)
    end
    
    -- Update level if enabled
    if JarUnitFramesDB.showLevel then
        playerFrame.levelText:SetText(UnitLevel("player"))
    else
        playerFrame.levelText:SetText("")
    end
    
    -- Update status icons
    if UnitAffectingCombat("player") then
        playerFrame.combatIcon:Show()
    else
        playerFrame.combatIcon:Hide()
    end
    
    if IsResting() then
        playerFrame.restingIcon:Show()
    else
        playerFrame.restingIcon:Hide()
    end
    
    -- Get health values (these are SECRET values)
    local health = UnitHealth("player")  -- Secret value
    local maxHealth = UnitHealthMax("player")  -- Secret value
    
    -- KEY: Pass secret values DIRECTLY to StatusBar:SetValue()
    -- StatusBar:SetValue() accepts secret values even from tainted code!
    playerFrame.healthBar:SetMinMaxValues(0, maxHealth)
    playerFrame.healthBar:SetValue(health)
    
    -- For text display, we can use concatenation in UNTAINTED code
    -- But tainted code cannot do math/comparison on secrets
    -- Solution: Use StatusBar percentage display or just show bars
    -- Show numeric values with comma separators
    playerFrame.healthText:SetText(BreakUpLargeNumbers(health))
    
    -- Get power values (also secret) and color by type
    local power = UnitPower("player")
    local maxPower = UnitPowerMax("player")
    local powerType = UnitPowerType("player")
    
    -- Pass directly to status bar
    playerFrame.powerBar:SetMinMaxValues(0, maxPower)
    playerFrame.powerBar:SetValue(power)
    
    -- Update power bar color based on power type
    local powerColor = PowerBarColor[powerType]
    if powerColor then
        playerFrame.powerBar:SetStatusBarColor(powerColor.r, powerColor.g, powerColor.b)
        playerFrame.powerBar.bg:SetVertexColor(powerColor.r * 0.3, powerColor.g * 0.3, powerColor.b * 0.3)
    end
end

-- Update target frame
function UpdateTargetFrame()
    if not targetFrame then return end
    
    -- Check if we have a target
    if not UnitExists("target") then
        targetFrame:Hide()
        return
    end
    
    targetFrame:Show()
    
    -- Get target name (SECRET in combat for non-player units!)
    -- FontString:SetText() accepts secret values via Secret Aspects
    local name = UnitName("target")
    targetFrame.name:SetText(name or "Unknown")
    
    -- Update level if enabled
    if JarUnitFramesDB.showLevel and UnitLevel("target") then
        targetFrame.levelText:SetText(UnitLevel("target"))
    else
        targetFrame.levelText:SetText("")
    end
    
    -- Get health values (secret)
    local health = UnitHealth("target")
    local maxHealth = UnitHealthMax("target")
    
    -- Pass directly to status bar
    targetFrame.healthBar:SetMinMaxValues(0, maxHealth)
    targetFrame.healthBar:SetValue(health)
    
    -- Show numeric values with comma separators
    targetFrame.healthText:SetText(BreakUpLargeNumbers(health))
    
    -- Get power values and color by power type
    local power = UnitPower("target")
    local maxPower = UnitPowerMax("target")
    local powerType = UnitPowerType("target")
    
    targetFrame.powerBar:SetMinMaxValues(0, maxPower)
    targetFrame.powerBar:SetValue(power)
    
    -- Color power bar by power type
    local powerColor = PowerBarColor[powerType]
    if powerColor then
        targetFrame.powerBar:SetStatusBarColor(powerColor.r, powerColor.g, powerColor.b)
        targetFrame.powerBar.bg:SetVertexColor(powerColor.r * 0.3, powerColor.g * 0.3, powerColor.b * 0.3)
    end
    
    -- Color by class if player, otherwise by reaction
    if UnitIsPlayer("target") then
        local _, class = UnitClass("target")
        if class and RAID_CLASS_COLORS[class] then
            local classColor = RAID_CLASS_COLORS[class]
            targetFrame.healthBar:SetStatusBarColor(classColor.r, classColor.g, classColor.b)
            targetFrame.healthBar:SetStatusBarDesaturated(false)
            targetFrame.healthBar.bg:SetVertexColor(classColor.r * 0.3, classColor.g * 0.3, classColor.b * 0.3)
        else
            -- Fallback: Red if enemy, green if friendly
            if UnitIsEnemy("player", "target") then
                targetFrame.healthBar:SetStatusBarColor(1, 0, 0)
                targetFrame.healthBar.bg:SetVertexColor(0.3, 0, 0)
            else
                targetFrame.healthBar:SetStatusBarColor(0, 1, 0)
                targetFrame.healthBar.bg:SetVertexColor(0, 0.3, 0)
            end
        end
    else
        -- NPC coloring
        local reaction = UnitReaction("target", "player")
        if reaction and reaction <= 3 then
            targetFrame.healthBar:SetStatusBarColor(1, 0, 0)
        elseif reaction and reaction >= 5 then
            targetFrame.healthBar:SetStatusBarColor(0, 1, 0)
        else
            targetFrame.healthBar:SetStatusBarColor(1, 1, 0)
        end
    end
end

-- Create config window
local function CreateConfigFrame()
    local frame = CreateFrame("Frame", "JUF_ConfigFrame", UIParent, "BasicFrameTemplateWithInset")
    frame:SetSize(550, 550)
    frame:SetPoint("CENTER")
    frame:Hide()
    frame:SetMovable(true)
    frame:EnableMouse(true)
    frame:RegisterForDrag("LeftButton")
    frame:SetScript("OnDragStart", frame.StartMoving)
    frame:SetScript("OnDragStop", frame.StopMovingOrSizing)
    
    frame.title = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    frame.title:SetPoint("TOP", 0, -5)
    frame.title:SetText("Jar's Unit Frames Config")
    
    -- Unlock frames checkbox
    local unlockCheck = CreateFrame("CheckButton", nil, frame, "UICheckButtonTemplate")
    unlockCheck:SetPoint("TOPLEFT", 20, -35)
    unlockCheck.text = unlockCheck:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    unlockCheck.text:SetPoint("LEFT", unlockCheck, "RIGHT", 5, 0)
    unlockCheck.text:SetText("Unlock Frames (drag to reposition)")
    unlockCheck:SetChecked(JarUnitFramesDB.unlocked)
    unlockCheck:SetScript("OnClick", function(self)
        JarUnitFramesDB.unlocked = self:GetChecked()
        if JarUnitFramesDB.unlocked then
            print("|cff00ff00Jar's Unit Frames|r Frames unlocked - drag to reposition")
        else
            print("|cff00ff00Jar's Unit Frames|r Frames locked")
        end
    end)
    frame.unlockCheck = unlockCheck
    
    -- Show level checkbox
    local showLevelCheck = CreateFrame("CheckButton", nil, frame, "UICheckButtonTemplate")
    showLevelCheck:SetPoint("TOPLEFT", 20, -60)
    showLevelCheck.text = showLevelCheck:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    showLevelCheck.text:SetPoint("LEFT", showLevelCheck, "RIGHT", 5, 0)
    showLevelCheck.text:SetText("Show Level")
    showLevelCheck:SetChecked(JarUnitFramesDB.showLevel)
    showLevelCheck:SetScript("OnClick", function(self)
        JarUnitFramesDB.showLevel = self:GetChecked()
        UpdatePlayerFrame()
        UpdateTargetFrame()
    end)
    frame.showLevelCheck = showLevelCheck
    
    -- Scale slider
    local scaleSlider = CreateFrame("Slider", nil, frame, "OptionsSliderTemplate")
    scaleSlider:SetPoint("TOPLEFT", 20, -140)
    scaleSlider:SetMinMaxValues(0.5, 2.0)
    scaleSlider:SetValue(JarUnitFramesDB.frameScale)
    scaleSlider:SetValueStep(0.1)
    scaleSlider:SetObeyStepOnDrag(true)
    scaleSlider:SetWidth(200)
    scaleSlider.Text = scaleSlider:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    scaleSlider.Text:SetPoint("BOTTOM", scaleSlider, "TOP", 0, 5)
    scaleSlider.Text:SetText("Frame Scale: " .. JarUnitFramesDB.frameScale)
    scaleSlider:SetScript("OnValueChanged", function(self, value)
        value = math.floor(value * 10 + 0.5) / 10  -- Round to 1 decimal
        JarUnitFramesDB.frameScale = value
        self.Text:SetText("Frame Scale: " .. value)
        if playerFrame then
            playerFrame:SetScale(value)
        end
        if targetFrame then
            targetFrame:SetScale(value)
        end
    end)
    frame.scaleSlider = scaleSlider
    
    -- Hide Player Permanent Buffs checkbox (top right)
    local hidePlayerPermBuffsCheck = CreateFrame("CheckButton", "JARUNITFRAMESHidePlayerPermBuffsCheck", frame, "UICheckButtonTemplate")
    hidePlayerPermBuffsCheck:SetPoint("TOPRIGHT", -20, -35)
    hidePlayerPermBuffsCheck.text = hidePlayerPermBuffsCheck:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    hidePlayerPermBuffsCheck.text:SetPoint("RIGHT", hidePlayerPermBuffsCheck, "LEFT", -5, 0)
    hidePlayerPermBuffsCheck.text:SetText("Hide Player Permanent Buffs")
    hidePlayerPermBuffsCheck:SetChecked(JarUnitFramesDB.hidePlayerPermanentBuffs)
    hidePlayerPermBuffsCheck:SetScript("OnClick", function(self)
        JarUnitFramesDB.hidePlayerPermanentBuffs = self:GetChecked()
        UpdatePlayerBuffs()
    end)
    
    -- Hide Target Permanent Buffs checkbox (top right)
    local hideTargetPermBuffsCheck = CreateFrame("CheckButton", "JARUNITFRAMESHideTargetPermBuffsCheck", frame, "UICheckButtonTemplate")
    hideTargetPermBuffsCheck:SetPoint("TOPRIGHT", -20, -60)
    hideTargetPermBuffsCheck.text = hideTargetPermBuffsCheck:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    hideTargetPermBuffsCheck.text:SetPoint("RIGHT", hideTargetPermBuffsCheck, "LEFT", -5, 0)
    hideTargetPermBuffsCheck.text:SetText("Hide Target Permanent Buffs")
    hideTargetPermBuffsCheck:SetChecked(JarUnitFramesDB.hideTargetPermanentBuffs)
    hideTargetPermBuffsCheck:SetScript("OnClick", function(self)
        JarUnitFramesDB.hideTargetPermanentBuffs = self:GetChecked()
        UpdateTargetBuffs()
    end)
    
    -- Mirror Target Position checkbox
    local mirrorCheck = CreateFrame("CheckButton", "JARUNITFRAMESMirrorCheck", frame, "UICheckButtonTemplate")
    mirrorCheck:SetPoint("TOPLEFT", showLevelCheck, "BOTTOMLEFT", 0, -5)
    mirrorCheck.text = mirrorCheck:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    mirrorCheck.text:SetPoint("LEFT", mirrorCheck, "RIGHT", 5, 0)
    mirrorCheck.text:SetText("Mirror Target Frame Position")
    mirrorCheck:SetChecked(JarUnitFramesDB.mirrorTargetPosition)
    mirrorCheck:SetScript("OnClick", function(self)
        JarUnitFramesDB.mirrorTargetPosition = self:GetChecked()
        
        -- Apply mirrored positioning immediately if enabled
        if JarUnitFramesDB.mirrorTargetPosition and playerFrame and targetFrame then
            local point = JarUnitFramesDB.playerPos.point
            local x = JarUnitFramesDB.playerPos.x
            local y = JarUnitFramesDB.playerPos.y
            local mirroredX = -x
            local mirroredY = y
            -- Use the same anchor point, just flip the X coordinate
            local mirroredPoint = point
            
            JarUnitFramesDB.targetPos.point = mirroredPoint
            JarUnitFramesDB.targetPos.x = mirroredX
            JarUnitFramesDB.targetPos.y = mirroredY
            
            targetFrame:ClearAllPoints()
            targetFrame:SetPoint(mirroredPoint, UIParent, mirroredPoint, mirroredX, mirroredY)
        end
    end)
    frame.mirrorCheck = mirrorCheck
    
    -- Background transparency slider
    local bgAlphaSlider = CreateFrame("Slider", nil, frame, "OptionsSliderTemplate")
    bgAlphaSlider:SetPoint("TOPLEFT", 20, -180)
    bgAlphaSlider:SetMinMaxValues(0.0, 1.0)
    bgAlphaSlider:SetValueStep(0.05)
    bgAlphaSlider:SetObeyStepOnDrag(true)
    bgAlphaSlider:SetWidth(200)
    bgAlphaSlider.Low:SetText("0%")
    bgAlphaSlider.High:SetText("100%")
    bgAlphaSlider.Text:SetText("Background Opacity: " .. math.floor(JarUnitFramesDB.bgAlpha * 100) .. "%")
    bgAlphaSlider:SetValue(JarUnitFramesDB.bgAlpha)
    bgAlphaSlider:SetScript("OnValueChanged", function(self, value)
        value = math.floor(value * 20 + 0.5) / 20  -- Round to 0.05 increments
        JarUnitFramesDB.bgAlpha = value
        self.Text:SetText("Background Opacity: " .. math.floor(value * 100) .. "%")
        -- Update drop shadow transparency on both frames
        if playerFrame then
            playerFrame.shadow:SetColorTexture(0, 0, 0, value)
        end
        if targetFrame then
            targetFrame.shadow:SetColorTexture(0, 0, 0, value)
        end
    end)
    frame.bgAlphaSlider = bgAlphaSlider
    
    -- Texture selection dropdown
    local textureLabel = frame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    textureLabel:SetPoint("TOPLEFT", 20, -235)
    textureLabel:SetText("Bar Texture:")
    
    local textureDropdown = CreateFrame("Frame", "JUF_TextureDropdown", frame, "UIDropDownMenuTemplate")
    textureDropdown:SetPoint("TOPLEFT", 10, -250)
    
    -- Get current texture name
    local function GetCurrentTextureName()
        for name, path in pairs(TEXTURES) do
            if path == JarUnitFramesDB.texture then
                return name
            end
        end
        return "Blizzard"
    end
    
    -- Initialize dropdown
    UIDropDownMenu_SetWidth(textureDropdown, 150)
    UIDropDownMenu_SetText(textureDropdown, GetCurrentTextureName())
    
    -- Dropdown menu function
    UIDropDownMenu_Initialize(textureDropdown, function(self, level)
        local info = UIDropDownMenu_CreateInfo()
        for name, path in pairs(TEXTURES) do
            info.text = name
            info.func = function()
                JarUnitFramesDB.texture = path
                UIDropDownMenu_SetText(textureDropdown, name)
                
                -- Update frame textures
                if playerFrame then
                    UpdateFrameTextures(playerFrame)
                end
                if targetFrame then
                    UpdateFrameTextures(targetFrame)
                end
            
                print("|cff00ff00Jar's Unit Frames|r Texture changed to " .. name)
            end
            info.checked = (path == JarUnitFramesDB.texture)
            UIDropDownMenu_AddButton(info)
        end
    end)
    
    -- Font selection dropdown
    local fontLabel = frame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    fontLabel:SetPoint("TOPLEFT", 20, -295)
    fontLabel:SetText("Font:")
    
    local fontDropdown = CreateFrame("Frame", "JUF_FontDropdown", frame, "UIDropDownMenuTemplate")
    fontDropdown:SetPoint("TOPLEFT", 10, -310)
    
    -- Get current font name
    local function GetCurrentFontName()
        for name, path in pairs(FONTS) do
            if path == JarUnitFramesDB.font then
                return name
            end
        end
        return "Friz Quadrata (Default)"
    end
    
    -- Initialize dropdown
    UIDropDownMenu_SetWidth(fontDropdown, 150)
    UIDropDownMenu_SetText(fontDropdown, GetCurrentFontName())
    
    -- Dropdown menu function
    UIDropDownMenu_Initialize(fontDropdown, function(self, level)
        local info = UIDropDownMenu_CreateInfo()
        for name, path in pairs(FONTS) do
            info.text = name
            info.func = function()
                JarUnitFramesDB.font = path
                UIDropDownMenu_SetText(fontDropdown, name)
                
                -- Update frame fonts
                if playerFrame then
                    UpdateFrameFonts(playerFrame)
                end
                if targetFrame then
                    UpdateFrameFonts(targetFrame)
                end
            
                print("|cff00ff00Jar's Unit Frames|r Font changed to " .. name)
            end
            info.checked = (path == JarUnitFramesDB.font)
            UIDropDownMenu_AddButton(info)
        end
    end)
    
    -- Close button is already provided by BasicFrameTemplateWithInset
    frame:SetScript("OnHide", function()
        -- Nothing needed
    end)
    
    return frame
end

-- Main update function
local function OnUpdate(self, elapsed)
    timeSinceLastUpdate = timeSinceLastUpdate + elapsed
    
    if timeSinceLastUpdate >= UPDATE_INTERVAL then
        timeSinceLastUpdate = 0
        
        if JarUnitFramesDB.showPlayerFrame then
            UpdatePlayerFrame()
        end
        
        if JarUnitFramesDB.showTargetFrame then
            UpdateTargetFrame()
        end
    end
end

-- Event handler
local eventFrame = CreateFrame("Frame")
eventFrame:RegisterEvent("PLAYER_LOGIN")
eventFrame:RegisterEvent("PLAYER_ENTERING_WORLD")
eventFrame:RegisterEvent("PLAYER_TARGET_CHANGED")

eventFrame:SetScript("OnEvent", function(self, event, ...)
    if event == "PLAYER_LOGIN" then
        -- Initialize defaults for any missing fields (after SavedVariables are loaded)
        for key, value in pairs(defaults) do
            if JarUnitFramesDB[key] == nil then
                JarUnitFramesDB[key] = value
            end
        end
        
        -- Load fonts from SharedMedia if available
        LoadSharedMediaFonts()
        
        print("|cff00ff00Jar's Unit Frames|r loaded. Type /juf for options.")
        
        -- Hide default Blizzard unit frames
        PlayerFrame:Hide()
        PlayerFrame:UnregisterAllEvents()
        PlayerFrame.Show = function() end  -- Prevent it from showing again
        
        TargetFrame:Hide()
        TargetFrame:UnregisterAllEvents()
        TargetFrame.Show = function() end  -- Prevent it from showing again
        
        -- Create frames
        playerFrame = CreatePlayerFrame()
        targetFrame = CreateTargetFrame()
        
        -- Create config window
        local success, result = pcall(CreateConfigFrame)
        if success then
            configFrame = result
            print("|cff00ff00Jar's Unit Frames|r Config frame created successfully")
        else
            print("|cffff0000Jar's Unit Frames|r Error creating config frame: " .. tostring(result))
        end
        
        -- Set up update ticker (only if playerFrame was created)
        if playerFrame then
            playerFrame:SetScript("OnUpdate", OnUpdate)
        end
        
        -- Initial update
        UpdatePlayerFrame()
        UpdatePlayerBuffs()
        UpdateTargetFrame()
        UpdateTargetBuffs()
    
    elseif event == "PLAYER_ENTERING_WORLD" then
        -- Initial full update
        UpdatePlayerFrame()
        UpdatePlayerBuffs()
        UpdateTargetFrame()
        UpdateTargetBuffs()
        
    elseif event == "PLAYER_TARGET_CHANGED" then
        -- Target changed, but frame events will handle the details
        -- Just do an initial update
        UpdateTargetFrame()
        UpdateTargetBuffs()
    end
end)

-- Slash commands
SLASH_JARUNITFRAMES1 = "/juf"
SLASH_JARUNITFRAMES2 = "/JARUNITFRAMES"
SlashCmdList["JARUNITFRAMES"] = function(msg)
    msg = msg:lower():trim()
    
    if msg == "config" or msg == "" then
        if configFrame then
            configFrame:SetShown(not configFrame:IsShown())
            print("|cff00ff00Jar's Unit Frames|r Config " .. (configFrame:IsShown() and "shown" or "hidden"))
        else
            print("|cffff0000Jar's Unit Frames|r Config frame not initialized!")
        end
        
    elseif msg == "toggle" then
        JarUnitFramesDB.showPlayerFrame = not JarUnitFramesDB.showPlayerFrame
        JarUnitFramesDB.showTargetFrame = not JarUnitFramesDB.showTargetFrame
        
        if playerFrame then
            playerFrame:SetShown(JarUnitFramesDB.showPlayerFrame)
        end
        if targetFrame then
            targetFrame:SetShown(JarUnitFramesDB.showTargetFrame)
        end
        
        print("|cff00ff00Jar's Unit Frames|r " .. (JarUnitFramesDB.showPlayerFrame and "shown" or "hidden"))
        
    elseif msg == "scale" then
        print("Usage: /juf scale <number> (e.g., /juf scale 1.2)")
        
    elseif msg:match("^scale%s+(.+)") then
        local scale = tonumber(msg:match("^scale%s+(.+)"))
        if scale and scale > 0.5 and scale < 3 then
            JarUnitFramesDB.frameScale = scale
            if playerFrame then
                playerFrame:SetScale(scale)
            end
            if targetFrame then
                targetFrame:SetScale(scale)
            end
            print("|cff00ff00Jar's Unit Frames|r scale set to " .. scale)
        else
            print("|cffff0000Error:|r Scale must be between 0.5 and 3.0")
        end
        
    elseif msg == "percent" then
        JarUnitFramesDB.showPercentages = not JarUnitFramesDB.showPercentages
        print("|cff00ff00Jar's Unit Frames|r percentages " .. (JarUnitFramesDB.showPercentages and "shown" or "hidden"))
        UpdatePlayerFrame()
        UpdateTargetFrame()
        
    elseif msg == "buffs" then
        -- List all current player buffs with their spell IDs
        local auras = C_UnitAuras.GetUnitAuras("player", "HELPFUL", 40, nil, nil)
        print("|cff00ff00Jar's Unit Frames|r Current Buffs:")
        for i, auraData in ipairs(auras) do
            local stacks = (auraData.applications and auraData.applications > 1) and (" x" .. auraData.applications) or ""
            print("  " .. i .. ". " .. auraData.name .. stacks .. " (ID: " .. auraData.spellId .. ")")
        end
        if #auras == 0 then
            print("  No buffs active")
        end
        
    elseif msg == "showconfig" then
        print("|cff00ff00Jar's Unit Frames|r Current Configuration:")
        print("  showPlayerFrame: " .. tostring(JarUnitFramesDB.showPlayerFrame))
        print("  showTargetFrame: " .. tostring(JarUnitFramesDB.showTargetFrame))
        print("  showPercentages: " .. tostring(JarUnitFramesDB.showPercentages))
        print("  showLevel: " .. tostring(JarUnitFramesDB.showLevel))
        print("  unlocked: " .. tostring(JarUnitFramesDB.unlocked))
        print("  frameScale: " .. tostring(JarUnitFramesDB.frameScale))
        print("  bgAlpha: " .. tostring(JarUnitFramesDB.bgAlpha))
        print("  mirrorTargetPosition: " .. tostring(JarUnitFramesDB.mirrorTargetPosition))
        print("  texture: " .. tostring(JarUnitFramesDB.texture))
        print("  font: " .. tostring(JarUnitFramesDB.font))
        print("  playerPos: point=" .. tostring(JarUnitFramesDB.playerPos.point) .. 
              ", x=" .. tostring(JarUnitFramesDB.playerPos.x) .. 
              ", y=" .. tostring(JarUnitFramesDB.playerPos.y))
        print("  targetPos: point=" .. tostring(JarUnitFramesDB.targetPos.point) .. 
              ", x=" .. tostring(JarUnitFramesDB.targetPos.x) .. 
              ", y=" .. tostring(JarUnitFramesDB.targetPos.y))
        
    else
        print("|cff00ff00Jar's Unit Frames|r commands:")
        print("  /juf - Open config window")
        print("  /juf config - Open config window")
        print("  /juf toggle - Show/hide frames")
        print("  /juf scale <number> - Set frame scale (0.5-2.0)")
        print("  /juf percent - Toggle percentage display")
        print("  /juf buffs - List current buffs with spell IDs")
        print("  /juf showConfig - Display all saved variables")
    end
end

