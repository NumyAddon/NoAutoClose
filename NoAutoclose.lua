local _, ns = ...

ns.hookedFrames = {}
ns.ignore = {
    GossipFrame = true,
    QuestFrame = true,
    WarboardQuestChoiceFrame = true,
    MacroFrame = true,
    CinematicFrame = true,
    BarberShopFrame = true,
    CommunitiesFrame = true,
}
local nukedCenterPanels = {
    ClassTalentFrame = true,
    SettingsPanel = true,
}

local function table_invert(t)
    local s={}
    for k,v in pairs(t) do
        s[v]=k
    end
    return s
end

function ns:OnShowUIPanel(frame)
    if (not frame or (InCombatLockdown() and frame:IsProtected())) then
        return -- can't touch this frame in combat :(
    end

    if (frame.IsShown and not frame:IsShown()) then
        -- if possible, force show the frame, ignoring the INTERFACE_ACTION_BLOCKED message
        frame:Show()
    end
    if (frame.GetName and frame:GetName() and self.hookedFrames[frame:GetName()]) then
        if (frame.GetPoint and not frame:GetPoint()) then
            -- disabling the UIPanelLayout system removes the default location, so let's set one
            local ofsx, ofsy = 50, -50
            frame:SetPoint('TOPLEFT', UIParent, 'TOPLEFT', ofsx, ofsy)
        end
        if (frame.IsToplevel and frame:IsToplevel() and frame.IsShown and frame:IsShown()) then
            -- if the frame is a toplevel frame, raise it to the top of the stack
            frame:Raise()
        end
    end
end

function ns:OnHideUIPanel(frame)
    if (not frame or (InCombatLockdown() and frame:IsProtected())) then
        return -- can't touch this frame in combat :(
    end
    if (frame.IsShown and frame:IsShown()) then
        -- if possible, force hide the frame, ignoring the INTERFACE_ACTION_BLOCKED message
        frame:Hide()
    end
end

function ns:ReworkSettingsOpenAndClose()
    if not SettingsPanel then return end

    -- this prevents closing the settings panel from cancelling spell casting (and therefore giving a taint error when any addon is registered)
    if SettingsPanel.TransitionBackOpeningPanel then
        function SettingsPanel:TransitionBackOpeningPanel()
            HideUIPanel(SettingsPanel)
        end
    end
    -- this closes the game menu when opening the settings ui, which makes it less buggy when pressing escape to close the settings UI
    if GameMenuButtonSettings then
        GameMenuButtonSettings:HookScript('OnClick', function()
            if GameMenuFrame and GameMenuFrame:IsShown() then
                HideUIPanel(GameMenuFrame)
            end
        end)
    end
end

function ns:HandleUIPanel(name, info, flippedUiSpecialFrames)
    if info.area == 'center' and not nukedCenterPanels[name] then
        UIPanelWindows[name].allowOtherPanels = true
        return
    end
    local frame = _G[name]
    if not frame or self.ignore[name] then return end
    if (frame.IsProtected and frame:IsProtected()) then
        self.ignore[name] = true
        return
    end
    if (not flippedUiSpecialFrames[name]) then
        flippedUiSpecialFrames[name] = true
        tinsert(UISpecialFrames, name)
    end
    self.hookedFrames[name] = true
    UIPanelWindows[name] = nil
    if frame.SetAttribute then
        frame:SetAttribute("UIPanelLayout-defined", nil)
        frame:SetAttribute("UIPanelLayout-enabled", nil)
        frame:SetAttribute("UIPanelLayout-area", nil)
        frame:SetAttribute("UIPanelLayout-pushable", nil)
        frame:SetAttribute("UIPanelLayout-whileDead", nil)
    end
end

function ns:ADDON_LOADED()
    local flippedUiSpecialFrames = table_invert(UISpecialFrames)

    for name, info in pairs(UIPanelWindows) do
        self:HandleUIPanel(name, info, flippedUiSpecialFrames)
    end
end

function ns:Init()
    hooksecurefunc('ShowUIPanel', function(frame) return self:OnShowUIPanel(frame) end)
    hooksecurefunc('HideUIPanel', function(frame) return self:OnHideUIPanel(frame) end)
    self:ReworkSettingsOpenAndClose()

    local eventFrame = CreateFrame('Frame')
    eventFrame:HookScript('OnEvent', function(_, event, ...) return self[event](self, event, ...) end)
    eventFrame:RegisterEvent('ADDON_LOADED')

    C_Timer.After(2, function()
        -- don't remember why this was needed, or when it should be triggered
        ns:OnShowUIPanel(CharacterFrame)
        ns:OnHideUIPanel(CharacterFrame)
    end)
end

do
    ns:Init()
end