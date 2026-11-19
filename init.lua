plugin = {
    name = "cosmetic-denicker",
    displayName = "Cosmetic Denicker",
    command = "cd",
    prefix = "§dCD",
    version = "0.1.3",
    minStarfishVersion = "0.1.0-beta.19",
    description = "Beta. Spots nicked players' cosmetics and finds who they are after the game",
    readme = [[
Spots the cosmetics nicked players use in Bed Wars and helps find who they are.

**Setup**
1. Get an Aurora API key and set it with `/cd key <key>`.
2. Turn on **Auto Block Nicks**. A nick must be on your block list for `/profile` to confirm who it is.

**After a game** you get a list of nicks and their cosmetics. **[Search]** asks Aurora for players with those cosmetics, then checks each one with `/profile` in a lobby. The profile menu shows "Unblock Player" for the real account.

Unresolved nicks stay in `/cd saved` until found or removed. Removing one also unblocks it.

**Commands:** `/cd list` (last game), `/cd saved`, `/cd search <nick>`, `/cd remove <nick>`, `/cd clear confirm`, `/cd key <key>`, `/cd stop`.
]],
    dependencies = {
        { name = "hypixel-mod-api" },
        { name = "denicker", optional = true },
    },
}

local D = require("data")

-- Starfish leaves out the block of blockdust particles (and sends Blood's
-- trail without sparks), so the bare name counts.
table.insert(D.TRAIL_SIGNS, { ids = { "projectiletrail_blood" }, min = { blockdust = 30 }, confirmed = true })

-- Mobs (and lightning, "L") that kill effects and bed destroys spawn where
-- they play, keyed by 1.8 mob id. A sign that fits wins; this is next.
-- maybe: why it's only a guess. adultOnly: babies mean something else.
-- babyIds: only babies. manyIds/manyAt: that many grown at once.
-- unnamedOnly: a named mob (a bought Dream Defender) doesn't count.
local FX_MOBS = {
    kill = {
        [92] = { ids = { "killeffect_cow_rocket" } },
        [90] = { ids = { "killeffect_pigsmash" }, adultOnly = true, maybe = "a pig with no hearts seen - Pig Smash shows hearts too" },
        [94] = { ids = { "killeffect_squid_missile" } },
        [68] = { ids = { "killeffect_guardian_rocket" } },
        [101] = { ids = { "killeffect_bunny_explosion" } },
        [99] = { ids = { "killeffect_golemyeet" }, unnamedOnly = true },
        [93] = { ids = { "killeffect_hatching_eggs" }, babyIds = { "killeffect_chicken_tower" }, anyCount = true },
        L = { ids = { "killeffect_lighting_strike" } },
        [65] = { ids = { "killeffect_blood_bats", "killeffect_draculas_flight", "killeffect_batcrux" }, maybe = "several effects use bats" },
    },
    bed = {
        [90] = { ids = { "beddestroy_pig_missile" }, babyIds = { "beddestroy_pigsplosion" }, manyIds = { "beddestroy_pigsplosion" }, manyAt = 3 },
        [94] = { ids = { "beddestroy_squid_missile" } },
        L = { ids = { "beddestroy_lighting_strike" } },
    },
}
-- Riding victory dances: the mob the winner rides.
for typ, ids in pairs({ [63] = "victorydance_dragon_rider", [64] = "victorydance_wither_rider", [56] = "victorydance_ghast_rider",
    [100] = "victorydance_yeehaw", [68] = "victorydance_elder_guardian_rider", [93] = "victorydance_chicken_rider" }) do
    D.DANCE_RIDES[typ] = D.DANCE_RIDES[typ] or { ids = { ids }, confirmed = true }
end

-- Constants

local SIGN_MS = 3000          -- what shows up this long after a kill/bed line counts for it
local EARLY_MS = 1000         -- ...and this long before it
local SIGN_BLOCKS = 8         -- this far from the spot (flat)
local MAX_UP = 60
local CLEAR_BLOCKS = 16       -- another final/bed this close makes it a maybe
local TRAIL_MS = 3000
local TRAIL_BLOCKS = 2.5
local SHOOTER_BLOCKS = 3      -- a shot's shooter: the player this close to where it appeared
local TWIN_MS = 150
local HEAL_POOL_PUFF = 40
local MENU_WAIT_MS = 5000
local MENU_SETTLE_MS = 600
local LOBBY_SETTLE_MS = 2500
local BLOCK_GAP_MS = 1500
local DANCE_WAIT_MS = 10000   -- a victory dance is judged this long after the game ends
local AURORA_URL = "https://api.bordic.xyz/v3/lookup/players"

local FIREBALLS = { [63] = true, [64] = true }
local FIREBALL_OWN = { explode = true, largeexplode = true, hugeexplosion = true, smoke = true }
local FIREBALL_BLAST = { "explode", "largeexplode", "hugeexplosion", "smoke", "largesmoke" }
local COLOURED = { reddust = true, mobSpell = true, mobSpellAmbient = true, note = true }
local TRAIL_SKIP_ITEMS = { [264] = true, [265] = true, [266] = true, [388] = true }

-- Item ids (Starfish names them, the signs number them).
local ITEM_IDS = {
    packed_ice = 174, egg = 344, cookie = 357, gold_block = 41, gold_ingot = 266, pumpkin_pie = 400,
    lit_pumpkin = 91, pumpkin = 86, beef = 363, cooked_beef = 364, leather = 334, dye = 351, bone = 352,
    skull = 397, string = 287, fire_charge = 385, netherbrick = 405, golden_apple = 322, spider_eye = 375,
    leather_helmet = 298, leather_chestplate = 299, leather_leggings = 300, leather_boots = 301,
    paper = 339, name_tag = 421, coal = 263, diamond = 264, iron_ingot = 265, emerald = 388, hopper = 154,
}

-- Starfish entity kinds -> object/mob names used by the signs.
local KIND_ALIASES = {
    ["armor stand"] = "armor stand", ["firework rocket"] = "firework", ["fireworks rocket"] = "firework",
    ["firework"] = "firework", ["tnt"] = "tnt", ["primed tnt"] = "tnt", ["experience orb"] = "xp orb",
    ["xp orb"] = "xp orb", ["falling block"] = "falling block", ["falling sand"] = "falling block",
    ["item"] = "item", ["snowball"] = "snowball", ["fireball"] = "fireball", ["large fireball"] = "fireball",
    ["small fireball"] = "small fireball", ["egg"] = "egg", ["arrow"] = "arrow", ["ender dragon"] = "ender dragon",
}
local SHOT_TYPES = { arrow = 60, snowball = 61, egg = 62, fireball = 63, ["small fireball"] = 64 }
local OBJECTS = { ["armor stand"] = true, firework = true, tnt = true, ["xp orb"] = true, ["falling block"] = true,
    item = true, snowball = true, fireball = true, ["small fireball"] = true, egg = true, arrow = true }

local KINDS = {
    effect = { field = "activekilleffect", prefix = "killeffect_", label = "Kill effect" },
    bed = { field = "activebeddestroy", prefix = "beddestroy_", label = "Bed destroy" },
    trail = { field = "activeprojectiletrail", prefix = "projectiletrail_", label = "Trail" },
    killmsg = { field = "activekillmessages", prefix = "killmessages_", label = "Kill messages" },
    deathcry = { field = "activedeathcry", prefix = "deathcry_", label = "Death cry" },
    dance = { field = "activevictorydance", prefix = "victorydance_", label = "Victory dance" },
    glyph = { field = "activeglyph", prefix = "glyph_", label = "Glyph" },
    npc = { field = "activenpcskin", prefix = "npcskin_", label = "Shopkeeper" },
    topper = { field = "activeislandtopper", prefix = "islandtopper_", label = "Island topper" },
    figurine = { field = "active_figurine", prefix = "figurine_", label = "Figurine" },
    wood = { field = "activewoodtype", prefix = "woodSkin_", label = "Wood skin" },
}
local KIND_ORDER = { "effect", "bed", "trail", "killmsg", "deathcry", "dance", "glyph", "npc", "topper", "figurine", "wood" }

-- Config schema

starfish.schema.section({
    key = "summary",
    label = "After Each Game",
    description = "List the nicks you played with and the cosmetics they showed.",
    settings = {
        { key = "summary.enabled", type = "toggle", default = true, label = "Enabled", description = "Show the list after each game." },
        { key = "summary.resolved", type = "toggle", default = true, label = "Show Known Nicks", description = "List nicks already identified." },
        { key = "summary.maybes", type = "toggle", default = true, label = "Show Guesses", description = "Show unsure cosmetics." },
    },
})

starfish.schema.section({
    key = "lookup",
    label = "Aurora Lookup",
    description = "Search Aurora for players with a nick's cosmetics after the game.",
    settings = {
        { key = "lookup.auto", type = "toggle", default = false, label = "Auto Search", description = "Search nicks after each game." },
        { key = "lookup.key", type = "text", default = "", label = "Aurora Key", description = "Your Aurora API key.", setCommand = "/cd key" },
        { key = "lookup.max", type = "cycle", default = 20, label = "Max Candidates", description = "Players checked per nick.", values = {
            { text = "10", value = 10 }, { text = "20", value = 20 }, { text = "30", value = 30 },
        } },
    },
})

starfish.schema.section({
    key = "profile",
    label = "Profile Check",
    description = "Confirm candidates with /profile. Needs Auto Block.",
    settings = {
        { key = "profile.enabled", type = "toggle", default = true, label = "Enabled", description = "Check Aurora's candidates with /profile." },
        { key = "profile.gap", type = "cycle", default = 1500, label = "Check Delay", description = "Time between /profile checks.", values = {
            { text = "1s", value = 1000 }, { text = "1.5s", value = 1500 }, { text = "2s", value = 2000 }, { text = "3s", value = 3000 },
        } },
        { key = "profile.unblock", type = "toggle", default = true, label = "Unblock When Found", description = "Unblock the nick once identified." },
    },
})

starfish.schema.section({
    key = "autoBlock",
    label = "Auto Block Nicks",
    description = "Block nicks during the game.",
    settings = {
        { key = "autoBlock.enabled", type = "toggle", default = false, label = "Enabled", description = "Block nicks so they can be identified." },
    },
})

starfish.config.defaults({ blocked = {}, trace = {}, saved = {}, hinted = false })

