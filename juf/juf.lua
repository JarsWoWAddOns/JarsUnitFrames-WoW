-- Jar's Unit Frames for WoW 12.1.5
-- Demonstrates proper handling of secret values for unit frame data

-- Saved variables with defaults
JarUnitFramesDB = JarUnitFramesDB or {}

-- Modern UI Color Palette
local UI_PALETTE = {
    bg = {0.10, 0.10, 0.12, 0.95},
    header = {0.15, 0.15, 0.18, 1},
    accent = {1.0, 0.55, 0.0, 1},
    text = {0.95, 0.95, 0.95, 1},
    textDim = {0.70, 0.70, 0.70, 1},
    border = {0.20, 0.20, 0.22, 1},
}

local modernBackdrop = {
    bgFile = "Interface\\Buttons\\WHITE8X8",
    edgeFile = "Interface\\Buttons\\WHITE8X8",
    edgeSize = 1,
}

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
    enableAuraTooltips = true,   -- Show tooltip when hovering buff/debuff icons
    showTargetItemLevel = true,    -- Show target's item level (players only)
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
    playerDebuffFilter = "HARMFUL",
    targetDebuffFilter = "HARMFUL",
    focusDebuffFilter  = "HARMFUL|RAID",
    totDebuffFilter    = "HARMFUL|RAID",
    petDebuffFilter    = "HARMFUL",
    partyDebuffFilter  = "HARMFUL|RAID",
    playerMaxDebuffs = 40,
    targetMaxDebuffs = 40,
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

-- Item level display: request inspect on target change, show result when ready
local pendingGUID

local EQUIP_SLOTS = { 1, 2, 3, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15, 16, 17 }
local function CalcInspectItemLevel(unit)
    local total, count = 0, 0
    for _, slot in ipairs(EQUIP_SLOTS) do
        local link = GetInventoryItemLink(unit, slot)
        if link then
            -- local ilvl = GetDetailedItemLevelInfo(link)
            local ilvl = C_Item.GetDetailedItemLevelInfo(link)
            if ilvl and ilvl > 0 then
                total = total + ilvl
                count = count + 1
            end
        end
    end
    if count > 0 then return math.floor(total / count + 0.5) end
    return nil
end

local function ShowIlvl(ilvl)
    if not targetFrame or not targetFrame.ilvlText then return end
    if ilvl and ilvl > 0 and JarUnitFramesDB.showTargetItemLevel then
        targetFrame.ilvlText:SetText("ilvl " .. ilvl)
        targetFrame.ilvlText:Show()
    else
        targetFrame.ilvlText:Hide()
    end
end

local function RequestTargetItemLevel()
    pendingGUID = nil
    if not JarUnitFramesDB.showTargetItemLevel then return end
    if not UnitExists("target") or not UnitIsPlayer("target") then return end
    if not CanInspect("target") then return end
    if InspectFrame and InspectFrame:IsShown() then return end
    local guid = UnitGUID("target")
    if issecretvalue(guid) then return end
    pendingGUID = guid
    NotifyInspect("target")
end

-- still the same target we asked about?
local function IsPendingTarget()
    local guid = UnitGUID("target")
    return pendingGUID and not issecretvalue(guid) and guid == pendingGUID
end

local function TryReadInspectIlvl(attempt)
    if not IsPendingTarget() then
        pendingGUID = nil
        return
    end
    local ilvl = C_PaperDollInfo and C_PaperDollInfo.GetInspectItemLevel
        and C_PaperDollInfo.GetInspectItemLevel("target")
    if not ilvl or ilvl <= 0 then
        ilvl = CalcInspectItemLevel("target")
    end
    if ilvl and ilvl > 0 then
        pendingGUID = nil
        ShowIlvl(ilvl)
    elseif attempt < 4 then
        C_Timer.After(0.5 * attempt, function() TryReadInspectIlvl(attempt + 1) end)
    else
        pendingGUID = nil
    end
end

local function OnInspectReady(guid)
    if not pendingGUID or issecretvalue(guid) or guid ~= pendingGUID then return end
    TryReadInspectIlvl(1)
end

-- Debuff filter presets for config dropdowns
local DEBUFF_FILTER_PRESETS = {
    { label = "All Debuffs",       value = "HARMFUL" },
    { label = "Raid-Relevant",     value = "HARMFUL|RAID" },
    -- { label = "Not Self",          value = "HARMFUL|NOT_SELF" },
    { label = "Not Self",          value = "HARMFUL|!PLAYER" },
}

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

-- saved font can point at a font pack thats not installed, SetFont errors on that now
local DEFAULT_FONT = "Fonts\\FRIZQT__.TTF"
local fontProbe, checkedFont
local function GetSafeFont()
    local font = JarUnitFramesDB.font or DEFAULT_FONT
    if font == DEFAULT_FONT or font == checkedFont then return font end
    fontProbe = fontProbe or UIParent:CreateFontString(nil, "OVERLAY")
    if pcall(fontProbe.SetFont, fontProbe, font, 12, "") then
        checkedFont = font
        return font
    end
    print("|cff00ff00Jar's Unit Frames|r font not found, using default: " .. tostring(font))
    JarUnitFramesDB.font = nil
    return DEFAULT_FONT
end

local function UpdateFrameFonts(frame)
    local font = GetSafeFont()
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

-- combat queue for anything touching secure frames
local pending = {}
local function RunWhenSafe(key, fn)
    if InCombatLockdown() then pending[key] = fn else fn() end
end

local function FlushPending()
    for key, fn in pairs(pending) do
        pending[key] = nil
        fn()
    end
end

-- unit watch drives show/hide, we just turn it on or off
local function SetFrameEnabled(frame, enabled)
    if not frame then return end
    RunWhenSafe(frame, function()
        if enabled then
            RegisterUnitWatch(frame)
        else
            UnregisterUnitWatch(frame)
            frame:Hide()
        end
    end)
end

local UNIT_EVENTS = { "UNIT_HEALTH", "UNIT_MAXHEALTH", "UNIT_POWER_UPDATE", "UNIT_MAXPOWER", "UNIT_NAME_UPDATE", "UNIT_LEVEL" }
local function RegisterUnitEvents(frame, unit)
    for _, event in ipairs(UNIT_EVENTS) do
        frame:RegisterUnitEvent(event, unit)
    end
end

-- class can be secret in 12.1, dont use it as a key then
local function GetUnitClassColor(unit)
    local _, class = UnitClass(unit)
    if issecretvalue(class) or not class then return end
    return RAID_CLASS_COLORS[class]
end

local function ForEachUnitFrame(fn)
    for _, f in pairs({ playerFrame, targetFrame, focusFrame, targetTargetFrame, petFrame }) do
        fn(f)
    end
    for i = 1, 4 do
        if partyFrames[i] then fn(partyFrames[i]) end
    end
end

local function ApplyFrameScale()
    RunWhenSafe("scale", function()
        for _, f in pairs({ playerFrame, targetFrame, focusFrame, targetTargetFrame, petFrame }) do
            f:SetScale(JarUnitFramesDB.frameScale)
        end
    end)
end

-- mirror around screen center, anchored to CENTER so it cant fly off screen
local function MirrorTargetPosition()
    if not playerFrame or not targetFrame then return end
    RunWhenSafe("mirror", function()
        local s = playerFrame:GetScale()
        local cx, cy = playerFrame:GetCenter()
        local ux, uy = UIParent:GetCenter()
        JarUnitFramesDB.targetPos = { point = "CENTER", x = -(cx - ux / s), y = cy - uy / s }
        RestoreFramePosition(targetFrame, JarUnitFramesDB.targetPos)
    end)
end

