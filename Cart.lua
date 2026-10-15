local _, HSC = ...
local L = HSC.L;
local Data = HSC.Data;
local CT = Data.CT;

local Cart = {};
HSC.Cart = Cart;

local BY_HAND = "~byhand";
Cart.BY_HAND = BY_HAND;

local function DB()
	return HSC.db;
end

function Cart:GetLines()
	return DB() and DB().lines or {};
end

function Cart:GetLine(key)
	return self:GetLines()[key];
end

function Cart:GetProgress(line)
	local need = line.need or 0;
	if line.manual then
		return need, need, 0, true;
	end
	local got = math.min(line.got or 0, need);
	local left = need - got;
	return got, need, left, left <= 0;
end

function Cart:IsCollected(line)
	local _, _, _, collected = self:GetProgress(line);
	return collected;
end

function Cart:GetLeftNow(line)
	local got, need, left = self:GetProgress(line);
	if left > 0 and not line.manual and line.base and Data.IsCountable(line.contentType) then
		local owned = Data.GetOwned(line.contentType, line.recordID);
		if owned then
			left = math.max(need - math.max(got, owned - line.base), 0);
		end
	end
	return left;
end

function Cart:GetStats()
	local stats = { lines = 0, collectedLines = 0, need = 0, got = 0, left = 0, blueprints = 0 };
	for _, line in pairs(self:GetLines()) do
		local got, need, left, collected = self:GetProgress(line);
		stats.lines = stats.lines + 1;
		stats.need = stats.need + need;
		stats.got = stats.got + got;
		stats.left = stats.left + left;
		if collected then
			stats.collectedLines = stats.collectedLines + 1;
		end
	end
	if DB() then
		for shareCode in pairs(DB().blueprints) do
			if shareCode ~= BY_HAND then
				stats.blueprints = stats.blueprints + 1;
			end
		end
	end
	return stats;
end

local undo;

local function Copy(value)
	if type(value) ~= "table" then
		return value;
	end
	local copy = {};
	for key, inner in pairs(value) do
		copy[key] = Copy(inner);
	end
	return copy;
end

local function SetUndo(value)
	undo = value;
	HSC:Fire("UNDO_CHANGED");
end

local function RememberForUndo(text)
	local db = DB();
	SetUndo({ text = text, lines = Copy(db.lines), blueprints = Copy(db.blueprints), collapsed = Copy(db.collapsed), at = GetTime() });
end

local function ForgetUndo()
	if undo then
		SetUndo(nil);
	end
end

function Cart:GetUndo()
	if undo then
		return undo.text, undo.at;
	end
	return nil;
end

function Cart:Undo()
	if not undo then
		return false;
	end
	local db, saved = DB(), undo;
	for key in pairs(saved.collapsed) do
		local shareCode = key:match("^bp:(.+)$");
		if shareCode and saved.blueprints[shareCode] and not db.blueprints[shareCode] then
			db.collapsed[key] = true;
		end
	end
	wipe(db.lines);
	for key, line in pairs(saved.lines) do
		db.lines[key] = line;
	end
	wipe(db.blueprints);
	for shareCode, blueprint in pairs(saved.blueprints) do
		db.blueprints[shareCode] = blueprint;
	end
	SetUndo(nil);
	HSC:Fire("CART_CHANGED");
	self:Refresh(true);
	return true, saved.text;
end

local BLUEPRINT_TYPE_NAMES = {
	[1] = HOUSING_BLUEPRINT_TYPE_HOUSE or L["Full Layout Blueprint"],
	[2] = HOUSING_BLUEPRINT_TYPE_ROOM or L["Room Blueprint"],
	[3] = HOUSING_BLUEPRINT_TYPE_INTERIOR or L["Interior Blueprint"],
	[4] = HOUSING_BLUEPRINT_TYPE_EXTERIOR or L["Exterior Blueprint"],
};

