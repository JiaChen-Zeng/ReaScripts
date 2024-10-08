TransientDetection = {
  window_size = 1024,
  hop_size = 512
}

-- Compute the energy of a frame
function TransientDetection._compute_energy(frame)
  local energy = 0
  for i = 1, #frame do
    energy = energy + frame[i] * frame[i]
  end
  return energy
end

-- Compute the mean and standard deviation of an array
function TransientDetection._mean_and_std(array)
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
function TransientDetection._compute_transients(audio)
  local num_frames = math.floor((#audio - TransientDetection.window_size) / TransientDetection.hop_size) + 1
  local energies = {}

  -- Compute energy for each frame
  for i = 0, num_frames - 1 do
    local start_index = i * TransientDetection.hop_size + 1
    local frame = {}
    for j = 0, TransientDetection.window_size - 1 do
      frame[j + 1] = audio[start_index + j]
    end
    local energy = TransientDetection._compute_energy(frame)
    table.insert(energies, energy)
  end

  -- Compute dynamic threshold
  local mean_energy, std_energy = TransientDetection._mean_and_std(energies)
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
function TransientDetection._get_audio_data(media_item)
  local take = reaper.GetActiveTake(media_item)
  if not take or reaper.TakeIsMIDI(take) then return end

  local source = reaper.GetMediaItemTake_Source(take)
  local sample_rate = reaper.GetMediaSourceSampleRate(source)
  local length, isqn = reaper.GetMediaSourceLength(source)

  if isqn then
    local _, bpm = reaper.GetProjectTimeSignature2(0)
    length = length * 60 / bpm -- Convert quarter notes to seconds
  end

  local num_samples = math.ceil(length * sample_rate)
  local audio_data = reaper.new_array(num_samples)
  reaper.GetAudioAccessorSamples(reaper.CreateTakeAudioAccessor(take), sample_rate, 1, 0, num_samples, audio_data)

  return audio_data, sample_rate
end

function TransientDetection._compute_max_transient(transients, sample_rate)
  local position = 0
  for _, frame in ipairs(transients) do
    position = position + (frame - 1) * TransientDetection.hop_size / sample_rate
  end
  return position / #transients
end

function TransientDetection.compute_transient(item)
  local audio_data, sample_rate = TransientDetection._get_audio_data(item)
  local transients = TransientDetection._compute_transients(audio_data)
  return TransientDetection._compute_max_transient(transients, sample_rate)
end
