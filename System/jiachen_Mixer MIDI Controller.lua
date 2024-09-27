-- @descrption MIDI Mixer Controller
-- @author Jiachen
-- @version 1.0.0

function get_midi_device_index_by_name(name)
    local n = reaper.GetNumMIDIInputs()
    for i = 0, n - 1 do
        local _, this_name = reaper.GetMIDIInputName(i, "")
        if this_name == name then
            return i
        end
    end
    
    error("Can't find the device: " .. name)
end

local DEVICE_TO_MONITOR = get_midi_device_index_by_name("REAPER Mixer") -- TODO: to set manually
local CHANNEL_TO_MONITOR = 16

local this_project = reaper.EnumProjects(-1)

function get_track_by_name(track_name)
  local track_count = reaper.CountTracks(0)
  for i = 0, track_count - 1 do
    local track = reaper.GetTrack(0, i)
    local _, current_track_name = reaper.GetSetMediaTrackInfo_String(track, "P_NAME", "", false)
    if current_track_name == track_name then
      return track
    end
  end
  
  error("Track name specified in controller is wrong: " .. track_name)
end

function get_fx_by_name(track, fx_name)
  local fx_count = reaper.TrackFX_GetCount(track)
  for i = 0, fx_count - 1 do
    local _, current_fx_name = reaper.TrackFX_GetFXName(track, i, "")
    if current_fx_name == fx_name then
      return i
    end
  end
  
  error("FX name specified in controller is wrong: " .. fx_name)
end

-- Controller Action Functions Begin

function to_mute(mute)
  return function(track)
    local mute_number
    if mute then mute_number = 1 else mute_number = 0 end
    reaper.SetMediaTrackInfo_Value(track, "B_MUTE", mute_number)
  end
end

function to_preset(preset_name_or_callback)
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

function to_bypass(bypass)
  return function(track, fx_or_cc_value, cc_value)
    if cc_value == nil then -- 2 params. for all fxs in track
      reaper.SetMediaTrackInfo_Value(track, "I_FXEN", bypass and 0 or 1)
    else -- 3 params, for one fx
      reaper.TrackFX_SetEnabled(track, fx_or_cc_value, not bypass)
    end
  end
end

function to_map(min, max)
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

function to_send(receive_track_name, send)
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

-- Controller Action Functions End

