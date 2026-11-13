--[[
  Odkrywca - WoW: Forever (1.60.x, interfejs 16001)

  PL: Zapisuje TYLKO te zasoby (ziola, zyly rud, skrzynie), ktore sam zebrales,
      i pokazuje je na duzej mapie swiata. Zadnej gotowej bazy.
  EN: Records ONLY the herbs, ore veins and chests YOU gathered and shows them
      on the world map. No pre-made database.

  Jak to dziala / How it works:
    UNIT_SPELLCAST_SENT      -> czar zbierania + nazwa obiektu / gathering spell + node name
    UNIT_SPELLCAST_SUCCEEDED -> zapis pozycji / position is saved
    LOOT_READY               -> co wypadlo + ikona / what dropped + icon
]]

local ADDON_NAME = ...
local PIN_TEMPLATE = "OdkrywcaPinTemplate"
local MERGE_YARDS = 25          -- ten sam zasob w promieniu tylu jardow = ten sam punkt
local MERGE_FALLBACK = 0.008    -- to samo, gdy nie znamy rozmiaru mapy (wspolrzedne 0..1)
local LOOT_WINDOW = 5           -- sekundy po zebraniu, w ktorych loot przypisujemy do punktu

------------------------------------------------------------------------
-- Jezyki / Languages
------------------------------------------------------------------------

local LOCALES = {
	pl = {
		herb = "Zioła", ore = "Rudy", treasure = "Skrzynie",
		discovered = "Odkryto: |cffffd100%s|r  (%s %.1f, %.1f)",
		map_fallback = "mapa %s",
		tt_count = "Zebrano razy:",
		tt_first = "Odkryto:",
		tt_last = "Ostatnio:",
		tt_loot = "Łącznie wypadło:",
		tt_by = "Odkryte przez: %s",
		tt_remove = "Shift + prawy klik: usuń ten punkt",
		removed = "Usunięto punkt: %s",
		on = "wł.", off = "wył.",
		stats = "Odkryte punkty: %d  (zioła %d, rudy %d, skrzynie %d) na %d mapach.",
		settings = "Pinezki %s | zioła %s | rudy %s | skrzynie %s | tylko ta postać %s | rozmiar %d | polskie znaki %s",
		pins = "Pinezki: %s",
		filter = "%s: %s",
		only_mine = "Tylko ta postać: %s",
		size_set = "Rozmiar ikon: %d",
		size_bad = "Podaj liczbę 8-40, np. /odk rozmiar 18",
		announce = "Komunikaty o odkryciach: %s",
		clear_confirm = "To usunie odkrycia z: %s. Wpisz: /odk wyczysc tak",
		cleared = "Wyczyszczono: %s",
		reset_confirm = "To usunie WSZYSTKIE odkrycia. Wpisz: /odk reset tak",
		reset_done = "Wszystkie odkrycia usunięte.",
		lang_set = "Język: polski",
		lang_bad = "Dostępne języki: pl, en  (np. /odk jezyk en)",
		accents = "Polskie znaki: %s",
		commands = "komendy:",
		help = {
			"/odk pokaz  - włącz/wyłącz wszystkie pinezki",
			"/odk ziola | rudy | skrzynie  - filtr typu",
			"/odk moje  - tylko punkty odkryte przez tę postać",
			"/odk rozmiar 18  - rozmiar ikon (8-40)",
			"/odk ogloszenia  - komunikat na czacie przy nowym odkryciu",
			"/odk stat  - statystyki",
			"/odk wyczysc tak  - usuń punkty z obecnej strefy",
			"/odk reset tak  - usuń WSZYSTKIE odkrycia",
			"/odk jezyk en  - English / angielski",
			"/odk ogonki  - polskie znaki (tylko z czcionką, która je ma)",
		},
	},
	en = {
		herb = "Herbs", ore = "Ore", treasure = "Chests",
		discovered = "Discovered: |cffffd100%s|r  (%s %.1f, %.1f)",
		map_fallback = "map %s",
		tt_count = "Gathered:",
		tt_first = "Discovered:",
		tt_last = "Last time:",
		tt_loot = "Total loot:",
		tt_by = "Discovered by: %s",
		tt_remove = "Shift + right-click: remove this node",
		removed = "Node removed: %s",
		on = "on", off = "off",
		stats = "Discovered nodes: %d  (herbs %d, ore %d, chests %d) on %d maps.",
		settings = "Pins %s | herbs %s | ore %s | chests %s | this character only %s | size %d",
		pins = "Pins: %s",
		filter = "%s: %s",
		only_mine = "This character only: %s",
		size_set = "Icon size: %d",
		size_bad = "Enter a number 8-40, e.g. /odk size 18",
		announce = "Discovery messages: %s",
		clear_confirm = "This will delete discoveries in: %s. Type: /odk clear yes",
		cleared = "Cleared: %s",
		reset_confirm = "This will delete ALL discoveries. Type: /odk reset yes",
		reset_done = "All discoveries deleted.",
		lang_set = "Language: English",
		lang_bad = "Available languages: pl, en  (e.g. /odk lang pl)",
		accents = "Polish characters: %s",
		commands = "commands:",
		help = {
			"/odk show  - toggle all pins",
			"/odk herbs | ore | chests  - type filters",
			"/odk mine  - only nodes discovered by this character",
			"/odk size 18  - icon size (8-40)",
			"/odk announce  - chat message on new discovery",
			"/odk stats  - statistics",
			"/odk clear yes  - delete nodes in the current zone",
			"/odk reset yes  - delete ALL discoveries",
			"/odk lang pl  - Polski / Polish",
		},
	},
}

