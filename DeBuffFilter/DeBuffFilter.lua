local AddonName, DBF = ...

local DeBuffFilter = LibStub:GetLibrary(AddonName, true)
local MAX_TARGET_DEBUFFS = 16
local MAX_TARGET_BUFFS = 40
local AURA_START_Y = 32
local AURA_START_X = 5
local fontName
local mabs, pairs, mfloor = math.abs, pairs, math.floor
local tinsert, tsort, tostring = table.insert, table.sort, tostring
local UnitBuff, UnitDebuff, UnitIsEnemy = _G.UnitBuff, _G.UnitDebuff, _G.UnitIsEnemy
local UnitIsUnit, UnitIsOwnerOrControllerOfUnit, UnitIsFriend = _G.UnitIsUnit, _G.UnitIsOwnerOrControllerOfUnit, _G.UnitIsFriend
local IsAddOnLoaded = C_AddOns and C_AddOns.IsAddOnLoaded or IsAddOnLoaded
local GetAddOnMetadata = C_AddOns and C_AddOns.GetAddOnMetadata or GetAddOnMetadata
local playerClass = select(2, UnitClass("player"))
local isClassic = WOW_PROJECT_ID == WOW_PROJECT_CLASSIC
local LibClassicDurations
DeBuffFilter._trackedAuras = DeBuffFilter._trackedAuras or {}
DeBuffFilter._auraState = DeBuffFilter._auraState or {}

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
}

function DeBuffFilter:ShouldAuraBeLarge(caster)
    if not caster then
        return false
    end

    for token, value in pairs(PLAYER_UNITS) do
        if UnitIsUnit(caster, token) or UnitIsOwnerOrControllerOfUnit(token, caster) then
            return value
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

function DeBuffFilter:CheckSmarterAuraFilters(spellId, auraName, expirationTime, stacks, frameName, filters)
    if not filters then
        return nil
    end

    local actions = {}

    for _, settings in ipairs(filters) do
        local passDuration = not settings.enableDurationFilter
        if settings.enableDurationFilter then
            local currentDuration = expirationTime and (expirationTime - GetTime()) or 0
            passDuration = (settings.minDuration <= 0 or currentDuration >= settings.minDuration) and
                    (settings.maxDuration <= 0 or currentDuration <= settings.maxDuration)
        end

        local passStacks = not settings.enableStacksFilter
        if settings.enableStacksFilter then
            if stacks == nil then
                passStacks = (settings.minStacks <= 0 and settings.maxStacks <= 0)
            else
                passStacks = (settings.minStacks <= 0 or stacks >= settings.minStacks) and
                        (settings.maxStacks <= 0 or stacks <= settings.maxStacks)
            end
        end

        if passDuration and passStacks then
            table.insert(actions, settings.action)
        end
    end

    if #actions > 0 then
        return actions
    else
        return nil
    end
end

