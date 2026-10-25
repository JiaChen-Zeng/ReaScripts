-- @description MIDI Mixer Controller
-- @author Jiachen
-- @version 1.8.9

-- Current mixer layout (documentation only; no FX index/order locking):
-- Global Monitoring FX: [0] TR5 Metering, [1] TDR Prism,
--                       [2] Youlean Loudness Meter 2,
--                       [3] MUtility (Silence Toggle), [4] ARC 4.
-- VSX track FX:         [0] VSX, [1] MUtility (Silence Toggle).
-- MUtility Switch 0 = silence, 1 = 0 dB; set Switch Time in each MUtility GUI.
-- The normalized Volume ramps linearly, with audio amplitude ~= x^2.
-- The controller changes only each Switch target.
-- All FX and parameter locations below are resolved by name.

-- Resolves the system-wide mixer project once at startup by project filename,
-- regardless of which REAPER tab is selected. Background control uses project
-- track/FX pointers without switching tabs. Idle saves wait ten minutes after
-- REAPER loses focus, regardless of input in other applications.

--#region CONSTANTS

local SCRIPT_IDENTIFIER = "Jiachen_MIDI Mixer Controller"

local DEVICE_TO_MONITOR = "REAPER Mixer"
local CHANNEL_TO_MONITOR = 16

local MIXER_PROJECT_NAME = "Reaper System-Wide Mixer.rpp"

local function find_mixer_project()
  local matched_project = nil
  local i = 0
  while true do
    local project, filename = reaper.EnumProjects(i, "")
    if not project then break end

    -- Compare the filename only; a project may be opened from any directory.
    local name = filename and filename:gsub("\\", "/"):match("([^/]+)$")
    if name and name:lower() == MIXER_PROJECT_NAME:lower() then
      if matched_project then
        error("Multiple open mixer projects named " .. MIXER_PROJECT_NAME)
      end
      matched_project = project
    end
    i = i + 1
  end
  assert(matched_project, "Open mixer project not found: " .. MIXER_PROJECT_NAME)
  return matched_project
end

local THIS_PROJECT = find_mixer_project()
local IDLE_SAVE_SECONDS = 10 * 60

--#endregion

--#region HELPER FUNCTIONS

local function get_midi_device_index_by_name(name)
  local n = reaper.GetNumMIDIInputs()
  for i = 0, n - 1 do
      local _, this_name = reaper.GetMIDIInputName(i, "")
      if this_name == name then
          return i
      end
  end

  error("Can't find the device: " .. name)
end

local MIDI_DEVICE = get_midi_device_index_by_name(DEVICE_TO_MONITOR)

local function get_track_by_name(track_name)
  local track_count = reaper.CountTracks(THIS_PROJECT)
  for i = 0, track_count - 1 do
    local track = reaper.GetTrack(THIS_PROJECT, i)
    local _, current_track_name = reaper.GetSetMediaTrackInfo_String(track, "P_NAME", "", false)
    if current_track_name == track_name then
      return track
    end
  end
  
  error("Track name specified in controller is wrong: " .. track_name)
end

local function get_fx_by_name(track, fx_name)
  local fx_count = reaper.TrackFX_GetCount(track)
  for i = 0, fx_count - 1 do
    local _, current_fx_name = reaper.TrackFX_GetFXName(track, i)
    if current_fx_name == fx_name then
      return i
    end
  end
  
  error("FX name specified in controller is wrong: " .. fx_name)
end

--#endregion

--#region CONTROLLER ACTION FUNCTIONS

