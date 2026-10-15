local _, HSC = ...
local L = HSC.L;
local Cart = HSC.Cart;
local Recent = HSC.Recent;
local Colors = HSC.Colors;

local BAR_WIDTH, BAR_HEIGHT = 350, 44;
local CHECK_SIZE = 20;

local importFrame, summary, bar;
local autoAddedCode;

local function GetLoadedContent()
	local info = summary and summary.blueprintContentInfo;
	if type(info) == "table" and info.shareCode and info.contentGroups then
		return info;
	end
	return nil;
end

local function AutoAdd(info)
	if autoAddedCode == info.shareCode or not HSC.db then
		return;
	end
	autoAddedCode = info.shareCode;
	local name = Cart:GetBlueprintName(info.shareCode);
	if Cart:CountMissing(info) == 0 and Cart:CountShared(info) == 0 then
		if HSC.settings.addSummary then
			HSC:Print(L["You already have everything for %s."]:format("|cffffd200" .. name .. "|r"));
		end
		return;
	end
	local added = Cart:AddBlueprint(info);
	HSC:PlaySound("LOOT_WINDOW_COIN_SOUND");
	Cart:PrintAddSummary(added, info.shareCode);
	local count = added.newLines + added.updatedLines;
	if count > 0 then
		HSC.Toast:Queue({
			label = L["Added to your Shopping Cart"],
			name = name,
			detail = count == 1 and L["1 missing item"] or L["%d missing items"]:format(count),
			iconAtlas = "Perks-ShoppingCart",
		});
	end
	if HSC.settings.openOnAdd then
		HSC:ShowWindow(importFrame);
	end
end

function HSC:SetAutoAdd(enabled)
	self.settings.autoAdd = enabled and true or false;
	local info = GetLoadedContent();
	if self.settings.autoAdd and info and importFrame:IsVisible() then
		AutoAdd(info);
	end
	self:Fire("AUTO_ADD_CHANGED");
end

local function OnContentsReceived()
	local info = GetLoadedContent();
	if not info then
		return;
	end
	Recent:Remember(info.shareCode);
	if HSC.settings and HSC.settings.autoAdd then
		AutoAdd(info);
	end
end

local function LoadInImportWindow(shareCode)
	if InCombatLockdown() then
		HSC:Print(L["That window can't be opened during combat."]);
		return;
	end
	if HousingFramesUtil and HousingFramesUtil.ShowBlueprintImport then
		HousingFramesUtil.ShowBlueprintImport(shareCode);
	end
end

local function UpdateBar()
	if not bar then
		return;
	end
	local on = HSC.settings and HSC.settings.autoAdd;
	bar.Auto.Check:SetShown(on == true);
	bar.Auto.Label:SetTextColor((on and Colors.Title or Colors.Muted):GetRGB());
	bar.Recent:SetEnabled(not Recent:IsEmpty());
end

local function ShowAutoTooltip(owner)
	GameTooltip:SetOwner(owner, "ANCHOR_BOTTOM");
	GameTooltip_SetTitle(GameTooltip, L["Add to cart automatically"]);
	GameTooltip_AddNormalLine(GameTooltip, L["As soon as a blueprint loads here, everything it needs that you don't have goes into your Shopping Cart - no View List needed."]);
	GameTooltip_AddBlankLineToTooltip(GameTooltip);
	GameTooltip_AddColoredLine(GameTooltip, L["Off: add it yourself with Add to Shopping Cart in the Blueprint List."], Colors.Muted);
	GameTooltip:Show();
end

