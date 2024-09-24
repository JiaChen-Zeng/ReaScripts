-- @description Make region Loopable
-- @author Jiachen
-- @version 1.0.0
-- @about
--    Split the items that span the start and the end of the region, and move the part outsides to the inside at the other end of the region.

-- Get the start and end of the time selection
local start_time, end_time = reaper.GetSet_LoopTimeRange(false, false, 0, 0, false)

-- Begin undo block
reaper.Undo_BeginBlock()

-- Function to remove fades from an item
local function removeFades(item)
    reaper.SetMediaItemInfo_Value(item, "D_FADEINLEN", 0)
    reaper.SetMediaItemInfo_Value(item, "D_FADEOUTLEN", 0)
end

-- Function to process items in a track
local function processTrackItems(track)
    local num_items = reaper.CountTrackMediaItems(track)
    
    for j = num_items - 1, 0, -1 do
        local item = reaper.GetTrackMediaItem(track, j)
        local item_start = reaper.GetMediaItemInfo_Value(item, "D_POSITION")
        local item_end = item_start + reaper.GetMediaItemInfo_Value(item, "D_LENGTH")
        
        -- Split items that span the start of the range
        if item_start < start_time and item_end > start_time then
            local left_item = item
            local right_item = reaper.SplitMediaItem(item, start_time)
            if left_item then
                removeFades(left_item)
                removeFades(right_item)
                reaper.SetMediaItemInfo_Value(left_item, "D_POSITION", end_time - reaper.GetMediaItemInfo_Value(left_item, "D_LENGTH"))
            end
        end
        
        -- Split items that span the end of the range
        if item_start < end_time and item_end > end_time then
            local left_item = item
            local right_item = reaper.SplitMediaItem(item, end_time)
            if right_item then
                removeFades(left_item)
                removeFades(right_item)
                reaper.SetMediaItemInfo_Value(right_item, "D_POSITION", start_time)
            end
        end
    end
end

-- Function to process selected tracks and their descendants
local function processSelectedTracks()
    local processed_tracks = {}
    local function processTrack(track)
        if not processed_tracks[track] then
            processed_tracks[track] = true
            processTrackItems(track)
            
            -- Process children tracks
            local depth = reaper.GetTrackDepth(track)
            local track_index = reaper.GetMediaTrackInfo_Value(track, "IP_TRACKNUMBER") - 1
            local num_tracks = reaper.CountTracks(0)
            for i = track_index + 1, num_tracks - 1 do
                local child_track = reaper.GetTrack(0, i)
                if reaper.GetTrackDepth(child_track) <= depth then
                    break
                end
                processTrack(child_track)
            end
        end
    end
    
    local num_selected_tracks = reaper.CountSelectedTracks(0)
    if num_selected_tracks > 0 then
        for i = 0, num_selected_tracks - 1 do
            local track = reaper.GetSelectedTrack(0, i)
            processTrack(track)
        end
    else
        local num_tracks = reaper.CountTracks(0)
        for i = 0, num_tracks - 1 do
            local track = reaper.GetTrack(0, i)
            processTrack(track)
        end
    end
end

-- Process selected tracks and their descendants
processSelectedTracks()

-- End undo block
reaper.Undo_EndBlock("Make selected range loopable", -1)

-- Update the arrange view
reaper.UpdateArrange()
