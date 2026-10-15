local _, HSC = ...
local L = HSC.L;
local Data = HSC.Data;
local Cart = HSC.Cart;
local CT = Data.CT;
local Colors = HSC.Colors;

local AtlasIcon = HSC.AtlasIcon;

HSC_CartRowMixin = {};

function HSC_CartRowMixin:OnLoad()
	self:RegisterForClicks("LeftButtonUp", "RightButtonUp");
end

local function BuildSubText(line, sources, collected)
	if collected then
		return Colors.Green:WrapTextInColorCode(line.manual and L["Ticked off"] or L["Collected"]);
	end
	local primary = sources[1];
	if not primary then
		if line.tooltip and line.tooltip ~= "" then
			return Colors.Muted:WrapTextInColorCode(line.tooltip);
		end
		if Data.IsCountable(line.contentType) then
			return Colors.Faint:WrapTextInColorCode(L["Source unknown"]);
		end
		return Colors.Faint:WrapTextInColorCode(L["Unlock required"]);
	end

	if line.contentType == CT.Dye then
		local names = {};
		for _, source in ipairs(sources) do
			names[#names + 1] = source.name;
		end
		return AtlasIcon(Data.GetKindInfo(primary.kind).atlas, 12) .. " " .. Colors.Muted:WrapTextInColorCode(table.concat(names, "  ·  "));
	end

	local kind = Data.GetKindInfo(primary.kind);
	local text = primary.name or kind.label;
	if primary.kind == "market" then
		text = kind.label;
	end
	local where = (primary.kind == "endeavor" and primary.vendor ~= primary.name and primary.vendor) or primary.zone;
	if where then
		text = text .. "  ·  " .. where;
	end
	if #sources > 1 then
		text = text .. "  " .. Colors.Faint:WrapTextInColorCode(L["+%d more"]:format(#sources - 1));
	end
	return AtlasIcon(kind.atlas, 12) .. " " .. Colors.Muted:WrapTextInColorCode(text);
end

HSC.Rows = { SourceSummary = BuildSubText };

function HSC_CartRowMixin:Init(elementData)
	local line = elementData.line;
	self.elementData = elementData;
	self.line = line;

	local display = Data.GetDisplay(line.contentType, line.recordID, line.name);
	local sources = Data.GetSources(line);
	local got, need, left, collected = Cart:GetProgress(line);

	self.Stripe:SetShown(elementData.odd == true);

	local primary = sources[1];
	local accent = primary and Data.GetKindInfo(primary.kind).color or Colors.Faint;
	self.Accent:SetColorTexture(accent:GetRGB());
	self.Accent:SetAlpha(collected and 0.2 or 0.85);

	Data.SetIcon(self.Icon, display);
	self.Icon:SetDesaturated(collected);
	self.Icon:SetAlpha(collected and 0.5 or 1);
	self.Check:SetShown(collected);
	self.TrackIcon:SetShown(not collected and Data.IsTracking(line));

	self.Name:SetText(display.name);
	if collected then
		self.Name:SetTextColor(Colors.Faint:GetRGB());
	else
		self.Name:SetTextColor(Data.GetQualityColor(display.quality):GetRGB());
	end

	self.Sub:SetText(BuildSubText(line, sources, collected));

	if collected then
		self.Count:SetText(need > 1 and Colors.Green:WrapTextInColorCode(("%d/%d"):format(need, need)) or "");
	elseif got > 0 then
		self.Count:SetText(("%s|cff9c958a/%d|r"):format(Colors.Title:WrapTextInColorCode(tostring(got)), need));
	else
		self.Count:SetText(Colors.Title:WrapTextInColorCode("×" .. need));
	end

	local cost = (not collected) and Data.GetBestCost(line) or nil;
	if cost then
		local text = Data.FormatCost(cost, left);
		local canAfford = Data.CanAfford(cost, left);
		self.Cost:SetText(canAfford == false and Colors.Red:WrapTextInColorCode(text) or text);
	elseif not collected and primary and primary.kind == "market" and primary.marketPrice then
		self.Cost:SetText(Data.FormatHearthsteel(primary.marketPrice * left));
	else
		self.Cost:SetText("");
	end
end

function HSC_CartRowMixin:UpdateCursor()
	if IsModifiedClick("DRESSUP") and self.line and Data.CanPreview(self.line) then
		ShowInspectCursor();
	else
		ResetCursor();
	end
end

function HSC_CartRowMixin:OnEnter()
	if not self.line then
		return;
	end
	HSC.Tooltip.ShowLine(self, self.line, "ANCHOR_RIGHT");
	self:SetScript("OnUpdate", self.UpdateCursor);
	self:UpdateCursor();
end

function HSC_CartRowMixin:OnLeave()
	self:SetScript("OnUpdate", nil);
	if GameTooltip:GetOwner() == self then
		GameTooltip:Hide();
	end
	ResetCursor();
end

function HSC_CartRowMixin:OnClick(button)
	local line = self.line;
	if not line then
		return;
	end
	if button == "RightButton" then
		self:OpenMenu();
		return;
	end
	if IsModifiedClick("CHATLINK") and ChatFrameUtil and ChatFrameUtil.GetActiveWindow and ChatFrameUtil.GetActiveWindow() then
		local link = Data.GetChatLink(line);
		if link then
			ChatFrameUtil.InsertLink(link);
		end
	elseif IsModifiedClick("DRESSUP") then
		Data.Preview(line);
	elseif IsShiftKeyDown() then
		Data.ToggleTracking(line);
		C_Timer.After(0.1, function()
			if self.line == line and self:IsMouseOver() then
				self:OnEnter();
			end
			HSC:Fire("CART_REFRESH");
		end);
	end
end

local function LinkToChat(line)
	local link = Data.GetChatLink(line);
	if not link or not ChatFrameUtil then
		return;
	end
	if not ChatFrameUtil.InsertLink(link) then
		ChatFrameUtil.OpenChat(link);
	end
end

local function HasVendorSource(line)
	for _, source in ipairs(Data.GetSources(line)) do
		if source.kind == "vendor" or source.kind == "endeavor" then
			return true;
		end
	end
	return false;
end

function HSC.AddItemActions(rootDescription, line)
	local spots = HSC.Map.GetVendorSpots(line);
	if #spots == 1 then
		rootDescription:CreateButton(L["Show Vendor"], function()
			HSC.Map.ShowVendor(spots[1]);
		end);
	elseif #spots > 1 then
		local vendorMenu = rootDescription:CreateButton(L["Show Vendor"]);
		for _, spot in ipairs(spots) do
			vendorMenu:CreateButton(("%s - %s"):format(spot.name, spot.mapName), function()
				HSC.Map.ShowVendor(spot);
			end);
		end
	elseif HasVendorSource(line) and HSC.Map.CanTrackSource(line) then
		rootDescription:CreateButton(L["Show Vendor"], function()
			HSC.Map.ShowSourceByTracking(line);
		end);
	end

	if line.contentType == CT.Decor then
		local tracking = Data.IsTracking(line);
		local trackButton = rootDescription:CreateButton(tracking and (OBJECTIVES_STOP_TRACKING or L["Untrack"]) or (TRACK_ACHIEVEMENT or L["Track"]), function()
			Data.ToggleTracking(line);
			HSC:Fire("CART_REFRESH");
		end);
		trackButton:SetEnabled(tracking or Data.IsTrackable(line));
		if tracking then
			rootDescription:CreateButton(SHOW_MAP or L["Show Map"], function()
				Data.OpenMapToTracked(line);
			end);
		end
		rootDescription:CreateButton(PREVIEW or L["Preview"], function()
			Data.Preview(line);
		end);
		rootDescription:CreateButton(L["Show in Catalog"], function()
			Data.ShowInCatalog(line);
		end);
	end
	if Data.GetChatLink(line) then
		rootDescription:CreateButton(L["Link to Chat"], function()
			LinkToChat(line);
		end);
	end
end

function HSC_CartRowMixin:OpenMenu()
	local line = self.line;
	local key = Data.Key(line.contentType, line.recordID);
	local display = Data.GetDisplay(line.contentType, line.recordID, line.name);
	local collected = Cart:IsCollected(line);

	MenuUtil.CreateContextMenu(self, function(_, rootDescription)
		rootDescription:SetTag("MENU_HOUSINGSHOPPINGCART_ITEM");
		rootDescription:CreateTitle(display.name);
		HSC.AddItemActions(rootDescription, line);

		rootDescription:CreateDivider();
		if Data.IsCountable(line.contentType) then
			rootDescription:CreateButton(L["Want one more"], function()
				Cart:AddByHand(line.contentType, line.recordID, 1, line.name);
			end);
			if Cart:GetByHand(key) > 0 then
				rootDescription:CreateButton(L["One fewer (added by hand)"], function()
					Cart:RemoveOneByHand(key);
				end);
			end
		end
		if collected then
			rootDescription:CreateButton(L["Mark as not collected"], function()
				Cart:SetCollected(key, false);
			end);
		else
			rootDescription:CreateButton(L["Mark as collected"], function()
				Cart:SetCollected(key, true);
				HSC:PlaySound("IG_MAINMENU_OPTION_CHECKBOX_ON");
			end);
		end
		rootDescription:CreateButton(L["Remove from cart"], function()
			Cart:RemoveLine(key);
		end);
	end);
end

HSC_CartHeaderMixin = {};

function HSC_CartHeaderMixin:OnLoad()
	self:RegisterForClicks("LeftButtonUp", "RightButtonUp");
end

function HSC_CartHeaderMixin:Init(elementData)
	self.elementData = elementData;
	self.Name:SetText(elementData.label);
	if elementData.icon then
		self.Icon:SetTexture(elementData.icon);
	else
		self.Icon:SetAtlas(elementData.atlas or "house-chest-icon");
	end

	local countColor = (elementData.got >= elementData.need) and Colors.Green or Colors.Muted;
	self.Count:SetText(countColor:WrapTextInColorCode(("%d/%d"):format(elementData.got, elementData.need)));

	local atlas = elementData.collapsed and "Options_ListExpand_Right" or "Options_ListExpand_Right_Expanded";
	self.Right:SetAtlas(atlas, true);
	self.HighlightRight:SetAtlas(atlas, true);
	self.Name:SetTextColor(NORMAL_FONT_COLOR:GetRGB());
end

function HSC_CartHeaderMixin:OnEnter()
	self.Name:SetTextColor(HIGHLIGHT_FONT_COLOR:GetRGB());
	if self.elementData and self.elementData.shareCode then
		GameTooltip:SetOwner(self, "ANCHOR_RIGHT");
		GameTooltip_SetTitle(GameTooltip, self.elementData.label);
		GameTooltip_AddInstructionLine(GameTooltip, self.elementData.shareCode == Cart.BY_HAND and L["<Right-click to remove>"]
			or L["<Right-click to rename or remove>"]);
		GameTooltip:Show();
	end
end

function HSC_CartHeaderMixin:OnLeave()
	self.Name:SetTextColor(NORMAL_FONT_COLOR:GetRGB());
	if GameTooltip:GetOwner() == self then
		GameTooltip:Hide();
	end
end

function HSC_CartHeaderMixin:OnClick(button)
	local elementData = self.elementData;
	if not elementData then
		return;
	end
	if button == "RightButton" then
		if elementData.shareCode then
			HSC:OpenBlueprintMenu(self, elementData.shareCode);
		end
		return;
	end
	HSC:ToggleGroupCollapsed(elementData.key);
end

HSC_BrowserHeaderMixin = {};

function HSC_BrowserHeaderMixin:Init(elementData)
	self.elementData = elementData;
	self.Label:SetText(elementData.label);
	self.Count:SetText(Colors.Muted:WrapTextInColorCode(L["%d decor"]:format(elementData.count)));
end

HSC_BrowserRowMixin = {};

local function AddFromRow(row, count)
	local line = row.line;
	if not line then
		return;
	end
	Cart:AddByHand(line.contentType, line.recordID, count, line.name);
	HSC:PlaySound("LOOT_WINDOW_COIN_SOUND");
	local name = "|cffffd200" .. (line.name or "?") .. "|r";
	if count == 1 then
		HSC:Print(L["Added %s to your Shopping Cart."]:format(name));
	else
		HSC:Print(L["Added %s x%d to your Shopping Cart."]:format(name, count));
	end
end

local function ShowAddTooltip(button)
	local row = button:GetParent();
	GameTooltip:SetOwner(button, "ANCHOR_RIGHT");
	GameTooltip_SetTitle(GameTooltip, L["Add to Shopping Cart"]);
	if row.line and Cart:GetLine(Data.Key(row.line.contentType, row.line.recordID)) then
		GameTooltip_AddNormalLine(GameTooltip, L["Already in your cart - this adds one more."]);
	else
		GameTooltip_AddNormalLine(GameTooltip, L["Adds one to your Shopping Cart, on top of what you own."]);
	end
	GameTooltip_AddInstructionLine(GameTooltip, L["<Shift-click to add 5>"]);
	GameTooltip:Show();
end

function HSC_BrowserRowMixin:OnLoad()
	self:RegisterForClicks("LeftButtonUp", "RightButtonUp");
	local add = CreateFrame("Button", nil, self);
	add:SetSize(28, 28);
	add:SetPoint("RIGHT", -8, 0);
	add.Icon = add:CreateTexture(nil, "ARTWORK");
	add.Icon:SetAtlas("Perks-ShoppingCart");
	add.Icon:SetAllPoints();
	local highlight = add:CreateTexture(nil, "HIGHLIGHT");
	highlight:SetAtlas("Perks-ShoppingCart");
	highlight:SetAllPoints();
	highlight:SetBlendMode("ADD");
	highlight:SetAlpha(0.45);
	add.Plus = add:CreateFontString(nil, "OVERLAY", "NumberFontNormal");
	add.Plus:SetPoint("BOTTOMRIGHT", 3, -2);
	add.Plus:SetText("+");
	add:SetScript("OnClick", function()
		AddFromRow(self, IsShiftKeyDown() and 5 or 1);
	end);
	add:SetScript("OnEnter", ShowAddTooltip);
	add:SetScript("OnLeave", GameTooltip_Hide);
	self.Add = add;
end

function HSC_BrowserRowMixin:Init(elementData)
	local line = elementData.line;
	self.elementData = elementData;
	self.line = line;

	local display = Data.GetDisplay(line.contentType, line.recordID, line.name);
	local sources = Data.GetSources(line);
	local owned = Data.GetOwned(line.contentType, line.recordID) or 0;

	self.Stripe:SetShown(elementData.odd == true);
	Data.SetIcon(self.Icon, display);
	self.Name:SetText(display.name);
	self.Name:SetTextColor(Data.GetQualityColor(display.quality):GetRGB());

	self.Sub:SetText(HSC.Rows.SourceSummary(line, sources, false));

	self.Count:SetText(owned > 0 and Colors.Green:WrapTextInColorCode(L["Owned: %d"]:format(owned)) or Colors.Faint:WrapTextInColorCode(L["Not owned"]));

	local cartLine = Cart:GetLine(Data.Key(line.contentType, line.recordID));
	self.CartBadge:SetShown(cartLine ~= nil and not Cart:IsCollected(cartLine));

	local cost = Data.GetBestCost(line);
	local primary = sources[1];
	if cost then
		self.Cost:SetText(Data.FormatCost(cost, 1));
	elseif primary and primary.kind == "market" and primary.marketPrice then
		self.Cost:SetText(Data.FormatHearthsteel(primary.marketPrice));
	else
		self.Cost:SetText("");
	end
end

HSC_BrowserRowMixin.UpdateCursor = HSC_CartRowMixin.UpdateCursor;

function HSC_BrowserRowMixin:OnEnter()
	if not self.line then
		return;
	end
	HSC.Tooltip.ShowDecor(self, self.line, "ANCHOR_RIGHT");
	self:SetScript("OnUpdate", self.UpdateCursor);
	self:UpdateCursor();
end

HSC_BrowserRowMixin.OnLeave = HSC_CartRowMixin.OnLeave;

function HSC_BrowserRowMixin:OnClick(button)
	local line = self.line;
	if not line then
		return;
	end
	if button == "RightButton" then
		MenuUtil.CreateContextMenu(self, function(_, rootDescription)
			rootDescription:SetTag("MENU_HOUSINGSHOPPINGCART_BROWSER_ITEM");
			rootDescription:CreateTitle(line.name or "");
			rootDescription:CreateButton(L["Add to Shopping Cart"], function()
				AddFromRow(self, 1);
			end);
			rootDescription:CreateButton(L["Add 5 to Shopping Cart"], function()
				AddFromRow(self, 5);
			end);
			rootDescription:CreateDivider();
			HSC.AddItemActions(rootDescription, line);
		end);
		return;
	end
	HSC_CartRowMixin.OnClick(self, button);
end
