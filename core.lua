local addon = ...

local db
local realm
local player
local guild
local isAtBank = false

local format   = string.format
local match    = string.match
local select   = select
local tonumber = tonumber

local ContainerIDToInventoryID = _G.ContainerIDToInventoryID
local GetContainerNumSlots     = _G.GetContainerNumSlots
local GetContainerItemInfo     = _G.GetContainerItemInfo
local GetGuildBankItemInfo     = _G.GetGuildBankItemInfo
local GetGuildBankItemLink     = _G.GetGuildBankItemLink
local GetGuildBankTabInfo      = _G.GetGuildBankTabInfo
local GetCurrentGuildBankTab   = _G.GetCurrentGuildBankTab
local GetInventoryItemID       = _G.GetInventoryItemID
local GetNumGuildBankTabs      = _G.GetNumGuildBankTabs
local GetQuestItemLink         = _G.GetQuestItemLink
local GetRecipeReagentItemLink = _G.C_TradeSkillUI.GetRecipeReagentItemLink
local GetRecipeItemLink        = _G.C_TradeSkillUI.GetRecipeItemLink
local GetVoidItemInfo          = _G.GetVoidItemInfo

local BACKPACK_CONTAINER       = _G.BACKPACK_CONTAINER
local BANK_CONTAINER           = _G.BANK_CONTAINER
local GUILD_BANK               = _G.GUILD_BANK
local INVSLOT_FIRST_EQUIPPED   = _G.INVSLOT_FIRST_EQUIPPED
local INVSLOT_LAST_EQUIPPED    = _G.INVSLOT_LAST_EQUIPPED
local NUM_BAG_SLOTS            = _G.NUM_BAG_SLOTS
local NUM_BANKBAGSLOTS         = _G.NUM_BANKBAGSLOTS
local RAID_CLASS_COLORS        = _G.RAID_CLASS_COLORS
local REAGENTBANK_CONTAINER    = _G.REAGENTBANK_CONTAINER
local TOTAL                    = _G.TOTAL

local FACTION_COLORS = {
	Alliance = "ff4954e8",
	Horde = "ffe50c11"
}
local NUM_VOID_SLOTS_PER_TAB = 80
local NUM_GUILDBANK_SLOTS_PER_TAB = 98

local Warehouse = _G.CreateFrame('Frame', addon)
Warehouse:SetScript('OnEvent', function(self, event, ...) self[event](self, ...) end)
Warehouse:RegisterEvent("ADDON_LOADED")
Warehouse:RegisterEvent("PLAYER_LOGIN")

function Warehouse:SaveBag(bag)
	local contents = {}
	for slot = 1, GetContainerNumSlots(bag) do
		local _, count, _,_,_,_, link = GetContainerItemInfo(bag, slot)
		if link then
			local itemID = tonumber(match(link, "item:(%d+)"))
			contents[itemID] = (contents[itemID] or 0) + count
		end
	end

	player[bag] = contents

	if bag > 0 then
		self:PLAYER_EQUIPMENT_CHANGED(ContainerIDToInventoryID(bag))
	end
end

function Warehouse:ADDON_LOADED(name)
	if name ~= addon then return end

	self:UnregisterEvent("ADDON_LOADED")

	_G.rainWarehouseDB = _G.rainWarehouseDB or {}
	db = _G.rainWarehouseDB
end

function Warehouse:PLAYER_LOGIN()
	-- setup player
	local playerName = _G.UnitName("player")
	local realmName = _G.GetRealmName()
	local faction = _G.UnitFactionGroup("player")
	local _, class = _G.UnitClass("player")

	-- setup db
	db[realmName] = db[realmName] or {}
	realm = db[realmName]
	realm[playerName] = realm[playerName] or {}
	player = realm[playerName]
	player.equip = player.equip or {}
	player.faction = faction
	player.class = class

	-- get guild info
	self:PLAYER_GUILD_UPDATE()

	-- get player equipment
	for slot = INVSLOT_FIRST_EQUIPPED, INVSLOT_LAST_EQUIPPED do
		self:PLAYER_EQUIPMENT_CHANGED(slot)
	end

	-- get bag contents
	for bag = BACKPACK_CONTAINER, NUM_BAG_SLOTS do
		if next(player[bag] or {}) == nil then
			self:SaveBag(bag)
		end
	end

	-- get reagent bank contents
	if _G.IsReagentBankUnlocked() and next(player[REAGENTBANK_CONTAINER] or {}) == nil then
		self:SaveBag(REAGENTBANK_CONTAINER)
	end

	self:RegisterEvent("BAG_UPDATE")
	self:RegisterEvent("PLAYER_EQUIPMENT_CHANGED")
	self:RegisterUnitEvent("PLAYER_GUILD_UPDATE", "player")

	self:RegisterEvent("BANKFRAME_OPENED")
	self:RegisterEvent("PLAYERREAGENTBANKSLOTS_CHANGED")

	self:RegisterEvent("VOID_STORAGE_OPEN")
