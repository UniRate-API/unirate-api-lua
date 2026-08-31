--- Mock (offline) test suite.
--
-- Every test injects a stub transport, so no network is touched and neither
-- LuaSocket nor LuaSec is loaded. Covers all eleven client methods, the URL /
-- header construction, and the full HTTP-status error mapping.

local unirate = require("unirate")
local errors = require("unirate.errors")

-- Decode a percent-encoded query component.
local function url_decode(s)
  s = s:gsub("+", " ")
  return (s:gsub("%%(%x%x)", function(h)
    return string.char(tonumber(h, 16))
  end))
end

-- Split the query string of a URL into a decoded key -> value map.
local function query_of(url)
  local q = {}
  local qs = url:match("%?(.*)$")
  if not qs then return q end
  for pair in qs:gmatch("[^&]+") do
    local k, v = pair:match("^([^=]*)=(.*)$")
    if k then q[url_decode(k)] = url_decode(v) end
  end
  return q
end

local function header_of(headers, name)
  for _, pair in ipairs(headers) do
    if pair[1] == name then return pair[2] end
  end
  return nil
end

-- A client whose transport always returns `status`/`body`, recording the
-- request into `rec` (if given).
local function stub_client(status, body, rec)
  local transport = function(url, headers, timeout)
    if rec then
      rec.url = url
      rec.headers = headers
      rec.timeout = timeout
    end
    return status, body
  end
  return unirate.new("test-key", {
    base_url = "https://mock.local",
    transport = transport,
  })
end

describe("current rates", function()
  it("get_rate parses a string rate, uppercases codes, sends headers", function()
    local rec = {}
    local client = stub_client(200, '{"rate": "0.9321"}', rec)
    local rate = client:get_rate("usd", "eur")
    assert.is_true(rate > 0.9320 and rate < 0.9322)
    local q = query_of(rec.url)
    assert.truthy(rec.url:find("/api/rates", 1, true))
    assert.equal("USD", q["from"])
    assert.equal("EUR", q["to"])
    assert.equal("test-key", q["api_key"])
    assert.equal("application/json", header_of(rec.headers, "Accept"))
    assert.truthy(header_of(rec.headers, "User-Agent"):find("^unirate%-lua/"))
    assert.equal(30, rec.timeout)
  end)

  it("get_all_rates accepts both string and numeric rate values", function()
    local client = stub_client(200, '{"rates": {"EUR": "0.9", "GBP": 0.8}}')
    local rates = client:get_all_rates("USD")
    assert.equal(0.9, rates["EUR"])
    assert.equal(0.8, rates["GBP"])
  end)

  it("convert puts the amount in the query and parses the result", function()
    local rec = {}
    local client = stub_client(200, '{"result": "93.21"}', rec)
    local v = client:convert(100, "USD", "EUR")
    assert.is_true(v > 93.20 and v < 93.22)
    assert.equal("100", query_of(rec.url)["amount"])
  end)

  it("convert renders fractional amounts without truncating", function()
    local rec = {}
    local client = stub_client(200, '{"result": "1.0"}', rec)
    client:convert(2.5, "USD", "EUR")
    assert.equal("2.5", query_of(rec.url)["amount"])
  end)

  it("get_supported_currencies returns the code list", function()
    local client = stub_client(200, '{"currencies": ["USD", "EUR", "GBP"]}')
    local codes = client:get_supported_currencies()
    assert.same({ "USD", "EUR", "GBP" }, codes)
  end)

  it("format/callback options land in the query string", function()
    local rec = {}
    local client = stub_client(200, '{"rate": "1.0"}', rec)
    client:get_rate("USD", "EUR", { format = "json", callback = "cb" })
    local q = query_of(rec.url)
    assert.equal("json", q["format"])
    assert.equal("cb", q["callback"])
  end)
end)

