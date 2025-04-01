-- src/batch.lua

local batch_path = "batch/" .. os.date("%Y%m%d")

---enter vim editor to create a new batch
local function new()
    os.execute("/usr/local/bin/nvim " .. batch_path)
end

new()
