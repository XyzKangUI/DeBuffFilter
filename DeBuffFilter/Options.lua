local AddonName = "DeBuffFilter"

local DeBuffFilter = LibStub:NewLibrary(AddonName, 8)
local GetAddOnMetadata = C_AddOns and C_AddOns.GetAddOnMetadata or GetAddOnMetadata
local tinsert, tsort, tostring, wipe = table.insert, table.sort, tostring, table.wipe
local lastTime = 0

local function updateCastbarPosition(bar, val, xPos)
    if not bar:IsShown() then
        bar:SetAlpha(1)
        bar:Show()
    end
    local a, b, c, d, e = bar:GetPoint()
    bar:ClearAllPoints()
    if xPos then
        bar:SetPoint(a, b, c, val, e)
    else
        bar:SetPoint(a, b, c, d, val)
    end
    lastTime = GetTime()
    C_Timer.After(3, function()
        if (GetTime() - lastTime) > 2 then
            bar:SetAlpha(0)
            bar:Hide()
        end
    end)
end

local defaults = {
    profile = {
        hiddenBuffs = {},
        selfSize = 21,
        otherSize = 20,
        auraWidth = 122,
        verticalSpace = 1,
        horizontalSpace = 3,
        customHighlights = {},
        customHighlightColors = {},
        customSizes = {},
        sortBySize = false,
        sortbyDispellable = false,
        highlightAll = false,
        enablePrioritySort = false,
        customHighlightPriorities = {},
        customShowOwnOnly = {},
        removeDuplicates = {},
        focusBarPosX = 0,
        focusBarPosY = 0,
        targetBarPosX = 0,
        targetBarPosY = 0,
        targetCastBarSize = 1,
        focusCastBarSize = 1,
    }
}

