local _, HSC = ...
local L = HSC.L;
local Cart = HSC.Cart;

local Import = {};
HSC.Import = Import;

local REQUEST_TIMEOUT = 15;
local HOUSES_TIMEOUT = 5;

local pending;
local houses;
local houseWaiters = {};

function Import.ParseInput(text)
	if type(text) ~= "string" then
		return nil;
	end
	text = strtrim((text:gsub("||", "|")));
	if text == "" then
		return nil;
	end
	local linkCode, linkText = text:match("|Hhousingblueprint:([^:|]+)[^|]*|h(.-)|h");
	local linkName = linkText and strtrim(linkText:match("^%[(.*)%]$") or linkText);
	if linkName == "" then
		linkName = nil;
	end
	local code = linkCode or text;

	local api = C_HousingBlueprint;
	if not (api and api.IsShareCodeValid) then
		return nil, linkName;
	end
	local ok, valid = pcall(api.IsShareCodeValid, code);
	if not (ok and valid) then
		return nil, linkName;
	end
	if api.UpdateBlueprintStringFromInput then
		local okUpdate, updated = pcall(api.UpdateBlueprintStringFromInput, code);
		if okUpdate and type(updated) == "string" and updated ~= "" then
			code = updated;
		end
	end
	return code, linkName;
end

local function IsVisible(frame)
	return frame ~= nil and frame:IsVisible();
end

function Import:GetBlockedReason()
	local api = C_HousingBlueprint;
	if not (api and api.RequestBlueprintContents) then
		return L["Blueprints aren't available on this character."];
	end
	if HousingFramesUtil and HousingFramesUtil.IsBlueprintOperationInProgress then
		local ok, busy = pcall(HousingFramesUtil.IsBlueprintOperationInProgress);
		if ok and busy then
			return L["The game is busy importing a blueprint - try again in a moment."];
		end
	end
	local dashboard = _G.HousingDashboardFrame;
	local collection = dashboard and dashboard.CollectionContent;
	local details = collection and collection.BlueprintDetails;
	if IsVisible(_G.HousingBlueprintImportFrame) or IsVisible(_G.HousingBlueprintContentListFrame)
		or (details and IsVisible(details.ContentSummary)) then
		return L["Close Blizzard's blueprint windows first - the game looks up one blueprint at a time."];
	end
	return nil;
end

function Import.GetErrorText(result)
	local results = Enum.HousingResult or {};
	if result ~= nil and result == results.DbError then
		result = results.BlueprintNotFound;
	end
	local text = HousingResultToErrorText and result ~= nil and HousingResultToErrorText[result];
	return text or ERR_HOUSING_RESULT_BLUEPRINT_GENERIC_CONTENT_ERROR or L["The game couldn't load that blueprint."];
end

local function HasHouseAPI()
	return C_Housing ~= nil and C_Housing.GetPlayerOwnedHouses ~= nil;
end

function Import.GetHouseKey(info)
	return ("%s:%s"):format(tostring(info.neighborhoodName or ""), tostring(info.plotID or ""));
end

function Import.GetHouseLabel(info)
	local name = info.houseName ~= "" and info.houseName or nil;
	local neighborhood = info.neighborhoodName ~= "" and info.neighborhoodName or nil;
	if name and neighborhood then
		return ("%s (%s)"):format(name, neighborhood);
	end
	return name or neighborhood or L["Your house"];
end

function Import:GetHouses()
	if not HasHouseAPI() then
		return {};
	end
	return houses;
end

local function FlushHouseWaiters()
	local waiters = houseWaiters;
	houseWaiters = {};
	for _, callback in ipairs(waiters) do
		local ok, err = pcall(callback);
		if not ok then
			geterrorhandler()(err);
		end
	end
end

