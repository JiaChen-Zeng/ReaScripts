-- @description Ear Training Question Generator
-- @author Jiachen
-- @version 1.2.0
-- @about
--   # Ear Training Question Generator
--   This script provides functionality for generating ear training exercises in Reaper.
--   It can generate various types of ear training exercises, including:
--   - Scale degree recognition
--   - Chord progression recognition
--   - Interval recognition
--
--   The script supports exporting exercise data to CSV files for reference.

-- Global constants
local DEFAULT_VELOCITY = 96 -- MIDI velocity (0-127)
local MIDI_C4 = 60 -- MIDI note number for middle C

-- Get project BPM
local function getProjectBPM()
    local tempo = reaper.Master_GetTempo()
    return tempo
end

-- Default note length is 1 bar
local function getDefaultNoteLength()
    -- Calculate length of 1 bar based on project's time signature and tempo
    return reaper.TimeMap2_beatsToTime(0, 0, 1) -- Length of 1 bar in seconds
end

---------------------------------------------------------------
-- ScaleNote Class
---------------------------------------------------------------
-- Represents a note in terms of scale degree, octave offset, and alteration
-- degree: Scale degree (1+)
-- octaveOffset: Octave shift relative to base octave (can be negative)
-- alteration: Semitone alterations (#/b) (e.g., -1 for flat, 0 for natural, 1 for sharp)
local ScaleNote = {}
ScaleNote.__index = ScaleNote

function ScaleNote.new(degree, octaveOffset, alteration)
    local self = setmetatable({}, ScaleNote)
    
    -- Initialize fields
    self.octaveOffset = octaveOffset or 0
    self.alteration = alteration or 0
    self:setDegree(degree or 1)

    return self
end

-- Getter for degree
function ScaleNote:getDegree()
    return self._degree
end

-- Setter for degree with normalization
function ScaleNote:setDegree(degree)
    -- Validate degree (must be >= 1)
    if not (1 <= degree) then
        local errMsg = "Scale degree must be at least 1, but it's " .. degree
        local trace = debug.traceback(errMsg, 2)  -- Start from caller
        error(trace)
    end

    -- Normalize degree to 1-7 range and adjust octaveOffset
    local additionalOctaves = math.floor((degree - 1) / 7)
    self._degree = ((degree - 1) % 7) + 1
    
    -- Adjust octave offset if needed
    if additionalOctaves > 0 then
        self.octaveOffset = self.octaveOffset + additionalOctaves
    end
end

-- Property access (for backward compatibility)
function ScaleNote:__index(key)
    if key == "degree" then
        return self:getDegree()
    else
        return ScaleNote[key]
    end
end

function ScaleNote:__newindex(key, value)
    if key == "degree" then
        self:setDegree(value)
    else
        rawset(self, key, value)
    end
end

function ScaleNote:toString()
    local alterationStr = ""
    if self.alteration > 0 then
        alterationStr = string.rep("#", self.alteration)
    elseif self.alteration < 0 then
        alterationStr = string.rep("b", -self.alteration)
    end
    
    local octaveStr = ""
    if self.octaveOffset > 0 then
        octaveStr = "+" .. self.octaveOffset
    elseif self.octaveOffset < 0 then
        octaveStr = tostring(self.octaveOffset)
    end
    
    return self.degree .. alterationStr .. octaveStr
end

-- Check if two ScaleNote objects are equal
function ScaleNote:equals(other)
    if getmetatable(other) ~= ScaleNote then
        return false
    end
    
    return self.degree == other.degree 
        and self.octaveOffset == other.octaveOffset 
        and self.alteration == other.alteration
end

-- Move the scale note by a given step size, properly handling octave shifts
-- stepSize: Number of scale steps to move (can be negative)
function ScaleNote:move(stepSize)
    if stepSize == 0 then
        return self -- No change needed
    end
    
    -- Get the current absolute position
    local currentAbsPosition = (self.octaveOffset * 7) + self.degree
    
    -- Calculate the new absolute position
    local newAbsPosition = currentAbsPosition + stepSize
    
    -- Calculate new octaveOffset and degree
    local newOctaveOffset = math.floor((newAbsPosition - 1) / 7)
    local newDegree = ((newAbsPosition - 1) % 7) + 1
    
    -- Update values
    self.octaveOffset = newOctaveOffset
    self.degree = newDegree
    
    return self
end

---------------------------------------------------------------
-- Chord Class
---------------------------------------------------------------
-- Represents a chord in terms of scale degrees
local Chord = {}
Chord.__index = Chord

function Chord.new(...)
    local self = setmetatable({}, Chord)
    self.notes = {}
    
    -- Process arguments
    for i, note in ipairs({...}) do
        if type(note) == "number" then
            -- Convert number to ScaleNote
            table.insert(self.notes, ScaleNote.new(note))
        else
            -- Assume it's already a ScaleNote
            table.insert(self.notes, note)
        end
    end
    
    return self
end

-- Create a diatonic triad from a scale degree and octave offset
-- degree: Scale degree (1-7)
-- octaveOffset: Global octave offset for the chord (default 0)
function Chord.newDiatonicTriad(degree, octaveOffset, inversion)
    octaveOffset = octaveOffset or 0
    inversion = inversion or 0
    
    -- Create initial notes (root position with specified octave offset)
    local root = ScaleNote.new(degree, octaveOffset)
    local third = ScaleNote.new(degree + 2, octaveOffset)
    local fifth = ScaleNote.new(degree + 4, octaveOffset)
    
    local chord = Chord.new(root, third, fifth)
    
    -- Apply inversion
    if inversion == 1 then
        -- First inversion: root moves up an octave
        chord.notes[1].octaveOffset = chord.notes[1].octaveOffset + 1
    elseif inversion == 2 then
        -- Second inversion: root and third move up an octave
        chord.notes[1].octaveOffset = chord.notes[1].octaveOffset + 1
        chord.notes[2].octaveOffset = chord.notes[2].octaveOffset + 1
    end
    
    return chord
end

-- Create a dyad (two-note chord) from a scale degree and chromatic interval
-- degree: Scale degree (1-7)
-- interval: Chromatic interval (0 for unison, 12 for octave, etc), must be non-negative
-- direction: 0 for random, 1 for ascending, -1 for descending
-- octaveOffset: Global octave offset for the chord (default 0)
function Chord.newDyad(degree, interval, direction, octaveOffset)
    -- Validate inputs
    assert(interval >= 0, "Interval must be non-negative")
    assert(direction == 0 or direction == 1 or direction == -1, "Direction must be 0, 1, or -1")
    
    octaveOffset = octaveOffset or 0
    
    -- If direction is random (0), randomly choose between ascending and descending
    if direction == 0 then
        direction = math.random(1, 2) == 1 and 1 or -1
    end
    
    -- Convert chromatic interval to octave change and remaining interval
    local octaveOffsetChange = math.floor(interval / 12)
    local remainingInterval = interval % 12
    
    local first, second
    
    if direction == 1 then
        -- Ascending: first note is lower, second note is higher
        first = ScaleNote.new(degree, octaveOffset)
        second = ScaleNote.new(degree, octaveOffset + octaveOffsetChange)
        second.alteration = remainingInterval
    else
        -- Descending: first note is higher, second note is lower
        first = ScaleNote.new(degree, octaveOffset + octaveOffsetChange)
        first.alteration = remainingInterval
        second = ScaleNote.new(degree, octaveOffset)
    end
    
    return Chord.new(first, second)
end

-- Move all notes in the chord by a given step size
function Chord:moveAllNotes(stepSize)
    -- Move all notes
    for _, note in ipairs(self.notes) do
        note:move(stepSize)
    end
    
    return self
end

-- Check if all notes in the chord are within a given MIDI range
function Chord:isWithinMidiRange(keyContext, midiRange)
    for _, note in ipairs(self.notes) do
        local midiNote = keyContext:scaleNoteToMidi(note)
        if midiNote < midiRange.lo or midiNote > midiRange.hi then
            return false -- One note is outside of MIDI range
        end
    end
    return true
end

-- Map all notes in the chord relative to a target position
-- This transforms the chord as if the origin point is moved to targetPosition
function Chord:map(targetPosition)
    -- Apply the mapping to all notes
    for _, note in ipairs(self.notes) do
        -- Calculate relative position from base (1,0)
        local relDegree = note.degree - 1
        local relOctave = note.octaveOffset
        
        -- Apply new base position
        note.octaveOffset = relOctave + targetPosition.octaveOffset
        note:setDegree(relDegree + targetPosition.degree)
        -- Note: alteration remains unchanged
    end
    
    return self
end

function Chord:getNotes()
    return self.notes
end

-- Check if two Chord objects are equal by comparing all their notes
function Chord:equals(other)
    if getmetatable(other) ~= Chord then
        return false
    end
    
    -- First check if the number of notes is the same
    if #self.notes ~= #other.notes then
        return false
    end
    
    -- Then check each note
    for i, note in ipairs(self.notes) do
        if not note:equals(other.notes[i]) then
            return false
        end
    end
    
    return true
end

---------------------------------------------------------------
-- Key Context Classes
---------------------------------------------------------------
-- Base KeyContext class
local KeyContext = {}
KeyContext.__index = KeyContext

function KeyContext.new(rootNote, baseOctave, scalePattern)
    local self = setmetatable({}, KeyContext)
    self.rootNote = rootNote or 0  -- 0 for C, 1 for C#, etc.
    self.baseOctave = baseOctave or 4  -- MIDI octave number (middle C is in octave 4)
    self.scalePattern = scalePattern or {0, 2, 4, 5, 7, 9, 11}  -- Default to major scale
    return self
end

-- Convert ScaleNote to MIDI note number
function KeyContext:scaleNoteToMidi(scaleNote)
    -- Get the scale step within the octave (0-6)
    local scaleStep = scaleNote.degree - 1
    
    -- Calculate the base MIDI note (without alterations)
    local semitoneOffset = self.scalePattern[scaleStep + 1]
    local octave = self.baseOctave + scaleNote.octaveOffset
    local midiNote = self.rootNote + semitoneOffset + (octave * 12) + scaleNote.alteration
    
    return midiNote
end

-- Get the name of the current key
function KeyContext:getKeyName()
    local noteNames = {"C", "C#", "D", "D#", "E", "F", "F#", "G", "G#", "A", "A#", "B"}
    return noteNames[self.rootNote + 1] .. " " .. self:getScaleTypeName()
end

function KeyContext:getScaleTypeName()
    return "Scale"
end

-- MajorKeyContext Class
local MajorKeyContext = setmetatable({}, {__index = KeyContext})
MajorKeyContext.__index = MajorKeyContext

function MajorKeyContext.new(rootNote, baseOctave)
    local self = KeyContext.new(rootNote, baseOctave, {0, 2, 4, 5, 7, 9, 11})
    return setmetatable(self, MajorKeyContext)
end

function MajorKeyContext:getScaleTypeName()
    return "Major"
end

-- Harmonic Minor Key Context
local HarmonicMinorKeyContext = setmetatable({}, {__index = KeyContext})
HarmonicMinorKeyContext.__index = HarmonicMinorKeyContext

function HarmonicMinorKeyContext.new(rootNote, baseOctave)
    -- Harmonic minor scale pattern: 0,2,3,5,7,8,11
    local self = KeyContext.new(rootNote, baseOctave, {0, 2, 3, 5, 7, 8, 11})
    return setmetatable(self, HarmonicMinorKeyContext)
end

function HarmonicMinorKeyContext:getScaleTypeName()
    return "Harmonic Minor"
end

---------------------------------------------------------------
-- UnivocalKeyValidator Class
---------------------------------------------------------------
-- Validate if the notes played is univocal by
-- tracking if all scale degrees have appeared in a progression.
-- Note this is not perfect since it can be univocal despite all degrees aren't appeared,
-- but this approach can 100% eliminate key ambiguity and is simple enough. 
local UnivocalKeyValidator = {}
UnivocalKeyValidator.__index = UnivocalKeyValidator

function UnivocalKeyValidator.new()
    local self = setmetatable({}, UnivocalKeyValidator)
    self.degreesUsed = {
        [1] = false,
        [2] = false,
        [3] = false,
        [4] = false,
        [5] = false,
        [6] = false,
        [7] = false
    }
    return self
end

-- Add a scale degree or chord to the validator
function UnivocalKeyValidator:add(item)
    if type(item) == "number" then
        -- If a number is provided, mark that scale degree as used
        local degree = ((item - 1) % 7) + 1 -- Normalize to 1-7 range
        self.degreesUsed[degree] = true
    elseif getmetatable(item) == Chord then
        -- If a chord is provided, add all its notes
        for _, note in ipairs(item:getNotes()) do
            local degree = ((note.degree - 1) % 7) + 1 -- Normalize to 1-7 range
            self.degreesUsed[degree] = true
        end
    end
end

-- Check if all scale degrees have been used
function UnivocalKeyValidator:validate()
    for degree, used in pairs(self.degreesUsed) do
        if not used then
            return false
        end
    end
    return true
end

---------------------------------------------------------------
-- Helper Functions
---------------------------------------------------------------

-- Generate a random number that differs from previousNumber
local function randomDifferentInteger(min, max, previousInteger)
    if previousInteger == nil then
        return math.random(min, max)
    end

    assert(min <= previousInteger and previousInteger <= max,
        "previousInteger" .. previousInteger .. " must be in [" .. min .. ", " .. max .. "]")

    local result
    repeat
        result = math.random(min, max)
    until result ~= previousInteger

    return result
end

---------------------------------------------------------------
-- Reaper API Wrappers and Utility Functions
---------------------------------------------------------------

-- Global variable to track the current MIDI item for adding notes
local currentMidiItem = nil
local currentMidiTake = nil

-- Initialize or get the current MIDI item
local function getCurrentMidiItem(track)
    local cursorPos = reaper.GetCursorPosition()
    
    if currentMidiItem == nil then
        -- Create a new MIDI item with initial minimal length
        currentMidiItem = reaper.CreateNewMIDIItemInProj(track, cursorPos, cursorPos + getDefaultNoteLength())
        currentMidiTake = reaper.GetActiveTake(currentMidiItem)
    else
        -- Check if we need to extend the MIDI item
        local itemStart = reaper.GetMediaItemInfo_Value(currentMidiItem, "D_POSITION")
        local itemEnd = itemStart + reaper.GetMediaItemInfo_Value(currentMidiItem, "D_LENGTH")
        
        -- If cursor position is outside the current item, extend the item
        if cursorPos > itemEnd then
            reaper.SetMediaItemLength(currentMidiItem, cursorPos - itemStart + getDefaultNoteLength(), true)
        end
    end
    
    return currentMidiItem, currentMidiTake
end

-- Play silent (just advance the cursor position)
local function playSilent(bars)
    bars = bars or 1
    local duration = getDefaultNoteLength() * bars
    local cursorPos = reaper.GetCursorPosition()
    reaper.SetEditCurPos(cursorPos + duration, true, false)
    return cursorPos + duration
end

-- Play an audio file and optionally advance cursor
local function playMedia(track, filename, bars, advance)
    if advance == nil then advance = true end
    bars = bars or 1
    local requestedDuration = getDefaultNoteLength() * bars
    
    local cursorPos = reaper.GetCursorPosition()
    
    -- Get project path and construct full file path
    local projectPath = reaper.GetProjectPath("")
    local filePath = projectPath .. "/" .. filename
    
    -- Check if file exists
    if not reaper.file_exists(filePath) then
        error("Audio file not found: " .. filePath)
    end
    
    -- Insert media file into the project
    local mediaItem = reaper.AddMediaItemToTrack(track)
    reaper.SetMediaItemPosition(mediaItem, cursorPos, false)
    
    -- Get the take
    local take = reaper.AddTakeToMediaItem(mediaItem)
    
    -- Set the source
    local pcm_source = reaper.PCM_Source_CreateFromFile(filePath)
    reaper.SetMediaItemTake_Source(take, pcm_source)
    
    -- Get source media length
    local sourceLength = reaper.GetMediaSourceLength(pcm_source)
    
    -- Verify the audio file is short enough
    if requestedDuration < sourceLength then
        error("Audio file is too long: " .. filename .. " (length: " .. string.format("%.2f", sourceLength) .. 
              "s, limit: " .. string.format("%.2f", requestedDuration) .. "s)")
    end
    
    -- Keep original source length for the media item (don't stretch/shrink)
    reaper.SetMediaItemLength(mediaItem, sourceLength, false)
    
    -- Set take name to filename (without extension)
    local fileBaseName = filename:match("(.+)%..+$") or filename
    reaper.GetSetMediaItemTakeInfo_String(take, "P_NAME", fileBaseName, true)
    
    -- Advance the cursor if requested (using the requested duration, not the source length)
    if advance then
        reaper.SetEditCurPos(cursorPos + requestedDuration, true, false)
    end
    
    return cursorPos + (advance and requestedDuration or 0)
end

-- Play a note and optionally advance cursor
local function playNote(track, midiNote, bars, velocity, advance)
    if advance == nil then advance = true end
    velocity = velocity or DEFAULT_VELOCITY
    bars = bars or 1
    local duration = getDefaultNoteLength() * bars
    
    local cursorPos = reaper.GetCursorPosition()
    
    -- Get or create MIDI item and take
    local item, take = getCurrentMidiItem(track)
    
    -- Get PPQ positions
    local startPPQPos = reaper.MIDI_GetPPQPosFromProjTime(take, cursorPos)
    local endPPQPos = reaper.MIDI_GetPPQPosFromProjTime(take, cursorPos + duration)
    
    -- Insert the note
    reaper.MIDI_InsertNote(take, false, false, startPPQPos, endPPQPos, 0, midiNote, velocity, false)
    
    -- Ensure MIDI item extends to cover this note
    local itemStart = reaper.GetMediaItemInfo_Value(item, "D_POSITION")
    local noteEndTime = cursorPos + duration
    local itemEnd = itemStart + reaper.GetMediaItemInfo_Value(item, "D_LENGTH")
    
    -- If the note extends beyond the current MIDI item end, extend the item
    if noteEndTime > itemEnd then
        reaper.SetMediaItemLength(item, noteEndTime - itemStart, true)
    end
    
    -- Advance the cursor if requested
    if advance then
        reaper.SetEditCurPos(cursorPos + duration, true, false)
    end
    
    return cursorPos + (advance and duration or 0)
end

-- Play a scale degree note in the current key context
local function playScaleDegree(track, keyContext, scaleNoteOrDegree, bars, velocity, advance)
    local scaleNote
    
    if type(scaleNoteOrDegree) == "number" then
        -- If a number is provided, convert it to a ScaleNote
        scaleNote = ScaleNote.new(scaleNoteOrDegree)
    else
        -- Otherwise assume it's already a ScaleNote
        scaleNote = scaleNoteOrDegree
    end
    
    local midiNote = keyContext:scaleNoteToMidi(scaleNote)
    return playNote(track, midiNote, bars, velocity, advance)
end

-- Play a full scale
local function playScale(track, keyContext, bars, direction, velocity, advance)
    if advance == nil then advance = true end
    bars = bars or 1/4
    direction = direction or 1  -- 1 for ascending, -1 for descending
    
    local startDegree = 1
    local endDegree = 8
    local step = direction
    
    if direction < 0 then
        startDegree = 8
        endDegree = 1
    end
    
    local cursorPos = reaper.GetCursorPosition()
    
    for degree = startDegree, endDegree, step do
        -- Don't advance on the last note if advance is false
        local isLastNote = (direction > 0 and degree == endDegree) or (direction < 0 and degree == endDegree)
        local shouldAdvance = advance or not isLastNote
        
        playScaleDegree(track, keyContext, degree, bars, velocity, shouldAdvance)
    end
    
    return reaper.GetCursorPosition()
end

-- Play a chord (block or arpeggiated)
local function playChord(track, keyContext, chordOrNotes, arpeggiation, bars, velocity, advance)
    if advance == nil then advance = true end
    velocity = velocity or DEFAULT_VELOCITY
    bars = bars or 1
    local duration = getDefaultNoteLength() * bars
    
    local cursorPos = reaper.GetCursorPosition()
    
    -- Get or create MIDI item and take
    local item, take = getCurrentMidiItem(track)
    
    -- Process chord or notes
    local notesToPlay = {}
    
    if getmetatable(chordOrNotes) == Chord then
        -- If it's a Chord object, get its notes
        notesToPlay = chordOrNotes:getNotes()
    elseif type(chordOrNotes) == "table" then
        -- If it's a table, convert it to a Chord object and get its notes
        notesToPlay = Chord.new(table.unpack(chordOrNotes)):getNotes()
    else
        error("Chord parameter must be a Chord object or a table of ScaleNotes/numbers")
    end
    
    -- Handle arpeggiation if specified
    if arpeggiation then
        local noteCount = #notesToPlay
        local noteDuration = duration / noteCount
        local noteStartPos = cursorPos
        
        -- Iterate through each character in the arpeggiation string
        for i = 1, #arpeggiation do
            local idx = tonumber(arpeggiation:sub(i, i))
            if idx and idx >= 1 and idx <= noteCount then
                local noteStartPPQPos = reaper.MIDI_GetPPQPosFromProjTime(take, noteStartPos)
                local noteEndPPQPos = reaper.MIDI_GetPPQPosFromProjTime(take, noteStartPos + noteDuration)
                
                local scaleNote = notesToPlay[idx]
                local midiNote = keyContext:scaleNoteToMidi(scaleNote)
                reaper.MIDI_InsertNote(take, false, false, noteStartPPQPos, noteEndPPQPos, 0, midiNote, velocity, false)
                
                noteStartPos = noteStartPos + noteDuration
            end
        end
    else
        -- Play as a block chord (all notes simultaneously)
        local startPPQPos = reaper.MIDI_GetPPQPosFromProjTime(take, cursorPos)
        local endPPQPos = reaper.MIDI_GetPPQPosFromProjTime(take, cursorPos + duration)
        
        -- Insert all notes in the chord
        for _, scaleNote in ipairs(notesToPlay) do
            local midiNote = keyContext:scaleNoteToMidi(scaleNote)
            reaper.MIDI_InsertNote(take, false, false, startPPQPos, endPPQPos, 0, midiNote, velocity, false)
        end
    end
    
    -- Ensure MIDI item extends to cover this chord
    local itemStart = reaper.GetMediaItemInfo_Value(item, "D_POSITION")
    local noteEndTime = cursorPos + duration
    local itemEnd = itemStart + reaper.GetMediaItemInfo_Value(item, "D_LENGTH")
    
    -- If the chord extends beyond the current MIDI item end, extend the item
    if noteEndTime > itemEnd then
        reaper.SetMediaItemLength(item, noteEndTime - itemStart, true)
    end
    
    -- Advance the cursor if requested
    if advance then
        reaper.SetEditCurPos(cursorPos + duration, true, false)
    end
    
    return cursorPos + (advance and duration or 0)
end

---------------------------------------------------------------
-- Generator Class
---------------------------------------------------------------
local Generator = {}
Generator.__index = Generator

-- Constructor for Generator
-- keyContext: KeyContext object
-- factoryCallback: Function that takes (ScaleNote, midiRange, options) and creates an item
-- midiRange: Table with lo and hi MIDI note values
-- movePdf: Table with medium and standardDeviation for normal distribution
-- options: Table with boolean settings like noRepeat, allowNonDiatonic, maxAnswerRepeat (integer or nil)
function Generator.new(keyContext, factoryCallback, midiRange, movePdf, options)
    local self = setmetatable({}, Generator)
    
    -- Initialize required parameters
    self.keyContext = keyContext
    self.factoryCallback = factoryCallback
    self.midiRange = midiRange or {lo = 36, hi = 84} -- Default MIDI range C2-C6
    self.movePdf = movePdf or {mean = 2, stdDev = 3} -- Default distribution for absolute distance
    self.options = options or {noRepeat = true, allowNonDiatonic = false, maxAnswerRepeat = math.huge}
    
    -- Initialize state
    self.currentPosition = ScaleNote.new(1, 0) -- Start at key center (degree 1, octave 0)
    self.previousItem = nil
    self.previousAnswers = {} -- Track previous answers for maxAnswerRepeat option
    
    return self
end

-- Helper function for normal distribution random
local function normalRandom(mean, stddev)
    -- Box-Muller transform for normal distribution
    local u1 = math.random()
    local u2 = math.random()
    local z0 = math.sqrt(-2 * math.log(u1)) * math.cos(2 * math.pi * u2)
    return mean + stddev * z0
end

-- Generate next item
function Generator:next()
    local attempts = 0
    local maxAttempts = 100 -- Avoid infinite loops
    local item = nil
    local answer = nil
    
    while attempts < maxAttempts do
        attempts = attempts + 1
        
        -- Try to generate an item and get answer
        item, answer = self:tryGenerateItem()
        
        -- Check if generation succeeded and item passes all checks
        if item and self:validateItem(item, answer) then
            -- Update state
            self:updateState(item)
            
            -- Track the answer for maxAnswerRepeat option
            if answer then
                table.insert(self.previousAnswers, answer)
            end
            
            -- Return both the item and its answer
            return item, answer
        end
    end
    
    -- Fallback if we couldn't generate a valid item
    return nil, nil
end

-- Try to generate an item based on current position
function Generator:tryGenerateItem()
    -- Generate movement with direction indicated by sign based on normal distribution (allowing zero)
    -- Negative value means the other direction so in this phase the probability inclines to the positive direction.
    local movement = math.floor(normalRandom(self.movePdf.mean, self.movePdf.stdDev) + 0.5)
    
    -- Redirect to balance out the probability 
    local redirection = math.random(1, 2) == 1 and 1 or -1
    
    -- Calculate final step size
    local stepSize = movement * redirection

    -- Create a new position at a valid degree with current octave offset
    local targetPosition = ScaleNote.new(self.currentPosition.degree, self.currentPosition.octaveOffset)
    
    -- Use move to reach the desired position from the current one
    -- This handles degree wrapping and octave shifts correctly
    targetPosition:move(stepSize)
    
    -- Call factory callback to create the item at the target position and get the answer
    local item, answer = self.factoryCallback(targetPosition, self.midiRange, self.options)
    
    -- If item creation failed, return nil
    if not item then return nil, nil end
    
    -- Check if the item is within MIDI range
    if getmetatable(item) == Chord then
        if not item:isWithinMidiRange(self.keyContext, self.midiRange) then
            return nil, nil -- One note is outside of MIDI range
        end
    elseif getmetatable(item) == ScaleNote then
        local midiNote = self.keyContext:scaleNoteToMidi(item)
        if midiNote < self.midiRange.lo or midiNote > self.midiRange.hi then
            return nil, nil -- Outside of MIDI range
        end
    end
    
    return item, answer
end

-- Validate the generated item against constraints
function Generator:validateItem(item, answer)
    -- Check for repetition
    if self.options.noRepeat and self:isRepeat(item) then
        return false
    end
    
    -- Check for non-diatonic notes if not allowed
    if not self.options.allowNonDiatonic and self:hasNonDiatonicNotes(item) then
        return false
    end
    
    -- Check for consecutive identical answers if maxAnswerRepeat is specified
    if self.options.maxAnswerRepeat and answer then
        local consecutiveCount = 0
        
        -- Count how many times the current answer has appeared consecutively
        for i = #self.previousAnswers, 1, -1 do
            if self.previousAnswers[i] == answer then
                consecutiveCount = consecutiveCount + 1
                if consecutiveCount >= self.options.maxAnswerRepeat then
                    return false -- Too many consecutive identical answers
                end
            else
                break -- Chain broken, stop counting
            end
        end
    end
    
    return true
end

-- Check if the item is a repeat of the previous item
function Generator:isRepeat(item)
    if not self.previousItem then return false end
    
    -- Use the equals method of the appropriate class
    if getmetatable(item) == Chord and getmetatable(self.previousItem) == Chord then
        return item:equals(self.previousItem)
    elseif getmetatable(item) == ScaleNote and getmetatable(self.previousItem) == ScaleNote then
        return item:equals(self.previousItem)
    end
    
    return false
end

-- Check if the item contains non-diatonic notes
function Generator:hasNonDiatonicNotes(item)
    -- This is simplified and should be customized based on what items are
    if getmetatable(item) == Chord then
        for _, note in ipairs(item.notes) do
            if note.alteration ~= 0 then
                return true
            end
        end
    elseif getmetatable(item) == ScaleNote then
        return item.alteration ~= 0
    end
    
    return false
end

-- Update internal state after generating a valid item
function Generator:updateState(item)
    -- Update current position
    if getmetatable(item) == Chord then
        -- For chords, use the root note as new position
        self.currentPosition = item.notes[1]
    else
        -- For individual notes, use the note as new position
        self.currentPosition = item
    end
    
    -- Update previous item
    self.previousItem = item
end


---------------------------------------------------------------
-- Helper Functions for Uye Chord Progression Generators
---------------------------------------------------------------

-- Create a new track as a subtrack of selected track
local function createSubtrack()
    -- Get the currently selected track
    local selectedTrack = reaper.GetSelectedTrack(0, 0)
    if not selectedTrack then
        return reaper.GetMediaTrack(0, 0) -- Return first track if none selected
    end

    -- Get the track index and folder depth
    local trackIndex = reaper.GetMediaTrackInfo_Value(selectedTrack, "IP_TRACKNUMBER")
    local folderDepth = reaper.GetMediaTrackInfo_Value(selectedTrack, "I_FOLDERDEPTH")
    
    -- Check if the selected track is a folder parent (depth should be 1)
    local isFolder = (folderDepth == 1)
    
    -- If not a folder, make it a folder
    if not isFolder then
        reaper.SetMediaTrackInfo_Value(selectedTrack, "I_FOLDERDEPTH", 1)
    end
    
    -- Find the correct position for the new track
    -- If the selected track is already a folder, we need to find the last track in the folder
    local trackCount = reaper.CountTracks(0)
    local insertIndex = trackIndex
    
    if isFolder then
        local currentDepth = 1 -- Start at depth 1 (inside folder)
        
        -- Look for the end of the folder
        for i = trackIndex, trackCount - 1 do
            local depth = reaper.GetMediaTrackInfo_Value(reaper.GetTrack(0, i), "I_FOLDERDEPTH")
            currentDepth = currentDepth + depth
            
            -- If we've reached the end of the folder
            if currentDepth <= 0 then
                insertIndex = i
                break
            end
            
            -- If we reached the last track
            if i == trackCount - 1 then
                insertIndex = trackCount
                break
            end
        end
    end
    
    -- Insert a new track at the appropriate position (at the end of the folder or right after selected track)
    reaper.InsertTrackAtIndex(insertIndex, false)
    local newTrack = reaper.GetTrack(0, insertIndex)
    
    -- If this is the last track in the folder, update its folder depth to close the folder
    if isFolder then
        -- Check if the next track (if any) closes the folder
        if insertIndex < trackCount then
            local nextTrackDepth = reaper.GetMediaTrackInfo_Value(reaper.GetTrack(0, insertIndex + 1), "I_FOLDERDEPTH")
            if nextTrackDepth < 0 then
                -- The next track is a folder closing track, so we need to update its depth
                reaper.SetMediaTrackInfo_Value(reaper.GetTrack(0, insertIndex + 1), "I_FOLDERDEPTH", nextTrackDepth - 1)
            end
        end
    else
        -- Since we just made the selected track a folder, we need to close it
        reaper.SetMediaTrackInfo_Value(newTrack, "I_FOLDERDEPTH", -1)
    end

    return newTrack
end

-- Export chord progression data to CSV
local function exportChordProgressionsToCSV(progressions)
    -- Get timestamp for folder name
    local timestamp = os.date("%Y%m%d_%H%M%S")

    -- Get the project path
    local projectPath = reaper.GetProjectPath("")
    local renderFolder = projectPath .. "/../Answers"

    -- Create Render folder if it doesn't exist
    if not reaper.file_exists(renderFolder) then
        reaper.RecursiveCreateDirectory(renderFolder, 0)
    end

    -- Create timestamped folder
    local exportFolder = renderFolder .. "/" .. timestamp
    reaper.RecursiveCreateDirectory(exportFolder, 0)

    -- Create CSV file
    local csvFilePath = exportFolder .. "/chord_progressions.csv"
    local file = io.open(csvFilePath, "w")

    -- Write header
    file:write("filename,notes,key\n")

    -- Write data
    for filename, data in pairs(progressions) do
        file:write(filename .. "," .. data.notes .. "," .. data.key .. "\n")
    end

    file:close()

    return csvFilePath
end

-- Function to execute chord progression generation
local function executeChordProgressionGenerator(generatorFunc, trackName)
    -- Create a new track
    local track = createSubtrack()

    -- Reset cursor position
    reaper.SetEditCurPos(0, false, false)

    -- Reset MIDI item to avoid bad initial state
    currentMidiItem = nil
    currentMidiTake = nil

    -- Generate chord progression
    local result = generatorFunc(track)
    
    -- Set track name if provided
    reaper.GetSetMediaTrackInfo_String(track, "P_NAME", trackName and trackName or result.notes, true)
    
    -- Update MIDI item with notes data
    if currentMidiItem then
        -- Fixed API as requested - using proper API call for setting media notes
        reaper.GetSetMediaItemInfo_String(currentMidiItem, "P_NOTES", result.notes, true)
    end

    -- Reset state
    reaper.SetEditCurPos(0, false, false)
    currentMidiItem = nil
    currentMidiTake = nil

    return result
end

---------------------------------------------------------------
-- Uye Chord Progression Generators
---------------------------------------------------------------

-- Generate chord progression
local function generateChordPassiveAudio(track)
    -- Define factory callback for chord generation
    local factoryCallback = function(scaleNote)
        -- Only allow degrees that the user would like to train
        local degreeToTrain = "145"
        if not string.find(degreeToTrain, scaleNote.degree) then return nil end

        -- Create a diatonic triad with the degree
        local chord = Chord.newDiatonicTriad(scaleNote.degree, scaleNote.octaveOffset)

        -- Return both the chord and the degree as the answer
        return chord, scaleNote.degree
    end

    -- Keep generating until all scale degrees are used
    while true do
        -- Create a random key context
        local key = math.random(0, 11) -- 0 for C, 1 for C#, etc.
        local baseOctave = math.random(3, 4) -- Octaves 3-4
        local keyContext = MajorKeyContext.new(key, baseOctave)

        -- Create key validator
        local validator = UnivocalKeyValidator.new()

        -- Create generator
        local generator = Generator.new(
                keyContext,
                factoryCallback,
                {lo = 41, hi = 89}, -- MIDI range: F2-F5
                {mean = 3, stdDev = 4}, -- Movement parameters (absolute distance)
                {noRepeat = true, allowNonDiatonic = false, maxAnswerRepeat = 2} -- Options
        )

        -- Generate many chords
        local chords = {}
        local answers = {}
        local keyName = keyContext:getKeyName()
        local chordCount = 10

        for i = 1, chordCount do
            local chord, degree = generator:next()
            assert(chord, "generator:next() failed to generate an item.")

            table.insert(chords, chord)

            -- Add chord to validator
            validator:add(chord)

            -- Add to played chords string
            table.insert(answers, degree)
        end

        -- Check if we generated all 8 chords and the key is validated
        if validator:validate() then
            playSilent(1/2) -- Prevent play fading in some audio players
            
            playScale(track, keyContext, 1/8)
            playSilent(1/2)

            -- Play the chords
            for i = 1, #chords do
                -- Randomly choose ascending (123) or descending (321) pattern
                local pattern = math.random(1, 2) == 1 and "123" or "321"
                playChord(track, keyContext, chords[i], pattern)
                playSilent(3/4)
                playMedia(track, answers[i] .. ".wav", 1, false)
                playChord(track, keyContext, chords[i])
                playSilent(3/4)
            end

            return { notes = table.concat(answers, ""), key = keyName }
        end
    end
end

---------------------------------------------------------------
-- Main Function
---------------------------------------------------------------

-- Main function to run the script
local function main()
    -- Initialize random seed
    math.randomseed(os.time())
    
    -- Number of chord progressions to generate
    local n = 100
    
    -- Store progression data
    local progressions = {}
    reaper.Undo_BeginBlock()
    -- Generate folder3 chord progressions
    for i = 1, n do
        -- Execute generator and get results
        local result = executeChordProgressionGenerator(generateChordPassiveAudio)
        
        -- Store progression data
        local trackIndex = string.format("%03d", i)
        progressions[trackIndex] = result
    end
    reaper.UpdateArrange()
    reaper.Undo_EndBlock("Ear Training Question Generator", -1)
    
    -- Export to CSV
    exportChordProgressionsToCSV(progressions)
end

-- Entry point
main()