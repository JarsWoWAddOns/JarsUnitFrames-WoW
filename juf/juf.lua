-- Jar's Unit Frames for WoW 12.0.1
-- Demonstrates proper handling of secret values for unit frame data

-- Saved variables with defaults
JarUnitFramesDB = JarUnitFramesDB or {}

-- Default values (will be applied in PLAYER_LOGIN after SavedVariables load)
local defaults = {
    showPlayerFrame = true,
    showTargetFrame = true,
    showPetFrame = true,
    showFocusFrame = true,
    showTargetTargetFrame = true,
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
    focusPos = { point = "TOPLEFT", x = 500, y = -20 },
    focusWidth = 220,
    focusShowBuffs = true,
    focusShowDebuffs = true,
    totPos = { point = "TOPLEFT", x = 260, y = -100 },
    totWidth = 150,
    totShowBuffs = true,
    totShowDebuffs = true,
    petPos = { point = "TOPLEFT", x = 20, y = -200 },
    petWidth = 150,
    petShowBuffs = true,
    petShowDebuffs = true,
    hidePlayerPermanentBuffs = false,  -- Hide player buffs without timers
    hideTargetPermanentBuffs = false,  -- Hide target buffs without timers
    showPartyFrames = true,
    partyPos = { point = "TOPLEFT", x = 20, y = -300 },
    partyWidth = 150,
    partyPadding = 5,
    partyShowOnlyMyBuffs = true,
}

-- Frame references
local playerFrame, targetFrame, petFrame, focusFrame, targetTargetFrame, configFrame
local partyFrames = {}

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
    
    -- Proper tooltip handling for SecureUnitButton (prevents taint)
    frame:SetScript("OnEnter", function(self)
        local unit = self:GetAttribute("unit")
        if unit and UnitExists(unit) then
            GameTooltip_SetDefaultAnchor(GameTooltip, self)
            GameTooltip:SetUnit(unit)
            GameTooltip:Show()
        end
    end)
    frame:SetScript("OnLeave", function(self)
        GameTooltip:Hide()
    end)
    
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
        
        -- Add cooldown frame for duration spiral
        buff.cooldown = CreateFrame("Cooldown", nil, buff, "CooldownFrameTemplate")
        buff.cooldown:SetAllPoints()
        buff.cooldown:SetDrawEdge(false)
        buff.cooldown:SetDrawSwipe(true)
        buff.cooldown:SetReverse(true)
        buff.cooldown:SetHideCountdownNumbers(true)
        
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
        
        -- Add cooldown frame for duration spiral
        debuff.cooldown = CreateFrame("Cooldown", nil, debuff, "CooldownFrameTemplate")
        debuff.cooldown:SetAllPoints()
        debuff.cooldown:SetDrawEdge(false)
        debuff.cooldown:SetDrawSwipe(true)
        debuff.cooldown:SetReverse(true)
        debuff.cooldown:SetHideCountdownNumbers(true)
        
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
    
    -- Proper tooltip handling for SecureUnitButton (prevents taint)
    frame:SetScript("OnEnter", function(self)
        local unit = self:GetAttribute("unit")
        if unit and UnitExists(unit) then
            GameTooltip_SetDefaultAnchor(GameTooltip, self)
            GameTooltip:SetUnit(unit)
            GameTooltip:Show()
        end
    end)
    frame:SetScript("OnLeave", function(self)
        GameTooltip:Hide()
    end)
    
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
        
        -- Add cooldown frame for duration spiral
        buff.cooldown = CreateFrame("Cooldown", nil, buff, "CooldownFrameTemplate")
        buff.cooldown:SetAllPoints()
        buff.cooldown:SetDrawEdge(false)
        buff.cooldown:SetDrawSwipe(true)
        buff.cooldown:SetReverse(true)
        buff.cooldown:SetHideCountdownNumbers(true)
        
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
        
        -- Add cooldown frame for duration spiral
        debuff.cooldown = CreateFrame("Cooldown", nil, debuff, "CooldownFrameTemplate")
        debuff.cooldown:SetAllPoints()
        debuff.cooldown:SetDrawEdge(false)
        debuff.cooldown:SetDrawSwipe(true)
        debuff.cooldown:SetReverse(true)
        debuff.cooldown:SetHideCountdownNumbers(true)
        
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

-- Create Focus Frame
function CreateFocusFrame()
    local frame = CreateFrame("Button", "JarUnitFrameFocus", UIParent, "SecureUnitButtonTemplate")
    frame:SetSize(220, 30)
    frame:SetAttribute("unit", "focus")
    frame:SetAttribute("*type1", "target")
    frame:SetAttribute("*type2", "menu")
    frame:RegisterForClicks("AnyUp")
    
    -- Proper tooltip handling for SecureUnitButton (prevents taint)
    frame:SetScript("OnEnter", function(self)
        local unit = self:GetAttribute("unit")
        if unit and UnitExists(unit) then
            GameTooltip_SetDefaultAnchor(GameTooltip, self)
            GameTooltip:SetUnit(unit)
            GameTooltip:Show()
        end
    end)
    frame:SetScript("OnLeave", function(self)
        GameTooltip:Hide()
    end)
    
    -- Register events
    frame:RegisterEvent("PLAYER_TARGET_CHANGED")
    frame:RegisterEvent("UNIT_HEALTH")
    frame:RegisterEvent("UNIT_MAXHEALTH")
    frame:RegisterEvent("UNIT_POWER_UPDATE")
    frame:RegisterEvent("UNIT_MAXPOWER")
    frame:RegisterEvent("UNIT_NAME_UPDATE")
    frame:RegisterEvent("UNIT_LEVEL")
    frame:RegisterEvent("UNIT_AURA")
    frame:RegisterEvent("PLAYER_FOCUS_CHANGED")
    
    frame:SetScript("OnEvent", function(self, event, ...)
        local unit = ...
        if event == "PLAYER_FOCUS_CHANGED" or event == "PLAYER_TARGET_CHANGED" or (unit and unit == "focus") then
            UpdateFocusFrame()
            UpdateFocusBuffs()
            UpdateFocusDebuffs()
        end
    end)
    
    -- RegisterUnitWatch for automatic show/hide
    if not InCombatLockdown() then
        RegisterUnitWatch(frame)
    end
    
    -- Restore position or use default
    if JarUnitFramesDB.focusPos then
        RestoreFramePosition(frame, JarUnitFramesDB.focusPos)
    else
        frame:SetPoint("TOPLEFT", 500, -20)
    end
    
    frame:SetScale(JarUnitFramesDB.frameScale)
    
    -- Make draggable
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
            JarUnitFramesDB.focusPos.point = point
            JarUnitFramesDB.focusPos.x = x
            JarUnitFramesDB.focusPos.y = y
        end
    end)
    
    -- Drop shadow
    frame.shadow = frame:CreateTexture(nil, "BACKGROUND")
    frame.shadow:SetPoint("TOPLEFT", -3, 3)
    frame.shadow:SetPoint("BOTTOMRIGHT", 3, -3)
    frame.shadow:SetColorTexture(0, 0, 0, JarUnitFramesDB.bgAlpha)
    
    local font = JarUnitFramesDB.font or "Fonts\\FRIZQT__.TTF"
    local fontSize = JarUnitFramesDB.fontSize or 12
    local texture = JarUnitFramesDB.texture or "Interface\\TargetingFrame\\UI-StatusBar"
    
    -- Health bar
    frame.healthBar = CreateFrame("StatusBar", nil, frame)
    frame.healthBar:SetSize(220, 20)
    frame.healthBar:SetPoint("TOP", 0, 0)
    frame.healthBar:EnableMouse(false)
    frame.healthBar:SetStatusBarTexture(texture)
    frame.healthBar:SetStatusBarColor(1, 0, 0)
    frame.healthBar:SetMinMaxValues(0, 100)
    frame.healthBar:SetValue(0)
    frame.healthBar:SetReverseFill(true)
    
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
    
    -- Health text
    frame.healthText = frame.healthBar:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    frame.healthText:SetPoint("LEFT", frame.healthBar, "LEFT", 5, 0)
    frame.healthText:SetText("0")
    frame.healthText:SetJustifyH("LEFT")
    frame.healthText:SetFont(font, fontSize, "OUTLINE")
    
    -- Level text
    frame.levelText = frame.healthBar:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    frame.levelText:SetPoint("RIGHT", frame.healthBar, "RIGHT", -5, 0)
    frame.levelText:SetFont(font, fontSize, "OUTLINE")
    frame.levelText:SetText("")
    
    -- Power bar
    frame.powerBar = CreateFrame("StatusBar", nil, frame)
    frame.powerBar:SetSize(220, 8)
    frame.powerBar:SetPoint("TOP", 0, -22)
    frame.powerBar:EnableMouse(false)
    frame.powerBar:SetStatusBarTexture(texture)
    frame.powerBar:SetStatusBarColor(0, 0.4, 1)
    frame.powerBar:SetMinMaxValues(0, 100)
    frame.powerBar:SetValue(0)
    frame.powerBar:SetReverseFill(true)
    
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
    
    -- Name text
    frame.name = frame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    frame.name:SetPoint("TOPRIGHT", frame.powerBar, "BOTTOMRIGHT", 0, -5)
    frame.name:SetText("No Focus")
    frame.name:SetJustifyH("RIGHT")
    frame.name:SetFont(font, fontSize, "OUTLINE")
    
    -- Buff container (above the frame)
    frame.buffs = {}
    frame.buffContainer = CreateFrame("Frame", nil, frame)
    frame.buffContainer:SetSize(220, 20)
    frame.buffContainer:SetPoint("BOTTOMRIGHT", frame.healthBar, "TOPRIGHT", 0, 2)
    
    for i = 1, 40 do
        local buff = CreateFrame("Frame", nil, frame.buffContainer)
        buff:SetSize(18, 18)
        
        local col = (i - 1) % 10
        local row = math.floor((i - 1) / 10)
        buff:SetPoint("BOTTOMRIGHT", frame.buffContainer, "BOTTOMRIGHT", -col * 20, row * 20)
        
        buff.icon = buff:CreateTexture(nil, "ARTWORK")
        buff.icon:SetAllPoints()
        
        buff.count = buff:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        buff.count:SetPoint("BOTTOMRIGHT", 2, 0)
        buff.count:SetFont(font, 10, "OUTLINE")
        
        -- Add cooldown frame for duration spiral
        buff.cooldown = CreateFrame("Cooldown", nil, buff, "CooldownFrameTemplate")
        buff.cooldown:SetAllPoints()
        buff.cooldown:SetDrawEdge(false)
        buff.cooldown:SetDrawSwipe(true)
        buff.cooldown:SetReverse(true)
        buff.cooldown:SetHideCountdownNumbers(true)
        
        buff:SetScript("OnEnter", function(self)
            pcall(function()
                GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
                GameTooltip:SetUnitBuffByAuraInstanceID("focus", self.auraInstanceID)
                GameTooltip:Show()
            end)
        end)
        buff:SetScript("OnLeave", function() GameTooltip:Hide() end)
        
        buff:Hide()
        frame.buffs[i] = buff
    end
    
    -- Debuff container (below the name)
    frame.debuffs = {}
    frame.debuffContainer = CreateFrame("Frame", nil, frame)
    frame.debuffContainer:SetSize(220, 20)
    frame.debuffContainer:SetPoint("TOPRIGHT", frame.name, "BOTTOMRIGHT", 0, -2)
    
    for i = 1, 40 do
        local debuff = CreateFrame("Frame", nil, frame.debuffContainer)
        debuff:SetSize(18, 18)
        
        local col = (i - 1) % 10
        local row = math.floor((i - 1) / 10)
        debuff:SetPoint("TOPRIGHT", frame.debuffContainer, "TOPRIGHT", -col * 20, -row * 20)
        
        debuff.icon = debuff:CreateTexture(nil, "ARTWORK")
        debuff.icon:SetAllPoints()
        
        debuff.count = debuff:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        debuff.count:SetPoint("BOTTOMRIGHT", 2, 0)
        debuff.count:SetFont(font, 10, "OUTLINE")
        
        -- Add cooldown frame for duration spiral
        debuff.cooldown = CreateFrame("Cooldown", nil, debuff, "CooldownFrameTemplate")
        debuff.cooldown:SetAllPoints()
        debuff.cooldown:SetDrawEdge(false)
        debuff.cooldown:SetDrawSwipe(true)
        debuff.cooldown:SetReverse(true)
        debuff.cooldown:SetHideCountdownNumbers(true)
        
        debuff:SetScript("OnEnter", function(self)
            pcall(function()
                GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
                GameTooltip:SetUnitDebuffByAuraInstanceID("focus", self.auraInstanceID)
                GameTooltip:Show()
            end)
        end)
        debuff:SetScript("OnLeave", function() GameTooltip:Hide() end)
        
        debuff:Hide()
        frame.debuffs[i] = debuff
    end
    
    frame:Show()
    return frame