end

function Warehouse:PLAYER_GUILD_UPDATE()
	local oldGuild = player.guild
	local guildName = _G.GetGuildInfo("player")
	if guildName then
		local id = guildName .."*" -- to not colide with player names
		realm[id] = realm[id] or {}
		guild = realm[id]

		self:RegisterEvent("GUILDBANKFRAME_OPENED")
	else
		if guildName ~= oldGuild then
			local strayedGuild = true
			for name, data in pairs(realm) do
				if not name:find("*$") and data.guild == oldGuild then
					strayedGuild = false
					break
				end
			end
			if strayedGuild then
				realm[oldGuild.."*"] = nil
			end
		end
		self:UnregisterEvent("GUILDBANKFRAME_OPENED")
	end

	player.guild = guildName
end

function Warehouse.PLAYER_EQUIPMENT_CHANGED(_, slot)
	local itemID = GetInventoryItemID("player", slot)
	player["equip"][slot] = itemID
end

function Warehouse:BAG_UPDATE(bag)
	local available = isAtBank or bag >= BACKPACK_CONTAINER and bag <= NUM_BAG_SLOTS -- reagents has its own event

	if available then
		self:SaveBag(bag)
	end
end

function Warehouse:BANKFRAME_OPENED()
	isAtBank = true

	if next(player[BANK_CONTAINER] or {}) == nil then
		self:SaveBag(BANK_CONTAINER)
	end

	for bag = NUM_BAG_SLOTS + 1, NUM_BAG_SLOTS + NUM_BANKBAGSLOTS do
		if next(player[bag] or {}) == nil then
			self:SaveBag(bag)
		end
	end

	self:RegisterEvent("BANKFRAME_CLOSED")
	self:RegisterEvent("PLAYERBANKSLOTS_CHANGED")
end

function Warehouse:BANKFRAME_CLOSED()
	isAtBank = false

	self:UnregisterEvent("BANKFRAME_CLOSED")
	self:UnregisterEvent("PLAYERBANKSLOTS_CHANGED")
end

function Warehouse:PLAYERBANKSLOTS_CHANGED()
	self:SaveBag(BANK_CONTAINER)
end

function Warehouse:PLAYERREAGENTBANKSLOTS_CHANGED()
	self:SaveBag(REAGENTBANK_CONTAINER)
end

function Warehouse:VOID_STORAGE_OPEN()
	self:RegisterEvent("VOID_TRANSFER_DONE")
	self:RegisterEvent("VOID_STORAGE_CLOSE")
end

function Warehouse:VOID_STORAGE_CLOSE()
	self:UnregisterEvent("VOID_TRANSFER_DONE")
	self:UnregisterEvent("VOID_STORAGE_CLOSE")

	if next(player.vault or {}) == nil then
		self:VOID_TRANSFER_DONE()
	end
end

function Warehouse.VOID_TRANSFER_DONE()
	local vault = {}
	for tab = 1, 2 do
		for slot = 1, NUM_VOID_SLOTS_PER_TAB do
			local itemID = GetVoidItemInfo(tab, slot)
			if itemID then
				vault[itemID] = 1
			end
		end
	end

	player.vault = vault
end

function Warehouse:GUILDBANKFRAME_OPENED()
	self:RegisterEvent("GUILDBANKBAGSLOTS_CHANGED")
	self:RegisterEvent("GUILDBANKFRAME_CLOSED")
end

function Warehouse:GUILDBANKFRAME_CLOSED()
	self:UnregisterEvent("GUILDBANKBAGSLOTS_CHANGED")
	self:UnregisterEvent("GUILDBANKFRAME_CLOSED")
end

function Warehouse.GUILDBANKBAGSLOTS_CHANGED()
	local tab = GetCurrentGuildBankTab()
	if not tab then return end

	local _, _, isViewable = GetGuildBankTabInfo(tab)
	if not isViewable then return end

	local contents = {}

	for slot = 1, NUM_GUILDBANK_SLOTS_PER_TAB do
		local _, count = GetGuildBankItemInfo(tab, slot)
		if count and count > 0 then
			local link = GetGuildBankItemLink(tab, slot)
			if link then
				local itemID = tonumber(match(link, "item:(%d+)"))
				contents[itemID] = (contents[itemID] or 0) + count
			end
		end
	end

	guild[tab] = contents