local function UpdateBuffAnchor(self, buffName, numDebuffs, anchorBuff, size, offsetX, offsetY, mirrorVertically, newRow)
    local point, relativePoint
    local startY, auraOffsetY
    if mirrorVertically then
        point = "BOTTOM"
        relativePoint = "TOP"
        startY = -15
        if self.threatNumericIndicator:IsShown() then
            startY = startY + self.threatNumericIndicator:GetHeight()
        end
        offsetY = -offsetY
        auraOffsetY = -DeBuffFilter.db.profile.verticalSpace
    else
        point = "TOP"
        relativePoint = "BOTTOM"
        startY = AURA_START_Y
        auraOffsetY = DeBuffFilter.db.profile.verticalSpace
    end

    buffName:ClearAllPoints()

    if anchorBuff == nil then
        if (UnitIsFriend("player", self.unit) and not UnitIsEnemy("player", self.unit)) or numDebuffs == 0 then
            buffName:SetPoint(point .. "LEFT", self, relativePoint .. "LEFT", AURA_START_X, startY)
        else
            safeSetPoint(buffName, point .. "LEFT", self.debuffz, relativePoint .. "LEFT", 0, -offsetY)
        end
        self.buffz:ClearAllPoints()
        self.buffz:SetPoint(point .. "LEFT", buffName, point .. "LEFT", 0, 0)
        self.buffz:SetPoint(relativePoint .. "LEFT", buffName, relativePoint .. "LEFT", 0, -auraOffsetY)
        self.spellbarAnchor = buffName
    elseif newRow then
        buffName:SetPoint(point .. "LEFT", anchorBuff, relativePoint .. "LEFT", 0, -offsetY)
        self.buffz:ClearAllPoints()
        self.buffz:SetPoint(relativePoint .. "LEFT", buffName, relativePoint .. "LEFT", 0, -auraOffsetY)
        self.spellbarAnchor = buffName
    else
        buffName:SetPoint(point .. "LEFT", anchorBuff, point .. "RIGHT", offsetX, 0)
    end

    buffName:SetWidth(size)
    buffName:SetHeight(size)
end

local function UpdateDebuffAnchor(self, debuffName, numBuffs, anchorDebuff, size, offsetX, offsetY, mirrorVertically, newRow)
    local point, relativePoint
    local startY, auraOffsetY
    local isFriend = UnitIsFriend("player", self.unit)

    if mirrorVertically then
        point = "BOTTOM"
        relativePoint = "TOP"
        startY = -15
        if self.threatNumericIndicator:IsShown() then
            startY = startY + self.threatNumericIndicator:GetHeight()
        end
        offsetY = -offsetY
        auraOffsetY = -DeBuffFilter.db.profile.verticalSpace
    else
        point = "TOP"
        relativePoint = "BOTTOM"
        startY = AURA_START_Y
        auraOffsetY = DeBuffFilter.db.profile.verticalSpace
    end

    debuffName:ClearAllPoints()

    if anchorDebuff == nil then
        if (isFriend and not UnitIsEnemy("player", self.unit)) and numBuffs > 0 then
            debuffName:SetPoint(point .. "LEFT", self.buffz, relativePoint .. "LEFT", 0, -offsetY)
        else
            debuffName:SetPoint(point .. "LEFT", self, relativePoint .. "LEFT", AURA_START_X, startY)
        end
        self.debuffz:ClearAllPoints()
        self.debuffz:SetPoint(point .. "LEFT", debuffName, point .. "LEFT", 0, 0)
        self.debuffz:SetPoint(relativePoint .. "LEFT", debuffName, relativePoint .. "LEFT", 0, -auraOffsetY)
        if isFriend or (not isFriend and numBuffs == 0) then
            self.spellbarAnchor = debuffName
        end
    elseif newRow then
        debuffName:SetPoint(point .. "LEFT", anchorDebuff, relativePoint .. "LEFT", 0, -offsetY)
        self.debuffz:ClearAllPoints()
        self.debuffz:SetPoint(relativePoint .. "LEFT", debuffName, relativePoint .. "LEFT", 0, -auraOffsetY)
        if isFriend or (not isFriend and numBuffs == 0) then
            self.spellbarAnchor = debuffName
        end
    else
        debuffName:SetPoint(point .. "LEFT", anchorDebuff, point .. "RIGHT", offsetX, 0)
    end

    debuffName:SetWidth(size)
    debuffName:SetHeight(size)
    local debuffFrame = _G[debuffName:GetName() .. "Border"]
    if debuffFrame then
        debuffFrame:SetWidth(size + 2)
        debuffFrame:SetHeight(size + 2)
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
        if playerClass == "ROGUE" and (a.dispelName == "" and b.dispelName ~= "") then
            return true
        end
        if playerClass == "ROGUE" and (a.dispelName ~= "" and b.dispelName == "") then
            return false
        end
        if a.dispelName == "Magic" and b.dispelName ~= "Magic" then
            return true
        end
        if a.dispelName ~= "Magic" and b.dispelName == "Magic" then
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