end

-- Create Target of Target Frame
function CreateTargetTargetFrame()
    local frame = CreateFrame("Button", "JarUnitFrameTargetTarget", UIParent, "SecureUnitButtonTemplate")
    local width = JarUnitFramesDB.totWidth or 150
    frame:SetSize(width, 30)
    frame:SetAttribute("unit", "targettarget")
    frame:SetAttribute("*type1", "target")
    frame:SetAttribute("*type2", "menu")
    frame:RegisterForClicks("AnyUp")
    
    -- Proper tooltip handling for SecureUnitButton (prevents taint)
    frame:SetScript("OnEnter", function(self)
        local unit = self:GetAttribute("unit")
        if unit and UnitExists(unit) then
            GameTooltip_SetDefaultAnchor(GameTooltip, self)
            GameTooltip:SetUnit(unit)
            GameTooltip:Show()
        end
    end)
    frame:SetScript("OnLeave", function(self)
        GameTooltip:Hide()
    end)
    
    -- Register events
    frame:RegisterEvent("PLAYER_TARGET_CHANGED")
    frame:RegisterEvent("UNIT_HEALTH")
    frame:RegisterEvent("UNIT_MAXHEALTH")
    frame:RegisterEvent("UNIT_POWER_UPDATE")
    frame:RegisterEvent("UNIT_MAXPOWER")
    frame:RegisterEvent("UNIT_NAME_UPDATE")
    frame:RegisterEvent("UNIT_AURA")
    
    frame:SetScript("OnEvent", function(self, event, ...)
        local unit = ...
        if event == "PLAYER_TARGET_CHANGED" or (unit and unit == "targettarget") then
            UpdateTargetTargetFrame()
            if JarUnitFramesDB.totShowBuffs then
                UpdateTargetTargetBuffs()
            end
            if JarUnitFramesDB.totShowDebuffs then
                UpdateTargetTargetDebuffs()
            end
        end
    end)
    
    -- RegisterUnitWatch for automatic show/hide
    if not InCombatLockdown() then
        RegisterUnitWatch(frame)
    end
    
    -- Restore position or use default
    if JarUnitFramesDB.totPos then
        RestoreFramePosition(frame, JarUnitFramesDB.totPos)
    else
        frame:SetPoint("TOPLEFT", 260, -100)
    end
    
    frame:SetScale(JarUnitFramesDB.frameScale)
    
    -- Make draggable
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
            JarUnitFramesDB.totPos.point = point
            JarUnitFramesDB.totPos.x = x
            JarUnitFramesDB.totPos.y = y
        end
    end)
    
    -- Drop shadow
    frame.shadow = frame:CreateTexture(nil, "BACKGROUND")
    frame.shadow:SetPoint("TOPLEFT", -3, 3)
    frame.shadow:SetPoint("BOTTOMRIGHT", 3, -3)
    frame.shadow:SetColorTexture(0, 0, 0, JarUnitFramesDB.bgAlpha)
    
    local font = JarUnitFramesDB.font or "Fonts\\FRIZQT__.TTF"
    local fontSize = JarUnitFramesDB.fontSize or 12
    local texture = JarUnitFramesDB.texture or "Interface\\TargetingFrame\\UI-StatusBar"
    
    -- Health bar
    frame.healthBar = CreateFrame("StatusBar", nil, frame)
    frame.healthBar:SetSize(width, 20)
    frame.healthBar:SetPoint("TOP", 0, 0)
    frame.healthBar:EnableMouse(false)
    frame.healthBar:SetStatusBarTexture(texture)
    frame.healthBar:SetStatusBarColor(1, 0, 0)
    frame.healthBar:SetMinMaxValues(0, 100)
    frame.healthBar:SetValue(0)
    frame.healthBar:SetReverseFill(false)  -- Fill left to right for ToT
    
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
    
    -- Health text
    frame.healthText = frame.healthBar:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    frame.healthText:SetPoint("LEFT", frame.healthBar, "LEFT", 5, 0)
    frame.healthText:SetText("0")
    frame.healthText:SetJustifyH("LEFT")
    frame.healthText:SetFont(font, fontSize, "OUTLINE")
    
    -- Power bar
    frame.powerBar = CreateFrame("StatusBar", nil, frame)
    frame.powerBar:SetSize(width, 8)
    frame.powerBar:SetPoint("TOP", 0, -22)
    frame.powerBar:EnableMouse(false)
    frame.powerBar:SetStatusBarTexture(texture)
    frame.powerBar:SetStatusBarColor(0, 0.4, 1)
    frame.powerBar:SetMinMaxValues(0, 100)
    frame.powerBar:SetValue(0)
    frame.powerBar:SetReverseFill(false)
    
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
    
    -- Name text
    frame.name = frame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    frame.name:SetPoint("TOPLEFT", frame.powerBar, "BOTTOMLEFT", 0, -5)
    frame.name:SetText("No ToT")
    frame.name:SetJustifyH("LEFT")
    frame.name:SetFont(font, fontSize, "OUTLINE")
    
    -- Buff container (above the frame)
    frame.buffs = {}
    frame.buffContainer = CreateFrame("Frame", nil, frame)
    frame.buffContainer:SetSize(width, 20)
    frame.buffContainer:SetPoint("BOTTOMLEFT", frame.healthBar, "TOPLEFT", 0, 2)
        
    for i = 1, 20 do
        local buff = CreateFrame("Frame", nil, frame.buffContainer)
        buff:SetSize(18, 18)
        
        local col = (i - 1) % 7
        local row = math.floor((i - 1) / 7)
        buff:SetPoint("BOTTOMLEFT", frame.buffContainer, "BOTTOMLEFT", col * 20, row * 20)
            
            buff.icon = buff:CreateTexture(nil, "ARTWORK")
            buff.icon:SetAllPoints()
            
            buff.count = buff:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
            buff.count:SetPoint("BOTTOMRIGHT", 2, 0)
            buff.count:SetFont(font, 10, "OUTLINE")
            
            buff:SetScript("OnEnter", function(self)
                pcall(function()
                    GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
                    GameTooltip:SetUnitBuffByAuraInstanceID("targettarget", self.auraInstanceID)
                    GameTooltip:Show()
                end)
            end)
            buff:SetScript("OnLeave", function() GameTooltip:Hide() end)
            
        buff:Hide()
        frame.buffs[i] = buff
    end
    
    -- Debuff container (below the name)
    frame.debuffs = {}
    frame.debuffContainer = CreateFrame("Frame", nil, frame)
    frame.debuffContainer:SetSize(width, 20)
    frame.debuffContainer:SetPoint("TOPLEFT", frame.name, "BOTTOMLEFT", 0, -2)
    
    for i = 1, 20 do
        local debuff = CreateFrame("Frame", nil, frame.debuffContainer)
        debuff:SetSize(18, 18)
        
        local col = (i - 1) % 7
        local row = math.floor((i - 1) / 7)
        debuff:SetPoint("TOPLEFT", frame.debuffContainer, "TOPLEFT", col * 20, -row * 20)
        
        debuff.icon = debuff:CreateTexture(nil, "ARTWORK")
        debuff.icon:SetAllPoints()
        
        debuff.count = debuff:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        debuff.count:SetPoint("BOTTOMRIGHT", 2, 0)
        debuff.count:SetFont(font, 10, "OUTLINE")
        
        debuff:SetScript("OnEnter", function(self)
            pcall(function()
                GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
                GameTooltip:SetUnitDebuffByAuraInstanceID("targettarget", self.auraInstanceID)
                GameTooltip:Show()
            end)
        end)
        debuff:SetScript("OnLeave", function() GameTooltip:Hide() end)
        
        debuff:Hide()
        frame.debuffs[i] = debuff
    end
    
    frame:Show()
    return frame
end

