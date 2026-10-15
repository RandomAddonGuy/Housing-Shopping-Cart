local _, HSC = ...
local L = HSC.L;

local Data = {};
HSC.Data = Data;

local ContentTypeEnum = (Enum and Enum.HousingBlueprintContentType) or {};
local CT = {
	None      = ContentTypeEnum.None      or 0,
	HouseType = ContentTypeEnum.HouseType or 1,
	Room      = ContentTypeEnum.Room      or 2,
	Decor     = ContentTypeEnum.Decor     or 3,
	Dye       = ContentTypeEnum.Dye       or 4,
	Fixture   = ContentTypeEnum.Fixture   or 5,
	Other     = ContentTypeEnum.Other     or 6,
};
Data.CT = CT;

local CatalogEntryTypeEnum = (Enum and Enum.HousingCatalogEntryType) or {};
local CATALOG_ENTRY_TYPE = {
	[CT.Decor] = CatalogEntryTypeEnum.Decor or 1,
	[CT.Room]  = CatalogEntryTypeEnum.Room  or 2,
};

Data.Types = {
	[CT.Decor]     = { order = 1, label = HOUSING_BLUEPRINT_CONTENT_TYPE_DECOR or L["Decor"],                  atlas = "house-chest-icon" },
	[CT.Dye]       = { order = 2, label = HOUSING_BLUEPRINT_CONTENT_TYPE_DYE or L["Dyes"],                     atlas = "dye-drop_32" },
	[CT.Room]      = { order = 3, label = HOUSING_BLUEPRINT_CONTENT_TYPE_ROOM or L["Rooms"],                   atlas = "house-room-limit-icon" },
	[CT.Fixture]   = { order = 4, label = HOUSING_BLUEPRINT_CONTENT_TYPE_FIXTURE or L["Exterior Fixtures"],    atlas = "house-fixture-budget-icon" },
	[CT.HouseType] = { order = 5, label = HOUSING_BLUEPRINT_CONTENT_TYPE_HOUSE_TYPE or L["House Type"],       atlas = "housing-dashboard-homestone-icon" },
	[CT.Other]     = { order = 6, label = HOUSING_BLUEPRINT_CONTENT_TYPE_OTHER or L["Other"],                  atlas = "house-chest-icon" },
};

function Data.GetTypeInfo(contentType)
	return Data.Types[contentType] or Data.Types[CT.Other];
end

function Data.Key(contentType, recordID)
	return contentType .. ":" .. recordID;
end

