local _, HSC = ...
local L = HSC.L;

local Vendors = {};
HSC.Vendors = Vendors;

local GAME_VENDORS = HSC.VendorList or {};
local GAME_ITEMS = HSC.VendorItems or {};
local GAME_ENDEAVORS = HSC.Endeavors or {};

local sessionNames = {};
local trackingNames = {};
local byName;
local endeavorOf;

local function Learned()
	return HSC.db and HSC.db.learned;
end

function Vendors:Invalidate()
	byName, endeavorOf = nil, nil;
	for npcID, name in pairs(trackingNames) do
		if name == false then
			trackingNames[npcID] = nil;
		end
	end
end

local function TrackingName(npcID)
	if trackingNames[npcID] == nil then
		local game = GAME_VENDORS[npcID];
		local name = false;
		if game and game.src and C_ContentTracking and C_ContentTracking.GetVendorTrackingInfo then
			local ok, info = pcall(C_ContentTracking.GetVendorTrackingInfo, game.src);
			if ok and type(info) == "table" and type(info.creatureName) == "string" and info.creatureName ~= "" then
				name = info.creatureName;
			end
		end
		trackingNames[npcID] = name;
	end
	return trackingNames[npcID] or nil;
end

function Vendors:GetName(npcID)
	local learned = Learned();
	local seen = learned and learned.vendors[npcID];
	local scan = HSC.db and HSC.db.scan;
	return (seen and seen.name) or TrackingName(npcID) or sessionNames[npcID]
		or (GAME_VENDORS[npcID] and GAME_VENDORS[npcID].name) or (scan and scan.names and scan.names[npcID]);
end

function Vendors:SetSessionName(npcID, name)
	if type(name) ~= "string" or name == "" or sessionNames[npcID] then
		return;
	end
	sessionNames[npcID] = name;
	if byName then
		local key = strlower(name);
		byName[key] = byName[key] or {};
		table.insert(byName[key], npcID);
	end
end

function Vendors:Get(npcID)
	local game = GAME_VENDORS[npcID];
	local learned = Learned();
	local seen = learned and learned.vendors[npcID];
	if not (game or seen) then
		return nil;
	end
	local spots, maps = {}, {};
	for _, spot in ipairs(game and game.spots or {}) do
		spots[#spots + 1] = spot;
		maps[spot.map] = true;
	end
	for mapID, spot in pairs(seen and seen.spots or {}) do
		if not maps[mapID] and spot.x and spot.y then
			spots[#spots + 1] = { map = mapID, x = spot.x, y = spot.y, faction = seen.faction == "Alliance" and "A" or seen.faction == "Horde" and "H" or nil };
		end
	end
	return { npcID = npcID, name = self:GetName(npcID), spots = spots, class = game and game.class, portal = game and game.portal };
end

function Vendors:ForItem(itemID)
	local ids, seen = {}, {};
	for _, npcID in ipairs(itemID and GAME_ITEMS[itemID] or {}) do
		seen[npcID] = true;
		ids[#ids + 1] = npcID;
	end
	local learned = Learned();
	for npcID in pairs(itemID and learned and learned.items[itemID] or {}) do
		if not seen[npcID] then
			seen[npcID] = true;
			ids[#ids + 1] = npcID;
		end
	end
	return ids;
end

local function AddName(index, name, npcID)
	if type(name) == "string" and name ~= "" then
		local key = strlower(name);
		index[key] = index[key] or {};
		for _, known in ipairs(index[key]) do
			if known == npcID then
				return;
			end
		end
		table.insert(index[key], npcID);
	end
end

function Vendors:Named(name)
	if not byName then
		byName = {};
		for npcID in pairs(GAME_VENDORS) do
			AddName(byName, self:GetName(npcID), npcID);
		end
		local learned = Learned();
		for npcID, seen in pairs(learned and learned.vendors or {}) do
			AddName(byName, seen.name, npcID);
		end
		for npcID, sessionName in pairs(sessionNames) do
			AddName(byName, sessionName, npcID);
		end
	end
	return type(name) == "string" and byName[strlower(name)] or {};
end

function Vendors:GetActiveEndeavor()
	local api = C_NeighborhoodInitiative;
	if not (api and api.GetNeighborhoodInitiativeInfo) then
		return nil;
	end
	local ok, info = pcall(api.GetNeighborhoodInitiativeInfo);
	if not (ok and type(info) == "table" and info.isLoaded) then
		return nil;
	end
	local id = tonumber(info.initiativeID);
	local title = type(info.title) == "string" and info.title ~= "" and info.title or nil;
	if (id and id > 0) or title then
		return (id and id > 0) and id or nil, title;
	end
	return nil;
end

function Vendors:GetEndeavor(npcID)
	if not endeavorOf then
		endeavorOf = {};
		for initiativeID, endeavor in pairs(GAME_ENDEAVORS) do
			for _, vendorID in ipairs(endeavor.vendors or {}) do
				endeavorOf[vendorID] = initiativeID;
			end
		end
		local learned = Learned();
		for vendorID, initiativeID in pairs(learned and learned.endeavors or {}) do
			endeavorOf[vendorID] = (initiativeID ~= 0) and initiativeID or nil;
		end
	end
	return endeavorOf[npcID];
end

function Vendors:GetEndeavorTitle(initiativeID)
	if not initiativeID then
		return nil;
	end
	local activeID, activeTitle = self:GetActiveEndeavor();
	if activeID == initiativeID and activeTitle then
		return activeTitle;
	end
	if GAME_ENDEAVORS[initiativeID] then
		return GAME_ENDEAVORS[initiativeID].title;
	end
	local learned = Learned();
	return learned and learned.endeavorTitles[initiativeID] or L["Endeavor"];
end

function Vendors:IsEndeavorActive(initiativeID, title)
	local activeID, activeTitle = self:GetActiveEndeavor();
	if initiativeID and activeID then
		return initiativeID == activeID;
	end
	return title ~= nil and title == activeTitle;
end

HSC:On("CART_CHANGED", function()
	Vendors:Invalidate();
end);