-- Create Pet Frame
function CreatePetFrame()
    local frame = CreateFrame("Button", "JarUnitFramePet", UIParent, "SecureUnitButtonTemplate")
    local width = JarUnitFramesDB.petWidth or 150
    frame:SetSize(width, 30)
    frame:SetAttribute("unit", "pet")
    frame:SetAttribute("*type1", "target")
    frame:SetAttribute("*type2", "menu")
    frame:RegisterForClicks("AnyUp")
    
    -- Proper tooltip handling for SecureUnitButton (prevents taint)
    frame:SetScript("OnEnter", function(self)
        local unit = self:GetAttribute("unit")
        if unit and UnitExists(unit) then
            GameTooltip_SetDefaultAnchor(GameTooltip, self)
            GameTooltip:SetUnit(unit)
            GameTooltip:Show()
        end
    end)
    frame:SetScript("OnLeave", function(self)
        GameTooltip:Hide()
    end)
    
    -- Register events
    frame:RegisterEvent("UNIT_PET")
    frame:RegisterEvent("UNIT_HEALTH")
    frame:RegisterEvent("UNIT_MAXHEALTH")
    frame:RegisterEvent("UNIT_POWER_UPDATE")
    frame:RegisterEvent("UNIT_MAXPOWER")
    frame:RegisterEvent("UNIT_NAME_UPDATE")
    frame:RegisterEvent("UNIT_AURA")
    
    frame:SetScript("OnEvent", function(self, event, ...)
        local unit = ...
        if event == "UNIT_PET" or (unit and unit == "pet") then
            UpdatePetFrame()
            if JarUnitFramesDB.petShowBuffs then
                UpdatePetBuffs()
            end
            if JarUnitFramesDB.petShowDebuffs then
                UpdatePetDebuffs()
            end
        end
    end)
    
    -- RegisterUnitWatch for automatic show/hide
    if not InCombatLockdown() then
        RegisterUnitWatch(frame)
    end
    
    -- Restore position or use default
    if JarUnitFramesDB.petPos then
        RestoreFramePosition(frame, JarUnitFramesDB.petPos)
    else
        frame:SetPoint("TOPLEFT", 20, -200)
    end
    
    frame:SetScale(JarUnitFramesDB.frameScale)
    
    -- Make draggable
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
            JarUnitFramesDB.petPos.point = point
            JarUnitFramesDB.petPos.x = x
            JarUnitFramesDB.petPos.y = y
        end
    end)
    
    -- Drop shadow
    frame.shadow = frame:CreateTexture(nil, "BACKGROUND")
    frame.shadow:SetPoint("TOPLEFT", -3, 3)
    frame.shadow:SetPoint("BOTTOMRIGHT", 3, -3)
    frame.shadow:SetColorTexture(0, 0, 0, JarUnitFramesDB.bgAlpha)
    
    local font = JarUnitFramesDB.font or "Fonts\\FRIZQT__.TTF"
    local fontSize = JarUnitFramesDB.fontSize or 12
    local texture = JarUnitFramesDB.texture or "Interface\\TargetingFrame\\UI-StatusBar"
    
    -- Health bar
    frame.healthBar = CreateFrame("StatusBar", nil, frame)
    frame.healthBar:SetSize(width, 20)
    frame.healthBar:SetPoint("TOP", 0, 0)
    frame.healthBar:EnableMouse(false)
    frame.healthBar:SetStatusBarTexture(texture)
    frame.healthBar:SetStatusBarColor(1, 0, 0)
    frame.healthBar:SetMinMaxValues(0, 100)
    frame.healthBar:SetValue(0)
    frame.healthBar:SetReverseFill(false)
    
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
    
    -- Health text
    frame.healthText = frame.healthBar:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    frame.healthText:SetPoint("LEFT", frame.healthBar, "LEFT", 5, 0)
    frame.healthText:SetText("0")
    frame.healthText:SetJustifyH("LEFT")
    frame.healthText:SetFont(font, fontSize, "OUTLINE")
    
    -- Power bar
    frame.powerBar = CreateFrame("StatusBar", nil, frame)
    frame.powerBar:SetSize(width, 8)
    frame.powerBar:SetPoint("TOP", 0, -22)
    frame.powerBar:EnableMouse(false)
    frame.powerBar:SetStatusBarTexture(texture)
    frame.powerBar:SetStatusBarColor(0, 0.4, 1)
    frame.powerBar:SetMinMaxValues(0, 100)
    frame.powerBar:SetValue(0)
    frame.powerBar:SetReverseFill(false)
    
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
    
    -- Name text
    frame.name = frame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    frame.name:SetPoint("TOPLEFT", frame.powerBar, "BOTTOMLEFT", 0, -5)
    frame.name:SetText("No Pet")
    frame.name:SetJustifyH("LEFT")
    frame.name:SetFont(font, fontSize, "OUTLINE")
    
    -- Buff container (above the frame)
    frame.buffs = {}
    frame.buffContainer = CreateFrame("Frame", nil, frame)
    frame.buffContainer:SetSize(width, 20)
    frame.buffContainer:SetPoint("BOTTOMLEFT", frame.healthBar, "TOPLEFT", 0, 2)
    
    for i = 1, 20 do
        local buff = CreateFrame("Frame", nil, frame.buffContainer)
        buff:SetSize(18, 18)
        
        local col = (i - 1) % 7
        local row = math.floor((i - 1) / 7)
        buff:SetPoint("BOTTOMLEFT", frame.buffContainer, "BOTTOMLEFT", col * 20, row * 20)
        
        buff.icon = buff:CreateTexture(nil, "ARTWORK")
        buff.icon:SetAllPoints()
        
        buff.count = buff:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        buff.count:SetPoint("BOTTOMRIGHT", 2, 0)
        buff.count:SetFont(font, 10, "OUTLINE")
        
        -- Add cooldown frame for duration spiral
        buff.cooldown = CreateFrame("Cooldown", nil, buff, "CooldownFrameTemplate")
        buff.cooldown:SetAllPoints()
        buff.cooldown:SetDrawEdge(false)
        buff.cooldown:SetDrawSwipe(true)
        buff.cooldown:SetReverse(true)
        buff.cooldown:SetHideCountdownNumbers(true)
        
        buff:SetScript("OnEnter", function(self)
            pcall(function()
                GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
                GameTooltip:SetUnitBuffByAuraInstanceID("pet", self.auraInstanceID)
                GameTooltip:Show()
            end)
        end)
        buff:SetScript("OnLeave", function() GameTooltip:Hide() end)
        
        buff:Hide()
        frame.buffs[i] = buff
    end
    
    -- Debuff container (below the name)
    frame.debuffs = {}
    frame.debuffContainer = CreateFrame("Frame", nil, frame)
    frame.debuffContainer:SetSize(width, 20)
    frame.debuffContainer:SetPoint("TOPLEFT", frame.name, "BOTTOMLEFT", 0, -2)
    
    for i = 1, 20 do
        local debuff = CreateFrame("Frame", nil, frame.debuffContainer)
        debuff:SetSize(18, 18)
        
        local col = (i - 1) % 7
        local row = math.floor((i - 1) / 7)
        debuff:SetPoint("TOPLEFT", frame.debuffContainer, "TOPLEFT", col * 20, -row * 20)
        
        debuff.icon = debuff:CreateTexture(nil, "ARTWORK")
        debuff.icon:SetAllPoints()
        
        debuff.count = debuff:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        debuff.count:SetPoint("BOTTOMRIGHT", 2, 0)
        debuff.count:SetFont(font, 10, "OUTLINE")
        
        -- Add cooldown frame for duration spiral
        debuff.cooldown = CreateFrame("Cooldown", nil, debuff, "CooldownFrameTemplate")
        debuff.cooldown:SetAllPoints()
        debuff.cooldown:SetDrawEdge(false)
        debuff.cooldown:SetDrawSwipe(true)
        debuff.cooldown:SetReverse(true)
        debuff.cooldown:SetHideCountdownNumbers(true)
        
        debuff:SetScript("OnEnter", function(self)
            pcall(function()
                GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
                GameTooltip:SetUnitDebuffByAuraInstanceID("pet", self.auraInstanceID)
                GameTooltip:Show()
            end)
        end)
        debuff:SetScript("OnLeave", function() GameTooltip:Hide() end)
        
        debuff:Hide()
        frame.debuffs[i] = debuff
    end
    
    frame:Show()
    return frame
end

-- Create party frame (for party1-4)
function CreatePartyFrame(partyNum)
    local font = JarUnitFramesDB.font or "Fonts\\FRIZQT__.TTF"
    local fontSize = JarUnitFramesDB.fontSize or 12
    local texture = JarUnitFramesDB.texture or "Interface\\TargetingFrame\\UI-StatusBar"
    local width = JarUnitFramesDB.partyWidth or 150
    
    local frame = CreateFrame("Button", "JUF_PartyFrame"..partyNum, UIParent, "SecureUnitButtonTemplate")
    frame:SetSize(width, 30)
    frame:SetAttribute("unit", "party"..partyNum)
    frame:SetAttribute("*type1", "target")
    frame:SetAttribute("*type2", "menu")
    frame:RegisterForClicks("AnyUp")
    
    -- Proper tooltip handling for SecureUnitButton (prevents taint)
    frame:SetScript("OnEnter", function(self)
        local unit = self:GetAttribute("unit")
        if unit and UnitExists(unit) then
            GameTooltip_SetDefaultAnchor(GameTooltip, self)
            GameTooltip:SetUnit(unit)
            GameTooltip:Show()
        end
    end)
    frame:SetScript("OnLeave", function(self)
        GameTooltip:Hide()
    end)
    frame:SetSize(width, 45)
    frame:SetFrameStrata("MEDIUM")
    frame:SetFrameLevel(10)
    frame:SetAttribute("unit", "party"..partyNum)
    frame:SetAttribute("type1", "target")
    frame:SetAttribute("type2", "togglemenu")
    frame:RegisterForClicks("AnyUp")
    
    -- Make frame movable when unlocked (use Shift+Drag to avoid conflicts with secure clicks)
    frame:SetMovable(true)
    frame:SetClampedToScreen(true)
    frame:RegisterForDrag("LeftButton")
    frame:SetScript("OnDragStart", function(self)
        if JarUnitFramesDB.unlocked and IsShiftKeyDown() then
            self:StartMoving()
        end
    end)
    frame:SetScript("OnDragStop", function(self)
        self:StopMovingOrSizing()
        -- Save position only for first party frame
        if partyNum == 1 then
            local point, _, _, x, y = self:GetPoint()
            JarUnitFramesDB.partyPos = {point = point, x = x, y = y}
        end
    end)
    
    -- Add visual border when unlocked
    frame.unlockBorder = frame:CreateTexture(nil, "OVERLAY")
    frame.unlockBorder:SetAllPoints()
    frame.unlockBorder:SetColorTexture(0, 1, 0, 0.3)
    frame.unlockBorder:Hide()
    
    -- Register events
    frame:RegisterEvent("UNIT_HEALTH")
    frame:RegisterEvent("UNIT_MAXHEALTH")
    frame:RegisterEvent("UNIT_POWER_UPDATE")
    frame:RegisterEvent("UNIT_MAXPOWER")
    frame:RegisterEvent("UNIT_AURA")
    frame:RegisterEvent("UNIT_NAME_UPDATE")
    frame:RegisterEvent("GROUP_ROSTER_UPDATE")
    
    -- Event handler
    frame:SetScript("OnEvent", function(self, event, eventUnit)
        if event == "UNIT_AURA" and eventUnit == "party"..partyNum then
            UpdatePartyBuffs(partyNum)
            UpdatePartyDebuffs(partyNum)
        elseif event == "GROUP_ROSTER_UPDATE" then
            UpdatePartyFrame(partyNum)
            UpdatePartyBuffs(partyNum)
            UpdatePartyDebuffs(partyNum)
        elseif eventUnit == "party"..partyNum then
            UpdatePartyFrame(partyNum)
        end
    end)
    
    if not InCombatLockdown() then
        RegisterUnitWatch(frame)
    end
    
    -- Drop shadow background
    frame.shadow = frame:CreateTexture(nil, "BACKGROUND")
    frame.shadow:SetPoint("TOPLEFT", -3, 3)
    frame.shadow:SetPoint("BOTTOMRIGHT", 3, -3)
    frame.shadow:SetColorTexture(0, 0, 0, JarUnitFramesDB.bgAlpha)
    
    -- Health bar
    frame.healthBar = CreateFrame("StatusBar", nil, frame)
    frame.healthBar:SetSize(width, 20)
    frame.healthBar:SetPoint("TOP", 0, -7)
    frame.healthBar:SetStatusBarTexture(texture)
    frame.healthBar:SetMinMaxValues(0, 100)
    frame.healthBar:SetValue(100)
    
    frame.healthBar.border = CreateFrame("Frame", nil, frame.healthBar, "BackdropTemplate")
    frame.healthBar.border:SetAllPoints()
    frame.healthBar.border:SetBackdrop({
        edgeFile = "Interface\\Buttons\\WHITE8X8",
        edgeSize = 1,
    })
    frame.healthBar.border:SetBackdropBorderColor(0, 0, 0, 1)
    
    frame.healthBar.bg = frame.healthBar:CreateTexture(nil, "BACKGROUND")
    frame.healthBar.bg:SetAllPoints(frame.healthBar)
    frame.healthBar.bg:SetTexture(texture)
    frame.healthBar.bg:SetVertexColor(0, 0.4, 0)
    frame.healthBar.bg:SetAlpha(JarUnitFramesDB.bgAlpha)
    
    -- Health text
    frame.healthText = frame.healthBar:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    frame.healthText:SetPoint("RIGHT", frame.healthBar, "RIGHT", -3, 0)
    frame.healthText:SetFont(font, fontSize, "OUTLINE")
    frame.healthText:SetJustifyH("RIGHT")
    frame.healthText:SetText("")
    
    -- Power bar
    frame.powerBar = CreateFrame("StatusBar", nil, frame)
    frame.powerBar:SetSize(width, 8)
    frame.powerBar:SetPoint("TOP", frame.healthBar, "BOTTOM", 0, 0)
    frame.powerBar:SetStatusBarTexture(texture)
    frame.powerBar:SetStatusBarColor(0, 0.4, 1)
    frame.powerBar:SetMinMaxValues(0, 100)
    frame.powerBar:SetValue(0)
    
    frame.powerBar.border = CreateFrame("Frame", nil, frame.powerBar, "BackdropTemplate")
    frame.powerBar.border:SetAllPoints()
    frame.powerBar.border:SetBackdrop({
        edgeFile = "Interface\\Buttons\\WHITE8X8",
        edgeSize = 1,
    })
    frame.powerBar.border:SetBackdropBorderColor(0, 0, 0, 1)
    
    frame.powerBar.bg = frame.powerBar:CreateTexture(nil, "BACKGROUND")
    frame.powerBar.bg:SetAllPoints(frame.powerBar)
    frame.powerBar.bg:SetTexture(texture)
    frame.powerBar.bg:SetVertexColor(0, 0, 0.4)
    frame.powerBar.bg:SetAlpha(JarUnitFramesDB.bgAlpha)
    
    -- Name text
    frame.name = frame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    frame.name:SetPoint("TOPLEFT", frame.powerBar, "BOTTOMLEFT", 0, -2)
    frame.name:SetText("Party "..partyNum)
    frame.name:SetJustifyH("LEFT")
    frame.name:SetFont(font, fontSize, "OUTLINE")
    
    -- Buffs container (right side, growing rightward)
    frame.buffs = {}
    for i = 1, 15 do
        local buff = CreateFrame("Frame", nil, frame)
        buff:SetSize(18, 18)
        
        local col = (i - 1) % 5
        local row = math.floor((i - 1) / 5)
        buff:SetPoint("BOTTOMLEFT", frame.powerBar, "BOTTOMRIGHT", 2 + col * 20, row * 20)
        
        buff.icon = buff:CreateTexture(nil, "ARTWORK")
        buff.icon:SetAllPoints()
        buff.icon:SetTexCoord(0.07, 0.93, 0.07, 0.93)
        
        buff.border = buff:CreateTexture(nil, "OVERLAY")
        buff.border:SetAllPoints()
        buff.border:SetTexture("Interface\\Buttons\\UI-Debuff-Overlays")
        buff.border:SetTexCoord(0.296875, 0.5703125, 0, 0.515625)
        
        buff.count = buff:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        buff.count:SetPoint("BOTTOMRIGHT", 2, 0)
        buff.count:SetFont(font, 10, "OUTLINE")
        
        buff.cooldown = CreateFrame("Cooldown", nil, buff, "CooldownFrameTemplate")
        buff.cooldown:SetAllPoints()
        buff.cooldown:SetDrawEdge(false)
        buff.cooldown:SetDrawSwipe(true)
        buff.cooldown:SetReverse(true)
        buff.cooldown:SetHideCountdownNumbers(true)
        
        buff:EnableMouse(true)
        buff:SetScript("OnEnter", function(self)
            if self.auraInstanceID then
                pcall(function()
                    GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
                    GameTooltip:SetUnitBuffByAuraInstanceID("party"..partyNum, self.auraInstanceID)
                    GameTooltip:Show()
                end)
            end
        end)
        buff:SetScript("OnLeave", function() GameTooltip:Hide() end)
        
        buff:Hide()
        frame.buffs[i] = buff
    end
    
    -- Debuffs container (left side, growing leftward)
    frame.debuffs = {}
    for i = 1, 15 do
        local debuff = CreateFrame("Frame", nil, frame)
        debuff:SetSize(18, 18)
        
        local col = (i - 1) % 5
        local row = math.floor((i - 1) / 5)
        debuff:SetPoint("BOTTOMRIGHT", frame.powerBar, "BOTTOMLEFT", -2 - col * 20, row * 20)
        
        debuff.icon = debuff:CreateTexture(nil, "ARTWORK")
        debuff.icon:SetAllPoints()
        debuff.icon:SetTexCoord(0.07, 0.93, 0.07, 0.93)
        
        debuff.border = debuff:CreateTexture(nil, "OVERLAY")
        debuff.border:SetAllPoints()
        debuff.border:SetTexture("Interface\\Buttons\\UI-Debuff-Overlays")
        debuff.border:SetTexCoord(0.296875, 0.5703125, 0, 0.515625)
        
        debuff.count = debuff:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        debuff.count:SetPoint("BOTTOMRIGHT", 2, 0)
        debuff.count:SetFont(font, 10, "OUTLINE")
        
        debuff.cooldown = CreateFrame("Cooldown", nil, debuff, "CooldownFrameTemplate")
        debuff.cooldown:SetAllPoints()
        debuff.cooldown:SetDrawEdge(false)
        debuff.cooldown:SetDrawSwipe(true)
        debuff.cooldown:SetReverse(true)
        debuff.cooldown:SetHideCountdownNumbers(true)
        
        debuff:EnableMouse(true)
        debuff:SetScript("OnEnter", function(self)
            if self.auraInstanceID then
                pcall(function()
                    GameTooltip:SetOwner(self, "ANCHOR_LEFT")
                    GameTooltip:SetUnitDebuffByAuraInstanceID("party"..partyNum, self.auraInstanceID)
                    GameTooltip:Show()
                end)
            end
        end)
        debuff:SetScript("OnLeave", function() GameTooltip:Hide() end)
        
        debuff:Hide()
        frame.debuffs[i] = debuff
    end
    
    frame:Hide()
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
            
            -- Show stack count (SetText handles secret values safely)
            buff.count:SetText(C_UnitAuras.GetAuraApplicationDisplayCount("player", auraData.auraInstanceID, 2, 99))
            
            -- Update cooldown spiral
            if buff.cooldown and auraData.duration and auraData.expirationTime then
                if C_StringUtil.TruncateWhenZero(auraData.duration) then
                    buff.cooldown:SetCooldown(auraData.duration, auraData.expirationTime)
                    buff.cooldown:SetCooldownFromExpirationTime(auraData.expirationTime, auraData.duration)
                    buff.cooldown:Show()
                else
                    buff.cooldown:Hide()
                end
            end
            
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
            
            -- Show stack count (SetText handles secret values safely)
            buff.count:SetText(C_UnitAuras.GetAuraApplicationDisplayCount("target", auraData.auraInstanceID, 2, 99))
            
            -- Update cooldown spiral
            if buff.cooldown and auraData.duration and auraData.expirationTime then
                if C_StringUtil.TruncateWhenZero(auraData.duration) then
                    buff.cooldown:SetCooldown(auraData.duration, auraData.expirationTime)
                    buff.cooldown:SetCooldownFromExpirationTime(auraData.expirationTime, auraData.duration)
                    buff.cooldown:Show()
                else
                    buff.cooldown:Hide()
                end
            end
            
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
        
        -- Show stack count (SetText handles secret values safely)
        debuff.count:SetText(C_UnitAuras.GetAuraApplicationDisplayCount("player", auraData.auraInstanceID, 2, 99))
        
        -- Update cooldown spiral
        if debuff.cooldown and auraData.duration and auraData.expirationTime then
            if C_StringUtil.TruncateWhenZero(auraData.duration) then
                debuff.cooldown:SetCooldown(auraData.duration, auraData.expirationTime)
                debuff.cooldown:SetCooldownFromExpirationTime(auraData.expirationTime, auraData.duration)
                debuff.cooldown:Show()
            else
                debuff.cooldown:Hide()
            end
        end
        
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
        
        -- Show stack count (SetText handles secret values safely)
        debuff.count:SetText(C_UnitAuras.GetAuraApplicationDisplayCount("target", auraData.auraInstanceID, 2, 99))
        
        -- Update cooldown spiral
        if debuff.cooldown and auraData.duration and auraData.expirationTime then
            if C_StringUtil.TruncateWhenZero(auraData.duration) then
                debuff.cooldown:SetCooldown(auraData.duration, auraData.expirationTime)
                debuff.cooldown:SetCooldownFromExpirationTime(auraData.expirationTime, auraData.duration)
                debuff.cooldown:Show()
            else
                debuff.cooldown:Hide()
            end
        end
        
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