local Kinds = {
	vendor      = { order = 1,  atlas = "housing-decor-vendor_32",        color = CreateColor(1.00, 0.80, 0.36), label = BATTLE_PET_SOURCE_3 or L["Vendor"] },
	endeavor    = { order = 1.5, atlas = "housing-dashboard-homestone-icon", color = CreateColor(0.98, 0.70, 0.50), label = L["Endeavor"] },
	quest       = { order = 2,  atlas = "QuestNormal",                    color = CreateColor(1.00, 0.92, 0.40), label = BATTLE_PET_SOURCE_2 or L["Quest"] },
	achievement = { order = 3,  atlas = "UI-Achievement-Shield-NoPoints", color = CreateColor(1.00, 0.60, 0.26), label = BATTLE_PET_SOURCE_6 or L["Achievement"] },
	profession  = { order = 4,  atlas = "Profession",                     color = CreateColor(0.48, 0.78, 1.00), label = BATTLE_PET_SOURCE_4 or L["Profession"] },
	drop        = { order = 5,  atlas = "DungeonSkull",                   color = CreateColor(1.00, 0.46, 0.42), label = BATTLE_PET_SOURCE_1 or L["Drop"] },
	treasure    = { order = 6,  atlas = "VignetteLoot",                   color = CreateColor(0.40, 0.90, 0.75), label = L["Treasure"] },
	event       = { order = 7,  atlas = "VignetteEvent",                  color = CreateColor(1.00, 0.58, 0.86), label = BATTLE_PET_SOURCE_7 or L["World Event"] },
	petbattle   = { order = 8,  atlas = "WildBattlePet",                  color = CreateColor(0.60, 0.86, 0.42), label = BATTLE_PET_SOURCE_5 or L["Pet Battle"] },
	discovery   = { order = 9,  atlas = "QuestionMarkContinent-Icon",     color = CreateColor(0.55, 0.85, 0.95), label = BATTLE_PET_SOURCE_11 or L["Discovery"] },
	market      = { order = 10, atlas = "hearthsteel-icon-32x32",         color = CreateColor(0.80, 0.62, 1.00), label = L["Housing Market"] },
	shop        = { order = 11, atlas = "hud-microbutton-BStore-Up",      color = CreateColor(0.40, 0.72, 1.00), label = BATTLE_PET_SOURCE_10 or L["In-Game Shop"] },
	promotion   = { order = 12, atlas = "hud-microbutton-BStore-Up",      color = CreateColor(0.40, 0.72, 1.00), label = BATTLE_PET_SOURCE_8 or L["Promotion"] },
	tradingpost = { order = 13, atlas = "trading-post-minimap-icon",      color = CreateColor(0.40, 0.85, 0.85), label = BATTLE_PET_SOURCE_12 or L["Trading Post"] },
	auction     = { order = 14, atlas = "Auctioneer",                     color = CreateColor(0.92, 0.76, 0.40), label = BUTTON_LAG_AUCTIONHOUSE or L["Auction House"] },
	other       = { order = 99, atlas = "house-chest-icon",               color = CreateColor(0.74, 0.71, 0.66), label = OTHER or L["Other"] },
};
Data.Kinds = Kinds;

function Data.GetKindInfo(kind)
	return Kinds[kind] or Kinds.other;
end

local labelToKind;
local function GetLabelToKind()
	if labelToKind then
		return labelToKind;
	end
	labelToKind = {};
	local function Add(text, kind)
		if type(text) == "string" and text ~= "" then
			local key = strlower(strtrim(text));
			if labelToKind[key] == nil then
				labelToKind[key] = kind;
			end
		end
	end
	Add(BATTLE_PET_SOURCE_1, "drop");
	Add(BATTLE_PET_SOURCE_2, "quest");
	Add(BATTLE_PET_SOURCE_3, "vendor");
	Add(BATTLE_PET_SOURCE_4, "profession");
	Add(BATTLE_PET_SOURCE_5, "petbattle");
	Add(BATTLE_PET_SOURCE_6, "achievement");
	Add(BATTLE_PET_SOURCE_7, "event");
	Add(BATTLE_PET_SOURCE_8, "promotion");
	Add(BATTLE_PET_SOURCE_10, "shop");
	Add(BATTLE_PET_SOURCE_11, "discovery");
	Add(BATTLE_PET_SOURCE_12, "tradingpost");
	Add("Vendors", "vendor");
	Add("Treasure", "treasure");
	Add("Event", "event");
	Add("Holiday", "event");
	Add("World Event", "event");
	Add("Endeavor", "endeavor");
	Add("Neighborhood Endeavor", "endeavor");
	return labelToKind;
end

function Data.GetCatalogInfo(contentType, recordID)
	local entryType = CATALOG_ENTRY_TYPE[contentType];
	if not entryType or not recordID then
		return nil;
	end
	if not (C_HousingCatalog and C_HousingCatalog.GetCatalogEntryInfoByRecordID) then
		return nil;
	end
	local ok, info = pcall(C_HousingCatalog.GetCatalogEntryInfoByRecordID, entryType, recordID);
	if ok and type(info) == "table" then
		return info;
	end
	return nil;
end

