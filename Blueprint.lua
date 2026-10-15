local _, HSC = ...
local L = HSC.L;
local Cart = HSC.Cart;
local Colors = HSC.Colors;

local ICON_SIZE = 18;
local CONFIRM_SECONDS = 2;

local list, addButton, cartButton;

local function GetContentInfo()
	local info = list and list.blueprintContentInfo;
	if info and info.contentGroups and info.shareCode then
		return info;
	end
	return nil;
end

local function SetButtonFace(text, iconAtlas)
	addButton:SetText(text);
	addButton.Icon:SetAtlas(iconAtlas);
	local fontString = addButton:GetFontString();
	fontString:ClearAllPoints();
	fontString:SetPoint("CENTER", addButton, "CENTER", (ICON_SIZE + 5) / 2, 0);
end

local function UpdateAddButton()
	if not addButton then
		return;
	end
	if addButton.confirmUntil and GetTime() < addButton.confirmUntil then
		return;
	end
	SetButtonFace(L["Add to Shopping Cart"], "Perks-ShoppingCart");
	local info = GetContentInfo();
	local missingLines = info and Cart:CountMissing(info) or 0;
	local useful = missingLines > 0 or (info ~= nil and Cart:CountShared(info) > 0);
	addButton:SetEnabled(useful);
	addButton.Icon:SetDesaturated(not useful);
	addButton.Icon:SetAlpha(useful and 1 or 0.5);
end

local function UpdateCartButton()
	if not cartButton then
		return;
	end
	local stats = Cart:GetStats();
	cartButton.Count:SetText(stats.left > 0 and stats.left or "");
end

local function ShowAddButtonTooltip(self)
	local info = GetContentInfo();
	GameTooltip:SetOwner(self, "ANCHOR_TOP");
	GameTooltip_SetTitle(GameTooltip, L["Add to Shopping Cart"]);
	if not info then
		GameTooltip:Show();
		return;
	end
	local lines, quantity = Cart:CountMissing(info);
	local shared = Cart:CountShared(info);
	if lines == 0 and shared > 0 then
		GameTooltip_AddHighlightLine(GameTooltip, (shared == 1 and L["You have everything for this blueprint on its own, but 1 of its items is also wanted by the blueprints in your cart."]
			or L["You have everything for this blueprint on its own, but %d of its items are also wanted by the blueprints in your cart."]):format(shared));
		GameTooltip_AddNormalLine(GameTooltip, L["Adding it makes the cart count its copies too."]);
	elseif lines == 0 then
		GameTooltip_AddColoredLine(GameTooltip, L["You already have everything in this blueprint."], Colors.Green);
	else
		GameTooltip_AddHighlightLine(GameTooltip, (lines == 1) and L["Adds the 1 missing item (%d in total) to your Shopping Cart."]:format(quantity)
			or L["Adds the %d missing items (%d in total) to your Shopping Cart."]:format(lines, quantity));
		GameTooltip_AddNormalLine(GameTooltip, L["Hover an item in the cart to see how to get it."]);
		if info.targetHouseGUID == nil then
			GameTooltip_AddBlankLineToTooltip(GameTooltip);
			GameTooltip_AddColoredLine(GameTooltip, L["You're not at your house, so what's missing is worked out from your collection."], Colors.Muted);
		end
		if Cart:HasBlueprint(info.shareCode) then
			GameTooltip_AddBlankLineToTooltip(GameTooltip);
			GameTooltip_AddColoredLine(GameTooltip, L["This blueprint is already in your cart - adding it again updates it."], Colors.Brass);
		end
	end
	GameTooltip:Show();
end

local function OnAddClicked(self)
	local info = GetContentInfo();
	if not info or not HSC.db then
		return;
	end
	local summary = Cart:AddBlueprint(info);
	HSC.Recent:Remember(info.shareCode);
	HSC:PlaySound("LOOT_WINDOW_COIN_SOUND");
	Cart:PrintAddSummary(summary, info.shareCode);

	local confirmUntil = GetTime() + CONFIRM_SECONDS;
	self.confirmUntil = confirmUntil;
	SetButtonFace(L["Added to Cart!"], "common-icon-checkmark");
	C_Timer.After(CONFIRM_SECONDS, function()
		if self.confirmUntil == confirmUntil then
			self.confirmUntil = nil;
			UpdateAddButton();
		end
	end);

	if HSC.settings.openOnAdd then
		HSC:ShowWindow(list);
	end
	if GameTooltip:GetOwner() == self then
		ShowAddButtonTooltip(self);
	end
