-- Play Razor Edit area
-- v0.04

if (reaper.GetPlayState()&1)==1 then -- detects play/record
  reaper.Main_OnCommand(1016, 0) -- Transport: Stop
  return
end

-- Thanks to juliansader, https://forum.cockos.com/showpost.php?p=2348778&postcount=163
left, right = math.huge, -math.huge
for t = 0, reaper.CountTracks(0)-1 do
  local track = reaper.GetTrack(0, t)
  local razorOK, razorStr = reaper.GetSetMediaTrackInfo_String(track, "P_RAZOREDITS", "", false)
  if razorOK and #razorStr ~= 0 then
    for razorLeft, razorRight, envGuid in razorStr:gmatch([[([%d%.]+) ([%d%.]+) "([^"]*)"]]) do
      local razorLeft, razorRight = tonumber(razorLeft), tonumber(razorRight)
      if razorLeft  < left  then left  = razorLeft end
      if razorRight > right then right = razorRight end
    end
  end
end

if left <= right then
  reaper.PreventUIRefresh(1)
  reaper.GetSet_LoopTimeRange2(0, true, false, left, right, false)
  reaper.SetEditCurPos(left, true, false)
  reaper.Main_OnCommand(1007, 0) -- Transport: Play
  reaper.PreventUIRefresh(-1)
else
  reaper.Main_OnCommand(1007, 0) -- Transport: Play 
end  