-- Small helpers

local function now() return starfish.time.monotonic() end
local function plain(s) return starfish.text.plain(s or "") end
local function lower(s) return (s or ""):lower() end

local function flat(a, b)
    local dx, dz = a.x - b.x, a.z - b.z
    return math.sqrt(dx * dx + dz * dz)
end

local function dist(a, b)
    local dx, dy, dz = a.x - b.x, a.y - b.y, a.z - b.z
    return math.sqrt(dx * dx + dy * dy + dz * dz)
end

local function posOf(t)
    if not t then return nil end
    if t.position then return { x = t.position.x, y = t.position.y, z = t.position.z } end
    if t.x then return { x = t.x, y = t.y, z = t.z } end
    return nil
end

local function uuidVersion(uuid)
    local u = uuid and tostring(uuid):gsub("-", "")
    return u and #u >= 13 and u:sub(13, 13) or nil
end

local function shown(kind, id)
    if id == "random_cosmetic" then return "Random" end
    if id == "random_favorite_cosmetic" then return "Random favorite" end
    local prefix = KINDS[kind] and KINDS[kind].prefix or ""
    if id:sub(1, #prefix):lower() == prefix:lower() then id = id:sub(#prefix + 1) end
    id = id:gsub("_", " ")
    return (id:gsub("^%l", string.upper))
end

local function idsText(kind, ids)
    local out = {}
    for _, id in ipairs(ids) do out[#out + 1] = shown(kind, id) end
    return table.concat(out, " or ")
end

local KIND_TAGS = { effect = "Kill", bed = "Bed", trail = "Trail", killmsg = "Msg", deathcry = "Cry", dance = "Dance",
    glyph = "Glyph", npc = "NPC", topper = "Topper", figurine = "Fig", wood = "Wood" }

local function setOf(list)
    local s = {}
    for _, v in ipairs(list) do s[v] = true end
    return s
end

local function component(text, hover, command, suggest)
    local c = starfish.text.of(text)
    if hover then c = c:hover(hover) end
    if command then c = c:run(command) end
    if suggest then c = c:suggest(suggest) end
    return c
end

-- Denicker (optional): resolved names

local function denicker()
    return starfish.plugins.optional("denicker")
end

local foundByUs = {} -- nick (lower) -> real name, found with /profile

local function realNameOf(nick)
    if nick and foundByUs[nick:lower()] then return foundByUs[nick:lower()] end
    local dn = denicker()
    local ok, real = pcall(function() return dn and dn.getRealName(nick) end)
    return ok and real or nil
end

-- Location

local location = { inGame = false, inLobby = false, server = nil, inBedwars = false }
local game = nil       -- the game being played
local X = nil          -- extras.lua
local recentGames = {} -- the few games before lastGame
local lastGame = nil   -- the one before (for /cd and lookups)

-- Saved nicks: every unresolved nick stays here until it's found or removed.
local SAVED_MAX = 200
local function copy(v)
    if type(v) ~= "table" then return v end
    local t = {}
    for k, x in pairs(v) do t[k] = copy(x) end
    return t
end
local function savedList() return starfish.config.get("saved") or {} end
local function unsave(name)
    local s = savedList()
    if not s[name:lower()] then return false end
    s[name:lower()] = nil
    starfish.config.set("saved", s)
    return true
end
local savedSeq = 0
local function saveNicks(g)
    local s = savedList()
    for _, e in pairs(s) do if (e.seq or 0) > savedSeq then savedSeq = e.seq end end
    for _, key in ipairs(g.order) do
        local n = g.nicks[key]
        if not (n.real or realNameOf(n.name)) and (next(n.clues) or next(n.numbers or {}) or n.killPacks) then
            savedSeq = savedSeq + 1
            s[key] = { name = n.name, uuid = n.uuid, clues = copy(n.clues), killPacks = copy(n.killPacks), killConflict = n.killConflict or nil, numbers = copy(n.numbers or {}), seq = savedSeq, saved = true }
        end
    end
    local keys = {}
    for k in pairs(s) do keys[#keys + 1] = k end
    if #keys > SAVED_MAX then
        table.sort(keys, function(a, b) return (s[a].seq or 0) < (s[b].seq or 0) end)
        for i = 1, #keys - SAVED_MAX do s[keys[i]] = nil end
    end
    starfish.config.set("saved", s)
end

-- Players

local function meName()
    local me = starfish.players.me()
    return me and me.name
end

local function playerPos(name)
    local p = starfish.players.byName(name)
    if not p or not p.entityId then return nil end
    local e = starfish.entities.byId(p.entityId)
    return e and posOf(e)
end

local function isNick(player)
    if not player or not player.name or player.name == meName() then return false end
    if uuidVersion(player.uuid) == "1" then return true end
    local dn = denicker()
    local ok, nicked = pcall(function() return dn and dn.isNicked(player.name) end)
    return ok and nicked == true
end

local function noteNick(g, player)
    if not g or not isNick(player) then return nil end
    local key = lower(player.name)
    local n = g.nicks[key]
    if not n then
        n = { name = player.name, uuid = player.uuid, clues = {}, killPacks = nil, killConflict = false, numbers = {} }
        -- Seen before and still unresolved: keep what earlier games found.
        local old = savedList()[lower(player.name)]
        if old then
            for kind, toks in pairs(old.clues or {}) do
                n.clues[kind] = {}
                for tok, c in pairs(toks) do
                    local cc = copy(c)
                    cc.carried = true
                    n.clues[kind][tok] = cc
                end
            end
            n.numbers = copy(old.numbers or {})
            n.killPacks = copy(old.killPacks)
            n.killConflict = old.killConflict or false
        end
        g.nicks[key] = n
        g.order[#g.order + 1] = key
    end
    return n
end

local function nickByName(g, name)
    if not g or not name then return nil end
    local n = g.nicks[lower(name)]
    if n then return n end
    return noteNick(g, starfish.players.byName(name))
end

local function scanTab(g)
    for _, p in ipairs(starfish.players.all()) do noteNick(g, p) end
end

-- Clues

local function addClue(g, name, kind, ids, sure, why)
    local n = nickByName(g, name)
    if not n then return end
    local token = table.concat(ids, "|")
    n.clues[kind] = n.clues[kind] or {}
    local c = n.clues[kind][token]
    if not c then
        c = { ids = ids, sure = false, why = nil, count = 0 }
        n.clues[kind][token] = c
    end
    c.count = c.count + 1
    c.carried = nil
    if sure then c.sure = true; c.why = nil elseif not c.sure then c.why = why end
    starfish.log.debug(("%s: %s %s (%s)"):format(n.name, kind, token, sure and "sure" or (why or "maybe")))
end

local function removeClue(g, name, kind, token)
    local n = g and g.nicks[lower(name)]
    local c = n and n.clues[kind] and n.clues[kind][token]
    if c and not c.carried then n.clues[kind][token] = nil end
end

local function clearKind(g, name, kind)
    local n = g and g.nicks[lower(name)]
    if not (n and n.clues[kind]) then return end
    for tok, c in pairs(n.clues[kind]) do if not c.carried then n.clues[kind][tok] = nil end end
    if next(n.clues[kind]) == nil then n.clues[kind] = nil end
end

-- Kill messages: each pack's lines, matched without patterns (Lua has no alternation)

local MOBS = { "Iron Golem", "Golem", "Silverfish", "Bed Bug" }

local function compileTemplate(line)
    local parts = {}
    local text = line:gsub("%[([0-9a-fk-or]):([^%]]+)%]", "%2")
    text = text:gsub("[%.!]$", "")
    local i = 1
    while i <= #text do
        local s, e, ph = text:find("{(%u+)}", i)
        if not s then parts[#parts + 1] = { lit = text:sub(i) }; break end
        if s > i then parts[#parts + 1] = { lit = text:sub(i, s - 1) } end
        parts[#parts + 1] = { ph = ph }
        i = e + 1
    end
    return parts
end

local TEMPLATES = {}
for pack, lines in pairs(D.KILL_PACKS) do
    for _, line in ipairs(lines) do
        TEMPLATES[#TEMPLATES + 1] = { pack = pack, bed = line:sub(1, 5) == "{BED}", parts = compileTemplate(line) }
    end
end

local function isNameChar(c) return c:match("[%w_]") ~= nil end

local function matchParts(parts, pi, s, si, out)
    if pi > #parts then return si > #s end
    local p = parts[pi]
    if p.lit then
        if s:sub(si, si + #p.lit - 1) ~= p.lit then return false end
        return matchParts(parts, pi + 1, s, si + #p.lit, out)
    end
    if p.ph == "V" or p.ph == "K" then
        local j = si
        while j <= #s and j - si < 16 and isNameChar(s:sub(j, j)) do j = j + 1 end
        for e = j - 1, si, -1 do
            if matchParts(parts, pi + 1, s, e + 1, out) then
                out[p.ph] = s:sub(si, e)
                return true
            end
        end
        return false
    end
    if p.ph == "N" then
        local j = si
        while j <= #s and s:sub(j, j):match("[%d,]") do j = j + 1 end
        for e = j - 1, si, -1 do
            if matchParts(parts, pi + 1, s, e + 1, out) then out.N = s:sub(si, e); return true end
        end
        return false
    end
    if p.ph == "MOB" then
        for _, mob in ipairs(MOBS) do
            if s:sub(si, si + #mob - 1) == mob and matchParts(parts, pi + 1, s, si + #mob, out) then return true end
        end
        return false
    end
    if p.ph == "BED" then
        local start = si
        if s:sub(si, si + 17) == "BED DESTRUCTION > " then start = si + 18 end
        local e = s:find(" Bed", start, true)
        while e do
            if matchParts(parts, pi + 1, s, e + 4, out) then return true end
            e = s:find(" Bed", e + 1, true)
        end
        return false
    end
    return false
end

local function readKillLine(line, raw)
    local body = line:gsub(" FINAL KILL!$", "")
    if not body:match("[%.!]$") then return nil end
    body = body:sub(1, -2)
    local hits = {}
    for _, t in ipairs(TEMPLATES) do
        local out = {}
        if matchParts(t.parts, 1, body, 1, out) and out.K then
            hits[#hits + 1] = { t = t, killer = out.K, victim = out.V, number = out.N }
        end
    end
    if #hits == 0 then return nil end
    local killer = hits[1].killer
    local packs, seen, number = {}, {}, nil
    for _, h in ipairs(hits) do
        if h.killer == killer and not seen[h.t.pack] then
            seen[h.t.pack] = true
            packs[#packs + 1] = h.t.pack
            number = number or h.number
        end
    end
    return { killer = killer, victim = hits[1].victim, packs = packs, bed = hits[1].t.bed,
        number = number and tonumber((number:gsub(",", ""))) or nil }
end

local function noteKillPacks(g, hit)
    local n = nickByName(g, hit.killer)
    if not n then return end
    if hit.number then
        local stat = hit.bed and "beds" or "finals"
        n.numbers[stat] = math.max(n.numbers[stat] or 0, hit.number)
    end
    if n.killConflict then return end
    if not n.killPacks then
        n.killPacks = setOf(hit.packs)
        return
    end
    local both = {}
    for _, p in ipairs(hit.packs) do if n.killPacks[p] then both[#both + 1] = p end end
    if #both > 0 then n.killPacks = setOf(both) else n.killConflict = true end
end

-- Effects at a kill or bed break: what appears there, counted

local function fits(ev, pos, at)
    if not ev.pos or at < ev.at - (ev.early or EARLY_MS) or at > ev.at + (ev.window or SIGN_MS) then return false end
    if flat(ev.pos, pos) > (ev.radius or SIGN_BLOCKS) then return false end
    local up = pos.y - ev.pos.y
    return up >= (ev.minUp or -5) and up <= (ev.maxUp or MAX_UP)
end

local function tally(kind, name, pos, count)
    local g = game
    if not g or not pos then return end
    local t = now()
    local key = kind .. ":" .. name
    local recent = g.recent
    recent[#recent + 1] = { key = key, pos = pos, count = count, at = t }
    local head = g.recentHead or 1
    while head <= #recent and (t - recent[head].at > EARLY_MS or #recent - head >= 3000) do
        head = head + 1
    end
    if head > 512 then
        local moved = {}
        for i = head, #recent do moved[#moved + 1] = recent[i] end
        g.recent, head = moved, 1
    end
    g.recentHead = head
    for i = #g.events, 1, -1 do
        local ev = g.events[i]
        if t - ev.at > (ev.window or SIGN_MS) + 1000 then
            if not ev.window then break end
        elseif not (g.endAt and t > g.endAt + 250) and fits(ev, pos, t) then
            ev.features[key] = (ev.features[key] or 0) + count
        end
    end
end

local function signCount(features, key)
    if key:sub(-1) ~= "*" then return features[key] or 0 end
    local head, n = key:sub(1, -2), 0
    for k, v in pairs(features) do if k:sub(1, #head) == head then n = n + v end end
    return n
end

local function signFits(features, sign)
    if sign.colours then
        local n = 0
        for k, v in pairs(features) do
            if k:sub(1, 24) == "particle:reddust colour " and v >= 20 then n = n + 1 end
        end
        if n < sign.colours then return false end
    end
    for k, v in pairs(sign.min or {}) do if signCount(features, k) < v then return false end end
    for k, v in pairs(sign.max or {}) do if signCount(features, k) > v then return false end end
    return true
end

-- What the mobs at a kill or bed break mean (FX_MOBS), or nil.
local function mobMeaning(g, ev)
    local byType = FX_MOBS[ev.kind]
    if not byType or not g.mobs then return nil end
    local groups, order = {}, {}
    for _, m in ipairs(g.mobs) do
        if byType[m.type] and fits(ev, m.pos, m.at) then
            if not groups[m.type] then groups[m.type] = {}; order[#order + 1] = m.type end
            local meta = g.mobMeta[m.id] or {}
            local list = groups[m.type]
            list[#list + 1] = { baby = meta.baby, named = meta.named }
        end
    end
    local best
    for _, typ in ipairs(order) do
        local mean, list = byType[typ], groups[typ]
        local babies, named = 0, false
        for _, x in ipairs(list) do
            if x.baby then babies = babies + 1 end
            if x.named then named = true end
        end
        local grown = #list - babies
        local out
        if mean.unnamedOnly and named then
            out = nil
        elseif mean.manyIds and babies == 0 and grown >= mean.manyAt then
            out = { ids = mean.manyIds }
        elseif mean.babyIds then
            if babies > 0 and grown == 0 then out = { ids = mean.babyIds, maybe = mean.maybe }
            elseif babies == 0 and (grown == 1 or mean.anyCount) then out = { ids = mean.ids, maybe = mean.maybe }
            else
                local both = {}
                for _, id in ipairs(mean.ids) do both[#both + 1] = id end
                for _, id in ipairs(mean.babyIds) do both[#both + 1] = id end
                out = { ids = both, maybe = grown .. " grown and " .. babies .. " baby mobs appeared" }
            end
        elseif babies == 0 then
            if mean.adultOnly and grown ~= 1 then out = { ids = mean.ids, maybe = grown .. " appeared at once" }
            else out = { ids = mean.ids, maybe = mean.maybe } end
        end
        -- A sure meaning beats a guess.
        if out and (not best or (best.maybe and not out.maybe)) then best = out end
    end
    return best
end

local function judgeEvent(g, ev)
    if not ev.owner or not (ev.kind == "bed" or ev.final) then return end
    local matched = {}
    for _, sign in ipairs(D.FX_SIGNS) do
        if sign.kind == ev.kind and signFits(ev.features, sign) then matched[#matched + 1] = sign end
    end
    local learned = false
    if #matched == 0 then
        local m = mobMeaning(g, ev)
        if m then
            matched[1] = { ids = m.ids, confirmed = m.maybe == nil }
            ev.mobMaybe = m.maybe
        end
    end
    if #matched == 0 then
        -- Looks learned from real games (only when no sign fits).
        for _, sign in ipairs(D.LEARNED and D.LEARNED[ev.kind] or {}) do
            if signFits(ev.features, sign) then matched[#matched + 1] = { ids = sign.ids, confirmed = true } end
        end
        if #matched == 0 then return end
        learned = true
    end
    local ids, confirmed = {}, true
    if #matched == 1 then
        ids = matched[1].ids
        confirmed = matched[1].confirmed
    else
        -- Several matched: the ids they share, else all of them.
        local count = {}
        for _, s in ipairs(matched) do
            for _, id in ipairs(s.ids) do count[id] = (count[id] or 0) + 1 end
            confirmed = confirmed and s.confirmed
        end
        for id, c in pairs(count) do if c == #matched then ids[#ids + 1] = id end end
        if #ids == 0 then for id in pairs(count) do ids[#ids + 1] = id end end
        table.sort(ids)
    end
    local others = false
    for _, o in ipairs(g.events) do
        if o ~= ev and (o.final or o.kind == "bed") and not (o.kind == ev.kind and o.owner == ev.owner)
            and o.at >= ev.at - 1000 and o.at <= ev.at + SIGN_MS then
            if o.pos then
                if flat(o.pos, ev.pos) <= CLEAR_BLOCKS then others = true end
            elseif not (ev.me and dist(ev.me, ev.pos) <= 16) then
                others = true
            end
        end
    end
    local kind = ev.kind == "bed" and "bed" or "effect"
    if others then
        addClue(g, ev.owner, kind, ids, false, "another kill was close by")
    elseif not confirmed then
        addClue(g, ev.owner, kind, ids, false, ev.mobMaybe or "not confirmed yet")
    elseif #matched > 1 and #ids > 1 then
        addClue(g, ev.owner, kind, ids, false, "looks like more than one")
    else
        addClue(g, ev.owner, kind, ids, true)
    end
end

local function onKillLine(g, line, raw)
    -- A player's chat line is never a kill.
    if line:match("^[^:]-[%w_]+: ") and not line:match("^BED DESTRUCTION") then return end
    local final = line:sub(-12) == " FINAL KILL!"
    local hit = readKillLine(line, raw)
    local bed = hit and hit.bed or line:match("^BED DESTRUCTION > ") ~= nil
    if not hit and not final and not bed then return end
    if hit then noteKillPacks(g, hit) end
    local owner = hit and hit.killer or nil
    local victim = (not bed) and (line:match("^([%w_]+)") or nil) or nil
    local pos
    if bed and owner then
        local spot = g.breaking[lower(owner)]
        if spot and now() - spot.at < 3000 then pos = spot.pos else pos = playerPos(owner) end
    elseif victim then
        pos = g.lastPos[lower(victim)] or playerPos(victim)
        if not pos and lower(victim) == lower(meName() or "") then
            local me = starfish.players.me()
            pos = me and me.position and { x = me.position.x, y = me.position.y, z = me.position.z } or nil
        end
    end
    local me = starfish.players.me()
    local ev = { kind = bed and "bed" or "kill", final = final, owner = owner, at = now(), pos = pos,
        me = me and me.position and { x = me.position.x, y = me.position.y, z = me.position.z } or nil, features = {} }
    g.events[#g.events + 1] = ev
    if X then X.kill(g, ev, victim, final) end
    if not pos then return end
    for i = g.recentHead or 1, #g.recent do
        local r = g.recent[i]
        if r and fits(ev, r.pos, r.at) then ev.features[r.key] = (ev.features[r.key] or 0) + r.count end
    end
    starfish.timers.delay(SIGN_MS + 500, function()
        if game == g or lastGame == g then judgeEvent(g, ev) end
    end)
end

-- Projectile trails

local function shotAt(shot, at)
    if shot.known and at - shot.knownAt < 300 then return shot.known end
    local phys = D.TRAIL_OBJECTS[shot.type] or { gravity = 0.05, drag = 0.99 }
    local p = { x = shot.start.x, y = shot.start.y, z = shot.start.z }
    local v = { x = shot.vel.x, y = shot.vel.y, z = shot.vel.z }
    local ticks = math.min(100, math.floor((at - shot.at) / 50 + 0.5))
    for _ = 1, ticks do
        p.x, p.y, p.z = p.x + v.x, p.y + v.y, p.z + v.z
        v.x, v.y, v.z = v.x * phys.drag, v.y * phys.drag - phys.gravity, v.z * phys.drag
    end
    return p
end

local function nearestShot(g, pos)
    local best, bestDist = nil, TRAIL_BLOCKS
    local t = now()
    for _, shot in pairs(g.flying) do
        local d = dist(shotAt(shot, t), pos)
        if d <= bestDist then best, bestDist = shot, d end
    end
    return best
end

local function shooterNear(pos, shooterId)
    if shooterId and shooterId > 0 then
        for _, p in ipairs(starfish.players.all()) do
            if p.entityId == shooterId then return p.name end
        end
        for _, p in ipairs(starfish.players.all()) do
            if p.entityId == shooterId - 1 then return p.name end
        end
    end
    local best, bestDist = nil, SHOOTER_BLOCKS
    for _, p in ipairs(starfish.players.all()) do
        local pp = p.entityId and starfish.entities.byId(p.entityId)
        if pp and pp.position then
            local eye = { x = pp.position.x, y = pp.position.y + 1.5, z = pp.position.z }
            local d = dist(eye, pos)
            if d <= bestDist then best, bestDist = p.name, d end
        end
    end
    return best
end

local function trailCount(seen, k)
    if k:sub(-1) == "*" then
        local head, n = k:sub(1, -2), 0
        for key, v in pairs(seen) do if key:sub(1, #head) == head then n = n + v end end
        return n
    end
    local bar = k:find("|", 1, true)
    if not bar then return seen[k] or 0 end
    local colon = k:find(":", 1, true) or 0
    local kind, n = k:sub(1, colon), 0
    for id in k:sub(colon + 1):gmatch("[^|]+") do n = n + (seen[kind .. id] or 0) end
    return n
end

local function trailFits(seen, sign)
    for k, v in pairs(sign.min or {}) do if trailCount(seen, k) < v then return false end end
    for k, v in pairs(sign.max or {}) do if trailCount(seen, k) > v then return false end end
    if sign.anyOf then
        local hits = 0
        for _, k in ipairs(sign.anyOf) do if trailCount(seen, k) > 0 then hits = hits + 1 end end
        if hits < (sign.anyOfMin or 1) then return false end
    end
    if not sign.share then return true end
    local own, all = 0, 0
    for k, n in pairs(seen) do
        if k:find(" colour ", 1, true) then
            all = all + n
            if sign.min[k] then own = own + n end
        end
    end
    return own >= sign.share * all
end

local function endShot(g, shot)
    if shot.merged then return end
    g.flying[shot.id] = nil
    if shot.seen.hugeexplosion or shot.seen.largeexplode then
        for _, k in ipairs(FIREBALL_BLAST) do shot.seen[k] = nil end
    end
    for _, n in pairs(shot.hv) do
        if n >= HEAL_POOL_PUFF then
            local rest = (shot.seen.happyVillager or 0) - n
            shot.seen.happyVillager = rest > 0 and rest or nil
        end
    end
    if not shot.shooter or g.endAt or next(shot.seen) == nil then return end
    local seen = {}
    for k, v in pairs(shot.seen) do seen[k] = v end
    for k, v in pairs(shot.packing) do seen[k] = v end
    local signs = {}
    for _, sign in ipairs(D.TRAIL_SIGNS) do if trailFits(seen, sign) then signs[#signs + 1] = sign end end
    if #signs == 0 then
        for _, sign in ipairs(D.LEARNED and D.LEARNED.trail or {}) do
            if trailFits(shot.seen, sign) then signs[#signs + 1] = { ids = sign.ids, confirmed = true } end
        end
    end
    if #signs == 0 then return end
    local ids, got = {}, {}
    for _, s in ipairs(signs) do
        for _, id in ipairs(s.ids) do if not got[id] then got[id] = true; ids[#ids + 1] = id end end
    end
    local sure = false
    for _, s in ipairs(signs) do sure = sure or s.confirmed end
    -- (Two signs for the same trail are one match.)
    if #ids > 1 then addClue(g, shot.shooter, "trail", ids, false, "looks like more than one")
    elseif not sure then addClue(g, shot.shooter, "trail", ids, false, "not confirmed yet")
    else addClue(g, shot.shooter, "trail", ids, true) end
end

local function onShot(g, entityId, typeId, pos, data)
    local t = now()
    local vel = { x = 0, y = 0, z = 0 }
    local shooterId = nil
    if type(data) == "table" then
        local od = type(data.objectData) == "table" and data.objectData or nil
        shooterId = tonumber(data.shooterId or data.ownerId or data.intField or data.data or (od and (od.intField or od.data)))
        if type(data.velocity) == "table" then
            local w = data.velocity
            local x, y, z = tonumber(w.x) or 0, tonumber(w.y) or 0, tonumber(w.z) or 0
            -- Raw packet units are 1/8000 block per tick.
            if math.abs(x) > 10 or math.abs(y) > 10 or math.abs(z) > 10 then x, y, z = x / 8000, y / 8000, z / 8000 end
            vel = { x = x, y = y, z = z }
        else
            local src = od or data
            local function v(k) return (tonumber(src[k]) or 0) / 8000 end
            vel = { x = v("velocityX"), y = v("velocityY"), z = v("velocityZ") }
        end
    elseif type(data) == "number" then
        shooterId = data
    end
    local shooter = shooterNear(pos, shooterId)
    if shooter and shooter == meName() then shooter = nil end
    -- A thrown fireball comes with an arrow at the same spot: one throw.
    for _, o in pairs(g.flying) do
        if not o.merged and o.shooter == shooter and t - o.at <= TWIN_MS and dist(o.start, pos) <= 2 then
            if FIREBALLS[o.type] and typeId == 60 then return end
            if FIREBALLS[typeId] and o.type == 60 then o.merged = true; g.flying[o.id] = nil end
        end
    end
    local shot = { id = entityId, type = typeId, shooter = shooter, at = t, start = pos, vel = vel,
        known = nil, knownAt = 0, seen = {}, packing = {}, hv = {} }
    g.flying[entityId] = shot
    starfish.timers.delay(TRAIL_MS, function() endShot(g, shot) end)
end

local function trailParticle(g, name, e, pos, count)
    if next(g.flying) == nil then return end
    local shot = nearestShot(g, pos)
    if not shot then return end
    if (FIREBALLS[shot.type] and FIREBALL_OWN[name]) or name == "crit" then return end
    if name == "happyVillager" and count >= HEAL_POOL_PUFF then return end
    local key = name
    if (e.count or 0) == 0 and COLOURED[name] then key = name .. " colour " .. e.colour end
    shot.seen[key] = (shot.seen[key] or 0) + count
    local function pack(label) shot.packing[label] = (shot.packing[label] or 0) + 1 end
    if name == "fireworksSpark" then
        if count >= 5 then pack("fireworksSpark in fives") elseif count <= 1 then pack("fireworksSpark one by one") end
    elseif name == "lava" then
        if count == 2 then pack("lava in twos") elseif count <= 1 then pack("lava one by one") end
    elseif name == "mobSpell" and count == 3 then
        pack("mobSpell in threes")
    end
    if name == "happyVillager" then
        local moment = math.floor(now() / 100)
        shot.hv[moment] = (shot.hv[moment] or 0) + count
    end
end

-- World events in

local function colourOf(off)
    local function c(v) return math.floor(math.max(0, math.min(1, tonumber(v) or 0)) * 255 + 0.5) end
    off = off or {}
    return c(off.x) .. "," .. c(off.y) .. "," .. c(off.z)
end

starfish.events.on("world:particle", function(e)
    local g = game
    if not g then return end
    local pos = posOf(e)
    if not pos or type(e.particleId) ~= "number" then return end
    local name = D.PARTICLE_NAMES[e.particleId] or tostring(e.particleId)
    local count = math.max(1, e.count or 1)
    local key = name
    local d = type(e.data) == "table" and tonumber(e.data[1]) or nil
    if d and name == "iconcrack" then key = name .. "[" .. d .. "]"
    elseif d and (name == "blockcrack" or name == "blockdust") then key = name .. "[" .. (d % 4096) .. "]" end
    tally("particle", key, pos, count)
    e.colour = colourOf(e.offset)
    if (e.count or 0) == 0 and name == "reddust" then tally("particle", "reddust colour " .. e.colour, pos, count) end
    trailParticle(g, name, e, pos, count)
end)

starfish.events.on("world:sound", function(e)
    if not game or type(e.name) ~= "string" then return end
    local pos = posOf(e)
    local pitch = tonumber(e.pitch) or 0
    if pitch > 4 then pitch = pitch / 63 end
    tally("sound", e.name, pos, 1)
    tally("sound", e.name .. "@" .. string.format("%.1f", pitch), pos, 1)
end)

starfish.events.on("world:effect", function(e)
    if not game or type(e.effectId) ~= "number" or not e.position then return end
    local pos = { x = e.position.x + 0.5, y = e.position.y + 0.5, z = e.position.z + 0.5 }
    local data = tonumber(e.data) or 0
    local name = D.WORLD_EVENT_NAMES[e.effectId] or ("event " .. e.effectId)
    if e.effectId == 2001 then name = name .. " " .. (data % 4096) .. ":" .. math.floor(data / 4096)
    elseif data ~= 0 then name = name .. " [" .. data .. "]" end
    tally("event", name, pos, 1)
end)

local function kindName(kind)
    local k = tostring(kind or ""):gsub("^[%w_]+:", ""):gsub("_", " "):lower()
    return KIND_ALIASES[k] or k
end

-- 1.8 object and mob type numbers -> names
local OBJECT_KINDS = { [1] = "boat", [2] = "item", [10] = "minecart", [50] = "tnt", [51] = "ender_crystal",
    [60] = "arrow", [61] = "snowball", [62] = "egg", [63] = "fireball", [64] = "small_fireball",
    [65] = "ender_pearl", [66] = "wither_skull", [70] = "falling_block", [71] = "item_frame",
    [72] = "eye_of_ender", [73] = "potion", [75] = "xp_bottle", [76] = "firework_rocket",
    [77] = "leash_knot", [78] = "armor_stand", [90] = "fishing_hook" }
local MOB_KINDS = { [50] = "creeper", [51] = "skeleton", [52] = "spider", [53] = "giant", [54] = "zombie",
    [55] = "slime", [56] = "ghast", [57] = "zombie_pigman", [58] = "enderman", [59] = "cave_spider",
    [60] = "silverfish", [61] = "blaze", [62] = "magma_cube", [63] = "ender_dragon", [64] = "wither",
    [65] = "bat", [66] = "witch", [67] = "endermite", [68] = "guardian", [90] = "pig", [91] = "sheep",
    [92] = "cow", [93] = "chicken", [94] = "squid", [95] = "wolf", [96] = "mooshroom", [97] = "snow_golem",
    [98] = "ocelot", [99] = "iron_golem", [100] = "horse", [101] = "rabbit", [120] = "villager" }

-- What a spawned entity is, as "minecraft:<name>". Spawn events say "object" or
-- "mob" plus a type number; the tracked entity only says "minecraft:object".
local spawnKinds = {} -- entity id -> kind, for later events that only carry the id
local function spawnKind(e)
    local k = tostring(e.kind or "")
    local t = e.type or e.entityType or e.objectType or e.mobType
    local out
    if (k == "object" or k == "mob") and type(t) == "string" then out = t
    elseif k == "object" and tonumber(t) then out = "minecraft:" .. (OBJECT_KINDS[tonumber(t)] or ("object_" .. t))
    elseif k == "mob" and tonumber(t) then out = "minecraft:" .. (MOB_KINDS[tonumber(t)] or ("mob_" .. t))
    elseif k:find("weather", 1, true) or k:find("lightning", 1, true) then out = "minecraft:lightning_bolt"
    elseif k:find(":", 1, true) and k ~= "minecraft:object" and k ~= "minecraft:mob" then out = k
    else
        local ent = e.entityId and starfish.entities.byId(e.entityId)
        local bk = ent and ent.kind
        if type(bk) == "string" and bk ~= "minecraft:object" and bk ~= "minecraft:mob" then out = bk else out = k end
    end
    if e.entityId then spawnKinds[e.entityId] = out end
    return out
end
local MOB_NUMS = {}
for n, k in pairs(MOB_KINDS) do MOB_NUMS[k] = n end
MOB_NUMS.golem = 99; MOB_NUMS.villager_golem = 99; MOB_NUMS.entity_horse = 100; MOB_NUMS.mushroom_cow = 96

-- Baby (age below 0) and custom name, from a mob's metadata.
local function noteMobMeta(mm, md)
    for k, m in pairs(type(md) == "table" and md or {}) do
        local idx = type(m) == "table" and tonumber(m.index or m.key) or tonumber(k)
        local v = type(m) == "table" and m.value or m
        if idx == 12 and tonumber(v) then mm.baby = tonumber(v) < 0 end
        if idx == 2 and type(v) == "string" and plain(v):match("%S") then mm.named = true end
    end
end

local function kindOfId(id)
    if not id then return nil end
    if spawnKinds[id] then return spawnKinds[id] end
    local ent = starfish.entities.byId(id)
    return ent and ent.kind
end

local items = {} -- item entity id -> pos (counted once its stack arrives)

starfish.events.on("entity:spawn", function(e)
    local g = game
    if not g then return end
    local pos = posOf(e)
    if not pos then return end
    local name = kindName(spawnKind(e))
    if name:find("lightning", 1, true) then
        tally("lightning", "bolt", pos, 1)
        g.mobs[#g.mobs + 1] = { type = "L", pos = pos, at = now() }
        return
    end
    if name == "player" then return end
    if OBJECTS[name] then tally("object", name, pos, 1) else
        tally("mob", name, pos, 1)
        local typ = MOB_NUMS[name:gsub(" ", "_")]
        if typ and e.entityId and g.startAt then
            g.mobs[#g.mobs + 1] = { id = e.entityId, type = typ, pos = pos, at = now() }
            if #g.mobs > 400 then table.remove(g.mobs, 1) end
            g.mobMeta[e.entityId] = g.mobMeta[e.entityId] or {}
            noteMobMeta(g.mobMeta[e.entityId], e.metadata)
        end
    end
    if name == "item" then items[e.entityId] = { pos = pos, at = now() } end
    local shotType = SHOT_TYPES[name]
    if shotType and e.entityId then onShot(g, e.entityId, shotType, pos, e) end
end)

local function itemKey(item)
    local id = tostring(item.id or ""):gsub("^[%w_]+:", "")
    local num = tonumber(id) or ITEM_IDS[id] or D.ITEM_IDS[id]
    return num, item.name and plain(item.name) or nil
end

starfish.events.on("entity:metadata", function(e)
    local g = game
    local id = e.entity and e.entity.entityId
    local mm = g and id and g.mobMeta[id]
    if mm then noteMobMeta(mm, e.metadata) return end
    local it = id and items[id]
    if not g or not it or it.done then return end
    for _, m in ipairs(e.metadata or {}) do
        if type(m.value) == "table" and m.value.id then
            it.done = true
            local num, name = itemKey(m.value)
            it.num = num
            if num then
                tally("item", tostring(num), it.pos, 1)
                local shot = not TRAIL_SKIP_ITEMS[num] and nearestShot(g, it.pos)
                if shot then shot.seen["item:" .. num] = (shot.seen["item:" .. num] or 0) + 1 end
            end
            if name and name ~= "" then tally("itemname", name, it.pos, 1) end
            return
        end
    end
end)

starfish.events.on("entity:move", function(e)
    local g = game
    local ent = e.entity
    if not g or not ent then return end
    local shot = g.flying[ent.entityId]
    if shot then
        local live = starfish.entities.byId(ent.entityId)
        local p = posOf(e) or (live and posOf(live))
        if p then shot.known, shot.knownAt = p, now() end
        return
    end
    if ent.type == "player" and ent.uuid then
        local p = starfish.players.byUuid(ent.uuid)
        local live = starfish.entities.byId(ent.entityId)
        local pos = posOf(e) or (live and posOf(live))
        if p and pos then g.lastPos[lower(p.name)] = pos end
    end
end)

starfish.events.on("entity:despawn", function(e)
    for _, id in ipairs(e.entityIds or {}) do items[id] = nil; spawnKinds[id] = nil end
end)

-- A shot's speed comes in its own packet, just after the spawn.
starfish.events.on("entity:velocity", function(e)
    local g = game
    local id = e.entity and e.entity.entityId
    local shot = g and id and g.flying[id]
    local w = e.velocity
    if not shot or type(w) ~= "table" then return end
    local x, y, z = tonumber(w.x) or 0, tonumber(w.y) or 0, tonumber(w.z) or 0
    if math.abs(x) > 10 or math.abs(y) > 10 or math.abs(z) > 10 then x, y, z = x / 8000, y / 8000, z / 8000 end
    local t = now()
    shot.start = shot.known and now() - shot.knownAt < 300 and shot.known or shotAt(shot, t)
    shot.at, shot.vel = t, { x = x, y = y, z = z }
    shot.known = nil
end)

starfish.events.on("world:blockBreakAnimation", function(e)
    local g = game
    local ent = e.entity
    if not g or not ent or not ent.uuid then return end
    local p = starfish.players.byUuid(ent.uuid)
    if p then g.breaking[lower(p.name)] = { pos = { x = e.x + 0.5, y = e.y, z = e.z + 0.5 }, at = now() } end
end)

starfish.events.on("player:join", function(e)
    if game then noteNick(game, e) end
end)

-- The list after a game

local function bestClues(n, maybes)
    local out = {}
    for _, kind in ipairs(KIND_ORDER) do
        local best = nil
        for _, c in pairs(n.clues[kind] or {}) do
            if c.sure or maybes then
                if not best or (c.sure and not best.sure) or (c.sure == best.sure and c.count > best.count) then best = c end
            end
        end
        if best then out[#out + 1] = { kind = kind, clue = best } end
    end
    if n.killPacks and not n.killConflict then
        local packs = {}
        for p in pairs(n.killPacks) do if p ~= "killmessages_default" then packs[#packs + 1] = p end end
        table.sort(packs)
        if #packs > 0 and #packs <= 3 and (maybes or #packs == 1) then
            out[#out + 1] = { kind = "killmsg", clue = { ids = packs, sure = #packs == 1, why = #packs > 1 and "look-alike packs" or nil } }
        end
    end
    return out
end

-- One cosmetic (or none) is too little for Aurora to narrow down.
local function cosmeticCount(n)
    local count = 0
    for _, item in ipairs(bestClues(n, false)) do
        if item.clue.sure and #item.clue.ids == 1 then count = count + 1 end
    end
    return count
end

local function nickLine(g, n, short)
    local real = n.real or realNameOf(n.name)
    local clues = bestClues(n, starfish.config.get("summary.maybes"))
    local parts = {}
    local hover = { "§d" .. n.name .. (real and (" §8→ §a" .. real) or " §8(unresolved)") }
    for _, item in ipairs(clues) do
        local k, c = item.kind, item.clue
        local text = idsText(k, c.ids)
        parts[#parts + 1] = "§8" .. (KIND_TAGS[k] or k) .. " " .. (c.sure and "§f" or "§7") .. text .. (c.sure and "" or "?")
        hover[#hover + 1] = "§7" .. KINDS[k].label .. ": " .. (c.sure and "§f" or "§e") .. text .. (c.why and (" §8(" .. c.why .. ")") or "")
    end
    if n.numbers.finals then hover[#hover + 1] = "§7Finals: §f" .. n.numbers.finals end
    if n.numbers.beds then hover[#hover + 1] = "§7Beds: §f" .. n.numbers.beds end
    local head = component((real and "§a" or "§c") .. n.name .. (real and (" §8→ §a" .. real) or ""), table.concat(hover, "\n"))
    local line = head .. starfish.text.of(" §8· " .. (#parts > 0 and table.concat(parts, "§8, ") or "§8no cosmetics seen"))
    if not real and not short then
        if cosmeticCount(n) <= 1 then line = line .. starfish.text.of(" §8few clues") end
        line = line .. starfish.text.of(" ") .. component("§b[Search]", "§7Search Aurora and check with /profile", "/cd search " .. n.name)
        if n.saved then
            line = line .. starfish.text.of(" ") .. component("§7[Remove]", "§7Remove and unblock", "/cd remove " .. n.name)
        end
    end
    return line, #clues > 0
end

local function showSummary(g)
    if not g then return end
    local shownResolved = starfish.config.get("summary.resolved")
    local lines = {}
    for _, key in ipairs(g.order) do
        local n = g.nicks[key]
        n.real = n.real or realNameOf(n.name)
        if shownResolved or not n.real then lines[#lines + 1] = n end
    end
    if #lines == 0 then return false end
    starfish.chat.info("§f" .. #lines .. " nick" .. (#lines == 1 and "" or "s") .. " this game")
    for _, n in ipairs(lines) do starfish.chat.sendToClient(starfish.text.of(" ") .. nickLine(g, n)) end
    return true
end

-- Block list (only what this plugin sees)

local function setBlocked(name, on)
    local list = starfish.config.get("blocked") or {}
    local copy = {}
    for k, v in pairs(list) do copy[k] = v end
    copy[lower(name)] = on and true or nil
    starfish.config.set("blocked", copy)
end

local function isBlocked(name)
    return (starfish.config.get("blocked") or {})[lower(name)] == true
end

local blockQueue, blockBusy, blockBusyAt = {}, false, nil

local function pumpBlocks()
    if blockBusy or #blockQueue == 0 then return end
    blockBusy = true
    blockBusyAt = now()
    local item = table.remove(blockQueue, 1)
    starfish.chat.sendToServer(item:sub(1, 1) == "/" and item or ("/block add " .. item))
    starfish.timers.delay(BLOCK_GAP_MS, function() blockBusy = false; pumpBlocks() end)
end

local function queueUnblock(name)
    if not isBlocked(name) then return end
    blockQueue[#blockQueue + 1] = "/block remove " .. name
    pumpBlocks()
end

local function autoBlock(g)
    if not starfish.config.get("autoBlock.enabled") or not g or not g.startAt or not location.inGame then return end
    for _, key in ipairs(g.order) do
        local n = g.nicks[key]
        if not n.blockQueued and not isBlocked(n.name) and not realNameOf(n.name) then
            n.blockQueued = true
            blockQueue[#blockQueue + 1] = n.name
        end
    end
    pumpBlocks()
end

-- Lookups: Aurora, then /profile

local runs = {}       -- queue of { nick, candidates, index, ... }
local run = nil
local pending = nil   -- the /profile waiting for its menu
local nextTimer = nil
local menuTimeout
local awaitingBlock = {} -- nick -> run that stopped because it wasn't blocked
local lastBlockSend = nil -- { name, at }: undone if Hypixel refuses

local function cancel(sub) if sub then pcall(function() sub:off() end) end end
local seenWindows = {} -- menus already handled (Starfish can still report an old one as open)
local adopt, trace

local function status(text) starfish.chat.info(text) end

local function lookupBody(n)
    local body, used = {}, {}
    for _, item in ipairs(bestClues(n, false)) do
        local k, c = item.kind, item.clue
        if c.sure and #c.ids == 1 then
            body[KINDS[k].field] = c.ids[1]
            used[#used + 1] = KINDS[k].label .. " " .. shown(k, c.ids[1])
        end
    end
    if n.numbers.finals then body.final_kills = n.numbers.finals; used[#used + 1] = n.numbers.finals .. " finals" end
    if n.numbers.beds then body.beds_broken = n.numbers.beds; used[#used + 1] = n.numbers.beds .. " beds" end
    if #used == 0 then return nil end
    return body, used
end

local startChecking

local function finishRun(r, text)
    if run ~= r then return end
    if text then status(text) end
    run = nil
    cancel(nextTimer)
    starfish.timers.delay(500, function()
        if not run and #runs > 0 then run = table.remove(runs, 1); startChecking(run) end
    end)
end

local function checkNext(r)
    r.nextAt = nil
    if run ~= r or r.state ~= "checking" then return end
    if location.inGame then r.state = "paused"; status("§7Paused. Switch lobby to resume.") return end
    if r.index > #r.candidates then
        finishRun(r, "§7No match for §c" .. r.nick .. "§7 (" .. #r.candidates .. " checked).")
        return
    end
    local name = r.candidates[r.index]
    pending = { run = r, name = name, sentAt = now(), deadline = now() + MENU_WAIT_MS, windowId = nil, retries = r.retries or 0 }
    starfish.chat.sendToServer("/profile " .. name)
end

menuTimeout = function(p)
    local r, name = p.run, p.name
    trace("/profile " .. name .. ": no menu within 5s")
    pending = nil
    if run ~= r then return end
    r.retries = 0
    r.timeouts = (r.timeouts or 0) + 1
    if r.timeouts >= 3 then
        -- Three silent in a row: try those again next lobby.
        r.index = r.index - 2
        r.timeouts = 0
        r.state = "paused"
        status("§e/profile isn't answering. Switch lobby to resume.")
        return
    end
    r.unknown = r.unknown + 1
    r.index = r.index + 1
    r.nextAt = now() + (starfish.config.get("profile.gap") or 1500)
    nextTimer = starfish.timers.delay(starfish.config.get("profile.gap") or 1500, function() checkNext(r) end)
end

local function nextAfter(r)
    pending = nil
    r.index = r.index + 1
    r.retries = 0
    r.nextAt = now() + (starfish.config.get("profile.gap") or 1500)
    nextTimer = starfish.timers.delay(starfish.config.get("profile.gap") or 1500, function() checkNext(r) end)
end

startChecking = function(r)
    if run ~= r then return end
    if not starfish.config.get("profile.enabled") then
        local list = {}
        for i = 1, math.min(10, #r.candidates) do list[i] = r.candidates[i] end
        finishRun(r, "§7Candidates for §c" .. r.nick .. "§7: §f" .. table.concat(list, "§7, §f"))
        return
    end
    if not isBlocked(r.nick) then
        awaitingBlock[lower(r.nick)] = r
        local list = {}
        for i = 1, math.min(10, #r.candidates) do list[i] = r.candidates[i] end
        status("§7" .. r.nick .. " wasn't blocked in the game, so /profile can't check. Candidates: §f" .. table.concat(list, "§7, §f"))
        finishRun(r)
        return
    end
    if location.inGame or not location.inLobby then
        r.state = "paused"
        status("§7" .. #r.candidates .. " to check for §c" .. r.nick .. "§7. Waiting for a lobby.")
        return
    end
    r.state = "checking"
    status("§7Checking " .. #r.candidates .. " for §c" .. r.nick .. "§7...")
    checkNext(r)
end

local function finishMatch(r, real)
    finishRun(r, "§c" .. r.nick .. " §7is §a" .. real .. " §8(/profile)")
    foundByUs[lower(r.nick)] = real
    unsave(r.nick)
    for _, g in pairs({ a = game, b = lastGame }) do
        local n = g.nicks[lower(r.nick)]
        if n then n.real = real end
    end
    starfish.events.emit("cosmetic-denicker:resolved", { nickName = r.nick, realName = real })
    if starfish.config.get("profile.unblock") then
        queueUnblock(r.nick)
    end
end

local function search(n, quiet)
    if run and lower(run.nick) == lower(n.name) then return end
    for _, r in ipairs(runs) do if lower(r.nick) == lower(n.name) then return end end
    local key = starfish.config.get("lookup.key")
    if not key or key == "" then
        status("§cSet your Aurora key first: §f/cd key <key>")
        return
    end
    local body, used = lookupBody(n)
    if not body then
        if not quiet then status("§7Not enough clues for §c" .. n.name .. "§7.") end
        return
    end
    status("§7Searching §c" .. n.name .. "§7: §f" .. table.concat(used, "§7, §f"))
    -- Nobody found with everything: Aurora can be behind on a cosmetic, so
    -- the less certain ones are dropped one at a time.
    local DROP = { "final_kills", "beds_broken", "activewoodtype", "activedeathcry", "activeglyph", "activevictorydance", "active_figurine", "activeislandtopper", "activenpcskin" }
    local function ask(b)
        starfish.http.post(AURORA_URL .. "?key=" .. starfish.http.encodeUri(key), { body = b }, function(res)
            if not res.success or not res.data or type(res.data.data) ~= "table" then
                local why = ({ [401] = "Aurora rejected the key.", [403] = "Aurora refused this key.", [404] = "nobody found.",
                    [422] = "Aurora couldn't use those values.", [429] = "rate limited, try later." })[res.status or 0]
                if res.status ~= 404 then
                    status("§cAurora: " .. (why or (res.data and (res.data.cause or res.data.message)) or "error, try later."))
                    return
                end
                res.data = { data = {} }
            end
            local max = starfish.config.get("lookup.max") or 20
            local names, seen = {}, {}
            -- Aurora's stats can be behind, so an exact finals/beds match is rare:
            -- rank by how close their numbers are instead (never above the nick's).
            local rows = {}
            for i, c in ipairs(res.data.data) do if type(c) == "table" then rows[#rows + 1] = { c = c, i = i } end end
            local function gapOf(c)
                local gap, any = 0, false
                for _, f in ipairs({ { n.numbers.finals, tonumber(c.finals or c.final_kills) }, { n.numbers.beds, tonumber(c.beds or c.beds_broken) } }) do
                    if f[1] and f[2] then
                        any = true
                        local d = f[1] - f[2]
                        if d < -25 then return nil end
                        gap = gap + math.abs(d) / math.max(f[1], 1)
                    end
                end
                return any and gap or math.huge
            end
            if n.numbers.finals or n.numbers.beds then
                local kept = {}
                for _, r in ipairs(rows) do r.gap = gapOf(r.c); if r.gap then kept[#kept + 1] = r end end
                table.sort(kept, function(a, b2) if a.gap ~= b2.gap then return a.gap < b2.gap end return a.i < b2.i end)
                if #kept > 0 then rows = kept end
            end
            pcall(trace, ("Aurora for %s: %d rows, top %s"):format(n.name, #res.data.data, (function()
                local t = {}
                for i = 1, math.min(5, #rows) do local c = rows[i].c; t[#t + 1] = tostring(c.displayname or c.name) .. ":" .. tostring(c.finals or c.final_kills) end
                return table.concat(t, ",") end)()))
            for _, r in ipairs(rows) do
                local c = r.c
                local name = c.displayname or c.name or c.username
                if name and not seen[lower(name)] and #names < max then seen[lower(name)] = true; names[#names + 1] = name end
            end
            if #names == 0 then
                local fields = 0
                for _ in pairs(b) do fields = fields + 1 end
                for _, f in ipairs(DROP) do
                    if b[f] ~= nil and fields > 1 then
                        local nb = {}
                        for k, v in pairs(b) do if k ~= f then nb[k] = v end end
                        starfish.log.debug("Aurora: nobody with " .. f .. " - asking without it")
                        return ask(nb)
                    end
                end
                status("§7Aurora found nobody for §c" .. n.name .. "§7.")
                return
            end
            local r = { nick = n.name, candidates = names, index = 1, unknown = 0, state = "queued" }
            if run then runs[#runs + 1] = r else run = r; startChecking(r) end
        end)
    end
    ask(body)
end

local function autoLookups(g)
    if not starfish.config.get("lookup.auto") or not g then return end
    local key0 = starfish.config.get("lookup.key")
    if not key0 or key0 == "" then return end
    for _, key in ipairs(g.order) do
        local n = g.nicks[key]
        if not (n.real or realNameOf(n.name)) and lookupBody(n) and cosmeticCount(n) > 1 then search(n, true) end
    end
end

-- /profile replies

-- Menu trace: what /profile menus looked like, saved in the plugin's config
-- file ("trace") so a failed check can be looked at afterwards.
local traceBuf = {}
local traceDirty = false
trace = function(text)
    traceBuf[#traceBuf + 1] = os.date and (os.date("%H:%M:%S ") .. text) or text
    while #traceBuf > 80 do table.remove(traceBuf, 1) end
    traceDirty = true
    starfish.log.debug(text)
end
starfish.timers.interval(5000, function()
    if traceDirty then traceDirty = false; pcall(starfish.config.set, "trace", traceBuf) end
end)

local function safe(name, fn)
    return function(e)
        local ok, err = pcall(fn, e)
        if not ok then trace("ERROR in " .. name .. ": " .. tostring(err)) end
    end
end

-- Items can be tables or userdata, lists from 0 or 1, with holes.
local function eachItem(list, fn, size)
    if list == nil then return end
    local ok = pcall(function() for k, v in pairs(list) do fn(k, v) end end)
    if ok then return end
    for i = 0, (size or 90) do
        local got, v = pcall(function() return list[i] end)
        if got and v ~= nil then fn(i, v) end
    end
end

local function field(item, key)
    local ok, v = pcall(function() return item[key] end)
    return ok and v or nil
end

local function textOf(v)
    if v == nil then return "" end
    if type(v) == "string" then return plain(v) end
    local ok, t = pcall(plain, v)
    if ok and type(t) == "string" then return t end
    ok, t = pcall(starfish.text.legacy, v)
    return ok and type(t) == "string" and plain(t) or tostring(v)
end

local function itemText(item)
    -- (Menu items come with displayName and a numeric id.)
    local name = textOf(field(item, "name") or field(item, "displayName"))
    local lore = {}
    eachItem(field(item, "lore"), function(_, line) lore[#lore + 1] = textOf(line) end, 30)
    local id = tostring(field(item, "id") or "")
    id = ({ ["339"] = "paper", ["154"] = "hopper" })[id] or id
    return name, table.concat(lore, "\n"), id
end

local function classify(items)
    local verdict = "unknown"
    eachItem(items, function(_, item)
        if verdict ~= "unknown" or item == nil then return end
        local name, lore, id = itemText(item)
        name, lore = lower(name), lower(lore)
        id = id:gsub("^[%w_]+:", "")
        if name:find("block", 1, true) or lore:find("block list", 1, true) then
            if name:find("unblock", 1, true) or lore:find("remove .* from your block list") then verdict = "blocked"
            elseif name:find("block player", 1, true) or lore:find("add .* to your block list") then verdict = "not"
            elseif id == "paper" then verdict = "blocked"
            elseif id == "hopper" then verdict = "not" end
        end
    end)
    if verdict ~= "unknown" then return verdict end
    -- Names unreadable: go by the item alone (paper = Unblock, hopper = Block).
    local named, paper, hopper = false, false, false
    eachItem(items, function(_, item)
        if item == nil then return end
        local name, _, id = itemText(item)
        if name ~= "" then named = true end
        id = id:gsub("^[%w_]+:", "")
        if id == "paper" then paper = true elseif id == "hopper" then hopper = true end
    end)
    if not named then
        if paper and not hopper then return "blocked" end
        if hopper and not paper then return "not" end
    end
    return verdict
end

local function describe(items)
    local out, n = {}, 0
    eachItem(items, function(slot, item)
        n = n + 1
        local name, lore, id = itemText(item)
        if name:lower():find("block", 1, true) or lore:lower():find("block", 1, true) then
            out[#out + 1] = ("[%s] %s \"%s\" %s"):format(tostring(slot), id, name, lore:sub(1, 60))
        end
    end)
    return n .. " items" .. (#out > 0 and (": " .. table.concat(out, "; ")) or " (no block button)")
end

local function judgeMenu(windowId, final)
    local p = pending
    if not p or p.windowId ~= windowId then return end
    local okV, verdict = pcall(classify, p.items)
    if not okV then trace("ERROR classify: " .. tostring(verdict)); verdict = "unknown" end
    -- Items can come one slot at a time: wait for the block button a moment.
    if verdict == "unknown" and not final then
        p.settleAt = math.min(p.settleAt or math.huge, now() + MENU_SETTLE_MS)
        return
    end
    p.settleAt = nil
    pcall(starfish.client.window.closeWindow, windowId)
    local r = p.run
    local okD, desc = pcall(describe, p.items)
    trace(("/profile %s -> %s (%s)"):format(p.name, verdict, okD and desc or ("? " .. tostring(desc))))
    if run ~= r then pending = nil return end
    r.timeouts = 0
    if verdict == "blocked" then pending = nil; finishMatch(r, p.name) return end
    if verdict == "unknown" then r.unknown = r.unknown + 1 end
    nextAfter(r)
end

local function addItems(p, list, slot)
    if not p.itemsSeen then p.itemsSeen = true; trace("items arrived for " .. p.name .. (slot ~= nil and " (slot)" or " (list)")) end
    p.items = p.items or {}
    if slot ~= nil then
        p.items[slot] = list
        p.itemCount = (p.itemCount or 0) + 1
        return
    end
    eachItem(list, function(i, item)
        p.items[i] = item
        p.itemCount = (p.itemCount or 0) + 1
    end, p.slotCount)
end

-- A menu that shows up while a check waits is its answer.
adopt = function(p, windowId, how)
    if not windowId or windowId <= 0 or p.windowId == windowId then return end
    if p.windowId then
        -- Took an old menu for this one: the real one just opened.
        if how ~= "opened" or not p.polled then return end
        p.items, p.itemCount = nil, nil
    end
    p.polled = how ~= "opened"
    seenWindows[windowId] = true
    p.windowId = windowId
    trace(("menu %d for %s (%s, %dms after /profile)"):format(windowId, p.name, how, now() - p.sentAt))
    if p.early then
        for _, ev in ipairs(p.early) do if ev.windowId == windowId then addItems(p, ev.items, ev.slot) end end
        p.early = nil
    end
    -- No answer within 1.5 s: judge what came and move on.
    p.settleAt = now() + 1500
    if p.items then judgeMenu(windowId) end
end

-- One steady ticker drives the check (short-lived timers went missing live).
starfish.timers.interval(100, safe("ticker", function()
    local p = pending
    -- Backup in case a delay timer never fires.
    if not p and run and run.state == "checking" and run.nextAt and now() > run.nextAt + 2000 then
        local r = run
        r.nextAt = nil
        cancel(nextTimer)
        checkNext(r)
        return
    end
    if blockBusy and blockBusyAt and now() - blockBusyAt > BLOCK_GAP_MS + 2000 then blockBusy = false; pumpBlocks() end
    if not p or not p.deadline then return end
    if not p.windowId then
        local ok, id = pcall(function() return starfish.inventory.windowId() end)
        id = ok and tonumber(id)
        if id and id > 0 and not seenWindows[id] then adopt(p, id, "seen open") end
    end
    if p.windowId then
        if p.settleAt and now() >= p.settleAt then judgeMenu(p.windowId, true) end
    elseif now() >= p.deadline then
        menuTimeout(p)
    end
end))

starfish.events.on("inventory:windowOpen", safe("windowOpen", function(e)
    local p = pending
    if not p then return end
    local title = textOf(e.title)
    trace(("windowOpen id=%s title=%s slots=%s"):format(tostring(e.windowId), title, tostring(e.slotCount)))
    if p.windowId and not p.polled then return end
    -- A late menu for someone else isn't this answer.
    if title ~= "" and not lower(title):find(lower(p.name), 1, true) then
        seenWindows[tonumber(e.windowId) or -1] = true
        return
    end
    if now() - p.sentAt <= MENU_WAIT_MS then
        p.slotCount = tonumber(e.slotCount)
        adopt(p, tonumber(e.windowId), "opened")
    end
end))

starfish.events.on("inventory:windowItems", safe("windowItems", function(e)
    local p = pending
    if not p then return end
    local wid = tonumber(e.windowId)
    if wid == 0 then return end
    if p.windowId ~= wid then
        -- (Items before the open: kept until the menu is adopted.)
        p.early = p.early or {}
        p.early[#p.early + 1] = { windowId = wid, items = e.items }
        return
    end
    if p.windowId == wid then
        addItems(p, e.items)
        judgeMenu(wid)
    end
end))

starfish.events.on("inventory:slotUpdate", safe("slotUpdate", function(e)
    local p = pending
    local wid = tonumber(e.windowId)
    if not p or e.item == nil or wid == 0 or wid == -1 then return end
    if p.windowId ~= wid then
        p.early = p.early or {}
        p.early[#p.early + 1] = { windowId = wid, items = e.item, slot = e.slot or 0 }
        return
    end
    if p.windowId == wid then
        addItems(p, e.item, e.slot or ((p.itemCount or 0) + 1))
        judgeMenu(wid)
    end
end))

local function onProfileChat(text)
    local p = pending
    if not p or p.windowId or now() - p.sentAt > 5000 then return end
    if text:match("^[^:]-: ") then return end
    local r = p.run
    local l = lower(text)
    if l:find("find a player") or l:find("player not found") or l:find("does not exist") or l:find("no player")
        or l:find("profile is unavailable") or l:find("unavailable") then
        nextAfter(r)
    elseif l:find("slow down") or l:find("too fast") or l:find("please wait") or l:find("cooldown") then
        pending = nil
        r.retries = (r.retries or 0) + 1
        if r.retries > 2 then r.state = "paused"; status("§eHypixel says slow down - resuming next lobby.") return end
        nextTimer = starfish.timers.delay(5000, function() checkNext(r) end)
    elseif l:find("only use the social menu in lobbies") or l:find("can't use this here") then
        pending = nil
        r.state = "paused"
        status("§7Not in a lobby - resuming next lobby.")
    end
end

-- Island cosmetics, death cries, victory dances, glyphs, wood skins (extras.lua)

X = require("extras")({
    D = D, now = now, flat = flat, dist = dist, lower = lower, plain = plain, posOf = posOf, uuidVersion = uuidVersion,
    game = function() return game end, addClue = addClue, removeClue = removeClue, clearKind = clearKind,
    isNick = isNick, realNameOf = realNameOf, tally = tally, signFits = signFits,
    itemOf = function(id) local it = id and items[id]; return it and it.num end, spawnKind = spawnKind, kindOfId = kindOfId,
})

-- Chat in

starfish.events.on("chat:receive", function(e)
    if e.kind == "actionBar" then return end
    local raw = e.message or ""
    local text = plain(raw)
    local blocked = text:match("^Blocked ([%w_]+)%.$")
    if blocked then
        setBlocked(blocked, true)
        lastBlockSend = nil
        local r = awaitingBlock[lower(blocked)]
        if r then
            awaitingBlock[lower(blocked)] = nil
            r.index, r.unknown, r.state, r.timeouts = 1, 0, "queued", 0
            if run then runs[#runs + 1] = r else run = r; startChecking(r) end
        end
        return
    end
    if lastBlockSend and now() - lastBlockSend.at < 3000 and not text:find(":", 1, true) then
        local l = lower(text)
        if (l:find("can't", 1, true) or l:find("cannot", 1, true) or l:find("couldn't", 1, true) or l:find("not find", 1, true)
            or l:find("no player", 1, true) or l:find("full", 1, true) or l:find("maximum", 1, true)) and not l:find("already", 1, true) then
            trace("block refused: " .. lastBlockSend.name .. " (" .. text .. ")")
            setBlocked(lastBlockSend.name, false)
            lastBlockSend = nil
        end
    end
    local unblocked = text:match("^Unblocked ([%w_]+)%.$")
    if unblocked then setBlocked(unblocked, false) return end
    onProfileChat(text)
    if game and location.inGame then
        if not game.startAt and text:find("Protect your bed and destroy the enemy beds", 1, true) then X.start(game) end
        if game.startAt and not game.overAt and text:find("1st Killer %- ") then X.over(game) end
        onKillLine(game, text, raw)
    end
end)

starfish.events.on("chat:title", function(e)
    local text = plain(e.text or e.message or "")
    if game and game.startAt and not game.overAt and (text:find("VICTORY", 1, true) or text:find("GAME OVER", 1, true)) then X.over(game) end
end)

-- Location: a game starts, a game ends

local function newGame()
    for k in pairs(items) do items[k] = nil end
    for k in pairs(spawnKinds) do spawnKinds[k] = nil end
    return { nicks = {}, order = {}, events = {}, recent = {}, flying = {}, lastPos = {}, breaking = {}, mobs = {}, mobMeta = {}, endAt = nil, startedAt = now() }
end

local function endGame()
    local g = game
    if not g then return end
    game = nil
    g.endAt = now()
    for k in pairs(items) do items[k] = nil end
    -- A pregame left without playing (a dodge or /l) isn't a game.
    if not g.startAt then return end
    if next(g.nicks) == nil and lastGame then return end
    recentGames = recentGames or {}
    if lastGame then table.insert(recentGames, 1, lastGame) end
    while #recentGames > 5 do table.remove(recentGames) end
    lastGame = g
    saveNicks(g)
    -- Wait for the last effects (and the victory dance) to be judged.
    local wait = SIGN_MS + 1000
    if g.overAt then wait = math.max(wait, g.overAt + DANCE_WAIT_MS - now()) end
    starfish.timers.delay(wait, function()
        saveNicks(g)
        if starfish.config.get("summary.enabled") then showSummary(g) end
        local key = starfish.config.get("lookup.key")
        if next(g.nicks) and not starfish.config.get("hinted") and (not key or key == "" or not starfish.config.get("autoBlock.enabled")) then
            starfish.config.set("hinted", true)
            starfish.chat.info("§7Cosmetic Denicker: set §f/cd key§7 and turn on Auto Block.")
        end
        autoLookups(g)
        -- Only the nicks are needed from here on (once a dance has been judged).
        starfish.timers.delay(15000, function()
            g.events, g.recent, g.recentHead, g.flying, g.lastPos, g.breaking = {}, {}, 1, {}, {}, {}
        end)
    end)
end

local function applyLocation(loc)
    if not loc then return end
    local wasGame = location.inGame
    local changed = loc.serverName ~= location.server
    location.server = loc.serverName
    if changed then for k in pairs(seenWindows) do seenWindows[k] = nil end end
    location.inBedwars = loc.serverType == "BEDWARS"
    location.inGame = location.inBedwars and loc.lobbyName == nil and loc.mode ~= nil
    location.inLobby = loc.lobbyName ~= nil
    if wasGame and (changed or not location.inGame) then endGame() end
    if location.inGame and (changed or not game) then
        game = newGame()
        game.mode = loc.mode
        game.solo = tostring(loc.mode or ""):find("EIGHT_ONE", 1, true) ~= nil
        scanTab(game)
        starfish.timers.delay(5000, function() if game then scanTab(game) end end)
    end
    if location.inLobby and run and run.state == "paused" then
        local r = run
        starfish.timers.delay(LOBBY_SETTLE_MS, function()
            if run == r and r.state == "paused" and location.inLobby then startChecking(r) end
        end)
    end
end

starfish.events.on("hypixel:location", function(event)
    applyLocation(event.location)
end)

-- Auto block: once the game is under way, every few seconds
starfish.timers.interval(5000, function()
    if game and game.startAt and location.inGame then
        scanTab(game)
        autoBlock(game)
    end
end)

starfish.events.on("chat:send", function(e)
    local m = lower(e.message or "")
    local name = m:match("^/block add ([%w_]+)")
    if name then setBlocked(name, true); lastBlockSend = { name = name, at = now() } end
end)

starfish.events.on("session:detached", function()
    endGame()
    pending = nil
    if run and run.state == "checking" then run.state = "paused" end
end)

-- Commands

local function findNick(name)
    local n = game and game.nicks[lower(name)]
    if n then return n end
    n = lastGame and lastGame.nicks[lower(name)]
    if n then return n end
    for _, g in ipairs(recentGames or {}) do
        if g.nicks[lower(name)] then return g.nicks[lower(name)] end
    end
    local e = savedList()[lower(name)]
    if e then e.clues = e.clues or {}; e.numbers = e.numbers or {}; e.saved = true end
    return e
end

starfish.commands.register("saved", {
    description = "Show saved nicks",
}, function()
    local s, list = savedList(), {}
    for k, e in pairs(s) do
        if realNameOf(e.name) then s[k] = nil else list[#list + 1] = e end
    end
    starfish.config.set("saved", s)
    if #list == 0 then return "§7No saved nicks." end
    table.sort(list, function(a, b) return (a.seq or 0) > (b.seq or 0) end)
    starfish.chat.info("§f" .. #list .. " saved nick" .. (#list == 1 and "" or "s"))
    for _, e in ipairs(list) do
        e.clues = e.clues or {}; e.numbers = e.numbers or {}; e.saved = true
        starfish.chat.sendToClient(starfish.text.of(" ") .. nickLine(nil, e))
    end
end)

starfish.commands.register("remove", {
    description = "Remove a saved nick",
    arguments = { { name = "nick", type = "string" } },
}, function(ctx)
    if unsave(ctx.args.nick) then queueUnblock(ctx.args.nick); return "§7Removed §c" .. ctx.args.nick .. "§7." end
    return "§7" .. ctx.args.nick .. " isn't saved."
end)

starfish.commands.register("clear", {
    description = "Remove all saved nicks",
    arguments = { { name = "confirm", type = "string", optional = true } },
}, function(ctx)
    local s, count = savedList(), 0
    for _ in pairs(s) do count = count + 1 end
    if count == 0 then return "§7No saved nicks." end
    if lower(ctx.args.confirm) ~= "confirm" then
        return starfish.text.of("§7Remove and unblock " .. count .. " saved nick" .. (count == 1 and "" or "s") .. "? ")
            .. component("§c[Confirm]", "§7Can't be undone", "/cd clear confirm")
    end
    for _, e in pairs(s) do queueUnblock(e.name) end
    starfish.config.set("saved", {})
    return "§7Saved nicks cleared."
end)

starfish.commands.register("list", {
    description = "Nicks in your last game",
    default = true,
}, function()
    local g = game or lastGame
    if not g or not showSummary(g) then return "§7No nicks seen yet." end
end)

starfish.commands.register("search", {
    description = "Find who a nick is",
    arguments = { { name = "nick", type = "string" } },
}, function(ctx)
    local n = findNick(ctx.args.nick)
    if not n then return "§7" .. ctx.args.nick .. " isn't saved. See /cd saved." end
    search(n)
end)

starfish.commands.register("key", {
    description = "Set your Aurora API key",
    arguments = { { name = "key", type = "string" } },
}, function(ctx)
    starfish.config.set("lookup.key", ctx.args.key)
    return "§aAurora key saved."
end)

starfish.commands.register("stop", {
    description = "Stop searching",
}, function()
    runs = {}
    pending = nil
    if run then run = nil; cancel(nextTimer); return "§7Stopped." end
    return "§7Nothing running."
end)

-- Exports

starfish.plugin.export("getClues", function(nick)
    local n = findNick(nick)
    if not n then return nil end
    local out = {}
    for _, item in ipairs(bestClues(n, true)) do
        out[#out + 1] = { kind = item.kind, ids = item.clue.ids, sure = item.clue.sure }
    end
    return out
end)

-- Startup


applyLocation(starfish.plugins.require("hypixel-mod-api").getLocation())

if CD_TEST then _NC = { wipe = function() game = nil; lastGame = nil; recentGames = {} end, readKillLine = readKillLine, signFits = signFits, trailFits = trailFits, state = function() return game, lastGame, run end,
    reset = function() for k in pairs(foundByUs) do foundByUs[k] = nil end; for _, g in pairs({ a = game, b = lastGame }) do for _, n in pairs(g.nicks) do n.real = nil end end end }
end
