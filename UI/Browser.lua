local _, HSC = ...
local L = HSC.L;
local Data = HSC.Data;
local Cart = HSC.Cart;
local CT = Data.CT;
local Colors = HSC.Colors;

local Browser = {};
HSC.Browser = Browser;

local FRAME_NAME = "HousingShoppingCartBrowserFrame";
local DEFAULT_WIDTH, DEFAULT_HEIGHT = 460, 620;
local MIN_WIDTH, MIN_HEIGHT = 400, 420;
local MAX_WIDTH, MAX_HEIGHT = 800, 1100;
local ROW_HEIGHT = 44;
local HEADER_HEIGHT = 28;
local INDEX_PER_STEP = 150;
local CATALOG_DECOR = (Enum and Enum.HousingCatalogEntryType and Enum.HousingCatalogEntryType.Decor) or 1;

local KIND_FILTERS = { "vendor", "endeavor", "quest", "achievement", "profession", "drop", "treasure", "event", "market", "other" };
local LISTED_KINDS = {};
for _, kind in ipairs(KIND_FILTERS) do
	LISTED_KINDS[kind] = true;
end

local frame;
local entries;
local building;
local extraIDs = {};
local searcher;
local categoryNames = {};
local subcategoryNames = {};
local patchOf;

local function Settings()
	return HSC.settings.browser;
end

local function CategoryName(categoryID)
	if categoryNames[categoryID] == nil then
		local ok, info = pcall(C_HousingCatalog.GetCatalogCategoryInfo, categoryID);
		categoryNames[categoryID] = ok and type(info) == "table" and info.name and info.name ~= "" and { name = info.name, order = info.orderIndex or 0 } or false;
	end
	return categoryNames[categoryID] or nil;
end

local function SubcategoryName(subcategoryID)
	if subcategoryNames[subcategoryID] == nil then
		local name;
		if C_HousingCatalog.GetCatalogSubcategoryInfo then
			local ok, info = pcall(C_HousingCatalog.GetCatalogSubcategoryInfo, subcategoryID);
			name = ok and type(info) == "table" and info.name;
		end
		if not name and C_HousingCatalog.GetCatalogCategoryAndSubcategoryNames then
			local ok, _, subcategory = pcall(C_HousingCatalog.GetCatalogCategoryAndSubcategoryNames, subcategoryID);
			name = ok and subcategory;
		end
		subcategoryNames[subcategoryID] = type(name) == "string" and name ~= "" and name or false;
	end
	return subcategoryNames[subcategoryID] or nil;
end

local function PatchOf(recordID)
	if not patchOf then
		patchOf = {};
		for patch, ids in pairs(HSC.DecorPatches or {}) do
			for _, id in ipairs(ids) do
				patchOf[id] = patch;
			end
		end
	end
	return patchOf[recordID];
end

