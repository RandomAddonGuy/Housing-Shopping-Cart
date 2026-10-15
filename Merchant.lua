local _, HSC = ...
local L = HSC.L;
local Data = HSC.Data;
local Cart = HSC.Cart;

local Merchant = {};
HSC.Merchant = Merchant;

local STEP_SECONDS = 0.2;
local MIN_GAP = 0.35;
local STALL_SECONDS = 6;

local isOpen = false;
local run;

function Merchant:IsOpen()
	return isOpen;
end

local function WantedItems()
	local wanted = {};
	for _, line in pairs(Cart:GetLines()) do
		local _, _, left = Cart:GetProgress(line);
		if left > 0 then
			local itemID = Data.GetLineItemID(line);
			if itemID then
				wanted[itemID] = line;
			end
		end
	end
	return wanted;
end

local function ReadCosts(index, info)
	local costs = {};
	if (info.price or 0) > 0 then
		costs[#costs + 1] = { copper = info.price };
	end
	if info.hasExtendedCost then
		for slot = 1, (MAX_ITEM_COST or 3) do
			local texture, value, link, currencyName = GetMerchantItemCostItem(index, slot);
			if texture then
				local currencyID = currencyName and type(link) == "string" and tonumber(link:match("currency:(%d+)"));
				if not currencyID then
					return costs, L["Costs items - buy it in the vendor window"];
				end
				costs[#costs + 1] = { currencyID = currencyID, amount = value or 0 };
			end
		end
	end
	return costs, nil;
end

function Merchant:GetOffers()
	local offers = {};
	if not isOpen or not GetMerchantNumItems then
		return offers;
	end
	local wanted = WantedItems();
	if next(wanted) == nil then
		return offers;
	end
	for index = 1, GetMerchantNumItems() do
		local itemID = GetMerchantItemID(index);
		local line = itemID and wanted[itemID];
		local ok, info = false, nil;
		if line then
			ok, info = pcall(C_MerchantFrame.GetItemInfo, index);
		end
		if ok and type(info) == "table" then
			wanted[itemID] = nil;
			local _, _, left = Cart:GetProgress(line);
			local offer = {
				index = index,
				itemID = itemID,
				line = line,
				name = Data.GetDisplay(line.contentType, line.recordID, line.name).name or info.name,
				texture = info.texture,
				need = left,
			};
			offer.costs, offer.problem = ReadCosts(index, info);
			if not offer.problem then
				if info.isPurchasable == false then
					offer.problem = L["You can't buy this yet"];
				elseif info.numAvailable == 0 then
					offer.problem = L["Sold out"];
				elseif (info.stackCount or 1) > 1 then
					offer.problem = L["Sold in stacks - buy it in the vendor window"];
				end
			end
			offer.toBuy = left;
			if (info.numAvailable or -1) > 0 then
				offer.toBuy = math.min(left, info.numAvailable);
			end
			if offer.problem then
				offer.toBuy = 0;
			end
			offers[#offers + 1] = offer;
		end
	end
	table.sort(offers, function(a, b)
		return strcmputf8i(a.name or "", b.name or "") < 0;
	end);
	return offers;
end

function Merchant:GetTotals(offers)
	local totals = Data.NewTotals();
	for _, offer in ipairs(offers) do
		for _, cost in ipairs(offer.costs or {}) do
			Data.AddToTotals(totals, cost, offer.toBuy);
		end
	end
	return totals;
end

function Merchant:FormatTotals(offers, withNames)
	return Data.FormatTotals(self:GetTotals(offers), withNames);
end

function Merchant:CanAffordAll(offers)
	return Data.CanAffordTotals(self:GetTotals(offers));
end

function Merchant:IsBuying()
	return run ~= nil;
end

function Merchant:GetProgress()
	if not run then
		return 0, 0;
	end
	return run.bought, run.total;
end

local function ShortOf(costs)
	for _, cost in ipairs(costs) do
		if Data.CanAfford(cost, 1) == false then
			if cost.copper then
				return MONEY or L["gold"];
			end
			local _, info = Data.GetCurrencyOwned(cost.currencyID);
			return info and info.name or CURRENCY or L["currency"];
		end
	end
	return nil;
end

local function FindIndex(entry)
	if GetMerchantItemID(entry.index) == entry.itemID then
		return entry.index;
	end
	for index = 1, GetMerchantNumItems() do
		if GetMerchantItemID(index) == entry.itemID then
			return index;
		end
	end
	return nil;
end

local function CountOwned(entry)
	return Data.GetOwned(entry.line.contentType, entry.line.recordID) or 0;
end

local function Recount(entry)
	local landed = math.min(math.max(CountOwned(entry) - entry.start, 0), entry.qty);
	if landed > entry.landed then
		run.bought = run.bought + (landed - entry.landed);
		entry.landed = landed;
		run.lastProgress = GetTime();
		return true;
	end
	return false;
end

local function EndRun(reason)
	local bought, total = run.bought, run.total;
	if run.ticker then
		run.ticker:Cancel();
	end
	run = nil;
	Cart:Refresh(true);
	if reason then
		HSC:Print(L["Stopped buying: %s. Bought %d of %d."]:format(reason, bought, total));
	else
		HSC:Print(bought == 1 and L["Bought 1 item for your cart."] or L["Bought %d items for your cart."]:format(bought));
	end
	HSC:Fire("MERCHANT_RUN_DONE", bought, total, reason);
	HSC:Fire("MERCHANT_RUN_UPDATE");
end

function Merchant:Stop(reason)
	if run then
		EndRun(reason or L["you stopped it"]);
	end
end

function Merchant:Step()
	if not run then
		return;
	end
	if not isOpen then
		EndRun(L["the vendor window closed"]);
		return;
	end

	local changed = false;
	local entry = run.queue[run.pos];
	while entry do
		if Recount(entry) then
			changed = true;
		end
		if entry.landed < entry.qty then
			break;
		end
		run.pos = run.pos + 1;
		entry = run.queue[run.pos];
	end
	if changed then
		HSC:Fire("MERCHANT_RUN_UPDATE");
	end
	if not entry then
		EndRun(nil);
		return;
	end

	local now = GetTime();
	if entry.landed < entry.sent then
		if now - run.lastProgress > STALL_SECONDS then
			EndRun(L["a purchase didn't arrive - check your bags"]);
		end
		return;
	end
	if now - run.lastBuy < MIN_GAP then
		return;
	end
	local line = Cart:GetLine(Data.Key(entry.line.contentType, entry.line.recordID));
	local left = line and Cart:GetLeftNow(line) or 0;
	local qty = math.min(entry.qty, entry.landed + left);
	if qty < entry.qty then
		run.total = run.total - (entry.qty - qty);
		entry.qty = qty;
		HSC:Fire("MERCHANT_RUN_UPDATE");
		if entry.landed >= entry.qty then
			return;
		end
	end

	local index = FindIndex(entry);
	if not index then
		EndRun(L["the vendor no longer sells %s"]:format(entry.name or "?"));
		return;
	end
	entry.index = index;
	local short = ShortOf(entry.costs);
	if short then
		EndRun(L["not enough %s"]:format(short));
		return;
	end

	entry.sent = entry.sent + 1;
	run.lastBuy, run.lastProgress = now, now;
	BuyMerchantItem(index, 1);
end

function Merchant:Buy(offers)
	if run then
		return false;
	end
	if not isOpen then
		return false;
	end
	local queue, total = {}, 0;
	for _, offer in ipairs(offers) do
		local line = Cart:GetLine(Data.Key(offer.line.contentType, offer.line.recordID));
		local left = line and Cart:GetLeftNow(line) or 0;
		local qty = math.min(offer.toBuy, left);
		if not offer.problem and qty > 0 then
			local entry = {
				index = offer.index,
				itemID = offer.itemID,
				line = line,
				name = offer.name,
				costs = offer.costs,
				qty = qty,
				sent = 0,
				landed = 0,
			};
			entry.start = CountOwned(entry);
			queue[#queue + 1] = entry;
			total = total + qty;
		end
	end
	if total == 0 then
		return false;
	end
	run = { queue = queue, pos = 1, total = total, bought = 0, lastBuy = 0, lastProgress = GetTime() };
	run.ticker = C_Timer.NewTicker(STEP_SECONDS, function()
		Merchant:Step();
	end);
	HSC:Fire("MERCHANT_RUN_UPDATE");
	self:Step();
	return true;
end

StaticPopupDialogs["HOUSINGSHOPPINGCART_BUY"] = {
	text = "%s",
	button1 = PURCHASE or L["Buy"],
	button2 = CANCEL,
	OnAccept = function(_, offers)
		Merchant:Buy(offers);
	end,
	timeout = 0,
	whileDead = true,
	hideOnEscape = true,
};

function Merchant:ConfirmBuy(offers)
	local buyable, count = {}, 0;
	for _, offer in ipairs(offers) do
		if not offer.problem and offer.toBuy > 0 then
			buyable[#buyable + 1] = offer;
			count = count + offer.toBuy;
		end
	end
	if count == 0 or run then
		return;
	end
	local what;
	if #buyable == 1 then
		what = ("%d× %s"):format(count, buyable[1].name or "?");
	else
		what = L["%d items"]:format(count);
	end
	local text = L["Buy %s for your Shopping Cart?"]:format(what) .. "|n|n" .. self:FormatTotals(buyable, true);
	if not self:CanAffordAll(buyable) then
		text = text .. "|n|n" .. HSC.Colors.Red:WrapTextInColorCode(L["You can't afford all of it - buying stops when you run out."]);
	end
	StaticPopup_Show("HOUSINGSHOPPINGCART_BUY", text, nil, buyable);
end

HSC:RegisterEvent("MERCHANT_SHOW", function()
	isOpen = true;
	HSC:Fire("MERCHANT_CHANGED");
end);

HSC:RegisterEvent("MERCHANT_CLOSED", function()
	isOpen = false;
	StaticPopup_Hide("HOUSINGSHOPPINGCART_BUY");
	if run then
		EndRun(L["the vendor window closed"]);
	end
	HSC:Fire("MERCHANT_CHANGED");
end);

HSC:RegisterEvent("MERCHANT_UPDATE", function()
	if isOpen then
		HSC:Debounce("merchantUpdate", 0.2, function()
			HSC:Fire("MERCHANT_CHANGED");
		end);
	end
end);