-- 12.1 aura containers, one per buff/debuff row
local auraContainersOK
local function CanUseAuraContainers()
    if auraContainersOK == nil then
        auraContainersOK = select(4, GetBuildInfo()) >= 120100
            and pcall(CreateFrame, "AuraContainer", nil, UIParent, "CustomAuraContainerTemplate") or false
        if not auraContainersOK then
            print("|cffff0000Jar's Unit Frames|r AuraContainer not available, buffs/debuffs are off")
        end
    end
    return auraContainersOK
end

-- style each AuraButton once, cant touch them later while auras are secret
local function NewAuraButtonInit(o)
    return function(btn)
        btn:SetSize(o.size, o.size)
        btn:SetTooltipAnchorPoint(o.tooltip or "ANCHOR_RIGHT")
        btn:EnableMouse(not o.isBuff or JarUnitFramesDB.enableAuraTooltips)

        local icon = btn:CreateTexture(nil, "ARTWORK")
        icon:SetAllPoints()
        btn:SetIcon(icon)

        if o.bordered then
            icon:SetTexCoord(0.07, 0.93, 0.07, 0.93)
            local border = btn:CreateTexture(nil, "OVERLAY")
            border:SetAllPoints()
            border:SetTexture("Interface\\Buttons\\UI-Debuff-Overlays")
            border:SetTexCoord(0.296875, 0.5703125, 0, 0.515625)
        end

        -- no cooldown spiral, same as before
        if o.stacks then
            local count = btn:CreateFontString(nil, "OVERLAY", "NumberFontNormal")
            count:SetPoint("BOTTOMRIGHT", 2, 0)
            btn:SetApplicationCount(count, {})
        end
    end
end

-- boss first = a "boss" group then everything else
local function CreateAuraRow(parent, o)
    if not CanUseAuraContainers() then return end

    local c = CreateFrame("AuraContainer", nil, parent, "CustomAuraContainerTemplate")
    c:SetPoint(o.point, o.relTo, o.relPoint, o.x, o.y)
    c:SetFlowLayoutAnchorPoint(o.point)
    c:SetFlowLayoutGrowthDirection(o.growX, o.growY)
    c:SetFlowLayoutMaximumLineSize(o.perRow * (o.size + 2))
    c.isBuff = o.isBuff
    c.groups = o.bossFirst and { "boss", "auras" } or { "auras" }

    local init = NewAuraButtonInit(o)
    for _, key in ipairs(c.groups) do
        local filters
        if key == "boss" then
            filters = { isBossAura = true }
        elseif o.bossFirst then
            filters = { isBossAura = false }
        elseif o.hidePermanent then
            filters = { maxDuration = math.huge }
        end
        c:AddAuraGroup(key, o.filter, {
            maxFrameCount = o.max,
            initializeFrame = init,
            candidateFilters = filters,
            sortMethod = AuraContainerSortMethod.AuraInstanceIDOnly,
            sortDirection = AuraContainerSortDirection.Normal,
            layout = { elementSpacing = 2, lineSpacing = 2 },
        })
    end

    c:SetUnit(o.unit)
    c:SetEnabled(o.enabled ~= false)
    return c
end

local function SetAuraRowFilter(c, filter)
    if not c then return end
    for _, key in ipairs(c.groups) do
        c:SetAuraGroupFilterString(key, filter)
    end
end

local function SetAuraRowMax(c, max)
    if not c then return end
    for _, key in ipairs(c.groups) do
        c:SetAuraGroupMaxFrameCount(key, max)
    end
end

local function SetAuraRowShown(c, shown)
    if c then c:SetEnabled(shown) end
end

local function RefreshAuras(frame)
    if not frame then return end
    if frame.buffRow then frame.buffRow:UpdateAllAuras() end
    if frame.debuffRow then frame.debuffRow:UpdateAllAuras() end
end

-- only works while auras arent secret, new buttons pick it up on creation anyway
local function ApplyAuraTooltipSetting(frame)
    local c = frame and frame.buffRow
    if not c or C_Secrets.ShouldAurasBeSecret() then return end
    for i = 1, c:GetAuraGroupFrameCount("auras") do
        c:GetAuraGroupFrame("auras", i):EnableMouse(JarUnitFramesDB.enableAuraTooltips)
    end
end

-- hide blizz frames the 12.1 way (like oUF), no reparenting or OnShow hooks
local function DisableBlizzardFrame(f)
    if not f then return end
    f:UnregisterAllEvents()
    f:SetRolesets("alwaysBlocked")
    local subs = {
        f.healthBar or f.healthbar or f.HealthBar or (f.HealthBarsContainer and f.HealthBarsContainer.healthBar),
        f.manabar or f.ManaBar,
        f.castBar or f.spellbar or f.CastingBarFrame,
        f.BuffFrame or f.AurasFrame,
        f.DebuffFrame,
        f.petFrame or f.PetFrame,
        f.totFrame,
    }
    for _, sub in pairs(subs) do
        sub:UnregisterAllEvents()
    end
end

local function HideBlizzardUnitFrames()
    RunWhenSafe("blizzUnits", function()
        for _, f in pairs({ PlayerFrame, TargetFrame, FocusFrame, PetFrame }) do
            DisableBlizzardFrame(f)
        end
    end)
end

-- party only, and only when ours are on. raid container is left alone
local function HideBlizzardPartyFrames()
    if not JarUnitFramesDB.showPartyFrames then return end
    RunWhenSafe("blizzParty", function()
        if PartyFrame then
            DisableBlizzardFrame(PartyFrame)
            for f in PartyFrame.PartyMemberFramePool:EnumerateActive() do
                DisableBlizzardFrame(f)
            end
        end
        DisableBlizzardFrame(CompactPartyFrame)
        for i = 1, 5 do
            DisableBlizzardFrame(_G["CompactPartyFrameMember" .. i])
        end
    end)
end

-- Update frequency throttle (seconds)
local UPDATE_INTERVAL = 0.1
local timeSinceLastUpdate = 0

-- Forward declarations (locals, not globals)
local UpdatePlayerFrame, UpdateTargetFrame, UpdateFocusFrame, UpdateTargetTargetFrame, UpdatePetFrame, UpdatePartyFrame
local CreateFocusFrame, CreateTargetTargetFrame, CreatePetFrame, CreatePartyFrame, RepositionPartyFrames, SetupFrames

-- Create a custom player frame
local function CreatePlayerFrame()
    -- Get font settings early so they can be used throughout frame creation
    local font = GetSafeFont()
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
    
    -- per unit events, auras are the container's job now
    RegisterUnitEvents(frame, "player")
    frame:SetScript("OnEvent", function() UpdatePlayerFrame() end)
    
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
            if JarUnitFramesDB.mirrorTargetPosition then
                MirrorTargetPosition()
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
    local classColor = GetUnitClassColor("player")
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
    frame.healthText:SetJustifyH("RIGHT")
    frame.healthText:SetText("100")
    
    -- Power bar
    frame.powerBar = CreateFrame("StatusBar", nil, frame)
    frame.powerBar:SetSize(220, 8)
    frame.powerBar:SetPoint("TOP", 0, -22)
    frame.powerBar:EnableMouse(true)
    frame.powerBar:SetStatusBarTexture(texture)
    frame.powerBar:SetStatusBarColor(0, 0.4, 1)  -- Blue
    frame.powerBar:SetMinMaxValues(0, 100)
    frame.powerBar:SetValue(100)
    frame.powerBar:SetScript("OnEnter", function(self)
        if not GameTooltip:IsForbidden() then
            GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
            local power = UnitPower("player")
            local maxPower = UnitPowerMax("player")
            local powerType = UnitPowerType("player")
            local powerName = _G["POWER_TYPE_" .. (powerType or 0)] or "Power"
            GameTooltip:SetText(powerName, 1, 1, 1)
            GameTooltip:AddLine(BreakUpLargeNumbers(power) .. " / " .. BreakUpLargeNumbers(maxPower), 1, 1, 1)
            GameTooltip:Show()
        end
    end)
    frame.powerBar:SetScript("OnLeave", function()
        if not GameTooltip:IsForbidden() then
            GameTooltip:Hide()
        end
    end)
    
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
    frame.levelText = frame.healthBar:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    frame.levelText:SetPoint("LEFT", frame.healthBar, "LEFT", 5, 0)
    if JarUnitFramesDB.showLevel then
        frame.levelText:SetText(UnitLevel("player"))
    else
        frame.levelText:SetText("")
    end
    
    -- Name text (below the frame)
    frame.name = frame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    frame.name:SetPoint("TOPLEFT", frame.powerBar, "BOTTOMLEFT", 0, -5)
    frame.name:SetJustifyH("LEFT")
    frame.name:SetText("Player")
    
    -- Buffs above, debuffs below
    frame.buffRow = CreateAuraRow(frame, {
        unit = "player", filter = "HELPFUL", isBuff = true, max = 40,
        hidePermanent = JarUnitFramesDB.hidePlayerPermanentBuffs,
        size = 20, perRow = 10, bordered = true, stacks = true,
        point = "BOTTOMLEFT", relTo = frame.healthBar, relPoint = "TOPLEFT", x = 0, y = 2, growX = 1, growY = 1,
    })
    frame.debuffRow = CreateAuraRow(frame, {
        unit = "player", filter = JarUnitFramesDB.playerDebuffFilter or "HARMFUL", bossFirst = true,
        max = JarUnitFramesDB.playerMaxDebuffs or 40,
        size = 20, perRow = 10, bordered = true, stacks = true,
        point = "TOPLEFT", relTo = frame.healthBar, relPoint = "BOTTOMLEFT", x = 0, y = -35, growX = 1, growY = -1,
    })

    UpdateFrameFonts(frame)
    
    return frame