local function to_mute_all(mute)
  return function(track)
    local mute_number
    if mute then mute_number = 1 else mute_number = 0 end
    
    -- First mute the track itself
    reaper.SetMediaTrackInfo_Value(track, "B_MUTE", mute_number)
    
    -- Get track index
    local track_idx = reaper.GetMediaTrackInfo_Value(track, "IP_TRACKNUMBER") - 1
    local track_depth = reaper.GetMediaTrackInfo_Value(track, "I_FOLDERDEPTH")
    
    -- Only process descendants if this is a folder track
    if track_depth <= 0 then return end
    
    local current_depth = 1 -- Start at 1 because we're inside a folder
    local track_count = reaper.CountTracks(THIS_PROJECT)
    
    -- Iterate through potential child tracks
    for i = track_idx + 1, track_count - 1 do
      local child_track = reaper.GetTrack(THIS_PROJECT, i)
      local child_depth = reaper.GetMediaTrackInfo_Value(child_track, "I_FOLDERDEPTH")
      
      -- Update current depth
      current_depth = current_depth + child_depth
      
      -- If we've come back to the original depth or higher, we're done
      if current_depth <= 0 then break end
      
      -- Mute this track
      reaper.SetMediaTrackInfo_Value(child_track, "B_MUTE", mute_number)
    end
  end
end

local function to_preset(preset_name_or_callback)
  local t = type(preset_name_or_callback)
  if t == "string" then
    return function(track, fx)
      reaper.TrackFX_SetPreset(track, fx, preset_name_or_callback)
    end
  elseif t == "function" then
    return function(track, fx, cc_value)
      reaper.TrackFX_SetPreset(track, fx, preset_name_or_callback(cc_value))
    end
  else
    error("Wrong preset parameter: " .. tostring(preset_name_or_callback))
  end
end

local function to_bypass(bypass)
  return function(track, fx_or_cc_value, cc_value)
    if cc_value == nil then -- 2 params. for all fxs in track
      reaper.SetMediaTrackInfo_Value(track, "I_FXEN", bypass and 0 or 1)
    else -- 3 params, for one fx
      reaper.TrackFX_SetEnabled(track, fx_or_cc_value, not bypass)
    end
  end
end

-- Find the speaker's ARC 4 and MUtility in global Monitoring FX by name.
local function get_monitor_speaker_fx()
  local master = reaper.GetMasterTrack(THIS_PROJECT)
  local arc_fx, fade_fx
  for i = 0, reaper.TrackFX_GetRecCount(master) - 1 do
    local fx = 0x1000000 + i
    local _, name = reaper.TrackFX_GetFXName(master, fx)
    if name == "VST3: ARC 4 (IK Multimedia)" then arc_fx = fx end
    if name == "VST3: MUtility (MeldaProduction)" then fade_fx = fx end
  end
  if not arc_fx or not fade_fx then
    error("Monitoring FX: ARC 4 or MUtility missing")
  end
  return master, arc_fx, fade_fx
end

local function get_headphone_fade_fx()
  local vsx = get_track_by_name("VSX")
  for i = 0, reaper.TrackFX_GetCount(vsx) - 1 do
    local _, name = reaper.TrackFX_GetFXName(vsx, i)
    if name == "VST3: MUtility (MeldaProduction)" then return vsx, i end
  end
  error("VSX: MUtility not found")
end

local function get_named_fx_param(track, fx, wanted_name)
  for i = 0, reaper.TrackFX_GetNumParams(track, fx) - 1 do
    local _, name = reaper.TrackFX_GetParamName(track, fx, i)
    if name == wanted_name then return i end
  end
  error("MUtility parameter missing: " .. wanted_name)
end

local function set_arc4_enabled(master, arc_fx, enabled)
  if reaper.TrackFX_GetEnabled(master, arc_fx) ~= enabled then
    reaper.TrackFX_SetEnabled(master, arc_fx, enabled)
  end
end

local function set_fade_target(track, fx, param, on)
  reaper.TrackFX_SetParamNormalized(track, fx, param, on and 1 or 0)
end

local monitor_transition = nil
local mixer_save_pending = false
local last_mixer_change_time = reaper.time_precise()
local last_reaper_focus_time = reaper.time_precise()

local function queue_mixer_save()
  mixer_save_pending = true
  last_mixer_change_time = reaper.time_precise()
  reaper.MarkProjectDirty(THIS_PROJECT)
end

local function mixer_project_still_open()
  local index = 0
  while true do
    local project = reaper.EnumProjects(index)
    if not project then return false end
    if project == THIS_PROJECT then return true end
    index = index + 1
  end
end

