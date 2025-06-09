local AddonName = "DeBuffFilter"

local DeBuffFilter = LibStub:GetLibrary(AddonName, true)
local MAX_TARGET_DEBUFFS = 16
local MAX_TARGET_BUFFS = 40
local AURA_START_Y = 32
local AURA_START_X = 5
local mabs, pairs, mfloor = math.abs, pairs, math.floor
local tinsert, tsort, tostring = table.insert, table.sort, tostring
local UnitBuff, UnitDebuff, UnitIsEnemy = _G.UnitBuff, _G.UnitDebuff, _G.UnitIsEnemy
local UnitIsUnit, UnitIsOwnerOrControllerOfUnit, UnitIsFriend = _G.UnitIsUnit, _G.UnitIsOwnerOrControllerOfUnit, _G.UnitIsFriend
local IsAddOnLoaded = C_AddOns and C_AddOns.IsAddOnLoaded or IsAddOnLoaded
local GetAddOnMetadata = C_AddOns and C_AddOns.GetAddOnMetadata or GetAddOnMetadata
local playerClass = select(2, UnitClass("player"))
local fontName
local isClassic = WOW_PROJECT_ID == WOW_PROJECT_CLASSIC
local LibClassicDurations

function DeBuffFilter:Blacklisted(value)
    value = tostring(value)
    for _, blockedName in pairs(self.db.profile.hiddenBuffs) do
        if blockedName == value then
            return true
        end
    end
    return false
end

local function adjustCastbar(frame)
    local parentFrame = frame:GetParent()
    local yOffset, xOffset = parentFrame.largestAura or 0
    local spellbarAnchor = parentFrame.spellbarAnchor

    local db = DeBuffFilter.db.profile

    local barPosX = parentFrame == TargetFrame and db.targetBarPosX or parentFrame == FocusFrame and db.focusBarPosX
    local barPosY = parentFrame == TargetFrame and db.targetBarPosY or parentFrame == FocusFrame and db.focusBarPosY

    if (barPosX and barPosX ~= 0) or (barPosY and barPosY ~= 0) then
        spellbarAnchor = parentFrame
    end

    local function safeSet(frame, anchor, x, y)
        local curr = { frame:GetPoint() }
        if not (curr[2] == anchor and curr[4] == x and curr[5] == y) then
            frame:ClearAllPoints()
            frame:SetPoint("TOPLEFT", anchor, "BOTTOMLEFT", x, y)
        end
    end

    if frame.boss then
        safeSet(frame, parentFrame, barPosX ~= 0 and barPosX or 25, barPosY ~= 0 and barPosY or 10 - yOffset)
    elseif parentFrame.haveToT then
        if parentFrame.buffsOnTop or parentFrame.auraRows <= 1 then
            safeSet(frame, parentFrame, barPosX ~= 0 and barPosX or 25, barPosY ~= 0 and barPosY or -25)
        else
            safeSet(frame, spellbarAnchor, barPosX ~= 0 and barPosX or 20, barPosY ~= 0 and barPosY or -15 - yOffset)
        end
    elseif parentFrame.haveElite then
        if parentFrame.buffsOnTop or parentFrame.auraRows <= 1 then
            safeSet(frame, parentFrame, barPosX ~= 0 and barPosX or 25, barPosY ~= 0 and barPosY or -5)
        else
            safeSet(frame, spellbarAnchor, barPosX ~= 0 and barPosX or 20, barPosY ~= 0 and barPosY or -15 - yOffset)
        end
    else
        if not parentFrame.buffsOnTop and parentFrame.auraRows > 0 then
            safeSet(frame, spellbarAnchor, barPosX ~= 0 and barPosX or 20, barPosY ~= 0 and barPosY or -15 - yOffset)
        else
            safeSet(frame, parentFrame, barPosX ~= 0 and barPosX or 25, barPosY ~= 0 and barPosY or 7 - yOffset)
        end
    end
end

local PLAYER_UNITS = {
    player = true,
    vehicle = true,
    pet = true,
};

