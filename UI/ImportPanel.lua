local _, HSC = ...
local L = HSC.L;
local Cart = HSC.Cart;
local Import = HSC.Import;
local Colors = HSC.Colors;

local FRAME_NAME = "HousingShoppingCartImportFrame";
local WIDTH, HEIGHT = 380, 280;
local LEFT, RIGHT = 24, -24;
local ICON_SIZE = 18;
local RECHECK_SECONDS = 0.5;

local panel;

local function SetStatus(text, color)
	panel.Status:SetText(text or "");
	panel.Status:SetTextColor((color or Colors.Muted):GetRGB());
end

local function UpdateHouse()
	local houses = Import:GetHouses();
	local pick = houses ~= nil and #houses > 1;
	panel.HouseLabel:SetShown(pick);
	panel.HouseDropdown:SetShown(pick);
	panel.HouseText:SetShown(not pick);
	if pick then
		local target = Import:GetTargetHouse();
		panel.HouseDropdown:OverrideText(target and Import.GetHouseLabel(target) or "");
	elseif houses == nil then
		panel.HouseText:SetText(L["Looking for your house..."]);
	elseif #houses == 0 then
		panel.HouseText:SetText(L["You don't own a house, so what's missing is worked out from your collection."]);
	else
		panel.HouseText:SetText(L["Checked against your house: %s"]:format(Import.GetHouseLabel(houses[1])));
	end
end

local function Update()
	if not (panel and panel:IsShown()) then
		return;
	end
	UpdateHouse();
	panel.RecentButton:SetShown(not HSC.Recent:IsEmpty() or HSC.Recent:HasSaved());

	local text = panel.CodeBox:GetText() or "";
	local code = Import.ParseInput(text);
	local request = Import:GetPending();
	local blocked = code and not request and Import:GetBlockedReason();
	if request then
		SetStatus(request.shareCode == code and L["Looking up the blueprint..."] or L["Still waiting for the last blueprint."], Colors.Brass);
	elseif panel.lastError then
		SetStatus(panel.lastError, Colors.Red);
	elseif strtrim(text) == "" then
		SetStatus(L["Paste a blueprint's share code - from a friend, a guide, or your own saved blueprints."]);
	elseif not code then
		SetStatus(HOUSING_BLUEPRINT_IMPORT_SHARECODE_INVALID or L["Not a valid code."], Colors.Red);
	elseif blocked then
		SetStatus(blocked, Colors.Red);
	elseif Cart:HasBlueprint(code) then
		SetStatus(L["%s is already in your cart - adding it again updates it."]:format(Cart:GetBlueprintName(code)), Colors.Brass);
	elseif HSC.db.knownBlueprints[code] then
		SetStatus(L["Your saved blueprint: %s"]:format(Cart:GetBlueprintName(code)), Colors.Green);
	else
		SetStatus(L["%s - ready to add."]:format(Cart:GetBlueprintTypeName(Cart:GetBlueprintType(code))), Colors.Text);
	end

	local canAdd = code ~= nil and not request and not blocked;
	panel.AddButton:SetEnabled(canAdd);
	panel.AddButton.Icon:SetDesaturated(not canAdd);
	panel.AddButton.Icon:SetAlpha(canAdd and 1 or 0.5);
end

local function Submit()
	local code = Import.ParseInput(panel.CodeBox:GetText());
	if not code or Import:IsPending() then
		return;
	end
	local name = strtrim(panel.NameBox:GetText() or "");
	panel.lastError = nil;
	panel.requestCode = code;
	HSC:PlaySound("HOUSING_BLUEPRINTS_BUTTONS");
	local ok, reason = Import:Start(code, { name = name ~= "" and name or nil });
	if not ok then
		panel.lastError = reason;
	end
	Update();
end

