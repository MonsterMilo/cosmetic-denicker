-- cosmetic-denicker: island cosmetics (shopkeeper skins, toppers, figurines),
-- death cries, victory dances, glyphs and wood skins. Loaded by init.lua with
-- C, the bits of init.lua it uses.
return function(C)
local D = C.D
local now, flat, dist, lower, plain = C.now, C.flat, C.dist, C.lower, C.plain

local ISLAND_NEAR, ISLAND_MAX_UP, ISLAND_APART = 16, 75, 32
local ISLAND_START_MS, ISLAND_LOBBY_BLOCKS = 1000, 30
local RESPAWN_MIN, RESPAWN_MAX = 4000, 6500
local SETTLE_MS = 10000
local TOPPER_WATCH_MS, TOPPER_BUILD_MS, TOPPER_MIN_BLOCKS = 8000, 2500, 10
local TOPPER_NEAR_SHARE, TOPPER_NEAR_MIN, TOPPER_NEAR_MIN_BLOCKS = 0.04, 3, 20
local EFFECT_MS, EFFECT_BLOCKS = 8000, 16
local COPY_MS = 5000
local STALE_MS = 7 * 86400000
local CACHE_URL = "https://api.bordic.xyz/v3/cache/hypixel"
local CRY_MS, CRY_BLOCKS, CRY_FALL = 1500, 3, 12
local GLYPH_MS, GLYPH_BLOCKS, GLYPH_UP_LO, GLYPH_UP_HI, GLYPH_MIN = 2000, 3, 0.5, 8, 2
local DANCE_MS, DANCE_BLOCKS, DANCE_CLONES = 9000, 32, 5
local RANDOM = { random_cosmetic = true, random_favorite_cosmetic = true }