local function ShouldAuraBeLarge(caster)
    if not caster then
        return false;
    end

    for token, value in pairs(PLAYER_UNITS) do
        if UnitIsUnit(caster, token) or UnitIsOwnerOrControllerOfUnit(token, caster) then
            return value;
        end
    end
end

local function safeSetPoint(frame, point, relativeTo, relativePoint, x, y)
    if not frame or not relativeTo then
        return
    end
    local current = relativeTo
    while current do
        if current == frame then
            frame:ClearAllPoints()
            frame:SetPoint(point, relativeTo:GetParent(), relativePoint, x, y)
            return
        end
        local _, parent = current:GetPoint()
        current = parent
    end
    frame:ClearAllPoints()
    frame:SetPoint(point, relativeTo, relativePoint, x, y)
end

local function UpdateBuffAnchor(self, buffName, numDebuffs, anchorBuff, size, offsetX, offsetY, mirrorVertically, newRow)
    --For mirroring vertically
    local point, relativePoint;
    local startY, auraOffsetY;
    if (mirrorVertically) then
        point = "BOTTOM";
        relativePoint = "TOP";
        startY = -15;
        if (self.threatNumericIndicator:IsShown()) then
            startY = startY + self.threatNumericIndicator:GetHeight();
        end
        offsetY = -offsetY;
        auraOffsetY = -DeBuffFilter.db.profile.verticalSpace;
    else
        point = "TOP";
        relativePoint = "BOTTOM";
        startY = AURA_START_Y;
        auraOffsetY = DeBuffFilter.db.profile.verticalSpace;
    end

    buffName:ClearAllPoints()

    if anchorBuff == nil then
        -- Party member can be friendly and hostile at the same time.. UnitCanAssist would probably be better,
        -- but UnitCanAssist has it own quirks, e.g. in spectator mode
        if ((UnitIsFriend("player", self.unit) and not UnitIsEnemy("player", self.unit)) or numDebuffs == 0) then
            -- unit is friendly or there are no debuffs...buffs start on top
            buffName:SetPoint(point .. "LEFT", self, relativePoint .. "LEFT", AURA_START_X, startY);
        else
            -- unit is not friendly and we have debuffs...buffs start on bottom
            safeSetPoint(buffName, point .. "LEFT", self.debuffz, relativePoint .. "LEFT", 0, -offsetY);
        end
        self.buffz:ClearAllPoints()
        self.buffz:SetPoint(point .. "LEFT", buffName, point .. "LEFT", 0, 0);
        self.buffz:SetPoint(relativePoint .. "LEFT", buffName, relativePoint .. "LEFT", 0, -auraOffsetY);
        self.spellbarAnchor = buffName;
    elseif newRow then
        buffName:SetPoint(point .. "LEFT", anchorBuff, relativePoint .. "LEFT", 0, -offsetY);
        self.buffz:ClearAllPoints()
        self.buffz:SetPoint(relativePoint .. "LEFT", buffName, relativePoint .. "LEFT", 0, -auraOffsetY);
        self.spellbarAnchor = buffName;
    else
        buffName:SetPoint(point .. "LEFT", anchorBuff, point .. "RIGHT", offsetX, 0);
    end

    -- Resize
    buffName:SetWidth(size);
    buffName:SetHeight(size);
end

