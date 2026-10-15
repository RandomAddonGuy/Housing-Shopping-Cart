local _, HSC = ...
local L = HSC.L;
local Data = HSC.Data;
local Cart = HSC.Cart;
local Colors = HSC.Colors;

local Window = {};
HSC.Window = Window;

local FRAME_NAME = "HousingShoppingCartFrame";
local DEFAULT_WIDTH, DEFAULT_HEIGHT = 420, 600;
local MIN_WIDTH, MIN_HEIGHT = 360, 420;
local MAX_WIDTH, MAX_HEIGHT = 760, 1100;
local ROW_HEIGHT, HEADER_HEIGHT = 44, 26;

local frame;

local GROUPINGS = {
	{ key = "type",      label = TYPE or L["Type"] },
	{ key = "source",    label = L["Source"] },
	{ key = "zone",      label = ZONE or L["Zone"] },
	{ key = "blueprint", label = L["Blueprint"] },
};

local function GetGroups(line)
	local mode = HSC.settings.groupBy;
	if mode == "source" then
		local primary = Data.GetPrimarySource(line);
		if not primary then
			if Data.IsCountable(line.contentType) then
				local info = Data.GetKindInfo("other");
				return { { key = "kind:other", label = info.label, atlas = info.atlas, order = info.order } };
			end
			return { { key = "kind:unlock", label = L["Unlocks"], atlas = "house-room-limit-icon", order = 98 } };
		end
		local info = Data.GetKindInfo(primary.kind);
		return { { key = "kind:" .. primary.kind, label = info.label, atlas = info.atlas, order = info.order } };
	elseif mode == "zone" then
		local primary = Data.GetPrimarySource(line);
		if primary and primary.zone then
			return { { key = "zone:" .. primary.zone, label = primary.zone, atlas = "Waypoint-MapPin-ChatIcon", order = 1 } };
		end
		return { { key = "zone:", label = L["No specific place"], atlas = "house-chest-icon", order = 2 } };
	elseif mode == "blueprint" then
		local groups = {};
		for shareCode in pairs(line.from or {}) do
			if not Window.blueprintFilter or shareCode == Window.blueprintFilter then
				local blueprint = HSC.db.blueprints[shareCode];
				groups[#groups + 1] = {
					key = "bp:" .. shareCode,
					label = Cart:GetBlueprintName(shareCode),
					atlas = "common-icons-blueprints",
					order = blueprint and blueprint.addedAt or 0,
					shareCode = shareCode,
				};
			end
		end
		if #groups == 0 then
			groups[1] = { key = "bp:", label = OTHER or L["Other"], atlas = "house-chest-icon", order = math.huge };
		end
		return groups;
	end
	local info = Data.GetTypeInfo(line.contentType);
	return { { key = "type:" .. line.contentType, label = info.label, atlas = info.atlas, order = info.order } };
end

local function MatchesSearch(line, query)
	if query == "" then
		return true;
	end
	local display = Data.GetDisplay(line.contentType, line.recordID, line.name);
	if display.name and strlower(display.name):find(query, 1, true) then
		return true;
	end
	for _, source in ipairs(Data.GetSources(line)) do
		if Data.SourceMentions(source, query) then
			return true;
		end
	end
	return false;
end

