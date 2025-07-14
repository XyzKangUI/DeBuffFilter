local AddonName = "DeBuffFilter"

local DeBuffFilter = LibStub:GetLibrary(AddonName, true)
local BUFF_BUTTON_HEIGHT = 30
local BUFF_HORIZ_SPACING = -5
local format, gsub = string.format, string.gsub

local function durationPos(duration)
    local xPos = DeBuffFilter.db.profile.buffFrameDurationXPos or 0
    local yPos = DeBuffFilter.db.profile.buffFrameDurationYPos or -18

    duration:ClearAllPoints()
    duration:SetPoint("BOTTOM", duration:GetParent(), "BOTTOM", xPos, yPos)
end

local function New_BuffFrame_UpdateAllBuffAnchors()
    local buff, previousBuff, aboveBuff, index
    local processedSpellIDs = {}
    local numBuffs = 0;
    local numAuraRows = 0;
    local slack = BuffFrame.numEnchants
    if BuffFrame.numConsolidated and (BuffFrame.numConsolidated > 0) then
        slack = slack + 1;    -- one icon for all consolidated buffs
    end
    local BUFFS_PER_ROW = DeBuffFilter.db.profile.buffFrameBuffsPerRow

    for i = 1, BUFF_ACTUAL_DISPLAY do
        buff = _G["BuffButton" .. i];
        local parent = buff and buff.parent
        local auraData = C_UnitAuras.GetAuraDataByIndex("player", i, "HELPFUL")
        if not auraData or not auraData.name then
            return
        end

        local filters = DeBuffFilter:GetSmartFilterSettings(auraData.name, auraData.spellId, "BuffFrame")
        local action = DeBuffFilter:CheckSmarterAuraFilters(auraData.spellId, auraData.name, auraData.expirationTime, auraData.applications, "BuffFrame", filters)
        local frameSettings = filters._frameSettings
        local shouldBeLarge = auraData.sourceUnit and DeBuffFilter:ShouldAuraBeLarge(auraData.sourceUnit)
        local shouldHide, buffSize, shouldGlow, colorTable = false, 30, false, { r = 1, g = 1, b = 0.85, a = 1 }
        local removeDuplicates, ownOnly = false, false

        if action then
            for _, action in ipairs(action) do
                if action.hide then
                    shouldHide = true
                end
                if action.glow then
                    shouldGlow = true
                end
                if action.size and action.size.enabled then
                    if shouldBeLarge then
                        buffSize = action.selfSize or action.otherSize or 21
                    else
                        buffSize = action.otherSize or action.selfSize or 19
                    end
                end
            end
        end

        if frameSettings then
            if frameSettings.removeDuplicates then removeDuplicates = true end
            if frameSettings.ownOnly then ownOnly = true end
            if frameSettings.alwaysEnableGlow then shouldGlow = true end
            if frameSettings.color then colorTable = frameSettings.color end
        end

        if shouldHide or (ownOnly and auraData.sourceUnit ~= "player") or removeDuplicates then
            buff:ClearAllPoints()
            buff:SetPoint("TOPRIGHT", ConsolidatedBuffs, "TOPLEFT", 0, 10000);
        else
            if removeDuplicates then
                processedSpellIDs[auraData.spellId] = true
            end

            buff:SetSize(buffSize, buffSize)

            if filters then
                for _, settings in ipairs(filters) do
                    if settings.enableDurationFilter then
                        local timeLeft = auraData.expirationTime and (auraData.expirationTime - GetTime()) or 0
                        local duration = auraData.duration or timeLeft
                        DeBuffFilter:TrackAuraDuration(_G["BuffFrame"], auraData.spellId, auraData.expirationTime, duration, settings)
                        break
                    end
                end
            end

            if (buff.consolidated) then
                if (parent == BuffFrame) then
                    buff:SetParent(ConsolidatedBuffsContainer);
                    parent = ConsolidatedBuffsContainer;
                end
            else
                numBuffs = numBuffs + 1;
                index = numBuffs + slack;
                if (parent ~= BuffFrame) then
                    buff.count:SetFontObject(NumberFontNormal);
                    buff:SetParent(BuffFrame);
                    parent = BuffFrame;
                end
                buff:ClearAllPoints();
                if ((index > 1) and (mod(index, BUFFS_PER_ROW) == 1)) then
                    -- New row
                    if (index == BUFFS_PER_ROW + 1) then
                        buff:SetPoint("TOPRIGHT", ConsolidatedBuffs, "BOTTOMRIGHT", 0, -BUFF_ROW_SPACING);
                    else
                        buff:SetPoint("TOPRIGHT", aboveBuff, "BOTTOMRIGHT", 0, -BUFF_ROW_SPACING);
                    end
                    aboveBuff = buff;
                elseif (index == 1) then
                    numAuraRows = 1;
                    buff:SetPoint("TOPRIGHT", BuffFrame, "TOPRIGHT", 0, 0);
                    aboveBuff = buff;
                else
                    if (numBuffs == 1) then
                        if (BuffFrame.numEnchants > 0) then
                            buff:SetPoint("TOPRIGHT", "TemporaryEnchantFrame", "TOPLEFT", BUFF_HORIZ_SPACING, 0);
                            aboveBuff = TemporaryEnchantFrame;
                        else
                            buff:SetPoint("TOPRIGHT", ConsolidatedBuffs, "TOPLEFT", BUFF_HORIZ_SPACING, 0);
                        end
                    else
                        buff:SetPoint("RIGHT", previousBuff, "LEFT", BUFF_HORIZ_SPACING, 0);
                    end
                end
                previousBuff = buff;
            end
        end

        local highlightBorder = buff.highlightBorder

        if shouldGlow then
            local r, g, b, a = colorTable.r, colorTable.g, colorTable.b, colorTable.a
            local retailGlow = DeBuffFilter.db.profile.enableRetailGlow
            if not highlightBorder then
                highlightBorder = buff:CreateTexture(nil, "OVERLAY", nil, 7)
                if retailGlow then
                    highlightBorder:SetTexture("Interface\\AddOns\\DeBuffFilter\\newexp")
                    highlightBorder:SetTexCoord(0.338379, 0.412598, 0.680664, 0.829102)
                    highlightBorder:SetDesaturated(true)
                else
                    highlightBorder:SetTexture("Interface\\TargetingFrame\\UI-TargetingFrame-Stealable")
                end
                highlightBorder:SetPoint("CENTER", 0, 0)
                highlightBorder:SetBlendMode("ADD")
                buff.highlightBorder = highlightBorder
            end
            local xw, hw = buff:GetSize()
            local modifier = retailGlow and 2.06 or 1.34
            highlightBorder:SetSize(xw * modifier, hw * modifier)
            highlightBorder:SetVertexColor(r, g, b, a)
            highlightBorder:Show()
        else
            if highlightBorder then
                highlightBorder:Hide()
            end
        end

        if not buff.posChanged and DeBuffFilter.db.profile.enableMovingDuration then
            buff.posChanged = true
            hooksecurefunc(buff.duration, "SetFormattedText", durationPos)
        end
    end
