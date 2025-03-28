-- src/main.lua
local argparse = require("argparse")
local uv = require('luv')

---@type integer?
local minDiskSpace
local maxConcurrency = 20
local date = os.date("%Y%m%d")

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
        "df %s | awk '{ print $5 }' | tail -1",
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
            ytsearch:%q \
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
---@param onExit function
local function ytDlpSingle(track, dest, sleep, onExit)
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
    local url = getUrl(track)

    if url == nil then
        print('warn: \'' .. track .. '\' has been downloaded')
        return
    end
    print('debug: url found => ' .. url)

    local archive = './archive/' .. date .. '.archive'

    print('info: converting \'' .. track .. '\'')

    local args = {
        "--sleep-interval", tostring(sleep),
        "--audio-format", "wav",
        "--output", dest .. "/%(id)s.wav",
        "--download-archive", archive,
        "--format", "bestaudio",
        "--extract-audio",
        "--add-metadata",
        "--quiet",
        url
    }

    local handle, pid
    local stderr = uv.new_pipe()
    handle, pid = uv.spawn("yt-dlp", {
        args = args,
        stdio = { nil, nil, stderr }
    }, function(code)
        if code == 0 then
            onExit(true)
        else
            onExit(false)
        end

        print(string.format('debug: closing process (pid=%d)', pid))
        handle:close()
    end)

    uv.read_start(stderr, function(err, data)
        assert(not err, err)
        if data then
            print('stderr chunk', data)
        end
    end)

    stderr:close()

    print(string.format('debug: started process (pid=%d)', pid))
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

if #tracks > maxConcurrency then
    print(
        string.format(
            'error: currently, this downloader supports downloading up to %d tracks',
            maxConcurrency
        )
    )
    os.exit(1)
end

local sleep = math.floor(1.05 ^ count)
for _, track in pairs(tracks) do
    ytDlpSingle(track, args.destination, sleep, function(success)
        if success then
            print(string.format("info: '%s' successfully converted", track))
        else
            print(string.format("error: '%s' could not be converted", track))
        end
    end)
end

local signal = uv.new_signal()

uv.signal_start(signal, "sigint", function(signame)
    uv.signal_stop(signal)

    print("fatal: got " .. signame .. ", shutting down")

    uv.walk(function (handle)
        if not handle:is_closing() then
            handle:close()
        end
    end)

    uv.stop()
end)

uv.run()