end

-- Create a custom target frame
local function CreateTargetFrame()
    -- Get font settings early so they can be used throughout frame creation
    local font = GetSafeFont()
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
    RegisterUnitEvents(frame, "target")
    frame:RegisterEvent("PLAYER_TARGET_CHANGED")
    frame:RegisterEvent("INSPECT_READY")

    frame:SetScript("OnEvent", function(self, event, arg1)
        if event == "INSPECT_READY" then
            OnInspectReady(arg1)  -- arg1 is the GUID here
        elseif event == "PLAYER_TARGET_CHANGED" then
            ShowIlvl(nil)
            UpdateTargetFrame()
            RefreshAuras(self)
            RequestTargetItemLevel()
        else
            UpdateTargetFrame()
        end
    end)
    
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
    frame.healthText = frame.healthBar:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    frame.healthText:SetPoint("LEFT", frame.healthBar, "LEFT", 5, 0)
    frame.healthText:SetJustifyH("LEFT")
    frame.healthText:SetText("0")
    
    -- Level text (optional)
    frame.levelText = frame.healthBar:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    frame.levelText:SetPoint("RIGHT", frame.healthBar, "RIGHT", -5, 0)
    frame.levelText:SetText("")
    
    -- Power bar
    frame.powerBar = CreateFrame("StatusBar", nil, frame)
    frame.powerBar:SetSize(220, 8)
    frame.powerBar:SetPoint("TOP", 0, -22)
    frame.powerBar:EnableMouse(true)
    frame.powerBar:SetStatusBarTexture(texture)
    frame.powerBar:SetStatusBarColor(0, 0.4, 1)
    frame.powerBar:SetMinMaxValues(0, 100)
    frame.powerBar:SetValue(0)
    frame.powerBar:SetReverseFill(true)  -- Fill from right to left
    frame.powerBar:SetScript("OnEnter", function(self)
        if UnitExists("target") and not GameTooltip:IsForbidden() then
            GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
            local power = UnitPower("target")
            local maxPower = UnitPowerMax("target")
            local powerType = UnitPowerType("target")
            local powerName = _G["POWER_TYPE_" .. (powerType or 0)] or "Power"
            GameTooltip:SetText(powerName, 1, 1, 1)
            GameTooltip:AddLine(BreakUpLargeNumbers(power) .. " / " .. BreakUpLargeNumbers(maxPower), 1, 1, 1)
            GameTooltip:Show()
        end
    end)
    frame.powerBar:SetScript("OnLeave", function()
        if not GameTooltip:IsForbidden() then
            GameTooltip:Hide()
        end
    end)
    
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
    frame.name:SetJustifyH("RIGHT")
    frame.name:SetText("No Target")

    -- Item level text (below the frame, left side)
    frame.ilvlText = frame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    frame.ilvlText:SetPoint("TOPLEFT", frame.powerBar, "BOTTOMLEFT", 0, -5)
    frame.ilvlText:SetJustifyH("LEFT")
    frame.ilvlText:SetTextColor(0.6, 0.8, 1.0)
    frame.ilvlText:Hide()
    
    -- Buffs above, debuffs below, both growing right to left
    frame.buffRow = CreateAuraRow(frame, {
        unit = "target", filter = "HELPFUL", isBuff = true, max = 40,
        hidePermanent = JarUnitFramesDB.hideTargetPermanentBuffs,
        size = 20, perRow = 10, bordered = true, stacks = true, tooltip = "ANCHOR_LEFT",
        point = "BOTTOMRIGHT", relTo = frame.healthBar, relPoint = "TOPRIGHT", x = 0, y = 2, growX = -1, growY = 1,
    })
    frame.debuffRow = CreateAuraRow(frame, {
        unit = "target", filter = JarUnitFramesDB.targetDebuffFilter or "HARMFUL", bossFirst = true,
        max = JarUnitFramesDB.targetMaxDebuffs or 40,
        size = 20, perRow = 10, bordered = true, stacks = true, tooltip = "ANCHOR_LEFT",
        point = "TOPRIGHT", relTo = frame.healthBar, relPoint = "BOTTOMRIGHT", x = 0, y = -35, growX = -1, growY = -1,
    })

    UpdateFrameFonts(frame)
    return frame
end

-- Create Focus Frame
function CreateFocusFrame()
    local frame = CreateFrame("Button", "JarUnitFrameFocus", UIParent, "SecureUnitButtonTemplate")
    frame:SetSize(220, 30)
    frame:SetAttribute("unit", "focus")
    frame:SetAttribute("*type1", "target")
    frame:SetAttribute("*type2", "togglemenu")
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
    RegisterUnitEvents(frame, "focus")
    frame:RegisterEvent("PLAYER_FOCUS_CHANGED")

    frame:SetScript("OnEvent", function(self, event)
        UpdateFocusFrame()
        if event == "PLAYER_FOCUS_CHANGED" then
            RefreshAuras(self)
        end
    end)
    
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
    
    local font = GetSafeFont()
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
    frame.healthText = frame.healthBar:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    frame.healthText:SetPoint("LEFT", frame.healthBar, "LEFT", 5, 0)
    frame.healthText:SetJustifyH("LEFT")
    frame.healthText:SetText("0")
    
    -- Level text
    frame.levelText = frame.healthBar:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    frame.levelText:SetPoint("RIGHT", frame.healthBar, "RIGHT", -5, 0)
    frame.levelText:SetText("")
    
    -- Power bar
    frame.powerBar = CreateFrame("StatusBar", nil, frame)
    frame.powerBar:SetSize(220, 8)
    frame.powerBar:SetPoint("TOP", 0, -22)
    frame.powerBar:EnableMouse(true)
    frame.powerBar:SetStatusBarTexture(texture)
    frame.powerBar:SetStatusBarColor(0, 0.4, 1)
    frame.powerBar:SetMinMaxValues(0, 100)
    frame.powerBar:SetValue(0)
    frame.powerBar:SetReverseFill(true)
    frame.powerBar:SetScript("OnEnter", function(self)
        if UnitExists("focus") and not GameTooltip:IsForbidden() then
            GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
            local power = UnitPower("focus")
            local maxPower = UnitPowerMax("focus")
            local powerType = UnitPowerType("focus")
            local powerName = _G["POWER_TYPE_" .. (powerType or 0)] or "Power"
            GameTooltip:SetText(powerName, 1, 1, 1)
            GameTooltip:AddLine(BreakUpLargeNumbers(power) .. " / " .. BreakUpLargeNumbers(maxPower), 1, 1, 1)
            GameTooltip:Show()
        end
    end)
    frame.powerBar:SetScript("OnLeave", function()
        if not GameTooltip:IsForbidden() then
            GameTooltip:Hide()
        end
    end)
    
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
    frame.name:SetJustifyH("RIGHT")
    frame.name:SetText("No Focus")
    
    -- Buffs above, debuffs below the name
    frame.buffRow = CreateAuraRow(frame, {
        unit = "focus", filter = "HELPFUL", isBuff = true, max = 40, enabled = JarUnitFramesDB.focusShowBuffs,
        size = 18, perRow = 10,
        point = "BOTTOMRIGHT", relTo = frame.healthBar, relPoint = "TOPRIGHT", x = 0, y = 2, growX = -1, growY = 1,
    })
    frame.debuffRow = CreateAuraRow(frame, {
        unit = "focus", filter = JarUnitFramesDB.focusDebuffFilter or "HARMFUL|RAID", bossFirst = true,
        max = 40, enabled = JarUnitFramesDB.focusShowDebuffs,
        size = 18, perRow = 10,
        point = "TOPRIGHT", relTo = frame.name, relPoint = "BOTTOMRIGHT", x = 0, y = -2, growX = -1, growY = -1,
    })

    UpdateFrameFonts(frame)
    
    return frame
