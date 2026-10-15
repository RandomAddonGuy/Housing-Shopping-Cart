local _, HSC = ...
local L = HSC.L;
local Data = HSC.Data;
local Cart = HSC.Cart;
local CT = Data.CT;
local Colors = HSC.Colors;

local Tooltip = {};
HSC.Tooltip = Tooltip;

local DETAIL_OFFSET = 21;

local AtlasIcon = HSC.AtlasIcon;

local function AddLine(tooltip, text, color, wrap, leftOffset)
	color = color or HIGHLIGHT_FONT_COLOR;
	tooltip:AddLine(text, color.r, color.g, color.b, wrap ~= false, leftOffset);
end

local function AddDetail(tooltip, text, color)
	AddLine(tooltip, text, color, true, DETAIL_OFFSET);
end

local function AddCost(tooltip, cost, need)
	local each = Data.FormatCost(cost, 1, true);
	if not each then
		return;
	end
	local canAfford = Data.CanAfford(cost, need);
	local color = (canAfford == false) and Colors.Red or HIGHLIGHT_FONT_COLOR;
	if need and need > 1 then
		AddDetail(tooltip, L["%s each, %s for %d"]:format(each, Data.FormatCost(cost, need), need), color);
	else
		AddDetail(tooltip, each, color);
	end
	if Data.CanAffordCurrency(cost, need) == false then
		local have = Data.GetCurrencyOwned(cost.currencyID) or 0;
		AddDetail(tooltip, L["You have %s"]:format(BreakUpLargeNumbers(have)), Colors.Muted);
	end
end

local function AddSource(tooltip, source, need, compact)
	local kind = Data.GetKindInfo(source.kind);
	local label = source.label;
	if label == nil then
		label = kind.label;
	end
	local icon = AtlasIcon(kind.atlas, 16);

	if source.kind == "market" then
		local price = Data.FormatHearthsteel(source.marketPrice or 0);
		AddLine(tooltip, ("%s %s  %s"):format(icon, kind.color:WrapTextInColorCode(kind.label), price));
		if source.inBundle and not compact and HOUSING_DECOR_BUNDLE_DISCLAIMER then
			AddDetail(tooltip, HOUSING_DECOR_BUNDLE_DISCLAIMER, Colors.Muted);
		end
		return;
	end

	local name = source.name or "";
	if label and label ~= "" and label ~= name then
		AddLine(tooltip, ("%s %s %s"):format(icon, kind.color:WrapTextInColorCode(label .. ":"), name));
	else
		AddLine(tooltip, ("%s %s"):format(icon, kind.color:WrapTextInColorCode(name)));
	end

	if source.kind == "endeavor" and source.vendor and source.vendor ~= name then
		AddDetail(tooltip, L["Sold by %s"]:format(source.vendor), Colors.Muted);
	end
	if source.zone then
		AddDetail(tooltip, table.concat(Data.GetZones(source), ", "), Colors.Muted);
	end
	if source.faction then
		local text = source.standing and ("%s - %s"):format(source.faction, source.standing) or source.faction;
		AddDetail(tooltip, text, Colors.Muted);
	end
	if source.cost then
		AddCost(tooltip, source.cost, need);
	elseif source.costText then
		AddDetail(tooltip, source.costText);
	end
	if source.kind == "endeavor" then
		if Data.IsEndeavorActive(source) then
			AddDetail(tooltip, L["Active in your neighborhood right now"], Colors.Green);
		else
			AddDetail(tooltip, L["Only available while this Endeavor is active"], Colors.Muted);
		end
	end
	if not compact then
		for _, detail in ipairs(source.details or {}) do
			AddDetail(tooltip, detail, Colors.Muted);
		end
	end
end

