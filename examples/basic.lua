-- Runnable example. Reads the API key from the UNIRATE_API_KEY env var.
--
--   UNIRATE_API_KEY=your-key lua examples/basic.lua
--
-- Needs the rock installed (luarocks install unirate-api), or run from the repo
-- root with:  lua -e 'package.path="./src/?.lua;./src/?/init.lua;"..package.path' examples/basic.lua

local unirate = require("unirate")

local api_key = os.getenv("UNIRATE_API_KEY")
if not api_key or #api_key == 0 then
  io.stderr:write("Set UNIRATE_API_KEY to run this example.\n")
  os.exit(1)
end

local client = unirate.new(api_key)

local ok, err = pcall(function()
  print("USD -> EUR rate: " .. client:get_rate("USD", "EUR"))
  print("100 USD in EUR:  " .. client:convert(100, "USD", "EUR"))
  print("Supported currencies: " .. #client:get_supported_currencies())
end)

if not ok then
  if unirate.errors.is_error(err) then
    io.stderr:write("UniRate error (" .. err.type .. "): " .. err.message .. "\n")
  else
    io.stderr:write("Error: " .. tostring(err) .. "\n")
  end
  os.exit(1)
end