function Cart:GetBlueprintTypeName(blueprintType)
	return BLUEPRINT_TYPE_NAMES[blueprintType] or L["Blueprint"];
end

function Cart:GetBlueprintType(shareCode)
	if C_HousingBlueprint and C_HousingBlueprint.GetBlueprintTypeForCode then
		local ok, blueprintType = pcall(C_HousingBlueprint.GetBlueprintTypeForCode, shareCode);
		if ok and type(blueprintType) == "number" and blueprintType > 0 then
			return blueprintType;
		end
	end
	return nil;
end

function Cart:GetBlueprintName(shareCode)
	if shareCode == BY_HAND then
		return L["Added by hand"];
	end
	local db = DB();
	local blueprint = db and db.blueprints[shareCode];
	if blueprint and blueprint.customName then
		return blueprint.customName;
	end
	local known = db and db.knownBlueprints[shareCode];
	if known and known.name and known.name ~= "" then
		return known.name;
	end
	local recentName = HSC.Recent and HSC.Recent:GetName(shareCode);
	if recentName then
		return recentName;
	end
	if blueprint and blueprint.name then
		return blueprint.name;
	end
	local blueprintType = (blueprint and blueprint.type) or self:GetBlueprintType(shareCode);
	return ("%s (%s)"):format(self:GetBlueprintTypeName(blueprintType), strsub(shareCode or "?", 1, 5));
end

function Cart:GetBlueprints()
	local list = {};
	for shareCode, blueprint in pairs(DB() and DB().blueprints or {}) do
		if shareCode ~= BY_HAND then
			list[#list + 1] = {
				shareCode = shareCode, name = self:GetBlueprintName(shareCode), addedAt = blueprint.addedAt or 0,
				type = blueprint.type or self:GetBlueprintType(shareCode),
			};
		end
	end
	table.sort(list, function(a, b)
		if a.addedAt ~= b.addedAt then
			return a.addedAt < b.addedAt;
		end
		return a.name < b.name;
	end);
	return list;
end

function Cart:HasBlueprint(shareCode)
	return shareCode ~= nil and DB() ~= nil and DB().blueprints[shareCode] ~= nil;
end

function Cart:RenameBlueprint(shareCode, newName)
	local blueprint = DB().blueprints[shareCode];
	if not blueprint then
		return;
	end
	ForgetUndo();
	newName = newName and strtrim(newName) or "";
	blueprint.customName = (newName ~= "") and newName or nil;
	HSC.Recent:SetName(shareCode, blueprint.customName);
	HSC:Fire("CART_CHANGED");
end

local function EstimateMissing(contentType, recordID, total, serverMissing)
	if contentType == CT.Decor or contentType == CT.Dye then
		local owned = Data.GetOwned(contentType, recordID);
		if owned then
			return math.max(0, total - owned);
		end
	end
	return serverMissing;
end

local function Rebase(line, newNeed)
	line.need = math.max(0, newNeed);
	line.got = 0;
	line.manual = nil;
	line.base = Data.GetOwned(line.contentType, line.recordID);
end

local function TotalUses(line)
	local total = 0;
	for shareCode, uses in pairs(line.from) do
		if shareCode ~= BY_HAND then
			total = total + uses;
		end
	end
	return total;
end

local function ByHand(line)
	return line.from and line.from[BY_HAND] or 0;
end

local function MostMissing(line)
	local most = 0;
	for _, missing in pairs(line.from) do
		most = math.max(most, missing);
	end
	return most;
end

local function AvailableNow(line)
	local owned = Data.GetOwned(line.contentType, line.recordID);
	if line.avail == nil then
		return owned or 0;
	end
	if owned == nil or line.base == nil then
		return line.avail;
	end
	return math.max(line.avail + owned - line.base, 0);
end

local function Recompute(line, available)
	if not Data.IsCountable(line.contentType) then
		Rebase(line, MostMissing(line));
		return;
	end
	Rebase(line, math.max(TotalUses(line) - available, 0) + ByHand(line));
	line.avail = available;