function DeBuffFilter:AddCustomHighlightOptions()
    local new_args = {}

    for _, buff in ipairs(self.db.profile.customHighlights) do
        local buffName = tonumber(buff) and GetSpellInfo(buff) .. " (" .. buff .. ")" or buff

        local customSize = self.db.profile.customSizes[buff] or {}
        self.db.profile.customSizes[buff] = customSize

        customSize.enabled = customSize.enabled or false
        customSize.ownSize = customSize.ownSize or self.db.profile.selfSize
        customSize.otherSize = customSize.otherSize or self.db.profile.otherSize

        new_args["highlight_" .. buff] = {
            type = "group",
            name = buffName,
            args = {
                delete = {
                    order = 1,
                    type = "execute",
                    width = "0.5",
                    name = "Delete",
                    func = function()
                        local cur_index = 0
                        for i, value in ipairs(self.db.profile.customHighlights) do
                            if value == buff then
                                cur_index = i
                                break
                            end
                        end
                        if cur_index > 0 then
                            table.remove(self.db.profile.customHighlights, cur_index)
                            self.db.profile.customHighlightColors[buff] = nil
                            self.db.profile.customSizes[buff] = nil
                            self.options.args.highlightBuffs.args.buffList.args = self:AddCustomHighlightOptions()
                        end
                    end
                },
                color = {
                    order = 2,
                    type = "color",
                    name = "Color",
                    get = function(info)
                        local color = self.db.profile.customHighlightColors[buff]
                        if not color then
                            color = { r = 1, g = 1, b = 1, a = 1 }
                            self.db.profile.customHighlightColors[buff] = color
                        end
                        return color.r, color.g, color.b, color.a
                    end,
                    set = function(info, r, g, b, a)
                        self.db.profile.customHighlightColors[buff] = { r = r, g = g, b = b, a = a }
                        TargetFrame_UpdateAuras(TargetFrame)
                        if FocusFrame then
                            TargetFrame_UpdateAuras(FocusFrame)
                        end
                    end,
                },
                customSizeToggle = {
                    order = 3,
                    type = "toggle",
                    width = "full",
                    name = "Enable custom sizing",
                    get = function(info)
                        return self.db.profile.customSizes[buff].enabled
                    end,
                    set = function(info, val)
                        self.db.profile.customSizes[buff].enabled = val
                        if val == false then
                            self.db.profile.customSizes[buff] = {
                                ownSize = self.db.profile.selfSize,
                                otherSize = self.db.profile.otherSize
                            }
                        end
                    end,
                },
                ownAuraSize = {
                    order = 4,
                    type = "range",
                    width = 1.2,
                    name = "Personal aura size",
                    desc = "Change this aura's size when cast by you",
                    min = 17,
                    max = 34,
                    step = 1,
                    get = function(info)
                        local size = self.db.profile.customSizes[buff].ownSize
                        if not size then
                            size = self.db.profile.selfSize
                            self.db.profile.customSizes[buff].ownSize = size
                        end
                        return size
                    end,
                    set = function(info, val)
                        self.db.profile.customSizes[buff].ownSize = val
                        TargetFrame_UpdateAuras(TargetFrame)
                        if FocusFrame then
                            TargetFrame_UpdateAuras(FocusFrame)
                        end
                    end,
                    hidden = function()
                        return not self.db.profile.customSizes[buff].enabled
                    end,
                },
                otherAuraSize = {
                    order = 4.5,
                    type = "range",
                    width = 1.2,
                    name = "Other's aura size",
                    desc = "Change this aura's size when cast by others",
                    min = 17,
                    max = 34,
                    step = 1,
                    get = function(info)
                        local size = self.db.profile.customSizes[buff].otherSize
                        if not size then
                            size = self.db.profile.otherSize
                            self.db.profile.customSizes[buff].otherSize = size
                        end
                        return size
                    end,
                    set = function(info, val)
                        self.db.profile.customSizes[buff].otherSize = val
                        TargetFrame_UpdateAuras(TargetFrame)
                        if FocusFrame then
                            TargetFrame_UpdateAuras(FocusFrame)
                        end
                    end,
                    hidden = function()
                        return not self.db.profile.customSizes[buff].enabled
                    end,
                },
                priority = {
                    order = 5,
                    type = "range",
                    width = 2,
                    name = "Priority",
                    desc = "Set the priority of the aura",
                    min = 0,
                    max = 100,
                    step = 1,
                    get = function(info)
                        local priority = self.db.profile.customHighlightPriorities[buff]
                        if not priority then
                            priority = 0
                            self.db.profile.customHighlightPriorities[buff] = priority
                        end
                        return priority
                    end,
                    set = function(info, val)
                        self.db.profile.customHighlightPriorities[buff] = val
                        TargetFrame_UpdateAuras(TargetFrame)
                        if FocusFrame then
                            TargetFrame_UpdateAuras(FocusFrame)
                        end
                    end,
                    hidden = function()
                        return not self.db.profile.enablePrioritySort
                    end,
                },
                separator = {
                    order = 6,
                    type = "description",
                    name = "\n",
                    width = "full"
                },
                ownOnly = {
                    order = 7,
                    type = "toggle",
                    name = "Show own buff only",
                    desc = "Hides the aura when it is not applied by you",
                    get = function(info)
                        return self.db.profile.customShowOwnOnly[buff]
                    end,
                    set = function(info, val)
                        self.db.profile.customShowOwnOnly[buff] = val
                    end,
                },
                removeDuplicates = {
                    order = 8,
                    type = "toggle",
                    name = "Hide duplicate auras",
                    desc = "Hides duplicate effects of this aura",
                    get = function(info)
                        return self.db.profile.removeDuplicates[buff]
                    end,
                    set = function(info, val)
                        self.db.profile.removeDuplicates[buff] = val
                    end,
                },
                spellTitle = {
                    order = 0.5,
                    type = "description",
                    name = buffName,
                    fontSize = "medium",
                    width = "full",
                },
            },
        }
    end

    return new_args
end

