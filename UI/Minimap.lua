local _, HSC = ...
local L = HSC.L;

local MinimapButton = {};
HSC.MinimapButton = MinimapButton;

local BUTTON_NAME = "HousingShoppingCartMinimapButton";
local DEFAULT_ANGLE = 200;
local RIM_OFFSET = 5;

local button;

local ROUNDED_QUADRANTS = {
	["ROUND"]                 = { true,  true,  true,  true  },
	["SQUARE"]                = { false, false, false, false },
	["CORNER-TOPLEFT"]        = { false, false, false, true  },
	["CORNER-TOPRIGHT"]       = { false, false, true,  false },
	["CORNER-BOTTOMLEFT"]     = { false, true,  false, false },
	["CORNER-BOTTOMRIGHT"]    = { true,  false, false, false },
	["SIDE-LEFT"]             = { false, true,  false, true  },
	["SIDE-RIGHT"]            = { true,  false, true,  false },
	["SIDE-TOP"]              = { false, false, true,  true  },
	["SIDE-BOTTOM"]           = { true,  true,  false, false },
	["TRICORNER-TOPLEFT"]     = { false, true,  true,  true  },
	["TRICORNER-TOPRIGHT"]    = { true,  false, true,  true  },
	["TRICORNER-BOTTOMLEFT"]  = { true,  true,  false, true  },
	["TRICORNER-BOTTOMRIGHT"] = { true,  true,  true,  false },
};

local function GetShapeQuadrants()
	local getShape = _G.GetMinimapShape;
	local ok, shape = false, nil;
	if type(getShape) == "function" then
		ok, shape = pcall(getShape);
	end
	return (ok and ROUNDED_QUADRANTS[shape]) or ROUNDED_QUADRANTS.ROUND;
end

local function UpdatePosition()
	local angle = math.rad(HSC.settings.minimapAngle or DEFAULT_ANGLE);
	local x, y = math.cos(angle), math.sin(angle);
	local quadrant = 1 + (x < 0 and 1 or 0) + (y > 0 and 2 or 0);
	if not GetShapeQuadrants()[quadrant] then
		local stretch = 1 / math.max(math.abs(x), math.abs(y));
		x, y = x * stretch, y * stretch;
	end
	local halfWidth = Minimap:GetWidth() / 2 + RIM_OFFSET;
	local halfHeight = Minimap:GetHeight() / 2 + RIM_OFFSET;
	button:ClearAllPoints();
	button:SetPoint("CENTER", Minimap, "CENTER", x * halfWidth, y * halfHeight);
end

local function FollowCursor()
	local centerX, centerY = Minimap:GetCenter();
	if not (centerX and centerY) then
		return;
	end
	local scale = Minimap:GetEffectiveScale();
	local cursorX, cursorY = GetCursorPosition();
	local angle = math.deg(math.atan2(cursorY / scale - centerY, cursorX / scale - centerX));
	HSC.settings.minimapAngle = floor(angle % 360 + 0.5);
	UpdatePosition();
end

local function ShowTooltip(self)
	GameTooltip:SetOwner(self, "ANCHOR_LEFT");
	HSC:AddSummaryToTooltip(GameTooltip);
	GameTooltip_AddInstructionLine(GameTooltip, L["Click to open the Shopping Cart"]);
	GameTooltip_AddInstructionLine(GameTooltip, L["Drag to move this button"]);
	GameTooltip_AddInstructionLine(GameTooltip, L["<Right-click for options>"]);
	GameTooltip:Show();
end

local function OpenMenu(owner)
	MenuUtil.CreateContextMenu(owner, function(_, rootDescription)
		rootDescription:SetTag("MENU_HOUSINGSHOPPINGCART_MINIMAP");
		rootDescription:CreateTitle(HSC.TITLE);
		rootDescription:CreateButton(L["Open the Shopping Cart"], function()
			HSC:ShowWindow();
		end);
		rootDescription:CreateButton(L["Add a blueprint by share code..."], function()
			HSC:ShowImportPanel();
		end);
		rootDescription:CreateButton(L["Browse decor..."], function()
			HSC:ShowBrowser();
		end);
		rootDescription:CreateButton(L["Hide minimap button"], function()
			HSC:SetMinimapButtonShown(false);
			HSC:Print(L["Minimap button hidden. Type |cffffd200/hsc minimap|r to bring it back."]);
		end);
	end);
end

local function Create()
	button = CreateFrame("Button", BUTTON_NAME, Minimap);
	button:SetSize(31, 31);
	button:SetFrameStrata("MEDIUM");
	button:SetFrameLevel(8);
	button:RegisterForClicks("LeftButtonUp", "RightButtonUp");
	button:RegisterForDrag("LeftButton");
	button:SetHighlightTexture(136477);

	local background = button:CreateTexture(nil, "BACKGROUND");
	background:SetTexture(136467);
	background:SetSize(24, 24);
	background:SetPoint("CENTER");

	local icon = button:CreateTexture(nil, "ARTWORK");
	icon:SetAtlas("Perks-ShoppingCart");
	icon:SetSize(20, 20);
	icon:SetPoint("CENTER");
	button.Icon = icon;

	local border = button:CreateTexture(nil, "OVERLAY");
	border:SetTexture(136430);
	border:SetSize(50, 50);
	border:SetPoint("TOPLEFT");

	button:SetScript("OnClick", function(self, mouseButton)
		if mouseButton == "RightButton" then
			GameTooltip:Hide();
			OpenMenu(self);
		else
			HSC:ToggleWindow();
		end
	end);
	button:SetScript("OnMouseDown", function()
		icon:SetPoint("CENTER", 1, -1);
	end);
	button:SetScript("OnMouseUp", function()
		icon:SetPoint("CENTER");
	end);
	button:SetScript("OnDragStart", function(self)
		GameTooltip:Hide();
		self:SetScript("OnUpdate", FollowCursor);
	end);
	button:SetScript("OnDragStop", function(self)
		self:SetScript("OnUpdate", nil);
		icon:SetPoint("CENTER");
	end);
	button:SetScript("OnEnter", ShowTooltip);
	button:SetScript("OnLeave", GameTooltip_Hide);
end

function MinimapButton:Update()
	if not (HSC.settings and Minimap) then
		return;
	end
	if not HSC.settings.minimapButton then
		if button then
			button:Hide();
		end
		return;
	end
	if not button then
		Create();
	end
	UpdatePosition();
	button:Show();
end

function HSC:SetMinimapButtonShown(shown)
	self.settings.minimapButton = shown and true or false;
	MinimapButton:Update();
end

HSC:On("LOGIN", function()
	MinimapButton:Update();
end);