end

local labels = {
	"Bags",
	_G.BANK,
	"Equipped",
	_G.VOID_STORAGE,
}

local function FormatCount(total, ...)
	local text = ""
	local places = 0
	local delimiter = " "

	for i = 1, select("#", ...) do
		local count = select(i, ...)
		if count > 0 then
			text = format("%s%s%s: %d", text, i > 1 and delimiter or "", labels[i], count)
			places = places + 1
		end
	end

	if places > 1 then
		text = format("%d (%s)", total, text)
	end

	return text
end

local function GetItemCounts(storage, itemID)
	local inBags = 0
	for bag = BACKPACK_CONTAINER, NUM_BAG_SLOTS do
		local contents = storage[bag]
		inBags = inBags + (contents and contents[itemID] or 0)
	end

	local inBank = 0
	for bag = NUM_BAG_SLOTS + 1, NUM_BAG_SLOTS + NUM_BANKBAGSLOTS do
		local contents = storage[bag]
		inBank = inBank + (contents and contents[itemID] or 0)
	end

	local bank = storage[BANK_CONTAINER]
	inBank = inBank + (bank and bank[itemID] or 0)

	local reagents = storage[REAGENTBANK_CONTAINER]
	inBank = inBank + (reagents and reagents[itemID] or 0)

	local vault = storage.vault
	local inVault = vault and vault[itemID] or 0

	local equipped = 0
	for _, id in pairs(storage.equip) do
		if id == itemID then
			equipped = equipped + 1
		end
	end

	return inBags, inBank, equipped, inVault
end

local function AddItemCount(tooltip, link)
	if not link or link == "[]" then return end -- tooltip:GetItem() is bugged sometimes (since 6.2 apparently)

	local itemID = tonumber(match(link, "item:(%d+)"))
	local total = 0
	local lines = 0

	for playerName, storage in pairs(realm) do
		if not playerName:find("*$") and player.faction == storage.faction then
			local color = RAID_CLASS_COLORS[storage.class].colorStr
			local inBags, inBank, equipped, inVault = GetItemCounts(storage, itemID)
			local count = inBags + inBank + equipped + inVault
			if count > 0 then
				if lines == 0 then
					tooltip:AddLine(" ")
				end
				local text = FormatCount(count, inBags, inBank, equipped, inVault)
				tooltip:AddDoubleLine(format("|c%s%s|r", color, playerName), format("|c%s%s|r", color, text))
				total = total + count
				lines = lines + 1
			end
		end
	end

	local inGuild = 0
	if guild then -- current player only
		for tab = 1, GetNumGuildBankTabs() do
			local contents = guild[tab]
			inGuild = inGuild + (contents and contents[itemID] or 0)
		end
		if inGuild > 0 then
			local color = FACTION_COLORS[player.faction]
			tooltip:AddDoubleLine(format("|c%s%s|r", color, GUILD_BANK), format("|c%s%d", color, inGuild))
			total = total + inGuild
			lines = lines + 1
		end
	end

	local totalText = total
	if inGuild > 0 then
		totalText = format("%d (%d)", total - inGuild, total)
	end

	if lines > 1 and total > 0 then
		tooltip:AddDoubleLine(TOTAL, totalText)
	end

	--tooltip.__itemCountAdded = true
	tooltip:Show()
end

local function OnItem(tooltip)
	local _, link = tooltip:GetItem()
	AddItemCount(tooltip, link)
end

local function OnTradeSkill(tooltip, recipe, reagent)
	if reagent then
        AddItemCount(tooltip, GetRecipeReagentItemLink(recipe, reagent))
    else
        AddItemCount(tooltip, GetRecipeItemLink(recipe))
    end
end

local function OnQuest(tooltip, rewardType, rewardIndex)
	AddItemCount(tooltip, GetQuestItemLink(rewardType, rewardIndex))
end

local function OnHide(tooltip)
	tooltip.__itemCountAdded = false
end

local function HookTip(tooltip)
	tooltip:HookScript("OnTooltipSetItem", OnItem)
	--tooltip:HookScript("OnTooltipCleared", OnHide)

	--_G.hooksecurefunc(tooltip, 'SetRecipeReagentItem', OnTradeSkill)
	--_G.hooksecurefunc(tooltip, 'SetRecipeResultItem', OnTradeSkill)
	--_G.hooksecurefunc(tooltip, 'SetQuestItem', OnQuest)
	--_G.hooksecurefunc(tooltip, 'SetQuestLogItem', OnQuest)
end

HookTip(_G.GameTooltip)
HookTip(_G.ItemRefTooltip)