end

local function CreateAddButton()
	addButton = CreateFrame("Button", "HousingShoppingCartAddButton", list, "UIPanelButtonTemplate");
	addButton:SetHeight(28);
	addButton:SetMotionScriptsWhileDisabled(true);

	local close = list.BottomCloseButton;
	if close then
		close:ClearAllPoints();
		close:SetPoint("BOTTOMRIGHT", list, "BOTTOMRIGHT", -14, 10);
		addButton:SetPoint("BOTTOMLEFT", list, "BOTTOMLEFT", 14, 10);
		addButton:SetPoint("RIGHT", close, "LEFT", -8, 0);
	else
		addButton:SetPoint("BOTTOMLEFT", list, "BOTTOMLEFT", 14, 10);
		addButton:SetPoint("BOTTOMRIGHT", list, "BOTTOMRIGHT", -14, 10);
	end

	addButton.Icon = addButton:CreateTexture(nil, "ARTWORK");
	addButton.Icon:SetSize(ICON_SIZE, ICON_SIZE);
	addButton.Icon:SetPoint("RIGHT", addButton:GetFontString(), "LEFT", -5, 0);

	addButton:SetScript("OnClick", OnAddClicked);
	addButton:SetScript("OnEnter", ShowAddButtonTooltip);
	addButton:SetScript("OnLeave", GameTooltip_Hide);
	HSC.addButton = addButton;
end

local function CreateCartButton()
	cartButton = CreateFrame("Button", nil, list);
	cartButton:SetSize(24, 24);
	if list.Header then
		cartButton:SetPoint("LEFT", list.Header, "LEFT", 10, 0);
	else
		cartButton:SetPoint("TOPLEFT", list, "TOPLEFT", 6, 2);
	end

	local icon = cartButton:CreateTexture(nil, "ARTWORK");
	icon:SetAtlas("Perks-ShoppingCart");
	icon:SetAllPoints();
	local highlight = cartButton:CreateTexture(nil, "HIGHLIGHT");
	highlight:SetAtlas("Perks-ShoppingCart");
	highlight:SetAllPoints();
	highlight:SetBlendMode("ADD");
	highlight:SetAlpha(0.4);

	cartButton.Count = cartButton:CreateFontString(nil, "OVERLAY", "NumberFontNormalSmall");
	cartButton.Count:SetPoint("BOTTOMRIGHT", 5, -2);

	cartButton:SetScript("OnClick", function()
		if HSC.Window:IsShown() then
			HSC.Window:Hide();
		else
			HSC:ShowWindow(list);
		end
	end);
	cartButton:SetScript("OnEnter", function(self)
		GameTooltip:SetOwner(self, "ANCHOR_TOP");
		HSC:AddSummaryToTooltip(GameTooltip);
		GameTooltip_AddInstructionLine(GameTooltip, L["Click to open the Shopping Cart"]);
		GameTooltip:Show();
	end);
	cartButton:SetScript("OnLeave", GameTooltip_Hide);
end

local function Update()
	UpdateAddButton();
	UpdateCartButton();
end

local function OnBlueprintAddOnLoaded()
	list = _G.HousingBlueprintContentListFrame;
	if not list or addButton then
		return;
	end
	CreateAddButton();
	CreateCartButton();

	if list.ShowBlueprintContents then
		hooksecurefunc(list, "ShowBlueprintContents", Update);
	end
	if list.ClearData then
		hooksecurefunc(list, "ClearData", Update);
	end
	list:HookScript("OnShow", Update);
	Update();
end

EventUtil.ContinueOnAddOnLoaded("Blizzard_HousingBlueprint", OnBlueprintAddOnLoaded);

HSC:On("CART_CHANGED", Update);
HSC:On("CART_REFRESH", Update);

EventRegistry:RegisterCallback("HousingBlueprintContentEntry.MouseOver", function(_, entryFrame, tooltip)
	HSC.Tooltip.OnBlizzardEntryMouseOver(entryFrame, tooltip);
end, HSC);
