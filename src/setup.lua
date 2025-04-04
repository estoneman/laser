-- src/setup.lua
local version = _VERSION:match("%d+%.%d+")

package.path = 'lua_modules/share/lua/' .. version ..
    '/?.lua;lua_modules/share/lua/' .. version ..
    '/?/init.lua;' .. package.path .. ';src/?.lua'
package.cpath = 'lua_modules/lib/lua/' .. version ..
    '/?.so;' .. package.cpath