function DeBuffFilter:SetupOptions()
    self.db = LibStub("AceDB-3.0"):New("DeBuffFilterDB", defaults, true)

    self.options = {
        type = "group",
        childGroups = "tab",
        plugins = {},
        args = {
            author = {
                name = "|cff4693E6Author:|r Xyz - discord.gg/CtxPasSQnQ",
                type = "description"
            },
            version = {
                name = "|cff4693E6Version:|r " .. GetAddOnMetadata("DeBuffFilter", "Version") .. "\n",
                type = "description"
            },
            moreoptions = {
                name = "Hide Auras",
                type = "group",
                order = 1,
                args = {
                    buffNameInput = {
                        order = 1,
                        width = 1.5,
                        name = "Add (De)Buff By Name / Spell Id",
                        desc = "Type the name or spell id of a (de)buff to hide",
                        type = "input",
                        set = function(info, val)
                            if tonumber(val) then
                                if not GetSpellInfo(val) then
                                    return
                                end
                                val = tostring(val)
                            end

                            for _, value in ipairs(self.db.profile.hiddenBuffs) do
                                if value == val then
                                    return
                                end
                            end

                            tinsert(self.db.profile.hiddenBuffs, val);
                            tsort(self.db.profile.hiddenBuffs)
                            TargetFrame_UpdateAuras(TargetFrame);
                            if FocusFrame then
                                TargetFrame_UpdateAuras(FocusFrame)
                            end
                        end,
                    },
                    buffList = {
                        order = 3,
                        width = 1,
                        name = "Hidden Auras:",
                        type = "multiselect",
                        values = function()
                            local list = {}
                            for _, value in pairs(self.db.profile.hiddenBuffs) do
                                local spellName = GetSpellInfo(value)
                                if spellName then
                                    list[value] = spellName .. " (" .. value .. ")"
                                else
                                    list[value] = value
                                end
                            end
                            return list
                        end,
                        get = function(info, val)
                            return true;
                        end,
                        set = function(info, val)
                            for index, spellID in ipairs(self.db.profile.hiddenBuffs) do
                                if spellID == val then
                                    table.remove(self.db.profile.hiddenBuffs, index)
                                    break
                                end
                            end
                        end,
                        confirm = function(info, val, v2)
                            local spellName = GetSpellInfo(val) or val
                            return "Delete " .. spellName .. " (" .. val .. ")?"
                        end
                    },
                },
            },
            sizeoptions = {
                name = "General Settings",
                type = "group",
                order = 2,
                args = {
                    fancySliders = {
                        order = 1,
                        type = "group",
                        inline = false,
                        name = "Resizer",
                        args = {
                            selfSize = {
                                order = 1,
                                width = 2,
                                name = "My Debuffs/Buffs size",
                                desc = "Resize your own (de)buffs displayed on target",
                                type = "range",
                                min = 17,
                                max = 34,
                                step = 1,
                                get = function(info, val)
                                    return self.db.profile.selfSize
                                end,
                                set = function(info, val)
                                    self.db.profile.selfSize = val
                                    TargetFrame_UpdateAuras(TargetFrame);
                                    if FocusFrame then
                                        TargetFrame_UpdateAuras(FocusFrame)
                                    end
                                end
                            },
                            otherSize = {
                                order = 2,
                                width = 2,
                                name = "Others Debuffs/Buffs size",
                                desc = "Resize the (de)buffs casted by others that are displayed on target",
                                type = "range",
                                min = 17,
                                max = 34,
                                step = 1,
                                get = function(info, val)
                                    return self.db.profile.otherSize
                                end,
                                set = function(info, val)
                                    self.db.profile.otherSize = val
                                    TargetFrame_UpdateAuras(TargetFrame);
                                    if FocusFrame then
                                        TargetFrame_UpdateAuras(FocusFrame)
                                    end
                                end
                            },
                            auraWidth = {
                                order = 3,
                                width = 2,
                                name = "Aura row width",
                                desc = "How many auras do you want per row?",
                                type = "range",
                                min = 108,
                                max = 178,
                                step = 14,
                                get = function(info, val)
                                    return self.db.profile.auraWidth
                                end,
                                set = function(info, val)
                                    self.db.profile.auraWidth = val
                                    TargetFrame_UpdateAuras(TargetFrame);
                                    if FocusFrame then
                                        TargetFrame_UpdateAuras(FocusFrame)
                                    end
                                end
                            },
                            verticalSpacing = {
                                order = 4,
                                width = 2,
                                name = "Vertical spacing",
                                desc = "The spacing between aura rows",
                                type = "range",
                                min = 1,
                                max = 50,
                                step = 1,
                                get = function(info, val)
                                    return self.db.profile.verticalSpace
                                end,
                                set = function(info, val)
                                    self.db.profile.verticalSpace = val
                                    TargetFrame_UpdateAuras(TargetFrame);
                                    if FocusFrame then
                                        TargetFrame_UpdateAuras(FocusFrame)
                                    end
                                end
                            },
                            horizontalSpacing = {
                                order = 5,
                                width = 2,
                                name = "Horizontal spacing",
                                desc = "The spacing between auras",
                                type = "range",
                                min = 3,
                                max = 35,
                                step = 1,
                                get = function(info, val)
                                    return self.db.profile.horizontalSpace
                                end,
                                set = function(info, val)
                                    self.db.profile.horizontalSpace = val
                                    TargetFrame_UpdateAuras(TargetFrame);
                                    if FocusFrame then
                                        TargetFrame_UpdateAuras(FocusFrame)
                                    end
                                end
                            },
                        },
                    },
                    fancyCheckboxes = {
                        order = 2,
                        type = "group",
                        inline = false,
                        name = "Sorting options",
                        args = {
                            sortBySize = {
                                order = 1,
                                type = "toggle",
                                name = "Sort auras by size",
                                desc = "Recommended when using a different size per aura",
                                get = function()
                                    return self.db.profile.sortBySize
                                end,
                                set = function(_, value)
                                    self.db.profile.sortBySize = value
                                end,
                            },
                            sortbyDispellable = {
                                order = 2,
                                type = "toggle",
                                name = "Sort by dispellable",
                                desc = "Shows dispellable buffs first, unless size or priority sorting is enabled",
                                get = function()
                                    return self.db.profile.sortbyDispellable
                                end,
                                set = function(_, value)
                                    self.db.profile.sortbyDispellable = value
                                end,
                            },
                            highlightAll = {
                                order = 3,
                                type = "toggle",
                                name = "Highlight magic buffs",
                                desc = "Shows a glowing border on all dispellable magic buffs",
                                get = function()
                                    return self.db.profile.highlightAll
                                end,
                                set = function(_, value)
                                    self.db.profile.highlightAll = value
                                end,
                            },
                            enablePrioritySort = {
                                order = 4,
                                type = "toggle",
                                name = "Enable priority slider",
                                desc = "When enabled 'auras-specific customizations' will display an extra slider",
                                get = function()
                                    return self.db.profile.enablePrioritySort
                                end,
                                set = function(_, value)
                                    self.db.profile.enablePrioritySort = value
                                end,
                            },
                        },
                    },
                    fancyCastBar = {
                        order = 3,
                        type = "group",
                        inline = false,
                        name = "Castbar settings",
                        args = {
                            targetSpellbarPosX = {
                                order = 1,
                                width = 1.5,
                                name = "Target spellbar horizontal position",
                                desc = "Set horizontal & vertical to 0 for default behaviour",
                                type = "range",
                                min = -300,
                                max = 300,
                                step = 1,
                                get = function(info, val)
                                    return self.db.profile.targetBarPosX
                                end,
                                set = function(info, val)
                                    self.db.profile.targetBarPosX = val
                                    updateCastbarPosition(TargetFrameSpellBar, val, true)
                                end
                            },
                            targetSpellbarPosY = {
                                order = 2,
                                width = 1.5,
                                name = "Target spellbar vertical position",
                                desc = "Set horizontal & vertical to 0 for default behaviour",
                                type = "range",
                                min = -300,
                                max = 300,
                                step = 1,
                                get = function(info, val)
                                    return self.db.profile.targetBarPosY
                                end,
                                set = function(info, val)
                                    self.db.profile.targetBarPosY = val
                                    updateCastbarPosition(TargetFrameSpellBar, val, false)
                                end
                            },
                            focusSpellbarPosX = {
                                order = 3,
                                width = 1.5,
                                name = "Focus spellbar horizontal position",
                                desc = "Set horizontal & vertical to 0 for default behaviour",
                                type = "range",
                                min = -300,
                                max = 300,
                                step = 1,
                                get = function(info, val)
                                    return self.db.profile.focusBarPosX
                                end,
                                set = function(info, val)
                                    self.db.profile.focusBarPosX = val
                                    if FocusFrameSpellBar then updateCastbarPosition(FocusFrameSpellBar, val, true) end
                                end
                            },
                            focusSpellbarPosY = {
                                order = 4,
                                width = 1.5,
                                name = "Focus spellbar vertical position",
                                desc = "Set horizontal & vertical to 0 for default behaviour",
                                type = "range",
                                min = -300,
                                max = 300,
                                step = 1,
                                get = function(info, val)
                                    return self.db.profile.focusBarPosY
                                end,
                                set = function(info, val)
                                    self.db.profile.focusBarPosY = val
                                    if FocusFrameSpellBar then updateCastbarPosition(FocusFrameSpellBar, val, false) end
                                end
                            },
                            targetSpellbarScale = {
                                order = 5,
                                width = 1.5,
                                name = "Target spellbar size",
                                desc = "Change the scale of the castbar",
                                type = "range",
                                min = 0.7,
                                max = 3,
                                step = 0.05,
                                get = function(info, val)
                                    return self.db.profile.targetCastBarSize
                                end,
                                set = function(info, val)
                                    self.db.profile.targetCastBarSize = val
                                    TargetFrameSpellBar:SetScale(self.db.profile.targetCastBarSize)
                                    if not TargetFrameSpellBar:IsShown() then
                                        TargetFrameSpellBar:SetAlpha(1)
                                        TargetFrameSpellBar:Show()
                                    end
                                end
                            },
                            focusSpellbarScale = {
                                order = 6,
                                width = 1.5,
                                name = "Focus spellbar size",
                                desc = "Change the scale of the castbar",
                                type = "range",
                                min = 0.7,
                                max = 3,
                                step = 0.05,
                                get = function(info, val)
                                    return self.db.profile.focusCastBarSize
                                end,
                                set = function(info, val)
                                    self.db.profile.focusCastBarSize = val
                                    if FocusFrameSpellBar then FocusFrameSpellBar:SetScale(self.db.profile.focusCastBarSize) end
                                    if FocusFrameSpellBar and not FocusFrameSpellBar:IsShown() then
                                        FocusFrameSpellBar:SetAlpha(1)
                                        FocusFrameSpellBar:Show()
                                    end
                                end
                            },
                        },
                    },
                },
            },
            highlightBuffs = {
                type = "group",
                name = "Aura-specific customization",
                childGroups = "tree",
                order = 3,
                args = {
                    buffNameInput = {
                        order = 1,
                        width = 1.5,
                        name = "Add (De)Buff By Name / Spell Id",
                        desc = "Type the name or spell id of a (de)buff to customize",
                        type = "input",
                        set = function(info, val)
                            if tonumber(val) then
                                if not GetSpellInfo(val) then
                                    return
                                end
                                val = tostring(val)
                            end

                            for _, value in ipairs(self.db.profile.customHighlights) do
                                if value == val then
                                    return
                                end
                            end

                            tinsert(self.db.profile.customHighlights, val)
                            tsort(self.db.profile.customHighlights)
                            self.db.profile.customHighlightColors[val] = { r = 1, g = 1, b = 1, a = 0 }

                            self.options.args.highlightBuffs.args.buffList.args = self:AddCustomHighlightOptions()
                        end,
                    },
                    buffList = {
                        order = 2,
                        width = 1,
                        name = "Aura List",
                        type = "group",
                        args = DeBuffFilter:AddCustomHighlightOptions()
                    },
                },
            },
        },
    }

    local options = {
        name = "DeBuffFilter",
        type = "group",
        args = {
            load = {
                name = "Load configuration",
                desc = "Load configuration options",
                type = "execute",
                func = function()
                    if not InCombatLockdown() then
                        HideUIPanel(SettingsPanel)
                    end
                    LibStub("AceConfigDialog-3.0"):Open("DeBuffFilter")
                end,
            },
        },
    }

    self.options.plugins.profiles = { profiles = LibStub("AceDBOptions-3.0"):GetOptionsTable(self.db) }
    LibStub("AceConfig-3.0"):RegisterOptionsTable(AddonName .. "_blizz", options)
    LibStub("AceConfigDialog-3.0"):AddToBlizOptions(AddonName .. "_blizz", "|cff4693E6DeBuffFilter|r")
    LibStub("AceConfig-3.0"):RegisterOptionsTable(AddonName, self.options)
    LibStub("AceConsole-3.0"):RegisterChatCommand("dbf", function()
        if not InCombatLockdown() then
            HideUIPanel(SettingsPanel)
        end
        LibStub("AceConfigDialog-3.0"):Open("DeBuffFilter")
    end)
end