-- Zamiana polskich znakow, gdy czcionka gry ich nie obsluguje (/odk ogonki).
local ACCENT_MAP = {
	["ą"] = "a", ["ć"] = "c", ["ę"] = "e", ["ł"] = "l", ["ń"] = "n", ["ó"] = "o", ["ś"] = "s", ["ź"] = "z", ["ż"] = "z",
	["Ą"] = "A", ["Ć"] = "C", ["Ę"] = "E", ["Ł"] = "L", ["Ń"] = "N", ["Ó"] = "O", ["Ś"] = "S", ["Ź"] = "Z", ["Ż"] = "Z",
}

local db -- ustawiane w InitDB

local function StripAccents(s)
	for from, to in pairs(ACCENT_MAP) do s = s:gsub(from, to) end
	return s
end

local function Fix(s)
	if db and db.settings.accents == false then return StripAccents(s) end
	return s
end

-- T("klucz", argumenty...) -> przetlumaczony tekst
local function T(key, ...)
	local lang = db and db.settings.lang or "pl"
	local loc = LOCALES[lang] or LOCALES.pl
	local s = loc[key] or LOCALES.pl[key] or key
	if type(s) ~= "string" then return s end
	if select("#", ...) > 0 then s = s:format(...) end
	return Fix(s)
end

local function HelpLines()
	local lang = db and db.settings.lang or "pl"
	return (LOCALES[lang] or LOCALES.pl).help
end

------------------------------------------------------------------------
-- Typy zasobow
------------------------------------------------------------------------

local TYPES = {
	herb     = { icon = "Interface\\Icons\\INV_Misc_Herb_07",  color = { 0.30, 0.90, 0.35 } },
	ore      = { icon = "Interface\\Icons\\INV_Ore_Copper_01", color = { 1.00, 0.55, 0.15 } },
	treasure = { icon = "Interface\\Icons\\INV_Box_01",        color = { 1.00, 0.82, 0.10 } },
}

-- Znane ID czarow zbierania (wszystkie rangi/wersje). Nazwy pobieramy z klienta,
-- wiec dziala niezaleznie od jezyka gry.
local SPELLS = {
	herb = { 2366, 2368, 3570, 11993, 28695, 50300, 74519, 110413, 158745, 195114, 265819, 309780, 366252 },
	ore  = { 2575, 2576, 3564, 10248, 29354, 50310, 74517, 102161, 158754, 195122, 265837, 309835, 366260 },
	treasure = { 3365, 6247, 6477, 6478, 21651, 22810 },
}
-- Zapas, gdyby Forever mial wlasne ID czarow.
local FALLBACK_NAMES = {
	herb = { "Herb Gathering", "Herbalism", "Kräutersammeln", "Kräuterkunde", "Cueillette", "Herboristería" },
	ore  = { "Mining", "Bergbau", "Minage", "Minería" },
	treasure = { "Opening", "Öffnen", "Ouverture", "Abriendo" },
}