-- Update focus buffs
function UpdateFocusBuffs()
    if not focusFrame or not focusFrame.buffs then return end
    
    -- Hide all buffs if disabled or no focus
    if not JarUnitFramesDB.focusShowBuffs or not UnitExists("focus") then
        for i = 1, 40 do
            focusFrame.buffs[i]:Hide()
        end
        return
    end
    
    local auras = C_UnitAuras.GetUnitAuras("focus", "HELPFUL", 40) or {}
    local buffIndex = 1
    
    for _, auraData in ipairs(auras) do
        if buffIndex > 40 then break end
        
        local buff = focusFrame.buffs[buffIndex]
        buff.icon:SetTexture(auraData.icon)
        buff.auraInstanceID = auraData.auraInstanceID
        buff.count:SetText("")
        
        buff:Show()
        buffIndex = buffIndex + 1
    end
    
    -- Hide unused buff frames
    for i = buffIndex, 40 do
        focusFrame.buffs[i]:Hide()
    end
end

-- Update focus debuffs
function UpdateFocusDebuffs()
    if not focusFrame or not focusFrame.debuffs then return end
    
    -- Hide all debuffs if disabled or no focus
    if not JarUnitFramesDB.focusShowDebuffs or not UnitExists("focus") then
        for i = 1, 40 do
            focusFrame.debuffs[i]:Hide()
        end
        return
    end
    
    local auras = C_UnitAuras.GetUnitAuras("focus", "HARMFUL", 40) or {}
    local debuffIndex = 1
    
    for _, auraData in ipairs(auras) do
        if debuffIndex > 40 then break end
        
        local debuff = focusFrame.debuffs[debuffIndex]
        debuff.icon:SetTexture(auraData.icon)
        debuff.auraInstanceID = auraData.auraInstanceID
        debuff.count:SetText("")
        
        debuff:Show()
        debuffIndex = debuffIndex + 1
    end
    
    -- Hide unused debuff frames
    for i = debuffIndex, 40 do
        focusFrame.debuffs[i]:Hide()
    end
end

-- Update focus frame
function UpdateFocusFrame()
    if not focusFrame then return end
    
    -- Check if we have a focus
    if not UnitExists("focus") then
        focusFrame:Hide()
        return
    end
    
    focusFrame:Show()
    
    -- Get focus name
    local name = UnitName("focus")
    focusFrame.name:SetText(name or "Unknown")
    
    -- Update level if enabled
    if JarUnitFramesDB.showLevel and UnitLevel("focus") then
        focusFrame.levelText:SetText(UnitLevel("focus"))
    else
        focusFrame.levelText:SetText("")
    end
    
    -- Get health values
    local health = UnitHealth("focus")
    local maxHealth = UnitHealthMax("focus")
    
    focusFrame.healthBar:SetMinMaxValues(0, maxHealth)
    focusFrame.healthBar:SetValue(health)
    focusFrame.healthText:SetText(BreakUpLargeNumbers(health))
    
    -- Get power values
    local power = UnitPower("focus")
    local maxPower = UnitPowerMax("focus")
    local powerType = UnitPowerType("focus")
    
    focusFrame.powerBar:SetMinMaxValues(0, maxPower)
    focusFrame.powerBar:SetValue(power)
    
    -- Color power bar
    local powerColor = PowerBarColor[powerType]
    if powerColor then
        focusFrame.powerBar:SetStatusBarColor(powerColor.r, powerColor.g, powerColor.b)
        focusFrame.powerBar.bg:SetVertexColor(powerColor.r * 0.3, powerColor.g * 0.3, powerColor.b * 0.3)
    end
    
    -- Color health bar by class/reaction
    if UnitIsPlayer("focus") then
        local _, class = UnitClass("focus")
        if class and RAID_CLASS_COLORS[class] then
            local classColor = RAID_CLASS_COLORS[class]
            focusFrame.healthBar:SetStatusBarColor(classColor.r, classColor.g, classColor.b)
            focusFrame.healthBar.bg:SetVertexColor(classColor.r * 0.3, classColor.g * 0.3, classColor.b * 0.3)
        else
            if UnitIsEnemy("player", "focus") then
                focusFrame.healthBar:SetStatusBarColor(1, 0, 0)
                focusFrame.healthBar.bg:SetVertexColor(0.3, 0, 0)
            else
                focusFrame.healthBar:SetStatusBarColor(0, 1, 0)
                focusFrame.healthBar.bg:SetVertexColor(0, 0.3, 0)
            end
        end
    else
        local reaction = UnitReaction("focus", "player")
        if reaction and reaction <= 3 then
            focusFrame.healthBar:SetStatusBarColor(1, 0, 0)
        elseif reaction and reaction >= 5 then
            focusFrame.healthBar:SetStatusBarColor(0, 1, 0)
        else
            focusFrame.healthBar:SetStatusBarColor(1, 1, 0)
        end
    end
end

-- Update target of target buffs
function UpdateTargetTargetBuffs()
    if not targetTargetFrame or not targetTargetFrame.buffs then return end
    
    -- Hide all buffs if disabled or no targettarget
    if not JarUnitFramesDB.totShowBuffs or not UnitExists("targettarget") then
        for i = 1, 20 do
            targetTargetFrame.buffs[i]:Hide()
        end
        return
    end
    
    local auras = C_UnitAuras.GetUnitAuras("targettarget", "HELPFUL", 20) or {}
    local buffIndex = 1
    
    for _, auraData in ipairs(auras) do
        if buffIndex > 20 then break end
        
        local buff = targetTargetFrame.buffs[buffIndex]
        buff.icon:SetTexture(auraData.icon)
        buff.auraInstanceID = auraData.auraInstanceID
        buff.count:SetText("")
        
        buff:Show()
        buffIndex = buffIndex + 1
    end
    
    -- Hide unused buff frames
    for i = buffIndex, 20 do
        targetTargetFrame.buffs[i]:Hide()
    end
