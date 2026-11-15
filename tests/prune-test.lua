-- Self-check for the clean-up in knp_build.lua (one edition kept, folders of papers off the shelves deleted).
-- From the repo root, with LuaFileSystem (apt install lua5.1 lua-filesystem): lua5.1 tests/prune-test.lua
package.path = "konewspaper.koplugin/?.lua;" .. package.path
local lfs = require("lfs")
local home = os.tmpname()
os.remove(home)
assert(lfs.mkdir(home))
package.loaded["device"] = { home_dir = home }
package.loaded["libs/libkoreader-lfs"] = lfs
package.loaded["ffi/util"] = { purgeDir = function(d) os.execute(("rm -rf %q"):format(d)) end }
for _, m in ipairs{ "ffi/archiver", "socket.http", "logger", "ltn12", "ffi/sha2", "socket", "socket.url", "socketutil" } do
    package.loaded[m] = {}
end
package.loaded["knp_extract"] = {}
local Build = require("knp_build")

local function touch(p) local f = assert(io.open(p, "w")); f:close() end
local function exists(p) return lfs.attributes(p) ~= nil end
local root = home .. "/KoNewspaper"
lfs.mkdir(root)
for _, id in ipairs{ "a", "b" } do
    local dir = root .. "/" .. id
    lfs.mkdir(dir); lfs.mkdir(dir .. "/cache"); touch(dir .. "/cache/abc.lua")
    for _, d in ipairs{ "2026-11-13", "2026-11-14", "2026-11-15" } do
        touch(dir .. "/" .. d .. ".epub"); touch(dir .. "/" .. d .. ".cover.jpg"); touch(dir .. "/" .. d .. ".meta.lua")
    end
    lfs.mkdir(dir .. "/2026-11-09.sdr"); touch(dir .. "/2026-11-09.sdr/metadata.epub.lua") -- an orphan from long ago
end
lfs.mkdir(root .. "/mine") -- not a paper: never touched

Build.prune({ id = "a" })
assert(exists(root .. "/a/2026-11-15.epub") and exists(root .. "/a/2026-11-15.cover.jpg") and exists(root .. "/a/2026-11-15.meta.lua"))
assert(not exists(root .. "/a/2026-11-14.epub") and not exists(root .. "/a/2026-11-13.cover.jpg"))
assert(not exists(root .. "/a/2026-11-09.sdr"), "old .sdr goes too")
assert(exists(root .. "/a/cache/abc.lua"), "the cache is pruned per update, not here")

Build.dropUnshelved({ { id = "a" }, { id = "b" }, { id = "c" } }, { a = true })
assert(exists(root .. "/a/2026-11-15.epub"))
assert(not exists(root .. "/b"), "paper off the shelves: folder gone")
assert(exists(root .. "/mine"), "folders that aren't papers stay")

os.execute(("rm -rf %q"):format(home))
print("prune: all OK")
