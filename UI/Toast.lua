local _, HSC = ...
local L = HSC.L;
local Data = HSC.Data;
local Cart = HSC.Cart;
local Colors = HSC.Colors;

local Toast = {};
HSC.Toast = Toast;

local MAX_QUEUE = 4;
local HOLD_SECONDS = 3.5;

local toast;
local queue = {};

local function CreateTexture(parent, layer, atlas, subLevel)
	local texture = parent:CreateTexture(nil, layer, nil, subLevel or 0);
	texture:SetAtlas(atlas, true);
	return texture;
end

local function AddAlpha(group, region, fromAlpha, toAlpha, duration, startDelay, order)
	local animation = group:CreateAnimation("Alpha");
	animation:SetTarget(region);
	animation:SetFromAlpha(fromAlpha);
	animation:SetToAlpha(toAlpha);
	animation:SetDuration(duration);
	animation:SetStartDelay(startDelay or 0);
	animation:SetOrder(order or 1);
	return animation;
end

local function CreateToast()
	local frame = CreateFrame("Button", "HousingShoppingCartToast", GetAppropriateTopLevelParent());
	frame:SetSize(304, 105);
	frame:SetFrameStrata("DIALOG");
	frame:SetPoint("TOP", 0, -92);
	frame:RegisterForClicks("LeftButtonUp", "RightButtonUp");
	frame:Hide();
	FrameUtil.RegisterForTopLevelParentChanged(frame);

	frame.Background = CreateTexture(frame, "BACKGROUND", "housing-item-toast-background");
	frame.Background:SetPoint("BOTTOM", 0, 10);

	frame.LightRays = CreateTexture(frame, "BACKGROUND", "housing-item-toast-lightrays01", 1);
	frame.LightRays:SetBlendMode("ADD");
	frame.LightRays:SetPoint("CENTER", frame.Background);
	frame.LightRays2 = CreateTexture(frame, "BACKGROUND", "housing-item-toast-lightrays02", 1);
	frame.LightRays2:SetBlendMode("ADD");
	frame.LightRays2:SetPoint("CENTER", frame.LightRays);

	frame.Border = CreateTexture(frame, "BORDER", "housing-item-toast-frame");
	frame.Border:SetPoint("CENTER", frame.Background);
	local leaves = {
		{ "housing-item-toast-leaf01", "TOPLEFT", 22, -23 },
		{ "housing-item-toast-leaf04", "LEFT", 5, 10 },
		{ "housing-item-toast-leaf02", "BOTTOMLEFT", 15, 37 },
		{ "housing-item-toast-leaf06", "RIGHT", -1, 7 },
		{ "housing-item-toast-leaf03", "RIGHT", -5, -20 },
	};
	for _, leaf in ipairs(leaves) do
		local texture = CreateTexture(frame, "BORDER", leaf[1], 1);
		texture:SetPoint(leaf[2], leaf[3], leaf[4]);
	end

	frame.Label = frame:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall2");
	frame.Label:SetPoint("TOPLEFT", 88, -25);
	frame.Label:SetJustifyH("LEFT");
	local labelColor = HOUSING_REWARD_TOAST_LABEL_FONT_COLOR or Colors.Title;
	frame.Label:SetTextColor(labelColor:GetRGB());

	frame.Divider = CreateTexture(frame, "ARTWORK", "housing-item-toast-divider");
	frame.Divider:SetPoint("TOP", frame.Label, "BOTTOM", 0, -4);
	frame.Divider:SetPoint("LEFT", frame.Label, "LEFT", -8, 0);

	frame.Icon = frame:CreateTexture(nil, "ARTWORK");
	frame.Icon:SetSize(35, 35);
	frame.Icon:SetPoint("RIGHT", frame.Divider, "LEFT", -5, 0);
	frame.Icon:SetPoint("CENTER", frame.Background, "CENTER");

	frame.IconBorder = frame:CreateTexture(nil, "OVERLAY");
	frame.IconBorder:SetAtlas("housing-item-wood-frame_64");
	frame.IconBorder:SetAllPoints(frame.Icon);

	frame.Name = frame:CreateFontString(nil, "ARTWORK", "GameFontHighlightMed2");
	frame.Name:SetPoint("TOP", frame.Divider, "BOTTOM", 0, -5);
	frame.Name:SetPoint("LEFT", frame.Label, "LEFT");
	frame.Name:SetPoint("RIGHT", -35, 0);
	frame.Name:SetJustifyH("LEFT");
	frame.Name:SetWordWrap(false);

	frame.Detail = frame:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall");
	frame.Detail:SetPoint("TOPLEFT", frame.Name, "BOTTOMLEFT", 0, -3);
	frame.Detail:SetPoint("RIGHT", -35, 0);
	frame.Detail:SetJustifyH("LEFT");

	frame.Glow = CreateTexture(frame, "OVERLAY", "housing-item-toast-glow", 1);
	frame.Glow:SetBlendMode("ADD");
	frame.Glow:SetPoint("CENTER");
	frame.Glow:SetAlpha(0);

	frame.AnimIn = frame:CreateAnimationGroup();
	AddAlpha(frame.AnimIn, frame, 0, 1, 0.2);
	AddAlpha(frame.AnimIn, frame.Glow, 0, 1, 0.25);
	AddAlpha(frame.AnimIn, frame.Glow, 1, 0, 0.75, 0.25);
	AddAlpha(frame.AnimIn, frame.LightRays, 0, 1, 0.5, 0.25);
	AddAlpha(frame.AnimIn, frame.LightRays, 1, 0.4, 1, 0.75);
	AddAlpha(frame.AnimIn, frame.LightRays2, 0, 1, 0.6, 0.25);
	AddAlpha(frame.AnimIn, frame.LightRays2, 1, 0.6, 1, 0.85);
	frame.AnimIn:SetToFinalAlpha(true);

	frame.AnimOut = frame:CreateAnimationGroup();
	AddAlpha(frame.AnimOut, frame, 1, 0, 1.0, HOLD_SECONDS);
	frame.AnimOut:SetToFinalAlpha(true);
	frame.AnimOut:SetScript("OnFinished", function()
		frame:Hide();
		Toast:ShowNext();
	end);

	frame:SetScript("OnEnter", function()
		frame.AnimOut:Stop();
		frame:SetAlpha(1);
	end);
	frame:SetScript("OnLeave", function()
		frame.AnimOut:Play();
	end);
	frame:SetScript("OnClick", function(_, button)
		frame.AnimOut:Stop();
		frame:Hide();
		if button == "LeftButton" then
			HSC:ShowWindow();
		end
		Toast:ShowNext();
	end);

	return frame;
