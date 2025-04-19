-- src/batch.lua
local util = require("util")

local batch_path = "batch/" .. os.date("%Y%m%d")

---enter vim editor to create a new batch
local function new()
    if not util.pathExists('batch') then
        os.execute('mkdir -p batch')
    end
    os.execute("nvim " .. batch_path)
end

new()