local function reaper_has_foreground()
  -- js_ReaScriptAPI is installed with portable REAPER. Without it, do not
  -- attempt an automatic tab switch (manual mixer-tab save still works).
  if not (reaper.JS_Window_GetForeground and
          reaper.JS_Window_GetRelated and
          reaper.JS_Window_GetRoot) then return nil end

  local foreground = reaper.JS_Window_GetForeground()
  local main = reaper.GetMainHwnd()
  if not foreground or not main then return nil end

  -- The main window and docked editors are considered REAPER activity.
  if foreground == main or reaper.JS_Window_GetRoot(foreground) == main then
    return true
  end

  -- Treat REAPER-owned floating plugin/editor/dialog windows as activity too.
  local window = foreground
  for _ = 1, 16 do
    local owner = reaper.JS_Window_GetRelated(window, "OWNER")
    if not owner or owner == window then break end
    if owner == main or reaper.JS_Window_GetRoot(owner) == main then
      return true
    end
    window = owner
  end

  -- REAPER-created standalone windows may not be owned by its main window.
  -- Matching the application instance covers those windows as well.
  if reaper.JS_Window_GetLongPtr then
    local main_instance = reaper.JS_Window_GetLongPtr(main, "INSTANCE")
    local foreground_instance = reaper.JS_Window_GetLongPtr(foreground, "INSTANCE")
    if main_instance and foreground_instance == main_instance then
      return true
    end
  end

  return false
end

local function can_idle_save()
  if (reaper.GetAllProjectPlayStates(nil) & 4) ~= 0 then return false end

  -- Standard modal dialogs disable their owner window.
  -- If state cannot be determined, postpone the save.
  if not reaper.JS_Window_GetLong then return false end
  local main_window = reaper.GetMainHwnd()
  if not main_window then return false end
  local style = reaper.JS_Window_GetLong(main_window, "STYLE")
  if not style or (style & 0x08000000) ~= 0 then return false end

  return true
end

local function save_mixer_if_active()
  -- Project-saving APIs may activate their target tab, so never call them
  -- while the user is working in another project.
  if not mixer_save_pending or monitor_transition then return end
  if reaper.EnumProjects(-1) ~= THIS_PROJECT then return end

  reaper.Main_SaveProject(THIS_PROJECT, false)
  mixer_save_pending = false
end

local function save_mixer_if_idle()
  if not mixer_save_pending or monitor_transition then return end
  if reaper.EnumProjects(-1) == THIS_PROJECT then return end
  if not mixer_project_still_open() then return end

  local now = reaper.time_precise()
  local foreground = reaper_has_foreground()
  if foreground ~= false then
    -- Focus in REAPER (or an undetectable foreground) postpones idle saves.
    if foreground then last_reaper_focus_time = now end
    return
  end

  -- Both conditions must hold. MIDI actions do not reset the REAPER focus timer,
  -- but a recent mixer change must have had time to settle before saving.
  if now - last_reaper_focus_time < IDLE_SAVE_SECONDS then return end
  if now - last_mixer_change_time < IDLE_SAVE_SECONDS then return end
  if not can_idle_save() then return end
  if reaper_has_foreground() ~= false then return end

  local selected_project = reaper.EnumProjects(-1)
  reaper.PreventUIRefresh(1)
  local saved, save_error = pcall(function()
    reaper.SelectProjectInstance(THIS_PROJECT)
    if reaper.EnumProjects(-1) ~= THIS_PROJECT then
      error("Cannot select mixer project for idle save")
    end
    reaper.Main_SaveProject(THIS_PROJECT, false)
  end)

  -- Always attempt to restore the previous tab, even if the save failed.
  local restored, restore_error = pcall(function()
    if reaper.EnumProjects(-1) ~= selected_project then
      reaper.SelectProjectInstance(selected_project)
    end
    if reaper.EnumProjects(-1) ~= selected_project then
      error("Cannot restore the project after idle save")
    end
  end)
  reaper.PreventUIRefresh(-1)

  if not restored then error(restore_error) end
  if not saved then error(save_error) end
  mixer_save_pending = false
