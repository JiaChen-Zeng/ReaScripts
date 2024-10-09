function compute_transient(media_item_take, window_size, hop_size)
  if window_size == nil then window_size = 1024 end
  if hop_size == nil then hop_size = 512 end

  -- Compute the energy of a frame
  local function compute_energy(frame)
    local energy = 0
    for i = 1, #frame do
      energy = energy + frame[i] * frame[i]
    end
    return energy
  end

  -- Compute the mean and standard deviation of an array
  local function mean_and_std(array)
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
  local function compute_transients(audio)
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
  local function get_audio_data()
    if not media_item_take or reaper.TakeIsMIDI(media_item_take) then return end

    local source = reaper.GetMediaItemTake_Source(media_item_take)
    local sample_rate = reaper.GetMediaSourceSampleRate(source)
    local length, isqn = reaper.GetMediaSourceLength(source)

    if isqn then
      local _, bpm = reaper.GetProjectTimeSignature2(0)
      length = length * 60 / bpm -- Convert quarter notes to seconds
    end

    local num_samples = math.ceil(length * sample_rate)
    local audio_data = reaper.new_array(num_samples)
    reaper.GetAudioAccessorSamples(reaper.CreateTakeAudioAccessor(media_item_take), sample_rate, 1, 0, num_samples, audio_data)

    return audio_data, sample_rate
  end

  local function compute_max_transient(transients, sample_rate)
    local position = 0
    for _, frame in ipairs(transients) do
      position = position + (frame - 1) * hop_size / sample_rate
    end
    return position / #transients
  end


  local audio_data, sample_rate = get_audio_data()
  local transients = compute_transients(audio_data)
  return compute_max_transient(transients, sample_rate)
end

return { compute_transient = compute_transient }