end

-- Create Target of Target Frame
function CreateTargetTargetFrame()
    local frame = CreateFrame("Button", "JarUnitFrameTargetTarget", UIParent, "SecureUnitButtonTemplate")
    local width = JarUnitFramesDB.totWidth or 150
    frame:SetSize(width, 30)
    frame:SetAttribute("unit", "targettarget")
    frame:SetAttribute("*type1", "target")
    frame:SetAttribute("*type2", "togglemenu")
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
    
    -- targettarget has no unit events, so UNIT_TARGET on target + polling in OnUpdate
    frame:RegisterEvent("PLAYER_TARGET_CHANGED")
    frame:RegisterUnitEvent("UNIT_TARGET", "target")

    frame:SetScript("OnEvent", function(self)
        UpdateTargetTargetFrame()
        RefreshAuras(self)
    end)
    
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
    
    local font = GetSafeFont()
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
    frame.healthText = frame.healthBar:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    frame.healthText:SetPoint("LEFT", frame.healthBar, "LEFT", 5, 0)
    frame.healthText:SetJustifyH("LEFT")
    frame.healthText:SetText("0")
    
    -- Power bar
    frame.powerBar = CreateFrame("StatusBar", nil, frame)
    frame.powerBar:SetSize(width, 8)
    frame.powerBar:SetPoint("TOP", 0, -22)
    frame.powerBar:EnableMouse(true)
    frame.powerBar:SetStatusBarTexture(texture)
    frame.powerBar:SetStatusBarColor(0, 0.4, 1)
    frame.powerBar:SetMinMaxValues(0, 100)
    frame.powerBar:SetValue(0)
    frame.powerBar:SetReverseFill(false)
    frame.powerBar:SetScript("OnEnter", function(self)
        if UnitExists("targettarget") and not GameTooltip:IsForbidden() then
            GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
            local power = UnitPower("targettarget")
            local maxPower = UnitPowerMax("targettarget")
            local powerType = UnitPowerType("targettarget")
            local powerName = _G["POWER_TYPE_" .. (powerType or 0)] or "Power"
            GameTooltip:SetText(powerName, 1, 1, 1)
            GameTooltip:AddLine(BreakUpLargeNumbers(power) .. " / " .. BreakUpLargeNumbers(maxPower), 1, 1, 1)
            GameTooltip:Show()
        end
    end)
    frame.powerBar:SetScript("OnLeave", function()
        if not GameTooltip:IsForbidden() then
            GameTooltip:Hide()
        end
    end)
    
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
    frame.name = frame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    frame.name:SetPoint("TOPLEFT", frame.powerBar, "BOTTOMLEFT", 0, -5)
    frame.name:SetJustifyH("LEFT")
    frame.name:SetText("No ToT")
    
    -- Buffs above, debuffs below the name
    frame.buffRow = CreateAuraRow(frame, {
        unit = "targettarget", filter = "HELPFUL", isBuff = true, max = 20, enabled = JarUnitFramesDB.totShowBuffs,
        size = 18, perRow = 7,
        point = "BOTTOMLEFT", relTo = frame.healthBar, relPoint = "TOPLEFT", x = 0, y = 2, growX = 1, growY = 1,
    })
    frame.debuffRow = CreateAuraRow(frame, {
        unit = "targettarget", filter = JarUnitFramesDB.totDebuffFilter or "HARMFUL|RAID", bossFirst = true,
        max = 20, enabled = JarUnitFramesDB.totShowDebuffs,
        size = 18, perRow = 7,
        point = "TOPLEFT", relTo = frame.name, relPoint = "BOTTOMLEFT", x = 0, y = -2, growX = 1, growY = -1,
    })

    UpdateFrameFonts(frame)
    
    return frame
end

-- Create Pet Frame
function CreatePetFrame()
    local frame = CreateFrame("Button", "JarUnitFramePet", UIParent, "SecureUnitButtonTemplate")
    local width = JarUnitFramesDB.petWidth or 150
    frame:SetSize(width, 30)
    frame:SetAttribute("unit", "pet")
    frame:SetAttribute("*type1", "target")
    frame:SetAttribute("*type2", "togglemenu")
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
    RegisterUnitEvents(frame, "pet")
    frame:RegisterUnitEvent("UNIT_PET", "player")

    frame:SetScript("OnEvent", function(self, event)
        UpdatePetFrame()
        if event == "UNIT_PET" then
            RefreshAuras(self)
        end
    end)
    
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
    
    local font = GetSafeFont()
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
    frame.healthText = frame.healthBar:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    frame.healthText:SetPoint("LEFT", frame.healthBar, "LEFT", 5, 0)
    frame.healthText:SetJustifyH("LEFT")
    frame.healthText:SetText("0")
    
    -- Power bar
    frame.powerBar = CreateFrame("StatusBar", nil, frame)
    frame.powerBar:SetSize(width, 8)
    frame.powerBar:SetPoint("TOP", 0, -22)
    frame.powerBar:EnableMouse(true)
    frame.powerBar:SetStatusBarTexture(texture)
    frame.powerBar:SetStatusBarColor(0, 0.4, 1)
    frame.powerBar:SetMinMaxValues(0, 100)
    frame.powerBar:SetValue(0)
    frame.powerBar:SetReverseFill(false)
    frame.powerBar:SetScript("OnEnter", function(self)
        if UnitExists("pet") and not GameTooltip:IsForbidden() then
            GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
            local power = UnitPower("pet")
            local maxPower = UnitPowerMax("pet")
            local powerType = UnitPowerType("pet")
            local powerName = _G["POWER_TYPE_" .. (powerType or 0)] or "Power"
            GameTooltip:SetText(powerName, 1, 1, 1)
            GameTooltip:AddLine(BreakUpLargeNumbers(power) .. " / " .. BreakUpLargeNumbers(maxPower), 1, 1, 1)
            GameTooltip:Show()
        end
    end)
    frame.powerBar:SetScript("OnLeave", function()
        if not GameTooltip:IsForbidden() then
            GameTooltip:Hide()
        end
    end)
    
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
    frame.name = frame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    frame.name:SetPoint("TOPLEFT", frame.powerBar, "BOTTOMLEFT", 0, -5)
    frame.name:SetJustifyH("LEFT")
    frame.name:SetText("No Pet")
    
    -- Buffs above, debuffs below the name
    frame.buffRow = CreateAuraRow(frame, {
        unit = "pet", filter = "HELPFUL", isBuff = true, max = 20, enabled = JarUnitFramesDB.petShowBuffs,
        size = 18, perRow = 7,
        point = "BOTTOMLEFT", relTo = frame.healthBar, relPoint = "TOPLEFT", x = 0, y = 2, growX = 1, growY = 1,
    })
    frame.debuffRow = CreateAuraRow(frame, {
        unit = "pet", filter = JarUnitFramesDB.petDebuffFilter or "HARMFUL", bossFirst = true,
        max = 20, enabled = JarUnitFramesDB.petShowDebuffs,
        size = 18, perRow = 7,
        point = "TOPLEFT", relTo = frame.name, relPoint = "BOTTOMLEFT", x = 0, y = -2, growX = 1, growY = -1,
    })

    UpdateFrameFonts(frame)
    return frame
