-- @description Auto Light Color - Core (internal module)
-- @author Jiachen
-- @version 0.1.0
-- Shared, GUI-independent settings and perceptual color selection.

local M = {}
M.SECTION = "jiachen_AutoLightColor"
M.DEFAULTS = {
  enabled = 1, min_lightness = 79, max_lightness = 90,
  vibrancy = 48, variation = 40, separation = 12
}

local function clamp(x, lo, hi)
  return math.max(lo, math.min(hi, x))
end
M.clamp = clamp

function M.read_settings(api)
  local s = {}
  for key, default in pairs(M.DEFAULTS) do
    local value = tonumber(api.GetExtState(M.SECTION, key))
    if value == nil then value = default end
    s[key] = value
  end
  s.enabled = s.enabled == 0 and 0 or 1
  s.min_lightness = clamp(s.min_lightness, 65, 97)
  s.max_lightness = clamp(s.max_lightness, s.min_lightness, 98)
  s.vibrancy = clamp(s.vibrancy, 0, 100)
  s.variation = clamp(s.variation, 0, 100)
  s.separation = clamp(s.separation, 0, 20)
  return s
end

function M.save_setting(api, key, value)
  assert(M.DEFAULTS[key] ~= nil, "invalid setting: " .. tostring(key))
  api.SetExtState(M.SECTION, key, tostring(value), true)
  api.SetExtState(M.SECTION, "revision", tostring(api.time_precise()), false)
end

-- OKLab/OKLCH, using D65 sRGB. The comparison works in perceptual coordinates,
-- not RGB or HSV; exact-looking neighboring pastels are rejected.
local function gamma_decode(x)
  if x <= 0.04045 then return x / 12.92 end
  return ((x + 0.055) / 1.055) ^ 2.4
end

local function gamma_encode(x)
  if x <= 0.0031308 then return 12.92 * x end
  return 1.055 * x ^ (1 / 2.4) - 0.055
end

local function cube_root(x)
  if x < 0 then return -((-x) ^ (1 / 3)) end
  return x ^ (1 / 3)
end

function M.rgb_to_lab(r, g, b)
  r, g, b = gamma_decode(r / 255), gamma_decode(g / 255), gamma_decode(b / 255)
  local l = cube_root(0.4122214708*r + 0.5363325363*g + 0.0514459929*b)
  local m = cube_root(0.2119034982*r + 0.6806995451*g + 0.1073969566*b)
  local s = cube_root(0.0883024619*r + 0.2817188376*g + 0.6299787005*b)
  return {
    0.2104542553*l + 0.7936177850*m - 0.0040720468*s,
    1.9779984951*l - 2.4285922050*m + 0.4505937099*s,
    0.0259040371*l + 0.7827717662*m - 0.8086757660*s
  }
end

local function linear_rgb(L, a, b)
  local l = (L + 0.3963377774*a + 0.2158037573*b)^3
  local m = (L - 0.1055613458*a - 0.0638541728*b)^3
  local s = (L - 0.0894841775*a - 1.2914855480*b)^3
  return
    4.0767416621*l - 3.3077115913*m + 0.2309699292*s,
   -1.2684380046*l + 2.6097574011*m - 0.3413193965*s,
   -0.0041960863*l - 0.7034186147*m + 1.7076147010*s
end

local function is_in_gamut(r,g,b)
  return r >= -0.0000001 and r <= 1.0000001
     and g >= -0.0000001 and g <= 1.0000001
     and b >= -0.0000001 and b <= 1.0000001
end

function M.lch_to_rgb(L, C, hue)
  local a, b = C * math.cos(hue), C * math.sin(hue)
  local r,g,bl = linear_rgb(L,a,b)
  if not is_in_gamut(r,g,bl) then
    -- Reduce chroma, rather than clipping RGB channels and changing hue/lightness.
    local lo,hi = 0,C
    for _ = 1, 16 do
      local mid = (lo+hi)*0.5
      r,g,bl = linear_rgb(L,mid*math.cos(hue),mid*math.sin(hue))
      if is_in_gamut(r,g,bl) then lo=mid else hi=mid end
    end
    a,b = lo*math.cos(hue),lo*math.sin(hue)
    r,g,bl = linear_rgb(L,a,b)
  end
  local function byte(v)
    return math.floor(clamp(gamma_encode(clamp(v, 0, 1)), 0, 1) * 255 + 0.5)
  end
  return byte(r),byte(g),byte(bl)
end

function M.distance(a,b)
  local dl, da, db = a[1]-b[1], a[2]-b[2], a[3]-b[3]
  return math.sqrt(dl*dl + da*da + db*db)
end

-- neighbors: list of {L,a,b}; rng: optional deterministic function [0,1) for testing.
-- Find random acceptable pastel colors and avoid over-optimising to one hue.
function M.pick_color(settings, neighbors, rng)
  rng = rng or math.random
  local threshold = settings.separation / 100
  local count = 128
  local eligible, best, best_score = {}, nil, -1
  for _ = 1, count do
    local lightness = (settings.min_lightness
      + rng()*(settings.max_lightness-settings.min_lightness))/100
    local hue = rng() * 2 * math.pi
    local amount = (0.018 + 0.00205 * settings.vibrancy)
      * (1 + (rng()*2-1) * settings.variation/125)
    local r,g,b = M.lch_to_rgb(lightness, math.max(0, amount), hue)
    local lab = M.rgb_to_lab(r,g,b)
    local min_score = math.huge
    for _, neighbor in ipairs(neighbors or {}) do
      min_score = math.min(min_score, M.distance(lab, neighbor))
    end
    local candidate = {r=r,g=g,b=b,lab=lab,score=min_score}
    if min_score >= threshold then eligible[#eligible+1] = candidate end
    if min_score > best_score then
      best_score, best = min_score, candidate
    end
  end
  if #eligible > 0 then
    return eligible[math.floor(rng()*#eligible)+1]
  end
  return best
end

return M
