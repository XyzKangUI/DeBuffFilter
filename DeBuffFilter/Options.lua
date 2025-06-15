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
        customHighlight = {},
        customAuraSetting = {},
        smartFilters = {},
        selfSize = 21,
        otherSize = 20,
        auraWidth = 122,
        verticalSpace = 1,
        horizontalSpace = 3,
        countSize = 14,
        sortBySize = false,
        sortbyDispellable = false,
        highlightAll = false,
        enablePrioritySort = false,
        enableRetailGlow = false,
        focusBarPosX = 0,
        focusBarPosY = 0,
        targetBarPosX = 0,
        targetBarPosY = 0,
        targetCastBarSize = 1,
        focusCastBarSize = 1,
        buffFrameBuffsPerRow = 10,
        disableFade = false,
        enableFancyCount = false,
        countColor = {1, 1, 1},
    }
}

StaticPopupDialogs["DBF_RELOADUI"] = {
    text = "You must reload the UI for this change to take effect.",
    button1 = "Reload UI",
    button2 = "Cancel",
    OnAccept = function() ReloadUI() end,
    timeout = 0,
    whileDead = 1,
    hideOnEscape = 1,
}

function DeBuffFilter:GetAuraFrameSettings(aura, frame)
    local auraSettings = self.db.profile.customAuraSetting[aura]
    if auraSettings and auraSettings[frame] then
        return auraSettings[frame]
    end
    return nil
end

function DeBuffFilter:GetAuraFrameSettingsByAura(auraName, spellId, frame)
    local settings = self:GetAuraFrameSettings(tostring(spellId), frame)
    if not settings then
        settings = self:GetAuraFrameSettings(auraName, frame)
    end
    return settings
end

function DeBuffFilter:SetAuraFrameSettings(aura, frame)
    self.db.profile.customAuraSetting[aura] = self.db.profile.customAuraSetting[aura] or {}
    local settings = self.db.profile.customAuraSetting[aura]
    settings[frame] = settings[frame] or {
        hide = false,
        customSizeEnabled = false,
        ownSize = self.db.profile.selfSize,
        otherSize = self.db.profile.otherSize,
        color = { r = 1, g = 1, b = 1, a = 1 },
        ownOnly = false,
        removeDuplicates = false,
        priority = 0,
        alwaysEnableGlow = false,
    }
    return settings[frame]
end

function DeBuffFilter:GetSmartFilterSettings(auraName, spellId, frame)
    local spellKey = tostring(spellId)
    local results = {}

    if self.db.profile.smartFilters[spellKey] and self.db.profile.smartFilters[spellKey][frame] then
        for _, filter in ipairs(self.db.profile.smartFilters[spellKey][frame]) do
            table.insert(results, filter)
        end
    end

    if self.db.profile.smartFilters[auraName] and self.db.profile.smartFilters[auraName][frame] then
        for _, filter in ipairs(self.db.profile.smartFilters[auraName][frame]) do
            table.insert(results, filter)
        end
    end

    if #results > 0 then
        return results
    else
        return nil
    end
end

function DeBuffFilter:SetSmartFilterSettings(spellId, frame)
    local spellKey = tostring(spellId)
    self.db.profile.smartFilters[spellKey] = self.db.profile.smartFilters[spellKey] or {}
    self.db.profile.smartFilters[spellKey][frame] = self.db.profile.smartFilters[spellKey][frame] or {}

    local settings = {
        action = { hide = false, glow = false, size = { enabled = false, value = 21 } },
        minDuration = 0,
        maxDuration = 0,
        enableDurationFilter = false,
        minStacks = 0,
        maxStacks = 0,
        enableStacksFilter = false,
        customName = "New Filter",
    }

    table.insert(self.db.profile.smartFilters[spellKey][frame], settings)
    return settings
end

