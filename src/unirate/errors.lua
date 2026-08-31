--- Typed error objects for the UniRate client.
--
-- Lua has no exception-class hierarchy, so every failure is raised with
-- `error()` carrying a *table* value. Each error table has a `.type` field
-- (one of the `M.*_ERROR` tags — the "class name"), a human-readable
-- `.message`, and — for API errors — the originating `.status` code and the
-- response `.body`. Every error object shares one metatable, so
-- `errors.is_error(v)` recognises "any UniRate error" the way a base class
-- would, while `err.type` branches on the specific kind.
--
--   local ok, err = pcall(function() return client:get_rate("USD", "EUR") end)
--   if not ok and errors.is_error(err) then
--     if err.type == errors.AUTHENTICATION_ERROR then ... end
--   end

local M = {}

-- Error type tags (the equivalent of subclass names).
M.UNIRATE_ERROR          = "UnirateError"
M.AUTHENTICATION_ERROR   = "AuthenticationError"
M.RATE_LIMIT_ERROR       = "RateLimitError"
M.INVALID_CURRENCY_ERROR = "InvalidCurrencyError"
M.INVALID_DATE_ERROR     = "InvalidDateError"
M.API_ERROR              = "APIError"

-- Shared metatable identifies "a UniRate error" and prints the message.
local mt = {
  __tostring = function(e) return e.message end,
}

local function make(err_type, message, extra)
  local e = { type = err_type, message = message }
  if extra then
    for k, v in pairs(extra) do e[k] = v end
  end
  return setmetatable(e, mt)
end

--- True if `v` is any UniRate error object.
function M.is_error(v)
  return type(v) == "table" and getmetatable(v) == mt
end

function M.unirate(message)
  return make(M.UNIRATE_ERROR, message or "UniRate error")
end

function M.authentication(message)
  return make(M.AUTHENTICATION_ERROR, message or "Missing or invalid API key")
end

function M.rate_limit(message)
  return make(M.RATE_LIMIT_ERROR, message or "Rate limit exceeded")
end

function M.invalid_currency(message)
  return make(M.INVALID_CURRENCY_ERROR,
    message or "Currency not found or no data available")
end

function M.invalid_date(message)
  return make(M.INVALID_DATE_ERROR, message or "Invalid request parameters")
end

function M.api(status, body)
  local detail = (body and #body > 0) and (": " .. body) or ""
  return make(M.API_ERROR,
    string.format("UniRate API error (status %d)%s", status, detail),
    { status = status, body = body or "" })
end

--- Map an HTTP status code to the appropriate typed error.
-- 403 (Pro-gate) and 503 (unavailable) fall through to `api`, which carries
-- the status and response body for inspection.
function M.from_status(status, body)
  body = body or ""
  if status == 400 then
    return M.invalid_date()
  elseif status == 401 then
    return M.authentication()
  elseif status == 404 then
    return M.invalid_currency()
  elseif status == 429 then
    return M.rate_limit()
  else
    return M.api(status, body)
  end
end

return M