function Data.GetDyeOwned(itemID)
	local best;
	if C_DyeColor and C_DyeColor.GetDyeColorsForItem and C_DyeColor.GetDyeColorInfo then
		local ok, colorIDs = pcall(C_DyeColor.GetDyeColorsForItem, itemID);
		if ok and type(colorIDs) == "table" then
			for _, colorID in ipairs(colorIDs) do
				local okInfo, info = pcall(C_DyeColor.GetDyeColorInfo, colorID);
				local owned = okInfo and type(info) == "table" and tonumber(info.numOwned);
				if owned and (not best or owned > best) then
					best = owned;
				end
			end
		end
	end
	if C_Item and C_Item.GetItemCount then
		best = math.max(best or 0, Data.GetItemCount(itemID));
	end
	return best;
end

function Data.GetItemCount(itemID)
	if not (itemID and C_Item and C_Item.GetItemCount) then
		return 0;
	end
	local includeBank, includeUses, includeReagentBank, includeAccountBank = true, false, true, true;
	local ok, count = pcall(C_Item.GetItemCount, itemID, includeBank, includeUses, includeReagentBank, includeAccountBank);
	return (ok and type(count) == "number") and count or 0;
end

function Data.GetDecorItemCount(recordID)
	local info = Data.GetCatalogInfo(CT.Decor, recordID);
	return info and Data.GetItemCount(info.itemID) or 0;
end

function Data.GetOwned(contentType, recordID)
	if contentType == CT.Decor or contentType == CT.Room then
		local info = Data.GetCatalogInfo(contentType, recordID);
		if not info then
			return nil;
		end
		local stored = info.totalNumStored or info.quantity or 0;
		local placed = info.totalNumPlaced or info.numPlaced or 0;
		local owned = stored + (info.remainingRedeemable or 0) + placed;
		if contentType == CT.Decor then
			owned = owned + Data.GetItemCount(info.itemID);
		end
		return owned;
	elseif contentType == CT.Dye then
		return Data.GetDyeOwned(recordID);
	end
	return nil;
end

function Data.GetLineItemID(line)
	if line.contentType == CT.Decor then
		return Data.GetDisplay(line.contentType, line.recordID, line.name).itemID;
	elseif line.contentType == CT.Dye then
		return line.recordID;
	end
	return nil;
end

function Data.IsCountable(contentType)
	return contentType == CT.Decor or contentType == CT.Room or contentType == CT.Dye;
end

function Data.GetQualityColor(quality)
	if quality and ColorManager and ColorManager.GetColorDataForItemQuality then
		local colorData = ColorManager.GetColorDataForItemQuality(quality);
		if colorData and colorData.color then
			return colorData.color;
		end
	end
	if quality and ITEM_QUALITY_COLORS and ITEM_QUALITY_COLORS[quality] then
		return ITEM_QUALITY_COLORS[quality].color;
	end
	return HIGHLIGHT_FONT_COLOR;
end

local displayCache = {};

function Data.ForgetDisplay(contentType, recordID)
	displayCache[Data.Key(contentType, recordID)] = nil;
end

function Data.GetDisplay(contentType, recordID, fallbackName)
	local key = Data.Key(contentType, recordID);
	local display = displayCache[key];
	if display and display.complete then
		return display;
	end

	display = { name = fallbackName or UNKNOWN or "?" };

	if contentType == CT.Decor or contentType == CT.Room then
		local info = Data.GetCatalogInfo(contentType, recordID);
		if info then
			if info.name and info.name ~= "" then
				display.name = info.name;
			end
			display.quality = info.quality;
			display.itemID = info.itemID;
			display.icon = info.iconTexture;
			display.iconAtlas = info.iconAtlas;
			display.placementCost = info.placementCost;
			display.sourceText = info.sourceText;
			display.isPrefab = info.isPrefab;
			display.isUniqueTrophy = info.isUniqueTrophy;
			display.subcategoryIDs = info.subcategoryIDs;
			display.categoryIDs = info.categoryIDs;
			display.dataTagsByID = info.dataTagsByID;
			display.firstAcquisitionBonus = info.firstAcquisitionBonus;
			display.complete = true;
		end
		if not display.icon and not display.iconAtlas and contentType == CT.Decor
			and C_HousingDecor and C_HousingDecor.GetDecorIcon then
			local ok, icon = pcall(C_HousingDecor.GetDecorIcon, recordID);
			if ok and icon then
				display.icon = icon;
			end
		end
	elseif contentType == CT.Dye then
		display.itemID = recordID;
		if C_Item then
			local name = C_Item.GetItemNameByID and C_Item.GetItemNameByID(recordID);
			if name and name ~= "" then
				display.name = name;
				display.complete = true;
			elseif C_Item.RequestLoadItemDataByID then
				C_Item.RequestLoadItemDataByID(recordID);
			end
			display.icon = C_Item.GetItemIconByID and C_Item.GetItemIconByID(recordID);
			display.quality = C_Item.GetItemQualityByID and C_Item.GetItemQualityByID(recordID);
		end
	else
		display.complete = true;
	end

	if not display.icon and not display.iconAtlas then
		display.iconAtlas = Data.GetTypeInfo(contentType).atlas;
	end

	displayCache[key] = display;
	return display;