local function UpdateDebuffAnchor(self, debuffName, numBuffs, anchorDebuff, size, offsetX, offsetY, mirrorVertically, newRow)
    --For mirroring vertically
    local point, relativePoint;
    local startY, auraOffsetY;
    local isFriend = UnitIsFriend("player", self.unit);

    if (mirrorVertically) then
        point = "BOTTOM";
        relativePoint = "TOP";
        startY = -15;
        if (self.threatNumericIndicator:IsShown()) then
            startY = startY + self.threatNumericIndicator:GetHeight();
        end
        offsetY = -offsetY;
        auraOffsetY = -DeBuffFilter.db.profile.verticalSpace;
    else
        point = "TOP";
        relativePoint = "BOTTOM";
        startY = AURA_START_Y;
        auraOffsetY = DeBuffFilter.db.profile.verticalSpace;
    end

    debuffName:ClearAllPoints()

    if anchorDebuff == nil then
        if ((isFriend and not UnitIsEnemy("player", self.unit)) and numBuffs > 0) then
            -- unit is friendly and there are buffs...debuffs start on bottom
            debuffName:SetPoint(point .. "LEFT", self.buffz, relativePoint .. "LEFT", 0, -offsetY);
        else
            -- unit is not friendly or there are no buffs...debuffs start on top
            debuffName:SetPoint(point .. "LEFT", self, relativePoint .. "LEFT", AURA_START_X, startY);
        end
        self.debuffz:ClearAllPoints()
        self.debuffz:SetPoint(point .. "LEFT", debuffName, point .. "LEFT", 0, 0);
        self.debuffz:SetPoint(relativePoint .. "LEFT", debuffName, relativePoint .. "LEFT", 0, -auraOffsetY);
        if ((isFriend) or (not isFriend and numBuffs == 0)) then
            self.spellbarAnchor = debuffName;
        end
    elseif newRow then
        debuffName:SetPoint(point .. "LEFT", anchorDebuff, relativePoint .. "LEFT", 0, -offsetY);
        self.debuffz:ClearAllPoints()
        self.debuffz:SetPoint(relativePoint .. "LEFT", debuffName, relativePoint .. "LEFT", 0, -auraOffsetY);
        if ((isFriend) or (not isFriend and numBuffs == 0)) then
            self.spellbarAnchor = debuffName;
        end
    else
        debuffName:SetPoint(point .. "LEFT", anchorDebuff, point .. "RIGHT", offsetX, 0);
    end

    -- Resize
    debuffName:SetWidth(size);
    debuffName:SetHeight(size);
    local debuffFrame = _G[debuffName:GetName() .. "Border"];
    if debuffFrame then
        debuffFrame:SetWidth(size + 2);
        debuffFrame:SetHeight(size + 2);
    end
end

local function GetFramePosition(frame)
    if not frame then
        return 0, 0
    end
    local left = frame:GetLeft() or 0
    local bottom = frame:GetBottom() or 0
    return left, bottom
end

local function combinedSort(a, b)
    local db = DeBuffFilter.db.profile
    if db.sortbyDispellable then
        if playerClass == "ROGUE" and (a.dispelType == "" and b.dispelType ~= "") then
            return true
        end
        if playerClass == "ROGUE" and (a.dispelType ~= "" and b.dispelType == "") then
            return false
        end
        if a.dispelType == "Magic" and b.dispelType ~= "Magic" then
            return true
        end
        if a.dispelType ~= "Magic" and b.dispelType == "Magic" then
            return false
        end
    end
    if db.sortBySize and a.size ~= b.size then
        return a.size > b.size
    end
    if db.enablePrioritySort and a.prio ~= b.prio then
        return a.prio > b.prio
    end
    return a.index < b.index
end