function DeBuffFilter:BuildSmarterAuraOptions()
    local options = {}

    for aura, frames in pairs(self.db.profile.smartFilters or {}) do
        for frame, filters in pairs(frames or {}) do
            for index, settings in ipairs(filters) do
                local key = aura .. "_" .. frame .. "_" .. index

                options[key] = {
                    type = "group",
                    name = function()
                        return (settings.customName ~= "" and settings.customName) or (aura .. " (" .. index .. ")")
                    end,
                    args = {
                        customNameInput = {
                            order = 0,
                            type = "input",
                            name = "Filter Name",
                            desc = "Set a custom name for this filter",
                            set = function(_, val)
                                settings.customName = val
                            end,
                            get = function()
                                return settings.customName or ""
                            end
                        },
                        spellInput = {
                            order = 1,
                            type = "input",
                            name = "Spell ID or Name",
                            desc = "Change the spell ID or name for this filter",
                            set = function(_, val)
                                if val ~= aura and val ~= "" then
                                    self.db.profile.smartFilters[val] = self.db.profile.smartFilters[val] or {}
                                    self.db.profile.smartFilters[val][frame] = self.db.profile.smartFilters[val][frame] or {}
                                    table.insert(self.db.profile.smartFilters[val][frame], settings)

                                    table.remove(self.db.profile.smartFilters[aura][frame], index)

                                    if #self.db.profile.smartFilters[aura][frame] == 0 then
                                        self.db.profile.smartFilters[aura][frame] = nil
                                    end
                                    if next(self.db.profile.smartFilters[aura]) == nil then
                                        self.db.profile.smartFilters[aura] = nil
                                    end

                                    aura = val
                                end
                            end,
                            get = function()
                                return aura
                            end,
                        },
                        frame = {
                            order = 2,
                            type = "select",
                            name = "Apply To Frame",
                            values = { TargetFrame = "Target Frame", FocusFrame = "Focus Frame", BuffFrame = "Buff Frame" },
                            set = function(_, val)
                                if val ~= frame then
                                    self.db.profile.smartFilters[aura][val] = self.db.profile.smartFilters[aura][val] or {}
                                    table.insert(self.db.profile.smartFilters[aura][val], settings)

                                    table.remove(self.db.profile.smartFilters[aura][frame], index)

                                    if #self.db.profile.smartFilters[aura][frame] == 0 then
                                        self.db.profile.smartFilters[aura][frame] = nil
                                    end
                                    if next(self.db.profile.smartFilters[aura]) == nil then
                                        self.db.profile.smartFilters[aura] = nil
                                    end

                                    frame = val
                                end
                            end,
                            get = function()
                                return frame
                            end
                        },
                        action = {
                            order = 3,
                            type = "select",
                            name = "Action",
                            values = {
                                show = "Show Aura",
                                hide = "Hide Aura",
                                glow = "Glow Frame",
                                size = "Set Custom Size",
                            },
                            set = function(_, val)
                                settings.action.hide = false
                                settings.action.glow = false
                                settings.action.size.enabled = false

                                if val == "hide" then
                                    settings.action.hide = true
                                elseif val == "glow" then
                                    settings.action.glow = true
                                elseif val == "size" then
                                    settings.action.size.enabled = true
                                end
                            end,
                            get = function()
                                if settings.action.hide then
                                    return "hide"
                                end
                                if settings.action.glow then
                                    return "glow"
                                end
                                if settings.action.size and settings.action.size.enabled then
                                    return "size"
                                end
                                return "show"
                            end,
                        },
                        enableDurationFilter = {
                            order = 4,
                            type = "toggle",
                            name = "Enable Duration Filter",
                            set = function(_, val)
                                settings.enableDurationFilter = val
                            end,
                            get = function()
                                return settings.enableDurationFilter
                            end
                        },
                        enableStacksFilter = {
                            order = 5,
                            type = "toggle",
                            name = "Enable Stacks Filter",
                            set = function(_, val)
                                settings.enableStacksFilter = val
                            end,
                            get = function()
                                return settings.enableStacksFilter
                            end
                        },
                        minDuration = {
                            order = 6,
                            type = "range",
                            name = "Min Duration",
                            min = 0,
                            max = 120,
                            step = 1,
                            set = function(_, val)
                                settings.minDuration = val
                            end,
                            get = function()
                                return settings.minDuration or 0
                            end,
                            hidden = function()
                                return not settings.enableDurationFilter
                            end
                        },
                        maxDuration = {
                            order = 7,
                            type = "range",
                            name = "Max Duration",
                            min = 0,
                            max = 120,
                            step = 1,
                            set = function(_, val)
                                settings.maxDuration = val
                            end,
                            get = function()
                                return settings.maxDuration or 0
                            end,
                            hidden = function()
                                return not settings.enableDurationFilter
                            end
                        },
                        minStacks = {
                            order = 8,
                            type = "range",
                            name = "Min Stacks",
                            min = 0,
                            max = 100,
                            step = 1,
                            set = function(_, val)
                                settings.minStacks = val
                            end,
                            get = function()
                                return settings.minStacks or 0
                            end,
                            hidden = function()
                                return not settings.enableStacksFilter
                            end
                        },
                        maxStacks = {
                            order = 9,
                            type = "range",
                            name = "Max Stacks",
                            min = 0,
                            max = 100,
                            step = 1,
                            set = function(_, val)
                                settings.maxStacks = val
                            end,
                            get = function()
                                return settings.maxStacks or 0
                            end,
                            hidden = function()
                                return not settings.enableStacksFilter
                            end
                        },
                        customSize = {
                            order = 10,
                            type = "range",
                            name = "Set Custom Size",
                            min = 17,
                            max = 34,
                            step = 1,
                            set = function(_, val)
                                settings.action.size.value = val
                            end,
                            get = function()
                                return settings.action.size.value or 21
                            end,
                            hidden = function()
                                return not (settings.action.size and settings.action.size.enabled)
                            end,
                        },
                        deleteFilter = {
                            order = 99,
                            type = "execute",
                            name = "Delete Filter",
                            func = function()
                                table.remove(self.db.profile.smartFilters[aura][frame], index)

                                if #self.db.profile.smartFilters[aura][frame] == 0 then
                                    self.db.profile.smartFilters[aura][frame] = nil
                                end
                                if next(self.db.profile.smartFilters[aura]) == nil then
                                    self.db.profile.smartFilters[aura] = nil
                                end

                                DeBuffFilter:RefreshSmarterAuraOptions()
                            end
                        }
                    }
                }
            end
        end
    end

    return options