end

local function Display(entry)
	if not toast then
		toast = CreateToast();
	end
	if toast:GetParent() ~= GetAppropriateTopLevelParent() then
		FrameUtil.UpdateTopLevelParent(toast);
	end

	toast.Label:SetText(entry.label);
	toast.Name:SetText(entry.name);
	toast.Detail:SetText(entry.detail or "");
	Data.SetIcon(toast.Icon, { icon = entry.icon, iconAtlas = entry.iconAtlas or "Perks-ShoppingCart" });

	toast.AnimOut:Stop();
	toast.AnimIn:Stop();
	toast:SetAlpha(0);
	toast:Show();
	toast.AnimIn:Play();
	toast.AnimOut:Play();
end

function Toast:ShowNext()
	local entry = table.remove(queue, 1);
	if entry then
		Display(entry);
	end
end

function Toast:Queue(entry)
	if not (HSC.settings and HSC.settings.toasts) then
		return;
	end
	if #queue >= MAX_QUEUE and not entry.keep then
		for index = #queue, 1, -1 do
			local last = queue[index];
			if not last.keep then
				last.extra = (last.extra or 0) + 1;
				last.detail = last.extra == 1 and L["...and 1 more thing for your cart"]
					or L["...and %d more things for your cart"]:format(last.extra);
				return;
			end
		end
	end
	queue[#queue + 1] = entry;
	if not (toast and toast:IsShown()) then
		self:ShowNext();
	end
end

local function QueueCartComplete()
	Toast:Queue({
		label = L["Shopping Cart"],
		name = L["Everything collected!"],
		detail = Colors.Green:WrapTextInColorCode(L["Your cart is complete - time to build."]),
		iconAtlas = "Perks-ShoppingCart",
		keep = true,
	});
	HSC:PlaySound("UI_WORLDQUEST_COMPLETE");
end

local function IsCartComplete()
	local stats = Cart:GetStats();
	return stats.lines > 0 and stats.left == 0;
end

HSC:On("CART_PROGRESS", function(changes, silent)
	if silent or (HSC.Merchant and HSC.Merchant:IsBuying()) then
		return;
	end
	local completedAny = false;
	for _, change in ipairs(changes) do
		local line = change.line;
		local got, need, _, collected = Cart:GetProgress(line);
		local display = Data.GetDisplay(line.contentType, line.recordID, line.name);
		local entry = {
			label = L["Shopping Cart"],
			name = display.name,
			icon = display.icon,
			iconAtlas = display.iconAtlas,
		};
		if collected then
			completedAny = true;
			entry.detail = Colors.Green:WrapTextInColorCode(need > 1 and L["All %d collected!"]:format(need) or L["Collected!"]);
		else
			entry.detail = L["%d of %d collected"]:format(got, need);
		end
		Toast:Queue(entry);
	end

	if completedAny and IsCartComplete() then
		QueueCartComplete();
	elseif completedAny then
		HSC:PlaySound("IG_QUEST_LIST_COMPLETE");
	end
end);

HSC:On("MERCHANT_RUN_DONE", function(bought)
	if bought == 0 then
		return;
	end
	Toast:Queue({
		label = L["Shopping Cart"],
		name = bought == 1 and L["Bought 1 item"] or L["Bought %d items"]:format(bought),
		detail = Colors.Green:WrapTextInColorCode(L["for your Shopping Cart"]),
		iconAtlas = "Perks-ShoppingCart",
	});
	if IsCartComplete() then
		QueueCartComplete();
	end
end);