local function auraSortBySize(frame, auraName, numAuras, numOppositeAuras, updateFunc, offsetX, mirrorAurasVertically)
    local db = DeBuffFilter.db.profile
    local LARGE_AURA_SIZE = db.selfSize
    local SMALL_AURA_SIZE = db.otherSize
    local maxRowWidth = db.auraWidth
    local yDistance = db.verticalSpace
    local offsetY = yDistance
    local size, biggestAura
    local rowWidth = 0
    local anchorRowAura, lastBuff = nil, nil
    local haveTargetofTarget = frame.totFrame and frame.totFrame:IsShown()
    local totFrameX, totFrameBottom = GetFramePosition(frame.totFrame)
    local currentX, currentY
    local auras, processedSpellIDs = {}, {}
    local customSizes = db.customSizes
    local customShowOwnOnly = db.customShowOwnOnly
    local customHighlightPriorities = db.customHighlightPriorities
    local removeDuplicates = db.removeDuplicates
    local filter = (updateFunc == UpdateBuffAnchor) and "HELPFUL" or "HARMFUL"

    for i = 1, numAuras do
        local aura
        if isClassic then
            local name, _, _, dispelType, _, _, source, _, _, spellId = LibClassicDurations:UnitAura(frame.unit, i, filter)
            aura = { name = name, spellId = spellId, sourceUnit = source, dispelName = dispelType }
        else
            aura = C_UnitAuras.GetAuraDataByIndex(frame.unit, i, filter)
        end
        if aura and aura.name then
            local spellIdStr = tostring(aura.spellId)
            local customSize = customSizes[spellIdStr] or customSizes[aura.name]
            if customSize then
                size = ShouldAuraBeLarge(aura.sourceUnit) and customSize.ownSize or customSize.otherSize
            else
                size = (aura.sourceUnit and ShouldAuraBeLarge(aura.sourceUnit)) and LARGE_AURA_SIZE or SMALL_AURA_SIZE
            end
            if aura.dispelName == nil then
                aura.dispelName = "GG"
            end
            local priority = customHighlightPriorities[aura.name] or 0
            tinsert(auras, {
                size = size, name = aura.name, dbf = _G[auraName .. i],
                dispelType = aura.dispelName, prio = priority,
                source = aura.sourceUnit, index = i, spellId = aura.spellId
            })
        end
    end

    tsort(auras, combinedSort)

    for _, auraData in ipairs(auras) do
        local size = auraData.size
        local aura = auraData.dbf
        local source = auraData.source
        local spellIdStr = tostring(auraData.spellId)
        local ownOnly = customShowOwnOnly[spellIdStr] or customShowOwnOnly[auraData.name]

        if not (DeBuffFilter:Blacklisted(auraData.name) or DeBuffFilter:Blacklisted(auraData.spellId)) and
                (not ownOnly or (ownOnly and auraData.source == "player")) and
                not processedSpellIDs[auraData.spellId] then

            if removeDuplicates[spellIdStr] or removeDuplicates[auraData.name] then
                processedSpellIDs[auraData.spellId] = true
            end

            if source and ShouldAuraBeLarge(source) then
                offsetY = yDistance * 2
            end

            if lastBuff == nil then
                rowWidth = size
                frame.auraRows = frame.auraRows + 1
                anchorRowAura = aura
                if frame.largestAura then
                    offsetY = frame.largestAura
                end
            else
                rowWidth = rowWidth + size + offsetX
            end

            local verticalDistance = currentY and (currentY - totFrameBottom) or 0
            local horizontalDistance = rowWidth

            if currentX then
                horizontalDistance = (mfloor(mabs((currentX + size + offsetX) - totFrameX))) + 5
            end

            if (haveTargetofTarget and (horizontalDistance < size) and verticalDistance > 0) or (rowWidth > maxRowWidth) then
                if biggestAura and anchorRowAura and biggestAura >= mfloor(anchorRowAura:GetSize() + 0.5) then
                    offsetY = (yDistance * 2) + (biggestAura - anchorRowAura:GetSize())
                end
                updateFunc(frame, aura, numOppositeAuras, anchorRowAura, size, offsetX, offsetY, mirrorAurasVertically, true)
                rowWidth = size
                frame.auraRows = frame.auraRows + 1
                anchorRowAura = aura
                offsetY = yDistance
                biggestAura = nil
                frame.largestAura = nil
            else
                updateFunc(frame, aura, numOppositeAuras, lastBuff, size, offsetX, offsetY, mirrorAurasVertically)
            end

            lastBuff = aura
            currentX, currentY = aura:GetLeft(), aura:GetTop()

            if not biggestAura or (biggestAura and (biggestAura < size)) then
                biggestAura = size
            end
            local calc = (yDistance * 2) + (biggestAura - anchorRowAura:GetSize())
            if not frame.largestAura or (frame.largestAura and (frame.largestAura < calc)) then
                frame.largestAura = calc
            end
        else
            if aura then
                aura:ClearAllPoints()
                aura:SetPoint("CENTER", frame, "CENTER", 100000, 100000)
            end
        end
    end