local function CreateInput(labelText, y)
	local label = panel:CreateFontString(nil, "ARTWORK", "GameFontNormal");
	label:SetPoint("TOPLEFT", LEFT, y);
	label:SetText(labelText);

	local box = CreateFrame("EditBox", nil, panel, "InputBoxTemplate");
	box:SetHeight(22);
	box:SetPoint("TOPLEFT", label, "BOTTOMLEFT", 6, -4);
	box:SetPoint("RIGHT", panel, "RIGHT", RIGHT, 0);
	box:SetAutoFocus(false);
	box:SetMaxLetters(512);
	box:SetScript("OnEscapePressed", function()
		panel:Hide();
	end);
	box:SetScript("OnEnterPressed", Submit);
	return label, box;
end

local function CreateAddButton()
	local button = CreateFrame("Button", nil, panel, "UIPanelButtonTemplate");
	button:SetSize(220, 26);
	button:SetPoint("BOTTOM", 0, 18);
	button:SetText(L["Add to Shopping Cart"]);
	local fontString = button:GetFontString();
	fontString:ClearAllPoints();
	fontString:SetPoint("CENTER", button, "CENTER", (ICON_SIZE + 5) / 2, 0);
	button.Icon = button:CreateTexture(nil, "ARTWORK");
	button.Icon:SetAtlas("Perks-ShoppingCart");
	button.Icon:SetSize(ICON_SIZE, ICON_SIZE);
	button.Icon:SetPoint("RIGHT", fontString, "LEFT", -5, 0);
	button:SetScript("OnClick", Submit);
	return button;
end

