local _, HSC = ...
local L = HSC.L;
local Data = HSC.Data;
local Cart = HSC.Cart;
local Vendors = HSC.Vendors;

local Map = {};
HSC.Map = Map;

local MAP_TYPE_CONTINENT = (Enum and Enum.UIMapType and Enum.UIMapType.Continent) or 2;

local function IsForPlayer(vendor, spot)
	if vendor.class then
		local _, classToken = UnitClass("player");
		if classToken ~= vendor.class then
			return false;
		end
	end
	if spot.faction then
		local faction = UnitFactionGroup("player");
		if (faction == "Alliance" and spot.faction == "H") or (faction == "Horde" and spot.faction == "A") then
			return false;
		end
	end
	return true;
end

local function SpotsOf(npcID)
	local vendor = Vendors:Get(npcID);
	local spots = {};
	for _, spot in ipairs(vendor and vendor.spots or {}) do
		if IsForPlayer(vendor, spot) then
			spots[#spots + 1] = { npcID = npcID, mapID = spot.map, x = spot.x, y = spot.y, portal = vendor.portal };
		end
	end
	return spots;
end

local function MapName(mapID)
	local info = C_Map.GetMapInfo(mapID);
	return info and info.name or UNKNOWN or "?";
end

local function StandsIn(npcID, zone)
	local wanted = strlower(zone);
	for _, spot in ipairs(SpotsOf(npcID)) do
		local info, guard = C_Map.GetMapInfo(spot.mapID), 0;
		while info and guard < 10 do
			if info.name and strlower(info.name) == wanted then
				return true;
			end
			info = info.parentMapID and info.parentMapID ~= 0 and C_Map.GetMapInfo(info.parentMapID);
			guard = guard + 1;
		end
	end
	return false;
end

local function LearnNames(line, ids)
	local named = true;
	for _, npcID in ipairs(ids) do
		named = named and Vendors:GetName(npcID) ~= nil;
	end
	if named then
		return;
	end
	local sources = {};
	for _, source in ipairs(Data.GetSources(line)) do
		local name = source.vendor or ((source.kind == "vendor" or source.kind == "endeavor") and source.name);
		if name then
			sources[#sources + 1] = { name = name, zones = Data.GetZones(source) };
		end
	end
	for _, npcID in ipairs(ids) do
		if not Vendors:GetName(npcID) then
			local match;
			if #ids == 1 and #sources == 1 then
				match = sources[1];
			else
				for _, source in ipairs(sources) do
					for _, zone in ipairs(source.zones) do
						if StandsIn(npcID, zone) then
							match = (match == nil) and source or false;
							break;
						end
					end
				end
			end
			if match then
				Vendors:SetSessionName(npcID, match.name);
			end
		end
	end
end

local function VendorIDsFor(line)
	local ids = {};
	local itemID = Data.GetLineItemID(line);
	for _, npcID in ipairs(Vendors:ForItem(itemID)) do
		if #SpotsOf(npcID) > 0 then
			ids[#ids + 1] = npcID;
		end
	end
	if #ids > 0 then
		LearnNames(line, ids);
		return ids;
	end
	local seen = {};
	for _, source in ipairs(Data.GetSources(line)) do
		if source.kind == "vendor" or source.kind == "endeavor" then
			for _, npcID in ipairs(Vendors:Named(source.vendor or source.name)) do
				if not seen[npcID] and #SpotsOf(npcID) > 0 then
					seen[npcID] = true;
					ids[#ids + 1] = npcID;
				end
			end
		end
	end
	return ids;
end

function Map.GetVendorName(npcID)
	return Vendors:GetName(npcID) or L["Unknown vendor"];
end

function Map.GetVendorSpots(line)
	local spots = {};
	for _, npcID in ipairs(VendorIDsFor(line)) do
		for _, spot in ipairs(SpotsOf(npcID)) do
			spot.name = Map.GetVendorName(npcID);
			spot.mapName = MapName(spot.mapID);
			spots[#spots + 1] = spot;
		end
	end
	local here = C_Map.GetBestMapForUnit("player");
	table.sort(spots, function(a, b)
		if (a.mapID == here) ~= (b.mapID == here) then
			return a.mapID == here;
		end
		if a.name ~= b.name then
			return strcmputf8i(a.name, b.name) < 0;
		end
		return a.mapID < b.mapID;
	end);
	return spots;
end

function Map.GetEndeavorNote(npcID)
	local initiativeID = Vendors:GetEndeavor(npcID);
	if not initiativeID then
		return nil;
	end
	return L["Endeavor: %s"]:format(Vendors:GetEndeavorTitle(initiativeID)), Vendors:IsEndeavorActive(initiativeID);
end

local function CanWaypoint(mapID)
	local ok, canSet = pcall(C_Map.CanSetUserWaypointOnMap, mapID);
	return ok and canSet == true;
end

local function OnParentMap(fromMap, x, y)
	local info = C_Map.GetMapInfo(fromMap);
	local parentID = info and info.parentMapID;
	if not parentID or parentID == 0 then
		return nil;
	end
	local okWorld, continentID, worldPos = pcall(C_Map.GetWorldPosFromMapPos, fromMap, CreateVector2D(x, y));
	if not (okWorld and continentID and worldPos) then
		return nil;
	end
	local okMap, _, mapPos = pcall(C_Map.GetMapPosFromWorldPos, continentID, worldPos, parentID);
	if not (okMap and mapPos) then
		return nil;
	end
	local px, py = mapPos:GetXY();
	if px < 0 or px > 1 or py < 0 or py > 1 then
		return nil;
	end
	return parentID, px, py;
end

local function WaypointFor(spot)
	local mapID, x, y = spot.mapID, spot.x, spot.y;
	for _ = 1, 3 do
		if CanWaypoint(mapID) then
			return mapID, x, y, false;
		end
		mapID, x, y = OnParentMap(mapID, x, y);
		if not mapID then
			break;
		end
	end
	local portal = spot.portal;
	if portal and CanWaypoint(portal.map) then
		return portal.map, portal.x, portal.y, true;
	end
	return nil;
end

function Map.ShowVendor(spot, keepMap)
	local name = spot.name or Map.GetVendorName(spot.npcID);
	local mapName = spot.mapName or MapName(spot.mapID);
	local mapID, x, y, viaPortal = WaypointFor(spot);
	if mapID then
		C_Map.SetUserWaypoint(UiMapPoint.CreateFromCoordinates(mapID, x, y));
		C_SuperTrack.SetSuperTrackedUserWaypoint(true);
		if viaPortal then
			HSC:Print(L["Waypoint set to the portal that takes you to %s (%s)."]:format(name, mapName));
		else
			HSC:Print(L["Waypoint set: %s in %s (%.1f, %.1f)."]:format(name, mapName, spot.x * 100, spot.y * 100));
		end
	else
		HSC:Print(L["%s is in %s (%.1f, %.1f) - the game doesn't allow a waypoint there."]:format(name, mapName, spot.x * 100, spot.y * 100));
	end
	if not keepMap and HSC:CanOpenPanel(WorldMapFrame, L["The map can't be opened during combat - your waypoint is set."]) then
		OpenWorldMap(spot.mapID);
	end
	HSC:PlaySound("UI_MAP_WAYPOINT_CLICK_TO_PLACE");
	return mapID ~= nil;
end

function Map.CanTrackSource(line)
	return Data.IsTracking(line) or Data.IsTrackable(line);
end

function Map.ShowSourceByTracking(line)
	if not Data.IsTracking(line) then
		Data.ToggleTracking(line);
	end
	local trackingType = Enum.ContentTrackingType and Enum.ContentTrackingType.Decor;
	if trackingType and C_SuperTrack.SetSuperTrackedContent then
		pcall(C_SuperTrack.SetSuperTrackedContent, trackingType, line.recordID);
	end
	Data.OpenMapToTracked(line);
	HSC:Fire("CART_REFRESH");
end

local neededCache;
local shownSignature;

local function NeededByVendor()
	if neededCache then
		return neededCache;
	end
	local needed = {};
	for _, line in pairs(Cart:GetLines()) do
		local _, _, left = Cart:GetProgress(line);
		if left > 0 then
			for _, npcID in ipairs(VendorIDsFor(line)) do
				local entry = needed[npcID];
				if not entry then
					entry = { npcID = npcID, lines = {}, left = 0 };
					needed[npcID] = entry;
				end
				entry.lines[#entry.lines + 1] = line;
				entry.left = entry.left + left;
			end
		end
	end
	neededCache = needed;
	return needed;
end

local ancestorCache = {};
local function IsAncestor(ancestorID, mapID)
	local ancestors = ancestorCache[mapID];
	if not ancestors then
		ancestors = {};
		local info = C_Map.GetMapInfo(mapID);
		local guard = 0;
		while info and info.parentMapID and info.parentMapID ~= 0 and guard < 10 do
			ancestors[info.parentMapID] = true;
			info = C_Map.GetMapInfo(info.parentMapID);
			guard = guard + 1;
		end
		ancestorCache[mapID] = ancestors;
	end
	return ancestors[ancestorID] == true;
end

local function PositionOn(fromMap, x, y, viewMap)
	if fromMap == viewMap then
		return x, y;
	end
	if not (IsAncestor(viewMap, fromMap) or IsAncestor(fromMap, viewMap)) then
		return nil;
	end
	local okWorld, continentID, worldPos = pcall(C_Map.GetWorldPosFromMapPos, fromMap, CreateVector2D(x, y));
	if not (okWorld and continentID and worldPos) then
		return nil;
	end
	local okMap, _, mapPos = pcall(C_Map.GetMapPosFromWorldPos, continentID, worldPos, viewMap);
	if not (okMap and mapPos) then
		return nil;
	end
	local px, py = mapPos:GetXY();
	if px < 0 or px > 1 or py < 0 or py > 1 then
		return nil;
	end
	return px, py;
end

local function Signature(needed)
	local parts = {};
	for npcID, entry in pairs(needed) do
		parts[#parts + 1] = npcID .. ":" .. entry.left;
	end
	table.sort(parts);
	return table.concat(parts, ",");
end

function Map.GetPinsForMap(viewMap)
	local pins = {};
	shownSignature = Signature(NeededByVendor());
	local info = viewMap and C_Map.GetMapInfo(viewMap);
	if not info or info.mapType < MAP_TYPE_CONTINENT then
		return pins;
	end
	for npcID, entry in pairs(NeededByVendor()) do
		for _, spot in ipairs(SpotsOf(npcID)) do
			local x, y = PositionOn(spot.mapID, spot.x, spot.y, viewMap);
			if x then
				pins[#pins + 1] = { entry = entry, spot = spot, x = x, y = y };
			end
		end
	end
	return pins;
end

local function Invalidate()
	neededCache = nil;
	HSC:Fire("MAP_VENDORS_CHANGED");
end
HSC:On("CART_CHANGED", Invalidate);
HSC:On("CART_PROGRESS", Invalidate);
HSC:On("VENDORS_CHANGED", Invalidate);
HSC:On("CART_REFRESH", function()
	neededCache = nil;
	if WorldMapFrame and WorldMapFrame:IsShown() and Signature(NeededByVendor()) ~= shownSignature then
		HSC:Fire("MAP_VENDORS_CHANGED");
	end
end);