end

local function updatePositions(frame, auraName, numAuras, numOppositeAuras, updateFunc, offsetX, mirrorAurasVertically)
    local db = DeBuffFilter.db.profile
    local LARGE_AURA_SIZE = db.selfSize
    local SMALL_AURA_SIZE = db.otherSize
    local maxRowWidth = db.auraWidth
    local yDistance = db.verticalSpace
    local offsetY = yDistance
    local size, biggestAura
    local rowWidth = 0
    local anchorRowAura, lastBuff = nil, nil
    local haveTargetofTarget = frame.totFrame and frame.totFrame:IsShown()
    local totFrameX, totFrameBottom = GetFramePosition(frame.totFrame)
    local currentX, currentY
    local processedSpellIDs = {}
    local customShowOwnOnly = db.customShowOwnOnly
    local customSizes = db.customSizes
    local removeDuplicates = db.removeDuplicates
    local filter = (updateFunc == UpdateBuffAnchor) and "HELPFUL" or "HARMFUL"

    for i = 1, numAuras do
        local aura
        if isClassic then
            local name, icon, _, dispelType, _, _, source, _, _, spellId = LibClassicDurations:UnitAura(frame.unit, i, filter)
            aura = { name = name, spellId = spellId, sourceUnit = source, dispelName = dispelType, icon = icon }
        else
            aura = C_UnitAuras.GetAuraDataByIndex(frame.unit, i, filter)
        end
        if aura and aura.name and aura.icon then
            local dbf = _G[auraName .. i]
            local spellIdStr = tostring(aura.spellId)
            local ownOnly = customShowOwnOnly[spellIdStr] or customShowOwnOnly[aura.name]
            if not (DeBuffFilter:Blacklisted(aura.name) or DeBuffFilter:Blacklisted(aura.spellId)) and
                    (not ownOnly or (ownOnly and aura.sourceUnit == "player")) and
                    not processedSpellIDs[aura.spellId] then

                if removeDuplicates[spellIdStr] or removeDuplicates[aura.name] then
                    processedSpellIDs[aura.spellId] = true
                end

                local shouldbeLarge = ShouldAuraBeLarge(aura.sourceUnit)
                if aura.sourceUnit and shouldbeLarge then
                    size = LARGE_AURA_SIZE
                    offsetY = yDistance * 2
                else
                    size = SMALL_AURA_SIZE
                end

                local customSize = customSizes[spellIdStr] or customSizes[aura.name]
                if customSize then
                    size = shouldbeLarge and customSize.ownSize or customSize.otherSize
                end

                if lastBuff == nil then
                    rowWidth = size
                    frame.auraRows = frame.auraRows + 1
                    anchorRowAura = dbf
                    if frame.largestAura then
                        offsetY = frame.largestAura
                    end
                else
                    rowWidth = rowWidth + size + offsetX
                end

                local verticalDistance = currentY and (currentY - totFrameBottom) or 0
                local horizontalDistance = rowWidth

                if currentX then
                    horizontalDistance = (mfloor(mabs((currentX + size + offsetX) - totFrameX))) + 5
                end

                if (haveTargetofTarget and (horizontalDistance < size) and verticalDistance > 0) or (rowWidth > maxRowWidth) then
                    if biggestAura and anchorRowAura and biggestAura >= mfloor(anchorRowAura:GetSize() + 0.5) then
                        offsetY = (yDistance * 2) + (biggestAura - anchorRowAura:GetSize())
                    end
                    updateFunc(frame, dbf, numOppositeAuras, anchorRowAura, size, offsetX, offsetY, mirrorAurasVertically, true)
                    rowWidth = size
                    frame.auraRows = frame.auraRows + 1
                    offsetY = yDistance
                    anchorRowAura = dbf
                    biggestAura = nil
                    frame.largestAura = nil
                else
                    updateFunc(frame, dbf, numOppositeAuras, lastBuff, size, offsetX, offsetY, mirrorAurasVertically)
                end
                lastBuff = dbf
                currentX, currentY = dbf:GetLeft(), dbf:GetTop()

                if not biggestAura or (biggestAura and (biggestAura < size)) then
                    biggestAura = size
                end
                local calc = (yDistance * 2) + (biggestAura - anchorRowAura:GetSize())
                if not frame.largestAura or (frame.largestAura and (frame.largestAura < calc)) then
                    frame.largestAura = calc
                end
            else
                if dbf then
                    dbf:ClearAllPoints()
                    dbf:SetPoint("CENTER", frame, "CENTER", 100000, 100000)
                end
            end
        end
    end