local charKey
local spellIDType, spellNameType = {}, {}
local currentCast   -- { castGUID, type, name, unnamed }
local pendingLoot   -- { node, t }

------------------------------------------------------------------------
-- Pomocnicze
------------------------------------------------------------------------

-- WoW Forever dzieli API z Midnight: niektore wartosci moga byc "sekretne"
-- (np. w walce). Porownanie takiej wartosci rzuca blad, wiec zawsze sprawdzamy.
local function IsSecret(v)
	if v == nil then return false end
	return issecretvalue ~= nil and issecretvalue(v) or false
end

local function Usable(v)
	return v ~= nil and not IsSecret(v)
end

local function Print(msg)
	DEFAULT_CHAT_FRAME:AddMessage("|cff7fd1ffOdkrywca|r: " .. msg)
end

local function SpellName(id)
	if C_Spell and C_Spell.GetSpellName then
		return C_Spell.GetSpellName(id)
	elseif GetSpellInfo then
		return (GetSpellInfo(id))
	end
end

local function BuildSpellTables()
	for gtype, ids in pairs(SPELLS) do
		for _, id in ipairs(ids) do
			spellIDType[id] = gtype
			local name = SpellName(id)
			if Usable(name) then spellNameType[name] = gtype end
		end
	end
	for gtype, names in pairs(FALLBACK_NAMES) do
		for _, name in ipairs(names) do
			spellNameType[name] = spellNameType[name] or gtype
		end
	end
end

local function GatherTypeForSpell(spellID)
	if not Usable(spellID) then return nil end
	local gtype = spellIDType[spellID]
	if gtype then return gtype end
	local name = SpellName(spellID)
	if Usable(name) then return spellNameType[name] end
end

local function TooltipObjectName()
	local line = _G.GameTooltipTextLeft1
	if GameTooltip and GameTooltip:IsShown() and line then
		local text = line:GetText()
		if Usable(text) and text ~= "" then return text end
	end
end

local function MapName(mapID)
	local info = C_Map.GetMapInfo(mapID)
	return info and info.name or T("map_fallback", tostring(mapID))
end

-- Punkt bez znanej nazwy pokazujemy jako nazwe typu w aktualnym jezyku.
local function NodeName(n)
	if n.unnamed or not n.name then return T(n.type) end
	return n.name
end

local function Round(v)
	return math.floor(v * 10000 + 0.5) / 10000
end

------------------------------------------------------------------------
-- Baza (SavedVariables: OdkrywcaDB, wspolna dla Twoich postaci na koncie)
------------------------------------------------------------------------

local DEFAULT_SETTINGS = {
	show = { herb = true, ore = true, treasure = true },
	onlyMine = false,  -- tylko punkty odkryte przez aktualna postac
	hidden = false,    -- ukryj wszystkie pinezki
	announce = true,   -- komunikat na czacie przy nowym odkryciu
	size = 18,
	lang = "pl",       -- jezyk: "pl" albo "en"
	accents = false,   -- polskie znaki: czcionka WoW ich nie ma, wiec domyslnie bez ogonkow
}

local function InitDB()
	OdkrywcaDB = OdkrywcaDB or {}
	db = OdkrywcaDB
	db.nodes = db.nodes or {}
	db.settings = db.settings or {}
	local s = db.settings
	-- migracja z 1.1.0: czcionka gry nie ma polskich liter, wylaczamy ogonki
	if (db.version or 1) < 2 then s.accents = false end
	db.version = 2
	for k, v in pairs(DEFAULT_SETTINGS) do
		if s[k] == nil then
			s[k] = type(v) == "table" and CopyTable(v) or v
		end
	end
	for k, v in pairs(DEFAULT_SETTINGS.show) do
		if s.show[k] == nil then s.show[k] = v end
	end
	if not LOCALES[s.lang] then s.lang = "pl" end
end

local function IsVisible(node)
	local s = db.settings
	if s.show[node.type] == false then return false end
	if s.onlyMine and not (node.chars and node.chars[charKey]) then return false end
	return true
end

------------------------------------------------------------------------
-- Mapa swiata: pinezki
------------------------------------------------------------------------

OdkrywcaPinMixin = CreateFromMixins(MapCanvasPinMixin)