end

-- Update target of target debuffs
function UpdateTargetTargetDebuffs()
    if not targetTargetFrame or not targetTargetFrame.debuffs then return end
    
    -- Hide all debuffs if disabled or no targettarget
    if not JarUnitFramesDB.totShowDebuffs or not UnitExists("targettarget") then
        for i = 1, 20 do
            targetTargetFrame.debuffs[i]:Hide()
        end
        return
    end
    
    local auras = C_UnitAuras.GetUnitAuras("targettarget", "HARMFUL", 20) or {}
    local debuffIndex = 1
    
    for _, auraData in ipairs(auras) do
        if debuffIndex > 20 then break end
        
        local debuff = targetTargetFrame.debuffs[debuffIndex]
        debuff.icon:SetTexture(auraData.icon)
        debuff.auraInstanceID = auraData.auraInstanceID
        debuff.count:SetText("")
        
        debuff:Show()
        debuffIndex = debuffIndex + 1
    end
    
    -- Hide unused debuff frames
    for i = debuffIndex, 20 do
        targetTargetFrame.debuffs[i]:Hide()
    end
end

-- Update target of target frame
function UpdateTargetTargetFrame()
    if not targetTargetFrame then return end
    
    -- Check if the frame is disabled in settings
    if not JarUnitFramesDB.showTargetTargetFrame then
        targetTargetFrame:Hide()
        return
    end
    
    -- Check if we have a targettarget
    if not UnitExists("targettarget") then
        targetTargetFrame:Hide()
        return
    end
    
    targetTargetFrame:Show()
    
    -- Get targettarget name
    local name = UnitName("targettarget")
    targetTargetFrame.name:SetText(name or "Unknown")
    
    -- Get health values
    local health = UnitHealth("targettarget")
    local maxHealth = UnitHealthMax("targettarget")
    
    targetTargetFrame.healthBar:SetMinMaxValues(0, maxHealth)
    targetTargetFrame.healthBar:SetValue(health)
    targetTargetFrame.healthText:SetText(BreakUpLargeNumbers(health))
    
    -- Get power values
    local power = UnitPower("targettarget")
    local maxPower = UnitPowerMax("targettarget")
    local powerType = UnitPowerType("targettarget")
    
    targetTargetFrame.powerBar:SetMinMaxValues(0, maxPower)
    targetTargetFrame.powerBar:SetValue(power)
    
    -- Color power bar
    local powerColor = PowerBarColor[powerType]
    if powerColor then
        targetTargetFrame.powerBar:SetStatusBarColor(powerColor.r, powerColor.g, powerColor.b)
        targetTargetFrame.powerBar.bg:SetVertexColor(powerColor.r * 0.3, powerColor.g * 0.3, powerColor.b * 0.3)
    end
    
    -- Color health bar by class/reaction
    if UnitIsPlayer("targettarget") then
        local _, class = UnitClass("targettarget")
        if class and RAID_CLASS_COLORS[class] then
            local classColor = RAID_CLASS_COLORS[class]
            targetTargetFrame.healthBar:SetStatusBarColor(classColor.r, classColor.g, classColor.b)
            targetTargetFrame.healthBar.bg:SetVertexColor(classColor.r * 0.3, classColor.g * 0.3, classColor.b * 0.3)
        else
            if UnitIsEnemy("player", "targettarget") then
                targetTargetFrame.healthBar:SetStatusBarColor(1, 0, 0)
                targetTargetFrame.healthBar.bg:SetVertexColor(0.3, 0, 0)
            else
                targetTargetFrame.healthBar:SetStatusBarColor(0, 1, 0)
                targetTargetFrame.healthBar.bg:SetVertexColor(0, 0.3, 0)
            end
        end
    else
        local reaction = UnitReaction("targettarget", "player")
        if reaction and reaction <= 3 then
            targetTargetFrame.healthBar:SetStatusBarColor(1, 0, 0)
        elseif reaction and reaction >= 5 then
            targetTargetFrame.healthBar:SetStatusBarColor(0, 1, 0)
        else
            targetTargetFrame.healthBar:SetStatusBarColor(1, 1, 0)
        end
    end
end

-- Update pet buffs
function UpdatePetBuffs()
    if not petFrame or not petFrame.buffs then return end
    
    -- Hide all buffs if disabled or no pet
    if not JarUnitFramesDB.petShowBuffs or not UnitExists("pet") then
        for i = 1, 20 do
            petFrame.buffs[i]:Hide()
        end
        return
    end
    
    local auras = C_UnitAuras.GetUnitAuras("pet", "HELPFUL", 20) or {}
    local buffIndex = 1
    
    for _, auraData in ipairs(auras) do
        if buffIndex > 20 then break end
        
        local buff = petFrame.buffs[buffIndex]
        buff.icon:SetTexture(auraData.icon)
        buff.auraInstanceID = auraData.auraInstanceID
        buff.count:SetText("")
        
        buff:Show()
        buffIndex = buffIndex + 1
    end
    
    -- Hide unused buff frames
    for i = buffIndex, 20 do
        petFrame.buffs[i]:Hide()
    end
end

-- Update pet debuffs
function UpdatePetDebuffs()
    if not petFrame or not petFrame.debuffs then return end
    
    -- Hide all debuffs if disabled or no pet
    if not JarUnitFramesDB.petShowDebuffs or not UnitExists("pet") then
        for i = 1, 20 do
            petFrame.debuffs[i]:Hide()
        end
        return
    end
    
    local auras = C_UnitAuras.GetUnitAuras("pet", "HARMFUL", 20) or {}
    local debuffIndex = 1
    
    for _, auraData in ipairs(auras) do
        if debuffIndex > 20 then break end
        
        local debuff = petFrame.debuffs[debuffIndex]
        debuff.icon:SetTexture(auraData.icon)
        debuff.auraInstanceID = auraData.auraInstanceID
        debuff.count:SetText("")
        
        debuff:Show()
        debuffIndex = debuffIndex + 1
    end
    
    -- Hide unused debuff frames
    for i = debuffIndex, 20 do
        petFrame.debuffs[i]:Hide()
    end
end

-- Update pet frame
function UpdatePetFrame()
    if not petFrame then return end
    
    -- Check if we have a pet
    if not UnitExists("pet") then
        petFrame:Hide()
        return
    end
    
    petFrame:Show()
    
    -- Get pet name
    local name = UnitName("pet")
    petFrame.name:SetText(name or "Unknown")
    
    -- Get health values
    local health = UnitHealth("pet")
    local maxHealth = UnitHealthMax("pet")
    
    petFrame.healthBar:SetMinMaxValues(0, maxHealth)
    petFrame.healthBar:SetValue(health)
    petFrame.healthText:SetText(BreakUpLargeNumbers(health))
    
    -- Get power values
    local power = UnitPower("pet")
    local maxPower = UnitPowerMax("pet")
    local powerType = UnitPowerType("pet")
    
    petFrame.powerBar:SetMinMaxValues(0, maxPower)
    petFrame.powerBar:SetValue(power)
    
    -- Color power bar
    local powerColor = PowerBarColor[powerType]
    if powerColor then
        petFrame.powerBar:SetStatusBarColor(powerColor.r, powerColor.g, powerColor.b)
        petFrame.powerBar.bg:SetVertexColor(powerColor.r * 0.3, powerColor.g * 0.3, powerColor.b * 0.3)
    end
    
    -- Color health bar (green for friendly pet)
    petFrame.healthBar:SetStatusBarColor(0, 1, 0)
    petFrame.healthBar.bg:SetVertexColor(0, 0.3, 0)
end