end

local function Filterino(self)
    if self and (not (self == TargetFrame or self == FocusFrame) or self:IsForbidden()) then
        return
    end

    local frame, frameName
    local frameIcon, frameCount, frameCooldown
    local selfName = self:GetName()
    local numDebuffs, numBuffs = 0, 0
    local numDebuff, numBuff = 0, 0
    local playerIsTarget = UnitIsUnit("player", self.unit)
    local isEnemy = UnitIsEnemy("player", self.unit)
    local buffDetect = isClassic and LibClassicDurations.UnitAuraWithBuffs or UnitBuff
    local db = DeBuffFilter.db.profile

    for i = 1, MAX_TARGET_BUFFS do
        local buffName, icon, count, debuffType, duration, expirationTime, caster, canStealOrPurge, _, spellId = buffDetect(self.unit, i, "HELPFUL")
        if buffName then
            frameName = selfName .. "Buff" .. i
            frame = _G[frameName]
            local frameStealable = _G[frameName .. "Stealable"]
            local shouldBeLarge = caster and ShouldAuraBeLarge(caster)
            local buffSize = shouldBeLarge and db.selfSize or db.otherSize
            local modifier = 1.34
            local stockR, stockG, stockB = 1, 1, 1

            if isClassic then
                if (not frame) then
                    if (not icon) then
                        break
                    else
                        frame = CreateFrame("Button", frameName, self, "TargetBuffFrameTemplate")
                        frame.unit = self.unit
                    end
                end
                if (icon and (not self.maxBuffs or i <= self.maxBuffs)) then
                    frame:SetID(i)
                    frameIcon = _G[frameName .. "Icon"]
                    frameIcon:SetTexture(icon)
                    frameCount = _G[frameName .. "Count"]
                    if (count and count > 1 and self.showAuraCount) then
                        frameCount:SetText(count)
                        frameCount:Show()
                    else
                        frameCount:Hide()
                    end
                    frameCooldown = _G[frameName .. "Cooldown"]
                    CooldownFrame_Set(frameCooldown, expirationTime - duration, duration, duration > 0, true)
                    if isClassic then
                        frame:ClearAllPoints()
                        frame:Show()
                    end
                    if isEnemy and UnitBuff(frame.unit, i, "HELPFUL") == nil then
                        frame:SetScript("OnEnter", function(self)
                            GameTooltip:SetOwner(self, "ANCHOR_BOTTOMRIGHT", 15, -25)
                            GameTooltip:SetSpellByID(spellId)
                            GameTooltip:Show()
                        end)
                        frame:SetScript("OnLeave", function(self)
                            GameTooltip:Hide()
                        end)
                    end
                else
                    if isClassic and frame then
                        frame:Hide()
                    end
                end
            end

            if IsAddOnLoaded("RougeUI") and (RougeUI.Lorti or RougeUI.Roug or RougeUI.Modern) then
                modifier = 2.06
                stockR, stockG, stockB = 1, 1, 0.75
            end

            local newSize = db.customSizes[tostring(spellId)] or db.customSizes[buffName]
            if newSize then
                buffSize = shouldBeLarge and newSize.ownSize or newSize.otherSize
            end

            if db.customHighlights and frameStealable then
                local customColor = db.customHighlightColors[tostring(spellId)] or db.customHighlightColors[buffName]
                if icon and (customColor or (db.highlightAll and debuffType == "Magic")) then
                    if not customColor then
                        customColor = { r = 1, g = 1, b = 0.85, a = 1 }
                    end
                    local r, g, b, a = customColor.r, customColor.g, customColor.b, customColor.a
                    frameStealable:Show()
                    frameStealable:SetHeight(buffSize * modifier)
                    frameStealable:SetWidth(buffSize * modifier)
                    frameStealable:SetVertexColor(r, g, b, a)
                    if modifier == 2.06 then
                        frameStealable:SetDesaturated(true)
                    end
                elseif (not playerIsTarget and isEnemy and canStealOrPurge) then
                    frameStealable:Show()
                    frameStealable:SetVertexColor(stockR, stockG, stockB)
                    frameStealable:SetHeight(buffSize * modifier)
                    frameStealable:SetWidth(buffSize * modifier)
                    if modifier == 2.06 then
                        frameStealable:SetDesaturated(true)
                    end
                else
                    frameStealable:Hide()
                end
            end

            local frameCount = _G[frameName .. "Count"]
            if frameCount then
                if not fontName then
                    fontName = frameCount:GetFont()
                end
                -- Only set font if different
                local _, currSize = frameCount:GetFont()
                local newFontSize = buffSize / 1.75
                if currSize ~= newFontSize then
                    frameCount:SetFont(fontName, newFontSize, "OUTLINE, THICKOUTLINE, MONOCHROME")
                end
            end

            numBuffs = numBuffs + 1
            if not (DeBuffFilter:Blacklisted(buffName) or DeBuffFilter:Blacklisted(spellId)) then
                numBuff = numBuff + 1
            end
        else
            break
        end
    end

    local frameNum = 1;
    local index = 1;

    local maxDebuffs = self.maxDebuffs or MAX_TARGET_DEBUFFS;
    while (frameNum <= maxDebuffs and index <= maxDebuffs) do
        local debuffName, icon, _, debuffType, _, _, caster, _, _, spellId, _, _, casterIsPlayer, nameplateShowAll = UnitDebuff(self.unit, index, "INCLUDE_NAME_PLATE_ONLY")
        if debuffName then
            if icon and (TargetFrame_ShouldShowDebuffs(self.unit, caster, nameplateShowAll, casterIsPlayer)) then
                frameName = selfName .. "Debuff" .. frameNum
                frame = _G[frameName]
                local debuffBorder = _G[frameName .. "Border"]
                local shouldBeLarge = caster and ShouldAuraBeLarge(caster)
                local buffSize = shouldBeLarge and DeBuffFilter.db.profile.selfSize or DeBuffFilter.db.profile.otherSize

                if DeBuffFilter.db.profile.customHighlights then
                    local customColor = DeBuffFilter.db.profile.customHighlightColors[tostring(spellId)] or DeBuffFilter.db.profile.customHighlightColors[debuffName]
                    local modifier = 1.3
                    local stockR, stockG, stockB = 1, 1, 1
                    local texturePath = "Interface\\TargetingFrame\\UI-TargetingFrame-Stealable"

                    if IsAddOnLoaded("RougeUI") and (RougeUI.Lorti or RougeUI.Roug or RougeUI.Modern) then
                        modifier = 2.06
                        stockR, stockG, stockB = 1, 1, 0.75
                    end

                    local frameStealable = _G[frameName .. "Stealable"]
                    if not frameStealable and frame and customColor then
                        frameStealable = frame:CreateTexture(frameName .. "Stealable", "OVERLAY")
                        if modifier == 2.06 then
                            texturePath = "Interface\\AddOns\\RougeUI\\textures\\newexp"
                            frameStealable:SetTexCoord(0.338379, 0.412598, 0.680664, 0.829102)
                        end
                        frameStealable:SetTexture(texturePath)
                        frameStealable:SetSize(24, 24)
                        frameStealable:SetPoint("CENTER", 0, 0)
                        frameStealable:SetBlendMode("ADD")
                    end

                    if frameStealable then
                        if customColor then
                            local newSize = DeBuffFilter.db.profile.customSizes[tostring(spellId)] or DeBuffFilter.db.profile.customSizes[debuffName]
                            if newSize then
                                buffSize = shouldBeLarge and newSize.ownSize or newSize.otherSize
                            end

                            local r, g, b, a = customColor.r, customColor.g, customColor.b, customColor.a
                            frameStealable:Show()
                            frameStealable:SetHeight(buffSize * modifier)
                            frameStealable:SetWidth(buffSize * modifier)
                            frameStealable:SetVertexColor(r, g, b, a)
                            debuffBorder:SetShown(r == 0 and g == 0 and b == 0 or a == 0)

                            if modifier == 2.06 then
                                frameStealable:SetDesaturated(true)
                            end
                        else
                            frameStealable:Hide()
                            debuffBorder:Show()
                        end
                    end
                end

                local frameCount = _G[frameName .. "Count"]
                if frameCount then
                    if not fontName then
                        fontName = frameCount:GetFont()
                    end
                    _G[frameName .. "Count"]:SetFont(fontName, buffSize / 1.75, "OUTLINE, THICKOUTLINE, MONOCHROME")
                end

                numDebuffs = numDebuffs + 1;
                frameNum = frameNum + 1;
                if not (DeBuffFilter:Blacklisted(debuffName) or DeBuffFilter:Blacklisted(spellId)) then
                    numDebuff = numDebuff + 1
                end
            end
        else
            break
        end
        index = index + 1;
    end

    local mirrorAurasVertically = self.buffsOnTop and true or false
    local offsetX = db.horizontalSpace

    self.auraRows = 0
    self.largestAura = 0
    self.spellbarAnchor = nil

    local sortOrDefault = (db.sortBySize or db.sortbyDispellable or db.enablePrioritySort) and auraSortBySize or updatePositions

    if not self.buffz then
        self.buffz = CreateFrame("Frame", "$parentBuffz", self)
        self.buffz:SetSize(10, 10)
    end
    if not self.debuffz then
        self.debuffz = CreateFrame("Frame", "$parentDebuffz", self)
        self.debuffz:SetSize(10, 10)
    end

    if isEnemy then
        sortOrDefault(self, selfName .. "Debuff", numDebuffs, numBuff, UpdateDebuffAnchor, offsetX, mirrorAurasVertically)
        sortOrDefault(self, selfName .. "Buff", numBuffs, numDebuff, UpdateBuffAnchor, offsetX, mirrorAurasVertically)
    else
        sortOrDefault(self, selfName .. "Buff", numBuffs, numDebuff, UpdateBuffAnchor, offsetX, mirrorAurasVertically)
        sortOrDefault(self, selfName .. "Debuff", numDebuffs, numBuff, UpdateDebuffAnchor, offsetX, mirrorAurasVertically)
    end

    if self.spellbar then
        adjustCastbar(self.spellbar)
    end
end

DeBuffFilter.event = CreateFrame("Frame")
DeBuffFilter.event:RegisterEvent("PLAYER_LOGIN")
DeBuffFilter.event:SetScript("OnEvent", function(self)
    DeBuffFilter:SetupOptions()

    if isClassic then
        LibClassicDurations = LibStub("LibClassicDurations")
        LibClassicDurations:Register(AddonName)
        LibClassicDurations.RegisterCallback(AddonName, "UNIT_BUFF", function(event, unit)
            TargetFrame_UpdateAuras(TargetFrame)
        end)
    end

    hooksecurefunc("TargetFrame_UpdateAuras", Filterino)

    for _, v in pairs({ TargetFrameSpellBar, FocusFrameSpellBar }) do
        if v then
            hooksecurefunc(v, "SetPoint", function(self)
                if self.busy then return end
                self.busy = true
                adjustCastbar(self)
                self.busy = false
            end)
        end
    end

    local db = DeBuffFilter.db.profile
    TargetFrameSpellBar:SetScale(db.targetCastBarSize)
    if FocusFrameSpellBar then
        FocusFrameSpellBar:SetScale(db.focusCastBarSize)
    end

    playerClass = select(2, UnitClass("player"))
end)