end

local function request_monitor_mode(mode)
  local want_speaker = mode == "speaker" or mode == "both"
  local want_vsx = mode == "vsx" or mode == "both"

  local master, arc_fx, speaker_fx = get_monitor_speaker_fx()
  local vsx, headphone_fx = get_headphone_fade_fx()
  local speaker_param = get_named_fx_param(master, speaker_fx, "Silence Toggle")
  local speaker_volume = get_named_fx_param(master, speaker_fx, "Volume (Basic)")
  local headphone_param = get_named_fx_param(vsx, headphone_fx, "Silence Toggle")
  local headphone_volume = get_named_fx_param(vsx, headphone_fx, "Volume (Basic)")

  -- Wake the VSX processing chain before its fade-in.
  if want_vsx and reaper.GetMediaTrackInfo_Value(vsx, "B_MUTE") ~= 0 then
    reaper.SetMediaTrackInfo_Value(vsx, "B_MUTE", 0)
  end
  -- MUtility handles the fade without hardware-send volume automation.
  set_fade_target(vsx, headphone_fx, headphone_param, want_vsx)

  local pending_arc = false
  if want_speaker and not reaper.TrackFX_GetEnabled(master, arc_fx) then
    -- ARC 4 is enabled only when the final speaker gain has reached silence.
    if reaper.TrackFX_GetParamNormalized(master, speaker_fx, speaker_volume) == 0 then
      set_arc4_enabled(master, arc_fx, true)
      set_fade_target(master, speaker_fx, speaker_param, true)
    else
      set_fade_target(master, speaker_fx, speaker_param, false)
      pending_arc = true
    end
  else
    set_fade_target(master, speaker_fx, speaker_param, want_speaker)
  end

  monitor_transition = {
    master = master, arc_fx = arc_fx,
    speaker_fx = speaker_fx, speaker_param = speaker_param, speaker_volume = speaker_volume,
    vsx = vsx, headphone_fx = headphone_fx, headphone_volume = headphone_volume,
    want_speaker = want_speaker, want_vsx = want_vsx, pending_arc = pending_arc
  }
end

local function to_monitor_mode(mode)
  return function(_) request_monitor_mode(mode) end
end

local function update_monitor_transition()
  local tr = monitor_transition
  if not tr then return end

  if tr.pending_arc and
     reaper.TrackFX_GetParamNormalized(tr.master, tr.speaker_fx, tr.speaker_volume) == 0 then
    set_arc4_enabled(tr.master, tr.arc_fx, true)
    set_fade_target(tr.master, tr.speaker_fx, tr.speaker_param, true)
    tr.pending_arc = false
  end

  local speaker_level = reaper.TrackFX_GetParamNormalized(tr.master, tr.speaker_fx, tr.speaker_volume)
  local headphone_level = reaper.TrackFX_GetParamNormalized(tr.vsx, tr.headphone_fx, tr.headphone_volume)
  local speaker_end = tr.want_speaker and 1 or 0
  local headphone_end = tr.want_vsx and 1 or 0

  if not tr.pending_arc and speaker_level == speaker_end and headphone_level == headphone_end then
    if not tr.want_speaker then set_arc4_enabled(tr.master, tr.arc_fx, false) end
    -- The headphone output is now silent; mute its track to stop VSX processing.
    if not tr.want_vsx then reaper.SetMediaTrackInfo_Value(tr.vsx, "B_MUTE", 1) end
    monitor_transition = nil
    queue_mixer_save()
  end
end

local function to_map(min, max) -- Untested
  -- map [min, max] if params passed
  if min == nil and max == nil then
    return function(track, fx, param, cc_value)
      reaper.TrackFX_SetParam(track, fx, param, min + (max - min) * (cc_value / 127))
    end
  end

  -- map full range if no params
  if min ~= nil and max ~= nil then
    return function(track, fx, param, cc_value)
      reaper.TrackFX_SetParamNormalized(track, fx, param, cc_value / 127)
    end
  end
  
  error("to_map: Invalid Arguments: " .. min .. ", " .. max)
end