describe("historical (Pro-gated shapes)", function()
  it("get_historical_rate parses a single rate", function()
    local rec = {}
    local client = stub_client(200, '{"rate": "0.88"}', rec)
    assert.equal(0.88, client:get_historical_rate("2024-01-01", "USD", "EUR"))
    local q = query_of(rec.url)
    assert.truthy(rec.url:find("/api/historical/rates", 1, true))
    assert.equal("2024-01-01", q["date"])
  end)

  it("get_historical_rates returns a rate map", function()
    local client = stub_client(200, '{"rates": {"EUR": "0.9", "JPY": 130.0}}')
    local rates = client:get_historical_rates("2024-01-01", "USD")
    assert.equal(0.9, rates["EUR"])
    assert.equal(130.0, rates["JPY"])
  end)

  it("convert_historical parses the result field", function()
    local client = stub_client(200, '{"result": "88.00"}')
    assert.equal(88.0, client:convert_historical(100, "USD", "EUR", "2024-01-01"))
  end)

  it("get_time_series parses nested date/currency data", function()
    local body = [[{"amount": 1, "base": "USD", "start_date": "2024-01-01",
      "end_date": "2024-01-02", "total_days": 2, "currencies": ["EUR", "GBP"],
      "data": {"2024-01-01": {"EUR": 0.92, "GBP": 0.79},
               "2024-01-02": {"EUR": 0.93, "GBP": 0.80}}}]]
    local rec = {}
    local client = stub_client(200, body, rec)
    local data = client:get_time_series("2024-01-01", "2024-01-02",
      { currencies = { "eur", "gbp" } })
    assert.equal(0.92, data["2024-01-01"]["EUR"])
    assert.equal(0.80, data["2024-01-02"]["GBP"])
    assert.equal("EUR,GBP", query_of(rec.url)["currencies"])
  end)

  it("get_historical_limits parses per-currency coverage", function()
    local body = [[{"total_currencies": 2, "data_source": "test",
      "currencies": {"USD": {"earliest_date": "1999-01-01",
      "latest_date": "2026-04-22", "total_days": 9000, "description": "US Dollar"}}}]]
    local client = stub_client(200, body)
    local limits = client:get_historical_limits()
    assert.equal(2, limits.total_currencies)
    assert.equal("1999-01-01", limits.currencies["USD"].earliest_date)
    assert.equal(9000, limits.currencies["USD"].total_days)
  end)
end)

describe("VAT", function()
  it("get_vat_rates parses the country map", function()
    local body = [[{"total_countries": 1, "date": "2026-04-22",
      "vat_rates": {"DE": {"country_code": "DE", "country_name": "Germany",
      "vat_rate": 19.0}}}]]
    local client = stub_client(200, body)
    local vat = client:get_vat_rates()
    assert.equal(1, vat.total_countries)
    assert.equal("Germany", vat.vat_rates["DE"].country_name)
    assert.equal(19.0, vat.vat_rates["DE"].vat_rate)
  end)

  it("get_vat_rate parses a single country and uppercases the code", function()
    local rec = {}
    local client = stub_client(200, [[{"country": "DE", "vat_data":
      {"country_code": "DE", "country_name": "Germany", "vat_rate": 19.0}}]], rec)
    local vat = client:get_vat_rate("de")
    assert.equal("DE", vat.country)
    assert.equal(19.0, vat.vat_data.vat_rate)
    assert.equal("DE", query_of(rec.url)["country"])
  end)
end)

describe("error mapping", function()
  local function expect_error(client, method_call, tag)
    local ok, err = pcall(method_call)
    assert.is_false(ok)
    assert.is_true(errors.is_error(err))
    assert.equal(tag, err.type)
    return err
  end

  it("400 -> InvalidDateError", function()
    local client = stub_client(400, "bad")
    expect_error(client, function() return client:get_rate("USD", "EUR") end,
      errors.INVALID_DATE_ERROR)
  end)

  it("401 -> AuthenticationError", function()
    local client = stub_client(401, "nope")
    expect_error(client, function() return client:get_rate("USD", "EUR") end,
      errors.AUTHENTICATION_ERROR)
  end)

  it("404 -> InvalidCurrencyError", function()
    local client = stub_client(404, "missing")
    expect_error(client, function() return client:get_rate("USD", "XXX") end,
      errors.INVALID_CURRENCY_ERROR)
  end)

  it("429 -> RateLimitError", function()
    local client = stub_client(429, "slow down")
    expect_error(client, function() return client:get_rate("USD", "EUR") end,
      errors.RATE_LIMIT_ERROR)
  end)

  it("403 -> APIError carrying status and body", function()
    local client = stub_client(403, "Pro only")
    local err = expect_error(client,
      function() return client:get_historical_rate("2024-01-01", "USD", "EUR") end,
      errors.API_ERROR)
    assert.equal(403, err.status)
    assert.equal("Pro only", err.body)
  end)

  it("503 -> APIError with status 503", function()
    local client = stub_client(503, "down")
    local err = expect_error(client,
      function() return client:get_supported_currencies() end,
      errors.API_ERROR)
    assert.equal(503, err.status)
  end)

  it("malformed JSON body raises a UnirateError", function()
    local client = stub_client(200, "not json{")
    expect_error(client, function() return client:get_supported_currencies() end,
      errors.UNIRATE_ERROR)
  end)

  it("missing expected field raises a UnirateError", function()
    local client = stub_client(200, '{"unexpected": true}')
    expect_error(client, function() return client:get_rate("USD", "EUR") end,
      errors.UNIRATE_ERROR)
  end)
end)

describe("metadata", function()
  it("exposes VERSION", function()
    assert.equal("0.1.0", unirate.VERSION)
  end)

  it("requires an api_key", function()
    assert.has_error(function() unirate.new(nil) end)
    assert.has_error(function() unirate.new("") end)
  end)

  it("re-exports the errors module", function()
    assert.equal(errors, unirate.errors)
  end)
end)
