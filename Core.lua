local ADDON_NAME, HSC = ...
local L = HSC.L;

_G.HousingShoppingCart = HSC;

HSC.ADDON_NAME = ADDON_NAME;
HSC.VERSION = C_AddOns.GetAddOnMetadata(ADDON_NAME, "Version") or "dev";
HSC.TITLE = L["Housing Shopping Cart"];

HSC.Colors = {
	Title  = CreateColor(1.00, 0.87, 0.58),
	Brass  = CreateColor(0.91, 0.69, 0.30),
	Text   = CreateColor(0.95, 0.92, 0.84),
	Muted  = CreateColor(0.68, 0.64, 0.57),
	Faint  = CreateColor(0.46, 0.43, 0.39),
	Green  = CreateColor(0.45, 0.87, 0.40),
	Red    = CreateColor(1.00, 0.42, 0.36),
};

HSC.CHAT_PREFIX = "|cffe8b04d" .. L["Shopping Cart"] .. ":|r ";

function HSC.AtlasIcon(atlas, size)
	size = size or 14;
	return CreateAtlasMarkup(atlas, size, size);
end

function HSC:Print(...)
	print(self.CHAT_PREFIX .. strjoin(" ", tostringall(...)));
end

local listeners = {};

function HSC:On(message, callback)
	local list = listeners[message];
	if not list then
		list = {};
		listeners[message] = list;
	end
	list[#list + 1] = callback;
end

function HSC:Fire(message, ...)
	local list = listeners[message];
	if not list then
		return;
	end
	for i = 1, #list do
		local ok, err = pcall(list[i], ...);
		if not ok then
			geterrorhandler()(err);
		end
	end
end

local eventFrame = CreateFrame("Frame");
local eventHandlers = {};

function HSC:RegisterEvent(event, callback)
	local list = eventHandlers[event];
	if not list then
		if not pcall(eventFrame.RegisterEvent, eventFrame, event) then
			return false;
		end
		list = {};
		eventHandlers[event] = list;
	end
	list[#list + 1] = callback;
	return true;
end

eventFrame:SetScript("OnEvent", function(_, event, ...)
	local list = eventHandlers[event];
	if not list then
		return;
	end
	for i = 1, #list do
		local ok, err = pcall(list[i], event, ...);
		if not ok then
			geterrorhandler()(err);
		end
	end
end);

local debounceTimers = {};
function HSC:Debounce(key, delay, callback)
	local timer = debounceTimers[key];
	if timer then
		timer:Cancel();
	end
	debounceTimers[key] = C_Timer.NewTimer(delay, function()
		debounceTimers[key] = nil;
		callback();
	end);
end

local DEFAULTS = {
	dbVersion = 2,
	lines = {},
	blueprints = {},
	knownBlueprints = {},
	recentBlueprints = {},
	collapsed = {},
	window = {},
	browserWindow = {},
	learned = {
		vendors = {},
		items = {},
		endeavors = {},
		endeavorTitles = {},
	},
	settings = {
		groupBy = "type",
		hideCollected = false,
		openOnAdd = true,
		addSummary = true,
		autoAdd = false,
		toasts = true,
		sounds = true,
		blizzardTooltips = true,
		minimapButton = true,
		minimapAngle = 200,
		merchantPanel = true,
		mapPins = true,
		windowLocked = false,
		autoScan = true,
		browser = {
			owned = "all",
		},
	},
};

local function ApplyDefaults(target, defaults)
	for key, value in pairs(defaults) do
		if type(value) == "table" then
			if type(target[key]) ~= "table" then
				target[key] = {};
			end
			ApplyDefaults(target[key], value);
		elseif target[key] == nil then
			target[key] = value;
		end
	end
end

HSC:RegisterEvent("ADDON_LOADED", function(_, name)
	if name ~= ADDON_NAME then
		return;
	end
	if type(HousingShoppingCartDB) ~= "table" then
		HousingShoppingCartDB = {};
	end
	ApplyDefaults(HousingShoppingCartDB, DEFAULTS);
	HSC.db = HousingShoppingCartDB;
	HSC.settings = HSC.db.settings;
	HSC:Fire("DB_READY");
end);

HSC:RegisterEvent("PLAYER_LOGIN", function()
	HSC.loginTime = GetTime();
	HSC:Fire("LOGIN");
end);

function HSC:IsWarmingUp()
	return not self.loginTime or (GetTime() - self.loginTime) < 12;
end

function HSC:CanOpenPanel(panel, message)
	if InCombatLockdown() and not (panel and panel:IsShown()) then
		self:Print(message or L["That window can't be opened during combat."]);
		return false;
	end
	return true;
end

function HSC:PlaySound(soundKitName)
	if not (self.settings and self.settings.sounds) then
		return;
	end
	local kit = SOUNDKIT and SOUNDKIT[soundKitName];
	if kit then
		PlaySound(kit);
	end
end

StaticPopupDialogs["HOUSINGSHOPPINGCART_CLEAR_ALL"] = {
	text = L["Empty your whole Shopping Cart?|n|nThis removes every item and blueprint from it."],
	button1 = YES,
	button2 = NO,
	OnAccept = function()
		HSC.Cart:ClearAll();
	end,
	timeout = 0,
	whileDead = true,
	hideOnEscape = true,
	showAlert = true,
};

function HSC:ConfirmClearAll()
	StaticPopup_Show("HOUSINGSHOPPINGCART_CLEAR_ALL");
end

SLASH_HOUSINGSHOPPINGCART1 = "/hsc";
SLASH_HOUSINGSHOPPINGCART2 = "/shoppingcart";

local function AddByShareCode(text)
	if text == "" then
		HSC:ShowImportPanel();
		return;
	end
	local shareCode = HSC.Import.ParseInput(text);
	if not shareCode then
		HSC:Print(L["That isn't a share code. Paste the code exactly as it was shared."]);
		return;
	end
	local ok, reason = HSC.Import:Start(shareCode);
	if ok then
		HSC:Print(L["Looking up the blueprint..."]);
	else
		HSC:Print(reason);
	end
end

SlashCmdList.HOUSINGSHOPPINGCART = function(message)
	local word, rest = strtrim(message or ""):match("^(%S*)%s*(.-)$");
	local command = strlower(word or "");
	if command == "add" or command == "import" then
		AddByShareCode(rest or "");
	elseif command == "" or command == "show" or command == "toggle" then
		HSC:ToggleWindow();
	elseif command == "browse" or command == "decor" then
		HSC:ToggleBrowser();
	elseif command == "scan" then
		HSC.Scan:Start(true);
	elseif command == "clear" then
		HSC:ConfirmClearAll();
	elseif command == "undo" then
		HSC:Undo();
	elseif command == "reset" then
		HSC:ResetWindowPosition();
		HSC:Print(L["Window position reset."]);
	elseif command == "minimap" then
		HSC:SetMinimapButtonShown(not HSC.settings.minimapButton);
		HSC:Print(HSC.settings.minimapButton and L["Minimap button shown."] or L["Minimap button hidden."]);
	elseif command == "debug" then
		HSC:PrintDebug();
	else
		HSC:Print(L["Commands:"]);
		print("  |cffffd200/hsc|r - " .. L["open or close the Shopping Cart"]);
		print("  |cffffd200/hsc add|r " .. L["<share code>"] .. " - " .. L["add a blueprint's missing items, from anywhere"]);
		print("  |cffffd200/hsc browse|r - " .. L["browse every decor and add it to the cart"]);
		print("  |cffffd200/hsc scan|r - " .. L["read the game's vendor data again (runs by itself once per patch)"]);
		print("  |cffffd200/hsc minimap|r - " .. L["show or hide the minimap button"]);
		print("  |cffffd200/hsc clear|r - " .. L["empty the cart"]);
		print("  |cffffd200/hsc undo|r - " .. L["take back the last removal"]);
		print("  |cffffd200/hsc reset|r - " .. L["move the window back to the middle of the screen"]);
		print("  |cffffd200/hsc debug|r - " .. L["print diagnostics for bug reports"]);
	end
end

function HSC:PrintDebug()
	local stats = self.Cart:GetStats();
	local version, build = GetBuildInfo();
	self:Print(("v%s, game data %s, client %s.%s"):format(self.VERSION, tostring(self.GameDataBuild), tostring(version), tostring(build)));
	local learnedVendors, learnedItems, learnedEndeavors = self.Learn:GetCounts();
	print(("  learned in game: %d vendors, %d items, %d Endeavor vendors"):format(learnedVendors, learnedItems, learnedEndeavors));
	print(("  vendor data scan: %s"):format(self.Scan:GetState()));
	local activeID, activeTitle = self.Vendors:GetActiveEndeavor();
	if activeID or activeTitle then
		print(("  Endeavor running: %s (%s)"):format(tostring(activeTitle), tostring(activeID)));
	end
	print(("  lines: %d (%d collected), items: %d/%d, blueprints: %d"):format(
		stats.lines, stats.collectedLines, stats.got, stats.need, stats.blueprints));
	print(("  C_HousingBlueprint: %s, C_HousingCatalog: %s"):format(
		tostring(type(C_HousingBlueprint) == "table"), tostring(type(C_HousingCatalog) == "table")));
	local list = _G.HousingBlueprintContentListFrame;
	print(("  Blueprint List loaded: %s, shown: %s, button: %s"):format(
		tostring(list ~= nil), tostring(list ~= nil and list:IsShown()), tostring(self.addButton ~= nil)));
	if list and list.blueprintContentInfo then
		local info = list.blueprintContentInfo;
		print(("  showing %s, target house: %s"):format(tostring(info.shareCode), tostring(info.targetHouseGUID ~= nil)));
	end
	local houses = self.Import:GetHouses();
	local request = self.Import:GetPending();
	print(("  import: %s, houses: %s, blocked: %s"):format(request and ("waiting for " .. request.shareCode) or "idle",
		houses and #houses or "not loaded", tostring(self.Import:GetBlockedReason() or "no")));
end

function HousingShoppingCart_OnAddonCompartmentClick()
	HSC:ToggleWindow();
end

function HSC:AddSummaryToTooltip(tooltip)
	GameTooltip_SetTitle(tooltip, self.TITLE);
	local stats = self.Cart:GetStats();
	if stats.lines == 0 then
		GameTooltip_AddHighlightLine(tooltip, L["Your cart is empty."]);
	else
		GameTooltip_AddHighlightLine(tooltip, L["%d of %d items collected"]:format(stats.got, stats.need));
	end
end

function HousingShoppingCart_OnAddonCompartmentEnter(_, menuButtonFrame)
	local tooltip = GameTooltip;
	tooltip:SetOwner(menuButtonFrame, "ANCHOR_LEFT");
	HSC:AddSummaryToTooltip(tooltip);
	GameTooltip_AddInstructionLine(tooltip, L["Click to open the Shopping Cart"]);
	tooltip:Show();
end

function HousingShoppingCart_OnAddonCompartmentLeave()
	GameTooltip:Hide();
end

BINDING_HEADER_HOUSINGSHOPPINGCART = HSC.TITLE;
BINDING_NAME_HOUSINGSHOPPINGCART_TOGGLE = L["Open / close the Shopping Cart"];