local function SearchWords(recordID, display)
	local words = {};
	local tagText = HSC.DecorTagText or {};
	for _, tag in ipairs(HSC.DecorTags and HSC.DecorTags[recordID] or {}) do
		words[#words + 1] = tagText[tag];
	end
	if type(display.dataTagsByID) == "table" then
		for _, text in pairs(display.dataTagsByID) do
			if type(text) == "string" then
				words[#words + 1] = text;
			end
		end
	end
	for _, id in ipairs(display.categoryIDs or {}) do
		local category = CategoryName(id);
		words[#words + 1] = category and category.name;
	end
	for _, id in ipairs(display.subcategoryIDs or {}) do
		words[#words + 1] = SubcategoryName(id);
	end
	local text = strlower(table.concat(words, " ")):gsub("[%(%)/,]", " ");
	return " " .. text .. " ";
end

local function KnownIDs()
	local ids, seen = {}, {};
	for _, id in ipairs(HSC.DecorList or {}) do
		if not seen[id] then
			seen[id] = true;
			ids[#ids + 1] = id;
		end
	end
	for id in pairs(extraIDs) do
		if not seen[id] then
			seen[id] = true;
			ids[#ids + 1] = id;
		end
	end
	return ids, seen;
end

local function FinishBuild()
	local list = building.list;
	building.ticker:Cancel();
	building = nil;
	table.sort(list, function(a, b)
		return strcmputf8i(a.lowerName, b.lowerName) < 0;
	end);
	entries = list;
	Browser.stale = HSC:IsWarmingUp();
	Browser:Refresh(true);
end

local function BuildStep()
	local stop = math.min(building.pos + INDEX_PER_STEP - 1, #building.ids);
	for index = building.pos, stop do
		local recordID = building.ids[index];
		local display = Data.GetDisplay(CT.Decor, recordID);
		if display.complete then
			local subcategories = {};
			for _, id in ipairs(display.subcategoryIDs or {}) do
				subcategories[id] = true;
			end
			building.list[#building.list + 1] = {
				line = { contentType = CT.Decor, recordID = recordID, name = display.name },
				lowerName = strlower(display.name or ""),
				categoryID = display.categoryIDs and display.categoryIDs[1],
				words = SearchWords(recordID, display),
				patch = PatchOf(recordID),
				subcategories = subcategories,
			};
		end
	end
	building.pos = stop + 1;
	if building.pos > #building.ids then
		FinishBuild();
	elseif frame and frame:IsShown() then
		frame.Loading:SetText(L["Reading the catalog... %d%%"]:format(math.floor(100 * building.pos / #building.ids)));
	end
end

function Browser:BuildIndex()
	if building then
		return;
	end
	building = { ids = KnownIDs(), pos = 1, list = {} };
	building.ticker = C_Timer.NewTicker(0.01, BuildStep);
end

local function SearchCatalog()
	if searcher ~= nil or not (C_HousingCatalog and C_HousingCatalog.CreateCatalogSearcher) then
		return;
	end
	local ok, created = pcall(C_HousingCatalog.CreateCatalogSearcher);
	if not (ok and created) then
		searcher = false;
		return;
	end
	searcher = created;
	local started = pcall(function()
		searcher:SetResultsUpdatedCallback(function()
			if searcher:IsSearchInProgress() then
				return;
			end
			local _, known = KnownIDs();
			local okResults, results = pcall(searcher.GetCatalogSearchResults, searcher);
			local added = 0;
			for _, entryID in ipairs(okResults and results or {}) do
				if entryID.entryType == CATALOG_DECOR and entryID.recordID and not known[entryID.recordID] then
					extraIDs[entryID.recordID] = true;
					known[entryID.recordID] = true;
					added = added + 1;
					if building then
						building.ids[#building.ids + 1] = entryID.recordID;
					end
				end
			end
			if added > 0 and entries then
				entries = nil;
				if frame and frame:IsShown() then
					Browser:BuildIndex();
				end
			end
		end);
		searcher:SetAutoUpdateOnParamChanges(false);
		searcher:SetStoredOnly(false);
		searcher:SetBaseVariantOnly(true);
		searcher:RunSearch();
	end);
	if not started then
		searcher = false;
	end
end

function Browser:GetEntryCount()
	return entries and #entries or 0;
end

local function HasKind(line, kind)
	local sources = Data.GetSources(line);
	if kind == "other" and #sources == 0 then
		return true;
	end
	for _, source in ipairs(sources) do
		if source.kind == kind or (kind == "other" and not LISTED_KINDS[source.kind]) then
			return true;
		end
	end
	return false;
end

local function ParseQuery(text)
	local query = { words = {}, patches = {} };
	for word in strlower(text or ""):gmatch("%S+") do
		if word:find("^%d+%.[%d%.]*%d$") then
			query.patches[#query.patches + 1] = word;
		else
			query.words[#query.words + 1] = word;
		end
	end
	return query;
end

local function InPatch(entry, patch)
	local added = entry.patch;
	return added ~= nil and (added == patch or added:sub(1, #patch + 1) == patch .. ".");
end

local function MatchesWord(entry, word)
	if entry.lowerName:find(word, 1, true) or entry.words:find(" " .. word, 1, true) then
		return true;
	end
	for _, source in ipairs(Data.GetSources(entry.line)) do
		if Data.SourceMentions(source, word) then
			return true;
		end
	end
	return false;
end

local function MatchesWords(entry, words)
	for _, word in ipairs(words) do
		if not MatchesWord(entry, word) then
			return false;
		end
	end
	return true;
end

local function PassesFilters(entry, query, settings)
	if settings.category and entry.categoryID ~= settings.category then
		return false;
	end
	for _, patch in ipairs(query.patches) do
		if not InPatch(entry, patch) then
			return false;
		end
	end
	if settings.owned ~= "all" then
		local owned = (Data.GetOwned(CT.Decor, entry.line.recordID) or 0) > 0;
		if (settings.owned == "missing" and owned) or (settings.owned == "owned" and not owned) then
			return false;
		end
	end
	if settings.kind and not HasKind(entry.line, settings.kind) then
		return false;
	end
	return true;
end

local function MainSubcategory(matched)
	local counts = {};
	for _, entry in ipairs(matched) do
		for id in pairs(entry.subcategories) do
			counts[id] = (counts[id] or 0) + 1;
		end
	end
	local best, bestCount;
	for id, count in pairs(counts) do
		if not bestCount or count > bestCount or (count == bestCount and id < best) then
			best, bestCount = id, count;
		end
	end
	if best and bestCount >= 2 and 2 * bestCount >= #matched and SubcategoryName(best) then
		return best;
	end
	return nil;
end

function Browser:BuildDataProvider()
	local provider = CreateDataProvider();
	local query = ParseQuery(self.searchText);
	local settings = Settings();
	local matched, rest = {}, {};
	for _, entry in ipairs(entries or {}) do
		if PassesFilters(entry, query, settings) then
			if MatchesWords(entry, query.words) then
				matched[#matched + 1] = entry;
				provider:Insert({ line = entry.line, odd = (#matched % 2 == 0) });
			else
				rest[#rest + 1] = entry;
			end
		end
	end
	local similar = {};
	local subcategoryID = #query.words == 1 and MainSubcategory(matched);
	if subcategoryID then
		for _, entry in ipairs(rest) do
			if entry.subcategories[subcategoryID] then
				similar[#similar + 1] = entry;
			end
		end
	end
	if #similar > 0 then
		provider:Insert({ header = true, label = L["Similar: %s"]:format(SubcategoryName(subcategoryID)), count = #similar });
		for index, entry in ipairs(similar) do
			provider:Insert({ line = entry.line, odd = (index % 2 == 0) });
		end
	end
	return provider, #matched, #similar;
end

local function SavePosition()
	local db = HSC.db.browserWindow;
	local left, top = frame:GetLeft(), frame:GetTop();
	if left and top then
		db.left, db.top = left, top;
		frame:ClearAllPoints();
		frame:SetPoint("TOPLEFT", frame:GetParent(), "BOTTOMLEFT", left, top);
	end
	db.width, db.height = frame:GetSize();
end

local function RestorePosition()
	local db = HSC.db.browserWindow;
	frame:ClearAllPoints();
	if db.left and db.top then
		frame:SetPoint("TOPLEFT", frame:GetParent(), "BOTTOMLEFT", db.left, db.top);
	elseif HSC.Window:IsShown() then
		local cart = _G.HousingShoppingCartFrame;
		local parentWidth = frame:GetParent():GetWidth();
		if cart:GetRight() and cart:GetRight() + 12 + frame:GetWidth() <= parentWidth then
			frame:SetPoint("TOPLEFT", cart, "TOPRIGHT", 12, 0);
		else
			frame:SetPoint("TOPRIGHT", cart, "TOPLEFT", -12, 0);
		end
	else
		frame:SetPoint("CENTER", frame:GetParent(), "CENTER", 0, 20);
	end
end

local function SetupFilterMenu(dropdown)
	dropdown:SetupMenu(function(_, rootDescription)
		rootDescription:SetTag("MENU_HOUSINGSHOPPINGCART_BROWSER_FILTER");
		local settings = Settings();
		local function Pick(key, value)
			return function()
				settings[key] = value;
				Browser:Refresh(true);
			end;
		end
		rootDescription:CreateTitle(L["Show"]);
		for _, option in ipairs({ { "all", L["All decor"] }, { "missing", L["Not owned yet"] }, { "owned", L["Owned"] } }) do
			rootDescription:CreateRadio(option[2], function() return settings.owned == option[1]; end, Pick("owned", option[1]));
		end
		rootDescription:CreateDivider();
		rootDescription:CreateTitle(L["Where it comes from"]);
		rootDescription:CreateRadio(L["Anywhere"], function() return settings.kind == nil; end, Pick("kind", nil));
		for _, kind in ipairs(KIND_FILTERS) do
			rootDescription:CreateRadio(Data.GetKindInfo(kind).label, function() return settings.kind == kind; end, Pick("kind", kind));
		end
	end);
end

local function SetupCategoryMenu(dropdown)
	dropdown:SetupMenu(function(_, rootDescription)
		rootDescription:SetTag("MENU_HOUSINGSHOPPINGCART_BROWSER_CATEGORY");
		local settings = Settings();
		rootDescription:CreateRadio(L["All categories"], function() return settings.category == nil; end, function()
			settings.category = nil;
			Browser:Refresh(true);
		end);
		local seen, categories = {}, {};
		for _, entry in ipairs(entries or {}) do
			local id = entry.categoryID;
			if id and not seen[id] and CategoryName(id) then
				seen[id] = true;
				categories[#categories + 1] = id;
			end
		end
		table.sort(categories, function(a, b)
			return CategoryName(a).order < CategoryName(b).order;
		end);
		for _, id in ipairs(categories) do
			rootDescription:CreateRadio(CategoryName(id).name, function() return settings.category == id; end, function()
				settings.category = id;
				Browser:Refresh(true);
			end);
		end
	end);
end

local function Create()
	local db = HSC.db.browserWindow;
	frame = CreateFrame("Frame", FRAME_NAME, GetAppropriateTopLevelParent());
	frame:Hide();
	frame:SetSize(db.width or DEFAULT_WIDTH, db.height or DEFAULT_HEIGHT);
	frame:SetFrameStrata("HIGH");
	frame:SetToplevel(true);
	frame:SetClampedToScreen(true);
	frame:SetClampRectInsets(-10, 10, 10, -10);
	frame:SetMovable(true);
	frame:SetResizable(true);
	frame:SetResizeBounds(MIN_WIDTH, MIN_HEIGHT, MAX_WIDTH, MAX_HEIGHT);
	frame:EnableMouse(true);
	tinsert(UISpecialFrames, FRAME_NAME);
	FrameUtil.RegisterForTopLevelParentChanged(frame);

	HSC.Window.CreatePanelArt(frame, L["Decor Browser"], "house-chest-icon");
	frame.DragArea:SetScript("OnDragStart", function() frame:StartMoving(); end);
	frame.DragArea:SetScript("OnDragStop", function()
		frame:StopMovingOrSizing();
		SavePosition();
	end);

	local summary = frame:CreateFontString(nil, "ARTWORK", "GameFontHighlight");
	summary:SetPoint("TOPLEFT", 22, -50);
	summary:SetJustifyH("LEFT");
	summary:SetTextColor(Colors.Muted:GetRGB());
	frame.Summary = summary;

	local category = CreateFrame("DropdownButton", nil, frame, "WowStyle1DropdownTemplate");
	category:SetWidth(150);
	category:SetPoint("TOPRIGHT", -20, -44);
	SetupCategoryMenu(category);
	frame.CategoryDropdown = category;
	summary:SetPoint("RIGHT", category, "LEFT", -10, 0);

	local filter = CreateFrame("DropdownButton", nil, frame, "WowStyle1DropdownTemplate");
	filter:SetWidth(120);
	filter:SetPoint("TOPRIGHT", -20, -78);
	filter:SetDefaultText(L["Filter"]);
	SetupFilterMenu(filter);
	frame.FilterDropdown = filter;

	local search = CreateFrame("EditBox", nil, frame, "SearchBoxTemplate");
	search:SetHeight(20);
	search:SetPoint("LEFT", frame, "TOPLEFT", 26, -90);
	search:SetPoint("RIGHT", filter, "LEFT", -12, 0);
	if search.Instructions then
		search.Instructions:SetText(L["Name, tag, vendor or patch (12.1.5)"]);
	end
	search:HookScript("OnTextChanged", function(editBox)
		Browser.searchText = editBox:GetText();
		HSC:Debounce("browserSearch", 0.2, function()
			Browser:Refresh(true);
		end);
	end);
	frame.SearchBox = search;

	local inset = CreateFrame("Frame", nil, frame);
	inset:SetPoint("TOPLEFT", 14, -110);
	inset:SetPoint("BOTTOMRIGHT", -14, 42);
	local insetBackground = inset:CreateTexture(nil, "BACKGROUND");
	insetBackground:SetAtlas("housing-basic-panel-innerblackbox");
	insetBackground:SetAllPoints();
	insetBackground:SetAlpha(0.6);
	frame.Inset = inset;

	local scrollBox = CreateFrame("Frame", nil, inset, "WowScrollBoxList");
	scrollBox:SetPoint("TOPLEFT", 6, -6);
	scrollBox:SetPoint("BOTTOMRIGHT", -22, 6);
	frame.ScrollBox = scrollBox;
	local scrollBar = CreateFrame("EventFrame", nil, inset, "MinimalScrollBar");
	scrollBar:SetPoint("TOPLEFT", scrollBox, "TOPRIGHT", 7, 0);
	scrollBar:SetPoint("BOTTOMLEFT", scrollBox, "BOTTOMRIGHT", 7, 0);
	local view = CreateScrollBoxListLinearView(2, 4, 0, 0, 2);
	view:SetElementFactory(function(factory, elementData)
		factory(elementData.header and "HSC_BrowserHeaderTemplate" or "HSC_BrowserRowTemplate", function(row, data)
			row:Init(data);
		end);
	end);
	view:SetElementExtentCalculator(function(_, elementData)
		return elementData.header and HEADER_HEIGHT or ROW_HEIGHT;
	end);
	ScrollUtil.InitScrollBoxListWithScrollBar(scrollBox, scrollBar, view);

	local loading = inset:CreateFontString(nil, "ARTWORK", "GameFontNormalLarge");
	loading:SetPoint("CENTER");
	loading:SetWidth(300);
	loading:SetTextColor(Colors.Title:GetRGB());
	frame.Loading = loading;

	local cartButton = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate");
	cartButton:SetSize(150, 22);
	cartButton:SetPoint("BOTTOMRIGHT", -26, 12);
	cartButton:SetText(L["Shopping Cart"]);
	cartButton:SetScript("OnClick", function()
		HSC:ShowWindow();
	end);
	local hint = frame:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall");
	hint:SetPoint("LEFT", frame, "BOTTOMLEFT", 20, 23);
	hint:SetPoint("RIGHT", cartButton, "LEFT", -10, 0);
	hint:SetJustifyH("LEFT");
	hint:SetWordWrap(false);
	hint:SetTextColor(Colors.Muted:GetRGB());
	hint:SetText(HSC.AtlasIcon("Perks-ShoppingCart", 14) .. " " .. L["adds one to your cart"]);

	local grip = CreateFrame("Button", nil, frame);
	grip:SetSize(16, 16);
	grip:SetPoint("BOTTOMRIGHT", -4, 4);
	grip:SetNormalTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Up");
	grip:SetHighlightTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Highlight");
	grip:SetPushedTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Down");
	grip:SetScript("OnMouseDown", function() frame:StartSizing("BOTTOMRIGHT"); end);
	grip:SetScript("OnMouseUp", function()
		frame:StopMovingOrSizing();
		SavePosition();
	end);
end

function Browser:Refresh(toTop)
	if not (frame and frame:IsShown()) then
		return;
	end
	if not entries then
		frame.ScrollBox:SetDataProvider(CreateDataProvider());
		frame.Loading:SetText(L["Reading the catalog..."]);
		frame.Loading:Show();
		frame.Summary:SetText("");
		return;
	end
	local provider, shown, similar = self:BuildDataProvider();
	frame.ScrollBox:SetDataProvider(provider, toTop and ScrollBoxConstants.DiscardScrollPosition or ScrollBoxConstants.RetainScrollPosition);
	local summary = shown == #entries and L["%d decor"]:format(#entries) or L["%d of %d decor"]:format(shown, #entries);
	if similar > 0 then
		summary = summary .. " " .. L["(+%d similar)"]:format(similar);
	end
	frame.Summary:SetText(summary);
	if #entries == 0 then
		frame.Loading:SetText(L["The game hasn't sent its catalog yet - try again in a moment."]);
		frame.Loading:Show();
	elseif shown == 0 then
		frame.Loading:SetText(L["Nothing matches your search or filters."]);
		frame.Loading:Show();
	else
		frame.Loading:Hide();
	end
	local settings = Settings();
	frame.CategoryDropdown:OverrideText(settings.category and CategoryName(settings.category) and CategoryName(settings.category).name or L["All categories"]);
	local active = (settings.owned ~= "all" and 1 or 0) + (settings.kind and 1 or 0);
	frame.FilterDropdown:OverrideText(active > 0 and L["Filter (%d)"]:format(active) or L["Filter"]);
end

function Browser:IsShown()
	return frame ~= nil and frame:IsShown();
end

function Browser:Show()
	if not HSC.db then
		return;
	end
	if not frame then
		Create();
	end
	if frame:GetParent() ~= GetAppropriateTopLevelParent() then
		FrameUtil.UpdateTopLevelParent(frame);
	end
	if frame:IsShown() then
		frame:Raise();
		return;
	end
	if self.stale and not HSC:IsWarmingUp() then
		entries, self.stale = nil, false;
	end
	RestorePosition();
	HSC:PlaySound("HOUSING_BLUEPRINTS_IMPORT_OPEN");
	frame:Show();
	if not entries then
		self:BuildIndex();
	end
	SearchCatalog();
	self:Refresh(true);
end

function Browser:Hide()
	if frame and frame:IsShown() then
		HSC:PlaySound("HOUSING_BLUEPRINTS_CONTENTLIST_CLOSE");
		frame:Hide();
	end
end

function HSC:ToggleBrowser()
	if Browser:IsShown() then
		Browser:Hide();
	else
		Browser:Show();
	end
end

function HSC:ShowBrowser()
	Browser:Show();
end

local function RefreshSoon()
	if Browser:IsShown() then
		HSC:Debounce("browserRefresh", 0.3, function()
			Browser:Refresh(false);
		end);
	end
end
HSC:On("CART_CHANGED", RefreshSoon);
HSC:On("CART_REFRESH", RefreshSoon);