local function Create()
	panel = CreateFrame("Frame", FRAME_NAME, GetAppropriateTopLevelParent());
	panel:Hide();
	panel:SetSize(WIDTH, HEIGHT);
	panel:SetFrameStrata("DIALOG");
	panel:SetToplevel(true);
	panel:SetClampedToScreen(true);
	panel:SetMovable(true);
	panel:EnableMouse(true);
	panel:SetPoint("CENTER", 0, 60);
	HSC.Window.CreatePanelArt(panel, L["Add a Blueprint"], "common-icons-blueprints");
	panel.DragArea:SetScript("OnDragStart", function() panel:StartMoving(); end);
	panel.DragArea:SetScript("OnDragStop", function() panel:StopMovingOrSizing(); end);
	tinsert(UISpecialFrames, FRAME_NAME);
	FrameUtil.RegisterForTopLevelParentChanged(panel);

	panel.CodeLabel, panel.CodeBox = CreateInput(HOUSING_BLUEPRINT_IMPORT_SHARECODE_LABEL or L["Enter Import Code:"], -50);
	panel.NameLabel, panel.NameBox = CreateInput(L["Name in your cart (optional):"], -102);
	panel.CodeBox:SetScript("OnTabPressed", function() panel.NameBox:SetFocus(); end);
	panel.NameBox:SetScript("OnTabPressed", function() panel.CodeBox:SetFocus(); end);
	panel.CodeBox:SetScript("OnTextChanged", function(editBox)
		panel.lastError = nil;
		local _, linkName = Import.ParseInput(editBox:GetText());
		if linkName and strtrim(panel.NameBox:GetText() or "") == "" then
			panel.NameBox:SetText(linkName);
		end
		Update();
	end);

	local recent = CreateFrame("Button", nil, panel);
	recent:SetHeight(16);
	recent:SetPoint("BOTTOMRIGHT", panel.CodeBox, "TOPRIGHT", 0, 3);
	local recentText = recent:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall");
	recentText:SetPoint("RIGHT");
	recentText:SetText(HSC.AtlasIcon("common-icons-blueprints", 14) .. " " .. L["Recent & saved"]);
	recentText:SetTextColor(Colors.Brass:GetRGB());
	recent:SetWidth(recentText:GetStringWidth() + 4);
	recent:SetScript("OnEnter", function() recentText:SetTextColor(Colors.Title:GetRGB()); end);
	recent:SetScript("OnLeave", function() recentText:SetTextColor(Colors.Brass:GetRGB()); end);
	recent:SetScript("OnClick", function(self)
		MenuUtil.CreateContextMenu(self, function(_, rootDescription)
			rootDescription:SetTag("MENU_HOUSINGSHOPPINGCART_RECENT_BLUEPRINTS");
			local withSaved = true;
			HSC.Recent:AddToMenu(rootDescription, function(shareCode)
				panel.NameBox:SetText("");
				panel.CodeBox:SetText(shareCode);
				panel.lastError = nil;
				Submit();
			end, withSaved);
		end);
	end);
	panel.RecentButton = recent;

	local houseLabel = panel:CreateFontString(nil, "ARTWORK", "GameFontNormal");
	houseLabel:SetPoint("TOPLEFT", LEFT, -158);
	houseLabel:SetText(L["Check against:"]);
	panel.HouseLabel = houseLabel;

	local houseDropdown = CreateFrame("DropdownButton", nil, panel, "WowStyle1DropdownTemplate");
	houseDropdown:SetPoint("LEFT", houseLabel, "RIGHT", 10, 0);
	houseDropdown:SetPoint("RIGHT", panel, "RIGHT", RIGHT, 0);
	houseDropdown:SetupMenu(function(_, rootDescription)
		rootDescription:SetTag("MENU_HOUSINGSHOPPINGCART_IMPORT_HOUSE");
		local target = Import:GetTargetHouse();
		for _, info in ipairs(Import:GetHouses() or {}) do
			rootDescription:CreateRadio(Import.GetHouseLabel(info), function()
				return target ~= nil and Import.GetHouseKey(target) == Import.GetHouseKey(info);
			end, function()
				Import:SetTargetHouse(info);
			end);
		end
	end);
	panel.HouseDropdown = houseDropdown;

	local houseText = panel:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall");
	houseText:SetPoint("TOPLEFT", LEFT, -154);
	houseText:SetPoint("RIGHT", panel, "RIGHT", RIGHT, 0);
	houseText:SetJustifyH("LEFT");
	houseText:SetTextColor(Colors.Muted:GetRGB());
	panel.HouseText = houseText;

	local status = panel:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall");
	status:SetPoint("TOPLEFT", LEFT, -194);
	status:SetPoint("RIGHT", panel, "RIGHT", RIGHT, 0);
	status:SetJustifyH("LEFT");
	status:SetSpacing(2);
	panel.Status = status;

	panel.AddButton = CreateAddButton();

	panel:SetScript("OnShow", function()
		Import:RequestHouses();
		Update();
	end);
	panel:SetScript("OnHide", function()
		panel.CodeBox:ClearFocus();
		panel.NameBox:ClearFocus();
	end);
	local sinceCheck = 0;
	panel:SetScript("OnUpdate", function(_, elapsed)
		sinceCheck = sinceCheck + elapsed;
		if sinceCheck >= RECHECK_SECONDS then
			sinceCheck = 0;
			Update();
		end
	end);
end

function HSC:ShowImportPanel(text)
	if not HSC.db then
		return;
	end
	if not panel then
		Create();
	end
	if panel:GetParent() ~= GetAppropriateTopLevelParent() then
		FrameUtil.UpdateTopLevelParent(panel);
	end
	panel.lastError = nil;
	if text then
		panel.NameBox:SetText("");
		panel.CodeBox:SetText(text);
	end
	if panel:IsShown() then
		panel:Raise();
		Update();
	else
		HSC:PlaySound("HOUSING_BLUEPRINTS_BUTTONS");
		panel:Show();
	end
	panel.CodeBox:SetFocus();
	panel.CodeBox:HighlightText();
end

function HSC:HideImportPanel()
	if panel then
		panel:Hide();
	end
end

HSC:On("IMPORT_CHANGED", Update);
HSC:On("CART_CHANGED", Update);
HSC:On("RECENT_CHANGED", Update);
HSC:On("IMPORT_DONE", function(ok, shareCode, result)
	if not (panel and panel:IsShown() and shareCode == panel.requestCode) then
		return;
	end
	panel.requestCode = nil;
	if ok then
		panel.CodeBox:SetText("");
		panel.NameBox:SetText("");
		panel:Hide();
	else
		panel.lastError = result;
		Update();
	end
end);
