-- @description Auto Light Color - Startup (internal)
-- @author Jiachen
-- @version 0.1.0

-- Register optional GUI and the silent monitor using the existing global startup.
local resource = reaper.GetResourcePath()
local relative_dir = "Jiachen Scripts/System/Auto Light Color/"
local absolute_dir = resource .. "/Scripts/" .. relative_dir

local function find_action(relative_file)
  local file = io.open(resource .. "/reaper-kb.ini", "r")
  if not file then return 0 end
  local id = 0
  for line in file:lines() do
    if line:find(relative_file, 1, true) then
      local token = line:match("^SCR%s+%d+%s+%d+%s+(RS[%x]+)")
      if token then id = reaper.NamedCommandLookup("_" .. token) end
      if id > 0 then break end
    end
  end
  file:close()
  return id
end

local function ensure_action(script)
  local rel = relative_dir .. script
  local id = find_action(rel)
  if id > 0 then return id end
  return reaper.AddRemoveReaScript(true, 0, absolute_dir .. script, true)
end

local settings_action = ensure_action("jiachen_Auto Light Color Settings.lua")
local monitor_action = ensure_action("jiachen_Auto Light Color Monitor.lua")
if settings_action > 0 and monitor_action > 0 then
  -- SWS Auto Color would otherwise color new tracks before our monitor.
  local sws_action = reaper.NamedCommandLookup("_SWSAUTOCOLOR_ENABLE")
  if sws_action > 0 and reaper.GetToggleCommandState(sws_action) == 1 then
    reaper.Main_OnCommand(sws_action, 0)
  end
  reaper.Main_OnCommand(monitor_action, 0)
else
  reaper.ShowConsoleMsg("Auto Light Color: failed to register scripts.\n")
end