end

local function Resize(line)
	if Data.IsCountable(line.contentType) then
		line.need = math.max(TotalUses(line) - (line.avail or 0), 0) + ByHand(line);
	else
		line.need = MostMissing(line);
	end
end

local function NotWantedAnymore(line)
	if not (line.lacked and Data.IsCountable(line.contentType)) or (line.need or 0) > 0 then
		return false;
	end
	for shareCode in pairs(line.from) do
		if line.lacked[shareCode] then
			return false;
		end
	end
	return true;
end

local function ByHandCollected(line)
	local byHand = ByHand(line);
	if byHand == 0 then
		return 0;
	end
	local got, need = Cart:GetProgress(line);
	return math.min(math.max(got - (need - byHand), 0), byHand);
end

function Cart:MergeIntoLine(line, shareCode, uses, missing)
	line.from = line.from or {};
	if not Data.IsCountable(line.contentType) then
		line.from[shareCode] = missing;
		Recompute(line);
		return;
	end
	local byHandGot = ByHandCollected(line);
	uses = math.max(uses or 0, missing);
	line.from[shareCode] = uses;
	line.lacked = line.lacked or {};
	local available;
	if missing > 0 then
		available = uses - missing;
		line.lacked[shareCode] = true;
	else
		available = math.max(uses, AvailableNow(line));
	end
	Recompute(line, math.max(available - byHandGot, 0));
	if byHandGot > 0 then
		line.got = byHandGot;
		line.base = line.base and (line.base - byHandGot);
	end
end

local function CountOtherBlueprints(line, key, shareCode)
	line.from = line.from or {};
	for code, blueprint in pairs(DB().blueprints) do
		local uses = blueprint.uses and blueprint.uses[key];
		if code ~= shareCode and uses and uses > 0 and line.from[code] == nil then
			line.from[code] = uses;
		end
	end
end

local function ShortTogether(contentType, recordID, key, shareCode, uses)
	local others = 0;
	for code, blueprint in pairs(DB().blueprints) do
		if code ~= shareCode and blueprint.uses and blueprint.uses[key] then
			others = others + blueprint.uses[key];
		end
	end
	if others == 0 then
		return false;
	end
	local owned = Data.GetOwned(contentType, recordID);
	return owned ~= nil and others + uses > math.max(uses, owned);
end

local function ForgetUses(key)
	for _, blueprint in pairs(DB().blueprints) do
		if blueprint.uses then
			blueprint.uses[key] = nil;
		end
	end
end

