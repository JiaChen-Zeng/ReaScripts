-- @description Global Setup Action
-- @author Jiachen
-- @version 1.0.0

function main()
  -- Switch to the first tab (project)
  reaper.Main_OnCommand(3122, 0)

  -- Run the specified custom actions
  -- Run "Script: jiachen_Mixer MIDI Controller.lua"
  local mixer_cmd_id = reaper.NamedCommandLookup("_RS2c4229a976a70340c00f2fcc878445c5a60ee11e")
  reaper.Main_OnCommand(mixer_cmd_id, 0)

  -- Run "Script: jiachen_VST Evaluation Resetter.lua"
  local resetter_cmd_id = reaper.NamedCommandLookup("_RSdaf98a2af5fff4266a0a459ce9b624e678581a3b")
  reaper.Main_OnCommand(resetter_cmd_id, 0)
end

main()

