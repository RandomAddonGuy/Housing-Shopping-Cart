local _, HSC = ...
local Data = HSC.Data;
local Vendors = HSC.Vendors;
local Merchant = HSC.Merchant;

local Learn = {};
HSC.Learn = Learn;

local MOVED = 0.01;

local function Readable(value)
	return value ~= nil and not (issecretvalue and issecretvalue(value));
end

local function NpcID(unit)
	local guid = UnitGUID(unit);
	if not (Readable(guid) and type(guid) == "string") then
		return nil;
	end
	local unitType, _, _, _, _, npcID = strsplit("-", guid);
	if unitType == "Creature" or unitType == "Vehicle" then
		return tonumber(npcID);
	end
	return nil;
end

local function IsHousingItem(itemID)
	if C_DyeColor and C_DyeColor.GetDyeColorsForItem then
		local ok, colors = pcall(C_DyeColor.GetDyeColorsForItem, itemID);
		if ok and type(colors) == "table" and #colors > 0 then
			return true;
		end
	end
	if C_HousingCatalog and C_HousingCatalog.GetCatalogEntryInfoByItem then
		local ok, info = pcall(C_HousingCatalog.GetCatalogEntryInfoByItem, itemID);
		return ok and type(info) == "table";
	end
	return false;
end

local function CostsCoupons(index)
	for slot = 1, (MAX_ITEM_COST or 3) do
		local _, _, link = GetMerchantItemCostItem(index, slot);
		if type(link) == "string" and tonumber(link:match("currency:(%d+)")) == Data.COMMUNITY_COUPONS_CURRENCY_ID then
			return true;
		end
	end
	return false;
end

local function InNeighborhood()
	if not (C_Housing and C_Housing.IsOnNeighborhoodMap) then
		return false;
	end
	local ok, onMap = pcall(C_Housing.IsOnNeighborhoodMap);
	return ok and onMap == true;
end

local function Build()
	local version, build = GetBuildInfo();
	return version and build and (version .. "." .. build) or nil;
end

local function PlayerSpot()
	local mapID = C_Map.GetBestMapForUnit("player");
	if not mapID then
		return nil;
	end
	local position = C_Map.GetPlayerMapPosition(mapID, "player");
	if not position then
		return nil;
	end
	local x, y = position:GetXY();
	if not (x and y) or (x == 0 and y == 0) then
		return nil;
	end
	return mapID, floor(x * 10000 + 0.5) / 10000, floor(y * 10000 + 0.5) / 10000;
end

function Learn:Merchant()
	local learned = HSC.db and HSC.db.learned;
	local npcID = learned and Merchant:IsOpen() and NpcID("npc");
	if not npcID then
		return false;
	end
	local wares, coupons = {}, false;
	for index = 1, GetMerchantNumItems() do
		local itemID = GetMerchantItemID(index);
		if itemID and IsHousingItem(itemID) then
			wares[#wares + 1] = itemID;
			coupons = coupons or CostsCoupons(index);
		end
	end
	if #wares == 0 then
		return false;
	end

	local changed = false;
	local vendor = learned.vendors[npcID];
	if not vendor then
		vendor = {};
		learned.vendors[npcID] = vendor;
		changed = true;
	end
	vendor.spots = vendor.spots or {};
	local name = UnitName("npc");
	if Readable(name) and type(name) == "string" and name ~= "" and name ~= vendor.name then
		vendor.name, vendor.locale, changed = name, GetLocale(), true;
	end
	local faction = UnitFactionGroup("npc");
	if Readable(faction) and (faction == "Alliance" or faction == "Horde") and faction ~= vendor.faction then
		vendor.faction, changed = faction, true;
	end
	local mapID, x, y = PlayerSpot();
	if mapID then
		local spot = vendor.spots[mapID];
		if not spot or math.abs(spot.x - x) > MOVED or math.abs(spot.y - y) > MOVED then
			vendor.spots[mapID], changed = { x = x, y = y }, true;
		end
	end
	vendor.seen, vendor.build = time(), Build();

	for _, itemID in ipairs(wares) do
		local sellers = learned.items[itemID];
		if not sellers then
			sellers = {};
			learned.items[itemID] = sellers;
		end
		if not sellers[npcID] then
			sellers[npcID], changed = true, true;
		end
	end

	if coupons and InNeighborhood() then
		local initiativeID, title = Vendors:GetActiveEndeavor();
		if initiativeID then
			local before = learned.endeavors[npcID];
			if before == nil then
				learned.endeavors[npcID], changed = initiativeID, true;
			elseif before ~= initiativeID and before ~= 0 then
				learned.endeavors[npcID], changed = 0, true;
			end
			if title and learned.endeavorTitles[initiativeID] ~= title then
				learned.endeavorTitles[initiativeID] = title;
			end
		end
	end

	if changed then
		Vendors:Invalidate();
		Data.ResetCaches();
		HSC:Fire("VENDORS_CHANGED");
	end
	return changed;
end

function Learn:GetCounts()
	local learned = HSC.db and HSC.db.learned;
	local vendors, items, endeavors = 0, 0, 0;
	for _ in pairs(learned and learned.vendors or {}) do vendors = vendors + 1; end
	for _ in pairs(learned and learned.items or {}) do items = items + 1; end
	for _, initiativeID in pairs(learned and learned.endeavors or {}) do
		if initiativeID ~= 0 then endeavors = endeavors + 1; end
	end
	return vendors, items, endeavors;
end

local function LearnSafely()
	local ok, err = pcall(Learn.Merchant, Learn);
	if not ok then
		geterrorhandler()(err);
	end
end

HSC:RegisterEvent("MERCHANT_SHOW", function()
	C_Timer.After(0.5, LearnSafely);
end);
HSC:RegisterEvent("MERCHANT_UPDATE", function()
	if Merchant:IsOpen() then
		HSC:Debounce("learnMerchant", 1, LearnSafely);
	end
end);
