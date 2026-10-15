local _, HSC = ...
local L = HSC.L;
local Data = HSC.Data;
local Cart = HSC.Cart;
local Colors = HSC.Colors;

local PIN_TEMPLATE = "HSC_VendorPinTemplate";
local MAX_TOOLTIP_ITEMS = 12;

local provider;

local function ItemIcon(line)
	local display = Data.GetDisplay(line.contentType, line.recordID, line.name);
	if display.icon then
		return "|T" .. display.icon .. ":16:16|t";
	end
	return HSC.AtlasIcon(display.iconAtlas or "house-chest-icon", 16);
end

local function ShowTooltip(owner, pin)
	local entry, spot = pin.entry, pin.spot;
	local tooltip = GameTooltip;
	tooltip:SetOwner(owner, "ANCHOR_RIGHT");
	GameTooltip_SetTitle(tooltip, HSC.Map.GetVendorName(entry.npcID));
	local mapInfo = C_Map.GetMapInfo(spot.mapID);
	if mapInfo and mapInfo.name then
		GameTooltip_AddColoredLine(tooltip, mapInfo.name, Colors.Muted);
	end
	local endeavorNote, active = HSC.Map.GetEndeavorNote(entry.npcID);
	if endeavorNote then
		GameTooltip_AddColoredLine(tooltip, endeavorNote, Data.GetKindInfo("endeavor").color);
		if active then
			GameTooltip_AddColoredLine(tooltip, L["Active in your neighborhood right now"], Colors.Green);
		else
			GameTooltip_AddColoredLine(tooltip, L["Only here while this Endeavor is active"], Colors.Muted);
		end
	end

	GameTooltip_AddBlankLineToTooltip(tooltip);
	GameTooltip_AddColoredLine(tooltip, L["Sells for your cart:"], Colors.Title);
	local lines, names = {}, {};
	for _, line in ipairs(entry.lines) do
		lines[#lines + 1] = line;
		names[line] = Data.GetDisplay(line.contentType, line.recordID, line.name).name or "";
	end
	table.sort(lines, function(a, b)
		return strcmputf8i(names[a], names[b]) < 0;
	end);
	for index, line in ipairs(lines) do
		if index > MAX_TOOLTIP_ITEMS then
			GameTooltip_AddColoredLine(tooltip, L["...and %d more"]:format(#lines - MAX_TOOLTIP_ITEMS), Colors.Muted);
			break;
		end
		local _, _, left = Cart:GetProgress(line);
		local display = Data.GetDisplay(line.contentType, line.recordID, line.name);
		GameTooltip_AddColoredDoubleLine(tooltip, ItemIcon(line) .. " " .. names[line], "×" .. left,
			Data.GetQualityColor(display.quality), Colors.Title, false);
	end

	GameTooltip_AddBlankLineToTooltip(tooltip);
	GameTooltip_AddInstructionLine(tooltip, L["<Click to set a waypoint>"]);
	tooltip:Show();
end

HSC_VendorPinMixin = {};

function HSC_VendorPinMixin:OnLoad()
	self:UseFrameLevelType("PIN_FRAME_LEVEL_AREA_POI");
	self:SetScalingLimits(1, 1.0, 1.25);
end

function HSC_VendorPinMixin:OnAcquired(pin)
	self.pin = pin;
	self.Count:SetText(pin.entry.left > 1 and pin.entry.left or "");
	self.Hover:Hide();
	self:SetPosition(pin.x, pin.y);
end

function HSC_VendorPinMixin:CheckMouseButtonPassthrough(...)
	if InCombatLockdown() or not MapCanvasPinMixin.CheckMouseButtonPassthrough then
		return;
	end
	MapCanvasPinMixin.CheckMouseButtonPassthrough(self, ...);
end

function HSC_VendorPinMixin:OnMouseEnter()
	self.Hover:Show();
	if self.pin then
		ShowTooltip(self, self.pin);
	end
end

function HSC_VendorPinMixin:OnMouseLeave()
	self.Hover:Hide();
	GameTooltip_Hide();
end

function HSC_VendorPinMixin:OnMouseClickAction(button)
	if button == "LeftButton" and self.pin then
		local keepMap = true;
		HSC.Map.ShowVendor(self.pin.spot, keepMap);
	end
end

local function IsEnabled()
	return HSC.settings and HSC.settings.mapPins;
end

local function CreateProvider()
	local dataProvider = CreateFromMixins(MapCanvasDataProviderMixin);

	function dataProvider:RemoveAllData()
		self:GetMap():RemoveAllPinsByTemplate(PIN_TEMPLATE);
	end

	function dataProvider:RefreshAllData()
		self:RemoveAllData();
		if not IsEnabled() then
			return;
		end
		local map = self:GetMap();
		for _, pin in ipairs(HSC.Map.GetPinsForMap(map:GetMapID())) do
			map:AcquirePin(PIN_TEMPLATE, pin);
		end
	end

	return dataProvider;
end

local function Refresh()
	if provider and provider:GetMap() then
		provider:RefreshAllData();
	end
end

function HSC:SetMapPinsShown(shown)
	self.settings.mapPins = shown and true or false;
	Refresh();
end

HSC:On("MAP_VENDORS_CHANGED", function()
	if provider and WorldMapFrame:IsShown() then
		HSC:Debounce("mapPins", 0.2, Refresh);
	end
end);

EventUtil.ContinueOnAddOnLoaded("Blizzard_WorldMap", function()
	if not (WorldMapFrame and WorldMapFrame.AddDataProvider and MapCanvasDataProviderMixin and MapCanvasPinMixin) then
		return;
	end
	for key, value in pairs(MapCanvasPinMixin) do
		if HSC_VendorPinMixin[key] == nil then
			HSC_VendorPinMixin[key] = value;
		end
	end
	provider = CreateProvider();
	WorldMapFrame:AddDataProvider(provider);

	if Menu and Menu.ModifyMenu then
		Menu.ModifyMenu("MENU_WORLD_MAP_TRACKING", function(_, rootDescription)
			rootDescription:CreateDivider();
			rootDescription:CreateCheckbox(L["Shopping Cart vendors"], IsEnabled, function()
				HSC:SetMapPinsShown(not IsEnabled());
			end);
		end);
	end
end);
