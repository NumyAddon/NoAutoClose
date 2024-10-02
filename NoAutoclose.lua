local _, ns = ...;

ns.hookedFrames = {};
ns.ignore = {
    BarberShopFrame = true, -- barbershop frame, better to allow it to hide the UI
    CinematicFrame = true, -- cinematic frame, better to allow it to hide the UI
    CommunitiesFrame = true,
    MacroFrame = true,
    PerksProgramFrame = true, -- trading post frame, better to allow it to hide the UI
    WarboardQuestChoiceFrame = true,
};
local nukedCenterPanels = {
    ClassTalentFrame = true,
    DelvesDifficultyPickerFrame = true,
    SettingsPanel = true,
};
local uiSpecialFrameBlacklist = {
    PlayerSpellsFrame = true, -- cannot be safely closed with UISpecialFrames
};

local UpdateScaleForFit = UpdateScaleForFit or UIPanelUpdateScaleForFit;

local CHECK_FIT_DEFAULT_EXTRA_WIDTH = 20;
local CHECK_FIT_DEFAULT_EXTRA_HEIGHT = 20;

local function table_invert(t)
    local s = {};
    for k,v in pairs(t) do
        s[v] = k;
    end

    return s;
end

local function setTrue(table, key)
    TextureLoadingGroupMixin.AddTexture({textures = table}, key);
end

local function setNil(table, key)
    TextureLoadingGroupMixin.RemoveTexture({textures = table}, key);
end

function ns:ShouldNotManuallyShowHide(frame, interfaceActionWasBlocked)
    local name = frame.GetName and frame:GetName();
    if
        (
            frame == WorldMapFrame and C_AddOns.IsAddOnLoaded('Carbonite')
            and Nx and Nx.db and Nx.db.profile and Nx.db.profile.Map and Nx.db.profile.Map.MaxOverride
        )
        or (uiSpecialFrameBlacklist[name])
    then
        return true;
    end

    return not interfaceActionWasBlocked;
end

function ns:OnDisplayInterfaceActionBlockedMessage()
    if InCombatLockdown() and debugstack(3):find("in function `ShowUIPanel'") then
        self.interfaceActionWasBlocked = true;
    end
end

function ns:SetDefaultPosition(frame)
    if
        (frame.IsForbidden and frame:IsForbidden())
        or (frame.IsProtected and frame:IsProtected() and InCombatLockdown())
    then
        return;
    end
    frame:ClearAllPoints();
    local ofsx, ofsy = 50, -50;
    (frame.SetPointBase or frame.SetPoint)(frame, 'TOPLEFT', UIParent, 'TOPLEFT', ofsx, ofsy);
end

function ns:OnShowUIPanel(frame)
    local interfaceActionWasBlocked = self.interfaceActionWasBlocked;
    self.interfaceActionWasBlocked = false;
    if not frame or (frame.IsForbidden and frame:IsForbidden()) then return; end
    local name = frame.GetName and frame:GetName();
    local isHooked = self.hookedFrames[name];
    if not isHooked and frame.IsProtected and frame:IsProtected() and InCombatLockdown() then return; end

    if isHooked and ((frame.IsProtected and frame:IsProtected()) or uiSpecialFrameBlacklist[name]) then
        -- ensure that we have a secure esc handler configured for this frame
        if InCombatLockdown() then
            self:AddToCombatLockdownQueue(self.ConfigureSecureEscHandler, ns, frame);
            return; -- don't do anything else while we're in combat
        end
        self:ConfigureSecureEscHandler(frame, uiSpecialFrameBlacklist[name]);
    end

    if (frame.IsShown and not frame:IsShown()) then
        if self:ShouldNotManuallyShowHide(frame, interfaceActionWasBlocked) then return; end
        -- if possible, force show the frame, ignoring the INTERFACE_ACTION_BLOCKED message
        frame:Show();
    end
    if isHooked then
        if (frame.GetPoint and not frame:GetPoint()) then
            -- disabling the UIPanelLayout system removes the default location, so let's set one
            self:SetDefaultPosition(frame);
        end
        if (frame.IsToplevel and frame:IsToplevel() and frame.IsShown and frame:IsShown()) then
            -- if the frame is a toplevel frame, raise it to the top of the stack
            frame:Raise();
        end
        if isHooked.checkFit then
            UpdateScaleForFit(frame, isHooked.checkFitExtraWidth, isHooked.checkFitExtraHeight);
        end
    end
end

