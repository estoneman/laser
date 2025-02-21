-- src/main.lua

local capacity = 90

---capture command output into stdout
---@param cmd string
---@param raw boolean
local function cmdOutputCapture(cmd, raw)
    local proc = assert(io.popen(cmd, 'r'))
    local out = assert(proc:read('*a'))

    proc:close()

    if raw then return out end

    out = string.gsub(out, '^%s+', '')
    out = string.gsub(out, '%s+$', '')

    return out
end

---check if file exists
---@param file string
---@return boolean
local function exists(file)
    local handle, _ = io.open(file, 'r')
    if handle == nil then
        return false
    end

    handle:close()

    return true
end

---invoke `yt-dlp` to convert YouTube video to a WAV file
---@param track string
---@param dest string
---@param sleep integer
local function yt_dlp(track, dest, sleep)
    if not exists(dest) then
        os.execute('mkdir ' .. dest)
    end

    local date = os.date("%Y%m%d")
    if not exists('archive') then
        os.execute('mkdir archive')
    end
    local archive = './archive/' .. date

    local cmd = string.format([[
        yt-dlp \
            --sleep-interval %d \
            --audio-format wav \
            --output '%s/%%(id)s.wav' \
            --match-filters 'duration > 150' \
            --download-archive %s.archive \
            --format bestaudio \
            --extract-audio \
            --add-metadata \
            --quiet \
            "ytsearch:%s"
    ]], sleep, dest, archive, track)

    print('converting ' .. track)

    os.execute(cmd)
end

---read lines from file and return each line as its own in element in a table
---@param file string
---@return table, integer, string
local function readLines(file)
    if not exists(file) then
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

---check if directory is taking up too much space on its mountpoint
---@param dir string
---@return boolean
local function atCapacity(dir)
    local proc, _ = io.popen('df ' .. dir .. '| awk \'{ print $5 }\' | tail -1')
    if proc == nil then
        return false
    end

    local diskUsage
    local out = proc:read('a')
    ---@type number
    for v in string.gmatch(out, '%d+') do
        diskUsage = tonumber(v)
        if diskUsage == nil then
            return false
        end
    end

    local ret = false
    if diskUsage >= capacity then
        ret = true
    end

    proc:close()

    return ret
end

local function main()
    local tracks, count, msg = readLines('./batch/20250221')
    if string.len(msg) > 0 then
        print(msg)
        os.exit(1)
    end

    local dest = os.getenv('HOME') .. '/.local/share/rekordbox/usb/tracks/wav'
    if not exists(dest) then
        print('error: ' .. dest .. ' does not exist.. is it mounted?')
        os.exit(1)
    end

    if atCapacity(dest) then
        print('error: ' .. dest .. ' is at >=' .. capacity .. '% capacity.. get a new usb')
        os.exit(1)
    end

    local sleep = math.floor(1.05 ^ count)
    for _, track in pairs(tracks) do
        yt_dlp(track, dest, sleep)
    end
end

main()