function Cart:AddBlueprint(contentInfo)
	ForgetUndo();
	local db = DB();
	local shareCode = contentInfo.shareCode;
	local estimated = contentInfo.targetHouseGUID == nil;
	local summary = {
		newLines = 0, updatedLines = 0, quantity = 0, invalid = 0, satisfied = 0,
		estimated = estimated, refreshed = db.blueprints[shareCode] ~= nil,
	};
	local now = time();
	local usesByKey = {};

	for _, group in ipairs(contentInfo.contentGroups or {}) do
		for _, entry in ipairs(group.entries or {}) do
			local contentType = entry.contentType or group.contentType;
			local recordID = entry.recordID;
			if contentType and recordID then
				local key = Data.Key(contentType, recordID);
				local line = db.lines[key];
				if entry.invalid then
					summary.invalid = summary.invalid + 1;
				else
					local missing = entry.numMissing or 0;
					if estimated then
						missing = EstimateMissing(contentType, recordID, entry.total or 0, missing);
					end
					local uses = entry.total or missing;
					local countable = Data.IsCountable(contentType);
					if countable and uses > 0 then
						usesByKey[key] = uses;
					end
					if line then
						local _, _, leftBefore = self:GetProgress(line);
						local wasThere = line.from ~= nil and line.from[shareCode] ~= nil;
						if missing > 0 or wasThere or countable then
							if countable then
								CountOtherBlueprints(line, key, shareCode);
							end
							self:MergeIntoLine(line, shareCode, uses, missing);
							local _, _, leftAfter = self:GetProgress(line);
							if missing > 0 or leftAfter > leftBefore then
								summary.updatedLines = summary.updatedLines + 1;
							elseif wasThere then
								summary.satisfied = summary.satisfied + 1;
							end
							summary.quantity = summary.quantity + math.max(leftAfter - leftBefore, 0);
						end
					elseif missing > 0 or (countable and uses > 0 and ShortTogether(contentType, recordID, key, shareCode, uses)) then
						line = { contentType = contentType, recordID = recordID, addedAt = now };
						if countable then
							CountOtherBlueprints(line, key, shareCode);
						end
						self:MergeIntoLine(line, shareCode, uses, missing);
						db.lines[key] = line;
						summary.newLines = summary.newLines + 1;
						summary.quantity = summary.quantity + line.need;
					end
					if line then
						line.name = entry.name or line.name;
						line.tooltip = entry.tooltip or line.tooltip;
					end
				end
			end
		end
	end

	local blueprint = db.blueprints[shareCode];
	if not blueprint then
		blueprint = { addedAt = now };
		db.blueprints[shareCode] = blueprint;
	end
	blueprint.updatedAt = now;
	blueprint.uses = usesByKey;
	blueprint.type = self:GetBlueprintType(shareCode) or blueprint.type;
	local known = db.knownBlueprints[shareCode];
	if known and known.name then
		blueprint.name = known.name;
	end

	if summary.newLines + summary.updatedLines + summary.satisfied == 0 then
		local stillUsed = false;
		for _, line in pairs(db.lines) do
			if line.from and line.from[shareCode] ~= nil then
				stillUsed = true;
				break;
			end
		end
		if not stillUsed then
			db.blueprints[shareCode] = nil;
		end
	end

	HSC:Fire("CART_CHANGED");
	return summary;
end

function Cart:PrintAddSummary(summary, shareCode)
	if not (HSC.settings and HSC.settings.addSummary) then
		return;
	end
	local name = "|cffffd200" .. self:GetBlueprintName(shareCode) .. "|r";
	local count = summary.newLines + summary.updatedLines;
	if count == 0 and not self:HasBlueprint(shareCode) then
		HSC:Print(L["You already have everything for %s."]:format(name));
	elseif count == 0 and not summary.refreshed then
		HSC:Print(L["Added %s - you already have enough for it as well."]:format(name));
	elseif count == 0 then
		HSC:Print(L["Updated %s - nothing from it is missing anymore."]:format(name));
	elseif summary.refreshed then
		HSC:Print((count == 1 and L["Updated %s in your cart - 1 item still missing."] or L["Updated %s in your cart - %d items still missing."]):format(name, count));
	elseif count == 1 then
		HSC:Print(L["Added 1 missing item from %s to your cart."]:format(name));
	else
		HSC:Print(L["Added %d missing items from %s to your cart."]:format(count, name));
	end
	if summary.invalid > 0 then
		HSC:Print((summary.invalid == 1 and L["1 item can't be used at this house (for example another faction's style) and was left out."]
			or L["%d items can't be used at this house (for example another faction's style) and were left out."]):format(summary.invalid));
	end
	if summary.estimated and count > 0 then
		HSC:Print(L["Not checked against a house of yours, so what's missing is worked out from your collection."]);
	end
end