function Window:BuildDataProvider(expandAll)
	local query = strlower(strtrim(self.searchText or ""));
	local hideCollected = HSC.settings.hideCollected;
	local blueprintFilter = self.blueprintFilter;
	local groupsByKey, groupList = {}, {};
	local visible, total = 0, 0;

	for _, line in pairs(Cart:GetLines()) do
		total = total + 1;
		local include = not (hideCollected and Cart:IsCollected(line))
			and (not blueprintFilter or (line.from and line.from[blueprintFilter] ~= nil))
			and MatchesSearch(line, query);
		if include then
			visible = visible + 1;
			for _, group in ipairs(GetGroups(line)) do
				local existing = groupsByKey[group.key];
				if not existing then
					existing = group;
					existing.lines = {};
					groupsByKey[group.key] = existing;
					groupList[#groupList + 1] = existing;
				end
				existing.lines[#existing.lines + 1] = line;
			end
		end
	end

	table.sort(groupList, function(a, b)
		if a.order ~= b.order then
			return a.order < b.order;
		end
		return strcmputf8i(a.label, b.label) < 0;
	end);

	local provider = CreateDataProvider();
	for _, group in ipairs(groupList) do
		local names, collectedState = {}, {};
		local got, need = 0, 0;
		for _, line in ipairs(group.lines) do
			local lineGot, lineNeed, _, collected = Cart:GetProgress(line);
			got, need = got + lineGot, need + lineNeed;
			names[line] = Data.GetDisplay(line.contentType, line.recordID, line.name).name or "";
			collectedState[line] = collected;
		end
		table.sort(group.lines, function(a, b)
			if collectedState[a] ~= collectedState[b] then
				return not collectedState[a];
			end
			return strcmputf8i(names[a], names[b]) < 0;
		end);

		local collapsed = HSC.db.collapsed[group.key] == true;
		provider:Insert({
			isHeader = true,
			key = group.key,
			label = group.label,
			atlas = group.atlas,
			got = got,
			need = need,
			collapsed = collapsed,
			shareCode = group.shareCode,
		});
		if expandAll or not collapsed then
			for index, line in ipairs(group.lines) do
				provider:Insert({ line = line, odd = (index % 2 == 0), groupKey = group.key });
			end
		end
	end
	return provider, visible, total;
end

function HSC:ToggleGroupCollapsed(key)
	local collapsed = HSC.db.collapsed;
	if collapsed[key] then
		collapsed[key] = nil;
		HSC:PlaySound("HOUSING_CATALOG_EXPAND");
	else
		collapsed[key] = true;
		HSC:PlaySound("HOUSING_CATALOG_COLLAPSE");
	end
	Window:Refresh();
end

local function GetDialogEditBox(dialog)
	return (dialog.GetEditBox and dialog:GetEditBox()) or dialog.editBox;
end

StaticPopupDialogs["HOUSINGSHOPPINGCART_RENAME"] = {
	text = L["Name this blueprint:"],
	button1 = ACCEPT,
	button2 = CANCEL,
	hasEditBox = 1,
	maxLetters = 64,
	timeout = 0,
	whileDead = 1,
	hideOnEscape = 1,
	OnShow = function(dialog, shareCode)
		local editBox = GetDialogEditBox(dialog);
		editBox:SetText(Cart:GetBlueprintName(shareCode));
		editBox:HighlightText();
		editBox:SetFocus();
	end,
	OnAccept = function(dialog, shareCode)
		Cart:RenameBlueprint(shareCode, GetDialogEditBox(dialog):GetText());
	end,
	EditBoxOnEnterPressed = function(editBox, shareCode)
		Cart:RenameBlueprint(shareCode, editBox:GetText());
		editBox:GetParent():Hide();
	end,
	EditBoxOnEscapePressed = function(editBox)
		editBox:GetParent():Hide();
	end,
};

function HSC:ShowRenameDialog(shareCode)
	StaticPopup_Show("HOUSINGSHOPPINGCART_RENAME", nil, nil, shareCode);
end

local function UpdateBlueprint(shareCode)
	local ok, reason = HSC.Import:Start(shareCode);
	if ok then
		HSC:Print(L["Checking %s again..."]:format(Cart:GetBlueprintName(shareCode)));
	else
		HSC:Print(reason);
	end
end

local function AddBlueprintActions(description, shareCode)
	if shareCode ~= Cart.BY_HAND then
		description:CreateButton(L["Update missing items"], function()
			UpdateBlueprint(shareCode);
		end);
		description:CreateButton(L["Rename..."], function()
			HSC:ShowRenameDialog(shareCode);
		end);
		description:CreateButton(L["Show share code"], function()
			Window:ShowCopyBox(Cart:GetBlueprintName(shareCode), shareCode);
		end);
	end
	description:CreateButton(L["Remove from cart"], function()
		if Window.blueprintFilter == shareCode then
			Window.blueprintFilter = nil;
		end
		Cart:RemoveBlueprint(shareCode);
	end);
end

function HSC:OpenBlueprintMenu(owner, shareCode)
	MenuUtil.CreateContextMenu(owner, function(_, rootDescription)
		rootDescription:SetTag("MENU_HOUSINGSHOPPINGCART_BLUEPRINT");
		rootDescription:CreateTitle(Cart:GetBlueprintName(shareCode));
		AddBlueprintActions(rootDescription, shareCode);
	end);
end

local copyFrame;

local function CreatePanelArt(panel, titleText, iconAtlas)
	local background = panel:CreateTexture(nil, "BACKGROUND", nil, 0);
	background:SetAtlas("housing-basic-container");
	background:SetPoint("TOPLEFT", -10, 10);
	background:SetPoint("BOTTOMRIGHT", 10, -10);
	if background.SetTexelSnappingBias then
		background:SetTexelSnappingBias(0);
		background:SetSnapToPixelGrid(false);
	end

	local header = panel:CreateTexture(nil, "BACKGROUND", nil, 1);
	header:SetAtlas("housing-basic-container-woodheader");
	header:SetHeight(32);
	header:SetPoint("TOPLEFT", background, "TOPLEFT", 5, -5);
	header:SetPoint("TOPRIGHT", background, "TOPRIGHT", -5, -5);

	local title = panel:CreateFontString(nil, "ARTWORK", "GameFontHighlightMed2");
	title:SetPoint("CENTER", header, "CENTER", iconAtlas and 11 or 0, 0);
	title:SetTextColor(Colors.Title:GetRGB());
	title:SetText(titleText);

	if iconAtlas then
		local icon = panel:CreateTexture(nil, "ARTWORK");
		icon:SetAtlas(iconAtlas);
		icon:SetSize(22, 22);
		icon:SetPoint("RIGHT", title, "LEFT", -5, 0);
		panel.TitleIcon = icon;
	end

	local close = CreateFrame("Button", nil, panel, "UIPanelCloseButtonNoScripts");
	close:SetPoint("TOPRIGHT", 12, 8);
	close:SetScript("OnClick", function()
		panel:Hide();
	end);

	local drag = CreateFrame("Frame", nil, panel);
	drag:SetPoint("TOPLEFT", header, "TOPLEFT");
	drag:SetPoint("BOTTOMRIGHT", header, "BOTTOMRIGHT", -34, 0);
	drag:EnableMouse(true);
	drag:RegisterForDrag("LeftButton");
	close:SetFrameLevel(drag:GetFrameLevel() + 2);

	panel.Background, panel.Header, panel.Title, panel.CloseButton, panel.DragArea = background, header, title, close, drag;
end
Window.CreatePanelArt = CreatePanelArt;

function Window:ShowCopyBox(titleText, text)
	if not copyFrame then
		copyFrame = CreateFrame("Frame", "HousingShoppingCartCopyFrame", GetAppropriateTopLevelParent());
		copyFrame:SetSize(400, 320);
		copyFrame:SetFrameStrata("DIALOG");
		copyFrame:SetToplevel(true);
		copyFrame:SetClampedToScreen(true);
		copyFrame:SetMovable(true);
		copyFrame:EnableMouse(true);
		copyFrame:SetPoint("CENTER");
		CreatePanelArt(copyFrame, "", nil);
		copyFrame.DragArea:SetScript("OnDragStart", function() copyFrame:StartMoving(); end);
		copyFrame.DragArea:SetScript("OnDragStop", function() copyFrame:StopMovingOrSizing(); end);
		tinsert(UISpecialFrames, "HousingShoppingCartCopyFrame");
		FrameUtil.RegisterForTopLevelParentChanged(copyFrame);

		local hint = copyFrame:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall");
		hint:SetPoint("BOTTOM", 0, 14);
		hint:SetTextColor(Colors.Muted:GetRGB());
		hint:SetText(L["Press Ctrl+C to copy, then paste it anywhere."]);

		local scroll = CreateFrame("ScrollFrame", nil, copyFrame, "InputScrollFrameTemplate");
		scroll:SetPoint("TOPLEFT", 20, -46);
		scroll:SetPoint("BOTTOMRIGHT", -30, 38);
		if scroll.CharCount then
			scroll.CharCount:Hide();
		end
		scroll.EditBox:SetFontObject("GameFontHighlightSmall");
		scroll.EditBox:SetScript("OnEscapePressed", function()
			copyFrame:Hide();
		end);
		copyFrame.Scroll = scroll;
	end

	if copyFrame:GetParent() ~= GetAppropriateTopLevelParent() then
		FrameUtil.UpdateTopLevelParent(copyFrame);
	end
	copyFrame.Title:SetText(titleText or "");
	copyFrame:Show();
	local editBox = copyFrame.Scroll.EditBox;
	editBox:SetWidth(copyFrame.Scroll:GetWidth() - 18);
	editBox:SetText(text or "");
	editBox:SetCursorPosition(0);
	editBox:HighlightText();
	editBox:SetFocus();
end

local function PlainText(text)
	if not text then
		return "";
	end
	return (text:gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", ""):gsub("|T.-|t", ""):gsub("|A.-|a", ""):gsub("|H.-|h(.-)|h", "%1"));
end

local function PlainMoney(copper)
	local gold, silver, rest = floor(copper / 10000), floor(copper / 100) % 100, copper % 100;
	local parts = {};
	if gold > 0 then
		parts[#parts + 1] = BreakUpLargeNumbers(gold) .. (GOLD_AMOUNT_SYMBOL or "g");
	end
	if silver > 0 then
		parts[#parts + 1] = silver .. (SILVER_AMOUNT_SYMBOL or "s");
	end
	if rest > 0 or #parts == 0 then
		parts[#parts + 1] = rest .. (COPPER_AMOUNT_SYMBOL or "c");
	end
	return table.concat(parts, " ");
end

local function PlainCost(cost, quantity)
	if not cost then
		return nil;
	end
	local parts = {};
	if cost.copper then
		parts[#parts + 1] = PlainMoney(cost.copper * quantity);
	end
	if cost.currencyID then
		local _, info = Data.GetCurrencyOwned(cost.currencyID);
		parts[#parts + 1] = ("%s %s"):format(BreakUpLargeNumbers((cost.amount or 0) * quantity), info and info.name or "");
	end
	return table.concat(parts, " + ");
end

function Window:BuildPlainText()
	local out = {};
	local stats = Cart:GetStats();
	out[#out + 1] = ("%s - %s"):format(L["Housing Shopping Cart"], L["%d of %d items collected"]:format(stats.got, stats.need));
	local expandAll = true;
	local provider = self:BuildDataProvider(expandAll);
	for _, elementData in provider:Enumerate() do
		if elementData.isHeader then
			out[#out + 1] = "";
			out[#out + 1] = ("== %s (%d/%d) =="):format(elementData.label, elementData.got, elementData.need);
		else
			local line = elementData.line;
			local _, _, left, collected = Cart:GetProgress(line);
			local display = Data.GetDisplay(line.contentType, line.recordID, line.name);
			local entry = ("%s %dx %s"):format(collected and "[x]" or "[ ]", collected and (line.need or 0) or left, display.name);
			local primary = Data.GetPrimarySource(line);
			if primary and not collected then
				local where = primary.name or "";
				if primary.zone then
					where = where .. ", " .. table.concat(Data.GetZones(primary), " / ");
				end
				local cost = primary.cost and PlainCost(primary.cost, left);
				entry = entry .. " - " .. PlainText(where) .. (cost and (" (" .. cost .. ")") or "");
			end
			out[#out + 1] = entry;
		end
	end
	return table.concat(out, "\n");
end

local function SetClosedByEscape(closable)
	for index = #UISpecialFrames, 1, -1 do
		if UISpecialFrames[index] == FRAME_NAME then
			table.remove(UISpecialFrames, index);
		end
	end
	if closable then
		tinsert(UISpecialFrames, FRAME_NAME);
	end
end

function Window:IsLocked()
	return HSC.settings ~= nil and HSC.settings.windowLocked == true;
end

local function UpdateLockButton()
	local button = frame and frame.LockButton;
	if not button then
		return;
	end
	local locked = Window:IsLocked();
	button.Icon:SetDesaturated(not locked);
	button.Icon:SetAlpha(locked and 1 or 0.45);
end

function Window:SetLocked(locked)
	HSC.settings.windowLocked = locked and true or false;
	SetClosedByEscape(not locked);
	UpdateLockButton();
	HSC:PlaySound(locked and "IG_MAINMENU_OPTION_CHECKBOX_ON" or "IG_MAINMENU_OPTION_CHECKBOX_OFF");
end

local function CreateLockButton(parent)
	local button = CreateFrame("Button", nil, parent);
	button:SetSize(16, 19);
	button:SetPoint("RIGHT", parent.CloseButton, "LEFT", 0, 0);
	button:SetFrameLevel(parent.CloseButton:GetFrameLevel());

	local icon = button:CreateTexture(nil, "ARTWORK");
	icon:SetAtlas("QuestSharing-QuestLog-Padlock");
	icon:SetAllPoints();
	button.Icon = icon;

	local highlight = button:CreateTexture(nil, "HIGHLIGHT");
	highlight:SetAtlas("QuestSharing-QuestLog-Padlock");
	highlight:SetAllPoints();
	highlight:SetBlendMode("ADD");
	highlight:SetAlpha(0.4);

	button:SetScript("OnClick", function(self)
		Window:SetLocked(not Window:IsLocked());
		if self:IsMouseOver() then
			self:GetScript("OnEnter")(self);
		end
	end);
	button:SetScript("OnEnter", function(self)
		GameTooltip:SetOwner(self, "ANCHOR_RIGHT");
		if Window:IsLocked() then
			GameTooltip_SetTitle(GameTooltip, L["Window locked"]);
			GameTooltip_AddNormalLine(GameTooltip, L["Stays open through Esc, loading screens and the House Editor until you close it yourself, and reopens after a reload."]);
			GameTooltip_AddInstructionLine(GameTooltip, L["<Click to unlock>"]);
		else
			GameTooltip_SetTitle(GameTooltip, L["Lock window"]);
			GameTooltip_AddNormalLine(GameTooltip, L["Keep the cart open through Esc, loading screens and the House Editor until you close it yourself."]);
			GameTooltip_AddInstructionLine(GameTooltip, L["<Click to lock>"]);
		end
		GameTooltip:Show();
	end);
	button:SetScript("OnLeave", GameTooltip_Hide);
	return button;
end

local function CreateBrowseButton(parent)
	local button = CreateFrame("Button", nil, parent);
	button:SetSize(22, 22);
	button:SetPoint("LEFT", parent.Header, "LEFT", 8, 0);
	button:SetFrameLevel(parent.DragArea:GetFrameLevel() + 2);
	local icon = button:CreateTexture(nil, "ARTWORK");
	icon:SetAtlas("house-chest-icon");
	icon:SetAllPoints();
	local highlight = button:CreateTexture(nil, "HIGHLIGHT");
	highlight:SetAtlas("house-chest-icon");
	highlight:SetAllPoints();
	highlight:SetBlendMode("ADD");
	highlight:SetAlpha(0.45);
	button:SetScript("OnClick", function()
		HSC:ToggleBrowser();
	end);
	button:SetScript("OnEnter", function(self)
		GameTooltip:SetOwner(self, "ANCHOR_RIGHT");
		GameTooltip_SetTitle(GameTooltip, L["Decor Browser"]);
		GameTooltip_AddNormalLine(GameTooltip, L["Every decor in the game: search it, see how to get it, and add any of it to your cart."]);
		GameTooltip:Show();
	end);
	button:SetScript("OnLeave", GameTooltip_Hide);
	return button;
end

local function CreateProgressBar(parent)
	local bar = CreateFrame("Frame", nil, parent, "BackdropTemplate");
	bar:SetHeight(14);
	bar:SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8x8", edgeFile = "Interface\\Buttons\\WHITE8x8", edgeSize = 1 });
	bar:SetBackdropColor(0.05, 0.035, 0.02, 0.85);
	bar:SetBackdropBorderColor(Colors.Brass.r, Colors.Brass.g, Colors.Brass.b, 0.45);

	local fill = bar:CreateTexture(nil, "ARTWORK");
	fill:SetPoint("TOPLEFT", 1, -1);
	fill:SetPoint("BOTTOMLEFT", 1, 1);
	fill:SetColorTexture(1, 1, 1, 1);
	fill:SetWidth(1);

	local shine = bar:CreateTexture(nil, "ARTWORK", nil, 1);
	shine:SetPoint("TOPLEFT", fill, "TOPLEFT");
	shine:SetPoint("TOPRIGHT", fill, "TOPRIGHT");
	shine:SetHeight(5);
	shine:SetColorTexture(1, 1, 1, 1);
	shine:SetGradient("VERTICAL", CreateColor(1, 1, 1, 0), CreateColor(1, 1, 1, 0.22));

	local text = bar:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall");
	text:SetPoint("CENTER", 0, 0);

	function bar:SetProgress(got, need)
		local fraction = need > 0 and math.min(got / need, 1) or 0;
		self.fraction = fraction;
		local width = math.max((self:GetWidth() - 2) * fraction, 0.001);
		fill:SetWidth(width);
		fill:SetShown(fraction > 0);
		shine:SetShown(fraction > 0);
		if need > 0 and got >= need then
			fill:SetGradient("HORIZONTAL", CreateColor(0.22, 0.55, 0.20, 1), CreateColor(0.45, 0.85, 0.38, 1));
		else
			fill:SetGradient("HORIZONTAL", CreateColor(0.62, 0.38, 0.14, 1), CreateColor(1.00, 0.78, 0.34, 1));
		end
		text:SetText(need > 0 and L["%d / %d collected"]:format(got, need) or "");
	end

	bar:SetScript("OnSizeChanged", function(self)
		if self.fraction then
			fill:SetWidth(math.max((self:GetWidth() - 2) * self.fraction, 0.001));
		end
	end);
	return bar;
end

local function CreateEmptyState(parent)
	local empty = CreateFrame("Frame", nil, parent);
	empty:SetPoint("TOPLEFT", 20, -20);
	empty:SetPoint("BOTTOMRIGHT", -20, 20);

	local icon = empty:CreateTexture(nil, "ARTWORK");
	icon:SetAtlas("housing-map-cart");
	icon:SetSize(72, 72);
	icon:SetPoint("BOTTOM", empty, "CENTER", 0, 40);
	icon:SetAlpha(0.85);

	local title = empty:CreateFontString(nil, "ARTWORK", "GameFontNormalLarge");
	title:SetPoint("TOP", icon, "BOTTOM", 0, -10);
	title:SetTextColor(Colors.Title:GetRGB());

	local body = empty:CreateFontString(nil, "ARTWORK", "GameFontHighlight");
	body:SetPoint("TOP", title, "BOTTOM", 0, -8);
	body:SetWidth(270);
	body:SetSpacing(3);
	body:SetTextColor(Colors.Muted:GetRGB());

	local addButton = CreateFrame("Button", nil, empty, "UIPanelButtonTemplate");
	addButton:SetSize(220, 26);
	addButton:SetPoint("TOP", body, "BOTTOM", 0, -16);
	addButton:SetText(L["Add a Blueprint by Code"]);
	addButton:SetScript("OnClick", function()
		HSC:ShowImportPanel();
	end);
	empty.AddButton = addButton;

	local browseButton = CreateFrame("Button", nil, empty, "UIPanelButtonTemplate");
	browseButton:SetSize(220, 26);
	browseButton:SetPoint("TOP", addButton, "BOTTOM", 0, -8);
	browseButton:SetText(L["Browse Decor"]);
	browseButton:SetScript("OnClick", function()
		HSC:ShowBrowser();
	end);
	empty.BrowseButton = browseButton;

	function empty:SetMessage(titleText, bodyText, showAddButton)
		title:SetText(titleText);
		body:SetText(bodyText);
		addButton:SetShown(showAddButton == true);
		browseButton:SetShown(showAddButton == true);
	end
	empty:Hide();
	return empty;
end

function Window:Create()
	local db = HSC.db.window;

	frame = CreateFrame("Frame", FRAME_NAME, GetAppropriateTopLevelParent());
	frame:Hide();
	frame:SetSize(db.width or DEFAULT_WIDTH, db.height or DEFAULT_HEIGHT);
	frame:SetFrameStrata("HIGH");
	frame:SetToplevel(true);
	frame:SetClampedToScreen(true);
	frame:SetClampRectInsets(-10, 10, 10, -10);
	frame:SetMovable(true);
	frame:SetResizable(true);
	frame:SetResizeBounds(MIN_WIDTH, MIN_HEIGHT, MAX_WIDTH, MAX_HEIGHT);
	frame:EnableMouse(true);
	SetClosedByEscape(not Window:IsLocked());
	FrameUtil.RegisterForTopLevelParentChanged(frame);

	CreatePanelArt(frame, L["Shopping Cart"], "Perks-ShoppingCart");
	frame.LockButton = CreateLockButton(frame);
	UpdateLockButton();
	frame.BrowseButton = CreateBrowseButton(frame);
	frame.DragArea:SetScript("OnDragStart", function()
		frame:StartMoving();
	end);
	frame.DragArea:SetScript("OnDragStop", function()
		frame:StopMovingOrSizing();
		Window:SavePosition();
	end);
	frame.CloseButton:SetScript("OnClick", function()
		Window:Hide();
	end);

	local blueprintDropdown = CreateFrame("DropdownButton", nil, frame, "WowStyle1DropdownTemplate");
	blueprintDropdown:SetWidth(140);
	blueprintDropdown:SetPoint("TOPRIGHT", -20, -44);
	blueprintDropdown:SetDefaultText(L["Blueprints"]);

	local bigCount = frame:CreateFontString(nil, "ARTWORK", "GameFontNormalHuge");
	bigCount:SetPoint("TOPLEFT", 20, -42);
	bigCount:SetTextColor(Colors.Title:GetRGB());
	frame.BigCount = bigCount;

	local bigLabel = frame:CreateFontString(nil, "ARTWORK", "GameFontHighlight");
	bigLabel:SetPoint("BOTTOMLEFT", bigCount, "BOTTOMRIGHT", 7, 2);
	bigLabel:SetPoint("RIGHT", blueprintDropdown, "LEFT", -10, 0);
	bigLabel:SetJustifyH("LEFT");
	bigLabel:SetWordWrap(false);
	bigLabel:SetTextColor(Colors.Muted:GetRGB());
	frame.BigLabel = bigLabel;
	blueprintDropdown:SetupMenu(function(_, rootDescription)
		rootDescription:SetTag("MENU_HOUSINGSHOPPINGCART_BLUEPRINTS");
		local blueprints = Cart:GetBlueprints();
		local function IsSelected(shareCode)
			return Window.blueprintFilter == shareCode;
		end
		local function SetSelected(shareCode)
			Window.blueprintFilter = shareCode;
			Window:Refresh();
		end
		rootDescription:CreateButton(L["Add a blueprint by share code..."], function()
			HSC:ShowImportPanel();
		end);
		rootDescription:CreateButton(L["Browse decor..."], function()
			HSC:ShowBrowser();
		end);
		local byHand = Cart:HasBlueprint(Cart.BY_HAND);
		if #blueprints > 0 or byHand then
			rootDescription:CreateDivider();
			rootDescription:CreateRadio(L["All blueprints (%d)"]:format(#blueprints), function()
				return Window.blueprintFilter == nil;
			end, function()
				SetSelected(nil);
			end);
			if byHand then
				rootDescription:CreateRadio(Cart:GetBlueprintName(Cart.BY_HAND), IsSelected, SetSelected, Cart.BY_HAND);
			end
			local groups = HSC.Recent.GroupByType(blueprints);
			for _, group in ipairs(groups) do
				if #groups > 1 then
					rootDescription:CreateTitle(group.label);
				end
				for _, blueprint in ipairs(group.entries) do
					rootDescription:CreateRadio(blueprint.name, IsSelected, SetSelected, blueprint.shareCode);
				end
			end
			rootDescription:CreateDivider();
			local manage = rootDescription:CreateButton(L["Manage blueprints"]);
			if byHand then
				AddBlueprintActions(manage:CreateButton(Cart:GetBlueprintName(Cart.BY_HAND)), Cart.BY_HAND);
			end
			for _, blueprint in ipairs(blueprints) do
				AddBlueprintActions(manage:CreateButton(blueprint.name), blueprint.shareCode);
			end
		end
	end);
	frame.BlueprintDropdown = blueprintDropdown;

	local bar = CreateProgressBar(frame);
	bar:SetPoint("TOPLEFT", 20, -80);
	bar:SetPoint("TOPRIGHT", -20, -80);
	frame.ProgressBar = bar;

	local TOOLBAR_Y = -118;
	local settingsDropdown = CreateFrame("DropdownButton", nil, frame, "UIPanelIconDropdownButtonTemplate");
	settingsDropdown:SetPoint("RIGHT", frame, "TOPRIGHT", -24, TOOLBAR_Y);
	settingsDropdown:SetupMenu(function(_, rootDescription)
		rootDescription:SetTag("MENU_HOUSINGSHOPPINGCART_SETTINGS");
		local function Option(text, key)
			rootDescription:CreateCheckbox(text, function()
				return HSC.settings[key];
			end, function()
				HSC.settings[key] = not HSC.settings[key];
				Window:Refresh();
			end);
		end
		rootDescription:CreateTitle(L["Options"]);
		Option(L["Hide collected items"], "hideCollected");
		rootDescription:CreateCheckbox(L["Add blueprints as soon as you import them"], function()
			return HSC.settings.autoAdd;
		end, function()
			HSC:SetAutoAdd(not HSC.settings.autoAdd);
		end);
		Option(L["Open the cart when adding a blueprint"], "openOnAdd");
		Option(L["Print a summary in chat when adding a blueprint"], "addSummary");
		Option(L["Show a toast when you collect something"], "toasts");
		Option(L["Play sounds"], "sounds");
		Option(L["Show sources in the Blueprint List"], "blizzardTooltips");
		rootDescription:CreateCheckbox(L["Show vendors on the world map"], function()
			return HSC.settings.mapPins;
		end, function()
			HSC:SetMapPinsShown(not HSC.settings.mapPins);
		end);
		rootDescription:CreateCheckbox(L["Show your cart at vendors"], function()
			return HSC.settings.merchantPanel;
		end, function()
			HSC:SetMerchantPanelShown(not HSC.settings.merchantPanel);
		end);
		rootDescription:CreateCheckbox(L["Read the game's vendor data once per patch"], function()
			return HSC.settings.autoScan;
		end, function()
			HSC.settings.autoScan = not HSC.settings.autoScan;
			if HSC.settings.autoScan then
				HSC.Scan:Start(false);
			end
		end);
		rootDescription:CreateCheckbox(L["Show minimap button"], function()
			return HSC.settings.minimapButton;
		end, function()
			HSC:SetMinimapButtonShown(not HSC.settings.minimapButton);
		end);
		rootDescription:CreateDivider();
		local undoText = Cart:GetUndo();
		if undoText then
			rootDescription:CreateButton(L["Undo: %s"]:format(undoText), function()
				HSC:Undo();
			end);
		end
		rootDescription:CreateButton(L["Copy list as text"], function()
			Window:ShowCopyBox(L["Shopping Cart"], Window:BuildPlainText());
		end);
		rootDescription:CreateButton(L["Clear collected items"], function()
			Cart:ClearCollected();
		end);
		rootDescription:CreateButton(L["Empty the cart..."], function()
			HSC:ConfirmClearAll();
		end);
	end);
	frame.SettingsDropdown = settingsDropdown;

	local groupDropdown = CreateFrame("DropdownButton", nil, frame, "WowStyle1DropdownTemplate");
	groupDropdown:SetWidth(128);
	groupDropdown:SetPoint("RIGHT", settingsDropdown, "LEFT", -12, 0);
	groupDropdown:SetupMenu(function(_, rootDescription)
		rootDescription:SetTag("MENU_HOUSINGSHOPPINGCART_GROUPBY");
		rootDescription:CreateTitle(L["Group by"]);
		for _, option in ipairs(GROUPINGS) do
			rootDescription:CreateRadio(option.label, function()
				return HSC.settings.groupBy == option.key;
			end, function()
				HSC.settings.groupBy = option.key;
				Window:Refresh();
			end);
		end
	end);
	groupDropdown:SetSelectionText(function(selections)
		local selection = selections and selections[1];
		return selection and L["Group: %s"]:format(MenuUtil.GetElementText(selection)) or nil;
	end);
	frame.GroupDropdown = groupDropdown;

	local search = CreateFrame("EditBox", nil, frame, "SearchBoxTemplate");
	search:SetHeight(20);
	search:SetPoint("LEFT", frame, "TOPLEFT", 26, TOOLBAR_Y);
	search:SetPoint("RIGHT", groupDropdown, "LEFT", -14, 0);
	search:HookScript("OnTextChanged", function(editBox)
		Window.searchText = editBox:GetText();
		Window:Refresh();
	end);
	frame.SearchBox = search;

	local inset = CreateFrame("Frame", nil, frame);
	inset:SetPoint("TOPLEFT", 14, -136);
	inset:SetPoint("BOTTOMRIGHT", -14, 42);
	local insetBackground = inset:CreateTexture(nil, "BACKGROUND");
	insetBackground:SetAtlas("housing-basic-panel-innerblackbox");
	insetBackground:SetAllPoints();
	insetBackground:SetAlpha(0.6);
	frame.Inset = inset;

	local scrollBox = CreateFrame("Frame", nil, inset, "WowScrollBoxList");
	scrollBox:SetPoint("TOPLEFT", 6, -6);
	scrollBox:SetPoint("BOTTOMRIGHT", -22, 6);
	frame.ScrollBox = scrollBox;

	local scrollBar = CreateFrame("EventFrame", nil, inset, "MinimalScrollBar");
	scrollBar:SetPoint("TOPLEFT", scrollBox, "TOPRIGHT", 7, 0);
	scrollBar:SetPoint("BOTTOMLEFT", scrollBox, "BOTTOMRIGHT", 7, 0);
	frame.ScrollBar = scrollBar;

	local view = CreateScrollBoxListLinearView(2, 4, 0, 0, 2);
	view:SetElementFactory(function(factory, elementData)
		if elementData.isHeader then
			factory("HSC_CartHeaderTemplate", function(button, data)
				button:Init(data);
			end);
		else
			factory("HSC_CartRowTemplate", function(button, data)
				button:Init(data);
			end);
		end
	end);
	view:SetElementExtentCalculator(function(_, elementData)
		return elementData.isHeader and HEADER_HEIGHT or ROW_HEIGHT;
	end);
	ScrollUtil.InitScrollBoxListWithScrollBar(scrollBox, scrollBar, view);

	frame.Empty = CreateEmptyState(inset);

	local clearButton = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate");
	clearButton:SetSize(136, 22);
	clearButton:SetPoint("BOTTOMRIGHT", -26, 12);
	clearButton:SetText(L["Clear Collected"]);
	clearButton:SetScript("OnClick", function()
		Cart:ClearCollected();
		HSC:PlaySound("IG_MAINMENU_OPTION_CHECKBOX_OFF");
	end);
	frame.ClearButton = clearButton;

	local totals = frame:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall");
	totals:SetPoint("LEFT", frame, "BOTTOMLEFT", 20, 23);
	totals:SetPoint("RIGHT", clearButton, "LEFT", -10, 0);
	totals:SetJustifyH("LEFT");
	totals:SetWordWrap(false);
	frame.Totals = totals;

	local totalsHover = CreateFrame("Frame", nil, frame);
	totalsHover:SetAllPoints(totals);
	totalsHover:SetScript("OnEnter", function(self)
		GameTooltip:SetOwner(self, "ANCHOR_TOP");
		GameTooltip_SetTitle(GameTooltip, L["Still to buy"]);
		GameTooltip_AddNormalLine(GameTooltip, L["What buying everything you still need costs, using each item's cheapest gold price. Items sold only for a currency add that currency. Items from quests, achievements, drops and the like cost nothing here."]);
		GameTooltip:Show();
	end);
	totalsHover:SetScript("OnLeave", GameTooltip_Hide);
	frame.TotalsHover = totalsHover;

	local undoBar = CreateFrame("Frame", nil, frame);
	undoBar:SetHeight(22);
	undoBar:SetPoint("LEFT", frame, "BOTTOMLEFT", 16, 23);
	undoBar:SetPoint("RIGHT", clearButton, "LEFT", -8, 0);
	undoBar:Hide();
	local undoButton = CreateFrame("Button", nil, undoBar, "UIPanelButtonTemplate");
	undoButton:SetSize(64, 22);
	undoButton:SetPoint("RIGHT");
	undoButton:SetText(L["Undo"]);
	undoButton:SetScript("OnClick", function()
		HSC:Undo();
	end);
	undoButton:SetScript("OnEnter", function(self)
		GameTooltip:SetOwner(self, "ANCHOR_TOP");
		GameTooltip_SetTitle(GameTooltip, L["Undo"]);
		GameTooltip_AddHighlightLine(GameTooltip, Cart:GetUndo() or "");
		GameTooltip_AddNormalLine(GameTooltip, L["Until the cart changes some other way, the settings menu and /hsc undo can take it back too."]);
		GameTooltip:Show();
	end);
	undoButton:SetScript("OnLeave", GameTooltip_Hide);
	undoBar.Button = undoButton;
	local undoIcon = undoBar:CreateTexture(nil, "ARTWORK");
	undoIcon:SetAtlas("common-icon-undo");
	undoIcon:SetSize(14, 14);
	undoIcon:SetPoint("LEFT", 4, 0);
	local undoText = undoBar:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall");
	undoText:SetPoint("LEFT", undoIcon, "RIGHT", 5, 0);
	undoText:SetPoint("RIGHT", undoButton, "LEFT", -6, 0);
	undoText:SetJustifyH("LEFT");
	undoText:SetWordWrap(false);
	undoText:SetTextColor(Colors.Muted:GetRGB());
	undoBar.Text = undoText;
	frame.UndoBar = undoBar;

	local grip = CreateFrame("Button", nil, frame);
	grip:SetSize(16, 16);
	grip:SetPoint("BOTTOMRIGHT", -4, 4);
	grip:SetNormalTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Up");
	grip:SetHighlightTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Highlight");
	grip:SetPushedTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Down");
	grip:SetScript("OnMouseDown", function()
		frame:StartSizing("BOTTOMRIGHT");
	end);
	grip:SetScript("OnMouseUp", function()
		frame:StopMovingOrSizing();
		Window:SavePosition();
	end);

	frame:SetScript("OnShow", function()
		Window:Refresh();
	end);
end

function Window:SavePosition()
	local db = HSC.db.window;
	local left, top = frame:GetLeft(), frame:GetTop();
	if left and top then
		db.left, db.top = left, top;
		frame:ClearAllPoints();
		frame:SetPoint("TOPLEFT", frame:GetParent(), "BOTTOMLEFT", left, top);
	end
	db.width, db.height = frame:GetSize();
end

function Window:RestorePosition()
	local db = HSC.db.window;
	frame:ClearAllPoints();
	if db.left and db.top then
		frame:SetPoint("TOPLEFT", frame:GetParent(), "BOTTOMLEFT", db.left, db.top);
	else
		frame:SetPoint("CENTER", frame:GetParent(), "CENTER", 0, 20);
	end
end

function Window:PlaceBeside(anchorFrame)
	if HSC.db.window.left or not (anchorFrame and anchorFrame:IsVisible()) then
		return false;
	end
	local left, right, top = anchorFrame:GetLeft(), anchorFrame:GetRight(), anchorFrame:GetTop();
	local parent = frame:GetParent();
	local parentWidth = parent:GetWidth();
	if not (left and right and top and parentWidth) then
		return false;
	end
	local ratio = anchorFrame:GetEffectiveScale() / frame:GetEffectiveScale();
	left, right, top = left * ratio, right * ratio, top * ratio;
	local gap = 28;
	local width = frame:GetWidth();
	local x = (right + gap + width <= parentWidth) and (right + gap) or (left - gap - width);
	frame:ClearAllPoints();
	frame:SetPoint("TOPLEFT", parent, "BOTTOMLEFT", math.max(x, 0), top);
	return true;
end

function HSC:ResetWindowPosition()
	local db = HSC.db.window;
	db.left, db.top = nil, nil;
	db.width, db.height = nil, nil;
	if frame then
		frame:SetSize(DEFAULT_WIDTH, DEFAULT_HEIGHT);
		Window:RestorePosition();
	end
end

function Window:IsShown()
	return frame ~= nil and frame:IsShown();
end

function Window:Show(anchorFrame, quiet)
	if not HSC.db then
		return;
	end
	HSC.db.window.open = true;
	if not frame then
		self:Create();
	end
	if frame:GetParent() ~= GetAppropriateTopLevelParent() then
		FrameUtil.UpdateTopLevelParent(frame);
	end
	if not frame:IsShown() then
		Data.ResetCaches();
		if not self:PlaceBeside(anchorFrame) then
			self:RestorePosition();
		end
		if not quiet then
			HSC:PlaySound("HOUSING_BLUEPRINTS_IMPORT_OPEN");
		end
		frame:Show();
	else
		frame:Raise();
		self:Refresh();
	end
end

function Window:Hide()
	if HSC.db then
		HSC.db.window.open = false;
	end
	if frame and frame:IsShown() then
		HSC:PlaySound("HOUSING_BLUEPRINTS_CONTENTLIST_CLOSE");
		frame:Hide();
	end
end

function HSC:ToggleWindow()
	if Window:IsShown() then
		Window:Hide();
	else
		Window:Show();
	end
end

function HSC:ShowWindow(anchorFrame)
	Window:Show(anchorFrame);
end

local function FormatTotals()
	local totals = Data.NewTotals();
	for _, line in pairs(Cart:GetLines()) do
		local _, _, left, collected = Cart:GetProgress(line);
		if not collected and left > 0 then
			Data.AddToTotals(totals, Data.GetBestCost(line), left);
		end
	end
	local text = Data.FormatTotals(totals, false, "   ");
	if text == "" then
		return "";
	end
	return Colors.Muted:WrapTextInColorCode(L["Still to buy:"]) .. " " .. text;
end

local UNDO_BAR_SECONDS = 10;

local function UpdateUndoBar()
	local text, at = Cart:GetUndo();
	local show = text ~= nil and GetTime() - at < UNDO_BAR_SECONDS;
	frame.UndoBar.Text:SetText(text or "");
	frame.UndoBar:SetShown(show);
	frame.Totals:SetShown(not show);
	frame.TotalsHover:SetShown(not show);
end

function HSC:Undo()
	local ok, text = Cart:Undo();
	if not ok then
		HSC:Print(L["Nothing to undo."]);
		return false;
	end
	HSC:PlaySound("LOOT_WINDOW_COIN_SOUND");
	if not Window:IsShown() then
		HSC:Print(L["Undone: %s"]:format(text));
	end
	return true;
end

HSC:On("UNDO_CHANGED", function()
	local text = Cart:GetUndo();
	if not text then
		return;
	end
	HSC:Debounce("undoBar", UNDO_BAR_SECONDS + 0.1, function()
		if Window:IsShown() then
			UpdateUndoBar();
		end
	end);
	if not Window:IsShown() then
		HSC:Print(text .. " " .. L["Type |cffffd200/hsc undo|r to take it back."]);
	end
end);

function Window:Refresh()
	if not (frame and frame:IsShown()) then
		return;
	end

	if self.blueprintFilter and not Cart:HasBlueprint(self.blueprintFilter) then
		self.blueprintFilter = nil;
	end

	local provider, visible, total = self:BuildDataProvider();
	frame.ScrollBox:SetDataProvider(provider, ScrollBoxConstants.RetainScrollPosition);

	local stats = Cart:GetStats();
	frame.BigCount:SetText(stats.left);
	if stats.lines > 0 and stats.left == 0 then
		frame.BigCount:SetTextColor(Colors.Green:GetRGB());
		frame.BigLabel:SetText(L["- everything collected!"]);
	else
		frame.BigCount:SetTextColor(Colors.Title:GetRGB());
		frame.BigLabel:SetText(stats.left == 1 and L["item left to collect"] or L["items left to collect"]);
	end
	frame.ProgressBar:SetProgress(stats.got, stats.need);

	if total == 0 then
		local showAddButton = true;
		frame.Empty:SetMessage(L["Your cart is empty"],
			L["Open a blueprint's |cffffd200View List|r and press |cffffd200Add to Shopping Cart|r - or add one by its share code, from anywhere, or pick decor in the browser. Everything you're missing lands here."],
			showAddButton);
		frame.Empty:Show();
	elseif visible == 0 then
		frame.Empty:SetMessage(L["Nothing to show"], L["No items match your search or filters."]);
		frame.Empty:Show();
	else
		frame.Empty:Hide();
	end

	frame.ClearButton:SetEnabled(stats.collectedLines > 0);
	frame.Totals:SetText(FormatTotals());
	UpdateUndoBar();

	if self.blueprintFilter then
		frame.BlueprintDropdown:OverrideText(Cart:GetBlueprintName(self.blueprintFilter));
	elseif stats.blueprints == 0 then
		frame.BlueprintDropdown:OverrideText(L["Blueprints"]);
	else
		frame.BlueprintDropdown:OverrideText(stats.blueprints == 1 and L["1 Blueprint"] or L["%d Blueprints"]:format(stats.blueprints));
	end
end

HSC:On("CART_CHANGED", function()
	Window:Refresh();
end);
HSC:On("LOGIN", function()
	if Window:IsLocked() and HSC.db.window.open then
		local quiet = true;
		Window:Show(nil, quiet);
	end
end);
HSC:On("CART_REFRESH", function()
	Window:Refresh();
end);