end

local function New_DebuffButton_UpdateAnchors(buttonName, index)
    local numBuffs = BUFF_ACTUAL_DISPLAY + BuffFrame.numEnchants;
    if BuffFrame.numConsolidated and (BuffFrame.numConsolidated > 0) then
        numBuffs = numBuffs - BuffFrame.numConsolidated + 1;
    end

    local BUFFS_PER_ROW = DeBuffFilter.db.profile.buffFrameBuffsPerRow
    local processedSpellIDs = {}
    local rows = ceil(numBuffs / BUFFS_PER_ROW);
    local offsetY, previousBuff
    local numDebuffs = 0

    -- Position debuffs
    for i = 1, DEBUFF_MAX_DISPLAY do
        local buff = _G[buttonName .. i];
        if not buff then
            return
        end
        local auraData = C_UnitAuras.GetAuraDataByIndex("player", i, "HARMFUL")
        if not auraData or not auraData.name then
            return
        end

        local action, frameSettings = DeBuffFilter:CheckSmarterAuraFilters(auraData.spellId, auraData.name, auraData.expirationTime, auraData.applications, "BuffFrame")
        if not frameSettings then frameSettings = {} end
        local shouldBeLarge = auraData.sourceUnit and DeBuffFilter:ShouldAuraBeLarge(auraData.sourceUnit)
        local shouldHide, buffSize, shouldGlow, colorTable = false, 30, false, { r = 1, g = 1, b = 0.85, a = 1 }
        local removeDuplicates, ownOnly = false, false

        if action then
            for _, action in ipairs(action) do
                if action.hide then
                    shouldHide = true
                end
                if action.glow then
                    shouldGlow = true
                end
                if action.size and action.size.enabled then
                    if shouldBeLarge then
                        buffSize = action.selfSize or action.otherSize or 21
                    else
                        buffSize = action.otherSize or action.selfSize or 19
                    end
                end
            end
        end

        if frameSettings then
            if frameSettings.removeDuplicates then removeDuplicates = true end
            if frameSettings.ownOnly then ownOnly = true end
            if frameSettings.alwaysEnableGlow then shouldGlow = true end
            if frameSettings.color then colorTable = frameSettings.color end
        end

        if shouldHide or (ownOnly and auraData.source ~= "player") or removeDuplicates then
            buff:ClearAllPoints()
            buff:SetPoint("TOPRIGHT", ConsolidatedBuffs, "TOPLEFT", 0, 10000);
        else
            if removeDuplicates then
                processedSpellIDs[auraData.spellId] = true
            end

            buff:SetSize(buffSize, buffSize)

            if filters then
                for _, settings in ipairs(filters) do
                    if settings.enableDurationFilter then
                        local timeLeft = auraData.expirationTime and (auraData.expirationTime - GetTime()) or 0
                        local duration = auraData.duration or timeLeft
                        DeBuffFilter:TrackAuraDuration(_G["BuffFrame"], auraData.spellId, auraData.expirationTime, duration, settings)
                        break
                    end
                end
            end

            buff:ClearAllPoints()
            numDebuffs = numDebuffs + 1
            local index = numDebuffs
            if ((index > 1) and (mod(index, BUFFS_PER_ROW) == 1)) then
                -- New row
                buff:SetPoint("TOP", _G[buttonName .. (index - BUFFS_PER_ROW)], "BOTTOM", 0, -BUFF_ROW_SPACING);
            elseif (index == 1) then
                if (rows < 2) then
                    offsetY = 1 * ((2 * BUFF_ROW_SPACING) + BUFF_BUTTON_HEIGHT);
                else
                    offsetY = rows * (BUFF_ROW_SPACING + BUFF_BUTTON_HEIGHT);
                end
                buff:SetPoint("TOPRIGHT", BuffFrame, "BOTTOMRIGHT", 0, -offsetY);
            else
                buff:SetPoint("RIGHT", previousBuff, "LEFT", -5, 0);
            end
            previousBuff = buff
        end

        local highlightBorder = buff.highlightBorder
        local border = _G[buff:GetName().."Border"]

        if shouldGlow then
            local r, g, b, a = colorTable.r, colorTable.g, colorTable.b, colorTable.a
            local retailGlow = DeBuffFilter.db.profile.enableRetailGlow

            if not highlightBorder then
                highlightBorder = buff:CreateTexture(nil, "OVERLAY", nil, 7)
                if retailGlow then
                    highlightBorder:SetTexture("Interface\\AddOns\\DeBuffFilter\\newexp")
                    highlightBorder:SetTexCoord(0.338379, 0.412598, 0.680664, 0.829102)
                    highlightBorder:SetDesaturated(true)
                else
                    highlightBorder:SetTexture("Interface\\TargetingFrame\\UI-TargetingFrame-Stealable")
                end
                highlightBorder:SetPoint("CENTER", 0, 0)
                highlightBorder:SetBlendMode("ADD")
                buff.highlightBorder = highlightBorder
            end

            local xw, hw = buff:GetSize()
            local modifier = retailGlow and 2.06 or 1.34
            highlightBorder:SetSize(xw * modifier, hw * modifier)
            highlightBorder:SetVertexColor(r, g, b, a)
            highlightBorder:Show()
            if border then
                border:Hide()
            end
        else
            if highlightBorder then
                highlightBorder:Hide()
            end
            if border then
                border:Show()
            end
        end

        if not buff.posChanged and DeBuffFilter.db.profile.enableMovingDuration then
            buff.posChanged = true
            hooksecurefunc(buff.duration, "SetFormattedText", durationPos)
        end
    end
end

hooksecurefunc("BuffFrame_UpdateAllBuffAnchors", New_BuffFrame_UpdateAllBuffAnchors)
hooksecurefunc("DebuffButton_UpdateAnchors", New_DebuffButton_UpdateAnchors);