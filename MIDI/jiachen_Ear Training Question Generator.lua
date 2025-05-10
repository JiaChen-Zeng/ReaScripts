-- Ear Training Question Generator for Reaper
-- This script provides functionality for generating ear training exercises in Reaper

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
    assert(1 <= degree, "Scale degree must be at least 1")
    
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

function Chord:getNotes()
    return self.notes
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
    if currentMidiItem == nil then
        local cursorPos = reaper.GetCursorPosition()
        currentMidiItem = reaper.CreateNewMIDIItemInProj(track, cursorPos, cursorPos + getDefaultNoteLength() * 32)  -- Create a longer item initially to fix MIDI length issue
        currentMidiTake = reaper.GetActiveTake(currentMidiItem)
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
local function playScale(track, keyContext, direction, bars, velocity, advance)
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

-- Play a block chord
local function playBlockChord(track, keyContext, chordOrNotes, bars, velocity, advance)
    if advance == nil then advance = true end
    velocity = velocity or DEFAULT_VELOCITY
    bars = bars or 1
    local duration = getDefaultNoteLength() * bars
    
    local cursorPos = reaper.GetCursorPosition()
    
    -- Get or create MIDI item and take
    local item, take = getCurrentMidiItem(track)
    
    local startPPQPos = reaper.MIDI_GetPPQPosFromProjTime(take, cursorPos)
    local endPPQPos = reaper.MIDI_GetPPQPosFromProjTime(take, cursorPos + duration)
    
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
    
    -- Insert all notes in the chord
    for _, scaleNote in ipairs(notesToPlay) do
        local midiNote = keyContext:scaleNoteToMidi(scaleNote)
        reaper.MIDI_InsertNote(take, false, false, startPPQPos, endPPQPos, 0, midiNote, velocity, false)
    end
    
    -- Advance the cursor if requested
    if advance then
        reaper.SetEditCurPos(cursorPos + duration, true, false)
    end
    
    return cursorPos + (advance and duration or 0)
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
    
    -- Get the track index
    local trackIndex = reaper.GetMediaTrackInfo_Value(selectedTrack, "IP_TRACKNUMBER")
    
    -- Insert a new track after the selected track
    reaper.InsertTrackAtIndex(trackIndex, false)
    local newTrack = reaper.GetTrack(0, trackIndex)
    
    -- Make it a child of the selected track
    reaper.SetMediaTrackInfo_Value(newTrack, "P_PARTRACK", reaper.GetMediaTrackInfo_Value(selectedTrack, "PTR_TRACKNUMBER"))
    
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
    
    -- Set track name if provided
    if trackName then
        reaper.GetSetMediaTrackInfo_String(track, "P_NAME", trackName, true)
    end
    
    -- Reset cursor position
    reaper.SetEditCurPos(0, false, false)
    
    -- Reset MIDI item
    currentMidiItem = nil
    currentMidiTake = nil
    
    -- Generate chord progression
    local result = generatorFunc(track)
    
    -- Update MIDI item with notes data
    if currentMidiItem then
        -- Fixed API as requested - using proper API call for setting media notes
        reaper.GetSetMediaItemInfo_String(currentMidiItem, "P_NOTES", result.notes, true)
    end
    
    -- Update the arrange view
    reaper.UpdateArrange()
    
    return result
end

---------------------------------------------------------------
-- Uye Chord Progression Generators
---------------------------------------------------------------

-- Generate chord progression using scale degrees 1, 2, 4, 5, 6
local function generateUyeChordProgressionFolder3(track)
    -- Available chord degrees
    local chordDegrees = {1, 2, 4, 5, 6}
    
    -- Keep generating until all scale degrees are used
    while true do
        -- Create a random key context
        local rootNote = math.random(0, 11) -- 0 for C, 1 for C#, etc.
        local baseOctave = math.random(3, 4) -- Octaves 3-4
        local keyContext = MajorKeyContext.new(rootNote, baseOctave)
        
        -- Track played chords and validate key usage
        local validator = UnivocalKeyValidator.new()
        local chords = {}
        local playedChords = ""
        local keyName = keyContext:getKeyName()
        
        -- Previous chord degree to avoid repetition
        local prevDegreeIndex = nil
        
        -- Track current octave offset (between -1 and 1)
        local currentOctaveOffset = 0
        
        -- Play 8 random chords
        for i = 1, 8 do
            -- Decide if we should change the octave (20% chance)
            if math.random(1, 100) <= 20 then
                -- Determine direction of octave change
                local direction = math.random(0, 1) * 2 - 1  -- -1 or 1
                
                -- Ensure the offset stays within -1 to 1 range
                if currentOctaveOffset == 1 then
                    direction = -1  -- Can only go down
                elseif currentOctaveOffset == -1 then
                    direction = 1   -- Can only go up
                end
                
                -- Apply octave shift
                currentOctaveOffset = currentOctaveOffset + direction
            end
            
            -- Generate a random degree different from the previous one
            local degreeIndex = randomDifferentInteger(1, #chordDegrees, prevDegreeIndex)
            local degree = chordDegrees[degreeIndex]
            
            -- Create the chord with current octave offset
            local chord = Chord.newDiatonicTriad(degree, currentOctaveOffset)
            table.insert(chords, chord)
            
            -- Add chord to validator
            validator:add(chord)
            
            -- Add to played chords string
            playedChords = playedChords .. degree
            
            -- Update previous degree
            prevDegreeIndex = degreeIndex
        end
        
        -- Check if all scale degrees were used
        if validator:validate() then
            -- Play the chord only after validated because playing function has side effect
            for i = 1, #chords do
                playBlockChord(track, keyContext, chords[i])
            end

            return {notes = playedChords, key = keyName}
        end
        
        -- If not all scale degrees were used, reset and try again
        reaper.SetEditCurPos(0, false, false)
        currentMidiItem = nil
        currentMidiTake = nil
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
    local n = 10
    
    -- Store progression data
    local progressions = {}
    reaper.Undo_BeginBlock()
    -- Generate folder3 chord progressions
    for i = 1, n do
        -- Create track name with padded number
        local trackName = string.format("Folder3_%03d", i)
        
        -- Execute generator and get results
        local result = executeChordProgressionGenerator(generateUyeChordProgressionFolder3, trackName)
        
        -- Store progression data
        progressions[trackName] = result
    end
    reaper.Undo_EndBlock("generateUyeChordProgressionFolder3", -1)
    
    -- Export to CSV
    exportChordProgressionsToCSV(progressions)
end

-- Entry point
main()