function Import:WithHouses(callback)
	if houses or not HasHouseAPI() then
		callback();
		return;
	end
	houseWaiters[#houseWaiters + 1] = callback;
	if #houseWaiters == 1 then
		C_Timer.After(HOUSES_TIMEOUT, FlushHouseWaiters);
		pcall(C_Housing.GetPlayerOwnedHouses);
	end
end

function Import:RequestHouses()
	self:WithHouses(function() end);
end

local function GetTrackedHouseGUID()
	if not (C_Housing and C_Housing.GetTrackedHouseGuid) then
		return nil;
	end
	local ok, guid = pcall(C_Housing.GetTrackedHouseGuid);
	return ok and guid or nil;
end

function Import:GetTargetHouse()
	local list = self:GetHouses();
	if not list or #list == 0 then
		return nil;
	end
	local picked = HSC.settings and HSC.settings.importHouse;
	local tracked = GetTrackedHouseGUID();
	local trackedHouse;
	for _, info in ipairs(list) do
		if picked and Import.GetHouseKey(info) == picked then
			return info;
		end
		if tracked and info.houseGUID == tracked then
			trackedHouse = info;
		end
	end
	return trackedHouse or list[1];
end

function Import:SetTargetHouse(info)
	HSC.settings.importHouse = info and Import.GetHouseKey(info) or nil;
	HSC:Fire("IMPORT_CHANGED");
end

HSC:RegisterEvent("PLAYER_HOUSE_LIST_UPDATED", function(_, houseInfos)
	if type(houseInfos) ~= "table" then
		return;
	end
	local list = {};
	for _, info in ipairs(houseInfos) do
		if type(info) == "table" and info.houseGUID then
			list[#list + 1] = info;
		end
	end
	houses = list;
	FlushHouseWaiters();
	HSC:Fire("IMPORT_CHANGED");
end);

function Import:IsPending()
	return pending ~= nil;
end

function Import:GetPending()
	return pending;
end

local function Finish(request, ok, result)
	if pending ~= request then
		return;
	end
	pending = nil;
	if request.timer then
		request.timer:Cancel();
	end
	if ok then
		Cart:PrintAddSummary(result, request.shareCode);
		if Cart:HasBlueprint(request.shareCode) then
			HSC:PlaySound("LOOT_WINDOW_COIN_SOUND");
			if HSC.settings.openOnAdd then
				HSC:ShowWindow();
			end
		end
	else
		HSC:Print(L["Couldn't add the blueprint: %s"]:format(result));
	end
	HSC:Fire("IMPORT_DONE", ok, request.shareCode, result);
	HSC:Fire("IMPORT_CHANGED");
end

local function Send(request)
	if pending ~= request then
		return;
	end
	local blocked = Import:GetBlockedReason();
	if blocked then
		Finish(request, false, blocked);
		return;
	end
	local api = C_HousingBlueprint;
	request.house = Import:GetTargetHouse();
	request.waitingForHouses = nil;
	request.timer = C_Timer.NewTimer(REQUEST_TIMEOUT, function()
		Finish(request, false, L["The game didn't answer - try again in a moment."]);
	end);
	local ok;
	if request.house and api.RequestBlueprintContentsForContext then
		ok = pcall(api.RequestBlueprintContentsForContext, request.shareCode, request.house.houseGUID);
	else
		ok = pcall(api.RequestBlueprintContents, request.shareCode);
	end
	if not ok then
		Finish(request, false, Import.GetErrorText(nil));
		return;
	end
	HSC:Fire("IMPORT_CHANGED");
end

function Import:Start(shareCode, options)
	if pending then
		return false, L["Still waiting for the last blueprint."];
	end
	if not (HSC.db and shareCode) then
		return false, L["That isn't a share code."];
	end
	local blocked = self:GetBlockedReason();
	if blocked then
		return false, blocked;
	end
	local request = { shareCode = shareCode, name = options and options.name, waitingForHouses = true };
	pending = request;
	HSC:Fire("IMPORT_CHANGED");
	self:WithHouses(function()
		Send(request);
	end);
	return true;
end

HSC:RegisterEvent("HOUSING_BLUEPRINT_CONTENTS_RECEIVED", function(_, contentInfo)
	local request = pending;
	if not (request and not request.waitingForHouses and type(contentInfo) == "table"
		and contentInfo.shareCode == request.shareCode and contentInfo.contentGroups) then
		return;
	end
	local summary = Cart:AddBlueprint(contentInfo);
	HSC.Recent:Remember(request.shareCode, request.name);
	if request.name and request.name ~= "" then
		Cart:RenameBlueprint(request.shareCode, request.name);
	end
	Finish(request, true, summary);
end);

HSC:RegisterEvent("HOUSING_BLUEPRINT_CONTENTS_FAILURE", function(_, shareCode, result)
	local request = pending;
	if request and not request.waitingForHouses and shareCode == request.shareCode then
		Finish(request, false, Import.GetErrorText(result));
	end
end);