function ns:OnHideUIPanel(frame)
    local interfaceActionWasBlocked = self.interfaceActionWasBlocked;
    self.interfaceActionWasBlocked = false;
    if (not frame or (InCombatLockdown() and frame:IsProtected())) then
        return; -- can't touch this frame in combat :(
    end
    if (frame.IsShown and frame:IsShown()) then
        if self:ShouldNotManuallyShowHide(frame, interfaceActionWasBlocked) then return; end
        -- if possible, force hide the frame, ignoring the INTERFACE_ACTION_BLOCKED message
        frame:Hide();
    end
end

function ns:ReworkSettingsOpenAndClose()
    if not SettingsPanel then return; end

    -- this prevents closing the settings panel from cancelling spell casting (and therefore giving a taint error when any addon is registered)
    if SettingsPanel.TransitionBackOpeningPanel then
        function SettingsPanel:TransitionBackOpeningPanel()
            HideUIPanel(SettingsPanel);
        end
    end
    -- this closes the game menu when opening the settings ui, which makes it less buggy when pressing escape to close the settings UI
    if GameMenuButtonSettings then
        GameMenuButtonSettings:HookScript('OnClick', function()
            if GameMenuFrame and GameMenuFrame:IsShown() then
                HideUIPanel(GameMenuFrame);
            end
        end);
    end
end

function ns:HandleUIPanel(name, info, flippedUiSpecialFrames)
    if info.area == 'center' and not nukedCenterPanels[name] then
        setTrue(UIPanelWindows[name], 'allowOtherPanels');
        return;
    end
    local frame = _G[name];
    if not frame or self.ignore[name] then return; end
    if ((frame.IsProtected and frame:IsProtected()) or uiSpecialFrameBlacklist[name]) then
        if InCombatLockdown() then
            self:AddToCombatLockdownQueue(ns.HandleUIPanel, ns, name, info, flippedUiSpecialFrames);
            return;
        end

        self:ConfigureSecureEscHandler(frame, uiSpecialFrameBlacklist[name]);
    end
    if (not flippedUiSpecialFrames[name] and not uiSpecialFrameBlacklist[name]) then
        flippedUiSpecialFrames[name] = true;
        tinsert(UISpecialFrames, name);
    end
    self.hookedFrames[name] = {
        checkFit = UIPanelWindows[name] and UIPanelWindows[name].checkFit,
        checkFitExtraWidth = UIPanelWindows[name] and UIPanelWindows[name].checkFitExtraWidth or CHECK_FIT_DEFAULT_EXTRA_WIDTH,
        checkFitExtraHeight = UIPanelWindows[name] and UIPanelWindows[name].checkFitExtraHeight or CHECK_FIT_DEFAULT_EXTRA_HEIGHT,
    };
    setNil(UIPanelWindows, name);
    if frame.SetAttribute then
        frame:SetAttribute("UIPanelLayout-defined", nil);
        frame:SetAttribute("UIPanelLayout-enabled", nil);
        frame:SetAttribute("UIPanelLayout-area", nil);
        frame:SetAttribute("UIPanelLayout-pushable", nil);
        frame:SetAttribute("UIPanelLayout-whileDead", nil);
    end
    if (frame.GetPoint and not frame:GetPoint()) then
        -- disabling the UIPanelLayout system removes the default location, so let's set one
        local ofsx, ofsy = 50, -50;
        (frame.SetPointBase or frame.SetPoint)(frame, 'TOPLEFT', UIParent, 'TOPLEFT', ofsx, ofsy);
    end
end

--- @param func function
--- @param ... any # arguments
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