local function CreateAutoCheckbox(parent)
	local check = CreateFrame("Button", nil, parent);
	check:SetSize(CHECK_SIZE, CHECK_SIZE);

	local box = check:CreateTexture(nil, "ARTWORK");
	box:SetAtlas("checkbox-minimal");
	box:SetSize(CHECK_SIZE, CHECK_SIZE);
	box:SetPoint("LEFT");
	local mark = check:CreateTexture(nil, "OVERLAY");
	mark:SetAtlas("checkmark-minimal");
	mark:SetAllPoints(box);
	check.Check = mark;

	local label = check:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall");
	label:SetPoint("LEFT", box, "RIGHT", 4, 0);
	label:SetText(L["Add to cart automatically"]);
	check.Label = label;
	check:SetWidth(CHECK_SIZE + 4 + label:GetStringWidth());

	local highlight = check:CreateTexture(nil, "HIGHLIGHT");
	highlight:SetAtlas("checkbox-minimal");
	highlight:SetAllPoints(box);
	highlight:SetBlendMode("ADD");
	highlight:SetAlpha(0.35);

	check:SetScript("OnClick", function(self)
		local enabled = not HSC.settings.autoAdd;
		HSC:PlaySound(enabled and "IG_MAINMENU_OPTION_CHECKBOX_ON" or "IG_MAINMENU_OPTION_CHECKBOX_OFF");
		HSC:SetAutoAdd(enabled);
		ShowAutoTooltip(self);
	end);
	check:SetScript("OnEnter", ShowAutoTooltip);
	check:SetScript("OnLeave", GameTooltip_Hide);
	return check;
end

local function CreateBar()
	bar = CreateFrame("Frame", "HousingShoppingCartImportBar", importFrame:GetParent(), "BackdropTemplate");
	bar:Hide();
	bar:SetSize(BAR_WIDTH, BAR_HEIGHT);
	bar:EnableMouse(true);
	bar:SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8x8", edgeFile = "Interface\\Buttons\\WHITE8x8", edgeSize = 1 });
	bar:SetBackdropColor(0.05, 0.035, 0.02, 0.92);
	bar:SetBackdropBorderColor(Colors.Brass.r, Colors.Brass.g, Colors.Brass.b, 0.55);

	local icon = bar:CreateTexture(nil, "ARTWORK");
	icon:SetAtlas("Perks-ShoppingCart");
	icon:SetSize(20, 20);
	icon:SetPoint("LEFT", 12, 0);

	local recent = CreateFrame("DropdownButton", nil, bar, "WowStyle1DropdownTemplate");
	recent:SetWidth(150);
	recent:SetPoint("LEFT", icon, "RIGHT", 8, 0);
	recent:SetDefaultText(L["Recent Blueprints"]);
	recent:SetupMenu(function(_, rootDescription)
		rootDescription:SetTag("MENU_HOUSINGSHOPPINGCART_RECENT_IMPORTS");
		local withSaved = false;
		Recent:AddToMenu(rootDescription, LoadInImportWindow, withSaved);
	end);
	bar.Recent = recent;

	bar.Auto = CreateAutoCheckbox(bar);
	bar.Auto:SetPoint("RIGHT", -12, 0);
end

local function SyncBar()
	if not (importFrame and importFrame:IsShown()) then
		return;
	end
	if not bar then
		CreateBar();
	end
	if bar:GetParent() ~= importFrame:GetParent() then
		bar:SetParent(importFrame:GetParent());
	end
	bar:SetFrameStrata(importFrame:GetFrameStrata());
	bar:SetFrameLevel(importFrame:GetFrameLevel() + 10);
	bar:ClearAllPoints();
	bar:SetPoint("TOP", importFrame, "BOTTOM", 0, -4);
	UpdateBar();
	bar:Show();
end

local function OnImportFrameHidden()
	if bar then
		bar:Hide();
	end
end

local function Guarded(callback)
	return function(...)
		local ok, err = pcall(callback, ...);
		if not ok then
			geterrorhandler()(err);
		end
	end
end

EventUtil.ContinueOnAddOnLoaded("Blizzard_HousingBlueprint", function()
	importFrame = _G.HousingBlueprintImportFrame;
	summary = importFrame and importFrame.ValidationContent and importFrame.ValidationContent.ContentSummary;
	if not (summary and summary.OnBlueprintContentsReceived) then
		return;
	end
	hooksecurefunc(summary, "OnBlueprintContentsReceived", Guarded(OnContentsReceived));
	if importFrame.ClearData then
		hooksecurefunc(importFrame, "ClearData", function()
			autoAddedCode = nil;
		end);
	end
	if importFrame.ShowSelf then
		hooksecurefunc(importFrame, "ShowSelf", Guarded(SyncBar));
	end
	importFrame:HookScript("OnShow", Guarded(SyncBar));
	importFrame:HookScript("OnHide", Guarded(OnImportFrameHidden));
end);

HSC:On("RECENT_CHANGED", UpdateBar);
HSC:On("AUTO_ADD_CHANGED", UpdateBar);
