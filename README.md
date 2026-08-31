# UniRate Lua Client

Official Lua client for the [UniRate API](https://unirateapi.com) — free, real-time and historical currency exchange rates plus VAT rates.

- 🔄 Real-time exchange rates between 170+ currencies (fiat + crypto)
- 📈 Historical rates back to 1999
- ⏰ Time-series ranges up to 5 years
- 💰 Currency conversion (current and historical)
- 🏛️ VAT rates for countries worldwide
- 🆓 Free tier, no credit card required
- 🧩 Injectable HTTP transport — the mock test suite runs fully offline
- 📦 Small dependency surface — pure-Lua JSON (`dkjson`) + LuaSocket/LuaSec for HTTPS

## Requirements

- Lua 5.1+ (including LuaJIT)
- For live HTTPS requests: `luasocket` + `luasec` (pulled in as dependencies)

## Installation

```sh
luarocks install unirate-api
```

## Quick start

```lua
local unirate = require("unirate")

local client = unirate.new("your-api-key")

-- Current rate
print(client:get_rate("USD", "EUR"))

-- Convert
print(client:convert(100, "USD", "EUR"))

-- All supported currencies
print(#client:get_supported_currencies())
```

Get a free API key at [https://unirateapi.com](https://unirateapi.com).

## API

Methods use colon syntax (`client:get_rate(...)`), so the client is the implicit
`self`. Currency and country codes are uppercased for you.

### Current rates

```lua
local rate  = client:get_rate("USD", "EUR")          -- number
local rates = client:get_all_rates("USD")            -- { EUR = 0.92, ... }
local euros = client:convert(100, "USD", "EUR")      -- number
local codes = client:get_supported_currencies()      -- { "USD", "EUR", ... }
```

### Historical data (Pro tier)

These endpoints require a Pro subscription and raise an `APIError` (status 403)
on the free tier.

```lua
client:get_historical_rate("2024-01-01", "USD", "EUR")           -- number
client:get_historical_rates("2024-01-01", "USD")                 -- { EUR = 0.92, ... }
client:convert_historical(100, "USD", "EUR", "2024-01-01")       -- number
client:get_time_series("2024-01-01", "2024-01-07",
  { currencies = { "EUR", "GBP" } })                             -- { ["2024-01-01"] = { EUR = ... } }
client:get_historical_limits()                                   -- table
```

### VAT rates

```lua
local all = client:get_vat_rates()          -- { date, total_countries, vat_rates }
local de  = client:get_vat_rate("DE")        -- { country, vat_data }
print(de.vat_data.vat_rate)                  -- 19.0
```

### Constructor options & response formats

```lua
local client = unirate.new("your-api-key", {
  timeout  = 30,                              -- seconds (default 30)
  base_url = "https://api.unirateapi.com",    -- override (mainly for tests)
  transport = my_transport,                   -- inject a custom HTTP transport
})
```

Every method accepts an optional trailing options table with `format` and
`callback` keys for the API's query parameters. The typed methods always decode
JSON, so request non-JSON formats only when you know what you are doing.

## Error handling

Lua has no exception classes, so errors are raised (via `error()`) as tables
with a `.type` tag. Catch them with `pcall`:

```lua
local unirate = require("unirate")
local errors = unirate.errors

local ok, err = pcall(function()
  return client:get_rate("USD", "EUR")
end)

if not ok and errors.is_error(err) then
  if err.type == errors.AUTHENTICATION_ERROR then
    print("check your API key")
  elseif err.type == errors.RATE_LIMIT_ERROR then
    print("slow down")
  elseif err.type == errors.API_ERROR then
    print("API error " .. err.status .. ": " .. err.body)
  else
    print("unirate error: " .. err.message)
  end
end
```

| HTTP status | `err.type` | Meaning |
|---|---|---|
| 400 | `INVALID_DATE_ERROR` | Invalid request parameters |
| 401 | `AUTHENTICATION_ERROR` | Missing or invalid API key |
| 403 | `API_ERROR` (`err.status == 403`) | Endpoint requires a Pro subscription |
| 404 | `INVALID_CURRENCY_ERROR` | Currency not found / no data |
| 429 | `RATE_LIMIT_ERROR` | Rate limit exceeded |
| 503 | `API_ERROR` (`err.status == 503`) | Service unavailable |
| other / network | `API_ERROR` / `UNIRATE_ERROR` | Generic / transport error |

## Rate limits

The free tier is rate limited. On HTTP 429 the client raises a `RATE_LIMIT_ERROR`
— back off and retry.

## Testing

```sh
busted              # mock suite (offline, no key needed)
busted --run=live   # free-tier live tests (need UNIRATE_API_KEY)
```

The client takes an injectable `transport`, so the mock suite runs entirely
offline without loading LuaSocket/LuaSec.

## Related clients

UniRate ships official clients for Python, Node/TypeScript, Swift, Java, Go,
Rust, Ruby, PHP, .NET, Dart, D, Nim, and more — see the
[UniRate-API organization](https://github.com/UniRate-API).

## License

MIT — see [LICENSE](LICENSE).