local function to_send(receive_track_name, send)
  return function(track)
    local receive_track = get_track_by_name(receive_track_name)
    local send_count = reaper.GetTrackNumSends(track, 0)
    for i = 0, send_count - 1 do
      local dest_track = reaper.BR_GetMediaTrackSendInfo_Track(track, 0, i, 1)
      if dest_track == receive_track then
        local mute_num
        if send then mute_num = 0 else mute_num = 1 end
        reaper.SetTrackSendInfo_Value(track, 0, i, "B_MUTE", mute_num)
        return
      end
    end
    
    error("to_send: Can't find the receive track specified: " .. receive_track_name .. "\n")
  end 
end

local JIACHEN_CONTROLLER = {
  -- Speakers: Monitoring FX MUtility. Headphones: VSX-track MUtility.
  -- Consumer/Phone keep independent Matrix routes; both REAPER outputs fade off.
  [0] = { PreMaster = {_action = to_monitor_mode("speaker")} },
  [1] = { PreMaster = {_action = to_monitor_mode("vsx")} },
  [2] = function(value)
    return { PreMaster = {_action = to_monitor_mode(value == 127 and "both" or "speaker")} }
  end,
  [3] = { PreMaster = {_action = to_monitor_mode("off")} },
  [4] = { PreMaster = {_action = to_monitor_mode("off")} },
  [5] = { PreMaster = {_action = to_monitor_mode("off")} },
  [6] = { PreMaster = {_action = to_monitor_mode("off")} },

  [10] = { VSX = { ["VST3: VSX (Steven Slate)"] = {_action = to_preset("Spitfire LA")} } },
  [11] = { VSX = { ["VST3: VSX (Steven Slate)"] = {_action = to_preset("Human Linear")} } },
  [12] = { VSX = { ["VST3: VSX (Steven Slate)"] = {_action = to_preset("Steven Mono")} } },
  [13] = { VSX = { ["VST3: VSX (Steven Slate)"] = {_action = to_preset("Audiophile")} } },
  [14] = { VSX = { ["VST3: VSX (Steven Slate)"] = {_action = to_preset("SUV 2")} } },
  [15] = { VSX = { ["VST3: VSX (Steven Slate)"] = {_action = to_preset("Club Indey")} } },
  
  [20] = function (value)
    return { ["Non-Inst"] = { ["VST3: kHs Gain (Kilohearts)"] = { _action = to_bypass(value ~= 127) } } }
  end,
  
  [21] = function (value)
    return {
      ["Soft Synth"] = {_action = to_mute_all(value == 127)},
    }
  end,
  [24] = function (value)
    return { ["OBS"] = {_action = to_send("Non-Inst", value == 127)} }
  end,
  
  [30] = {
    PreMaster = { ["VST3: kHs Channel Mixer (Kilohearts)"] = {_action = to_bypass(true)} }
  },
  [31] = {
    PreMaster = { ["VST3: kHs Channel Mixer (Kilohearts)"] = {_action = {to_preset("Cross"), to_bypass(false)}} }
  },
  [32] = {
    PreMaster = { ["VST3: kHs Channel Mixer (Kilohearts)"] = {_action = {to_preset("Mono"), to_bypass(false)}} }
  },
  [33] = {
    PreMaster = { ["VST3: kHs Channel Mixer (Kilohearts)"] = {_action = to_bypass(true)} }
  }
}

--#endregion

--#region MIDI - ACTION PROCESSING

local function get_actions_by_value(controller, cc, cc_value)
  local actions = controller[cc]
  if type(actions) == "function" then
    return actions(cc_value)
  end
  
  if type(actions) == "table" then
    return actions
  end
  
  if actions == nil then return nil end
  
  error("Bad syntax for controller. The action list needs to be a generator `function` or a `table`")
end

local function is_action_callback(key, value)
  local t = type(value)
  return key == "_action" and (t == "function" or t == "table")
end

local function execute_action_callback(callback, ...)
  local t = type(callback)
  if t == "function" then
    callback(...)
  elseif t == "table" then
    for _, fn in ipairs(callback) do fn(...) end
  else
    error("Action callback should be a `function` or a `table` of `function`s. Now is " .. tostring(t))
  end
