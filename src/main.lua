-- src/main.lua

local argparse = require("argparse")
local uv = require('luv')
local util = require("util")

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

---extract YouTube URL given a track title
---@param track string
---@return string?
local function getUrl(track)
    if not util.pathExists('archive') then
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

    local out = util.cmdCapture(cmd, false)

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
    if not util.pathExists(dest) then
        os.execute('mkdir ' .. dest)
    end

    if util.deviceFull(dest, minDiskSpace) then
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

    local format = "flac"
    local args = {
        "--sleep-interval", tostring(sleep),
        "--audio-format", format,
        "--output", dest .. "/%(id)s." .. format,
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

local function main()
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

    local tracks, count, msg = util.readLines(args.batch_file)
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

    uv.run()
end

main()