end

function Data.SetIcon(texture, display)
	if display.icon then
		texture:SetTexture(display.icon);
		texture:SetTexCoord(0, 1, 0, 1);
	else
		texture:SetAtlas(display.iconAtlas or "house-chest-icon");
	end
end

local function ParseMoney(text)
	local copper, found = 0, false;
	for amount, texture in text:gmatch("([%d%.,]+)%s*|T([^|]+)|t") do
		local value = tonumber((amount:gsub("[^%d]", "")));
		local lower = strlower(texture);
		if value then
			if lower:find("goldicon", 1, true) or lower:find("coin%-gold") then
				copper, found = copper + value * 10000, true;
			elseif lower:find("silvericon", 1, true) or lower:find("coin%-silver") then
				copper, found = copper + value * 100, true;
			elseif lower:find("coppericon", 1, true) or lower:find("coin%-copper") then
				copper, found = copper + value, true;
			end
		end
	end
	return found and copper or nil;
end

local function ParseCost(text)
	if type(text) ~= "string" or text == "" then
		return nil;
	end
	local cost;
	local amount, currencyID = text:match("([%d%.,]+)%s*|Hcurrency:(%d+)");
	if currencyID then
		cost = { currencyID = tonumber(currencyID), amount = tonumber((amount:gsub("[^%d]", ""))) or 0 };
	end
	local copper = ParseMoney(text);
	if copper then
		cost = cost or {};
		cost.copper = copper;
	end
	if cost then
		return cost;
	end
	local plain = text:match("^%s*([%d%.,]+)%s*$");
	if plain then
		local gold = tonumber((plain:gsub("[^%d]", "")));
		if gold then
			return { copper = gold * 10000 };
		end
	end
	return nil;
end

local function CurrencyInfo(currencyID)
	if C_CurrencyInfo and C_CurrencyInfo.GetCurrencyInfo then
		local ok, info = pcall(C_CurrencyInfo.GetCurrencyInfo, currencyID);
		if ok and type(info) == "table" then
			return info;
		end
	end
	return nil;
end

local function FormatCurrency(currencyID, amount, withName)
	local info = CurrencyInfo(currencyID);
	local total = BreakUpLargeNumbers(amount);
	local icon = info and info.iconFileID and ("|T" .. info.iconFileID .. ":0|t") or "";
	if withName and info and info.name then
		return ("%s %s %s"):format(total, icon, info.name);
	end
	return ("%s %s"):format(total, icon);
end

