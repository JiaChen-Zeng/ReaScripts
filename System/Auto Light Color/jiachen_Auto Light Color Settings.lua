-- @description Auto Light Color - Settings
-- @author Jiachen
-- @version 0.1.0
-- Optional GUI. Closing it never stops the background monitor.

local source = debug.getinfo(1, "S").source
local here = assert(source:match("^@(.+[\\/])"), "Cannot locate settings script folder")
local Core = assert(loadfile(here .. "jiachen_Auto Light Color Core.lua"))()
if not reaper.ImGui_GetBuiltinPath then
  reaper.MB("Install ReaImGui via ReaPack to open Auto Light Color settings.", "Auto Light Color", 0)
  return
end
package.path = reaper.ImGui_GetBuiltinPath() .. "/?.lua;" .. package.path
local ok, ImGui = pcall(function() return require("imgui")("0.10") end)
if not ok then
  reaper.MB("Could not load ReaImGui 0.10 or later:\n" .. tostring(ImGui), "Auto Light Color", 0)
  return
end

local ctx = ImGui.CreateContext("Auto Light Color - Settings")
local settings = Core.read_settings(reaper)
local preview = {}
math.randomseed(math.floor(reaper.time_precise() * 1000000) % 2147483647)

local function refresh_preview()
  preview = {}
  local last_lab = nil
  for i = 1, 16 do
    local n = last_lab and {last_lab} or {}
    local c = Core.pick_color(settings, n)
    preview[#preview+1] = c
    last_lab = c.lab
  end
end
refresh_preview()

local function save(key, value)
  settings[key] = value
  Core.save_setting(reaper, key, value)
  refresh_preview()
end

local function draw_slider(label,key,min,max)
  local changed,value = ImGui.SliderInt(ctx,label,settings[key],min,max)
  if changed then save(key,value) end
end

local function loop()
  local visible,open = ImGui.Begin(ctx,"Auto Light Color - Settings",true)
  if visible then
    local changed,enabled = ImGui.Checkbox(ctx,"Auto-color new tracks",settings.enabled == 1)
    if changed then save("enabled",enabled and 1 or 0) end
    local heartbeat = tonumber(reaper.GetExtState(Core.SECTION,"heartbeat")) or 0
    local active = heartbeat > 0 and (reaper.time_precise()-heartbeat) < 1
    ImGui.Text(ctx,active and "Monitor: RUNNING (window can be closed)"
                            or "Monitor: NOT RUNNING (will start with REAPER)")
    ImGui.Separator(ctx)
    draw_slider("Minimum lightness (%)","min_lightness",65,95)
    draw_slider("Maximum lightness (%)","max_lightness",65,98)
    if settings.max_lightness < settings.min_lightness then
      save("max_lightness",settings.min_lightness)
    end
    ImGui.TextWrapped(ctx,"Perceptual lightness: higher = lighter. Default: 79-90%.")
    draw_slider("Vibrancy (%)","vibrancy",0,100)
    draw_slider("Vibrancy variation (%)","variation",0,100)
    draw_slider("Neighbor separation (%)","separation",0,20)
    ImGui.TextWrapped(ctx,"Separation is a minimum OKLab color distance (0-0.20). If no candidate passes, the best available is chosen. Both adjacent tracks are checked.")
    ImGui.Separator(ctx)
    ImGui.Text(ctx,"Preview (new colors generated with neighbor avoidance)")
    for i,c in ipairs(preview) do
      local packed = (c.r << 24) | (c.g << 16) | (c.b << 8) | 255
      ImGui.ColorButton(ctx,"##sample"..i,packed,ImGui.ColorEditFlags_NoTooltip,31,29)
      if i % 8 ~= 0 then ImGui.SameLine(ctx) end
    end
    if ImGui.Button(ctx,"Generate new preview") then refresh_preview() end
    ImGui.SameLine(ctx)
    if ImGui.Button(ctx,"Restore defaults") then
      for key,value in pairs(Core.DEFAULTS) do
        Core.save_setting(reaper,key,value)
      end
      settings = Core.read_settings(reaper)
      refresh_preview()
    end
    ImGui.Separator(ctx)
    ImGui.TextWrapped(ctx,"Only brand-new uncolored tracks are changed. Existing and manually colored tracks are left untouched. Close this window without stopping auto-coloring.")
  end
  ImGui.End(ctx)
  if open then
    reaper.defer(loop)
  end
  -- The ReaImGui context is released automatically when the script exits.
end
reaper.defer(loop)