end

-- Create party frame (for party1-4)
function CreatePartyFrame(partyNum)
    local font = GetSafeFont()
    local fontSize = JarUnitFramesDB.fontSize or 12
    local texture = JarUnitFramesDB.texture or "Interface\\TargetingFrame\\UI-StatusBar"
    local width = JarUnitFramesDB.partyWidth or 150
    
    local frame = CreateFrame("Button", "JUF_PartyFrame"..partyNum, UIParent, "SecureUnitButtonTemplate")
    frame:SetSize(width, 45)
    frame:SetFrameStrata("MEDIUM")
    frame:SetFrameLevel(10)
    frame:SetAttribute("unit", "party"..partyNum)
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
    RegisterUnitEvents(frame, "party"..partyNum)
    frame:RegisterEvent("GROUP_ROSTER_UPDATE")

    frame:SetScript("OnEvent", function(self, event)
        UpdatePartyFrame(partyNum)
        if event == "GROUP_ROSTER_UPDATE" then
            RefreshAuras(self)
        end
    end)
    
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
    frame.healthText = frame.healthBar:CreateFontString(nil, "OVERLAY")
    frame.healthText:SetPoint("RIGHT", frame.healthBar, "RIGHT", -3, 0)
    frame.healthText:SetFont(font, fontSize, "OUTLINE")
    frame.healthText:SetTextColor(1, 1, 0)
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
    frame.name = frame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    frame.name:SetPoint("TOPLEFT", frame.powerBar, "BOTTOMLEFT", 0, -2)
    frame.name:SetJustifyH("LEFT")
    frame.name:SetText("Party "..partyNum)
    
    -- Buffs grow right off the power bar, debuffs grow left
    frame.buffRow = CreateAuraRow(frame, {
        unit = "party"..partyNum, filter = JarUnitFramesDB.partyShowOnlyMyBuffs and "HELPFUL|PLAYER" or "HELPFUL",
        isBuff = true, max = 15,
        size = 18, perRow = 5, bordered = true, stacks = true,
        point = "BOTTOMLEFT", relTo = frame.powerBar, relPoint = "BOTTOMRIGHT", x = 2, y = 0, growX = 1, growY = 1,
    })
    frame.debuffRow = CreateAuraRow(frame, {
        unit = "party"..partyNum, filter = JarUnitFramesDB.partyDebuffFilter or "HARMFUL|RAID", bossFirst = true,
        max = 15,
        size = 18, perRow = 5, bordered = true, stacks = true, tooltip = "ANCHOR_LEFT",
        point = "BOTTOMRIGHT", relTo = frame.powerBar, relPoint = "BOTTOMLEFT", x = -2, y = 0, growX = -1, growY = 1,
    })

    UpdateFrameFonts(frame)
    return frame
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
    
    -- unit watch does show/hide now
    if not UnitExists("target") then return end

    -- name can be secret, pass it straight thru
    targetFrame.name:SetText(UnitName("target"))
    
    -- Update level if enabled
    if JarUnitFramesDB.showLevel and UnitLevel("target") then
        targetFrame.levelText:SetText(UnitLevel("target"))
    else
        targetFrame.levelText:SetText("")
    end

    -- Update item level display (only show cached value on retarget; fresh request fires separately)
    if not (UnitExists("target") and UnitIsPlayer("target")) then
        ShowIlvl(nil)
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
        local classColor = GetUnitClassColor("target")
        if classColor then
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

-- Update focus frame
function UpdateFocusFrame()
    if not focusFrame then return end
    
    if not UnitExists("focus") then return end

    focusFrame.name:SetText(UnitName("focus"))
    
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
        local classColor = GetUnitClassColor("focus")
        if classColor then
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

-- Update target of target frame
function UpdateTargetTargetFrame()
    if not targetTargetFrame then return end
    
    -- unit watch handles visibility
    if not UnitExists("targettarget") then return end

    targetTargetFrame.name:SetText(UnitName("targettarget"))
    
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
        local classColor = GetUnitClassColor("targettarget")
        if classColor then
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

-- Update pet frame
function UpdatePetFrame()
    if not petFrame then return end
    
    if not UnitExists("pet") then return end

    petFrame.name:SetText(UnitName("pet"))
    
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
    frame.name:SetText(UnitName(unit))
    
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
        local classColor = GetUnitClassColor(unit)
        if classColor then
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