-- Reposition party frames based on width and padding settings
function RepositionPartyFrames()
    if not partyFrames[1] then return end
    
    local width = JarUnitFramesDB.partyWidth
    local padding = JarUnitFramesDB.partyPadding
    
    -- Clear all anchor points first
    for i = 1, 4 do
        if partyFrames[i] then
            partyFrames[i]:ClearAllPoints()
        end
    end
    
    -- Position first frame
    if JarUnitFramesDB.partyPos then
        partyFrames[1]:SetPoint(JarUnitFramesDB.partyPos.point or "LEFT", UIParent, JarUnitFramesDB.partyPos.point or "LEFT", JarUnitFramesDB.partyPos.x, JarUnitFramesDB.partyPos.y)
    else
        partyFrames[1]:SetPoint("LEFT", UIParent, "LEFT", 50, 0)
    end
    
    -- Set width for all frames and position vertically
    for i = 1, 4 do
        if partyFrames[i] then
            local f = partyFrames[i]
            
            -- Update frame width
            f:SetWidth(width)
            
            -- Update health bar width
            if f.healthBar then
                f.healthBar:SetWidth(width)
            end
            
            -- Update power bar width
            if f.powerBar then
                f.powerBar:SetWidth(width)
            end
            
            -- Reanchor buffs and debuffs (they're positioned relative to power bar edges)
            -- Buffs grow right from power bar right edge
            if f.buffs then
                for j = 1, 15 do
                    if f.buffs[j] then
                        f.buffs[j]:ClearAllPoints()
                        local col = (j - 1) % 5
                        local row = math.floor((j - 1) / 5)
                        f.buffs[j]:SetPoint("BOTTOMLEFT", f.powerBar, "BOTTOMRIGHT", 2 + col * 20, row * 20)
                    end
                end
            end
            
            -- Debuffs grow left from power bar left edge
            if f.debuffs then
                for j = 1, 15 do
                    if f.debuffs[j] then
                        f.debuffs[j]:ClearAllPoints()
                        local col = (j - 1) % 5
                        local row = math.floor((j - 1) / 5)
                        f.debuffs[j]:SetPoint("BOTTOMRIGHT", f.powerBar, "BOTTOMLEFT", -2 - col * 20, row * 20)
                    end
                end
            end
            
            -- Position frames 2-4 below the previous frame with padding
            if i > 1 then
                f:SetPoint("TOPLEFT", partyFrames[i-1], "BOTTOMLEFT", 0, -padding)
            end
        end
    end
end

-- Update party frame
function UpdatePartyFrame(partyNum)
    local frame = partyFrames[partyNum]
    if not frame then return end
    
    local unit = "party"..partyNum
    
    -- Check if party member exists (RegisterUnitWatch handles show/hide)
    if not UnitExists(unit) then
        return
    end
    
    -- Update name
    local name = UnitName(unit)
    frame.name:SetText(name or "Unknown")
    
    -- Get health values (secret values)
    local health = UnitHealth(unit)
    local maxHealth = UnitHealthMax(unit)
    
    -- Pass directly to status bar
    frame.healthBar:SetMinMaxValues(0, maxHealth)
    frame.healthBar:SetValue(health)
    
    -- Show numeric values
    frame.healthText:SetText(BreakUpLargeNumbers(health))
    
    -- Get power values
    local power = UnitPower(unit)
    local maxPower = UnitPowerMax(unit)
    local powerType = UnitPowerType(unit)
    
    frame.powerBar:SetMinMaxValues(0, maxPower)
    frame.powerBar:SetValue(power)
    
    -- Color power bar by power type
    local powerColor = PowerBarColor[powerType]
    if powerColor then
        frame.powerBar:SetStatusBarColor(powerColor.r, powerColor.g, powerColor.b)
        frame.powerBar.bg:SetVertexColor(powerColor.r * 0.3, powerColor.g * 0.3, powerColor.b * 0.3)
    end
    
    -- Color by class if player
    local colored = false
    if UnitIsPlayer(unit) then
        local _, class = UnitClass(unit)
        if class and RAID_CLASS_COLORS[class] then
            local classColor = RAID_CLASS_COLORS[class]
            frame.healthBar:SetStatusBarColor(classColor.r, classColor.g, classColor.b)
            frame.healthBar:SetStatusBarDesaturated(false)
            frame.healthBar.bg:SetVertexColor(classColor.r * 0.3, classColor.g * 0.3, classColor.b * 0.3)
            colored = true
        end
    end
    
    -- If not colored by class, use reaction or default green
    if not colored then
        local reaction = UnitReaction(unit, "player")
        if reaction and reaction <= 3 then
            frame.healthBar:SetStatusBarColor(1, 0, 0)
            frame.healthBar.bg:SetVertexColor(0.3, 0, 0)
        elseif reaction and reaction >= 5 then
            frame.healthBar:SetStatusBarColor(0, 1, 0)
            frame.healthBar.bg:SetVertexColor(0, 0.3, 0)
        else
            frame.healthBar:SetStatusBarColor(1, 1, 0)
            frame.healthBar.bg:SetVertexColor(0.3, 0.3, 0)
        end
    end
end

-- Update party buffs
function UpdatePartyBuffs(partyNum)
    local frame = partyFrames[partyNum]
    if not frame or not frame.buffs then return end
    
    local unit = "party"..partyNum
    
    -- Hide all buffs if no unit
    if not UnitExists(unit) then
        for i = 1, 15 do
            frame.buffs[i]:Hide()
        end
        return
    end
    
    -- Use PLAYER filter if option enabled (like raid frames)
    local filter = JarUnitFramesDB.partyShowOnlyMyBuffs and "HELPFUL|PLAYER" or "HELPFUL"
    local auras = C_UnitAuras.GetUnitAuras(unit, filter, 15) or {}
    local buffIndex = 1
    
    for _, auraData in ipairs(auras) do
        if buffIndex > 15 then break end
        
        local buff = frame.buffs[buffIndex]
        buff.icon:SetTexture(auraData.icon)
        buff.auraInstanceID = auraData.auraInstanceID
        
        -- Show stack count (SetText handles secret values safely)
        buff.count:SetText(C_UnitAuras.GetAuraApplicationDisplayCount(unit, auraData.auraInstanceID, 2, 99))
        
        -- Update cooldown
        local duration = auraData.duration
        local expirationTime = auraData.expirationTime
        
        if duration and C_StringUtil.TruncateWhenZero(duration) then
            buff.cooldown:SetCooldown(duration, expirationTime)
            buff.cooldown:SetCooldownFromExpirationTime(expirationTime, duration)
        else
            buff.cooldown:Clear()
        end
        
        buff:Show()
        buffIndex = buffIndex + 1
    end
    
    -- Hide unused buff frames
    for i = buffIndex, 15 do
        frame.buffs[i]:Hide()
    end
end

-- Update party debuffs
function UpdatePartyDebuffs(partyNum)
    local frame = partyFrames[partyNum]
    if not frame or not frame.debuffs then return end
    
    local unit = "party"..partyNum
    
    -- Hide all debuffs if no unit
    if not UnitExists(unit) then
        for i = 1, 15 do
            frame.debuffs[i]:Hide()
        end
        return
    end
    
    local auras = C_UnitAuras.GetUnitAuras(unit, "HARMFUL", 15) or {}
    local debuffIndex = 1
    
    for _, auraData in ipairs(auras) do
        if debuffIndex > 15 then break end
        
        local debuff = frame.debuffs[debuffIndex]
        debuff.icon:SetTexture(auraData.icon)
        debuff.auraInstanceID = auraData.auraInstanceID
        
        -- Show stack count (SetText handles secret values safely)
        debuff.count:SetText(C_UnitAuras.GetAuraApplicationDisplayCount(unit, auraData.auraInstanceID, 2, 99))
        
        -- Update cooldown
        local duration = auraData.duration
        local expirationTime = auraData.expirationTime
        
        if duration and C_StringUtil.TruncateWhenZero(duration) then
            debuff.cooldown:SetCooldown(duration, expirationTime)
            debuff.cooldown:SetCooldownFromExpirationTime(expirationTime, duration)
        else
            debuff.cooldown:Clear()
        end
        
        debuff:Show()
        debuffIndex = debuffIndex + 1
    end
    
    -- Hide unused debuff frames
    for i = debuffIndex, 15 do
        frame.debuffs[i]:Hide()
    end
end

-- Create config window
local function CreateConfigFrame()
    local frame = CreateFrame("Frame", "JUF_ConfigFrame", UIParent, "BasicFrameTemplateWithInset")
    frame:SetSize(600, 700)
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
            print("|cff00ff00Jar's Unit Frames|r Frames unlocked - Shift+drag party frames to reposition")
            -- Show unlock borders on party frames
            for i = 1, 4 do
                if partyFrames[i] and partyFrames[i].unlockBorder then
                    partyFrames[i].unlockBorder:Show()
                end
            end
        else
            print("|cff00ff00Jar's Unit Frames|r Frames locked")
            -- Hide unlock borders on party frames
            for i = 1, 4 do
                if partyFrames[i] and partyFrames[i].unlockBorder then
                    partyFrames[i].unlockBorder:Hide()
                end
            end
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
    scaleSlider:SetPoint("TOPLEFT", 20, -210)
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
        if focusFrame then
            focusFrame:SetScale(value)
        end
        if targetTargetFrame then
            targetTargetFrame:SetScale(value)
        end
        if petFrame then
            petFrame:SetScale(value)
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
    mirrorCheck:SetPoint("TOPLEFT", showLevelCheck, "BOTTOMLEFT", 0, -10)
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
    
    -- Show Focus Frame checkbox (top right)
    local showFocusCheck = CreateFrame("CheckButton", nil, frame, "UICheckButtonTemplate")
    showFocusCheck:SetPoint("TOPRIGHT", hideTargetPermBuffsCheck, "BOTTOMRIGHT", 0, -10)
    showFocusCheck.text = showFocusCheck:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    showFocusCheck.text:SetPoint("RIGHT", showFocusCheck, "LEFT", -5, 0)
    showFocusCheck.text:SetText("Show Focus Frame")
    showFocusCheck:SetChecked(JarUnitFramesDB.showFocusFrame)
    showFocusCheck:SetScript("OnClick", function(self)
        JarUnitFramesDB.showFocusFrame = self:GetChecked()
        if JarUnitFramesDB.showFocusFrame then
            if not focusFrame then
                focusFrame = CreateFocusFrame()
                UpdateFocusFrame()
                UpdateFocusBuffs()
                UpdateFocusDebuffs()
            else
                focusFrame:Show()
            end
        else
            if focusFrame then
                focusFrame:Hide()
            end
        end
    end)
    frame.showFocusCheck = showFocusCheck
    
    -- Focus Show Buffs checkbox (indented, right side)
    local focusShowBuffsCheck = CreateFrame("CheckButton", nil, frame, "UICheckButtonTemplate")
    focusShowBuffsCheck:SetPoint("TOPRIGHT", showFocusCheck, "BOTTOMRIGHT", -20, -5)
    focusShowBuffsCheck.text = focusShowBuffsCheck:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    focusShowBuffsCheck.text:SetPoint("RIGHT", focusShowBuffsCheck, "LEFT", -5, 0)
    focusShowBuffsCheck.text:SetText("Show Focus Buffs")
    focusShowBuffsCheck:SetChecked(JarUnitFramesDB.focusShowBuffs)
    focusShowBuffsCheck:SetScript("OnClick", function(self)
        JarUnitFramesDB.focusShowBuffs = self:GetChecked()
        if focusFrame and focusFrame.buffs then
            if JarUnitFramesDB.focusShowBuffs then
                UpdateFocusBuffs()
            else
                for i = 1, 40 do
                    focusFrame.buffs[i]:Hide()
                end
            end
        end
    end)
    frame.focusShowBuffsCheck = focusShowBuffsCheck
    
    -- Focus Show Debuffs checkbox (indented, right side)
    local focusShowDebuffsCheck = CreateFrame("CheckButton", nil, frame, "UICheckButtonTemplate")
    focusShowDebuffsCheck:SetPoint("TOPRIGHT", focusShowBuffsCheck, "BOTTOMRIGHT", 0, -5)
    focusShowDebuffsCheck.text = focusShowDebuffsCheck:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    focusShowDebuffsCheck.text:SetPoint("RIGHT", focusShowDebuffsCheck, "LEFT", -5, 0)
    focusShowDebuffsCheck.text:SetText("Show Focus Debuffs")
    focusShowDebuffsCheck:SetChecked(JarUnitFramesDB.focusShowDebuffs)
    focusShowDebuffsCheck:SetScript("OnClick", function(self)
        JarUnitFramesDB.focusShowDebuffs = self:GetChecked()
        if focusFrame and focusFrame.debuffs then
            if JarUnitFramesDB.focusShowDebuffs then
                UpdateFocusDebuffs()
            else
                for i = 1, 40 do
                    focusFrame.debuffs[i]:Hide()
                end
            end
        end
    end)
    frame.focusShowDebuffsCheck = focusShowDebuffsCheck
    
    -- Focus Width slider (right side)
    local focusWidthSlider = CreateFrame("Slider", nil, frame, "OptionsSliderTemplate")
    focusWidthSlider:SetPoint("TOPRIGHT", focusShowDebuffsCheck, "BOTTOMRIGHT", 20, -15)
    focusWidthSlider:SetMinMaxValues(150, 300)
    focusWidthSlider:SetValue(JarUnitFramesDB.focusWidth or 220)
    focusWidthSlider:SetValueStep(10)
    focusWidthSlider:SetObeyStepOnDrag(true)
    focusWidthSlider:SetWidth(200)
    focusWidthSlider.Text = focusWidthSlider:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    focusWidthSlider.Text:SetPoint("BOTTOM", focusWidthSlider, "TOP", 0, 5)
    focusWidthSlider.Text:SetText("Focus Width: " .. (JarUnitFramesDB.focusWidth or 220))
    focusWidthSlider:SetScript("OnValueChanged", function(self, value)
        value = math.floor(value / 10 + 0.5) * 10
        JarUnitFramesDB.focusWidth = value
        self.Text:SetText("Focus Width: " .. value)
        if focusFrame then
            focusFrame:SetWidth(value)
            focusFrame.healthBar:SetWidth(value)
            focusFrame.powerBar:SetWidth(value)
            if focusFrame.buffContainer then
                focusFrame.buffContainer:SetWidth(value)
            end
            if focusFrame.debuffContainer then
                focusFrame.debuffContainer:SetWidth(value)
            end
        end
    end)
    frame.focusWidthSlider = focusWidthSlider
    
    -- Show Target of Target Frame checkbox (right side)
    local showToTCheck = CreateFrame("CheckButton", nil, frame, "UICheckButtonTemplate")
    showToTCheck:SetPoint("TOPRIGHT", focusWidthSlider, "BOTTOMRIGHT", 0, -25)
    showToTCheck.text = showToTCheck:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    showToTCheck.text:SetPoint("RIGHT", showToTCheck, "LEFT", -5, 0)
    showToTCheck.text:SetText("Show Target of Target Frame")
    showToTCheck:SetChecked(JarUnitFramesDB.showTargetTargetFrame)
    showToTCheck:SetScript("OnClick", function(self)
        JarUnitFramesDB.showTargetTargetFrame = self:GetChecked()
        if JarUnitFramesDB.showTargetTargetFrame then
            if not targetTargetFrame then
                targetTargetFrame = CreateTargetTargetFrame()
                UpdateTargetTargetFrame()
                if JarUnitFramesDB.totShowBuffs then UpdateTargetTargetBuffs() end
                if JarUnitFramesDB.totShowDebuffs then UpdateTargetTargetDebuffs() end
            else
                -- Re-enable unit watch
                if not InCombatLockdown() then
                    RegisterUnitWatch(targetTargetFrame)
                end
                targetTargetFrame:Show()
            end
        else
            if targetTargetFrame then
                -- Unregister unit watch to prevent auto-show
                if not InCombatLockdown() then
                    UnregisterUnitWatch(targetTargetFrame)
                end
                targetTargetFrame:Hide()
            end
        end
    end)
    frame.showToTCheck = showToTCheck
    
    -- ToT Show Buffs checkbox (indented, right side)
    local totShowBuffsCheck = CreateFrame("CheckButton", nil, frame, "UICheckButtonTemplate")
    totShowBuffsCheck:SetPoint("TOPRIGHT", showToTCheck, "BOTTOMRIGHT", -20, -5)
    totShowBuffsCheck.text = totShowBuffsCheck:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    totShowBuffsCheck.text:SetPoint("RIGHT", totShowBuffsCheck, "LEFT", -5, 0)
    totShowBuffsCheck.text:SetText("Show ToT Buffs")
    totShowBuffsCheck:SetChecked(JarUnitFramesDB.totShowBuffs)
    totShowBuffsCheck:SetScript("OnClick", function(self)
        JarUnitFramesDB.totShowBuffs = self:GetChecked()
        if targetTargetFrame and targetTargetFrame.buffs then
            if JarUnitFramesDB.totShowBuffs then
                UpdateTargetTargetBuffs()
            else
                for i = 1, 20 do
                    targetTargetFrame.buffs[i]:Hide()
                end
            end
        end
    end)
    frame.totShowBuffsCheck = totShowBuffsCheck
    
    -- ToT Show Debuffs checkbox (indented, right side)
    local totShowDebuffsCheck = CreateFrame("CheckButton", nil, frame, "UICheckButtonTemplate")
    totShowDebuffsCheck:SetPoint("TOPRIGHT", totShowBuffsCheck, "BOTTOMRIGHT", 0, -5)
    totShowDebuffsCheck.text = totShowDebuffsCheck:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    totShowDebuffsCheck.text:SetPoint("RIGHT", totShowDebuffsCheck, "LEFT", -5, 0)
    totShowDebuffsCheck.text:SetText("Show ToT Debuffs")
    totShowDebuffsCheck:SetChecked(JarUnitFramesDB.totShowDebuffs)
    totShowDebuffsCheck:SetScript("OnClick", function(self)
        JarUnitFramesDB.totShowDebuffs = self:GetChecked()
        if targetTargetFrame and targetTargetFrame.debuffs then
            if JarUnitFramesDB.totShowDebuffs then
                UpdateTargetTargetDebuffs()
            else
                for i = 1, 20 do
                    targetTargetFrame.debuffs[i]:Hide()
                end
            end
        end
    end)
    frame.totShowDebuffsCheck = totShowDebuffsCheck
    
    -- ToT Width slider (right side)
    local totWidthSlider = CreateFrame("Slider", nil, frame, "OptionsSliderTemplate")
    totWidthSlider:SetPoint("TOPRIGHT", totShowDebuffsCheck, "BOTTOMRIGHT", 20, -15)
    totWidthSlider:SetMinMaxValues(100, 250)
    totWidthSlider:SetValue(JarUnitFramesDB.totWidth or 150)
    totWidthSlider:SetValueStep(10)
    totWidthSlider:SetObeyStepOnDrag(true)
    totWidthSlider:SetWidth(200)
    totWidthSlider.Text = totWidthSlider:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    totWidthSlider.Text:SetPoint("BOTTOM", totWidthSlider, "TOP", 0, 5)
    totWidthSlider.Text:SetText("ToT Width: " .. (JarUnitFramesDB.totWidth or 150))
    totWidthSlider:SetScript("OnValueChanged", function(self, value)
        value = math.floor(value / 10 + 0.5) * 10
        JarUnitFramesDB.totWidth = value
        self.Text:SetText("ToT Width: " .. value)
        if targetTargetFrame then
            targetTargetFrame:SetWidth(value)
            targetTargetFrame.healthBar:SetWidth(value)
            targetTargetFrame.powerBar:SetWidth(value)
            if targetTargetFrame.buffContainer then
                targetTargetFrame.buffContainer:SetWidth(value)
            end
            if targetTargetFrame.debuffContainer then
                targetTargetFrame.debuffContainer:SetWidth(value)
            end
        end
    end)
    frame.totWidthSlider = totWidthSlider
    
    -- Show Pet Frame checkbox (right side)
    local showPetCheck = CreateFrame("CheckButton", nil, frame, "UICheckButtonTemplate")
    showPetCheck:SetPoint("TOPRIGHT", totWidthSlider, "BOTTOMRIGHT", 0, -25)
    showPetCheck.text = showPetCheck:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    showPetCheck.text:SetPoint("RIGHT", showPetCheck, "LEFT", -5, 0)
    showPetCheck.text:SetText("Show Pet Frame")
    showPetCheck:SetChecked(JarUnitFramesDB.showPetFrame)
    showPetCheck:SetScript("OnClick", function(self)
        JarUnitFramesDB.showPetFrame = self:GetChecked()
        if JarUnitFramesDB.showPetFrame then
            if not petFrame then
                petFrame = CreatePetFrame()
                UpdatePetFrame()
                if JarUnitFramesDB.petShowBuffs then UpdatePetBuffs() end
                if JarUnitFramesDB.petShowDebuffs then UpdatePetDebuffs() end
            else
                petFrame:Show()
            end
        else
            if petFrame then
                petFrame:Hide()
            end
        end
    end)
    frame.showPetCheck = showPetCheck
    
    -- Pet Show Buffs checkbox (indented, right side)
    local petShowBuffsCheck = CreateFrame("CheckButton", nil, frame, "UICheckButtonTemplate")
    petShowBuffsCheck:SetPoint("TOPRIGHT", showPetCheck, "BOTTOMRIGHT", -20, -5)
    petShowBuffsCheck.text = petShowBuffsCheck:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    petShowBuffsCheck.text:SetPoint("RIGHT", petShowBuffsCheck, "LEFT", -5, 0)
    petShowBuffsCheck.text:SetText("Show Pet Buffs")
    petShowBuffsCheck:SetChecked(JarUnitFramesDB.petShowBuffs)
    petShowBuffsCheck:SetScript("OnClick", function(self)
        JarUnitFramesDB.petShowBuffs = self:GetChecked()
        if petFrame and petFrame.buffs then
            if JarUnitFramesDB.petShowBuffs then
                UpdatePetBuffs()
            else
                for i = 1, 20 do
                    petFrame.buffs[i]:Hide()
                end
            end
        end
    end)
    frame.petShowBuffsCheck = petShowBuffsCheck
    
    -- Pet Show Debuffs checkbox (indented, right side)
    local petShowDebuffsCheck = CreateFrame("CheckButton", nil, frame, "UICheckButtonTemplate")
    petShowDebuffsCheck:SetPoint("TOPRIGHT", petShowBuffsCheck, "BOTTOMRIGHT", 0, -5)
    petShowDebuffsCheck.text = petShowDebuffsCheck:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    petShowDebuffsCheck.text:SetPoint("RIGHT", petShowDebuffsCheck, "LEFT", -5, 0)
    petShowDebuffsCheck.text:SetText("Show Pet Debuffs")
    petShowDebuffsCheck:SetChecked(JarUnitFramesDB.petShowDebuffs)
    petShowDebuffsCheck:SetScript("OnClick", function(self)
        JarUnitFramesDB.petShowDebuffs = self:GetChecked()
        if petFrame and petFrame.debuffs then
            if JarUnitFramesDB.petShowDebuffs then
                UpdatePetDebuffs()
            else
                for i = 1, 20 do
                    petFrame.debuffs[i]:Hide()
                end
            end
        end
    end)
    frame.petShowDebuffsCheck = petShowDebuffsCheck
    
    -- Pet Width slider (right side)
    local petWidthSlider = CreateFrame("Slider", nil, frame, "OptionsSliderTemplate")
    petWidthSlider:SetPoint("TOPRIGHT", petShowDebuffsCheck, "BOTTOMRIGHT", 20, -15)
    petWidthSlider:SetMinMaxValues(100, 250)
    petWidthSlider:SetValue(JarUnitFramesDB.petWidth or 150)
    petWidthSlider:SetValueStep(10)
    petWidthSlider:SetObeyStepOnDrag(true)
    petWidthSlider:SetWidth(200)
    petWidthSlider.Text = petWidthSlider:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    petWidthSlider.Text:SetPoint("BOTTOM", petWidthSlider, "TOP", 0, 5)
    petWidthSlider.Text:SetText("Pet Width: " .. (JarUnitFramesDB.petWidth or 150))
    petWidthSlider:SetScript("OnValueChanged", function(self, value)
        value = math.floor(value / 10 + 0.5) * 10
        JarUnitFramesDB.petWidth = value
        self.Text:SetText("Pet Width: " .. value)
        if petFrame then
            petFrame:SetWidth(value)
            petFrame.healthBar:SetWidth(value)
            petFrame.powerBar:SetWidth(value)
            if petFrame.buffContainer then
                petFrame.buffContainer:SetWidth(value)
            end
            if petFrame.debuffContainer then
                petFrame.debuffContainer:SetWidth(value)
            end
        end
    end)
    frame.petWidthSlider = petWidthSlider
    
    -- Background transparency slider
    local bgAlphaSlider = CreateFrame("Slider", nil, frame, "OptionsSliderTemplate")
    bgAlphaSlider:SetPoint("TOPLEFT", scaleSlider, "BOTTOMLEFT", 0, -50)
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
        -- Update drop shadow transparency on all frames
        if playerFrame then
            playerFrame.shadow:SetColorTexture(0, 0, 0, value)
        end
        if targetFrame then
            targetFrame.shadow:SetColorTexture(0, 0, 0, value)
        end
        if focusFrame then
            focusFrame.shadow:SetColorTexture(0, 0, 0, value)
        end
        if targetTargetFrame then
            targetTargetFrame.shadow:SetColorTexture(0, 0, 0, value)
        end
        if petFrame then
            petFrame.shadow:SetColorTexture(0, 0, 0, value)
        end
        -- Update party frames
        for i = 1, 4 do
            if partyFrames[i] and partyFrames[i].shadow then
                partyFrames[i].shadow:SetColorTexture(0, 0, 0, value)
            end
        end
    end)
    frame.bgAlphaSlider = bgAlphaSlider
    
    -- Texture selection dropdown
    local textureLabel = frame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    textureLabel:SetPoint("TOPLEFT", bgAlphaSlider, "BOTTOMLEFT", 0, -30)
    textureLabel:SetText("Bar Texture:")
    
    local textureDropdown = CreateFrame("Frame", "JUF_TextureDropdown", frame, "UIDropDownMenuTemplate")
    textureDropdown:SetPoint("TOPLEFT", textureLabel, "BOTTOMLEFT", -10, -5)
    
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
    frame.textureDropdown = textureDropdown
    
    -- Font selection dropdown
    local fontLabel = frame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    fontLabel:SetPoint("TOPLEFT", textureLabel, "BOTTOMLEFT", 0, -45)
    fontLabel:SetText("Font:")
    
    local fontDropdown = CreateFrame("Frame", "JUF_FontDropdown", frame, "UIDropDownMenuTemplate")
    fontDropdown:SetPoint("TOPLEFT", fontLabel, "BOTTOMLEFT", -10, -5)
    
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
    
    -- Party Frames Section (left side, under font)
    local partyHeader = frame:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    partyHeader:SetPoint("TOPLEFT", fontLabel, "BOTTOMLEFT", 0, -60)
    partyHeader:SetText("Party Frames")
    
    -- Show Party Frames checkbox
    local showPartyCheck = CreateFrame("CheckButton", nil, frame, "UICheckButtonTemplate")
    showPartyCheck:SetPoint("TOPLEFT", partyHeader, "BOTTOMLEFT", 0, -10)
    showPartyCheck.text = showPartyCheck:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    showPartyCheck.text:SetPoint("LEFT", showPartyCheck, "RIGHT", 5, 0)
    showPartyCheck.text:SetText("Show Party Frames")
    showPartyCheck:SetChecked(JarUnitFramesDB.showPartyFrames)
    showPartyCheck:SetScript("OnClick", function(self)
        JarUnitFramesDB.showPartyFrames = self:GetChecked()
        if JarUnitFramesDB.showPartyFrames then
            -- Hide Blizzard party frames
            if CompactRaidFrameManager then
                CompactRaidFrameManager:UnregisterAllEvents()
                CompactRaidFrameManager:Hide()
            end
            if CompactPartyFrame then
                CompactPartyFrame:UnregisterAllEvents()
                CompactPartyFrame:Hide()
            end
            if CompactRaidFrameContainer then
                CompactRaidFrameContainer:UnregisterAllEvents()
                CompactRaidFrameContainer:Hide()
            end
            
            -- Create party frames if they don't exist
            if not partyFrames[1] then
                for i = 1, 4 do
                    partyFrames[i] = CreatePartyFrame(i)
                end
                RepositionPartyFrames()
                -- Do initial updates
                for i = 1, 4 do
                    UpdatePartyFrame(i)
                    UpdatePartyBuffs(i)
                    UpdatePartyDebuffs(i)
                end
            else
                -- Frames exist, just enable them by triggering updates
                for i = 1, 4 do
                    if partyFrames[i] and not InCombatLockdown() then
                        RegisterUnitWatch(partyFrames[i])
                        UpdatePartyFrame(i)
                        UpdatePartyBuffs(i)
                        UpdatePartyDebuffs(i)
                    end
                end
            end
            print("|cff00ff00Jar's Unit Frames|r Party frames enabled")
        else
            -- Unregister unit watch and hide custom party frames
            for i = 1, 4 do
                if partyFrames[i] then
                    if not InCombatLockdown() then
                        UnregisterUnitWatch(partyFrames[i])
                    end
                    partyFrames[i]:Hide()
                end
            end
            -- Re-enable Blizzard party frames
            if CompactRaidFrameManager then
                CompactRaidFrameManager_OnLoad(CompactRaidFrameManager)
                CompactRaidFrameManager:Show()
            end
            if CompactPartyFrame then
                CompactPartyFrame:Show()
            end
            if CompactRaidFrameContainer then
                CompactRaidFrameContainer:Show()
            end
            print("|cff00ff00Jar's Unit Frames|r Party frames disabled, Blizzard frames restored")
        end
    end)
    frame.showPartyCheck = showPartyCheck
    
    -- Show Only My Buffs checkbox
    local partyOnlyMyBuffsCheck = CreateFrame("CheckButton", nil, frame, "UICheckButtonTemplate")
    partyOnlyMyBuffsCheck:SetPoint("TOPLEFT", showPartyCheck, "BOTTOMLEFT", 0, -10)
    partyOnlyMyBuffsCheck.text = partyOnlyMyBuffsCheck:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    partyOnlyMyBuffsCheck.text:SetPoint("LEFT", partyOnlyMyBuffsCheck, "RIGHT", 5, 0)
    partyOnlyMyBuffsCheck.text:SetText("Show Only My Buffs")
    partyOnlyMyBuffsCheck:SetChecked(JarUnitFramesDB.partyShowOnlyMyBuffs)
    partyOnlyMyBuffsCheck:SetScript("OnClick", function(self)
        JarUnitFramesDB.partyShowOnlyMyBuffs = self:GetChecked()
        -- Update all party frames to reflect the change
        if JarUnitFramesDB.showPartyFrames then
            for i = 1, 4 do
                UpdatePartyBuffs(i)
            end
        end
    end)
    frame.partyOnlyMyBuffsCheck = partyOnlyMyBuffsCheck
    
    -- Party Width slider
    local partyWidthSlider = CreateFrame("Slider", nil, frame, "OptionsSliderTemplate")
    partyWidthSlider:SetPoint("TOPLEFT", partyOnlyMyBuffsCheck, "BOTTOMLEFT", 0, -20)
    partyWidthSlider:SetMinMaxValues(100, 250)
    partyWidthSlider:SetValue(JarUnitFramesDB.partyWidth or 150)
    partyWidthSlider:SetValueStep(10)
    partyWidthSlider:SetObeyStepOnDrag(true)
    partyWidthSlider:SetWidth(200)
    partyWidthSlider.Text = partyWidthSlider:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    partyWidthSlider.Text:SetPoint("BOTTOM", partyWidthSlider, "TOP", 0, 5)
    partyWidthSlider.Text:SetText("Party Width: " .. (JarUnitFramesDB.partyWidth or 150))
    partyWidthSlider:SetScript("OnValueChanged", function(self, value)
        value = math.floor(value / 10 + 0.5) * 10
        JarUnitFramesDB.partyWidth = value
        self.Text:SetText("Party Width: " .. value)
        RepositionPartyFrames()
    end)
    frame.partyWidthSlider = partyWidthSlider
    
    -- Party Padding slider
    local partyPaddingSlider = CreateFrame("Slider", nil, frame, "OptionsSliderTemplate")
    partyPaddingSlider:SetPoint("TOPLEFT", partyWidthSlider, "BOTTOMLEFT", 0, -50)
    partyPaddingSlider:SetMinMaxValues(0, 20)
    partyPaddingSlider:SetValue(JarUnitFramesDB.partyPadding or 5)
    partyPaddingSlider:SetValueStep(1)
    partyPaddingSlider:SetObeyStepOnDrag(true)
    partyPaddingSlider:SetWidth(200)
    partyPaddingSlider.Text = partyPaddingSlider:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    partyPaddingSlider.Text:SetPoint("BOTTOM", partyPaddingSlider, "TOP", 0, 5)
    partyPaddingSlider.Text:SetText("Party Padding: " .. (JarUnitFramesDB.partyPadding or 5))
    partyPaddingSlider:SetScript("OnValueChanged", function(self, value)
        value = math.floor(value + 0.5)
        JarUnitFramesDB.partyPadding = value
        self.Text:SetText("Party Padding: " .. value)
        RepositionPartyFrames()
    end)
    frame.partyPaddingSlider = partyPaddingSlider
    
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
eventFrame:RegisterEvent("GROUP_ROSTER_UPDATE")

