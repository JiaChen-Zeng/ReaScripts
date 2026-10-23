-- Validate the selected tracks before changing item selection or opening an undo block.
local num_sel_tracks = reaper.CountSelectedTracks(0)
if num_sel_tracks == 0 then
    reaper.ShowMessageBox("Please select a track first!", "Error", 0)
    return
end

reaper.Undo_BeginBlock()

-- Step 1: Unselect all items first to give us a clean slate
reaper.Main_OnCommand(40289, 0)

local found_count = 0

-- Step 2: Loop through only the selected track(s)
for t = 0, num_sel_tracks - 1 do
    local track = reaper.GetSelectedTrack(0, t)
    local num_items = reaper.CountTrackMediaItems(track)

    -- Step 3: Scan every item on this specific track
    for i = 0, num_items - 1 do
        local item = reaper.GetTrackMediaItem(track, i)
        local num_takes = reaper.CountTakes(item)

        -- Step 4: If it has exactly 3 takes, select it
        if num_takes == 3 then
            reaper.SetMediaItemSelected(item, true)
            found_count = found_count + 1
        end
    end
end

reaper.Undo_EndBlock("Select 3-take items on selected track", -1)
reaper.UpdateArrange()

reaper.ShowMessageBox("Found and selected " .. found_count .. " RX edited items (3 takes) on the selected track.", "Scan Complete", 0)