-- Create config window
local function CreateConfigFrame()
    local frame = CreateFrame("Frame", "JUF_ConfigFrame", UIParent, "BackdropTemplate")
    frame:SetSize(480, 680)
    frame:SetPoint("CENTER")
    frame:Hide()
    frame:SetMovable(true)
    frame:EnableMouse(true)
    frame:RegisterForDrag("LeftButton")
    frame:SetScript("OnDragStart", frame.StartMoving)
    frame:SetScript("OnDragStop", frame.StopMovingOrSizing)
    frame:SetBackdrop(modernBackdrop)
    frame:SetBackdropColor(unpack(UI_PALETTE.bg))
    frame:SetBackdropBorderColor(unpack(UI_PALETTE.border))

    -- Title bar
    local titleBar = frame:CreateTexture(nil, "OVERLAY")
    titleBar:SetPoint("TOPLEFT", 1, -1)
    titleBar:SetPoint("TOPRIGHT", -1, -1)
    titleBar:SetHeight(32)
    titleBar:SetColorTexture(unpack(UI_PALETTE.header))

    local titleAccent = frame:CreateTexture(nil, "OVERLAY")
    titleAccent:SetPoint("TOPLEFT", titleBar, "BOTTOMLEFT")
    titleAccent:SetPoint("TOPRIGHT", titleBar, "BOTTOMRIGHT")
    titleAccent:SetHeight(2)
    titleAccent:SetColorTexture(unpack(UI_PALETTE.accent))

    frame.title = frame:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    frame.title:SetPoint("TOP", titleBar, "TOP", 0, -8)
    frame.title:SetText("Jar's Unit Frames Config")
    frame.title:SetTextColor(unpack(UI_PALETTE.text))

    -- Close button
    local closeBtn = CreateFrame("Button", nil, frame)
    closeBtn:SetSize(20, 20)
    closeBtn:SetPoint("TOPRIGHT", -6, -6)
    local closeBtnBg = closeBtn:CreateTexture(nil, "BACKGROUND")
    closeBtnBg:SetAllPoints()
    closeBtnBg:SetColorTexture(0.05, 0.05, 0.05, 0.8)
    local closeBtnText = closeBtn:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    closeBtnText:SetPoint("CENTER", 0, 1)
    closeBtnText:SetText("\195\151")
    closeBtnText:SetTextColor(unpack(UI_PALETTE.textDim))
    closeBtn:SetScript("OnEnter", function() closeBtnText:SetTextColor(unpack(UI_PALETTE.accent)) end)
    closeBtn:SetScript("OnLeave", function() closeBtnText:SetTextColor(unpack(UI_PALETTE.textDim)) end)
    closeBtn:SetScript("OnClick", function() frame:Hide() end)

    -- Scroll frame
    local scrollFrame = CreateFrame("ScrollFrame", nil, frame, "UIPanelScrollFrameTemplate")
    scrollFrame:SetPoint("TOPLEFT", 12, -38)
    scrollFrame:SetPoint("BOTTOMRIGHT", -28, 8)

    local content = CreateFrame("Frame", nil, scrollFrame)
    content:SetWidth(420)
    scrollFrame:SetScrollChild(content)

    -- Layout state
    local W = 420
    local PAD = 10
    local yOff = 0

    local function NextY(gap) yOff = yOff - gap; return yOff end

    local function AddHeader(text)
        NextY(30)
        local hdr = content:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        hdr:SetPoint("TOPLEFT", PAD, yOff)
        hdr:SetTextColor(unpack(UI_PALETTE.accent))
        hdr:SetText(text:upper())
        local line = content:CreateTexture(nil, "ARTWORK")
        line:SetHeight(1)
        line:SetPoint("LEFT", hdr, "RIGHT", 8, 0)
        line:SetPoint("RIGHT", content, "RIGHT", -PAD, 0)
        line:SetColorTexture(UI_PALETTE.accent[1], UI_PALETTE.accent[2], UI_PALETTE.accent[3], 0.3)
        NextY(14)
    end

    local function AddCheck(text, getVal, setVal)
        NextY(28)
        local chk = CreateFrame("CheckButton", nil, content, "UICheckButtonTemplate")
        chk:SetPoint("TOPLEFT", PAD, yOff)
        chk.text = chk:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        chk.text:SetPoint("LEFT", chk, "RIGHT", 5, 0)
        chk.text:SetText(text)
        chk:SetChecked(getVal())
        chk:SetScript("OnClick", function(self) setVal(self:GetChecked()) end)
        return chk
    end

    local function AddSlider(label, minV, maxV, step, getVal, setVal, fmtFunc)
        NextY(42)
        local slider = CreateFrame("Slider", nil, content, "OptionsSliderTemplate")
        slider:SetPoint("TOPLEFT", PAD + 10, yOff)
        slider:SetWidth(W - PAD * 2 - 20)
        slider:SetMinMaxValues(minV, maxV)
        slider:SetValueStep(step)
        slider:SetObeyStepOnDrag(true)
        slider:SetValue(getVal())
        slider.Text = slider:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        slider.Text:SetPoint("BOTTOM", slider, "TOP", 0, 4)
        local display = fmtFunc and fmtFunc(getVal()) or tostring(getVal())
        slider.Text:SetText(label .. ": " .. display)
        slider:SetScript("OnValueChanged", function(self, value)
            local v = fmtFunc and fmtFunc(value) or value
            if type(v) == "string" then v = tonumber(v) end
            setVal(v)
            self.Text:SetText(label .. ": " .. tostring(v))
        end)
        NextY(18)
        return slider
    end

    local function AddDropdown(label, width, getText, setupMenu)
        NextY(28)
        local lbl = content:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        lbl:SetPoint("TOPLEFT", PAD, yOff)
        lbl:SetText(label)
        lbl:SetTextColor(unpack(UI_PALETTE.text))
        NextY(24)
        local dd = CreateFrame("DropdownButton", nil, content, "WowStyle1DropdownTemplate")
        dd:SetPoint("TOPLEFT", PAD + 10, yOff)
        dd:SetWidth(width)
        dd:SetDefaultText(getText())
        dd:SetupMenu(setupMenu)
        NextY(8)
        return dd
    end

    local function AddFilterCycler(label, dbKey, updateFunc)
        NextY(28)
        local lbl = content:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        lbl:SetPoint("TOPLEFT", PAD + 10, yOff)
        lbl:SetText(label)
        lbl:SetTextColor(unpack(UI_PALETTE.text))
        local btn = CreateFrame("Button", nil, content, "BackdropTemplate")
        btn:SetSize(160, 20)
        btn:SetPoint("LEFT", lbl, "RIGHT", 8, 0)
        btn:SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8X8", edgeFile = "Interface\\Buttons\\WHITE8X8", edgeSize = 1 })
        btn:SetBackdropColor(0.14, 0.14, 0.17, 1)
        btn:SetBackdropBorderColor(unpack(UI_PALETTE.border))
        btn.text = btn:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        btn.text:SetPoint("CENTER")
        local curVal = JarUnitFramesDB[dbKey] or "HARMFUL"
        for _, p in ipairs(DEBUFF_FILTER_PRESETS) do
            if p.value == curVal then btn.text:SetText(p.label); break end
        end
        if not btn.text:GetText() or btn.text:GetText() == "" then btn.text:SetText(curVal) end
        btn:SetScript("OnEnter", function(self) self:SetBackdropColor(0.20, 0.20, 0.24, 1) end)
        btn:SetScript("OnLeave", function(self) self:SetBackdropColor(0.14, 0.14, 0.17, 1) end)
        btn:SetScript("OnClick", function(self)
            local cur = JarUnitFramesDB[dbKey] or "HARMFUL"
            local ni = 1
            for idx, p in ipairs(DEBUFF_FILTER_PRESETS) do
                if p.value == cur then ni = (idx % #DEBUFF_FILTER_PRESETS) + 1; break end
            end
            local nxt = DEBUFF_FILTER_PRESETS[ni]
            JarUnitFramesDB[dbKey] = nxt.value
            self.text:SetText(nxt.label)
            if updateFunc then updateFunc() end
        end)
    end

    -- ═══════════════════════════════════════════════
    --  GENERAL
    -- ═══════════════════════════════════════════════
    AddHeader("General")
    AddCheck("Unlock Frames (drag to reposition)",
        function() return JarUnitFramesDB.unlocked end,
        function(v) JarUnitFramesDB.unlocked = v
            for i = 1, 4 do if partyFrames[i] and partyFrames[i].unlockBorder then partyFrames[i].unlockBorder:SetShown(v) end end
        end)
    AddCheck("Show Level",
        function() return JarUnitFramesDB.showLevel end,
        function(v) JarUnitFramesDB.showLevel = v; UpdatePlayerFrame(); UpdateTargetFrame() end)
    AddCheck("Mirror Target Frame Position",
        function() return JarUnitFramesDB.mirrorTargetPosition end,
        function(v) JarUnitFramesDB.mirrorTargetPosition = v
            if v then MirrorTargetPosition() end
        end)
    AddCheck("Show Buff/Debuff Tooltips on Hover",
        function() return JarUnitFramesDB.enableAuraTooltips end,
        function(v) JarUnitFramesDB.enableAuraTooltips = v; ForEachUnitFrame(ApplyAuraTooltipSetting) end)
    AddCheck("Show Target Item Level",
        function() return JarUnitFramesDB.showTargetItemLevel end,
        function(v) JarUnitFramesDB.showTargetItemLevel = v
            if targetFrame and targetFrame.ilvlText then
                if v then RequestTargetItemLevel(); UpdateTargetFrame()
                else targetFrame.ilvlText:Hide() end
            end
        end)
    AddSlider("Frame Scale", 0.5, 2.0, 0.1,
        function() return JarUnitFramesDB.frameScale end,
        function(v)
            v = math.floor(v * 10 + 0.5) / 10
            JarUnitFramesDB.frameScale = v
            ApplyFrameScale()
        end,
        function(v) return math.floor(v * 10 + 0.5) / 10 end)
    AddSlider("Background Opacity", 0, 100, 5,
        function() return math.floor(JarUnitFramesDB.bgAlpha * 100) end,
        function(v)
            local alpha = v / 100
            JarUnitFramesDB.bgAlpha = alpha
            local frames = { playerFrame, targetFrame, focusFrame, targetTargetFrame, petFrame }
            for _, f in ipairs(frames) do if f and f.shadow then f.shadow:SetColorTexture(0, 0, 0, alpha) end end
            for i = 1, 4 do if partyFrames[i] and partyFrames[i].shadow then partyFrames[i].shadow:SetColorTexture(0, 0, 0, alpha) end end
        end,
        function(v) return math.floor(v + 0.5) end)

    -- ═══════════════════════════════════════════════
    --  APPEARANCE
    -- ═══════════════════════════════════════════════
    AddHeader("Appearance")
    local function GetCurrentTextureName()
        for name, path in pairs(TEXTURES) do if path == JarUnitFramesDB.texture then return name end end
        return "Blizzard"
    end
    AddDropdown("Bar Texture", 220, GetCurrentTextureName, function(_, root)
        for name, path in pairs(TEXTURES) do
            root:CreateRadio(name,
                function() return JarUnitFramesDB.texture == path end,
                function()
                    JarUnitFramesDB.texture = path
                    ForEachUnitFrame(UpdateFrameTextures)
                end)
        end
    end)
    local function GetCurrentFontName()
        for name, path in pairs(FONTS) do if path == JarUnitFramesDB.font then return name end end
        return "Friz Quadrata (Default)"
    end
    AddDropdown("Font", 220, GetCurrentFontName, function(_, root)
        for name, path in pairs(FONTS) do
            root:CreateRadio(name,
                function() return JarUnitFramesDB.font == path end,
                function()
                    JarUnitFramesDB.font = path
                    ForEachUnitFrame(UpdateFrameFonts)
                end)
        end
    end)

    -- ═══════════════════════════════════════════════
    --  BUFFS & DEBUFFS
    -- ═══════════════════════════════════════════════
    AddHeader("Buffs & Debuffs")
    local filterSub = content:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    filterSub:SetPoint("TOPLEFT", PAD, yOff)
    filterSub:SetTextColor(unpack(UI_PALETTE.textDim))
    filterSub:SetText("Debuff Filters  (click to cycle)")
    NextY(8)
    AddFilterCycler("Player:", "playerDebuffFilter", function() SetAuraRowFilter(playerFrame and playerFrame.debuffRow, JarUnitFramesDB.playerDebuffFilter) end)
    AddFilterCycler("Target:", "targetDebuffFilter", function() SetAuraRowFilter(targetFrame and targetFrame.debuffRow, JarUnitFramesDB.targetDebuffFilter) end)
    AddFilterCycler("Focus:",  "focusDebuffFilter",  function() SetAuraRowFilter(focusFrame and focusFrame.debuffRow, JarUnitFramesDB.focusDebuffFilter) end)
    AddFilterCycler("Party:",  "partyDebuffFilter",  function()
        for i = 1, 4 do SetAuraRowFilter(partyFrames[i] and partyFrames[i].debuffRow, JarUnitFramesDB.partyDebuffFilter) end
    end)
    NextY(10)
    AddSlider("Player Max Debuffs", 5, 40, 1,
        function() return JarUnitFramesDB.playerMaxDebuffs or 40 end,
        function(v) JarUnitFramesDB.playerMaxDebuffs = v; SetAuraRowMax(playerFrame and playerFrame.debuffRow, v) end,
        function(v) return math.floor(v + 0.5) end)
    AddSlider("Target Max Debuffs", 5, 40, 1,
        function() return JarUnitFramesDB.targetMaxDebuffs or 40 end,
        function(v) JarUnitFramesDB.targetMaxDebuffs = v; SetAuraRowMax(targetFrame and targetFrame.debuffRow, v) end,
        function(v) return math.floor(v + 0.5) end)

    -- ═══════════════════════════════════════════════
    --  FOCUS FRAME
    -- ═══════════════════════════════════════════════
    AddHeader("Focus Frame")
    AddCheck("Show Focus Frame",
        function() return JarUnitFramesDB.showFocusFrame end,
        function(v) JarUnitFramesDB.showFocusFrame = v; SetupFrames() end)
    AddCheck("Show Focus Buffs",
        function() return JarUnitFramesDB.focusShowBuffs end,
        function(v) JarUnitFramesDB.focusShowBuffs = v; SetAuraRowShown(focusFrame and focusFrame.buffRow, v) end)
    AddCheck("Show Focus Debuffs",
        function() return JarUnitFramesDB.focusShowDebuffs end,
        function(v) JarUnitFramesDB.focusShowDebuffs = v; SetAuraRowShown(focusFrame and focusFrame.debuffRow, v) end)
    AddSlider("Focus Width", 150, 300, 10,
        function() return JarUnitFramesDB.focusWidth or 220 end,
        function(v) v = math.floor(v / 10 + 0.5) * 10; JarUnitFramesDB.focusWidth = v
            if focusFrame then
                RunWhenSafe("focusWidth", function() focusFrame:SetWidth(v); focusFrame.healthBar:SetWidth(v); focusFrame.powerBar:SetWidth(v) end)
            end
        end,
        function(v) return math.floor(v / 10 + 0.5) * 10 end)

    -- ═══════════════════════════════════════════════
    --  TARGET OF TARGET
    -- ═══════════════════════════════════════════════
    AddHeader("Target of Target")
    AddCheck("Show Target of Target Frame",
        function() return JarUnitFramesDB.showTargetTargetFrame end,
        function(v) JarUnitFramesDB.showTargetTargetFrame = v; SetupFrames() end)
    AddCheck("Show ToT Buffs",
        function() return JarUnitFramesDB.totShowBuffs end,
        function(v) JarUnitFramesDB.totShowBuffs = v; SetAuraRowShown(targetTargetFrame and targetTargetFrame.buffRow, v) end)
    AddCheck("Show ToT Debuffs",
        function() return JarUnitFramesDB.totShowDebuffs end,
        function(v) JarUnitFramesDB.totShowDebuffs = v; SetAuraRowShown(targetTargetFrame and targetTargetFrame.debuffRow, v) end)
    AddSlider("ToT Width", 100, 250, 10,
        function() return JarUnitFramesDB.totWidth or 150 end,
        function(v) v = math.floor(v / 10 + 0.5) * 10; JarUnitFramesDB.totWidth = v
            if targetTargetFrame then
                RunWhenSafe("totWidth", function() targetTargetFrame:SetWidth(v); targetTargetFrame.healthBar:SetWidth(v); targetTargetFrame.powerBar:SetWidth(v) end)
            end
        end,
        function(v) return math.floor(v / 10 + 0.5) * 10 end)

    -- ═══════════════════════════════════════════════
    --  PET FRAME
    -- ═══════════════════════════════════════════════
    AddHeader("Pet Frame")
    AddCheck("Show Pet Frame",
        function() return JarUnitFramesDB.showPetFrame end,
        function(v) JarUnitFramesDB.showPetFrame = v; SetupFrames() end)
    AddCheck("Show Pet Buffs",
        function() return JarUnitFramesDB.petShowBuffs end,
        function(v) JarUnitFramesDB.petShowBuffs = v; SetAuraRowShown(petFrame and petFrame.buffRow, v) end)
    AddCheck("Show Pet Debuffs",
        function() return JarUnitFramesDB.petShowDebuffs end,
        function(v) JarUnitFramesDB.petShowDebuffs = v; SetAuraRowShown(petFrame and petFrame.debuffRow, v) end)
    AddSlider("Pet Width", 100, 250, 10,
        function() return JarUnitFramesDB.petWidth or 150 end,
        function(v) v = math.floor(v / 10 + 0.5) * 10; JarUnitFramesDB.petWidth = v
            if petFrame then
                RunWhenSafe("petWidth", function() petFrame:SetWidth(v); petFrame.healthBar:SetWidth(v); petFrame.powerBar:SetWidth(v) end)
            end
        end,
        function(v) return math.floor(v / 10 + 0.5) * 10 end)

    -- ═══════════════════════════════════════════════
    --  PARTY FRAMES
    -- ═══════════════════════════════════════════════
    AddHeader("Party Frames")
    AddCheck("Show Party Frames",
        function() return JarUnitFramesDB.showPartyFrames end,
        function(v) JarUnitFramesDB.showPartyFrames = v
            HideBlizzardPartyFrames()
            SetupFrames()
            -- blocked blizz frames cant be un-blocked without a reload
            if not v then print("|cff00ff00Jar's Unit Frames|r /reload to get the Blizzard party frames back") end
        end)
    AddCheck("Show Only My Buffs",
        function() return JarUnitFramesDB.partyShowOnlyMyBuffs end,
        function(v) JarUnitFramesDB.partyShowOnlyMyBuffs = v
            for i = 1, 4 do SetAuraRowFilter(partyFrames[i] and partyFrames[i].buffRow, v and "HELPFUL|PLAYER" or "HELPFUL") end
        end)
    AddSlider("Party Width", 100, 250, 10,
        function() return JarUnitFramesDB.partyWidth or 150 end,
        function(v) v = math.floor(v / 10 + 0.5) * 10; JarUnitFramesDB.partyWidth = v; RunWhenSafe("partyPos", RepositionPartyFrames) end,
        function(v) return math.floor(v / 10 + 0.5) * 10 end)
    AddSlider("Party Padding", 0, 20, 1,
        function() return JarUnitFramesDB.partyPadding or 5 end,
        function(v) v = math.floor(v + 0.5); JarUnitFramesDB.partyPadding = v; RunWhenSafe("partyPos", RepositionPartyFrames) end,
        function(v) return math.floor(v + 0.5) end)

    -- Set scroll child height
    NextY(20)
    content:SetHeight(math.abs(yOff))

    frame:SetScript("OnHide", function() end)
    
    return frame
end

-- Main update function, also polls ToT since it has no events
local totTick = 0
local function OnUpdate(self, elapsed)
    timeSinceLastUpdate = timeSinceLastUpdate + elapsed
    if timeSinceLastUpdate < UPDATE_INTERVAL then return end
    timeSinceLastUpdate = 0

    if JarUnitFramesDB.showPlayerFrame then
        UpdatePlayerFrame()
    end

    if JarUnitFramesDB.showTargetFrame then
        UpdateTargetFrame()
    end

    if targetTargetFrame and JarUnitFramesDB.showTargetTargetFrame then
        UpdateTargetTargetFrame()
        totTick = totTick + 1
        if totTick >= 5 then
            totTick = 0
            RefreshAuras(targetTargetFrame)
        end
    end
end

local function UpdateAllFrames()
    UpdatePlayerFrame()
    UpdateTargetFrame()
    UpdateFocusFrame()
    UpdateTargetTargetFrame()
    UpdatePetFrame()
    for i = 1, 4 do
        UpdatePartyFrame(i)
    end
    ForEachUnitFrame(RefreshAuras)
end

-- create whatever is enabled (once) and set unit watches. queued in combat
function SetupFrames()
    RunWhenSafe("setup", function()
        playerFrame = playerFrame or CreatePlayerFrame()
        targetFrame = targetFrame or CreateTargetFrame()
        if JarUnitFramesDB.showFocusFrame then
            focusFrame = focusFrame or CreateFocusFrame()
        end
        if JarUnitFramesDB.showTargetTargetFrame then
            targetTargetFrame = targetTargetFrame or CreateTargetTargetFrame()
        end
        if JarUnitFramesDB.showPetFrame then
            petFrame = petFrame or CreatePetFrame()
        end
        if JarUnitFramesDB.showPartyFrames and not partyFrames[1] then
            for i = 1, 4 do
                partyFrames[i] = CreatePartyFrame(i)
            end
            RepositionPartyFrames()
        end

        SetFrameEnabled(playerFrame, JarUnitFramesDB.showPlayerFrame)
        SetFrameEnabled(targetFrame, JarUnitFramesDB.showTargetFrame)
        SetFrameEnabled(focusFrame, JarUnitFramesDB.showFocusFrame)
        SetFrameEnabled(targetTargetFrame, JarUnitFramesDB.showTargetTargetFrame)
        SetFrameEnabled(petFrame, JarUnitFramesDB.showPetFrame)
        for i = 1, 4 do
            SetFrameEnabled(partyFrames[i], JarUnitFramesDB.showPartyFrames)
        end

        UpdateAllFrames()
    end)
end

-- Event handler
local eventFrame = CreateFrame("Frame")
eventFrame:RegisterEvent("PLAYER_LOGIN")
eventFrame:RegisterEvent("PLAYER_ENTERING_WORLD")
eventFrame:RegisterEvent("GROUP_ROSTER_UPDATE")
eventFrame:RegisterEvent("PLAYER_REGEN_ENABLED")

eventFrame:SetScript("OnEvent", function(self, event, ...)
    if event == "PLAYER_LOGIN" then
        -- Initialize defaults for any missing fields (after SavedVariables are loaded)
        for key, value in pairs(defaults) do
            if JarUnitFramesDB[key] == nil then
                JarUnitFramesDB[key] = value
            end
        end

        -- NOT_SELF is gone in 12.1
        for _, key in ipairs({ "playerDebuffFilter", "targetDebuffFilter", "focusDebuffFilter", "totDebuffFilter", "petDebuffFilter", "partyDebuffFilter" }) do
            JarUnitFramesDB[key] = JarUnitFramesDB[key]:gsub("NOT_SELF", "!PLAYER")
        end

        -- Load fonts from SharedMedia if available
        LoadSharedMediaFonts()

        print("|cff00ff00Jar's Unit Frames|r loaded. Type /juf for options.")

        HideBlizzardUnitFrames()
        HideBlizzardPartyFrames()
        SetupFrames()

        -- Create config window
        local success, result = pcall(CreateConfigFrame)
        if success then
            configFrame = result
            print("|cff00ff00Jar's Unit Frames|r Config frame created successfully")
        else
            print("|cffff0000Jar's Unit Frames|r Error creating config frame: " .. tostring(result))
        end

        self:SetScript("OnUpdate", OnUpdate)

    elseif event == "PLAYER_ENTERING_WORLD" then
        HideBlizzardPartyFrames()
        UpdateAllFrames()

    elseif event == "GROUP_ROSTER_UPDATE" then
        -- blizz party frames can come back when the group changes
        HideBlizzardPartyFrames()

    elseif event == "PLAYER_REGEN_ENABLED" then
        FlushPending()
    end
end)

function JarsUnitFrames_OpenConfig()
    if configFrame then configFrame:Show() end
end

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
        
        -- unit watch on/off, queued if in combat
        SetupFrames()
        
        print("|cff00ff00Jar's Unit Frames|r " .. (JarUnitFramesDB.showPlayerFrame and "shown" or "hidden"))
        
    elseif msg == "scale" then
        print("Usage: /juf scale <number> (e.g., /juf scale 1.2)")
        
    elseif msg:match("^scale%s+(.+)") then
        local scale = tonumber(msg:match("^scale%s+(.+)"))
        if scale and scale > 0.5 and scale < 3 then
            JarUnitFramesDB.frameScale = scale
            ApplyFrameScale()
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
        -- List all current player buffs with their spell IDs (secret in combat, so skip then)
        if C_Secrets.ShouldAurasBeSecret() then
            print("|cff00ff00Jar's Unit Frames|r Buffs are hidden right now (combat/instance), try again later")
            return
        end
        local auras = C_UnitAuras.GetUnitAuras("player", "HELPFUL", 40, nil, nil)
        print("|cff00ff00Jar's Unit Frames|r Current Buffs:")
        for i, auraData in ipairs(auras) do
            if not issecretvalue(auraData.name) then
                local stacks = (auraData.applications and auraData.applications > 1) and (" x" .. auraData.applications) or ""
                print("  " .. i .. ". " .. auraData.name .. stacks .. " (ID: " .. auraData.spellId .. ")")
            end
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

