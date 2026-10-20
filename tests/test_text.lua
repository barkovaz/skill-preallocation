-- The mod's texts: every language complete, same placeholders as English, valid UTF-8, short
-- tooltip lines; language codes and formatting.
-- Run from the project folder:  lua5.1 tests/test_text.lua
SKILL_PREALLOCATION = { error = function(...) ERRORS = (ERRORS or 0) + 1 end }
local reads = 0
common = { get_context_value = function(t, id, expr) reads = reads + 1 return LANG end }
dofile("src/script/campaign/mod/skill_preallocation_text.lua")
local TEXT = SKILL_PREALLOCATION.text
local S = TEXT.strings

local passed, failed = 0, 0
local function check(c, msg) if c then passed = passed + 1 else failed = failed + 1 print("FAIL: " .. msg) end end

-- UTF-8: valid sequences; returns the number of characters and a display width (East Asian wide = 2)
local function utf8_info(s)
	local i, n, chars, width = 1, #s, 0, 0
	while i <= n do
		local c = s:byte(i)
		local len, cp
		if c < 0x80 then len, cp = 1, c
		elseif c >= 0xC2 and c <= 0xDF then len, cp = 2, c % 0x20
		elseif c >= 0xE0 and c <= 0xEF then len, cp = 3, c % 0x10
		elseif c >= 0xF0 and c <= 0xF4 then len, cp = 4, c % 0x08
		else return nil end
		for k = 1, len - 1 do
			local cc = s:byte(i + k)
			if not cc or cc < 0x80 or cc > 0xBF then return nil end
			cp = cp * 64 + (cc % 64)
		end
		chars = chars + 1
		local wide = (cp >= 0x1100 and cp <= 0x115F) or (cp >= 0x2E80 and cp <= 0xA4CF) or (cp >= 0xAC00 and cp <= 0xD7A3)
			or (cp >= 0xF900 and cp <= 0xFAFF) or (cp >= 0xFF00 and cp <= 0xFF60)
		width = width + (wide and 2 or 1)
		i = i + len
	end
	return chars, width
end

local function placeholders(s)
	local out = {}
	for p in string.gmatch(s, "%%[sd]") do out[#out + 1] = p end
	return table.concat(out, ",")
end

local function forms(v)
	if type(v) == "table" then return { v.one, v.other } end
	return { v }
end

check(#TEXT.languages == 13, "13 languages")
for _, lang in ipairs(TEXT.languages) do
	local L = S[lang]
	check(L ~= nil, lang .. ": present")
	if L then
		for key, en in pairs(S.en) do
			local v = L[key]
			check(v ~= nil, lang .. "." .. key .. ": present")
			if v ~= nil then
				local want = placeholders(forms(en)[1])
				for _, f in ipairs(forms(v)) do
					check(type(f) == "string" and f ~= "", lang .. "." .. key .. ": text")
					check(placeholders(f) == want, lang .. "." .. key .. ": placeholders " .. placeholders(f) .. " vs " .. want)
					check(utf8_info(f) ~= nil, lang .. "." .. key .. ": valid UTF-8")
					if lang ~= "en" and key ~= "default_name" then
						check(f ~= forms(en)[1] and f ~= forms(en)[2], lang .. "." .. key .. ": translated")
					end
				end
			end
		end
		for key in pairs(L) do check(S.en[key] ~= nil, lang .. "." .. key .. ": known key") end
		-- the tooltip stays narrow (it opens next to the button, near the screen's right edge)
		for line in string.gmatch(L.button_tip .. "\n", "(.-)\n") do
			local _, w = utf8_info(line)
			check(w and w <= 50, lang .. ": tooltip line too wide (" .. tostring(w) .. "): " .. line)
		end
	end
end

-- language codes the game may report
local cases = {
	EN = "en", en = "en", english = "en", FR = "fr", ["fr-FR"] = "fr", GE = "ge", de = "ge", German = "ge",
	IT = "it", SP = "sp", es = "sp", PL = "pl", RU = "ru", CZ = "cz", cs = "cz", TR = "tr", BR = "br",
	["pt-BR"] = "br", KR = "kr", ko = "kr", CN = "cn", ["zh-CN"] = "cn", schinese = "cn", ZH = "zh",
	["zh-TW"] = "zh", tchinese = "zh", [" ru "] = "ru", ["简体中文"] = "cn", ["繁體中文"] = "zh",
}
for code, want in pairs(cases) do
	check(TEXT.normalize(code) == want, "normalize(" .. code .. ") = " .. tostring(TEXT.normalize(code)) .. ", want " .. tostring(want))
end
for _, code in ipairs({ "xx", "", "klingon" }) do
	check(TEXT.normalize(code) == nil, "normalize(" .. code .. ") is unknown")
end
check(TEXT.normalize(nil) == nil and TEXT.normalize(7) == nil, "non-strings are unknown")

-- detection: read once; unknown -> English with one logged error; unreadable -> retried, then English
LANG = "RU"
check(TEXT.detect(nil) == nil and reads == 0, "no character, no read")
check(TEXT.detect(1) == "ru" and TEXT.detect(1) == "ru" and reads == 1, "read once (" .. reads .. ")")
check(TEXT.get("select") == "Выбрать шаблон", "Russian text")
check(TEXT.get("spend", 3) == "Распределить очки сейчас: 3", "Russian count: " .. TEXT.get("spend", 3))
TEXT.lang, reads, ERRORS = nil, 0, 0
LANG = "klingon"
check(TEXT.detect(1) == "en" and ERRORS == 1, "unknown language: English and one error")
TEXT.lang, reads, ERRORS, TEXT.tries = nil, 0, 0, 0
LANG = nil
check(TEXT.detect(1) == nil and TEXT.detect(1) == nil and TEXT.detect(1) == "en" and reads == 3 and ERRORS == 1,
	"unreadable language: tried 3 times, then English (" .. reads .. " reads, " .. tostring(ERRORS) .. " errors)")

-- formatting and fallbacks
TEXT.lang = "en"
check(TEXT.get("spend", 1) == "Allocate 1 point now" and TEXT.get("spend", 4) == "Allocate 4 points now", "English plural")
check(TEXT.get("ask_overwrite", "Tank") == "Overwrite the preset \"Tank\"?", "name in quotes")
check(TEXT.get("ask_spend", 1) == "Allocate 1 point now?" and TEXT.get("ask_spend", 6) == "Allocate 6 points now?", "English plural question")
check(TEXT.get("badge_tip", "7, 12") == "Pre-allocated: learned at rank 7, 12", "badge tooltip")
TEXT.lang = "ge"
check(TEXT.get("spend", 1) == "Jetzt 1 Punkt zuweisen" and TEXT.get("spend", 2) == "Jetzt 2 Punkte zuweisen", "German plural")
check(TEXT.get("ask_delete", "Panzer") == "Vorlage „Panzer“ löschen?", "German quotes")
TEXT.lang = "pl"
check(TEXT.get("ask_spend", 5) == "Rozdzielić teraz zaplanowane punkty (5)?", "Polish: the number in brackets")
TEXT.lang = "cn"
check(TEXT.get("ask_overwrite", "坦克") == "覆盖预设“坦克”？", "Chinese")
S.cn.select = nil
check(TEXT.get("select") == "Select preset", "a missing text falls back to English")
check(TEXT.get("no_such_key") == "no_such_key", "an unknown key shows itself")

print(string.format("%d passed, %d failed", passed, failed))
if failed > 0 then os.exit(1) end