function Cart:CountShared(contentInfo)
	local shared = 0;
	local estimated = contentInfo.targetHouseGUID == nil;
	for _, group in ipairs(contentInfo.contentGroups or {}) do
		for _, entry in ipairs(group.entries or {}) do
			local contentType = entry.contentType or group.contentType;
			if not entry.invalid and contentType and entry.recordID and Data.IsCountable(contentType) and (entry.total or 0) > 0 then
				local key = Data.Key(contentType, entry.recordID);
				local line = self:GetLine(key);
				local missing = entry.numMissing or 0;
				if estimated then
					missing = EstimateMissing(contentType, entry.recordID, entry.total or 0, missing);
				end
				local joinsLine = line ~= nil and not (line.from and line.from[contentInfo.shareCode] ~= nil);
				if missing == 0 and (joinsLine or (line == nil and ShortTogether(contentType, entry.recordID, key, contentInfo.shareCode, entry.total))) then
					shared = shared + 1;
				end
			end
		end
	end
	return shared;
end

function Cart:CountMissing(contentInfo)
	local lines, quantity = 0, 0;
	local estimated = contentInfo.targetHouseGUID == nil;
	for _, group in ipairs(contentInfo.contentGroups or {}) do
		for _, entry in ipairs(group.entries or {}) do
			if not entry.invalid then
				local contentType = entry.contentType or group.contentType;
				local missing = entry.numMissing or 0;
				if estimated and contentType and entry.recordID then
					missing = EstimateMissing(contentType, entry.recordID, entry.total or 0, missing);
				end
				if missing > 0 then
					lines = lines + 1;
					quantity = quantity + missing;
				end
			end
		end
	end
	return lines, quantity;
end

local function ForgetBlueprint(shareCode)
	local db = DB();
	db.blueprints[shareCode] = nil;
	db.collapsed["bp:" .. shareCode] = nil;
end

local function PruneBlueprints()
	local db = DB();
	local used = {};
	for _, line in pairs(db.lines) do
		for shareCode in pairs(line.from or {}) do
			used[shareCode] = true;
		end
	end
	for shareCode in pairs(db.blueprints) do
		if not used[shareCode] then
			ForgetBlueprint(shareCode);
		end
	end
end

function Cart:RemoveLine(key)
	local line = DB().lines[key];
	if line then
		local name = Data.GetDisplay(line.contentType, line.recordID, line.name).name;
		RememberForUndo(L["Removed %s."]:format("|cffffd200" .. name .. "|r"));
	end
	DB().lines[key] = nil;
	ForgetUses(key);
	PruneBlueprints();
	HSC:Fire("CART_CHANGED");
end

function Cart:SetCollected(key, collected)
	local line = DB().lines[key];
	if not line then
		return;
	end
	ForgetUndo();
	if collected then
		line.manual = true;
	elseif line.manual then
		line.manual = nil;
		self:UpdateLine(line);
	else
		local _, need = self:GetProgress(line);
		Rebase(line, need);
		if Data.IsCountable(line.contentType) and line.from then
			line.avail = math.max(TotalUses(line) - (need - ByHand(line)), 0);
		end
	end
	HSC:Fire("CART_CHANGED");
end

function Cart:ClearCollected()
	local db = DB();
	local collected = 0;
	for _, line in pairs(db.lines) do
		if self:IsCollected(line) then
			collected = collected + 1;
		end
	end
	if collected > 0 then
		RememberForUndo(collected == 1 and L["Cleared 1 collected item."] or L["Cleared %d collected items."]:format(collected));
	end
	local removed = 0;
	for key, line in pairs(db.lines) do
		if self:IsCollected(line) then
			db.lines[key] = nil;
			ForgetUses(key);
			removed = removed + 1;
		end
	end
	PruneBlueprints();
	HSC:Fire("CART_CHANGED");
	return removed;
end

function Cart:ClearAll()
	local db = DB();
	if next(db.lines) or next(db.blueprints) then
		RememberForUndo(L["Emptied your Shopping Cart."]);
	end
	wipe(db.lines);
	for shareCode in pairs(db.blueprints) do
		ForgetBlueprint(shareCode);
	end
	HSC:Fire("CART_CHANGED");
end