function DeBuffFilter:TrackAuraDuration(frame, spellId, expirationTime, duration, settings)
    if not expirationTime or not duration then return end

    self._trackedAuras = self._trackedAuras or {}
    self._auraState = self._auraState or {}

    self._trackedAuras[frame] = self._trackedAuras[frame] or {}
    self._auraState[frame] = self._auraState[frame] or {}

    self._trackedAuras[frame][spellId] = {
        expiration = expirationTime,
        min = settings.minDuration or 0,
        max = settings.maxDuration or 0,
    }

    self._auraState[frame][spellId] = self._auraState[frame][spellId] or { entered = false, exited = false }
end



local function updateLayout(frame, auraName, numAuras, numOppositeAuras, updateFunc, offsetX, mirrorAurasVertically, shouldSort)
    local db = DeBuffFilter.db.profile
    local LARGE_AURA_SIZE = db.selfSize
    local SMALL_AURA_SIZE = db.otherSize
    local maxRowWidth = db.auraWidth
    local yDistance = db.verticalSpace
    local offsetY = yDistance
    local size, biggestAura
    local rowWidth = 0
    local anchorRowAura, lastBuff = nil, nil
    local haveToT = frame.totFrame and frame.totFrame:IsShown()
    local totFrameX, totFrameBottom = GetFramePosition(frame.totFrame)
    local currentX, currentY
    local frameName = frame.unit == "target" and "TargetFrame" or frame.unit == "focus" and "FocusFrame"
    local filter = (updateFunc == UpdateBuffAnchor) and "HELPFUL" or "HARMFUL"
    local processedSpellIDs = {}
    local auraList = {}

    for i = 1, numAuras do
        local aura
        if isClassic then
            local name, icon, count, dispelType, _, expirationTime, source, _, _, spellId = LibClassicDurations:UnitAura(frame.unit, i, filter)
            aura = { name = name, icon = icon, spellId = spellId, sourceUnit = source, dispelName = dispelType, expirationTime = expirationTime, applications = count }
        else
            aura = C_UnitAuras.GetAuraDataByIndex(frame.unit, i, filter)
        end

        if aura and aura.name and aura.icon then
            local dbf = _G[auraName .. i]
            local settings = DeBuffFilter:GetAuraFrameSettingsByAura(aura.name, aura.spellId, frameName)
            local filters = DeBuffFilter:GetSmartFilterSettings(aura.name, aura.spellId, frameName)
            local action = DeBuffFilter:CheckSmarterAuraFilters(aura.spellId, aura.name, aura.expirationTime, aura.applications, frameName, filters)
            local hide = (settings and settings.hide)
            local prio = settings and settings.priority or 0
            local sizeOverride

            if action then
                for _, v in ipairs(action) do
                    if v.hide then
                        hide = true
                    end
                    if v.size and v.size.enabled then
                        sizeOverride = v.size.value
                    end
                end
            end

            if filters then
                for _, settings in ipairs(filters) do
                    if settings.enableDurationFilter then
                        local timeLeft = aura.expirationTime and (aura.expirationTime - GetTime()) or 0
                        local duration = aura.duration or timeLeft
                        DeBuffFilter:TrackAuraDuration(frame, aura.spellId, aura.expirationTime, duration, settings)
                        break
                    end
                end
            end

            tinsert(auraList, {
                aura = aura,
                dbf = dbf,
                hide = hide,
                sizeOverride = sizeOverride,
                settings = settings,
                prio = prio,
                index = i,
                dispelName = aura.dispelName,
            })
        end
    end

    if shouldSort then
        tsort(auraList, combinedSort)
    end

    for _, data in ipairs(auraList) do
        local aura, dbf, settings = data.aura, data.dbf, data.settings
        local ownOnly = settings and settings.ownOnly
        local removeDuplicates = settings and settings.removeDuplicates

        if not data.hide and (not ownOnly or (aura.sourceUnit == "player")) and
                not (removeDuplicates and processedSpellIDs[aura.spellId]) then

            if removeDuplicates then
                processedSpellIDs[aura.spellId] = true
            end

            local shouldBeLarge = aura.sourceUnit and DeBuffFilter:ShouldAuraBeLarge(aura.sourceUnit)
            if shouldBeLarge then
                offsetY = yDistance * 2
            end

            size = data.sizeOverride
            if not size then
                if settings and settings.customSizeEnabled then
                    size = shouldBeLarge and settings.ownSize or settings.otherSize
                else
                    size = shouldBeLarge and LARGE_AURA_SIZE or SMALL_AURA_SIZE
                end
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
                horizontalDistance = mfloor(mabs((currentX + size + offsetX) - totFrameX)) + 5
            end

            if (haveToT and (horizontalDistance < size) and verticalDistance > 0) or (rowWidth > maxRowWidth) then
                if biggestAura and anchorRowAura and biggestAura >= mfloor(anchorRowAura:GetSize() + 0.5) then
                    offsetY = (yDistance * 2) + (biggestAura - anchorRowAura:GetSize())
                end
                updateFunc(frame, dbf, numOppositeAuras, anchorRowAura, size, offsetX, offsetY, mirrorAurasVertically, true)
                rowWidth = size
                frame.auraRows = frame.auraRows + 1
                anchorRowAura = dbf
                offsetY = yDistance
                biggestAura = nil
                frame.largestAura = nil
            else
                updateFunc(frame, dbf, numOppositeAuras, lastBuff, size, offsetX, offsetY, mirrorAurasVertically)
            end

            lastBuff = dbf
            currentX, currentY = dbf:GetLeft(), dbf:GetTop()

            if not biggestAura or biggestAura < size then
                biggestAura = size
            end
            local calc = (yDistance * 2) + (biggestAura - anchorRowAura:GetSize())
            if not frame.largestAura or frame.largestAura < calc then
                frame.largestAura = calc
            end
        elseif dbf then
            dbf:ClearAllPoints()
            dbf:SetPoint("CENTER", frame, "CENTER", 100000, 100000)
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
    local retailGlow = db.enableRetailGlow
    local texturePath = "Interface\\TargetingFrame\\UI-TargetingFrame-Stealable"

    for i = 1, MAX_TARGET_BUFFS do
        local buffName, icon, count, debuffType, duration, expirationTime, caster, canStealOrPurge, _, spellId = buffDetect(self.unit, i, "HELPFUL")
        if buffName then
            frameName = selfName .. "Buff" .. i
            frame = _G[frameName]
            local frameStealable = _G[frameName .. "Stealable"]
            local settings = DeBuffFilter:GetAuraFrameSettingsByAura(buffName, spellId, selfName)
            local filters = DeBuffFilter:GetSmartFilterSettings(buffName, spellId, selfName)
            local action = DeBuffFilter:CheckSmarterAuraFilters(spellId, buffName, expirationTime, count, selfName, filters)
            local shouldBeLarge = caster and DeBuffFilter:ShouldAuraBeLarge(caster)
            local buffSize = shouldBeLarge and db.selfSize or db.otherSize
            local actionSize, shouldHide, shouldGlow = nil, nil, nil

            if action then
                for _, action in ipairs(action) do
                    if action.hide then
                        shouldHide = true
                    end
                    if action.glow then
                        shouldGlow = true
                    end
                    if action.size and action.size.enabled then
                        buffSize = action.size.value
                        actionSize = true
                    end
                end
            end

            if not actionSize then
                if settings and settings.customSizeEnabled then
                    if shouldBeLarge then
                        buffSize = settings.ownSize
                    else
                        buffSize = settings.otherSize
                    end
                end
            end

            local modifier = 1.34
            local stockR, stockG, stockB = 1, 1, 1

            if isClassic then
                if not frame then
                    if not icon then
                        break
                    end
                    frame = CreateFrame("Button", frameName, self, "TargetBuffFrameTemplate")
                    frame.unit = self.unit
                end

                if icon and (not self.maxBuffs or i <= self.maxBuffs) then
                    frame:SetID(i)
                    frameIcon = _G[frameName .. "Icon"]
                    frameIcon:SetTexture(icon)
                    frameCount = _G[frameName .. "Count"]
                    if count and count > 1 and self.showAuraCount then
                        frameCount:SetText(count)
                        frameCount:Show()
                    else
                        frameCount:Hide()
                    end
                    frameCooldown = _G[frameName .. "Cooldown"]
                    CooldownFrame_Set(frameCooldown, expirationTime - duration, duration, duration > 0, true)
                    frame:ClearAllPoints()
                    frame:Show()

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
                elseif frame then
                    frame:Hide()
                end
            end

            if retailGlow then
                modifier = 2.06
                stockR, stockG, stockB = 1, 1, 0.75
                texturePath = "Interface\\AddOns\\DeBuffFilter\\newexp"
            end

            local showGlow = false
            if shouldGlow or (settings and settings.alwaysEnableGlow) then
                showGlow = true
            end

            if (db.customHighlight or showGlow) and frameStealable then
                if icon and (db.highlightAll and debuffType == "Magic" and isEnemy) or showGlow then
                    local hasCustomColor = settings and settings.color and (settings.color.r ~= 1 or settings.color.g ~= 1 or settings.color.b ~= 1 or settings.color.a ~= 1)
                    local r, g, b, a
                    if hasCustomColor then
                        r, g, b, a = settings.color.r, settings.color.g, settings.color.b, settings.color.a
                    else
                        r, g, b, a = 1, 1, 0.85, 1
                    end

                    frameStealable:Show()
                    frameStealable:SetHeight(buffSize * modifier)
                    frameStealable:SetWidth(buffSize * modifier)
                    frameStealable:SetVertexColor(r, g, b, a)
                    if retailGlow and not frameStealable.newTexture then
                        frameStealable.newTexture = true
                        frameStealable:SetTexture(texturePath)
                        frameStealable:SetTexCoord(0.338379, 0.412598, 0.680664, 0.829102)
                        frameStealable:SetDesaturated(true)
                    end
                elseif not playerIsTarget and isEnemy and canStealOrPurge then
                    frameStealable:Show()
                    frameStealable:SetHeight(buffSize * modifier)
                    frameStealable:SetWidth(buffSize * modifier)
                    frameStealable:SetVertexColor(stockR, stockG, stockB)
                    if retailGlow and not frameStealable.newTexture then
                        frameStealable.newTexture = true
                        frameStealable:SetTexture(texturePath)
                        frameStealable:SetTexCoord(0.338379, 0.412598, 0.680664, 0.829102)
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
                local countSize = db.enableFancyCount and db.countSize or (buffSize / 1.75)
                frameCount:SetFont(fontName, countSize, "OUTLINE, THICKOUTLINE, MONOCHROME")
                local color = db.countColor or {1, 1, 1}
                frameCount:SetVertexColor(color[1], color[2], color[3])
            end

            numBuffs = numBuffs + 1

            if not (settings and settings.hide) and not shouldHide then
                numBuff = numBuff + 1
            end

        else
            break
        end
    end

    local frameNum, index = 1, 1
    local maxDebuffs = self.maxDebuffs or MAX_TARGET_DEBUFFS

    while frameNum <= maxDebuffs and index <= maxDebuffs do
        local debuffName, icon, count, debuffType, duration, expirationTime, caster, _, _, spellId, _, _, casterIsPlayer, nameplateShowAll = UnitDebuff(self.unit, index, "INCLUDE_NAME_PLATE_ONLY")
        if debuffName then
            if icon and TargetFrame_ShouldShowDebuffs(self.unit, caster, nameplateShowAll, casterIsPlayer) then
                frameName = selfName .. "Debuff" .. frameNum
                frame = _G[frameName]
                local debuffBorder = _G[frameName .. "Border"]
                local settings = DeBuffFilter:GetAuraFrameSettingsByAura(debuffName, spellId, selfName)
                local filters = DeBuffFilter:GetSmartFilterSettings(debuffName, spellId, selfName)
                local action = DeBuffFilter:CheckSmarterAuraFilters(spellId, debuffName, expirationTime, count, selfName, filters)
                local shouldBeLarge = caster and DeBuffFilter:ShouldAuraBeLarge(caster)
                local modifier = 1.34
                local buffSize = shouldBeLarge and db.selfSize or db.otherSize
                local actionSize, shouldHide, shouldGlow = nil, nil, nil

                if action then
                    for _, action in ipairs(action) do
                        if action.hide then
                            shouldHide = true
                        end
                        if action.glow then
                            shouldGlow = true
                        end
                        if action.size and action.size.enabled then
                            buffSize = action.size.value
                            actionSize = true
                        end
                    end
                end

                if not actionSize then
                    if settings and settings.customSizeEnabled then
                        if shouldBeLarge then
                            buffSize = settings.ownSize
                        else
                            buffSize = settings.otherSize
                        end
                    end
                end

                if retailGlow then
                    modifier = 2.06
                    texturePath = "Interface\\AddOns\\DeBuffFilter\\newexp"
                end

                local showGlow = false
                if shouldGlow or (settings and settings.alwaysEnableGlow) then
                    showGlow = true
                end

                if db.customHighlight and showGlow then
                    local frameStealable = _G[frameName .. "Stealable"]
                    local hasCustomColor = settings and settings.color and (settings.color.r ~= 1 or settings.color.g ~= 1 or settings.color.b ~= 1 or settings.color.a ~= 1)

                    if not frameStealable and frame and hasCustomColor then
                        frameStealable = frame:CreateTexture(frameName .. "Stealable", "OVERLAY")
                        frameStealable:SetTexture(texturePath)
                        if retailGlow then
                            frameStealable:SetTexCoord(0.338379, 0.412598, 0.680664, 0.829102)
                        end
                        frameStealable:SetPoint("CENTER", 0, 0)
                        frameStealable:SetBlendMode("ADD")
                    end

                    if frameStealable then
                        local r, g, b, a
                        if hasCustomColor then
                            r, g, b, a = settings.color.r, settings.color.g, settings.color.b, settings.color.a
                        else
                            r, g, b, a = 1, 1, 0.85, 1
                        end
                        frameStealable:Show()
                        frameStealable:SetHeight(buffSize * modifier)
                        frameStealable:SetWidth(buffSize * modifier)
                        frameStealable:SetVertexColor(r, g, b, a)

                        if debuffBorder then
                            debuffBorder:SetShown(r == 0 and g == 0 and b == 0 or a == 0)
                        end

                        if retailGlow then
                            frameStealable:SetDesaturated(true)
                        end
                    else
                        if frameStealable then
                            frameStealable:Hide()
                        end
                        if debuffBorder then
                            debuffBorder:Show()
                        end
                    end
                end

                local frameCount = _G[frameName .. "Count"]
                if frameCount then
                    if not fontName then
                        fontName = frameCount:GetFont()
                    end
                    frameCount:SetFont(fontName, buffSize / 1.75, "OUTLINE, THICKOUTLINE, MONOCHROME")

                    local color = db.countColor or {1, 1, 1}
                    frameCount:SetVertexColor(color[1], color[2], color[3])
                end

                numDebuffs = numDebuffs + 1
                frameNum = frameNum + 1

                if not (settings and settings.hide) and not shouldHide then
                    numDebuff = numDebuff + 1
                end
            end
        else
            break
        end
        index = index + 1
    end

    local mirrorAurasVertically = self.buffsOnTop and true or false
    local db = DeBuffFilter.db.profile
    local offsetX = db.horizontalSpace

    self.auraRows = 0
    self.largestAura = 0
    self.spellbarAnchor = nil

    if not self.buffz then
        self.buffz = CreateFrame("Frame", "$parentBuffz", self)
        self.buffz:SetSize(10, 10)
    end

    if not self.debuffz then
        self.debuffz = CreateFrame("Frame", "$parentDebuffz", self)
        self.debuffz:SetSize(10, 10)
    end

    local sortOrDefault = (db.sortBySize or db.sortbyDispellable or db.enablePrioritySort)

    if isEnemy then
        updateLayout(self, selfName .. "Debuff", numDebuffs, numBuff, UpdateDebuffAnchor, offsetX, mirrorAurasVertically, sortOrDefault)
        updateLayout(self, selfName .. "Buff", numBuffs, numDebuff, UpdateBuffAnchor, offsetX, mirrorAurasVertically, sortOrDefault)
    else
        updateLayout(self, selfName .. "Buff", numBuffs, numDebuff, UpdateBuffAnchor, offsetX, mirrorAurasVertically, sortOrDefault)
        updateLayout(self, selfName .. "Debuff", numDebuffs, numBuff, UpdateDebuffAnchor, offsetX, mirrorAurasVertically, sortOrDefault)
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
        LibClassicDurations = LibStub("LibClassicDurations", true)
        LibClassicDurations:RegisterFrame(AddonName)
        LibClassicDurations.RegisterCallback(DBF, "UNIT_BUFF", function(event, unit)
            TargetFrame_UpdateAuras(TargetFrame)
        end)
    end

    hooksecurefunc("TargetFrame_UpdateAuras", Filterino)

    for _, v in pairs({ TargetFrameSpellBar, FocusFrameSpellBar }) do
        if v then
            hooksecurefunc(v, "SetPoint", function(self)
                if self.busy then
                    return
                end
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

    if db.disableFade then
        hooksecurefunc("AuraButton_OnUpdate", function(frame)
            if frame:GetAlpha() < 1 then
                frame:SetAlpha(1)
            end
        end)
    end

    playerClass = select(2, UnitClass("player"))
end)

