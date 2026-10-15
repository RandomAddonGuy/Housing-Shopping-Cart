local _, HSC = ...
local L = HSC.L;
local Cart = HSC.Cart;
local Colors = HSC.Colors;

local Recent = {};
HSC.Recent = Recent;

local PER_TYPE = 8;
local OTHER_TYPE = 0;

local BlueprintType = (Enum and Enum.HousingBlueprintType) or {};
local TYPE_GROUPS = {
	{ type = BlueprintType.Interior or 3, label = HOUSING_BLUEPRINT_COLLECTION_GROUP_INTERIOR or L["Interiors"] },
	{ type = BlueprintType.Exterior or 4, label = HOUSING_BLUEPRINT_COLLECTION_GROUP_EXTERIOR or L["Exteriors"] },
	{ type = BlueprintType.Room or 2,     label = HOUSING_BLUEPRINT_COLLECTION_GROUP_ROOM or L["Rooms"] },
	{ type = BlueprintType.House or 1,    label = HOUSING_BLUEPRINT_COLLECTION_GROUP_HOUSE or L["Full Layouts"] },
	{ type = OTHER_TYPE,                  label = L["Other blueprints"] },
};
local KNOWN_TYPES = {};
for _, group in ipairs(TYPE_GROUPS) do
	KNOWN_TYPES[group.type] = true;
end

local function GetList()
	return HSC.db and HSC.db.recentBlueprints or {};
end

local function TypeOf(entry)
	local blueprintType = entry.type or Cart:GetBlueprintType(entry.shareCode);
	return (blueprintType and KNOWN_TYPES[blueprintType]) and blueprintType or OTHER_TYPE;
end

local function Find(shareCode)
	for index, entry in ipairs(GetList()) do
		if entry.shareCode == shareCode then
			return entry, index;
		end
	end
	return nil;
end

function Recent:Remember(shareCode, name)
	if not (HSC.db and type(shareCode) == "string" and shareCode ~= "") then
		return;
	end
	local list = HSC.db.recentBlueprints;
	local entry, index = Find(shareCode);
	if entry then
		table.remove(list, index);
	else
		entry = { shareCode = shareCode };
	end
	entry.type = Cart:GetBlueprintType(shareCode) or entry.type;
	if name and name ~= "" then
		entry.name = name;
	end
	entry.usedAt = time();
	table.insert(list, 1, entry);

	local counts = {};
	for i = #list, 1, -1 do
		local blueprintType = TypeOf(list[i]);
		counts[blueprintType] = (counts[blueprintType] or 0) + 1;
	end
	for i = #list, 1, -1 do
		local blueprintType = TypeOf(list[i]);
		if counts[blueprintType] > PER_TYPE then
			counts[blueprintType] = counts[blueprintType] - 1;
			table.remove(list, i);
		end
	end
	HSC:Fire("RECENT_CHANGED");
end

function Recent:GetName(shareCode)
	local entry = Find(shareCode);
	return entry and entry.name;
end

function Recent:SetName(shareCode, name)
	local entry = Find(shareCode);
	if entry then
		entry.name = (name and name ~= "") and name or nil;
		HSC:Fire("RECENT_CHANGED");
	end
end

function Recent:IsEmpty()
	return #GetList() == 0;
end

function Recent:GetMostRecent()
	return GetList()[1];
end

function Recent:Clear()
	if HSC.db then
		wipe(HSC.db.recentBlueprints);
		HSC:Fire("RECENT_CHANGED");
	end
end

function Recent.GroupByType(entries)
	local byType = {};
	for _, entry in ipairs(entries) do
		local blueprintType = TypeOf(entry);
		byType[blueprintType] = byType[blueprintType] or {};
		table.insert(byType[blueprintType], entry);
	end
	local groups = {};
	for _, group in ipairs(TYPE_GROUPS) do
		if byType[group.type] then
			groups[#groups + 1] = { type = group.type, label = group.label, entries = byType[group.type] };
		end
	end
	return groups;
end

function Recent.FormatAge(timestamp)
	local seconds = math.max(time() - (timestamp or time()), 0);
	if seconds < 60 then
		return L["just now"];
	elseif seconds < 3600 then
		return L["%d min ago"]:format(math.floor(seconds / 60));
	elseif seconds < 86400 then
		return L["%d h ago"]:format(math.floor(seconds / 3600));
	end
	local days = math.floor(seconds / 86400);
	return days == 1 and L["1 day ago"] or L["%d days ago"]:format(days);
end

local function EntryText(entry)
	local text = Cart:GetBlueprintName(entry.shareCode);
	if entry.usedAt then
		text = text .. "  " .. Colors.Faint:WrapTextInColorCode(Recent.FormatAge(entry.usedAt));
	end
	if Cart:HasBlueprint(entry.shareCode) then
		text = text .. " " .. HSC.AtlasIcon("Perks-ShoppingCart", 12);
	end
	return text;
end

local function AddEntries(description, entries, onPick)
	for _, group in ipairs(Recent.GroupByType(entries)) do
		description:CreateTitle(group.label);
		for _, entry in ipairs(group.entries) do
			local button = description:CreateButton(EntryText(entry), function()
				onPick(entry.shareCode);
			end);
			button:SetTooltip(function(tooltip)
				GameTooltip_SetTitle(tooltip, Cart:GetBlueprintName(entry.shareCode));
				GameTooltip_AddNormalLine(tooltip, Cart:GetBlueprintTypeName(TypeOf(entry)));
				GameTooltip_AddColoredLine(tooltip, entry.shareCode, Colors.Muted);
				if Cart:HasBlueprint(entry.shareCode) then
					GameTooltip_AddColoredLine(tooltip, L["In your Shopping Cart"], Colors.Brass);
				end
			end);
		end
	end
end

local function SavedEntries()
	local entries = {};
	for shareCode, known in pairs(HSC.db and HSC.db.knownBlueprints or {}) do
		if known.name and known.name ~= "" then
			entries[#entries + 1] = { shareCode = shareCode, type = known.type, name = known.name };
		end
	end
	table.sort(entries, function(a, b)
		return strcmputf8i(a.name, b.name) < 0;
	end);
	return entries;
end

function Recent:HasSaved()
	return #SavedEntries() > 0;
end

function Recent:AddToMenu(rootDescription, onPick, withSaved)
	local list = GetList();
	if #list == 0 then
		rootDescription:CreateTitle(L["Blueprints you import show up here."]);
	else
		AddEntries(rootDescription, list, onPick);
	end
	local saved = withSaved and SavedEntries() or {};
	if #saved > 0 then
		rootDescription:CreateDivider();
		local savedMenu = rootDescription:CreateButton(L["Your saved blueprints"]);
		AddEntries(savedMenu, saved, onPick);
	end
	if #list > 0 then
		rootDescription:CreateDivider();
		rootDescription:CreateButton(L["Clear recent blueprints"], function()
			Recent:Clear();
		end);
	end
end