function OdkrywcaPinMixin:OnLoad()
	self:UseFrameLevelType("PIN_FRAME_LEVEL_AREA_POI")
	self:SetScalingLimits(1, 1.0, 1.2)
	self.Shadow:SetVertexColor(0, 0, 0, 0.75)
	self.Highlight:SetVertexColor(1, 1, 1, 0.25)
end

function OdkrywcaPinMixin:OnAcquired(node, srcMapID, x, y, size)
	self.node = node
	self.srcMapID = srcMapID
	self:SetSize(size, size)
	self:SetPosition(x, y)
	local t = TYPES[node.type] or TYPES.treasure
	self.Icon:SetTexture(node.icon or t.icon)
	self.Icon:SetTexCoord(0.08, 0.92, 0.08, 0.92) -- obciecie ramki ikony
	self.Ring:SetVertexColor(t.color[1], t.color[2], t.color[3], 1)
	self.Highlight:Hide()
end

function OdkrywcaPinMixin:OnMouseEnter()
	local n = self.node
	if not n then return end
	self.Highlight:Show()
	GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
	GameTooltip:AddLine(NodeName(n), 1, 0.82, 0)
	GameTooltip:AddLine(T(TYPES[n.type] and n.type or "treasure") .. " - " .. MapName(self.srcMapID), 0.7, 0.7, 0.7)
	GameTooltip:AddDoubleLine(T("tt_count"), tostring(n.count or 1), 1, 1, 1, 1, 1, 1)
	if n.first then GameTooltip:AddDoubleLine(T("tt_first"), date("%d.%m.%Y %H:%M", n.first), 1, 1, 1, 1, 1, 1) end
	if n.last and n.last ~= n.first then GameTooltip:AddDoubleLine(T("tt_last"), date("%d.%m.%Y %H:%M", n.last), 1, 1, 1, 1, 1, 1) end

	if n.items and next(n.items) then
		GameTooltip:AddLine(" ")
		GameTooltip:AddLine(T("tt_loot"), 0.6, 0.85, 1)
		local names = {}
		for item in pairs(n.items) do names[#names + 1] = item end
		table.sort(names, function(a, b) return n.items[a] > n.items[b] end)
		for i = 1, math.min(#names, 8) do
			GameTooltip:AddDoubleLine("  " .. names[i], "x" .. n.items[names[i]], 1, 1, 1, 1, 1, 1)
		end
	end

	if n.chars and next(n.chars) then
		local who = {}
		for c in pairs(n.chars) do who[#who + 1] = (c:match("^[^-]+") or c) end
		table.sort(who)
		GameTooltip:AddLine(" ")
		GameTooltip:AddLine(T("tt_by", table.concat(who, ", ")), 0.6, 0.6, 0.6, true)
	end
	GameTooltip:AddLine(T("tt_remove"), 0.5, 0.5, 0.5)
	GameTooltip:Show()
end

function OdkrywcaPinMixin:OnMouseLeave()
	self.Highlight:Hide()
	GameTooltip:Hide()
end

local RefreshMap -- forward

local function RemoveNode(target)
	for mapID, list in pairs(db.nodes) do
		for i = #list, 1, -1 do
			if list[i] == target then
				table.remove(list, i)
				if #list == 0 then db.nodes[mapID] = nil end
				Print(T("removed", NodeName(target)))
				RefreshMap()
				return
			end
		end
	end
end

function OdkrywcaPinMixin:OnMouseUp(button)
	if button == "RightButton" and IsShiftKeyDown() and self.node then
		GameTooltip:Hide()
		RemoveNode(self.node)
	end
end

-- Czy mapa childMapID lezy wewnatrz mapy parentMapID (strefa na kontynencie itp.)
local ancestryCache = {}
local function IsDescendant(childMapID, parentMapID)
	local key = childMapID .. ":" .. parentMapID
	local cached = ancestryCache[key]
	if cached ~= nil then return cached end
	local result = false
	local id, guard = childMapID, 0
	while id and id ~= 0 and guard < 10 do
		local info = C_Map.GetMapInfo(id)
		if not info then break end
		id = info.parentMapID
		if id == parentMapID then result = true break end
		guard = guard + 1
	end
	ancestryCache[key] = result
	return result
end

local rectCache = {}
local function GetChildRect(childMapID, parentMapID)
	local key = childMapID .. ":" .. parentMapID
	if rectCache[key] ~= nil then return rectCache[key] or nil end
	local rect = false
	if IsDescendant(childMapID, parentMapID) and C_Map.GetMapRectOnMap then
		local ok, minX, maxX, minY, maxY = pcall(C_Map.GetMapRectOnMap, childMapID, parentMapID)
		if ok and minX and maxX and minY and maxY and (maxX - minX) > 0 and (maxY - minY) > 0 then
			rect = { minX, maxX, minY, maxY }
		end
	end
	rectCache[key] = rect
	return rect or nil
end

local DataProvider = CreateFromMixins(MapCanvasDataProviderMixin)

function DataProvider:RemoveAllData()
	self:GetMap():RemoveAllPinsByTemplate(PIN_TEMPLATE)
end

function DataProvider:OnMapChanged()
	self:RefreshAllData()
end

function DataProvider:AddNodes(srcMapID, rect, size)
	local list = db.nodes[srcMapID]
	if not list then return end
	local map = self:GetMap()
	for _, n in ipairs(list) do
		if IsVisible(n) then
			local x, y = n.x, n.y
			if rect then
				x = rect[1] + x * (rect[2] - rect[1])
				y = rect[3] + y * (rect[4] - rect[3])
			end
			map:AcquirePin(PIN_TEMPLATE, n, srcMapID, x, y, size)
		end
	end
end

function DataProvider:RefreshAllData()
	self:RemoveAllData()
	if not db or db.settings.hidden then return end
	local uiMapID = self:GetMap():GetMapID()
	if not uiMapID then return end
	local size = db.settings.size

	-- punkty zapisane dokladnie na tej mapie
	self:AddNodes(uiMapID, nil, size)

	-- punkty z map podrzednych (np. strefy na widoku kontynentu, jaskinie na widoku strefy)
	local info = C_Map.GetMapInfo(uiMapID)
	if info and (info.mapType == Enum.UIMapType.Continent or info.mapType == Enum.UIMapType.Zone) then
		local childSize = info.mapType == Enum.UIMapType.Continent and math.max(8, math.floor(size * 0.6)) or size
		for srcMapID in pairs(db.nodes) do
			if srcMapID ~= uiMapID then
				local rect = GetChildRect(srcMapID, uiMapID)
				if rect then self:AddNodes(srcMapID, rect, childSize) end
			end
		end
	end
end

local providerAttached = false
local function AttachToWorldMap()
	if providerAttached or not WorldMapFrame or not WorldMapFrame.AddDataProvider then return end
	WorldMapFrame:AddDataProvider(DataProvider)
	providerAttached = true
end

RefreshMap = function()
	if providerAttached and WorldMapFrame:IsShown() then
		DataProvider:RefreshAllData()
	end
end

------------------------------------------------------------------------
-- Zapisywanie odkryc
------------------------------------------------------------------------

local function FindNearby(list, x, y, name, gtype, unnamed, w, h)
	for _, n in ipairs(list) do
		-- bez znanej nazwy laczymy z dowolnym punktem tego samego typu w poblizu
		if (name and n.name == name and not n.unnamed) or (n.type == gtype and (unnamed or n.unnamed)) then
			local dx, dy = n.x - x, n.y - y
			if w then
				dx, dy = dx * w, dy * h
				if dx * dx + dy * dy <= MERGE_YARDS * MERGE_YARDS then return n end
			elseif dx * dx + dy * dy <= MERGE_FALLBACK * MERGE_FALLBACK then
				return n
			end
		end
	end
end

local function RecordNode(gtype, name, unnamed)
	local mapID = C_Map.GetBestMapForUnit("player")
	if not Usable(mapID) then return end
	local pos = C_Map.GetPlayerMapPosition(mapID, "player")
	if not pos then return end
	local x, y = pos:GetXY()
	if not Usable(x) or not Usable(y) or (x == 0 and y == 0) then return end
	x, y = Round(x), Round(y)

	db.nodes[mapID] = db.nodes[mapID] or {}
	local list = db.nodes[mapID]
	local w, h
	if C_Map.GetMapWorldSize then
		local mw, mh = C_Map.GetMapWorldSize(mapID)
		if mw and mh and mw > 0 and mh > 0 then w, h = mw, mh end
	end

	local now = time()
	local node = FindNearby(list, x, y, name, gtype, unnamed, w, h)
	local isNew = false
	if node then
		node.count = (node.count or 1) + 1
		node.last = now
		if node.unnamed and not unnamed then
			node.name, node.unnamed = name, nil  -- poznalismy prawdziwa nazwe
		end
	else
		node = { x = x, y = y, name = name, type = gtype, count = 1, first = now, last = now, chars = {}, items = {}, unnamed = unnamed or nil }
		list[#list + 1] = node
		isNew = true
	end
	node.chars = node.chars or {}
	node.chars[charKey] = true
	pendingLoot = { node = node, t = GetTime() }

	if isNew and db.settings.announce then
		Print(T("discovered", NodeName(node), MapName(mapID), x * 100, y * 100))
	end
	RefreshMap()
end

local function OnSpellcastSent(unit, target, castGUID, spellID)
	if unit ~= "player" then return end
	local gtype = GatherTypeForSpell(spellID)
	if not gtype then return end
	local name = Usable(target) and target ~= "" and target or nil
	name = name or TooltipObjectName()
	currentCast = {
		castGUID = Usable(castGUID) and castGUID or nil,
		type = gtype,
		name = name,
		unnamed = name == nil,
	}
end

local function OnSpellcastSucceeded(unit, castGUID, spellID)
	if unit ~= "player" or not currentCast then return end
	local match
	if currentCast.castGUID and Usable(castGUID) then
		match = (castGUID == currentCast.castGUID)
	else
		match = (GatherTypeForSpell(spellID) == currentCast.type)
	end
	if match then
		local c = currentCast
		currentCast = nil
		RecordNode(c.type, c.name, c.unnamed)
	end
end

local function OnLootReady()
	if not pendingLoot then return end
	local p = pendingLoot
	pendingLoot = nil
	if GetTime() - p.t > LOOT_WINDOW then return end
	if IsFishingLoot and IsFishingLoot() then return end
	local node = p.node
	node.items = node.items or {}
	for slot = 1, GetNumLootItems() do
		local isItem = true
		if GetLootSlotType and Enum.LootSlotType then
			local st = GetLootSlotType(slot)
			isItem = Usable(st) and st == Enum.LootSlotType.Item
		end
		if isItem then
			local icon, itemName, qty = GetLootSlotInfo(slot)
			if Usable(icon) and not node.icon then node.icon = icon end
			if Usable(itemName) and itemName ~= "" then
				local q = (Usable(qty) and qty) or 1
				node.items[itemName] = (node.items[itemName] or 0) + q
			end
		end
	end
	RefreshMap()
end

------------------------------------------------------------------------
-- Komendy: /odk lub /odkrywca  (dzialaja slowa PL i EN)
------------------------------------------------------------------------

local function OnOff(v)
	return v and ("|cff00ff00" .. T("on") .. "|r") or ("|cffff4040" .. T("off") .. "|r")
end

local function Stats()
	local counts, maps, total = { herb = 0, ore = 0, treasure = 0 }, 0, 0
	for _, list in pairs(db.nodes) do
		maps = maps + 1
		for _, n in ipairs(list) do
			counts[n.type] = (counts[n.type] or 0) + 1
			total = total + 1
		end
	end
	Print(T("stats", total, counts.herb, counts.ore, counts.treasure, maps))
	local s = db.settings
	Print(T("settings", OnOff(not s.hidden), OnOff(s.show.herb), OnOff(s.show.ore), OnOff(s.show.treasure),
		OnOff(s.onlyMine), s.size, OnOff(s.accents)))
end

local function Help()
	Print(T("commands"))
	for _, l in ipairs(HelpLines()) do DEFAULT_CHAT_FRAME:AddMessage("   " .. Fix(l)) end
end

-- slowo z czatu -> komenda (polskie, polskie z ogonkami, angielskie)
local ALIASES = {
	pomoc = "help", help = "help",
	pokaz = "show", ["pokaż"] = "show", show = "show",
	ziola = "herb", ["zioła"] = "herb", herbs = "herb", herb = "herb",
	rudy = "ore", ore = "ore",
	skrzynie = "treasure", chests = "treasure", chest = "treasure",
	moje = "mine", mine = "mine",
	rozmiar = "size", size = "size",
	ogloszenia = "announce", ["ogłoszenia"] = "announce", announce = "announce",
	stat = "stats", stats = "stats", info = "stats",
	wyczysc = "clear", ["wyczyść"] = "clear", clear = "clear",
	reset = "reset",
	jezyk = "lang", ["język"] = "lang", lang = "lang", language = "lang",
	ogonki = "accents", accents = "accents",
}
local YES = { tak = true, yes = true }

SLASH_ODKRYWCA1 = "/odkrywca"
SLASH_ODKRYWCA2 = "/odk"
SlashCmdList.ODKRYWCA = function(msg)
	if not db then return end
	local word, arg = strtrim(msg or ""):lower():match("^(%S*)%s*(.-)$")
	local cmd = ALIASES[word]
	local s = db.settings
	if word == "" or cmd == "help" or not cmd then
		Help()
	elseif cmd == "show" then
		s.hidden = not s.hidden
		Print(T("pins", OnOff(not s.hidden)))
	elseif cmd == "herb" or cmd == "ore" or cmd == "treasure" then
		s.show[cmd] = not s.show[cmd]
		Print(T("filter", T(cmd), OnOff(s.show[cmd])))
	elseif cmd == "mine" then
		s.onlyMine = not s.onlyMine
		Print(T("only_mine", OnOff(s.onlyMine)))
	elseif cmd == "size" then
		local n = tonumber(arg)
		if n and n >= 8 and n <= 40 then
			s.size = math.floor(n)
			Print(T("size_set", s.size))
		else
			Print(T("size_bad"))
		end
	elseif cmd == "announce" then
		s.announce = not s.announce
		Print(T("announce", OnOff(s.announce)))
	elseif cmd == "stats" then
		Stats()
	elseif cmd == "clear" then
		local mapID = C_Map.GetBestMapForUnit("player")
		if not YES[arg] then
			Print(T("clear_confirm", mapID and MapName(mapID) or "?"))
		elseif mapID then
			db.nodes[mapID] = nil
			Print(T("cleared", MapName(mapID)))
		end
	elseif cmd == "reset" then
		if not YES[arg] then
			Print(T("reset_confirm"))
		else
			db.nodes = {}
			Print(T("reset_done"))
		end
	elseif cmd == "lang" then
		if LOCALES[arg] then
			s.lang = arg
			Print(T("lang_set"))
		else
			Print(T("lang_bad"))
		end
	elseif cmd == "accents" then
		s.accents = not s.accents
		Print(T("accents", OnOff(s.accents)))
	end
	RefreshMap()
end

-- Klikniecie w menu addonow (ikona przy minimapie)
function Odkrywca_OnAddonCompartmentClick()
	if not db then return end
	db.settings.hidden = not db.settings.hidden
	Print(T("pins", OnOff(not db.settings.hidden)))
	RefreshMap()
end

------------------------------------------------------------------------
-- Zdarzenia
------------------------------------------------------------------------

local frame = CreateFrame("Frame")
frame:RegisterEvent("ADDON_LOADED")
frame:RegisterEvent("PLAYER_LOGIN")
frame:RegisterEvent("UNIT_SPELLCAST_SENT")
frame:RegisterEvent("UNIT_SPELLCAST_SUCCEEDED")
frame:RegisterEvent("LOOT_READY")

frame:SetScript("OnEvent", function(_, event, ...)
	if event == "ADDON_LOADED" then
		local name = ...
		if name == ADDON_NAME then
			InitDB()
		elseif name == "Blizzard_WorldMap" then
			AttachToWorldMap()
		end
	elseif event == "PLAYER_LOGIN" then
		if not db then InitDB() end
		charKey = (UnitName("player") or "?") .. "-" .. (GetRealmName() or "?")
		BuildSpellTables()
		AttachToWorldMap()
	elseif event == "UNIT_SPELLCAST_SENT" then
		OnSpellcastSent(...)
	elseif event == "UNIT_SPELLCAST_SUCCEEDED" then
		OnSpellcastSucceeded(...)
	elseif event == "LOOT_READY" then
		OnLootReady()
	end
end)
