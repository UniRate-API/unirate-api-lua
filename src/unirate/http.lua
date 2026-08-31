--- The default HTTP transport, backed by LuaSocket + LuaSec.
--
-- This module is `require`d *lazily* by the client (only when no transport is
-- injected), so the mock test suite — which always injects its own transport —
-- never loads LuaSec/LuaSocket or the C extensions they compile. That keeps the
-- offline test path free of the native dependency surface.

local errors = require("unirate.errors")

--- Perform a GET request and return `status, body`.
-- @param url     fully-qualified request URL (query string already built)
-- @param headers array of `{ name, value }` pairs
-- @param timeout per-request timeout in seconds
-- @return status (number), body (string)
local function request(url, headers, timeout)
  local https = require("ssl.https")
  local ltn12 = require("ltn12")

  -- LuaSec applies this module-level default as the socket connect timeout.
  if timeout and timeout > 0 then
    https.TIMEOUT = timeout
  end

  local hdr = {}
  for _, pair in ipairs(headers) do
    hdr[pair[1]] = pair[2]
  end

  local chunks = {}
  -- On success LuaSec returns `1, <http-status>, <headers>, <status-line>` and
  -- streams the body into the sink; on a transport failure it returns
  -- `nil, <error-message>`.
  local ok, code = https.request({
    url = url,
    method = "GET",
    headers = hdr,
    sink = ltn12.sink.table(chunks),
  })

  if not ok then
    error(errors.unirate("Network error: " .. tostring(code)))
  end

  return code, table.concat(chunks)
end

return { request = request }
