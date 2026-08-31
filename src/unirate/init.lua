--- Official Lua client for the [UniRate API](https://unirateapi.com).
--
-- Free real-time and historical currency exchange rates plus VAT rates.
--
--   local unirate = require("unirate")
--   local client = unirate.new("your-api-key")
--   print(client:get_rate("USD", "EUR"))
--   print(client:convert(100, "USD", "EUR"))
--
-- The HTTP layer is injectable (`opts.transport`), so tests run fully offline
-- without loading LuaSocket/LuaSec. JSON decoding uses the pure-Lua `dkjson`.

local errors = require("unirate.errors")
local json = require("dkjson")

local M = {}

M.VERSION          = "0.1.0"
M.DEFAULT_BASE_URL = "https://api.unirateapi.com"
M.DEFAULT_TIMEOUT  = 30 -- seconds

M.errors = errors -- re-export so callers can `require("unirate").errors`

local Client = {}
Client.__index = Client

-- ---- helpers ---------------------------------------------------------------

local function strip_trailing_slash(s)
  return (s:gsub("/+$", ""))
end

-- Percent-encode a value per the RFC 3986 unreserved set.
local function url_encode(s)
  return (tostring(s):gsub("[^%w%-_%.~]", function(c)
    return string.format("%%%02X", string.byte(c))
  end))
end

-- Render a number for a query string without a spurious ".0" on integers.
local function format_amount(n)
  if math.type and math.type(n) == "integer" then
    return tostring(n)
  end
  if n == math.floor(n) and math.abs(n) < 1e15 then
    return string.format("%d", n)
  end
  return (string.format("%.14g", n)) -- avoids float noise, keeps precision
end

local function to_number(v)
  if type(v) == "number" then return v end
  if type(v) == "string" then return tonumber(v) end
  return nil
end

local function field_or_error(obj, key)
  if type(obj) == "table" and obj[key] ~= nil then
    return obj[key]
  end
  error(errors.unirate("Response missing expected field '" .. key .. "'"))
end

local function to_rate_map(obj, key)
  local out = {}
  local m = type(obj) == "table" and obj[key] or nil
  if type(m) == "table" then
    for code, v in pairs(m) do
      out[code] = to_number(v)
    end
  end
  return out
end

local function build_url(self, path, params)
  local parts = {}
  for _, p in ipairs(params) do
    parts[#parts + 1] = url_encode(p[1]) .. "=" .. url_encode(p[2])
  end
  parts[#parts + 1] = "api_key=" .. url_encode(self.api_key)
  return self.base_url .. path .. "?" .. table.concat(parts, "&")
end

local function common_headers(self)
  return {
    { "Accept", "application/json" },
    { "User-Agent", self.user_agent },
  }
end

-- Append the optional `format` / `callback` query params from an options table.
local function apply_options(params, opts)
  if type(opts) == "table" then
    if opts.format then params[#params + 1] = { "format", opts.format } end
    if opts.callback then params[#params + 1] = { "callback", opts.callback } end
  end
end

-- ---- constructor -----------------------------------------------------------

--- Create a client.
-- @param api_key your UniRate API key (string, required)
-- @param opts    optional table: `{ timeout = <seconds>, base_url = <url>,
--                transport = <function(url, headers, timeout) -> status, body> }`
function M.new(api_key, opts)
  assert(type(api_key) == "string" and #api_key > 0, "api_key is required")
  opts = opts or {}
  local self = setmetatable({}, Client)
  self.api_key    = api_key
  self.base_url   = strip_trailing_slash(opts.base_url or M.DEFAULT_BASE_URL)
  self.timeout    = opts.timeout or M.DEFAULT_TIMEOUT
  self.user_agent = "unirate-lua/" .. M.VERSION
  self.transport  = opts.transport -- injectable; nil -> default LuaSec transport
  return self
end

function Client:_request_json(path, params)
  local transport = self.transport
  if not transport then
    transport = require("unirate.http").request
  end
  local url = build_url(self, path, params)
  local status, body = transport(url, common_headers(self), self.timeout)
  if type(status) ~= "number" then
    error(errors.unirate("Transport returned a non-numeric status"))
  end
  if status < 200 or status >= 300 then
    error(errors.from_status(status, body or ""))
  end
  local decoded, _, err = json.decode(body or "")
  if err or decoded == nil then
    error(errors.unirate("Failed to parse response JSON: " .. tostring(err)))
  end
  return decoded
end

-- ---- current rates ---------------------------------------------------------

--- Current exchange rate from `from` to `to`. Codes are uppercased. → number
function Client:get_rate(from, to, opts)
  local params = {
    { "from", tostring(from):upper() },
    { "to", tostring(to):upper() },
  }
  apply_options(params, opts)
  return to_number(field_or_error(self:_request_json("/api/rates", params), "rate"))
end

--- All current rates for a base currency (default "USD"). → table<code, number>
function Client:get_all_rates(base, opts)
  local params = { { "from", tostring(base or "USD"):upper() } }
  apply_options(params, opts)
  return to_rate_map(self:_request_json("/api/rates", params), "rates")
end

--- Convert `amount` from one currency to another at the current rate. → number
function Client:convert(amount, from, to, opts)
  local params = {
    { "from", tostring(from):upper() },
    { "to", tostring(to):upper() },
    { "amount", format_amount(amount) },
  }
  apply_options(params, opts)
  return to_number(field_or_error(self:_request_json("/api/convert", params), "result"))
end

--- The list of supported currency codes. → array<string>
function Client:get_supported_currencies(opts)
  local params = {}
  apply_options(params, opts)
  local obj = self:_request_json("/api/currencies", params)
  local out = {}
  if type(obj) == "table" and type(obj.currencies) == "table" then
    for _, code in ipairs(obj.currencies) do
      out[#out + 1] = code
    end
  end
  return out
end

-- ---- historical data (Pro-gated: 403 on the free tier) ---------------------

--- Historical rate for a single from/to pair on `date` (YYYY-MM-DD). → number
function Client:get_historical_rate(date, from, to, opts)
  local params = {
    { "date", date },
    { "amount", "1" },
    { "from", tostring(from):upper() },
    { "to", tostring(to):upper() },
  }
  apply_options(params, opts)
  return to_number(field_or_error(
    self:_request_json("/api/historical/rates", params), "rate"))
end

--- All historical rates for a base currency on `date`. → table<code, number>
function Client:get_historical_rates(date, base, opts)
  local params = {
    { "date", date },
    { "amount", "1" },
    { "from", tostring(base or "USD"):upper() },
  }
  apply_options(params, opts)
  return to_rate_map(self:_request_json("/api/historical/rates", params), "rates")
end

--- Convert `amount` using the rate from a specific historical `date`. → number
function Client:convert_historical(amount, from, to, date, opts)
  local params = {
    { "date", date },
    { "amount", format_amount(amount) },
    { "from", tostring(from):upper() },
    { "to", tostring(to):upper() },
  }
  apply_options(params, opts)
  return to_number(field_or_error(
    self:_request_json("/api/historical/rates", params), "result"))
end

--- A range of historical rates between two dates (max 5-year span).
-- `options` = `{ amount = 1, base = "USD", currencies = { "EUR", ... },
-- format = ..., callback = ... }`. Returns the `date -> (code -> number)` map
-- directly (matching the Python/Node/Swift clients).
function Client:get_time_series(start_date, end_date, options)
  options = options or {}
  local params = {
    { "start_date", start_date },
    { "end_date", end_date },
    { "amount", format_amount(options.amount or 1) },
    { "base", tostring(options.base or "USD"):upper() },
  }
  if type(options.currencies) == "table" and #options.currencies > 0 then
    local upper = {}
    for _, c in ipairs(options.currencies) do
      upper[#upper + 1] = tostring(c):upper()
    end
    params[#params + 1] = { "currencies", table.concat(upper, ",") }
  end
  apply_options(params, options)
  local obj = self:_request_json("/api/historical/timeseries", params)
  local data = {}
  if type(obj) == "table" and type(obj.data) == "table" then
    for date, row in pairs(obj.data) do
      local m = {}
      if type(row) == "table" then
        for code, v in pairs(row) do m[code] = to_number(v) end
      end
      data[date] = m
    end
  end
  return data
end

--- Per-currency historical coverage. → table with total_currencies /
-- data_source / currencies fields (as returned by the API).
function Client:get_historical_limits(opts)
  local params = {}
  apply_options(params, opts)
  local obj = self:_request_json("/api/historical/limits", params)
  return {
    total_currencies = obj.total_currencies,
    data_source = obj.data_source,
    currencies = obj.currencies or {},
  }
end

-- ---- VAT -------------------------------------------------------------------

--- VAT data for every supported country. → table with date / total_countries /
-- vat_rates fields.
function Client:get_vat_rates(opts)
  local params = {}
  apply_options(params, opts)
  local obj = self:_request_json("/api/vat/rates", params)
  return {
    date = obj.date,
    total_countries = obj.total_countries,
    vat_rates = obj.vat_rates or {},
  }
end

--- VAT data for a single ISO-3166 alpha-2 country code (e.g. "DE"). → table
-- with country / vat_data fields.
function Client:get_vat_rate(country, opts)
  local params = { { "country", tostring(country):upper() } }
  apply_options(params, opts)
  local obj = self:_request_json("/api/vat/rates", params)
  return {
    country = obj.country,
    vat_data = obj.vat_data or {},
  }
end

M.Client = Client

return M
