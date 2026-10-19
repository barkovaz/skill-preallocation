-- The native module's loader (LIVE.load_native) and its two files in the game's folder: the DLL is
-- written when missing or different and that very file is loaded; it isn't written again once it was
-- removed (by an antivirus or by hand), nor over a file someone changed, nor where it couldn't be
-- written; a DLL Windows refused isn't tried again until the mod brings another; nothing is written or
-- loaded while skill_preallocation_no_native.txt is there, and removing that file turns it on again.
-- Stand-ins play native_bin.lua and Windows (package.loadlib, require).
-- Run from tests/run:  lua5.1 ../test_loader.lua
local MOD = "../../src/script/campaign/mod/"
dofile(MOD .. "skill_preallocation_live.lua")
local LIVE = SKILL_PREALLOCATION_LIVE

local passed, failed = 0, 0
local function check(c, msg)
	if c then passed = passed + 1 else failed = failed + 1 print("FAIL: " .. msg) end
end

local NAME = "spa_loader_test"
local DLL, MARKER, OPT_OUT, BIN = NAME .. ".dll", LIVE.MARKER, LIVE.OPT_OUT, NAME .. "_bin.lua"
local real_open = io.open
local function write(path, data)
	local f = assert(real_open(path, "wb"))
	f:write(data)
	f:close()
end
local function read(path)
	local f = real_open(path, "rb")
	if not f then return nil end
	local d = f:read("*a")
	f:close()
	return d