end

function DeBuffFilter:RefreshSmarterAuraOptions()
    if self.options and self.options.args and self.options.args.smarterAuraFilters and self.options.args.smarterAuraFilters.args then
        local updatedArgs = self.options.args.smarterAuraFilters.args

        for key in pairs(updatedArgs) do
            if key ~= "addFilterButton" then
                updatedArgs[key] = nil
            end
        end

        local newFilters = self:BuildSmarterAuraOptions()
        for key, val in pairs(newFilters) do
            updatedArgs[key] = val
        end
    end
end


function DeBuffFilter:AddCustomHighlightOptions()
    local new_args = {}
    for _, buff in ipairs(self.db.profile.customHighlight) do
        local buffName
        local spellName, _, spellIcon = GetSpellInfo(buff)

        if not spellIcon and type(buff) == "string" then
            for i = 1, 1248256 do
                local name, _, icon = GetSpellInfo(i)
                if name == buff then
                    spellIcon = icon
                    spellName = buff
                    break
                end
            end
        end

        if spellName and spellIcon then
            local iconMarkup = "|T" .. spellIcon .. ":18:18:0:0|t "
            buffName = iconMarkup .. spellName

            if tonumber(buff) then
                buffName = buffName .. " (" .. buff .. ")"
            end
        else
            buffName = buff
        end


        new_args["highlight_" .. buff] = {
            type = "group",
            name = buffName,
            childGroups = "tab",
            args = {}
        }
        for _, frame in ipairs({ "TargetFrame", "FocusFrame", "BuffFrame" }) do
            new_args["highlight_" .. buff].args[frame] = {
                type = "group",
                name = frame,
                order = frame == "TargetFrame" and 1 or frame == "FocusFrame" and 2 or 3,
                args = {
                    hide = {
                        order = 1,
                        type = "toggle",
                        name = "Hide aura",
                        desc = "Hides this aura completely",
                        get = function()
                            return (DeBuffFilter:GetAuraFrameSettings(buff, frame) or {}).hide or false
                        end,
                        set = function(_, val)
                            local frameSettings = DeBuffFilter:SetAuraFrameSettings(buff, frame)
                            frameSettings.hide = val
                            if frame == "TargetFrame" then
                                TargetFrame_UpdateAuras(TargetFrame)
                            end
                            if frame == "FocusFrame" and FocusFrame then
                                TargetFrame_UpdateAuras(FocusFrame)
                            end
                            if frame == "BuffFrame" then
                                BuffFrame_Update()
                            end
                        end,
                    },
                    removeDuplicates = {
                        order = 2,
                        type = "toggle",
                        name = "Hide duplicate auras",
                        desc = "Show this aura only once to prevent bloat",
                        get = function()
                            return (DeBuffFilter:GetAuraFrameSettings(buff, frame) or {}).removeDuplicates or false
                        end,
                        set = function(_, val)
                            local frameSettings = DeBuffFilter:SetAuraFrameSettings(buff, frame)
                            frameSettings.removeDuplicates = val
                        end,
                    },
                    ownOnly = {
                        order = 3,
                        type = "toggle",
                        name = "Show own buff only",
                        desc = "Shows only the auras applied by you and hides others",
                        get = function()
                            return (DeBuffFilter:GetAuraFrameSettings(buff, frame) or {}).ownOnly or false
                        end,
                        set = function(_, val)
                            local frameSettings = DeBuffFilter:SetAuraFrameSettings(buff, frame)
                            frameSettings.ownOnly = val
                        end,
                    },
                    customSizeToggle = {
                        order = 4,
                        type = "toggle",
                        name = "Enable custom sizing",
                        get = function()
                            return (DeBuffFilter:GetAuraFrameSettings(buff, frame) or {}).customSizeEnabled or false
                        end,
                        set = function(_, val)
                            local frameSettings = DeBuffFilter:SetAuraFrameSettings(buff, frame)
                            frameSettings.customSizeEnabled = val
                        end,
                    },
                    ownAuraSize = {
                        order = 5,
                        type = "range",
                        name = "Auras applied by me",
                        min = 17, max = 34, step = 1,
                        get = function()
                            return (DeBuffFilter:GetAuraFrameSettings(buff, frame) or {}).ownSize or DeBuffFilter.db.profile.selfSize
                        end,
                        set = function(_, val)
                            local frameSettings = DeBuffFilter:SetAuraFrameSettings(buff, frame)
                            frameSettings.ownSize = val
                            if frame == "TargetFrame" then
                                TargetFrame_UpdateAuras(TargetFrame)
                            end
                            if frame == "FocusFrame" and FocusFrame then
                                TargetFrame_UpdateAuras(FocusFrame)
                            end
                            if frame == "BuffFrame" then
                                BuffFrame_Update()
                            end
                        end,
                        hidden = function()
                            return not (DeBuffFilter:GetAuraFrameSettings(buff, frame) or {}).customSizeEnabled
                        end,
                    },
                    otherAuraSize = {
                        order = 6,
                        type = "range",
                        name = "Auras applied by others",
                        min = 17, max = 34, step = 1,
                        get = function()
                            return (DeBuffFilter:GetAuraFrameSettings(buff, frame) or {}).otherSize or DeBuffFilter.db.profile.otherSize
                        end,
                        set = function(_, val)
                            local frameSettings = DeBuffFilter:SetAuraFrameSettings(buff, frame)
                            frameSettings.otherSize = val
                            if frame == "TargetFrame" then
                                TargetFrame_UpdateAuras(TargetFrame)
                            end
                            if frame == "FocusFrame" and FocusFrame then
                                TargetFrame_UpdateAuras(FocusFrame)
                            end
                            if frame == "BuffFrame" then
                                BuffFrame_Update()
                            end
                        end,
                        hidden = function()
                            return not (DeBuffFilter:GetAuraFrameSettings(buff, frame) or {}).customSizeEnabled
                        end,
                    },
                    color = {
                        order = 8,
                        type = "color",
                        name = "Custom color highlight border",
                        get = function()
                            local c = (DeBuffFilter:GetAuraFrameSettings(buff, frame) or {}).color or { r = 1, g = 1, b = 1, a = 1 }
                            return c.r, c.g, c.b, c.a
                        end,
                        set = function(_, r, g, b, a)
                            local frameSettings = DeBuffFilter:SetAuraFrameSettings(buff, frame)
                            frameSettings.color = { r = r, g = g, b = b, a = a }
                            if frame == "TargetFrame" then
                                TargetFrame_UpdateAuras(TargetFrame)
                            end
                            if frame == "FocusFrame" and FocusFrame then
                                TargetFrame_UpdateAuras(FocusFrame)
                            end
                            if frame == "BuffFrame" then
                                BuffFrame_Update()
                            end
                        end,
                    },
                    alwaysEnableGlow = {
                        order = 9,
                        type = "toggle",
                        name = "Always glow",
                        desc = "Forces glow to appear regardless of any other setting",
                        get = function()
                            return (DeBuffFilter:GetAuraFrameSettings(buff, frame) or {}).alwaysEnableGlow or false
                        end,
                        set = function(_, val)
                            local frameSettings = DeBuffFilter:SetAuraFrameSettings(buff, frame)
                            frameSettings.alwaysEnableGlow = val
                            if frame == "TargetFrame" then
                                TargetFrame_UpdateAuras(TargetFrame)
                            end
                            if frame == "FocusFrame" and FocusFrame then
                                TargetFrame_UpdateAuras(FocusFrame)
                            end
                            if frame == "BuffFrame" then
                                BuffFrame_Update()
                            end
                        end,
                    },
                }
            }
            if frame ~= "BuffFrame" then
                new_args["highlight_" .. buff].args[frame].args.priority = {
                    order = 7,
                    type = "range",
                    width = 2,
                    name = "Priority",
                    desc = "Set the priority of the aura",
                    min = 0,
                    max = 100,
                    step = 1,
                    get = function()
                        return (DeBuffFilter:GetAuraFrameSettings(buff, frame) or {}).priority or 0
                    end,
                    set = function(_, val)
                        local frameSettings = DeBuffFilter:SetAuraFrameSettings(buff, frame)
                        frameSettings.priority = val
                        if frame == "TargetFrame" then
                            TargetFrame_UpdateAuras(TargetFrame)
                        end
                        if frame == "FocusFrame" and FocusFrame then
                            TargetFrame_UpdateAuras(FocusFrame)
                        end
                    end,
                    hidden = function()
                        return not DeBuffFilter.db.profile.enablePrioritySort
                    end,
                }
            end
        end
        new_args["highlight_" .. buff].args.delete = {
            order = 99,
            type = "execute",
            name = "Delete",
            func = function()
                for i, value in ipairs(self.db.profile.customHighlight) do
                    if value == buff then
                        table.remove(self.db.profile.customHighlight, i)
                        self.db.profile.customAuraSetting[buff] = nil
                        self.options.args.highlightBuffs.args.buffList.args = self:AddCustomHighlightOptions()
                        break
                    end
                end
            end,
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
                name = "|cff4693E6Author:|r Xyz",
                type = "description"
            },
            version = {
                name = "|cff4693E6Version:|r " .. GetAddOnMetadata("DeBuffFilter", "Version") .. "\n",
                type = "description"
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
                        name = "UnitFrame settings",
                        args = {
                            selfSize = {
                                order = 1,
                                width = 2,
                                name = "My Debuffs/Buffs size",
                                desc = "Resize your own (de)buffs displayed",
                                type = "range",
                                min = 17,
                                max = 34,
                                step = 1,
                                get = function()
                                    return self.db.profile.selfSize
                                end,
                                set = function(info, val)
                                    self.db.profile.selfSize = val
                                    TargetFrame_UpdateAuras(TargetFrame)
                                    if FocusFrame then
                                        TargetFrame_UpdateAuras(FocusFrame)
                                    end
                                end
                            },
                            otherSize = {
                                order = 2,
                                width = 2,
                                name = "Others Debuffs/Buffs size",
                                desc = "Resize the (de)buffs casted by others that are displayed",
                                type = "range",
                                min = 17,
                                max = 34,
                                step = 1,
                                get = function()
                                    return self.db.profile.otherSize
                                end,
                                set = function(info, val)
                                    self.db.profile.otherSize = val
                                    TargetFrame_UpdateAuras(TargetFrame)
                                    if FocusFrame then
                                        TargetFrame_UpdateAuras(FocusFrame)
                                    end
                                end
                            },
                            auraWidth = {
                                order = 3,
                                width = 2,
                                name = "Aura row width",
                                desc = "Increase the amount of auras that can fit per row",
                                type = "range",
                                min = 108,
                                max = 178,
                                step = 14,
                                get = function()
                                    return self.db.profile.auraWidth
                                end,
                                set = function(info, val)
                                    self.db.profile.auraWidth = val
                                    TargetFrame_UpdateAuras(TargetFrame)
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
                                get = function()
                                    return self.db.profile.verticalSpace
                                end,
                                set = function(info, val)
                                    self.db.profile.verticalSpace = val
                                    TargetFrame_UpdateAuras(TargetFrame)
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
                                get = function()
                                    return self.db.profile.horizontalSpace
                                end,
                                set = function(info, val)
                                    self.db.profile.horizontalSpace = val
                                    TargetFrame_UpdateAuras(TargetFrame)
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
                        name = "Misc options",
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
                                    TargetFrame_UpdateAuras(TargetFrame)
                                    if FocusFrame then
                                        TargetFrame_UpdateAuras(FocusFrame)
                                    end
                                end,
                            },
                            enablePrioritySort = {
                                order = 4,
                                type = "toggle",
                                name = "Enable priority slider",
                                desc = "When enabled 'Aura customization' will display an extra slider to set priority per aura",
                                get = function()
                                    return self.db.profile.enablePrioritySort
                                end,
                                set = function(_, value)
                                    self.db.profile.enablePrioritySort = value
                                end,
                            },
                            enableRetailGlow = {
                                order = 5,
                                type = "toggle",
                                name = "Retail glow border",
                                desc = "Enables the retail glowing highlight texture on borders",
                                get = function()
                                    return self.db.profile.enableRetailGlow
                                end,
                                set = function(_, value)
                                    self.db.profile.enableRetailGlow = value
                                    StaticPopup_Show("DBF_RELOADUI")
                                end,
                            },
                            disableFade = {
                                order = 6,
                                type = "toggle",
                                name = "Disable fading animation",
                                desc = "Disables the fading animation of auras on BuffFrame",
                                get = function()
                                    return self.db.profile.disableFade
                                end,
                                set = function(_, value)
                                    self.db.profile.disableFade = value
                                    StaticPopup_Show("DBF_RELOADUI")
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
                                get = function()
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
                                get = function()
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
                                get = function()
                                    return self.db.profile.focusBarPosX
                                end,
                                set = function(info, val)
                                    self.db.profile.focusBarPosX = val
                                    if FocusFrameSpellBar then
                                        updateCastbarPosition(FocusFrameSpellBar, val, true)
                                    end
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
                                get = function()
                                    return self.db.profile.focusBarPosY
                                end,
                                set = function(info, val)
                                    self.db.profile.focusBarPosY = val
                                    if FocusFrameSpellBar then
                                        updateCastbarPosition(FocusFrameSpellBar, val, false)
                                    end
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
                                get = function()
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
                                get = function()
                                    return self.db.profile.focusCastBarSize
                                end,
                                set = function(info, val)
                                    self.db.profile.focusCastBarSize = val
                                    if FocusFrameSpellBar then
                                        FocusFrameSpellBar:SetScale(self.db.profile.focusCastBarSize)
                                    end
                                    if FocusFrameSpellBar and not FocusFrameSpellBar:IsShown() then
                                        FocusFrameSpellBar:SetAlpha(1)
                                        FocusFrameSpellBar:Show()
                                    end
                                end
                            },
                        },
                    },
                    fancyCount = {
                        order = 4,
                        type = "group",
                        inline = false,
                        name = "Stack count settings",
                        args = {
                            countColor = {
                                order = 0,
                                type = "color",
                                hasAlpha = false,
                                name = "Stack text color",
                                desc = "Set the color of the aura stack count text",
                                get = function()
                                    local c = self.db.profile.countColor or {1, 1, 1}
                                    return c[1], c[2], c[3]
                                end,
                                set = function(_, r, g, b)
                                    self.db.profile.countColor = { r, g, b }
                                    TargetFrame_UpdateAuras(TargetFrame)
                                    if FocusFrame then TargetFrame_UpdateAuras(FocusFrame) end
                                end,
                            },
                            separator = {
                                order = 1,
                                type = "description",
                                name = "\n",
                                width = "full"
                            },
                            enableFancyCount = {
                                order = 2,
                                type = "toggle",
                                width = "full",
                                name = "Enable stack count size slider",
                                desc = "Enable or disable slider to set custom size for aura stack counts",
                                get = function()
                                    return self.db.profile.enableFancyCount
                                end,
                                set = function(_, val)
                                    self.db.profile.enableFancyCount = val
                                    TargetFrame_UpdateAuras(TargetFrame)
                                    if FocusFrame then
                                        TargetFrame_UpdateAuras(FocusFrame)
                                    end
                                end,
                            },
                            countSize = {
                                order = 3,
                                width = 1.5,
                                name = "Stack text size",
                                desc = "Adjust count size of auras with stacks",
                                type = "range",
                                min = 5,
                                max = 35,
                                step = 1,
                                get = function()
                                    return self.db.profile.countSize
                                end,
                                set = function(_, val)
                                    self.db.profile.countSize = val
                                    TargetFrame_UpdateAuras(TargetFrame)
                                    if FocusFrame then
                                        TargetFrame_UpdateAuras(FocusFrame)
                                    end
                                end,
                                disabled = function()
                                    return not self.db.profile.enableFancyCount
                                end,
                            },
                        },
                    },
                    fancyBuffFrame = {
                        order = 5,
                        type = "group",
                        inline = false,
                        name = "BuffFrame settings",
                        args = {
                            buffFrameBuffsPerRow = {
                                order = 0,
                                width = 1,
                                name = "Buffs per row",
                                desc = "Number of buffs to show per row on the BuffFrame",
                                type = "range",
                                min = 2,
                                max = 20,
                                step = 1,
                                get = function()
                                    return self.db.profile.buffFrameBuffsPerRow or 10
                                end,
                                set = function(_, val)
                                    self.db.profile.buffFrameBuffsPerRow = val
                                    BuffFrame_Update()
                                end,
                            },
                            separator1 = {
                                order = 1,
                                type = "description",
                                name = "\n",
                                width = "full"
                            },
                            enableMovingDuration = {
                                order = 2,
                                type = "toggle",
                                name = "Enable custom timer position",
                                width = "full",
                                desc = "Allows changing X and Y coordinates of buff duration text",
                                get = function()
                                    return self.db.profile.enableMovingDuration
                                end,
                                set = function(_, val)
                                    self.db.profile.enableMovingDuration = val
                                    StaticPopup_Show("DBF_RELOADUI")
                                end,
                            },
                            buffFrameDurationYPos = {
                                order = 3,
                                width = 2,
                                name = "Buff duration vertical position",
                                desc = "Set the Y-coord of buff durations",
                                type = "range",
                                min = -100,
                                max = 100,
                                step = 1,
                                get = function()
                                    return self.db.profile.buffFrameDurationYPos or 10
                                end,
                                set = function(_, val)
                                    self.db.profile.buffFrameDurationYPos = val
                                    BuffFrame_Update()
                                end,
                                hidden = function() return not self.db.profile.enableMovingDuration end,
                            },

                            buffFrameDurationXPos = {
                                order = 4,
                                width = 2,
                                name = "Buff duration horizontal position",
                                desc = "Set the X-coord of buff durations",
                                type = "range",
                                min = -100,
                                max = 100,
                                step = 1,
                                get = function()
                                    return self.db.profile.buffFrameDurationXPos or 10
                                end,
                                set = function(_, val)
                                    self.db.profile.buffFrameDurationXPos = val
                                    BuffFrame_Update()
                                end,
                                hidden = function() return not self.db.profile.enableMovingDuration end,
                            },
                        },
                    },
                },
            },
            highlightBuffs = {
                type = "group",
                name = "Aura customization",
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
                            for _, value in ipairs(self.db.profile.customHighlight) do
                                if value == val then
                                    return
                                end
                            end
                            tinsert(self.db.profile.customHighlight, val)
                            tsort(self.db.profile.customHighlight)
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
            smarterAuraFilters = {
                type = "group",
                name = "Advanced Aura Filters",
                order = 4,
                args = (function()
                    local flatArgs = {
                        addFilterButton = {
                            order = 0,
                            type = "execute",
                            name = "Add New Filter",
                            func = function()
                                local aura = ""
                                local frame = "TargetFrame"
                                local settings = DeBuffFilter:SetSmartFilterSettings(aura, frame)
                                settings.action = { hide = false, glow = false, size = { enabled = false, value = 21 } }
                                settings.minDuration = 0
                                settings.maxDuration = 0
                                settings.enableDurationFilter = false
                                settings.minStacks = 0
                                settings.maxStacks = 0
                                settings.customName = "New Filter"
                                DeBuffFilter:RefreshSmarterAuraOptions()
                            end
                        }
                    }

                    local filterOptions = DeBuffFilter:BuildSmarterAuraOptions()
                    for key, val in pairs(filterOptions) do
                        if type(val) == "table" and val.type then
                            flatArgs[key] = val
                        end
                    end

                    return flatArgs
                end)()
            }
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
