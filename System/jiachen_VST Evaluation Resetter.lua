-- @description VST Evaluation Resetter
-- @author Jiachen
-- @version 1.0.0

-- TimedTask class for encapsulated timed execution
TimedTask = {}
TimedTask.__index = TimedTask

-- Create a new timed logger
-- @param interval Interval in minutes between logs
-- @param callback Function to call when the interval elapses
-- @param name Optional name for this logger (used in debug)
function TimedTask.new(interval, callback, name)
  local self = setmetatable({}, TimedTask)
  self.interval = interval * 60 -- Convert minutes to seconds
  self.callback = callback
  self.name = name or "Task"
  self.last_time = 0
  return self
end

-- Check if it's time to run the callback
-- @return true if callback was executed, false otherwise
function TimedTask:check()
  local current_time = os.time()

  if current_time - self.last_time >= self.interval then
    self.callback()
    self.last_time = current_time
    return true
  end

  return false
end

-- Force the logger to run now and reset its timer
function TimedTask:runNow()
  self.callback()
  self.last_time = os.time()
end

-- Example usage
local tasks = {}

-- Store the initial project when script starts
local INITIAL_PROJECT = reaper.EnumProjects(-1)

-- Function to reset VST plugins marked with @ER: prefix
function resetEvaluationPlugins()
  -- Switch to our initial project temporarily
  local current_project = reaper.EnumProjects(-1)
  reaper.SelectProjectInstance(INITIAL_PROJECT)

  -- Check if the project is already saved
  local project_saved = reaper.IsProjectDirty(INITIAL_PROJECT) == 0

  -- Begin undo block to group all changes
  reaper.Undo_BeginBlock2(INITIAL_PROJECT)
  reaper.PreventUIRefresh(1)

  -- Get number of tracks in the project
  local track_count = reaper.CountTracks(INITIAL_PROJECT)

  -- Flag to track if we made any changes
  local changes_made = false

  -- Loop through all tracks
  for i = 0, track_count - 1 do
    local track = reaper.GetTrack(INITIAL_PROJECT, i)

    -- Get FX count for this track
    local fx_count = reaper.TrackFX_GetCount(track)

    -- Loop through all FX in this track
    for j = 0, fx_count - 1 do
      local retval, fx_name = reaper.TrackFX_GetFXName(track, j, "")

      -- Check if the FX name starts with @ER:
      if fx_name:match("^@ER:") then
        -- Toggle offline state to reset evaluation period
        reaper.TrackFX_SetOffline(track, j, true) -- Set offline
        reaper.TrackFX_SetOffline(track, j, false) -- Set back online
        changes_made = true
      end
    end
  end

  -- End undo block and refresh UI
  reaper.PreventUIRefresh(-1)
  reaper.Undo_EndBlock2(INITIAL_PROJECT, "jiachen_VST Evaluation Reset", -1)
  reaper.TrackList_AdjustWindows(false)

  -- If project was saved before our changes and we made changes, save only our changes
  if project_saved and changes_made then
    reaper.Main_SaveProject(INITIAL_PROJECT, false) -- Save the specific project
  end

  -- Switch back to the project the user was working on
  if current_project ~= INITIAL_PROJECT then
    reaper.SelectProjectInstance(current_project)
  end
end

-- Create a logger that resets evaluation plugins every 29 minutes
table.insert(tasks, TimedTask.new(29, resetEvaluationPlugins, "VSTResetter"))

-- Main function that checks all tasks
function main()
  -- Check all registered tasks
  for _, task in ipairs(tasks) do
    task:check()
  end

  -- Schedule the next check
  reaper.defer(main)
end

-- Run all tasks immediately on startup
for _, task in ipairs(tasks) do
  task:runNow()
end

-- Start the main loop
main()
