-- Parameters
local window_size = 1024
local hop_size = 512
local sample_rate = 48000

-- Compute the energy of a frame
function compute_energy(frame)
    local energy = 0
    for i = 1, #frame do
        energy = energy + frame[i] * frame[i]
    end
    return energy
end

-- Compute the mean and standard deviation of an array
function mean_and_std(array)
    local sum = 0
    for i = 1, #array do
        sum = sum + array[i]
    end
    local mean = sum / #array

    local variance = 0
    for i = 1, #array do
        variance = variance + (array[i] - mean) * (array[i] - mean)
    end
    local std = math.sqrt(variance / #array)

    return mean, std
end

-- Energy-based transient detection
function detect_transients(audio, window_size, hop_size)
    local num_frames = math.floor((#audio - window_size) / hop_size) + 1
    local energies = {}

    -- Compute energy for each frame
    for i = 0, num_frames - 1 do
        local start_index = i * hop_size + 1
        local frame = {}
        for j = 0, window_size - 1 do
            frame[j + 1] = audio[start_index + j]
        end
        local energy = compute_energy(frame)
        table.insert(energies, energy)
    end

    -- Compute dynamic threshold
    local mean_energy, std_energy = mean_and_std(energies)
    local threshold = mean_energy + 2 * std_energy

    -- Detect transients
    local transients = {}
    for i = 1, #energies do
        if energies[i] > threshold then
            table.insert(transients, i)
        end
    end

    return transients
end

-- Load media file and get audio data
function get_audio_data_from_media_item(media_item)
    local take = reaper.GetActiveTake(media_item)
    if not take or reaper.TakeIsMIDI(take) then return end

    local length, isqn = reaper.GetMediaSourceLength(reaper.GetMediaItemTake_Source(take))
    local num_samples = math.ceil(length * sample_rate)
    local audio_data = reaper.new_array(num_samples)
    reaper.GetAudioAccessorSamples(reaper.CreateTakeAudioAccessor(take), sample_rate, 1, 0, num_samples, audio_data)
    
    return audio_data
end

-- Insert markers at detected transient frames
function insert_markers(transients, hop_size)
    for i, frame in ipairs(transients) do
        local position = (frame - 1) * hop_size / sample_rate
        reaper.AddProjectMarker(0, false, position, 0, "Transient " .. i, -1)
    end
end

-- Example usage
local media_item = reaper.GetSelectedMediaItem(0, 0)  -- Get the first selected media item
if media_item then
    local audio_data = get_audio_data_from_media_item(media_item)
    if audio_data then
        local transients = detect_transients(audio_data, window_size, hop_size)
        
        -- Insert markers at detected transients
        insert_markers(transients, hop_size)
        
        reaper.ShowConsoleMsg("Inserted markers at detected transients.\n")
    else
        reaper.ShowConsoleMsg("Failed to get audio data from media item.\n")
    end
else
    reaper.ShowConsoleMsg("No media item selected.\n")
end