local interval = 0.1
local lastUpdate = 0
DeBuffFilter.event:SetScript("OnUpdate", function(self, elapsed)
    lastUpdate = lastUpdate + elapsed
    if lastUpdate < interval then return end
    lastUpdatef = 0

    local now = GetTime()
    local stateTable = DeBuffFilter._auraState or {}
    local tracked = DeBuffFilter._trackedAuras or {}

    for frame, spells in pairs(tracked) do
        for spellId, data in pairs(spells) do
            local timeLeft = data.expiration - now

            stateTable[frame] = stateTable[frame] or {}
            local state = stateTable[frame][spellId]

            if not state or state.expiration ~= data.expiration then
                state = {
                    entered = false,
                    exited = false,
                    expiration = data.expiration,
                }
                stateTable[frame][spellId] = state
            end

            if not state.entered and timeLeft <= data.max then
                state.entered = true
                if frame == TargetFrame or frame == FocusFrame then
                    TargetFrame_UpdateAuras(frame)
                elseif frame == BuffFrame then
                    BuffFrame_Update()
                end
            end

            if not state.exited and timeLeft <= data.min then
                state.exited = true
                state.entered = true
                if frame == TargetFrame or frame == FocusFrame then
                    TargetFrame_UpdateAuras(frame)
                elseif frame == BuffFrame then
                    BuffFrame_Update()
                end
            end

            if timeLeft <= 0 then
                spells[spellId] = nil
                stateTable[frame][spellId] = nil
            end
        end
    end

    DeBuffFilter._auraState = stateTable
end)