function Cart:RemoveBlueprint(shareCode)
	local db = DB();
	if db.blueprints[shareCode] then
		RememberForUndo(shareCode == BY_HAND and L["Removed the items you added by hand."]
			or L["Removed %s."]:format("|cffffd200" .. self:GetBlueprintName(shareCode) .. "|r"));
	end
	for key, line in pairs(db.lines) do
		local share = line.from and line.from[shareCode];
		if share ~= nil then
			line.from[shareCode] = nil;
			if line.lacked then
				line.lacked[shareCode] = nil;
			end
			if next(line.from) == nil then
				db.lines[key] = nil;
			else
				Resize(line);
				if NotWantedAnymore(line) then
					db.lines[key] = nil;
				end
			end
		end
	end
	ForgetBlueprint(shareCode);
	PruneBlueprints();
	HSC:Fire("CART_CHANGED");
end

function Cart:AddByHand(contentType, recordID, count, name)
	local db = DB();
	if not (db and contentType and recordID and Data.IsCountable(contentType)) then
		return nil;
	end
	ForgetUndo();
	count = math.max(math.floor(count or 1), 1);
	local key = Data.Key(contentType, recordID);
	local now = time();
	local line = db.lines[key];
	if line then
		line.from = line.from or {};
		local _, need, _, collected = self:GetProgress(line);
		if collected then
			local owned = Data.GetOwned(contentType, recordID);
			if owned and line.base then
				line.base = owned - need;
			end
			line.got, line.manual = need, nil;
		end
		line.from[BY_HAND] = ByHand(line) + count;
		Resize(line);
	else
		line = { contentType = contentType, recordID = recordID, addedAt = now, from = {}, lacked = {} };
		CountOtherBlueprints(line, key, nil);
		line.from[BY_HAND] = count;
		Recompute(line, Data.GetOwned(contentType, recordID) or 0);
		db.lines[key] = line;
	end
	line.name = name or line.name;
	local blueprint = db.blueprints[BY_HAND] or { addedAt = now };
	blueprint.updatedAt = now;
	db.blueprints[BY_HAND] = blueprint;
	HSC:Fire("CART_CHANGED");
	return line;
end

function Cart:GetByHand(key)
	local line = self:GetLine(key);
	return line and ByHand(line) or 0;
end

function Cart:RemoveOneByHand(key)
	local db = DB();
	local line = db.lines[key];
	if not (line and ByHand(line) > 0) then
		return;
	end
	ForgetUndo();
	line.from[BY_HAND] = (ByHand(line) > 1) and (ByHand(line) - 1) or nil;
	if next(line.from) == nil then
		db.lines[key] = nil;
	else
		Resize(line);
		if NotWantedAnymore(line) then
			db.lines[key] = nil;
		end
	end
	PruneBlueprints();
	HSC:Fire("CART_CHANGED");
end

local SETTLE_SECONDS = 1.5;
local settling = {};

local function NeedsSettling(line)
	if line.contentType ~= CT.Decor or (HSC.Merchant and HSC.Merchant:IsOpen()) then
		return false;
	end
	return Data.GetDecorItemCount(line.recordID) > 0;
end

function Cart:UpdateLine(line)
	if line.manual or not Data.IsCountable(line.contentType) then
		return false;
	end
	local owned = Data.GetOwned(line.contentType, line.recordID);
	if not owned then
		return false;
	end
	if line.base == nil then
		line.base = owned;
		return false;
	end
	local got = line.got or 0;
	if line.contentType == CT.Dye and owned < line.base + got and not HSC:IsWarmingUp() then
		line.base = owned - got;
	end
	got = math.min(owned - line.base, line.need or 0);
	local before = line.got or 0;
	local key = Data.Key(line.contentType, line.recordID);
	if got <= before then
		settling[key] = nil;
		return false;
	end
	if NeedsSettling(line) then
		local pending = settling[key];
		if not pending or pending.got ~= got then
			settling[key] = { got = got, since = GetTime() };
			HSC:Debounce("cartSettle", SETTLE_SECONDS + 0.1, function()
				Cart:Refresh();
			end);
			return false;
		end
		if GetTime() - pending.since < SETTLE_SECONDS then
			return false;
		end
	end
	settling[key] = nil;
	line.got = got;
	return true, before;
