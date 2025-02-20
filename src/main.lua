-- src/main.lua

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
local function exists(file)
    local ok, err, code = os.rename(file, file)
    if not ok then
        if code == 13 then
            -- permissiond denied, but still exists
            return true
        end
    end

    return ok, err
end

---check if `path` is a directory
---@param path string
---@return boolean
local function isdir(path)
    return exists(path .. '/')
end

---invoke `yt-dlp` to convert YouTube video to a WAV file
---@param track string
---@param dest string
---@param sleep integer
local function yt_dlp(track, dest, sleep)
    if not isdir(dest) then
        os.execute('mkdir ' .. dest)
    end

    local date = os.date("%Y%m%d")
    if not isdir('archive') then
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

    print(cmd)
    os.execute(cmd)
end

---return length of table
---@param t table
local function tableLen(t)
    local count = 0
    for _ in pairs(t) do count = count + 1 end
    return count
end

local function main()
    local tracks = {
        'let the bass kick, lemtom',
        'u won\'t see me, rossi.',
        'how u make me feel, dj seinfeld',
        'out the fire (at the hotel) [feat. eunice collins], franky rizardo & ros t',
        'spanish fly, 2000 and one',
        'good 4 u, luuk van fijk & kolter',
        'baby be mine, demarzo',
        'make it, demarzo',
    }

    local dest = os.getenv('HOME') .. '/.local/share/rekordbox/usb/tracks/wav'
    local nTracks = tableLen(tracks)
    for _, track in pairs(tracks) do
        yt_dlp(track, dest, math.floor(1.05 ^ nTracks))
    end
end

main()