local function log(fmt, ...) starfish.log.debug(fmt:format(...)) end
local function ukey(uuid) return uuid and tostring(uuid):gsub("-", ""):lower() or nil end
local function strip(id) return (tostring(id or ""):gsub("^[%w_]+:", "")) end
local function bitSet(v, bit) v = tonumber(v) or 0; return math.floor(v / bit) % 2 == 1 end
local function split(s, sep)
    local out = {}
    for part in (s .. sep):gmatch("(.-)" .. sep:gsub("%p", "%%%0")) do out[#out + 1] = part end
    return out
end

-- Skins (from the tab list's textures), kept for the session

local skins, skinNames = {}, {}

local function skinIdOf(properties)
    if type(properties) ~= "table" then return nil end
    local tex = properties.textures
    if not tex then for _, p in ipairs(properties) do if type(p) == "table" and p.name == "textures" then tex = p end end end
    if not tex or not tex.value then return nil end
    local text = starfish.base64.decode(tex.value)
    local ok, data = pcall(json.decode, text or "")
    local url = ok and type(data) == "table" and data.textures and data.textures.SKIN and data.textures.SKIN.url
    return url and url:match("([^/]+)$") or nil
end

local function noteSkin(uuid, name, properties)
    local id = skinIdOf(properties)
    if not id or not uuid then return end
    skins[ukey(uuid)] = id
    skinNames[ukey(uuid)] = tostring(name or "")
end

starfish.events.on("player:listUpdate", function(e)
    if e.action ~= "add" then return end
    for _, p in ipairs(e.players or {}) do noteSkin(p.uuid, p.name, p.properties) end
end)

-- Names: everyone seen in tab this game (final-killed players leave it)

local function S(g)
    if not g.x then
        g.x = { homes = {}, bad = {}, died = {}, finalDied = {}, things = {}, done = {}, ids = {}, teamOf = {},
            asks = {}, keeperSpots = {}, figSpots = {}, startBlocks = {}, toppers = {}, byUuid = {}, cries = {},
            glyphs = {}, glyphDone = {}, clones = {}, rides = {}, wood = {} }
    end
    return g.x
end

local function rememberTab(g)
    local s = S(g)
    for _, p in ipairs(starfish.players.all()) do
        if p.uuid and p.name then
            s.byUuid[ukey(p.uuid)] = p.name
            noteSkin(p.uuid, p.name, p.properties)
        end
    end
end

local function nameOfUuid(g, uuid)
    local k = ukey(uuid)
    if not k then return nil end
    local s = S(g)
    if s.byUuid[k] then return s.byUuid[k] end
    local p = starfish.players.byUuid(uuid)
    if p and p.name then s.byUuid[k] = p.name; return p.name end
    return nil
end

local function uuidOfName(g, name)
    for k, n in pairs(S(g).byUuid) do if lower(n) == lower(name) then return k end end
    return nil
end

local function isNpcUuid(uuid) return C.uuidVersion(uuid) == "2" end

-- Kinds and items, Starfish names -> 1.8 numbers

local MOB_ALIASES = {
    snowgolem = 97, zombiepigman = 57, zombifiedpiglin = 57, irongolem = 99, horse = 100, skeletonhorse = 100,
    zombiehorse = 100, mooshroom = 96, ocelot = 98, magmacube = 62, wither = 64, enderdragon = 63,
    cavespider = 59, witherskeleton = 51, zombievillager = 54, giant = 53, armorstand = 30,
}
local function mobType(kind)
    local k = strip(kind):lower():gsub("[_%s]", "")
    return D.MOB_IDS[k] or MOB_ALIASES[k], k
end

local function itemNum(item)
    if type(item) ~= "table" then return nil end
    local id = strip(item.id)
    return tonumber(id) or D.ITEM_IDS[id]
end

local function itemDamage(item)
    if type(item) ~= "table" then return nil end
    local d = item.damage or item.meta or item.metadata or (type(item.durability) == "table" and item.durability.damage)
    return tonumber(d)
end

local function metaMap(md)
    local m = {}
    if type(md) ~= "table" then return m end
    for k, v in pairs(md) do
        if type(v) == "table" and (v.index or v.key) ~= nil then m[tonumber(v.index or v.key)] = v.value
        elseif type(k) == "number" and type(v) ~= "table" then m[k] = v end
    end
    return m
end

local function customName(meta)
    local n = meta[2]
    if type(n) ~= "string" then return nil end
    n = plain(n):gsub("^%s+", ""):gsub("%s+$", "")
    return n ~= "" and n or nil
end

local SLOTS = { [0] = "held", "boots", "legs", "chest", "head",
    hand = "held", held = "held", mainhand = "held", mainHand = "held", boots = "boots", leggings = "legs",
    legs = "legs", chestplate = "chest", chest = "chest", helmet = "head", head = "head" }

-- Clues for the island's owners

local function token(ids) return table.concat(ids, "|") end

local function idsOf(id) return split(id, ",") end

local function isNickName(g, name)
    local p = starfish.players.byName(name)
    if p then return C.isNick(p) end
    local u = uuidOfName(g, name)
    return u ~= nil and u:sub(13, 13) == "1"
end

local function islandAdd(g, owner, cat, id, how)
    local s = S(g)
    local k = lower(owner) .. "|" .. cat
    s.ids[k] = s.ids[k] or {}
    s.ids[k][id] = true
    local all = {}
    for i in pairs(s.ids[k]) do for _, x in ipairs(idsOf(i)) do all[#all + 1] = x end end
    table.sort(all)
    if #all > #idsOf(id) then
        C.clearKind(g, owner, cat)
        C.addClue(g, owner, cat, all, false, "their island showed more than one")
        return
    end
    C.addClue(g, owner, cat, idsOf(id), true, how)
end

-- Spawn points

local function median(list)
    if #list == 0 then return nil end
    table.sort(list)
    return list[math.floor(#list / 2) + 1]
end

local islandSoon

local function islandHome(g, name, pos, how)
    if not name or not pos then return end
    local s = S(g)
    local key = lower(name)
    if how == "respawned" then
        local hs = {}
        for _, h in pairs(s.homes) do if h.how == "at the start" then hs[#hs + 1] = h.pos.y end end
        local m = median(hs)
        if m and math.abs(pos.y - m) > 8 then return false end
    end
    local old = s.homes[key]
    if old then
        if flat(old.pos, pos) > 8 then s.bad[key] = true end
        return
    end
    s.homes[key] = { pos = { x = pos.x, y = pos.y, z = pos.z }, how = how }
    log("island: %s spawns at %.0f,%.0f,%.0f (%s)", name, pos.x, pos.y, pos.z, how)
    islandSoon(g)
end

local function readTeams(g)
    local s = S(g)
    local ok, teams = pcall(starfish.scoreboard.teams)
    if not ok or type(teams) ~= "table" then return end
    for _, t in ipairs(teams) do
        local letter = plain(t.prefix or ""):match("^%s*(%S+)")
        if letter then
            for _, n in ipairs(t.players or {}) do
                local l = lower(n)
                if not s.teamOf[l] and uuidOfName(g, n) then s.teamOf[l] = letter end
            end
        end
    end
end

local function roster(g, name)
    local s = S(g)
    readTeams(g)
    local letter = s.teamOf[lower(name)]
    if not letter then return nil end
    local out = {}
    for n, l in pairs(s.teamOf) do if l == letter then out[#out + 1] = n end end
    table.sort(out)
    return out
end

local function owners(s, pos)
    local out = {}
    for name, home in pairs(s.homes) do
        local d = flat(home.pos, pos)
        local up = pos.y - home.pos.y
        if d <= ISLAND_NEAR and up >= -15 and up <= ISLAND_MAX_UP then out[#out + 1] = name
        elseif d <= ISLAND_APART then return nil end
    end
    for _, o in ipairs(out) do if s.bad[o] then return nil end end
    table.sort(out)
    return #out > 0 and out or nil
end

-- Looks

local function topperKey(id, m)
    if D.TOPPER_KEEP_DATA[id] then return id .. ":" .. (id == 6 and m % 8 or m) end
    if id == 44 or id == 126 or id == 182 or id == 175 then return id .. ":" .. m % 8 end
    if id == 17 or id == 162 or id == 18 or id == 161 then return id .. ":" .. m % 4 end
    if id == 155 then return id .. ":" .. (m >= 2 and 2 or m) end
    return tostring(id)
end

local function topperLook(blocks)
    local counts, order = {}, {}
    local lo, hi = { x = math.huge, y = math.huge, z = math.huge }, { x = -math.huge, y = -math.huge, z = -math.huge }
    for _, b in ipairs(blocks) do
        local k = topperKey(b.id, b.m)
        if not counts[k] then counts[k] = 0; order[#order + 1] = k end
        counts[k] = counts[k] + 1
        for _, a in ipairs({ "x", "y", "z" }) do lo[a] = math.min(lo[a], b[a]); hi[a] = math.max(hi[a], b[a]) end
    end
    table.sort(order, function(p, q)
        local pa, pb = p:match("^(%d+):?(%d*)$")
        local qa, qb = q:match("^(%d+):?(%d*)$")
        pa, qa = tonumber(pa), tonumber(qa)
        if pa ~= qa then return pa < qa end
        return (tonumber(pb) or 0) < (tonumber(qb) or 0)
    end)
    local parts = {}
    for _, k in ipairs(order) do parts[#parts + 1] = k .. "x" .. counts[k] end
    local a, c = hi.x - lo.x + 1, hi.z - lo.z + 1
    if a > c then a, c = c, a end
    return "blocks:" .. table.concat(parts, "|") .. "|size:" .. (hi.y - lo.y + 1) .. "h" .. a .. "x" .. c,
        { x = (lo.x + hi.x) / 2 + 0.5, y = lo.y, z = (lo.z + hi.z) / 2 + 0.5 }
end

local function parseTopper(look)
    local counts, total = {}, 0
    for _, part in ipairs(split(look:sub(8), "|")) do
        if part:sub(1, 5) ~= "size:" then
            local k, n = part:match("^(.-)x(%d+)$")
            if k then counts[k] = tonumber(n); total = total + tonumber(n) end
        end
    end
    return counts, total
end

local topperList
local function topperLooks()
    if not topperList then
        topperList = {}
        for k, id in pairs(D.ISLAND_LOOKS.topper) do
            local counts, total = parseTopper(k)
            topperList[#topperList + 1] = { id = id, counts = counts, total = total }
        end
    end
    return topperList
end

local function topperText(look)
    local high, thin, wide = look:match("|size:(%d+)h(%d+)x(%d+)$")
    high, thin, wide = tonumber(high), tonumber(thin), tonumber(wide)
    if not high or thin > 2 or wide < 15 or high < 5 or high > 14 then return nil end
    for k in pairs((parseTopper(look))) do if not D.TOPPER_TEXT_BLOCKS[k] then return nil end end
    return "islandtopper_tourney"
end

local function topperOnStand(x)
    local fits, ids = {}, {}
    for _, stair in ipairs(D.TOPPER_STAND_BLOCKS) do
        for _, y in ipairs(topperLooks()) do
            local extra = (x[stair] or 0) - (y.counts[stair] or 0)
            if y.total >= TOPPER_NEAR_MIN_BLOCKS and extra >= 4 and extra <= 20 then
                local same = true
                for b, n in pairs(x) do if b ~= stair and (y.counts[b] or 0) ~= n then same = false end end
                for b, n in pairs(y.counts) do if b ~= stair and (x[b] or 0) ~= n then same = false end end
                if same and not ids[y.id] then ids[y.id] = true; fits[#fits + 1] = y.id end
            end
        end
    end
    return #fits == 1 and fits[1] or nil
end

local function topperNear(look)
    local text = topperText(look)
    if text then return text end
    local x = parseTopper(look)
    local found = {}
    for _, y in ipairs(topperLooks()) do
        local off = 0
        for b, n in pairs(x) do off = off + math.abs(n - (y.counts[b] or 0)) end
        for b, n in pairs(y.counts) do if not x[b] then off = off + n end end
        found[#found + 1] = { id = y.id, off = off, total = y.total }
    end
    table.sort(found, function(a, b) return a.off < b.off end)
    local best, nxt = found[1], found[2]
    if not best or best.total < TOPPER_NEAR_MIN_BLOCKS then return nil end
    local allowed = math.max(TOPPER_NEAR_MIN, math.floor(best.total * TOPPER_NEAR_SHARE + 0.5))
    if best.off > allowed or (nxt and nxt.id ~= best.id and nxt.off <= allowed * 3) then return topperOnStand(x) end
    return best.id
end

-- Figurines: Starfish items carry no damage value or head skin, so looks are
-- compared by slot and item only.
local figList
local function reduceToken(t)
    local slot, id = t:match("^(%a+):(%d+)")
    return slot and (slot .. ":" .. id) or t
end
local function bagOf(tokens)
    local m = {}
    for _, t in ipairs(tokens) do m[t] = (m[t] or 0) + 1 end
    return m
end
local function figLooks()
    if not figList then
        figList = {}
        for k, id in pairs(D.ISLAND_LOOKS.figurine) do
            local tokens = {}
            for _, t in ipairs(split(k, "|")) do tokens[#tokens + 1] = reduceToken(t) end
            figList[#figList + 1] = { id = id, bag = bagOf(tokens), size = #tokens }
        end
    end
    return figList
end

local function figurineId(tokens)
    local x = bagOf(tokens)
    local exact, partial, eIds, pIds, looks = {}, {}, {}, {}, 0
    for _, f in ipairs(figLooks()) do
        local inside, same = true, f.size == #tokens
        for t, n in pairs(x) do
            if (f.bag[t] or 0) < n then inside = false end
            if (f.bag[t] or 0) ~= n then same = false end
        end
        if same then looks = looks + 1 end
        for _, id in ipairs(idsOf(f.id)) do
            if same and not eIds[id] then eIds[id] = true; exact[#exact + 1] = id end
            if inside and not pIds[id] then pIds[id] = true; partial[#partial + 1] = id end
        end
    end
    table.sort(exact); table.sort(partial)
    -- (One recorded look can name two ids - Sandman.)
    if #exact > 0 then return exact, looks == 1 and #exact == 1 end
    if #partial > 0 and #partial <= 2 and #tokens >= 3 then return partial, false end
    return nil
end

local function mobLook(t)
    local m = t.meta or {}
    local function n(k) return tonumber(m[k]) or 0 end
    local look = "mob:" .. t.type
    if bitSet(n(0), 32) or t.invisible then look = look .. ":invisible" end
    if t.type == 51 and (n(13) == 1 or t.kindKey == "witherskeleton") then look = look .. ":wither" end
    if t.type == 54 and n(12) == 1 then look = look .. ":baby" end
    if t.type == 54 and (n(13) == 1 or t.kindKey == "zombievillager") then look = look .. ":villager" end
    if t.type == 120 then look = look .. ":job" .. n(16) end
    if t.type == 100 then look = look .. ":kind" .. n(19) end
    if t.type == 98 then look = look .. ":kind" .. n(18) end
    if t.type == 91 then look = look .. ":colour" .. (n(16) % 16) end
    local ageable = { [90] = 1, [92] = 1, [93] = 1, [95] = 1, [96] = 1, [100] = 1, [101] = 1, [120] = 1 }
    if ageable[t.type] and n(12) < 0 then look = look .. ":baby" end
    return look
end

local function lookId(cat, look)
    local id = D.ISLAND_LOOKS[cat] and D.ISLAND_LOOKS[cat][look]
    if id then return id end
    if cat == "topper" then return topperNear(look) end
    return nil
end

-- Teammates' cosmetics, from Aurora's copy of their Hypixel data

local hyCache = {}

local function hypixelFields(uuids, cb)
    local key = starfish.config.get("lookup.key")
    local want, out = {}, {}
    for _, u in ipairs(uuids) do
        local c = hyCache[u]
        if c and now() - c.at < 600000 then out[u] = c.v else want[#want + 1] = u end
    end
    if #want == 0 then return cb(out) end
    if not key or key == "" then return cb(nil, "no Aurora key") end
    starfish.http.post(CACHE_URL .. "?key=" .. starfish.http.encodeUri(key), { body = { uuids = want } }, function(res)
        if not res or not res.success or type(res.data) ~= "table" or res.data.success == false then
            return cb(nil, "Aurora didn't answer")
        end
        local byKey = {}
        for k, v in pairs(res.data) do if type(v) == "table" then byKey[ukey(k)] = v end end
        for _, u in ipairs(want) do
            local entry = byKey[u]
            local bw = entry and entry.success ~= false and entry.player and entry.player.stats and entry.player.stats.Bedwars
            local v = bw and { fields = bw, updated = tonumber(entry.lastUpdated) or 0 } or false
            hyCache[u] = { v = v, at = now() }
            out[u] = v
        end
        cb(out)
    end)
end

local function islandField(cat, fields)
    if type(fields) ~= "table" then return nil end
    if cat == "npc" then return fields.activeNPCSkin end
    if cat == "topper" then return fields.activeIslandTopper end
    if cat == "figurine" then return type(fields.figurines) == "table" and fields.figurines.active or nil end
    return nil
end

local function checkTeam(ask)
    local g, cat, ids = ask.g, ask.cat, ask.ids
    local uuids = {}
    for _, r in ipairs(ask.reals) do uuids[#uuids + 1] = r.uuid end
    hypixelFields(uuids, function(infos, err)
        if err then
            for _, n in ipairs(ask.nicks) do C.addClue(g, n, cat, ids, false, "on their team's island - teammates not checked (" .. err .. ")") end
            return
        end
        local unsure = {}
        for _, r in ipairs(ask.reals) do
            local info = infos[r.uuid]
            local has = info and islandField(cat, info.fields)
            for _, id in ipairs(ids) do
                if has == id then
                    log("island: %s is %s's (Aurora) - not the nicks'", token(ids), r.name)
                    for _, n in ipairs(ask.nicks) do C.removeClue(g, n, cat, token(ids)) end
                    return
                end
            end
            if not info then unsure[#unsure + 1] = r.name .. " isn't on Aurora"
            elseif not info.updated or (starfish.time.now() - info.updated) > STALE_MS then unsure[#unsure + 1] = r.name .. "'s data is old"
            elseif has and RANDOM[has] then unsure[#unsure + 1] = r.name .. " has it on random" end
        end
        for _, n in ipairs(ask.nicks) do C.removeClue(g, n, cat, token(ids)) end
        if #unsure > 0 then
            for _, n in ipairs(ask.nicks) do C.addClue(g, n, cat, ids, false, "on their team's island, but " .. table.concat(unsure, ", ")) end
        elseif #ask.nicks > 1 then
            for _, n in ipairs(ask.nicks) do C.addClue(g, n, cat, ids, false, "one of " .. table.concat(ask.nicks, ", ") .. " - can't tell which") end
        else
            islandAdd(g, ask.nicks[1], cat, table.concat(ids, ","), "their team's island, not a teammate's")
        end
    end)
end

local function islandTeam(g, own, cat, ids)
    local team = roster(g, own[1])
    if not team then log("island: team of %s unknown", own[1]) return end
    local inTeam = {}
    for _, n in ipairs(team) do inTeam[n] = true end
    for _, o in ipairs(own) do if not inTeam[o] then return end end
    local nicks, reals = {}, {}
    for _, n in ipairs(team) do
        local shownName = S(g).byUuid[uuidOfName(g, n) or ""] or n
        if isNickName(g, shownName) then
            local real = C.realNameOf(shownName)
            if real then reals[#reals + 1] = { name = shownName, real = real }
            else nicks[#nicks + 1] = shownName end
        else
            reals[#reals + 1] = { name = shownName, uuid = uuidOfName(g, n) }
        end
    end
    if #nicks == 0 then return end
    local s = S(g)
    local askKey = token(ids) .. "|" .. table.concat(team, ",")
    for _, a in ipairs(s.asks) do if a.key == askKey then return end end
    -- A denicked teammate is checked by their real name (its uuid from Mojang).
    local needed = 0
    local ask = { key = askKey, g = g, cat = cat, ids = ids, nicks = nicks, reals = {} }
    s.asks[#s.asks + 1] = ask
    for _, n in ipairs(nicks) do C.addClue(g, n, cat, ids, false, "on their team's island - teammates not checked yet") end
    local function ready()
        needed = needed - 1
        if needed <= 0 then checkTeam(ask) end
    end
    needed = 1
    for _, r in ipairs(reals) do
        if r.uuid then
            ask.reals[#ask.reals + 1] = r
        elseif r.real then
            needed = needed + 1
            starfish.http.get("https://api.mojang.com/users/profiles/minecraft/" .. r.real, {}, function(res)
                local id = res and res.success and type(res.data) == "table" and res.data.id
                if id then ask.reals[#ask.reals + 1] = { name = r.name, uuid = ukey(id) }
                else ask.reals[#ask.reals + 1] = { name = r.name, uuid = "unknown-" .. r.name } end
                ready()
            end)
        end
    end
    ready()
end

-- Judging what's on the islands

local function deathCopy(g, s, f)
    for name, at in pairs(s.finalDied) do
        local u = uuidOfName(g, name)
        if u and skins[u] == f.skin and f.at >= at - 1000 and f.at <= at + COPY_MS then return name end
    end
    return nil
end

local function nearEffect(g, t)
    for _, ev in ipairs(g.events) do
        if ev.pos and ev.kind ~= "dance" and t.at >= ev.at - 500 and t.at - ev.at <= EFFECT_MS and dist(ev.pos, t.pos) <= EFFECT_BLOCKS then return true end
    end
    return false
end

local function decide(g, own, cat, look, f)
    local id = lookId(cat, look)
    log("island: %s's %s %s = %s", table.concat(own, "/"), cat, look, tostring(id))
    if not id then return end
    if #own == 1 and g.solo then
        if isNickName(g, S(g).byUuid[uuidOfName(g, own[1]) or ""] or own[1]) then
            islandAdd(g, S(g).byUuid[uuidOfName(g, own[1]) or ""] or own[1], cat, id, "on their island")
        end
        return
    end
    islandTeam(g, own, cat, idsOf(id))
end

local function judge(g)
    if not g.startAt or g.overAt then return end
    local s = S(g)
    readTeams(g)
    local t0 = now()
    local again = false
    local found, mobs = {}, {}
    for _, t in pairs(s.things) do
        if t.kind == "npc" then
            local skin = skins[t.uuid]
            if skin then
                found[#found + 1] = { key = "npc|" .. t.id, cat = "npc", look = "skin:" .. skin, skin = skin,
                    upsideDown = D.UPSIDE_DOWN[skinNames[t.uuid] or ""] ~= nil, pos = t.pos, at = t.at }
            end
        elseif t.kind == "mob" and not D.ISLAND_NOT_SHOPKEEPERS[t.type] and (not t.name or D.UPSIDE_DOWN[t.name]) then
            if t0 - t.at < SETTLE_MS then again = true
            elseif t.moved <= 0.5 and not nearEffect(g, t) then mobs[#mobs + 1] = t end
        end
    end
    -- Mobs of one kind standing together are one shopkeeper (Cluck Stack...).
    local used = {}
    for _, first in ipairs(mobs) do
        if not used[first] then
            local group = { first }
            used[first] = true
            local i = 1
            while i <= #group do
                for _, o in ipairs(mobs) do
                    if not used[o] and o.type == first.type and flat(group[i].pos, o.pos) <= 2 then used[o] = true; group[#group + 1] = o end
                end
                i = i + 1
            end
            local upright = group[1]
            for _, t in ipairs(group) do if not D.UPSIDE_DOWN[t.name or ""] then upright = t break end end
            local look = mobLook(upright)
            if #group > 1 then look = look .. ":stack" elseif D.UPSIDE_DOWN[first.name or ""] then look = look .. ":upsidedown" end
            local minId = first.id
            for _, t in ipairs(group) do minId = math.min(minId, t.id) end
            found[#found + 1] = { key = "npc|" .. minId, cat = "npc", look = look, pos = first.pos }
        end
    end
    for _, t in ipairs(s.toppers) do found[#found + 1] = { key = "top|" .. t.key, cat = "topper", look = t.look, pos = t.pos } end
    -- Figurines: armor stands wearing things, standing together.
    local stands = {}
    for _, t in pairs(s.things) do
        if t.kind == "stand" and not t.name and next(t.equip) and not nearEffect(g, t) then stands[#stands + 1] = t end
    end
    local usedS = {}
    for _, first in ipairs(stands) do
        if not usedS[first] then
            local group = { first }
            usedS[first] = true
            local i = 1
            while i <= #group do
                for _, o in ipairs(stands) do
                    if not usedS[o] and dist(group[i].pos, o.pos) <= 1.6 then usedS[o] = true; group[#group + 1] = o end
                end
                i = i + 1
            end
            local quiet, minId = true, first.id
            for _, t in ipairs(group) do
                if t0 - t.changedAt < 3000 then quiet = false end
                minId = math.min(minId, t.id)
            end
            if not quiet then
                again = true
            else
                local headName, skulls, tokens = nil, 0, {}
                for _, t in ipairs(group) do
                    local worn = 0
                    for slot, item in pairs(t.equip) do
                        local num = itemNum(item)
                        if num then
                            worn = worn + 1
                            tokens[#tokens + 1] = slot .. ":" .. num
                            local nm = item.name and plain(item.name) or nil
                            if slot == "head" and nm and D.ISLAND_LOOKS.npc["head:" .. nm] then headName = nm end
                        end
                    end
                    if worn == 1 and t.equip.head and itemNum(t.equip.head) == 397 then skulls = skulls + 1 end
                end
                table.sort(tokens)
                if headName then
                    found[#found + 1] = { key = "npc|" .. minId, cat = "npc", look = "head:" .. headName, pos = first.pos }
                elseif #group == 3 and skulls == 3 then
                    found[#found + 1] = { key = "npc|" .. minId, cat = "npc", look = "skullstack", pos = first.pos }
                elseif #tokens > 0 then
                    found[#found + 1] = { key = "fig|" .. minId .. "|" .. #group, cat = "figurine", tokens = tokens, look = table.concat(tokens, "|"), pos = first.pos }
                end
            end
        end
    end
    for _, f in ipairs(found) do
        if not s.done[f.key] then
            local copyOf = f.cat == "npc" and f.skin and deathCopy(g, s, f)
            local own = not copyOf and owners(s, f.pos)
            if copyOf then
                s.done[f.key] = true
            elseif own then
                s.done[f.key] = true
                local skip = false
                if f.cat == "figurine" then
                    for _, p in ipairs(s.figSpots) do if dist(p, f.pos) <= 4 then skip = true end end
                    if not skip then s.figSpots[#s.figSpots + 1] = f.pos end
                end
                -- The Everyman changes look during the game; a stack seen
                -- before the rest loaded is the same shopkeeper.
                if f.cat == "npc" and not skip then
                    local spot
                    for _, k in ipairs(s.keeperSpots) do
                        if flat(k.pos, f.pos) <= 1.5 and math.abs(k.pos.y - f.pos.y) <= 3 then spot = k end
                    end
                    if not spot then
                        s.keeperSpots[#s.keeperSpots + 1] = { pos = f.pos, look = f.look }
                    elseif spot.everyman then
                        skip = true
                    elseif f.look == spot.look .. ":stack" then
                        for _, o in ipairs(own) do C.clearKind(g, S(g).byUuid[uuidOfName(g, o) or ""] or o, "npc"); s.ids[o .. "|npc"] = nil end
                        spot.look = f.look
                    elseif spot.look == f.look .. ":stack" or spot.look == f.look then
                        skip = true
                    else
                        spot.everyman = true
                        for _, o in ipairs(own) do C.clearKind(g, S(g).byUuid[uuidOfName(g, o) or ""] or o, "npc"); s.ids[o .. "|npc"] = nil end
                        f.look, f.skin = "everyman", nil
                    end
                end
                if not skip then
                    if f.look == "skullstack" then
                        for _, o in ipairs(own) do
                            local nm = S(g).byUuid[uuidOfName(g, o) or ""] or o
                            if isNickName(g, nm) then C.addClue(g, nm, "npc", { "npcskin_skull_stack" }, false, "a Skull Stack on their island (id not confirmed)") end
                        end
                    elseif f.cat == "figurine" then
                        local ids, sure = figurineId(f.tokens)
                        log("island: %s's figurine %s = %s", table.concat(own, "/"), f.look, ids and token(ids) or "?")
                        if ids then
                            if #own == 1 and g.solo then
                                local nm = S(g).byUuid[uuidOfName(g, own[1]) or ""] or own[1]
                                if isNickName(g, nm) then
                                    if sure and #ids == 1 then islandAdd(g, nm, "figurine", ids[1], "on their island")
                                    else C.addClue(g, nm, "figurine", ids, false, "figurines that look alike") end
                                end
                            elseif #ids == 1 and sure then
                                islandTeam(g, own, "figurine", ids)
                            end
                        end
                    else
                        -- "You!": a shopkeeper in the skin of a player whose island it is.
                        local self = {}
                        if f.skin then
                            for _, o in ipairs(own) do
                                local u = uuidOfName(g, o)
                                if u and skins[u] == f.skin then self[#self + 1] = o end
                            end
                        end
                        if #self == 1 then
                            local nm = S(g).byUuid[uuidOfName(g, self[1]) or ""] or self[1]
                            if isNickName(g, nm) then islandAdd(g, nm, "npc", f.upsideDown and "npcskin_you_upside_down" or "npcskin_you", "their own skin on their island") end
                        else
                            decide(g, own, f.cat, f.look, f)
                        end
                    end
                end
            end
        end
    end
    if again then islandSoon(g) end
end

islandSoon = function(g)
    local s = S(g)
    if s.timer then return end
    s.timer = starfish.timers.delay(2000, function()
        s.timer = nil
        if C.game() == g then judge(g) end
    end)
end

local function addThing(g, id, kind, extra, pos)
    if type(id) ~= "number" or not pos or g.overAt then return end
    local s = S(g)
    local t = { id = id, kind = kind, pos = { x = pos.x, y = pos.y, z = pos.z }, at = now(), changedAt = now(), moved = 0, equip = {} }
    for k, v in pairs(extra or {}) do t[k] = v end
    s.things[id] = t
    islandSoon(g)
end

local function islandBlockGroups(blocks)
    local cell = {}
    local function key(x, y, z) return x .. "," .. y .. "," .. z end
    for i, b in ipairs(blocks) do cell[key(b.x, b.y, b.z)] = i end
    local used, groups = {}, {}
    for f = 1, #blocks do
        if not used[f] then
            used[f] = true
            local group = { blocks[f] }
            local i = 1
            while i <= #group do
                local b = group[i]
                for dx = -2, 2 do for dy = -2, 2 do for dz = -2, 2 do
                    local n = cell[key(b.x + dx, b.y + dy, b.z + dz)]
                    if n and not used[n] then used[n] = true; group[#group + 1] = blocks[n] end
                end end end
                i = i + 1
            end
            groups[#groups + 1] = group
        end
    end
    return groups
end

local function buildToppers(g)
    local s = S(g)
    local blocks = {}
    for _, b in ipairs(s.startBlocks) do
        if b.at <= TOPPER_BUILD_MS and b.id ~= 0 and b.id ~= 26 then blocks[#blocks + 1] = b end
    end
    for _, group in ipairs(islandBlockGroups(blocks)) do
        if #group >= TOPPER_MIN_BLOCKS then
            local look, pos = topperLook(group)
            s.toppers[#s.toppers + 1] = { key = math.floor(pos.x + 0.5) .. "," .. pos.y .. "," .. math.floor(pos.z + 0.5), look = look, pos = pos }
            log("island: topper at %.0f,%.0f,%.0f (%d blocks): %s = %s", pos.x, pos.y, pos.z, #group, look, tostring(lookId("topper", look)))
        end
    end
    islandSoon(g)
end

-- Game start / over / kills (called by init.lua)

local X = {}

function X.start(g)
    local s = S(g)
    g.startAt = now()
    rememberTab(g)
    starfish.timers.delay(ISLAND_START_MS, function()
        if C.game() ~= g then return end
        rememberTab(g)
        readTeams(g)
        local here = {}
        for _, e in ipairs(starfish.entities.players()) do
            local name = e.uuid and not isNpcUuid(e.uuid) and nameOfUuid(g, e.uuid)
            if name and e.position then here[#here + 1] = { name = name, pos = e.position } end
        end
        local me = starfish.players.me()
        if me and me.name and me.position then here[#here + 1] = { name = me.name, pos = me.position } end
        for _, p in ipairs(here) do
            local close = 0
            for _, q in ipairs(here) do if q ~= p and flat(p.pos, q.pos) < 8 then close = close + 1 end end
            if close <= 3 and math.sqrt(p.pos.x * p.pos.x + p.pos.z * p.pos.z) >= ISLAND_LOBBY_BLOCKS then
                islandHome(g, p.name, p.pos, "at the start")
            end
        end
    end)
    starfish.timers.delay(TOPPER_BUILD_MS + 500, function() if C.game() == g then buildToppers(g) end end)
    starfish.timers.delay(TOPPER_WATCH_MS + 1000, function() s.startBlocks = {} end)
end

local function cryNear(deathPos, cryPos)
    if dist(deathPos, cryPos) <= CRY_BLOCKS then return true end
    local below = deathPos.y - cryPos.y
    return below > 0 and below <= CRY_FALL and flat(deathPos, cryPos) <= CRY_BLOCKS
end

local function cryMatch(g, cry)
    if cry.done then return end
    local victims, seen, final = {}, {}, false
    for _, ev in ipairs(g.events) do
        if ev.kind == "kill" and ev.victim and ev.pos and math.abs(ev.at - cry.at) <= CRY_MS and cryNear(ev.pos, cry.pos) then
            if not seen[lower(ev.victim)] then seen[lower(ev.victim)] = true; victims[#victims + 1] = ev.victim end
            final = final or ev.final
        end
    end
    if #victims == 0 then return end
    cry.done = true
    local ids = { cry.id }
    if #victims > 1 then
        for _, v in ipairs(victims) do C.addClue(g, v, "deathcry", ids, false, "more than one player died there") end
    elseif final and D.DEATH_CRY_SHARED[cry.sound] then
        C.addClue(g, victims[1], "deathcry", ids, false, "a final kill effect can make that sound too")
    elseif cry.id ~= "deathcry_evil_laugh" then
        C.addClue(g, victims[1], "deathcry", ids, false, "heard where they died")
    else
        C.addClue(g, victims[1], "deathcry", ids, true)
    end
end

function X.kill(g, ev, victim, final)
    if not victim then return end
    local s = S(g)
    s.died[lower(victim)] = now()
    if final then s.finalDied[lower(victim)] = now() end
    ev.victim = victim
    for _, cry in ipairs(s.cries) do cryMatch(g, cry) end
end

function X.over(g)
    if g.overAt then return end
    g.overAt = now()
    local s = S(g)
    local winners = {}
    for _, e in ipairs(starfish.entities.players()) do
        local name = e.uuid and not isNpcUuid(e.uuid) and nameOfUuid(g, e.uuid)
        if name and e.position and not s.finalDied[lower(name)] then
            winners[#winners + 1] = name
            g.events[#g.events + 1] = { kind = "dance", owner = name, at = now(), pos = { x = e.position.x, y = e.position.y, z = e.position.z },
                features = {}, window = DANCE_MS, radius = DANCE_BLOCKS, minUp = -10, maxUp = 80, early = 0 }
        end
    end
    s.winners = {}
    for _, w in ipairs(winners) do s.winners[lower(w)] = w end
    if #winners == 0 then return end
    starfish.timers.delay(DANCE_MS + 500, function()
        local evs = {}
        for _, ev in ipairs(g.events) do if ev.kind == "dance" then evs[#evs + 1] = ev end end
        local done = {}
        local function call(owner, ids, why)
            local k = lower(owner) .. "|" .. token(ids)
            if done[k] then return end
            done[k] = true
            C.addClue(g, owner, "dance", ids, why == nil, why)
        end
        for _, r in ipairs(s.rides) do
            local ride = D.DANCE_RIDES[r.type]
            if ride and s.winners[lower(r.rider)] then call(r.rider, ride.ids, (not ride.confirmed) and "not seen in a real game yet" or nil) end
        end
        for _, sign in ipairs(D.DANCE_SIGNS) do
            local near = {}
            for _, ev in ipairs(evs) do if C.signFits(ev.features, sign) then near[#near + 1] = ev end end
            for _, ev in ipairs(near) do
                call(ev.owner, sign.ids, #near > 1 and "more than one winner stood close to it" or (not sign.confirmed and "not seen in a real game yet" or nil))
            end
        end
    end)
end

-- Events

starfish.events.on("entity:spawn", function(e)
    local g = C.game()
    if not g or not g.startAt then return end
    local pos = C.posOf(e)
    if not pos then return end
    local typ, k = mobType(C.spawnKind(e))
    if k == "player" then
        local uuid = e.uuid or e.playerUuid or e.playerUUID
        if not uuid and e.entityId then
            local ent = starfish.entities.byId(e.entityId)
            uuid = ent and ent.uuid
        end
        if not uuid then return end
        if isNpcUuid(uuid) then
            local key = ukey(uuid)
            if not skins[key] then
                local p = starfish.players.byUuid(uuid)
                if p then noteSkin(uuid, p.name, p.properties) end
            end
            if g.overAt then
                -- After the game: NPCs in a winner's skin (Twerk Apocalypse).
                local skin = skins[key]
                if not skin then return end
                for u, name in pairs(S(g).byUuid) do
                    if skins[u] == skin and S(g).winners and S(g).winners[lower(name)] then
                        local set = S(g).clones[name] or {}
                        set[key] = true
                        S(g).clones[name] = set
                        local n = 0
                        for _ in pairs(set) do n = n + 1 end
                        if n == DANCE_CLONES then C.addClue(g, name, "dance", { "victorydance_twerk_apocalypse" }, true) end
                        return
                    end
                end
            else
                addThing(g, e.entityId, "npc", { uuid = key }, pos)
            end
            return
        end
        -- A player reappearing just after dying has respawned at home.
        local name = nameOfUuid(g, uuid)
        local s = S(g)
        local died = name and s.died[lower(name)]
        if died then
            local since = now() - died
            if since >= RESPAWN_MIN and since <= RESPAWN_MAX and islandHome(g, name, pos, "respawned") ~= false then s.died[lower(name)] = nil end
        end
        return
    end
    if typ == 30 then
        addThing(g, e.entityId, "stand", {}, pos)
        return
    end
    if typ and typ >= 50 then
        local meta = metaMap(e.metadata)
        addThing(g, e.entityId, "mob", { type = typ, kindKey = k, meta = meta, name = customName(meta) }, pos)
    end
end)

starfish.events.on("entity:metadata", function(e)
    local g = C.game()
    local id = e.entity and (e.entity.entityId or e.entity.id)
    local t = g and g.x and id and g.x.things[id]
    if not t then return end
    local meta = metaMap(e.metadata)
    if t.meta then for k, v in pairs(meta) do t.meta[k] = v end end
    if meta[2] ~= nil then t.name = customName(meta) end
    local ent = starfish.entities.byId(id)
    if ent and ent.state and ent.state.invisible then t.invisible = true end
end)

local WOOD = { [5] = { "oak", "spruce", "birch", "jungle", "acacia", "dark_oak" }, [17] = { "oak_log", "spruce_log", "birch_log", "jungle_log" }, [162] = { "acacia_log", "dark_oak_log" } }

starfish.events.on("entity:equipmentChange", function(e)
    local g = C.game()
    if not g then return end
    local ent = e.entity or {}
    local id = ent.entityId or ent.id
    local slot = SLOTS[e.slot]
    if not e.isPlayer then
        local t = g.x and id and g.x.things[id]
        if t and slot then
            t.equip[slot] = e.item
            t.changedAt = now()
            islandSoon(g)
        end
        return
    end
    if slot ~= "held" or type(e.item) ~= "table" then return end
    local name = nameOfUuid(g, ent.uuid)
    if not name then return end
    local num = itemNum(e.item)
    -- Wood skin: the planks or logs they hold (oak planks = no skin).
    local woods = WOOD[num]
    local dmg = itemDamage(e.item)
    if woods and dmg then
        local kind = num == 5 and woods[dmg + 1] or woods[(dmg % (num == 162 and 2 or 4)) + 1]
        if kind and kind ~= "oak" then C.addClue(g, name, "wood", { "woodSkin_" .. kind }, true) end
    end
    -- After the game: an item named after their victory dance.
    if g.overAt and e.item.name then
        local words = " " .. plain(e.item.name):lower():gsub("[^a-z ]", ""):gsub("%s+", " ") .. " "
        local best, bestId = 0, nil
        for danceName, danceId in pairs(D.DANCE_ITEMS) do
            if danceName ~= "none" and #danceName > best and words:find(" " .. danceName .. " ", 1, true) then best, bestId = #danceName, danceId end
        end
        if bestId then C.addClue(g, name, "dance", { bestId }, true) return end
        for _, d in ipairs(D.DANCE_ITEM_NAMES) do
            if words:find(" " .. d.words .. " ", 1, true) then C.addClue(g, name, "dance", d.ids, d.sure == true, not d.sure and "not confirmed yet" or nil) return end
        end
    end
end)

starfish.events.on("entity:move", function(e)
    local g = C.game()
    local ent = e.entity
    if not g or not g.x or not ent then return end
    local t = g.x.things[ent.entityId or ent.id]
    if t then
        local live = starfish.entities.byId(t.id)
        local p = (e.position and C.posOf(e)) or (live and C.posOf(live))
        if p then t.moved = math.max(t.moved, dist(t.pos, p)) end
        return
    end
    -- Respawning shows up as a jump back to the island.
    if e.position and not e.delta and ent.uuid and not isNpcUuid(ent.uuid) then
        local name = nameOfUuid(g, ent.uuid)
        local died = name and g.x.died[lower(name)]
        if died then
            local since = now() - died
            if since >= RESPAWN_MIN and since <= RESPAWN_MAX and islandHome(g, name, C.posOf(e), "respawned") ~= false then g.x.died[lower(name)] = nil end
        end
    end
end)

starfish.events.on("entity:attach", function(e)
    local g = C.game()
    if not g or not g.overAt or not e.vehicle or e.leash then return end
    local rider = e.entity and e.entity.uuid and nameOfUuid(g, e.entity.uuid)
    if not rider then return end
    local vid = type(e.vehicle) == "table" and e.vehicle.entityId or e.vehicle
    local vkind = (type(e.vehicle) == "table" and e.vehicle.kind) or C.kindOfId(vid)
    local typ, k = mobType(vkind)
    local key = typ or (k and k:find("minecart") and "object") or nil
    if key then S(g).rides[#S(g).rides + 1] = { rider = rider, type = key } end
end)

starfish.events.on("world:blockChange", function(e)
    local g = C.game()
    if not g or not g.startAt then return end
    local id, m = tonumber(e.blockId) or 0, tonumber(e.meta) or 0
    if g.overAt then
        if id ~= 0 then C.tally("block", tostring(id), { x = e.x + 0.5, y = e.y, z = e.z + 0.5 }, 1) end
        return
    end
    local at = now() - g.startAt
    local list = S(g).startBlocks
    if at <= TOPPER_WATCH_MS and #list < 20000 then list[#list + 1] = { x = e.x, y = e.y, z = e.z, id = id, m = m, at = at } end
end)

starfish.events.on("world:sound", function(e)
    local g = C.game()
    if not g or type(e.name) ~= "string" then return end
    local pitch = tonumber(e.pitch) or 0
    if pitch > 4 then pitch = pitch / 63 end
    local key = ("%s|%.2f|%.1f"):format(e.name, pitch, tonumber(e.volume) or 0)
    local id = D.DEATH_CRY_SOUNDS[key]
    local pos = C.posOf(e)
    if not id or not pos then return end
    local cries = S(g).cries
    local cry = { id = id, sound = e.name, pos = pos, at = now() }
    cries[#cries + 1] = cry
    if #cries > 30 then table.remove(cries, 1) end
    cryMatch(g, cry)
end)

-- Glyphs: coloured dust over a player's head when they pick up a diamond or emerald.

local function glyphEnd(g, cap)
    local s = S(g)
    for i, c in ipairs(s.glyphs) do if c == cap then table.remove(s.glyphs, i) break end end
    local cols = {}
    for c in pairs(cap.colours) do cols[#cols + 1] = c end
    if #cols < GLYPH_MIN then return end
    table.sort(cols)
    local look = table.concat(cols, "|")
    local id = D.ISLAND_LOOKS.glyph[look]
    if not id then
        local hits = {}
        for l, gid in pairs(D.ISLAND_LOOKS.glyph) do
            local own, n = {}, 0
            for _, c in ipairs(split(l, "|")) do own[c] = true; n = n + 1 end
            local all = true
            for _, c in ipairs(cols) do if not own[c] then all = false end end
            if all and #cols >= n * 0.8 then hits[#hits + 1] = gid end
        end
        if #hits == 1 then id = hits[1] end
    end
    local crowded = false
    for _, o in ipairs(s.glyphDone) do
        if o.name ~= cap.name and math.abs(o.at - cap.at) < GLYPH_MS and flat(o.pos, cap.pos) <= GLYPH_BLOCKS * 2 then crowded = true end
    end
    s.glyphDone[#s.glyphDone + 1] = cap
    if #s.glyphDone > 50 then table.remove(s.glyphDone, 1) end
    log("glyph: %s %d colours %s = %s", cap.name, #cols, look, tostring(id))
    if not id then return end
    C.addClue(g, cap.name, "glyph", idsOf(id), not crowded, crowded and "another player's glyph was right there" or nil)
end

starfish.events.on("entity:collect", function(e)
    local g = C.game()
    if not g then return end
    local collectedId = type(e.collected) == "table" and (e.collected.entityId or e.collected.id) or e.collected
    local num = C.itemOf(collectedId)
    if num ~= 264 and num ~= 388 then return end
    local who = type(e.collector) == "table" and e.collector or starfish.entities.byId(e.collector)
    local name = who and who.uuid and nameOfUuid(g, who.uuid)
    local live = who and starfish.entities.byId(who.entityId or who.id)
    local pos = (live and C.posOf(live)) or C.posOf(who)
    if not name or not pos then return end
    local s = S(g)
    for _, c in ipairs(s.glyphs) do if c.name == name and now() - c.at < GLYPH_MS then return end end
    local cap = { name = name, pos = pos, at = now(), colours = {} }
    s.glyphs[#s.glyphs + 1] = cap
    starfish.timers.delay(GLYPH_MS + 200, function() glyphEnd(g, cap) end)
end)

starfish.events.on("world:particle", function(e)
    local g = C.game()
    if not g or not g.x or #g.x.glyphs == 0 or D.PARTICLE_NAMES[e.particleId] ~= "reddust" or (e.count or 0) ~= 0 then return end
    local pos, off = C.posOf(e), e.offset or {}
    if not pos then return end
    local function c(v) return math.floor(math.max(0, math.min(1, tonumber(v) or 0)) * 255 + 0.5) end
    local key = c(off.x) .. "," .. c(off.y) .. "," .. c(off.z)
    for _, cap in ipairs(g.x.glyphs) do
        local up = pos.y - cap.pos.y
        if now() - cap.at <= GLYPH_MS and flat(cap.pos, pos) <= GLYPH_BLOCKS and up >= GLYPH_UP_LO and up <= GLYPH_UP_HI then
            cap.colours[key] = (cap.colours[key] or 0) + 1
        end
    end
end)

-- (For tests.)
X._topperLook, X._topperNear, X._figurineId, X._mobLook, X._lookId = topperLook, topperNear, figurineId, mobLook, lookId
X._skins = skins
return X
end
