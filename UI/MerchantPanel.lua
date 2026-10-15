local _, HSC = ...
local L = HSC.L;
local Data = HSC.Data;
local Merchant = HSC.Merchant;
local Colors = HSC.Colors;

local MerchantPanel = {};
HSC.MerchantPanel = MerchantPanel;

local PANEL_WIDTH = 300;
local ROW_HEIGHT = 40;
local LIST_TOP, LIST_BOTTOM = -66, 70;
local DEFAULT_MERCHANT_HEIGHT = 444;

local panel;
local rows = {};
local offers = {};
local offset = 0;
local dismissed = false;
local badges = {};

local function IsEnabled()
	return HSC.settings and HSC.settings.merchantPanel;
end

local function FormatEach(costs)
	local parts = {};
	for _, cost in ipairs(costs or {}) do
		local text = Data.FormatCost(cost, 1);
		if text then
			parts[#parts + 1] = (Data.CanAfford(cost, 1) == false) and Colors.Red:WrapTextInColorCode(text) or text;
		end
	end
	if #parts == 0 then
		return nil;
	end
	return L["%s each"]:format(table.concat(parts, " + "));
end

local function UpdateRow(row, offer)
	row.offer = offer;
	if not offer then
		row:Hide();
		return;
	end
	local display = Data.GetDisplay(offer.line.contentType, offer.line.recordID, offer.line.name);
	Data.SetIcon(row.Icon, offer.texture and { icon = offer.texture } or display);
	row.Name:SetText(offer.name);
	row.Name:SetTextColor(Data.GetQualityColor(display.quality):GetRGB());
	row.Count:SetText(Colors.Title:WrapTextInColorCode("×" .. offer.need));

	if offer.problem then
		row.Sub:SetText(Colors.Red:WrapTextInColorCode(offer.problem));
	else
		row.Sub:SetText(Colors.Muted:WrapTextInColorCode(FormatEach(offer.costs) or L["Free"]));
	end

	local canBuy = not offer.problem and offer.toBuy > 0 and not Merchant:IsBuying();
	row.Buy:SetEnabled(canBuy);
	row:Show();
end

local function CreateRow(parent, index)
	local row = CreateFrame("Button", nil, parent);
	row:SetHeight(ROW_HEIGHT);
	row:SetPoint("TOPLEFT", 4, -4 - (index - 1) * ROW_HEIGHT);
	row:SetPoint("TOPRIGHT", -4, -4 - (index - 1) * ROW_HEIGHT);

	local highlight = row:CreateTexture(nil, "HIGHLIGHT");
	highlight:SetAtlas("common-dropdown-customize-mouseover");
	highlight:SetAlpha(0.18);
	highlight:SetBlendMode("ADD");
	highlight:SetAllPoints();

	local icon = row:CreateTexture(nil, "ARTWORK");
	icon:SetSize(30, 30);
	icon:SetPoint("LEFT", 6, 0);
	row.Icon = icon;

	local iconBorder = row:CreateTexture(nil, "OVERLAY");
	iconBorder:SetAtlas("housing-item-wood-frame_64");
	iconBorder:SetAllPoints(icon);

	local buy = CreateFrame("Button", nil, row, "UIPanelButtonTemplate");
	buy:SetSize(52, 22);
	buy:SetPoint("RIGHT", -4, 0);
	buy:SetText(L["Buy"]);
	buy:SetScript("OnClick", function()
		if row.offer then
			Merchant:ConfirmBuy({ row.offer });
		end
	end);
	row.Buy = buy;

	local count = row:CreateFontString(nil, "ARTWORK", "GameFontHighlight");
	count:SetPoint("RIGHT", buy, "LEFT", -8, 0);
	row.Count = count;

	local name = row:CreateFontString(nil, "ARTWORK", "GameFontNormal");
	name:SetPoint("TOPLEFT", icon, "TOPRIGHT", 8, -1);
	name:SetPoint("RIGHT", count, "LEFT", -6, 0);
	name:SetJustifyH("LEFT");
	name:SetWordWrap(false);
	row.Name = name;

	local sub = row:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall");
	sub:SetPoint("BOTTOMLEFT", icon, "BOTTOMRIGHT", 8, 1);
	sub:SetPoint("RIGHT", count, "LEFT", -6, 0);
	sub:SetJustifyH("LEFT");
	sub:SetWordWrap(false);
	row.Sub = sub;

	row:SetScript("OnEnter", function(self)
		if self.offer then
			HSC.Tooltip.ShowLine(self, self.offer.line, "ANCHOR_RIGHT");
		end
	end);
	row:SetScript("OnLeave", GameTooltip_Hide);
	return row;
end

local function VisibleRowCount()
	local height = MerchantFrame:GetHeight();
	if not height or height <= 0 then
		height = DEFAULT_MERCHANT_HEIGHT;
	end
	return math.max(math.floor((height + LIST_TOP - LIST_BOTTOM - 8) / ROW_HEIGHT), 3);
end

local function Create()
	panel = CreateFrame("Frame", "HousingShoppingCartMerchantPanel", MerchantFrame);
	panel:SetWidth(PANEL_WIDTH);
	panel:SetPoint("TOPLEFT", MerchantFrame, "TOPRIGHT", 16, -4);
	panel:SetPoint("BOTTOMLEFT", MerchantFrame, "BOTTOMRIGHT", 16, 4);
	panel:EnableMouse(true);
	panel:EnableMouseWheel(true);
	HSC.Window.CreatePanelArt(panel, L["Shopping Cart"], "Perks-ShoppingCart");
	panel.CloseButton:SetScript("OnClick", function()
		dismissed = true;
		panel:Hide();
	end);

	local summary = panel:CreateFontString(nil, "ARTWORK", "GameFontHighlight");
	summary:SetPoint("TOPLEFT", 16, -42);
	summary:SetPoint("TOPRIGHT", -16, -42);
	summary:SetJustifyH("LEFT");
	summary:SetWordWrap(false);
	summary:SetTextColor(Colors.Muted:GetRGB());
	panel.Summary = summary;

	local inset = CreateFrame("Frame", nil, panel);
	inset:SetPoint("TOPLEFT", 8, LIST_TOP);
	inset:SetPoint("BOTTOMRIGHT", -8, LIST_BOTTOM);
	local insetBackground = inset:CreateTexture(nil, "BACKGROUND");
	insetBackground:SetAtlas("housing-basic-panel-innerblackbox");
	insetBackground:SetAllPoints();
	insetBackground:SetAlpha(0.6);
	panel.Inset = inset;

	local more = inset:CreateFontString(nil, "ARTWORK", "GameFontDisableSmall");
	more:SetPoint("BOTTOM", 0, 4);
	panel.More = more;

	local buyAll = CreateFrame("Button", nil, panel, "UIPanelButtonTemplate");
	buyAll:SetHeight(26);
	buyAll:SetPoint("BOTTOMLEFT", 14, 14);
	buyAll:SetPoint("BOTTOMRIGHT", -14, 14);
	buyAll:SetScript("OnClick", function()
		if Merchant:IsBuying() then
			Merchant:Stop();
		else
			Merchant:ConfirmBuy(offers);
		end
	end);
	panel.BuyAll = buyAll;

	local totals = panel:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall");
	totals:SetPoint("BOTTOMLEFT", buyAll, "TOPLEFT", 4, 9);
	totals:SetPoint("BOTTOMRIGHT", buyAll, "TOPRIGHT", -4, 9);
	totals:SetJustifyH("LEFT");
	totals:SetWordWrap(false);
	panel.Totals = totals;

	panel:SetScript("OnMouseWheel", function(_, delta)
		local maxOffset = math.max(#offers - #rows, 0);
		offset = math.min(math.max(offset - delta, 0), maxOffset);
		MerchantPanel:Refresh();
	end);

	for index = 1, VisibleRowCount() do
		rows[index] = CreateRow(inset, index);
	end
	panel.Rows = rows;
end

local function ShouldShow()
	return IsEnabled() and not dismissed and Merchant:IsOpen() and MerchantFrame and MerchantFrame:IsShown();
end

function MerchantPanel:Refresh()
	if not ShouldShow() then
		if panel then
			panel:Hide();
		end
		return;
	end
	offers = Merchant:GetOffers();
	local buying = Merchant:IsBuying();
	if #offers == 0 and not buying then
		if panel then
			panel:Hide();
		end
		return offers;
	end
	if not panel then
		Create();
	end

	offset = math.min(offset, math.max(#offers - #rows, 0));
	for index, row in ipairs(rows) do
		UpdateRow(row, offers[offset + index]);
	end
	local hidden = #offers - #rows;
	panel.More:SetText(hidden > 0 and L["Scroll for %d more"]:format(hidden) or "");

	local need = 0;
	for _, offer in ipairs(offers) do
		need = need + offer.need;
	end
	panel.Summary:SetText(need == 1 and L["1 item from your cart is sold here"] or L["%d items from your cart are sold here"]:format(need));

	local toBuy = 0;
	for _, offer in ipairs(offers) do
		toBuy = toBuy + offer.toBuy;
	end
	if buying then
		local bought, total = Merchant:GetProgress();
		panel.Totals:SetText(Colors.Title:WrapTextInColorCode(L["Buying... %d of %d"]:format(bought, total)));
		panel.BuyAll:SetText(L["Stop"]);
		panel.BuyAll:Enable();
	else
		local totalsText = Merchant:FormatTotals(offers);
		panel.Totals:SetText(totalsText ~= "" and (Colors.Muted:WrapTextInColorCode(L["Total:"]) .. " " .. totalsText) or "");
		panel.BuyAll:SetText(L["Buy All (%d)"]:format(toBuy));
		panel.BuyAll:SetEnabled(toBuy > 0);
	end
	panel:Show();
	return offers;
end

local function UpdateBadges(knownOffers)
	if not (MerchantFrame and MERCHANT_ITEMS_PER_PAGE) then
		return;
	end
	local showBadges = IsEnabled() and Merchant:IsOpen() and MerchantFrame.selectedTab == 1;
	local wanted = {};
	if showBadges then
		for _, offer in ipairs(knownOffers or Merchant:GetOffers()) do
			wanted[offer.itemID] = true;
		end
	end
	local numItems = showBadges and GetMerchantNumItems() or 0;
	local page = MerchantFrame.page or 1;
	for i = 1, MERCHANT_ITEMS_PER_PAGE do
		local index = (page - 1) * MERCHANT_ITEMS_PER_PAGE + i;
		local isWanted = index <= numItems and wanted[GetMerchantItemID(index)] == true;
		local badge = badges[i];
		local itemButton = _G["MerchantItem" .. i .. "ItemButton"];
		if isWanted and not badge and itemButton then
			badge = itemButton:CreateTexture(nil, "OVERLAY", nil, 7);
			badge:SetAtlas("Perks-ShoppingCart");
			badge:SetSize(18, 18);
			badge:SetPoint("TOPRIGHT", 5, 5);
			badges[i] = badge;
		end
		if badge then
			badge:SetShown(isWanted);
		end
	end
end

local function RefreshAll()
	UpdateBadges(MerchantPanel:Refresh());
end

if MerchantFrame_Update then
	hooksecurefunc("MerchantFrame_Update", function()
		UpdateBadges();
	end);
end
if MerchantFrame then
	MerchantFrame:HookScript("OnShow", function()
		C_Timer.After(0, RefreshAll);
	end);
end

HSC:On("MERCHANT_CHANGED", function()
	if not Merchant:IsOpen() then
		dismissed = false;
		offset = 0;
	end
	RefreshAll();
end);
HSC:On("MERCHANT_RUN_UPDATE", RefreshAll);
HSC:On("CART_CHANGED", function()
	if Merchant:IsOpen() then
		RefreshAll();
	end
end);
HSC:On("CART_REFRESH", function()
	if Merchant:IsOpen() then
		RefreshAll();
	end
end);

function HSC:SetMerchantPanelShown(shown)
	self.settings.merchantPanel = shown and true or false;
	dismissed = false;
	RefreshAll();
end