-- Hide Blizzard party frames (called on various events to keep them hidden)
local function HideBlizzardPartyFrames()
    if not JarUnitFramesDB.showPartyFrames then
        return  -- Only hide if we're using custom party frames
    end
    
    if CompactRaidFrameManager then
        CompactRaidFrameManager:UnregisterAllEvents()
        CompactRaidFrameManager:Hide()
    end
    
    if CompactPartyFrame then
        CompactPartyFrame:UnregisterAllEvents()
        CompactPartyFrame:Hide()
    end
    
    if CompactRaidFrameContainer then
        CompactRaidFrameContainer:UnregisterAllEvents()
        CompactRaidFrameContainer:Hide()
    end
end

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
        
        FocusFrame:Hide()
        FocusFrame:UnregisterAllEvents()
        FocusFrame.Show = function() end  -- Prevent it from showing again
        
        PetFrame:Hide()
        PetFrame:UnregisterAllEvents()
        PetFrame.Show = function() end  -- Prevent it from showing again
        
        -- Always hide Blizzard party frames and prevent them from showing
        if CompactRaidFrameManager then
            CompactRaidFrameManager:UnregisterAllEvents()
            CompactRaidFrameManager:Hide()
            CompactRaidFrameManager:SetParent(nil)
            CompactRaidFrameManager.Show = function() end
        end
        
        if CompactPartyFrame then
            CompactPartyFrame:UnregisterAllEvents()
            CompactPartyFrame:Hide()
            CompactPartyFrame:SetParent(nil)
            CompactPartyFrame.Show = function() end
        end
        
        if CompactRaidFrameContainer then
            CompactRaidFrameContainer:UnregisterAllEvents()
            CompactRaidFrameContainer:Hide()
            CompactRaidFrameContainer:SetParent(nil)
            CompactRaidFrameContainer.Show = function() end
        end
        
        -- Create frames
        playerFrame = CreatePlayerFrame()
        targetFrame = CreateTargetFrame()
        if JarUnitFramesDB.showFocusFrame then
            focusFrame = CreateFocusFrame()
        end
        if JarUnitFramesDB.showTargetTargetFrame then
            targetTargetFrame = CreateTargetTargetFrame()
        end
        if JarUnitFramesDB.showPetFrame then
            petFrame = CreatePetFrame()
        end
        
        -- Create party frames
        if JarUnitFramesDB.showPartyFrames then
            for i = 1, 4 do
                partyFrames[i] = CreatePartyFrame(i)
            end
            -- Position party frames vertically
            RepositionPartyFrames()
        end
        
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
        UpdatePlayerDebuffs()
        UpdateTargetFrame()
        UpdateTargetBuffs()
        UpdateTargetDebuffs()
        if focusFrame then
            UpdateFocusFrame()
            UpdateFocusBuffs()
            UpdateFocusDebuffs()
        end
        if targetTargetFrame then
            UpdateTargetTargetFrame()
            if JarUnitFramesDB.totShowBuffs then
                UpdateTargetTargetBuffs()
            end
            if JarUnitFramesDB.totShowDebuffs then
                UpdateTargetTargetDebuffs()
            end
        end
        if petFrame then
            UpdatePetFrame()
            if JarUnitFramesDB.petShowBuffs then
                UpdatePetBuffs()
            end
            if JarUnitFramesDB.petShowDebuffs then
                UpdatePetDebuffs()
            end
        end
        
        -- Update party frames
        if JarUnitFramesDB.showPartyFrames then
            for i = 1, 4 do
                UpdatePartyFrame(i)
                UpdatePartyBuffs(i)
                UpdatePartyDebuffs(i)
            end
        end
    
    elseif event == "PLAYER_ENTERING_WORLD" then
        -- Hide Blizzard party frames (may re-show on zone change)
        if JarUnitFramesDB.showPartyFrames then
            HideBlizzardPartyFrames()
        end
        
        -- Initial full update
        UpdatePlayerFrame()
        UpdatePlayerBuffs()
        UpdatePlayerDebuffs()
        UpdateTargetFrame()
        UpdateTargetBuffs()
        UpdateTargetDebuffs()
        if focusFrame then
            UpdateFocusFrame()
            UpdateFocusBuffs()
            UpdateFocusDebuffs()
        end
        if targetTargetFrame then
            UpdateTargetTargetFrame()
            if JarUnitFramesDB.totShowBuffs then
                UpdateTargetTargetBuffs()
            end
            if JarUnitFramesDB.totShowDebuffs then
                UpdateTargetTargetDebuffs()
            end
        end
        if petFrame then
            UpdatePetFrame()
            if JarUnitFramesDB.petShowBuffs then
                UpdatePetBuffs()
            end
            if JarUnitFramesDB.petShowDebuffs then
                UpdatePetDebuffs()
            end
        end
        
        -- Update party frames
        if JarUnitFramesDB.showPartyFrames then
            for i = 1, 4 do
                UpdatePartyFrame(i)
                UpdatePartyBuffs(i)
                UpdatePartyDebuffs(i)
            end
        end
        
    elseif event == "PLAYER_TARGET_CHANGED" then
        -- Target changed, but frame events will handle the details
        -- Just do an initial update
        UpdateTargetFrame()
        UpdateTargetBuffs()
        
    elseif event == "GROUP_ROSTER_UPDATE" then
        -- Party composition changed, update all party frames
        if JarUnitFramesDB.showPartyFrames then
            for i = 1, 4 do
                UpdatePartyFrame(i)
                UpdatePartyBuffs(i)
                UpdatePartyDebuffs(i)
            end
            -- Hide Blizzard frames (they may re-show when party changes)
            HideBlizzardPartyFrames()
        end
    end
end)

-- Slash commands
SLASH_JARUNITFRAMES1 = "/juf"
SLASH_JARUNITFRAMES2 = "/jarunitframes"
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
        if focusFrame then
            focusFrame:SetShown(JarUnitFramesDB.showFocusFrame)
        end
        if targetTargetFrame then
            targetTargetFrame:SetShown(JarUnitFramesDB.showTargetTargetFrame)
        end
        if petFrame then
            petFrame:SetShown(JarUnitFramesDB.showPetFrame)
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
            if focusFrame then
                focusFrame:SetScale(scale)
            end
            if targetTargetFrame then
                targetTargetFrame:SetScale(scale)
            end
            if petFrame then
                petFrame:SetScale(scale)
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
        if focusFrame then
            UpdateFocusFrame()
        end
        if targetTargetFrame then
            UpdateTargetTargetFrame()
        end
        if petFrame then
            UpdatePetFrame()
        end
        
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