end

function Cart:Refresh(silent)
	if not DB() then
		return;
	end
	local changes = {};
	for _, line in pairs(DB().lines) do
		local changed, before = self:UpdateLine(line);
		if changed then
			changes[#changes + 1] = { line = line, before = before };
		end
	end
	if #changes > 0 then
		HSC:Fire("CART_PROGRESS", changes, silent or HSC:IsWarmingUp());
	end
	HSC:Fire("CART_REFRESH");
end

local function QueueRefresh()
	HSC:Debounce("cartRefresh", 0.4, function()
		Cart:Refresh();
	end);
end

HSC:RegisterEvent("HOUSING_STORAGE_UPDATED", QueueRefresh);
HSC:RegisterEvent("HOUSING_STORAGE_ENTRY_UPDATED", QueueRefresh);
HSC:RegisterEvent("HOUSE_DECOR_ADDED_TO_CHEST", QueueRefresh);
HSC:RegisterEvent("NEW_HOUSING_ITEM_ACQUIRED", QueueRefresh);
HSC:RegisterEvent("BAG_UPDATE_DELAYED", QueueRefresh);
HSC:RegisterEvent("DYE_COLOR_UPDATED", QueueRefresh);
HSC:RegisterEvent("PLAYER_MONEY", function()
	HSC:Debounce("moneyRefresh", 0.3, function()
		HSC:Fire("CART_REFRESH");
	end);
end);
HSC:RegisterEvent("CURRENCY_DISPLAY_UPDATE", function()
	HSC:Debounce("moneyRefresh", 0.3, function()
		HSC:Fire("CART_REFRESH");
	end);
end);

HSC:RegisterEvent("ITEM_DATA_LOAD_RESULT", function(_, itemID, success)
	if success and DB() and DB().lines[Data.Key(CT.Dye, itemID)] then
		Data.ForgetDisplay(CT.Dye, itemID);
		HSC:Debounce("itemNames", 0.2, function()
			HSC:Fire("CART_REFRESH");
		end);
	end
end);

HSC:RegisterEvent("HOUSING_BLUEPRINT_COLLECTION_RECEIVED", function(_, collection)
	if type(collection) ~= "table" or not DB() then
		return;
	end
	local known = DB().knownBlueprints;
	for _, group in ipairs(collection.groups or {}) do
		for _, info in ipairs(group.entries or {}) do
			if info.shareCode and info.name and not info.isAutoSave then
				known[info.shareCode] = { name = info.name, type = info.blueprintType };
			end
		end
	end
	HSC:Fire("CART_CHANGED");
end);

HSC:On("DB_READY", function()
	local db = DB();
	if (db.dbVersion or 1) < 2 then
		for _, line in pairs(db.lines) do
			if line.from and Data.IsCountable(line.contentType) then
				line.avail = math.max(TotalUses(line) - (line.need or 0), 0);
			end
		end
		db.dbVersion = 2;
	end
	for _, line in pairs(db.lines) do
		if line.lacked == nil and line.from and Data.IsCountable(line.contentType) then
			line.lacked = {};
			for shareCode in pairs(line.from) do
				if shareCode ~= BY_HAND then
					line.lacked[shareCode] = true;
				end
			end
		end
	end
	for key in pairs(db.collapsed) do
		local shareCode = key:match("^bp:(.+)$");
		if shareCode and not db.blueprints[shareCode] then
			db.collapsed[key] = nil;
		end
	end
end);

HSC:On("LOGIN", function()
	C_Timer.After(4, function() Cart:Refresh(true); end);
	C_Timer.After(15, function() Cart:Refresh(true); end);
end);