function Data.FormatCost(cost, quantity, withName)
	quantity = quantity or 1;
	if not cost then
		return nil;
	end
	local parts = {};
	if cost.copper then
		local separateThousands = true;
		parts[#parts + 1] = GetMoneyString(cost.copper * quantity, separateThousands);
	end
	if cost.currencyID then
		parts[#parts + 1] = FormatCurrency(cost.currencyID, (cost.amount or 0) * quantity, withName);
	end
	if #parts == 0 then
		return nil;
	end
	return table.concat(parts, " + ");
end

function Data.CanAffordCurrency(cost, quantity)
	if not (cost and cost.currencyID) then
		return nil;
	end
	local info = CurrencyInfo(cost.currencyID);
	if info and info.quantity then
		return info.quantity >= (cost.amount or 0) * (quantity or 1);
	end
	return nil;
end

function Data.CanAfford(cost, quantity)
	quantity = quantity or 1;
	if not cost then
		return nil;
	end
	local result;
	if cost.copper then
		result = GetMoney() >= cost.copper * quantity;
	end
	local currency = Data.CanAffordCurrency(cost, quantity);
	if currency ~= nil then
		result = (result ~= false) and currency;
	end
	return result;
end

function Data.NewTotals()
	return { copper = 0, currencies = {}, order = {} };
end

function Data.AddToTotals(totals, cost, quantity)
	if not cost then
		return;
	end
	if cost.copper then
		totals.copper = totals.copper + cost.copper * quantity;
	end
	if cost.currencyID then
		if not totals.currencies[cost.currencyID] then
			totals.currencies[cost.currencyID] = 0;
			totals.order[#totals.order + 1] = cost.currencyID;
		end
		totals.currencies[cost.currencyID] = totals.currencies[cost.currencyID] + (cost.amount or 0) * quantity;
	end
end

function Data.FormatTotals(totals, withNames, separator)
	local parts = {};
	if totals.copper > 0 then
		local text = Data.FormatCost({ copper = totals.copper });
		parts[#parts + 1] = (GetMoney() < totals.copper) and HSC.Colors.Red:WrapTextInColorCode(text) or text;
	end
	for _, currencyID in ipairs(totals.order) do
		local amount = totals.currencies[currencyID];
		local text = FormatCurrency(currencyID, amount, withNames);
		local canAfford = Data.CanAffordCurrency({ currencyID = currencyID, amount = amount }, 1);
		parts[#parts + 1] = (canAfford == false) and HSC.Colors.Red:WrapTextInColorCode(text) or text;
	end
	return table.concat(parts, separator or "  ·  ");
end

function Data.CanAffordTotals(totals)
	if GetMoney() < totals.copper then
		return false;
	end
	for currencyID, amount in pairs(totals.currencies) do
		if Data.CanAffordCurrency({ currencyID = currencyID, amount = amount }, 1) == false then
			return false;
		end
	end
	return true;
end

function Data.GetCurrencyOwned(currencyID)
	local info = CurrencyInfo(currencyID);
	return info and info.quantity, info;
end

local function StripColors(text)
	return (text:gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|cn[^:|]*:", ""):gsub("|r", ""));
end

local function SplitLabel(line)
	local label, value = line:match("^%s*([^:|]-)%s*:%s*(.-)%s*$");
	if label and label ~= "" then
		return label, value;
	end
	return nil, strtrim(line);
end

local fieldLabels;
local function GetFieldLabels()
	if fieldLabels then
		return fieldLabels;
	end
	local function Normalize(text)
		return type(text) == "string" and strlower(strtrim((text:gsub(":", "")))) or nil;
	end
	fieldLabels = { zone = {}, faction = {}, cost = {} };
	for _, text in ipairs({ ZONE, ZONE_COLON, LOCATION_COLON, "Zone", "Location" }) do
		local key = Normalize(text);
		if key then fieldLabels.zone[key] = true; end
	end
	for _, text in ipairs({ FACTION, "Faction", "Reputation" }) do
		local key = Normalize(text);
		if key then fieldLabels.faction[key] = true; end
	end
	for _, text in ipairs({ COSTS_LABEL, "Cost", "Price" }) do
		local key = Normalize(text);
		if key then fieldLabels.cost[key] = true; end
	end
	return fieldLabels;
end

local function IsZoneLabel(label)
	return label ~= nil and GetFieldLabels().zone[strlower(label)] == true;
end

local function IsFactionLabel(label)
	return label ~= nil and GetFieldLabels().faction[strlower(label)] == true;
end

local function LooksLikeCost(label, value)
	if value:find("|Hcurrency:", 1, true) or value:find("|T", 1, true) then
		return true;
	end
	return label ~= nil and GetFieldLabels().cost[strlower(label)] == true;
end

local COMMUNITY_COUPONS_CURRENCY_ID = 3363;
Data.COMMUNITY_COUPONS_CURRENCY_ID = COMMUNITY_COUPONS_CURRENCY_ID;

function Data.ResolveEndeavor(source, itemID)
	if source.kind ~= "endeavor" or source.endeavorID or not source.vendor then
		return;
	end
	local Vendors = HSC.Vendors;
	local lists = { Vendors:Named(source.vendor), itemID and Vendors:ForItem(itemID) or {} };
	for _, candidates in ipairs(lists) do
		for _, npcID in ipairs(candidates) do
			local initiativeID = Vendors:GetEndeavor(npcID);
			if initiativeID then
				source.endeavorID = initiativeID;
				source.endeavor = Vendors:GetEndeavorTitle(initiativeID);
				source.name = source.endeavor;
				source.label = Kinds.endeavor.label;
				return;
			end
		end
	end
end

function Data.IsEndeavorActive(source)
	return HSC.Vendors:IsEndeavorActive(source.endeavorID, source.endeavor);
end

local function MakeEndeavorSource(source, fromVendor)
	source.kind = "endeavor";
	if not fromVendor then
		source.endeavor = source.name;
		return;
	end
	source.vendor = source.name;
	source.label = L["Endeavor vendor"];
	Data.ResolveEndeavor(source);
end

local function ParseBlock(block)
	local lines = {};
	for line in (block .. "\n"):gmatch("(.-)\n") do
		line = strtrim(line);
		if line ~= "" then
			if line:find("%s%s+[^%s:|]+:") then
				line = line:gsub("%s%s+([^%s:|][^:|]-:)", "\n%1");
				for piece in (line .. "\n"):gmatch("(.-)\n") do
					piece = strtrim(piece);
					if piece ~= "" then
						lines[#lines + 1] = piece;
					end
				end
			else
				lines[#lines + 1] = line;
			end
		end
	end
	if #lines == 0 then
		return nil;
	end

	local source = { details = {} };
	local label, value = SplitLabel(lines[1]);
	source.label = label;
	source.name = (value ~= "" and value) or label or lines[1];
	source.kind = (label and GetLabelToKind()[strlower(label)]) or "other";

	for i = 2, #lines do
		local fieldLabel, fieldValue = SplitLabel(lines[i]);
		if IsZoneLabel(fieldLabel) then
			source.zones = source.zones or {};
			source.zones[#source.zones + 1] = fieldValue;
			source.zone = source.zone or fieldValue;
		elseif IsFactionLabel(fieldLabel) and not source.faction then
			local faction, standing = fieldValue:match("^(.-)%s+%-%s+(.+)$");
			source.faction = faction or fieldValue;
			source.standing = standing;
		elseif LooksLikeCost(fieldLabel, fieldValue) and not source.cost then
			source.cost = ParseCost(fieldValue);
			source.costText = fieldValue;
		else
			source.details[#source.details + 1] = fieldLabel and (fieldLabel .. ": " .. fieldValue) or fieldValue;
		end
	end
	if source.kind == "vendor" and source.cost and source.cost.currencyID == COMMUNITY_COUPONS_CURRENCY_ID then
		MakeEndeavorSource(source, true);
	elseif source.kind == "endeavor" then
		MakeEndeavorSource(source, false);
	end
	return source;
end

function Data.ParseSources(text)
	local sources = {};
	if type(text) ~= "string" or text == "" then
		return sources;
	end
	text = StripColors(text):gsub("\r", ""):gsub("|n", "\n");
	for block in (text .. "\n\n"):gmatch("(.-)\n%s*\n") do
		local source = ParseBlock(block);
		if source then
			sources[#sources + 1] = source;
		end
	end
	return sources;
end

local NO_ZONES = {};

function Data.GetZones(source)
	return source.zones or (source.zone and { source.zone }) or NO_ZONES;
end

function Data.SourceMentions(source, text)
	if (source.name and strlower(source.name):find(text, 1, true))
		or (source.vendor and strlower(source.vendor):find(text, 1, true)) then
		return true;
	end
	for _, zone in ipairs(Data.GetZones(source)) do
		if strlower(zone):find(text, 1, true) then
			return true;
		end
	end
	return false;
end

local sourcesCache = {};

local ITEM_BIND_NONE = (Enum and Enum.ItemBind and Enum.ItemBind.None) or 0;
local function GetDyeSources(itemID)
	local sources = {};
	local Vendors = HSC.Vendors;
	for _, npcID in ipairs(Vendors:ForItem(itemID)) do
		local vendor = Vendors:Get(npcID);
		local spot = vendor and vendor.spots[1];
		local mapInfo = spot and C_Map.GetMapInfo(spot.map);
		sources[#sources + 1] = {
			kind = "vendor", name = Vendors:GetName(npcID) or L["Unknown vendor"],
			zone = mapInfo and mapInfo.name, details = {},
		};
	end
	local bindType = select(14, C_Item.GetItemInfo(itemID));
	if bindType == nil then
		C_Item.RequestLoadItemDataByID(itemID);
		return sources, false;
	end
	if bindType == ITEM_BIND_NONE then
		sources[#sources + 1] = { kind = "auction", label = "", name = Kinds.auction.label, details = { L["Not bound - other players can sell it."] } };
	end
	return sources, true;
end

local NO_SOURCES = {};

function Data.GetSources(line)
	local key = Data.Key(line.contentType, line.recordID);
	local cached = sourcesCache[key];
	if cached then
		return cached;
	end

	local sources;
	if line.contentType == CT.Dye then
		local complete;
		sources, complete = GetDyeSources(line.recordID);
		if not complete then
			return sources;
		end
	elseif line.contentType == CT.Decor or line.contentType == CT.Room then
		local display = Data.GetDisplay(line.contentType, line.recordID, line.name);
		if not display.complete then
			return NO_SOURCES;
		end
		sources = Data.ParseSources(display.sourceText);
		for _, source in ipairs(sources) do
			Data.ResolveEndeavor(source, display.itemID);
		end
	else
		sources = NO_SOURCES;
	end

	if line.contentType == CT.Decor and C_HousingCatalog and C_HousingCatalog.GetMarketInfoForDecor then
		local ok, marketInfo = pcall(C_HousingCatalog.GetMarketInfoForDecor, line.recordID);
		if ok and type(marketInfo) == "table" and (marketInfo.price or 0) > 0 then
			local copy = {};
			for i, source in ipairs(sources) do
				copy[i] = source;
			end
			copy[#copy + 1] = {
				kind = "market",
				name = L["Housing Market"],
				marketPrice = marketInfo.price,
				inBundle = marketInfo.bundleIDs and #marketInfo.bundleIDs > 0,
				details = {},
			};
			sources = copy;
		end
	end

	sourcesCache[key] = sources;
	return sources;
end

function Data.ResetCaches()
	wipe(sourcesCache);
	for key, display in pairs(displayCache) do
		if not display.complete then
			displayCache[key] = nil;
		end
	end
end

function Data.FormatHearthsteel(price)
	if Blizzard_HousingCatalogUtil and Blizzard_HousingCatalogUtil.FormatPrice then
		return Blizzard_HousingCatalogUtil.FormatPrice(price);
	end
	return BreakUpLargeNumbers(price) .. CreateAtlasMarkup("hearthsteel-icon-32x32", 16, 16, 0, -1);
end

function Data.GetPrimarySource(line)
	local sources = Data.GetSources(line);
	return sources[1], sources;
end

function Data.GetBestCost(line)
	local goldOnly, mixed, currencyOnly;
	for _, source in ipairs(Data.GetSources(line)) do
		local cost = source.cost;
		if cost and cost.copper and not cost.currencyID then
			if not goldOnly or cost.copper < goldOnly.copper then
				goldOnly = cost;
			end
		elseif cost and cost.copper then
			if not mixed or cost.copper < mixed.copper then
				mixed = cost;
			end
		elseif cost and cost.currencyID and not currencyOnly then
			currencyOnly = cost;
		end
	end
	return goldOnly or mixed or currencyOnly;
end

function Data.GetChatLink(line)
	if line.contentType == CT.Decor and C_HousingDecor and C_HousingDecor.GetDecorHyperlink then
		local ok, link = pcall(C_HousingDecor.GetDecorHyperlink, line.recordID);
		if ok and link then
			return link;
		end
	elseif line.contentType == CT.Dye and C_Item and C_Item.GetItemInfo then
		local _, link = C_Item.GetItemInfo(line.recordID);
		return link;
	end
	return nil;
end

function Data.CanPreview(line)
	return line.contentType == CT.Decor and HousingFramesUtil and HousingFramesUtil.PreviewHousingDecorID ~= nil;
end

function Data.Preview(line)
	if Data.CanPreview(line) and HSC:CanOpenPanel(HousingModelPreviewFrame) then
		HousingFramesUtil.PreviewHousingDecorID(line.recordID);
	end
end

local function DecorTrackingType()
	return Enum and Enum.ContentTrackingType and Enum.ContentTrackingType.Decor;
end

function Data.IsTrackable(line)
	local trackingType = DecorTrackingType();
	if line.contentType ~= CT.Decor or not trackingType or not C_ContentTracking then
		return false;
	end
	local ok, trackable = pcall(C_ContentTracking.IsTrackable, trackingType, line.recordID);
	return ok and trackable or false;
end

function Data.IsTracking(line)
	local trackingType = DecorTrackingType();
	if line.contentType ~= CT.Decor or not trackingType or not C_ContentTracking then
		return false;
	end
	local ok, tracking = pcall(C_ContentTracking.IsTracking, trackingType, line.recordID);
	return ok and tracking or false;
end

function Data.ToggleTracking(line)
	if line.contentType ~= CT.Decor then
		return;
	end
	if Blizzard_HousingCatalogUtil and Blizzard_HousingCatalogUtil.TrackHousingDecorID then
		Blizzard_HousingCatalogUtil.TrackHousingDecorID(line.recordID);
		return;
	end
	local trackingType = DecorTrackingType();
	if not trackingType or not C_ContentTracking then
		return;
	end
	if C_ContentTracking.IsTracking(trackingType, line.recordID) then
		C_ContentTracking.StopTracking(trackingType, line.recordID, Enum.ContentTrackingStopType.Manual);
	else
		local trackingError = C_ContentTracking.StartTracking(trackingType, line.recordID);
		if trackingError and ContentTrackingUtil and ContentTrackingUtil.DisplayTrackingError then
			ContentTrackingUtil.DisplayTrackingError(trackingError);
		end
	end
end

function Data.OpenMapToTracked(line)
	if not HSC:CanOpenPanel(WorldMapFrame, L["The map can't be opened during combat."]) then
		return;
	end
	local trackingType = DecorTrackingType();
	if trackingType and ContentTrackingUtil and ContentTrackingUtil.OpenMapToTrackable then
		ContentTrackingUtil.OpenMapToTrackable(trackingType, line.recordID);
	end
end

function Data.ShowInCatalog(line)
	if line.contentType ~= CT.Decor or not HSC:CanOpenPanel(HousingDashboardFrame) then
		return;
	end
	if not HousingDashboardFrame then
		C_AddOns.LoadAddOn("Blizzard_HousingDashboard");
	end
	EventRegistry:TriggerEvent("HousingCatalogFrame.OpenToDecorID", line.recordID);
end