end
local function set_bin(data, sha)
	write(BIN, string.format("return { module = %q, version = %q, sha256 = %q, size = %d, data = %q }", NAME, "1.0.1", sha, #data, data))
end
local function marker()
	local t = read(MARKER) or ""
	return string.match(t, 'state = "(%a+)"'), string.match(t, 'sha256 = "(%x*)"'), t
end

-- Windows: package.loadlib loads the file it is given (and only a file that is there), require is the fallback
local real_config, real_require, real_loadlib = package.config, require, package.loadlib
package.config = "\\" .. string.sub(package.config, 2)
local requires, loadlibs, refuse, no_loadlib, loaded_path = 0, 0, false, false, nil
local function module_table() return { api = LIVE.API, version = "1.0.1" } end
package.loadlib = function(path, fn)
	if no_loadlib then return nil, "loadlib not here (test)", "absent" end
	loadlibs = loadlibs + 1
	loaded_path = path
	if refuse then return nil, "is not a valid Win32 application (test)", "open" end
	if fn ~= "luaopen_" .. NAME or path ~= ".\\" .. DLL or not read(DLL) then return nil, "not found", "open" end
	return function() return module_table() end
end
require = function(name)
	if name ~= NAME then return real_require(name) end
	requires = requires + 1
	if refuse then error("is not a valid Win32 application (test)", 0) end
	assert(read(DLL), "require without the DLL")
	package.loaded[name] = module_table()
	return package.loaded[name]
end
local function session()
	LIVE.native_tried, LIVE.native, LIVE.native_problem, LIVE.native_written, LIVE.native_how = nil, nil, nil, nil, nil
	return LIVE.load_native()
end
LIVE.BIN = { BIN }
local function clean() for _, f in ipairs({ DLL, MARKER, BIN }) do os.remove(f) end for _, f in ipairs(LIVE.OPT_OUT_NAMES) do os.remove(f) end end
clean()

-- 1. the first session: written, loaded from that very file, the marker says so (with the link)
set_bin("DLL v1", "a1")
local mod, why = session()
local state, sha, text = marker()
check(mod ~= nil and LIVE.native_written == true and read(DLL) == "DLL v1", "first session: written and loaded (" .. tostring(why) .. ")")
check(loadlibs == 1 and requires == 0 and loaded_path == ".\\" .. DLL and LIVE.native_how == "package.loadlib",
	"loaded with package.loadlib from the folder's own file: " .. tostring(loaded_path) .. " " .. tostring(LIVE.native_how))
check(state == "written" and sha == "a1", "the marker says written: " .. tostring(state) .. " " .. tostring(sha))
check(string.find(text, LIVE.INFO_URL, 1, true) and string.find(text, OPT_OUT, 1, true) and string.find(text, "Delete this file", 1, true),
	"the marker says what the DLL is, where to read about it and how to turn it off")
check(package.loaded[NAME] == nil, "the module isn't left in package.loaded")

-- 2. without package.loadlib (some Lua builds): require finds it, and it's taken off package.loaded again
no_loadlib = true
mod = session()
check(mod ~= nil and requires == 1 and LIVE.native_written == nil and package.loaded[NAME] == nil
	and string.find(tostring(LIVE.native_how), "^require; package.loadlib: loadlib not here") ~= nil,
	"no loadlib: require, nothing written again, the log says why: " .. tostring(LIVE.native_how))
no_loadlib = false

-- 3. a mod update brings another DLL: written over the old one
set_bin("DLL v2", "b2")
mod = session()
state, sha = marker()
check(mod ~= nil and read(DLL) == "DLL v2" and sha == "b2", "an update replaces the DLL")

-- 4. the DLL was removed (an antivirus, the player): not written again, and the log says how to allow it
os.remove(DLL)
mod, why = session()
state = marker()
check(mod == nil and read(DLL) == nil and state == "removed", "a removed DLL isn't written again (" .. tostring(state) .. ")")
check(string.find(tostring(why), "was removed", 1, true) and string.find(tostring(why), MARKER, 1, true), "the reason names the file to delete: " .. tostring(why))
set_bin("DLL v3", "c3")
mod = session()
check(mod == nil and read(DLL) == nil, "not even when the mod updates")

-- 5. the marker deleted: the mod starts over
os.remove(MARKER)
mod = session()
state, sha = marker()
check(mod ~= nil and read(DLL) == "DLL v3" and state == "written" and sha == "c3", "the marker deleted: written again")

-- 6. someone changed the DLL after the mod wrote it (an antivirus "cleaning" it): left as it is
write(DLL, "DLL v3, cleaned")
mod, why = session()
state = marker()
check(mod == nil and read(DLL) == "DLL v3, cleaned" and state == "changed" and string.find(tostring(why), "was changed", 1, true),
	"a changed DLL isn't written over: " .. tostring(why))
mod = session()
check(mod == nil and read(DLL) == "DLL v3, cleaned", "nor in the next session")
set_bin("DLL v4", "d4")
mod = session()
check(mod ~= nil and read(DLL) == "DLL v4", "a mod update writes its own DLL")

-- 7. Windows refuses to load it: not tried again until the mod brings another DLL
refuse = true
set_bin("DLL v5", "e5")
local tries = loadlibs + requires
mod, why = session()
state, sha = marker()
check(mod == nil and state == "refused" and sha == "e5" and loadlibs + requires > tries, "refused: " .. tostring(why))
tries = loadlibs + requires
mod, why = session()
check(mod == nil and loadlibs + requires == tries and string.find(tostring(why), "earlier session", 1, true), "the same DLL isn't tried again: " .. tostring(why))
refuse = false
set_bin("DLL v6", "f6")
mod = session()
state, sha = marker()
check(mod ~= nil and read(DLL) == "DLL v6" and state == "written" and sha == "f6", "another DLL is tried")

-- 8. the DLL can't be written (an antivirus blocks it): not tried again every session
os.remove(DLL)
os.remove(MARKER)
local writes = 0
io.open = function(path, mode)
	if path == DLL and mode == "wb" then writes = writes + 1 return nil, path .. ": Permission denied", 13 end
	return real_open(path, mode)
end
mod, why = session()
state = marker()
check(mod == nil and writes == 1 and state == "blocked", "blocked: " .. tostring(why))
mod, why = session()
check(mod == nil and writes == 1 and string.find(tostring(why), "couldn't be written", 1, true), "not tried again: " .. tostring(why))
io.open = real_open
os.remove(MARKER)

-- 9. an antivirus changes the file as it is written: not loaded, and left be afterwards
io.open = function(path, mode)
	if path == DLL and mode == "wb" then
		local f = real_open(path, mode)
		return { write = function(self) f:write("changed") end, close = function() f:close() end }
	end
	return real_open(path, mode)
end
mod, why = session()
io.open = real_open
check(mod == nil and string.find(tostring(why), "isn't what was written", 1, true), "a changed file isn't loaded: " .. tostring(why))
mod = session()
check(mod == nil and read(DLL) == "changed", "and isn't written over in the next session")
os.remove(DLL)
mod = session()
check(mod == nil and read(DLL) == nil, "nor written again once it's gone")
os.remove(MARKER)

-- 10. a DLL that is there but can't be read now: nothing changes, the next session tries again
mod = session()                                       -- (written and loaded: v6)
io.open = function(path, mode)
	if path == DLL and mode == "rb" then return nil, path .. ": Permission denied", 13 end
	return real_open(path, mode)
end
mod, why = session()
io.open = real_open
state = marker()
check(mod == nil and state == "written" and string.find(tostring(why), "can't read", 1, true), "unreadable for now: " .. tostring(why))
mod = session()
check(mod ~= nil, "and loaded in the next session")

-- 11. the opt-out file: never written, never loaded; deleting the DLL meanwhile is fine; removing the
-- file turns it on again
for _, name in ipairs(LIVE.OPT_OUT_NAMES) do
	write(name, "")
	local before = loadlibs + requires
	mod, why = session()
	check(mod == nil and loadlibs + requires == before and string.find(tostring(why), name, 1, true), "opt-out with " .. name .. ": " .. tostring(why))
	os.remove(name)
end
write(OPT_OUT, "")
mod = session()
state = marker()
check(state == "off", "the marker says off: " .. tostring(state))
os.remove(DLL)
mod = session()
check(mod == nil and read(DLL) == nil, "opted out: the DLL deleted, nothing written")
os.remove(OPT_OUT)
mod = session()
state = marker()
check(mod ~= nil and read(DLL) == "DLL v6" and state == "written", "the opt-out file removed: written and loaded again (" .. tostring(state) .. ")")

-- 12. not Windows: nothing happens
package.config = "/" .. string.sub(package.config, 2)
mod, why = session()
check(mod == nil and string.match(tostring(why), "^not Windows") ~= nil, "not Windows: " .. tostring(why))

package.config, require, package.loadlib = real_config, real_require, real_loadlib
clean()
print(passed .. " passed, " .. failed .. " failed")
if failed > 0 then os.exit(1) end
