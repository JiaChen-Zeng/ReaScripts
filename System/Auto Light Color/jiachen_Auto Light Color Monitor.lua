-- @description Auto Light Color - Monitor (runs silently, no GUI)
-- @author Jiachen
-- @version 0.1.0
-- REAPER 7 / Lua. This is a long-running deferred ReaScript.
-- No Undo_DoUndo / Undo_DoRedo / Undo_BeginBlock calls are used.

local info = debug.getinfo(1, "S").source
local here = info:match("^@(.+[\\/])")
assert(here, "Cannot determine Auto Light Color script folder")
local Core = assert(loadfile(here .. "jiachen_Auto Light Color Core.lua"))()
local api = reaper
local SECTION = Core.SECTION
local now = api.time_precise()
local previous_heartbeat = tonumber(api.GetExtState(SECTION, "heartbeat")) or -100
if now - previous_heartbeat < 1.0 then
  -- Prevent multiple instances (e.g. manually running while startup already active).
  return
end
local token = tostring(now)
api.SetExtState(SECTION, "owner", token, false)
api.SetExtState(SECTION, "heartbeat", tostring(now), false)

math.randomseed(math.floor((now * 1000000) % 2147483647))
for _ = 1, 4 do math.random() end

local projects = {}
local settings = Core.read_settings(api)
local revision = api.GetExtState(SECTION, "revision")
local next_scan = 0

local function get_identity(tr)
  return api.GetTrackGUID(tr)
end

local function get_color(tr)
  local native = api.GetTrackColor(tr)
  if not native or native == 0 then return nil end
  local r,g,b = api.ColorFromNative(native)
  return Core.rgb_to_lab(r,g,b)
end

local function set_color(tr, candidate)
  local native = api.ColorToNative(candidate.r,candidate.g,candidate.b) | 0x1000000
  api.SetMediaTrackInfo_Value(tr, "I_CUSTOMCOLOR", native)
end

local function scan(proj)
  local n = api.CountTracks(proj)
  local current = {}
  local order = {}
  for i = 0, n - 1 do
    local tr = api.GetTrack(proj, i)
    if tr then
      local guid = get_identity(tr)
      order[#order+1] = {track=tr, guid=guid}
      current[guid] = true
    end
  end
  local state = projects[tostring(proj)]
  if not state then
    -- The initial state is a baseline: never recolor an opened project.
    state = {seen={}, present={}, colors={}, change=api.GetProjectStateChangeCount(proj), count=n}
    for guid in pairs(current) do state.seen[guid] = true end
    state.present = current
    projects[tostring(proj)] = state
    return
  end

  -- Preserve existing track colors. Color only new uncolored tracks.
  local recolored = false
  for i, entry in ipairs(order) do
    local new = not state.seen[entry.guid]
    local restored = state.seen[entry.guid] and not state.present[entry.guid]
    local has_color = api.GetTrackColor(entry.track) ~= 0
    if settings.enabled == 1 and not has_color then
      if restored and state.colors[entry.guid] then
        -- Redo of a track insertion: restore its original generated color.
        set_color(entry.track, state.colors[entry.guid])
        recolored = true
      elseif new then
        local neighbors = {}
        if i > 1 then
          local above = get_color(order[i-1].track)
          if above then neighbors[#neighbors+1] = above end
        end
        if i < #order then
          local below = get_color(order[i+1].track)
          if below then neighbors[#neighbors+1] = below end
        end
        local candidate = Core.pick_color(settings, neighbors)
        set_color(entry.track, candidate)
        state.colors[entry.guid] = candidate
        recolored = true
      end
    end
    state.seen[entry.guid] = true
  end
  state.present = current
  state.change = api.GetProjectStateChangeCount(proj)
  state.count = n
  if recolored then api.UpdateArrange() end
end

local function loop()
  if api.GetExtState(SECTION, "owner") ~= token then return end
  local current_time = api.time_precise()
  if current_time >= next_scan then
    next_scan = current_time + 0.12
    api.SetExtState(SECTION, "heartbeat", tostring(current_time), false)

    local new_revision = api.GetExtState(SECTION, "revision")
    if new_revision ~= revision then
      revision = new_revision
      settings = Core.read_settings(api)
    end

    local proj = api.EnumProjects(-1)
    if proj then
      local state = projects[tostring(proj)]
      local count = api.CountTracks(proj)
      local changed = api.GetProjectStateChangeCount(proj)
      if not state or state.change ~= changed or state.count ~= count then
        scan(proj)
      end
    end
  end
  api.defer(loop)
end

api.set_action_options(1 | 4) -- one instance; show ON in REAPER Action List
api.atexit(function()
  if api.GetExtState(SECTION,"owner") == token then
    api.DeleteExtState(SECTION,"owner",false)
    api.DeleteExtState(SECTION,"heartbeat",false)
    api.set_action_options(8) -- show OFF when the active monitor exits
  end
end)
api.defer(loop)
