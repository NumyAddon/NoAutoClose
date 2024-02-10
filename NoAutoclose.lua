local _, ns = ...

ns.hookedFrames = {}
ns.ignore = {
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
    local s = {}
    for k,v in pairs(t) do
        s[v] = k
    end

    return s
end

local function setTrue(table, key)
    TextureLoadingGroupMixin.AddTexture({textures = table}, key);
end

local function setNil(table, key)
    TextureLoadingGroupMixin.RemoveTexture({textures = table}, key);
end

function ns:ShouldIgnoreShowHideUIPanel(frame)
    if frame == WorldMapFrame and IsAddOnLoaded('Carbonite')
        and Nx and Nx.db and Nx.db.profile and Nx.db.profile.Map and Nx.db.profile.Map.MaxOverride
    then
        return true
    end

    return false
end

function ns:OnShowUIPanel(frame)
    if (not frame or (InCombatLockdown() and frame:IsProtected())) then
        return -- can't touch this frame in combat :(
    end

    if (frame.IsShown and not frame:IsShown()) then
        if self:ShouldIgnoreShowHideUIPanel(frame) then return end
        -- if possible, force show the frame, ignoring the INTERFACE_ACTION_BLOCKED message
        frame:Show()
    end
    if (frame.GetName and frame:GetName() and self.hookedFrames[frame:GetName()]) then
        if (frame.GetPoint and not frame:GetPoint()) then
            -- disabling the UIPanelLayout system removes the default location, so let's set one
            local ofsx, ofsy = 50, -50
            (frame.SetPointBase or frame.SetPoint)(frame, 'TOPLEFT', UIParent, 'TOPLEFT', ofsx, ofsy)
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
        if self:ShouldIgnoreShowHideUIPanel(frame) then return end
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
        setTrue(UIPanelWindows[name], 'allowOtherPanels')
        return
    end
    local frame = _G[name]
    if not frame or self.ignore[name] then return end
    if (frame.IsProtected and frame:IsProtected() and InCombatLockdown()) then
        self:AddToCombatLockdownQueue(ns.HandleUIPanel, ns, name, info, flippedUiSpecialFrames)
        return
    end
    if (not flippedUiSpecialFrames[name]) then
        flippedUiSpecialFrames[name] = true
        tinsert(UISpecialFrames, name)
    end
    self.hookedFrames[name] = true
    setNil(UIPanelWindows, name)
    if frame.SetAttribute then
        frame:SetAttribute("UIPanelLayout-defined", nil)
        frame:SetAttribute("UIPanelLayout-enabled", nil)
        frame:SetAttribute("UIPanelLayout-area", nil)
        frame:SetAttribute("UIPanelLayout-pushable", nil)
        frame:SetAttribute("UIPanelLayout-whileDead", nil)
    end
    if (frame.GetPoint and not frame:GetPoint()) then
        -- disabling the UIPanelLayout system removes the default location, so let's set one
        local ofsx, ofsy = 50, -50
        (frame.SetPointBase or frame.SetPoint)(frame, 'TOPLEFT', UIParent, 'TOPLEFT', ofsx, ofsy)
    end
end

function ns:AddToCombatLockdownQueue(func, ...)
    if #self.combatLockdownQueue == 0 then
        self.eventFrame:RegisterEvent("PLAYER_REGEN_ENABLED");
    end

    tinsert(self.combatLockdownQueue, { func = func, args = { ... } });
end

function ns:PLAYER_REGEN_ENABLED()
    self.eventFrame:UnregisterEvent("PLAYER_REGEN_ENABLED");
    if #self.combatLockdownQueue == 0 then return; end

    for _, item in pairs(self.combatLockdownQueue) do
        item.func(unpack(item.args));
    end
    wipe(self.combatLockdownQueue);
end

function ns:ADDON_LOADED()
    local flippedUiSpecialFrames = table_invert(UISpecialFrames)

    for name, info in pairs(UIPanelWindows) do
        self:HandleUIPanel(name, info, flippedUiSpecialFrames)
    end
    WorldMapFrame:SetAttribute('UIPanelLayout-defined', '1')
    WorldMapFrame:SetAttribute('UIPanelLayout-maximizePoint', 'TOP')
end

ns.playerInteractionHideMap = {
    [Enum.PlayerInteractionType.Gossip] = 'GossipFrame',
    [Enum.PlayerInteractionType.QuestGiver] = 'QuestFrame',
}

function ns:PLAYER_INTERACTION_MANAGER_FRAME_SHOW(_, type)
    for mapType, frameName in pairs(self.playerInteractionHideMap) do
        local frame = _G[frameName]
        if type ~= mapType and frame.IsShown and frame:IsShown() then
            HideUIPanel(_G[frameName])
        end
    end
end

function ns:PLAYER_INTERACTION_MANAGER_FRAME_HIDE(_, type)
    if self.playerInteractionHideMap[type] then
        local frame = _G[self.playerInteractionHideMap[type]]
        if frame and frame.IsShown and frame:IsShown() then
            HideUIPanel(frame)
        end
    end
end

function ns:Init()
    hooksecurefunc('ShowUIPanel', function(frame) self:OnShowUIPanel(frame) end)
    hooksecurefunc('HideUIPanel', function(frame) self:OnHideUIPanel(frame) end)
    self:ReworkSettingsOpenAndClose()

    ns.eventFrame = CreateFrame('Frame')
    ns.eventFrame:HookScript('OnEvent', function(_, event, ...) self[event](self, event, ...) end)
    ns.eventFrame:RegisterEvent('ADDON_LOADED')
    ns.eventFrame:RegisterEvent('PLAYER_INTERACTION_MANAGER_FRAME_SHOW')
    ns.eventFrame:RegisterEvent('PLAYER_INTERACTION_MANAGER_FRAME_HIDE')

    ns.combatLockdownQueue = {}
end

do
    ns:Init()
end