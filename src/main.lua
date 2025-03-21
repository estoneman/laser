-- src/main.lua
local argparse = require("argparse")

---@type integer?
local minDiskSpace

---@type table
local threads = {}

if not os.getenv('PERCENT_DISK_REM') then
    minDiskSpace = 90
else
    minDiskSpace = tonumber(os.getenv('PERCENT_DISK_REM'))
    if not minDiskSpace then
        print('[error] invalid percentage (should be number)')
        os.exit(1)
    end
end

---capture command output into stdout
---@param cmd string
---@param raw boolean
local function cmdCapture(cmd, raw)
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
---@return boolean
local function deviceFull(dir)
    local cmd = string.format(
        'df %s | awk \'{ print $5 }\' | tail -1',
        dir
    )

    local out = cmdCapture(cmd, false)

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
local function pathExists(file)
    local handle, _ = io.open(file, 'r')
    if handle == nil then
        return false
    end

    handle:close()

    return true
end

---extract YouTube URL given a track title
---@param track string
---@return string?
local function getUrl(track)
    local date = os.date("%Y%m%d")

    if not pathExists('archive') then
        os.execute('mkdir archive')
    end

    local archive = './archive/' .. date .. '.archive'

    track = string.gsub(track, '"', '\\"')

    local cmd = string.format([[
        yt-dlp \
            --download-archive %s \
            --print-json \
            --skip-download \
            "ytsearch:%s" \
        | jq --raw-output .webpage_url
    ]], archive, track)

    local out = cmdCapture(cmd, false)

    if out == "" then
        return nil
    end

    return out
end

---invoke `yt-dlp` to convert YouTube video to a WAV file
---@param track string
---@param dest string
---@param sleep integer
local function ytDlpSingle(track, dest, sleep)
    if not pathExists(dest) then
        os.execute('mkdir ' .. dest)
    end

    if deviceFull(dest) then
        print(
            string.format(
                'error: %s is at >= %d%% capacity.. get a new storage device',
                dest,
                minDiskSpace
            )
        )

        os.exit(1)
    end

    print('info: retrieving url of \'' .. track .. '\'')
    -- local url = getUrl(track)
    local co = coroutine.create(function(t)
        local url = getUrl(t)
        coroutine.yield(url)
    end)

    local _, url = coroutine.resume(co, track)

    if url == nil then
        print('warn: \'' .. track .. '\' has been downloaded')
        return
    end
    print('debug: url found => ' .. url)

    local date = os.date("%Y%m%d")
    local archive = './archive/' .. date .. '.archive'

    local cmd = string.format([[
        yt-dlp \
            --sleep-interval %d \
            --audio-format wav \
            --output '%s/%%(id)s.wav' \
            --download-archive %s \
            --format bestaudio \
            --extract-audio \
            --add-metadata \
            --quiet \
            "%s"
    ]], sleep, dest, archive, url)

    print('info: converting \'' .. track .. '\'')

    co = coroutine.create(function ()
        os.execute(cmd)
    end)

    table.insert(threads, co)
end

---read lines from file and return each line as its own in element in a table
---@param file string
---@return table, integer, string
local function readLines(file)
    if not pathExists(file) then
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

local function tableLen(t)
    local count = 0
    for _ in pairs(t) do count = count + 1 end
    return count
end

local function dispatcher()
    while true do
        local n = tableLen(threads)
        if n == 0 then break end
        for i=1,n do
            local _, res = coroutine.resume(threads[i])
            if not res then
                table.remove(threads, i)
                break
            end
        end
    end
end

local parser = argparse("laser")
    :description("Lua wrapper to yt-dlp")
    :epilog("source can be found at: https://github.com/estoneman/laser.git")

parser:help_max_width(80)
parser:option("-f --batch-file")
    :description("path to existing file containing track titles " ..
                 "separated by a newline")
    :target("batch_file")

parser:option("-d --destination")
    :description("directory where the converted tracks should be stored")
    :target("destination")

local args = parser:parse()

if args.batch_file == nil or args.destination == nil then
    print(parser:get_help())
    os.exit(1)
end

local tracks, count, msg = readLines(args.batch_file)
if string.len(msg) > 0 then
    print(msg)
    os.exit(1)
end

local sleep = math.floor(1.05 ^ count)
for _, track in pairs(tracks) do
    ytDlpSingle(track, args.destination, sleep)
end

dispatcher()