end

local function process_fx_actions(track, fx, fx_actions, cc_value)
  for param, param_action in pairs(fx_actions) do
    if is_action_callback(param, param_action) then
      execute_action_callback(param_action, track, fx, param, cc_value)
    else
      error("Bad syntax for controler. The value should be a action callback")
    end
  end
end

local function process_track_actions(track, track_actions, cc_value)
  for fx_name, fx_actions in pairs(track_actions) do
    if is_action_callback(fx_name, fx_actions) then
      execute_action_callback(fx_actions, track, cc_value)
    elseif type(fx_actions) == "table" then
      process_fx_actions(track, get_fx_by_name(track, fx_name), fx_actions, cc_value)
    else
      error("Bad syntax for controller. The value should be a generator `function` or a `table` of actions")
    end
  end
end

local function process_mixing_control(controller, cc, cc_value)
  local actions = get_actions_by_value(controller, cc, cc_value)
  if actions == nil then return end

  -- Both Undo_* calls and Main_SaveProject can affect the selected tab.
  -- Modify the background mixer directly; use undo only if it is the active tab.
  local mixer_is_active = reaper.EnumProjects(-1) == THIS_PROJECT
  if mixer_is_active then
    reaper.Undo_BeginBlock2(THIS_PROJECT)
    reaper.PreventUIRefresh(1)
  end

  local ok, control_error = pcall(function()
    for track_name, track_actions in pairs(actions) do
      process_track_actions(get_track_by_name(track_name), track_actions, cc_value)
    end
  end)

  if mixer_is_active then
    reaper.PreventUIRefresh(-1)
    reaper.Undo_EndBlock2(THIS_PROJECT, SCRIPT_IDENTIFIER, -1)
  end

  if ok then queue_mixer_save() end
  if not ok then error(control_error) end
end

local function process_midi_messages(device_to_monitor, channel_to_monitor)
  local last_history_index = reaper.MIDI_GetRecentInputEvent(0)
  local function run_forever()
    local history_index = reaper.MIDI_GetRecentInputEvent(0)
    local new_message_count = history_index - last_history_index
    
    for i = new_message_count - 1, 0, -1 do
      local _, data, _, device = reaper.MIDI_GetRecentInputEvent(i)
      if device ~= device_to_monitor then goto continue end

      local status = string.byte(data, 1)
      local channel = (status & 0x0F) + 1
      if channel ~= channel_to_monitor then goto continue end

      local message_type = status & 0xF0
      if message_type == 0xB0 then -- Control Change message
      
        local cc_number = string.byte(data, 2)
        local cc_value = string.byte(data, 3)
        local ok, control_error = pcall(process_mixing_control, JIACHEN_CONTROLLER, cc_number, cc_value)
        if not ok then
          -- Preserve MIDI processing if an outdated track/FX mapping fails.
          reaper.SetExtState(SCRIPT_IDENTIFIER, "LastControlError", tostring(control_error), false)
        end
      end

      ::continue::
    end

    last_history_index = history_index

    local ok, transition_error = pcall(update_monitor_transition)
    if not ok then
      monitor_transition = nil
      reaper.SetExtState(SCRIPT_IDENTIFIER, "LastControlError", tostring(transition_error), false)
    end

    -- Save normally whenever the mixer tab is selected.
    local saved, save_error = pcall(save_mixer_if_active)
    if not saved then
      reaper.SetExtState(SCRIPT_IDENTIFIER, "LastControlError", tostring(save_error), false)
    end

    -- Otherwise, save only after ten minutes away from REAPER.
    local idle_saved, idle_save_error = pcall(save_mixer_if_idle)
    if not idle_saved then
      reaper.SetExtState(SCRIPT_IDENTIFIER, "LastControlError", tostring(idle_save_error), false)
    end

    reaper.defer(run_forever)
  end

  run_forever()
end

--#endregion

local function main()
  process_midi_messages(MIDI_DEVICE, CHANNEL_TO_MONITOR)
end

main()
