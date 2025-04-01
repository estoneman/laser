-- src/util.lua

local util = {}

---capture command output into stdout
---@param cmd string
---@param raw boolean
function util.cmdCapture(cmd, raw)
    local proc = assert(io.popen(cmd, 'r'))
    local out = assert(proc:read('*a'))

    proc:close()

    if raw then return out end

    out = string.gsub(out, '^%s+', '')
    out = string.gsub(out, '%s+$', '')

    return out
end

---check if directory is taking up too much space on its mountpoint
---@param dir string
---@param minDiskSpace integer
---@return boolean
function util.deviceFull(dir, minDiskSpace)
    local cmd = string.format(
        "df %s | awk '{ print $5 }' | tail -1",
        dir
    )

    local out = util.cmdCapture(cmd, false)

    ---@type integer?
    local diskUsage

    for v in string.gmatch(out, '%d+') do
        diskUsage = tonumber(v)
        if diskUsage == nil then
            return false
        end
    end

    local ret = false
    if diskUsage >= minDiskSpace then
        ret = true
    end

    return ret
end

---check if file exists
---@param file string
---@return boolean
function util.pathExists(file)
    local handle, _ = io.open(file, 'r')
    if handle == nil then
        return false
    end

    handle:close()

    return true
end

---read lines from file and return each line as its own in element in a table
---@param file string
---@return table, integer, string
function util.readLines(file)
    if not util.pathExists(file) then
        return {}, 0, string.format('%s: No such file or directory', file)
    end

    local handle, _ = io.open(file, 'r')
    if handle == nil then
        return {}, 0, string.format('fatal: could not open file with read permissions')
    end

    ---@type string
    local raw = handle:read('*a')

    ---@type table
    local t = {}
    local cnt = 0
    for line in raw:gmatch('[^\n]+') do
        table.insert(t, line)
        cnt = cnt + 1
    end

    return t, cnt, ""
end

return util