function Tooltip.AddHowToGet(tooltip, line, need, compact)
	local sources = Data.GetSources(line);
	local hasGameNote = line.tooltip and line.tooltip ~= "";
	if #sources == 0 and not hasGameNote and compact then
		return false;
	end

	GameTooltip_AddBlankLineToTooltip(tooltip);
	AddLine(tooltip, L["How to get it"], Colors.Title);

	local maxSources = compact and 3 or #sources;
	for index, source in ipairs(sources) do
		if index > maxSources then
			AddDetail(tooltip, L["...and %d more"]:format(#sources - maxSources), Colors.Muted);
			break;
		end
		AddSource(tooltip, source, need, compact);
	end

	if hasGameNote then
		AddLine(tooltip, line.tooltip, HIGHLIGHT_FONT_COLOR);
	elseif #sources == 0 then
		if Data.IsCountable(line.contentType) then
			AddLine(tooltip, L["The game doesn't list a source for this one yet."], Colors.Muted);
		else
			AddLine(tooltip, L["Unlocked through housing progress - the game doesn't list a source."], Colors.Muted);
		end
	end
	return true;
end

local function AddTitle(tooltip, line, display)
	local qualityColor = Data.GetQualityColor(display.quality);
	if display.placementCost and HOUSING_DECOR_PLACEMENT_COST_FORMAT then
		local costFormat = (line.contentType == CT.Room and HOUSING_ROOM_PLACEMENT_COST_FORMAT) or HOUSING_DECOR_PLACEMENT_COST_FORMAT;
		GameTooltip_AddColoredDoubleLine(tooltip, display.name, costFormat:format(display.placementCost), qualityColor, HIGHLIGHT_FONT_COLOR, false);
	else
		GameTooltip_SetTitle(tooltip, display.name, qualityColor, false);
	end

	local typeLabel = Data.GetTypeInfo(line.contentType).label;
	local category;
	if display.subcategoryIDs and display.subcategoryIDs[1] and C_HousingCatalog.GetCatalogCategoryAndSubcategoryNames then
		local ok, categoryName, subcategoryName = pcall(C_HousingCatalog.GetCatalogCategoryAndSubcategoryNames, display.subcategoryIDs[1]);
		if ok and subcategoryName and subcategoryName ~= "" then
			if categoryName and categoryName ~= "" and not subcategoryName:find(categoryName, 1, true) then
				category = ("%s - %s"):format(categoryName, subcategoryName);
			else
				category = subcategoryName;
			end
		end
	end
	AddLine(tooltip, category and ("%s  |cff9c958a%s|r"):format(typeLabel, category) or typeLabel, Colors.Muted);

	if display.isUniqueTrophy and HOUSING_DECOR_UNIQUE_TROPHY_TOOLTIP then
		AddLine(tooltip, HOUSING_DECOR_UNIQUE_TROPHY_TOOLTIP, LIGHTBLUE_FONT_COLOR or Colors.Title);
	end
end

function Tooltip.AddOwned(tooltip, line)
	local any = false;
	if line.contentType == CT.Decor then
		local info = Data.GetCatalogInfo(line.contentType, line.recordID);
		if info and HOUSING_DECOR_OWNED_COUNT_FORMAT then
			local stored = (info.totalNumStored or 0) + (info.remainingRedeemable or 0);
			local placed = info.totalNumPlaced or 0;
			if stored + placed > 0 then
				any = true;
				AddLine(tooltip, HOUSING_DECOR_OWNED_COUNT_FORMAT:format(stored + placed, placed, stored), NORMAL_FONT_COLOR, false);
			end
		end
		local inBags = info and Data.GetItemCount(info.itemID) or 0;
		if inBags > 0 then
			any = true;
			AddLine(tooltip, L["%d in your bags, not yet added to your storage"]:format(inBags), NORMAL_FONT_COLOR);
		end
	elseif line.contentType == CT.Dye then
		local owned = Data.GetDyeOwned(line.recordID);
		if owned then
			any = owned > 0;
			AddLine(tooltip, L["In your bags and bank: %d"]:format(owned), NORMAL_FONT_COLOR);
		end
	end
	return any;
end

local function AddProgress(tooltip, line)
	local got, need, left, collected = Cart:GetProgress(line);
	GameTooltip_AddBlankLineToTooltip(tooltip);
	if collected then
		local text = line.manual and L["Ticked off"] or L["Collected"];
		AddLine(tooltip, AtlasIcon("common-icon-checkmark", 14) .. " " .. text .. ((need > 0) and ("  (%d/%d)"):format(need, need) or ""), Colors.Green);
	elseif got > 0 then
		AddLine(tooltip, L["Collected %d of %d - %d to go"]:format(got, need, left), Colors.Text);
	else
		AddLine(tooltip, need == 1 and L["You need 1 more"] or L["You need %d more"]:format(need), Colors.Text);
	end

	Tooltip.AddOwned(tooltip, line);

	local names = {};
	for shareCode, count in pairs(line.from or {}) do
		names[#names + 1] = count > 0 and ("%s ×%d"):format(Cart:GetBlueprintName(shareCode), count) or Cart:GetBlueprintName(shareCode);
	end
	if #names > 0 then
		table.sort(names);
		AddLine(tooltip, AtlasIcon("common-icons-blueprints", 14) .. " " .. L["For: %s"]:format(table.concat(names, ", ")), Colors.Muted);
	end
end

local function AddInstructions(tooltip, line)
	GameTooltip_AddBlankLineToTooltip(tooltip);
	if line.contentType == CT.Decor then
		if Blizzard_HousingCatalogUtil and Blizzard_HousingCatalogUtil.AddDecorEntryTooltipTrackingText then
			Blizzard_HousingCatalogUtil.AddDecorEntryTooltipTrackingText(tooltip, line.recordID);
		end
		if HOUSING_DECOR_PREVIEW_TOOLTIP then
			GameTooltip_AddInstructionLine(tooltip, HOUSING_DECOR_PREVIEW_TOOLTIP);
		end
	end
	GameTooltip_AddInstructionLine(tooltip, L["<Right-click for options>"]);
end

function Tooltip.ShowLine(owner, line, anchor)
	local tooltip = GameTooltip;
	tooltip:SetOwner(owner, anchor or "ANCHOR_RIGHT");
	local display = Data.GetDisplay(line.contentType, line.recordID, line.name);
	local _, need, left = Cart:GetProgress(line);

	AddTitle(tooltip, line, display);
	AddProgress(tooltip, line);
	Tooltip.AddHowToGet(tooltip, line, math.max(left, 1), false);
	AddInstructions(tooltip, line);
	tooltip:Show();
end

function Tooltip.ShowDecor(owner, line, anchor)
	local tooltip = GameTooltip;
	tooltip:SetOwner(owner, anchor or "ANCHOR_RIGHT");
	local display = Data.GetDisplay(line.contentType, line.recordID, line.name);
	AddTitle(tooltip, line, display);

	GameTooltip_AddBlankLineToTooltip(tooltip);
	if not Tooltip.AddOwned(tooltip, line) then
		AddLine(tooltip, L["Not in your collection yet"], Colors.Muted);
	end
	local cartLine = Cart:GetLine(Data.Key(line.contentType, line.recordID));
	if cartLine then
		local got, need, _, collected = Cart:GetProgress(cartLine);
		local icon = AtlasIcon("Perks-ShoppingCart", 14);
		if collected then
			AddLine(tooltip, icon .. " " .. L["In your Shopping Cart - collected"], Colors.Green);
		else
			AddLine(tooltip, icon .. " " .. L["In your Shopping Cart: %d / %d"]:format(got, need), Colors.Brass);
		end
	end

	Tooltip.AddHowToGet(tooltip, line, 1, false);
	GameTooltip_AddBlankLineToTooltip(tooltip);
	if HOUSING_DECOR_PREVIEW_TOOLTIP then
		GameTooltip_AddInstructionLine(tooltip, HOUSING_DECOR_PREVIEW_TOOLTIP);
	end
	GameTooltip_AddInstructionLine(tooltip, L["<Right-click for options>"]);
	tooltip:Show();
end

function Tooltip.OnBlizzardEntryMouseOver(entryFrame, tooltip)
	if not (tooltip and HSC.settings and HSC.settings.blizzardTooltips) then
		return;
	end
	local entryData = entryFrame and entryFrame.entryData;
	if not (entryData and entryData.recordID and entryData.contentType) then
		return;
	end
	if entryData.contentType ~= CT.Decor and entryData.contentType ~= CT.Dye and entryData.contentType ~= CT.Room then
		return;
	end

	local pseudoLine = {
		contentType = entryData.contentType,
		recordID = entryData.recordID,
		name = entryData.name,
	};
	local missing = (not entryData.invalid) and (entryData.numMissing or 0) or 0;
	local shown = Tooltip.AddHowToGet(tooltip, pseudoLine, math.max(missing, 1), true);

	local cartLine = Cart:GetLine(Data.Key(entryData.contentType, entryData.recordID));
	if cartLine then
		local got, need, _, collected = Cart:GetProgress(cartLine);
		if not shown then
			GameTooltip_AddBlankLineToTooltip(tooltip);
		end
		local icon = AtlasIcon("Perks-ShoppingCart", 14);
		if collected then
			AddLine(tooltip, icon .. " " .. L["In your Shopping Cart - collected"], Colors.Green);
		else
			AddLine(tooltip, icon .. " " .. L["In your Shopping Cart: %d / %d"]:format(got, need), Colors.Brass);
		end
		shown = true;
	end

	if shown then
		tooltip:Show();
	end
end