local escHandlerMap = {};
local handlerFrameIndex = 0;
function ns:ConfigureSecureEscHandler(frame, alwaysSetBindinOnShow)
    --[[
        Since the UIPanel system no longer taintlessly hides protected panels, we need to create a secure handler, which will
        configure a temporary keybinding for ESC, to hide the panel. Once we leave combat, we unbind it again, to go back to normal.
        The downside of this approach, is that protected frames will close 1 by 1, and that hiding the frames takes priority over e.g. canceling spell casting.
    --]]

    if escHandlerMap[frame] then return; end
    handlerFrameIndex = handlerFrameIndex + 1;
    local name = 'Numy_NoAutoClose_SecureEscapeHandlerFrame' .. handlerFrameIndex;
    local escHandler = CreateFrame('Button', name, frame, 'SecureHandlerShowHideTemplate,SecureHandlerClickTemplate');
    escHandlerMap[frame] = escHandler;

    escHandler.name = name;
    escHandler.panel = frame;
    escHandler:SetFrameRef('panel', frame);
    escHandler:SetFrameRef('UIParent', UIParent);
    escHandler:RegisterEvent('PLAYER_REGEN_ENABLED');
    escHandler:RegisterEvent('PLAYER_REGEN_DISABLED');
    escHandler:HookScript('OnEvent', function(handlerFrame, event)
        if event == 'PLAYER_REGEN_ENABLED' then
            ClearOverrideBindings(handlerFrame);
        elseif event == 'PLAYER_REGEN_DISABLED' and frame:IsVisible() then
            SetOverrideBindingClick(handlerFrame, true, 'ESCAPE', handlerFrame.name);
        end
    end);
    escHandler:SetAttribute('alwaysSetBindingOnShow', alwaysSetBindinOnShow);
    escHandler:SetAttribute('_onclick', [[
        self:ClearBindings(); -- clear the bindings, just in case something is preventing the _onhide from firing
        local panel = self:GetFrameRef('panel');
        if panel:IsShown() then
            panel:Hide();
        end
    ]]);
    escHandler:SetAttribute('_onhide', [[
        self:ClearBindings();
    ]]);
    escHandler:SetAttribute('_onshow', [[
        local alwaysSetBindingOnShow = self:GetAttribute('alwaysSetBindingOnShow');
        if alwaysSetBindingOnShow or PlayerInCombat() then
            self:SetBindingClick(true, 'ESCAPE', self);
            local panel = self:GetFrameRef('panel');
            panel:Raise();
            if (not panel:GetPoint()) then
                -- disabling the UIPanelLayout system removes the default location, so let's set one
                local UIParent = self:GetFrameRef('UIParent');
                local ofsx, ofsy = 50, -50;
                panel:SetPoint('TOPLEFT', UIParent, 'TOPLEFT', ofsx, ofsy);
            end
        end
    ]]);
end

function ns:ADDON_LOADED()
    local flippedUiSpecialFrames = table_invert(UISpecialFrames);

    for name, info in pairs(UIPanelWindows) do
        self:HandleUIPanel(name, info, flippedUiSpecialFrames);
    end
    if InCombatLockdown() and WorldMapFrame:IsProtected() then
        self:AddToCombatLockdownQueue(function()
            WorldMapFrame:SetAttribute('UIPanelLayout-defined', '1');
            WorldMapFrame:SetAttribute('UIPanelLayout-maximizePoint', 'TOP');
        end);
    else
        WorldMapFrame:SetAttribute('UIPanelLayout-defined', '1');
        WorldMapFrame:SetAttribute('UIPanelLayout-maximizePoint', 'TOP');
    end
end

ns.playerInteractionHideMap = {
    [Enum.PlayerInteractionType.Gossip] = 'GossipFrame',
    [Enum.PlayerInteractionType.QuestGiver] = 'QuestFrame',
};

function ns:PLAYER_INTERACTION_MANAGER_FRAME_SHOW(_, type)
    for mapType, frameName in pairs(self.playerInteractionHideMap) do
        local frame = _G[frameName];
        if type ~= mapType and frame.IsShown and frame:IsShown() then
            HideUIPanel(_G[frameName]);
        end
    end
end

function ns:PLAYER_INTERACTION_MANAGER_FRAME_HIDE(_, type)
    if self.playerInteractionHideMap[type] then
        local frame = _G[self.playerInteractionHideMap[type]];
        if frame and frame.IsShown and frame:IsShown() then
            HideUIPanel(frame);
        end
    end
end

function ns:Init()
    hooksecurefunc('ShowUIPanel', function(frame) self:OnShowUIPanel(frame); end);
    hooksecurefunc('HideUIPanel', function(frame) self:OnHideUIPanel(frame); end);
    hooksecurefunc('RegisterUIPanel', function() self:ADDON_LOADED(); end);
    hooksecurefunc('DisplayInterfaceActionBlockedMessage', function() self:OnDisplayInterfaceActionBlockedMessage(); end);
    hooksecurefunc('RestoreUIPanelArea', function(frame) self:SetDefaultPosition(frame); end);
    self:ReworkSettingsOpenAndClose();

    ns.eventFrame = CreateFrame('Frame');
    ns.eventFrame:HookScript('OnEvent', function(_, event, ...) self[event](self, event, ...); end);
    ns.eventFrame:RegisterEvent('ADDON_LOADED');
    ns.eventFrame:RegisterEvent('PLAYER_INTERACTION_MANAGER_FRAME_SHOW');
    ns.eventFrame:RegisterEvent('PLAYER_INTERACTION_MANAGER_FRAME_HIDE');

    ns.combatLockdownQueue = {};
end

do
    ns:Init();
end