local jiachen_controller = {
--  <example>
--  [0] = {
--    VSX = {
--      _action = to_mute(true),
--      ["VST3: VSX (Steven Slate)"] = to_preset(function (value)
--        return ({[0] = "NRG Mid", [1] = "HD Linear 2", [2] = "SUV"})[value]
--      end),
--      MUtility = {
--        _action = to_bypass(true),
--        Volume = to_map()
--      }
--    }
--  },
  [0] = { VSX = {_action = to_mute(true)} },
  [1] = { VSX = {_action = to_mute(false)} },
  [2] = function (value)
    return {VSX = {_action = to_mute(value ~= 127)}}
  end,
  [3] = { VSX = {_action = to_mute(true)} },
  [4] = { VSX = {_action = to_mute(true)} },
  [5] = { VSX = {_action = to_mute(true)} },
  
  [10] = { VSX = { ["VST3: VSX (Steven Slate)"] = {_action = to_preset("Howie Weinberg")} } },
  [11] = { VSX = { ["VST3: VSX (Steven Slate)"] = {_action = to_preset("HD Linear 2")} } },
  [12] = { VSX = { ["VST3: VSX (Steven Slate)"] = {_action = to_preset("Steven Mono")} } },
  [13] = { VSX = { ["VST3: VSX (Steven Slate)"] = {_action = to_preset("Zuma Far")} } },
  [14] = { VSX = { ["VST3: VSX (Steven Slate)"] = {_action = to_preset("SUV")} } },
  [15] = { VSX = { ["VST3: VSX (Steven Slate)"] = {_action = to_preset("Club")} } },
  
  [20] = function (value)
    return {["BG Ducked"] = {_action = to_bypass(value ~= 127)}}
  end,
  [21] = function (value)
    return {["Synth Clean"] = {_action = to_send("Base", value == 127)}}
  end,
  
  [30] = { Base = {
    ["VST3: kHs Channel Mixer (Kilohearts)"] = {_action = to_bypass(true)},
    ["VST: sparta_binauraliser (AALTO) (64ch)"] = {_action = to_bypass(true)}
  }, ["Raw | Simplified 7.1"] = {
    ["VST3: MChannelMatrix (MeldaProduction)"] = {_action = to_bypass(true)}
  } },
  [31] = { Base = {
    ["VST3: kHs Channel Mixer (Kilohearts)"] = {_action = {to_preset("Cross"), to_bypass(false)}},
    ["VST: sparta_binauraliser (AALTO) (64ch)"] = {_action = to_bypass(true)}
  }, ["Raw | Simplified 7.1"] = {
    ["VST3: MChannelMatrix (MeldaProduction)"] = {_action = to_bypass(true)}
  } },
  [32] = { Base = {
    ["VST3: kHs Channel Mixer (Kilohearts)"] = {_action = {to_preset("Mono"), to_bypass(false)}},
    ["VST: sparta_binauraliser (AALTO) (64ch)"] = {_action = to_bypass(true)}
  }, ["Raw | Simplified 7.1"] = {
    ["VST3: MChannelMatrix (MeldaProduction)"] = {_action = to_bypass(true)}
  } },
  [33] = { Base = {
    ["VST3: kHs Channel Mixer (Kilohearts)"] = {_action = to_bypass(true)},
    ["VST: sparta_binauraliser (AALTO) (64ch)"] = {_action = to_bypass(false)}
  }, ["Raw | Simplified 7.1"] = {
    ["VST3: MChannelMatrix (MeldaProduction)"] = {_action = to_bypass(false)}
  } }
}

function get_actions_by_value(controller, cc, cc_value)
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

function is_action_callback(key, value)
  local t = type(value)
  return key == "_action" and (t == "function" or t == "table")
end

function execute_action_callback(callback, ...)
  local t = type(callback)
  if t == "function" then
    callback(...)
  elseif t == "table" then
    for _, fn in ipairs(callback) do fn(...) end
  else
    error("Action callback should be a `function` or a `table` of `function`s. Now is " .. tostring(t))
  end
end

function process_fx_actions(track, fx, fx_actions, cc_value)
  for param, param_action in pairs(fx_actions) do
    if is_action_callback(param, param_action) then
      execute_action_callback(param_action, track, fx, param, cc_value)
    else
      error("Bad syntax for controler. The value should be a action callback")
    end
  end
end

function process_track_actions(track, track_actions, cc_value)
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

function process_mixing_control(controller, cc, cc_value)
  local actions = get_actions_by_value(controller, cc, cc_value)
  if actions == nil then return end
  
  -- Deal with the case where mixer project is in the background
  local current_project = reaper.EnumProjects(-1)
  reaper.SelectProjectInstance(this_project)
  
  local saved_before = reaper.IsProjectDirty()
  reaper.Undo_BeginBlock2(this_project)
  reaper.PreventUIRefresh(1)

  for track_name, track_actions in pairs(actions) do
    process_track_actions(get_track_by_name(track_name), track_actions, cc_value)
  end

  reaper.PreventUIRefresh(-1)
  reaper.Undo_EndBlock2(this_project, "jiachen_MIDI Mixer Controller", -1)
  reaper.TrackList_AdjustWindows(false)
  
  if saved_before then
    reaper.Main_SaveProject(this_project, false)
  end
  
  reaper.SelectProjectInstance(current_project)
end

-- MIDI Processing Start

function process_midi_messages(device_to_monitor, channel_to_monitor)
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
        process_mixing_control(jiachen_controller, cc_number, cc_value)
      end

      ::continue::
    end

    last_history_index = history_index
    
    reaper.defer(run_forever)
  end

  run_forever()
end

function main()
  process_midi_messages(DEVICE_TO_MONITOR, CHANNEL_TO_MONITOR)
end

main()
