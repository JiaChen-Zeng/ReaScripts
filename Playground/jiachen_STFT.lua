package.path = package.path .. ";" .. debug.getinfo(1, "S").source:match[[^@?(.*[\\/])[^\\/]-$]] .. "../Library/?.lua"
local serpent = require("serpent.src.serpent")

-- STFT parameters
local window_size = 1024
local hop_size = 512
local sample_rate = 48000

-- Hann window function
function hann_window(size)
    local window = {}
    for i = 0, size - 1 do
        window[i + 1] = 0.5 * (1 - math.cos(2 * math.pi * i / (size - 1)))
    end
    return window
end

-- Apply window function to a frame
function apply_window(frame, window)
    local windowed_frame = {}
    for i = 1, #frame do
        windowed_frame[i] = frame[i] * window[i]
    end
    return windowed_frame
end

-- Perform FFT (using Reaper's FFT function)
function fft(frame)
    local fft_size = #frame
    local fft_out = reaper.new_array(fft_size * 2)
    fft_out.copy(frame)
    fft_out.fft(fft_size, true)
    return fft_out
end

-- Compute STFT
function stft(audio, window_size, hop_size)
    local window = hann_window(window_size)
    local num_frames = math.floor((#audio - window_size) / hop_size) + 1
    local stft_result = {}

    for i = 0, num_frames - 1 do
        local start_index = i * hop_size + 1
        local frame = {}
        for j = 0, window_size - 1 do
            frame[j + 1] = audio[start_index + j]
        end
        local windowed_frame = apply_window(frame, window)
        local fft_result = fft(windowed_frame)
        table.insert(stft_result, fft_result)
    end

    return stft_result
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

-- Example usage
local media_item = reaper.GetSelectedMediaItem(0, 0)  -- Get the first selected media item
if media_item then
    local audio_data = get_audio_data_from_media_item(media_item)
    if audio_data then
        local stft_result = stft(audio_data, window_size, hop_size)
        
        -- Print the magnitude of the frequency components for each frame
        for i, frame in ipairs(stft_result) do
            reaper.ShowConsoleMsg("Frame " .. i .. ":\n")
            for j = 1, #frame / 2 do
                local magnitude = math.sqrt(frame[j * 2 - 1]^2 + frame[j * 2]^2)
                reaper.ShowConsoleMsg(magnitude .. "\n")
            end
        end
    else
        reaper.ShowConsoleMsg("Failed to get audio data from media item.\n")
    end
else
    reaper.ShowConsoleMsg("No media item selected.\n")
end
