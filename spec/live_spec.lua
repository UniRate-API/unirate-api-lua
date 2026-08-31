--- Live test suite (free-tier endpoints only).
--
-- Tagged `#live`; the default `.busted` task excludes it, so `busted` runs the
-- mock suite only. Run these with `busted --run=live` (or `--tags=live`). Each
-- test self-skips (via `pending`) when `UNIRATE_API_KEY` is not set, so the
-- suite is safe to compile/run in CI without a key.
--
-- Only free-tier endpoints are exercised (/api/rates, /api/convert,
-- /api/currencies, /api/vat/rates). Historical/timeseries/limits are Pro-gated
-- (403 on the free tier) and are deliberately excluded.

local unirate = require("unirate")

local API_KEY = os.getenv("UNIRATE_API_KEY")

describe("#live free-tier endpoints", function()
  local client
  if API_KEY and #API_KEY > 0 then
    client = unirate.new(API_KEY)
  end

  local function requires_key(fn)
    return function()
      if not client then
        pending("UNIRATE_API_KEY not set")
        return
      end
      fn()
    end
  end

  it("get_rate returns a positive number", requires_key(function()
    local rate = client:get_rate("USD", "EUR")
    assert.is_number(rate)
    assert.is_true(rate > 0)
  end))

  it("get_all_rates returns a non-empty map", requires_key(function()
    local rates = client:get_all_rates("USD")
    assert.is_true(next(rates) ~= nil)
    assert.is_number(rates["EUR"])
  end))

  it("convert returns a positive number", requires_key(function()
    local result = client:convert(100, "USD", "EUR")
    assert.is_number(result)
    assert.is_true(result > 0)
  end))

  it("get_supported_currencies includes USD and EUR", requires_key(function()
    local codes = client:get_supported_currencies()
    local set = {}
    for _, c in ipairs(codes) do set[c] = true end
    assert.is_true(set["USD"])
    assert.is_true(set["EUR"])
  end))

  it("get_vat_rates returns country data", requires_key(function()
    local vat = client:get_vat_rates()
    assert.is_true(next(vat.vat_rates) ~= nil)
  end))

  it("get_vat_rate returns a single country", requires_key(function()
    local vat = client:get_vat_rate("DE")
    assert.equal("DE", vat.country)
    assert.is_number(vat.vat_data.vat_rate)
  end))
end)
