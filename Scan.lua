local _, HSC = ...
local L = HSC.L;
local Data = HSC.Data;
local CT = Data.CT;

local Scan = {};
HSC.Scan = Scan;

local STEP_SECONDS = 0.1;
local PER_STEP = 6;
local START_DELAY = 30;
local RETRIES = 3;
local RETRY_SECONDS = 1;

local run;

local function Build()
	local version, build = GetBuildInfo();
	return (version or "?") .. "." .. (build or "?");
end

local function Round(value)
	return value and floor(value * 10000 + 0.5) / 10000 or nil;
end

local function BuildQueue()
	local queue = {};
	local vendors = {};
	for npcID, vendor in pairs(HSC.VendorList or {}) do
		if vendor.src then
			vendors[#vendors + 1] = npcID;
		end
	end
	table.sort(vendors);
	for _, npcID in ipairs(vendors) do
		queue[#queue + 1] = { vendor = npcID };
	end
	for _, decorID in ipairs(HSC.DecorList or {}) do
		queue[#queue + 1] = { decor = decorID };
	end
	return queue;
end

local function VendorName(entryID)
	local api = C_ContentTracking;
	if not (api and api.GetVendorTrackingInfo) then
		return nil;
	end
	local ok, info = pcall(api.GetVendorTrackingInfo, entryID);
	if ok and type(info) == "table" and type(info.creatureName) == "string" and info.creatureName ~= "" then
		return info.creatureName;
	end
	return nil;
end

local function VendorText(decorID)
	local display = Data.GetDisplay(CT.Decor, decorID);
	if not display.complete then
		return nil, false;
	end
	local lines = {};
	for _, source in ipairs(Data.ParseSources(display.sourceText)) do
		local name = source.vendor or ((source.kind == "vendor" or source.kind == "endeavor") and source.name);
		if name then
			lines[#lines + 1] = name .. "\t" .. table.concat(Data.GetZones(source), "\t");
		end
	end
	return #lines > 0 and table.concat(lines, "\n") or nil, true;
end

local function Tracking(decorID)
	local api = C_ContentTracking;
	local decorType = Enum.ContentTrackingType and Enum.ContentTrackingType.Decor;
	local results = Enum.ContentTrackingResult or {};
	local targets = Enum.ContentTrackingTargetType or {};
	if not (decorType and api and api.IsTrackable and api.GetBestMapForTrackable and api.GetNextWaypointForTrackable) then
		return nil;
	end
	if not api.IsTrackable(decorType, decorID) then
		return nil;
	end
	local ignoreWaypoint = true;
	local result, mapID = api.GetBestMapForTrackable(decorType, decorID, ignoreWaypoint);
	if result == results.DataPending then
		return "pending";
	end
	if not mapID then
		return nil;
	end
	local waypointResult, info = api.GetNextWaypointForTrackable(decorType, decorID, mapID);
	if waypointResult == results.DataPending then
		return "pending";
	end
	if type(info) ~= "table" or info.targetType ~= targets.Vendor then
		return nil;
	end
	return { t = info.targetID, m = mapID, x = Round(info.x), y = Round(info.y), n = VendorName(info.targetID) };
end

local function Ask(scan, item)
	if item.vendor then
		local vendor = HSC.VendorList[item.vendor];
		local name = vendor and VendorName(vendor.src);
		if name then
			scan.names[item.vendor] = name;
		end
		return false;
	end
	local text, known = VendorText(item.decor);
	if not known then
		return false;
	end
	local tracking = Tracking(item.decor);
	if tracking == "pending" then
		return true;
	end
	if text or tracking then
		local entry = tracking or {};
		entry.v = text;
		scan.decor[item.decor] = entry;
	end
	return false;
end

local function Finish(scan)
	run.ticker:Cancel();
	local forced = run.forced;
	run = nil;
	scan.done, scan.at = true, time();
	local names, decor = 0, 0;
	for _ in pairs(scan.names) do names = names + 1; end
	for _ in pairs(scan.decor) do decor = decor + 1; end
	if forced then
		HSC:Print(L["Finished reading the game's vendor data: %d vendor names, %d decor."]:format(names, decor));
	end
	HSC.Vendors:Invalidate();
	Data.ResetCaches();
	HSC:Fire("VENDORS_CHANGED");
end

local function Step()
	local scan = HSC.db and HSC.db.scan;
	if not (run and scan) or InCombatLockdown() then
		return;
	end
	local asked = 0;
	while asked < PER_STEP and scan.pos <= #run.queue do
		local item = run.queue[scan.pos];
		local ok, pending = pcall(Ask, scan, item);
		if not ok then
			geterrorhandler()(pending);
		elseif pending then
			run.retry[#run.retry + 1] = { item = item, tries = 1, at = GetTime() };
		end
		scan.pos = scan.pos + 1;
		asked = asked + 1;
	end
	while asked < PER_STEP and scan.pos > #run.queue and #run.retry > 0 and GetTime() - run.retry[1].at >= RETRY_SECONDS do
		local again = table.remove(run.retry, 1);
		local ok, pending = pcall(Ask, scan, again.item);
		if ok and pending and again.tries < RETRIES then
			again.tries, again.at = again.tries + 1, GetTime();
			run.retry[#run.retry + 1] = again;
		end
		asked = asked + 1;
	end
	if scan.pos > #run.queue and #run.retry == 0 then
		Finish(scan);
	end
end

function Scan:IsRunning()
	return run ~= nil;
end

function Scan:Start(force)
	local db = HSC.db;
	if not db then
		return;
	end
	if run then
		if force then
			HSC:Print(L["Already reading the game's vendor data (%d of %d)."]:format(db.scan.pos - 1, #run.queue));
		end
		return;
	end
	local scan = db.scan;
	if force or type(scan) ~= "table" or scan.build ~= Build() or scan.data ~= HSC.GameDataBuild or scan.locale ~= GetLocale() then
		scan = { build = Build(), data = HSC.GameDataBuild, locale = GetLocale(), pos = 1, names = {}, decor = {} };
		db.scan = scan;
	elseif scan.done then
		return;
	end
	run = { queue = BuildQueue(), retry = {}, forced = force };
	run.ticker = C_Timer.NewTicker(STEP_SECONDS, Step);
	if force then
		HSC:Print(L["Reading the game's vendor data in the background - about a minute."]);
	end
end

function Scan:GetState()
	local scan = HSC.db and HSC.db.scan;
	if run then
		return ("running, %d of %d"):format(scan.pos - 1, #run.queue);
	end
	if type(scan) == "table" and scan.done then
		return ("done for %s"):format(tostring(scan.build));
	end
	return "not run";
end

HSC:On("LOGIN", function()
	C_Timer.After(START_DELAY, function()
		if HSC.settings and HSC.settings.autoScan then
			Scan:Start(false);
		end
	end);
end);
