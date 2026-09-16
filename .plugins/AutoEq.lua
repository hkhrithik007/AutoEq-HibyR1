-- HiBy R1 AutoEq
-- AutoEq precomputed IEM PEQ client.
-- Large database stays on SD; only the selected profile is parsed/applied.
-- Runtime state is kept in plugin.storage (no .autoeq_* files on the SD card).

plugin.define({
    id = "org.hiby.r1.autoeq",
    name = "AutoEq",
    version = "1.3.5",
    api_min = 2,
})

local SD = plugin.sd_root()
local ROOT = SD .. "/AutoEq"
local INDEX_PATH = ROOT .. "/INDEX.md"
local RANKING_PATH = ROOT .. "/RANKING.md"
local PROFILES_DIR = ROOT .. "/Profiles"
local IMPORTS_DIR = ROOT .. "/Imports"

-- Only plugin.storage is used for AutoEq's selected-config state.
-- This keeps the SD .plugins directory free of AutoEq state files.
local STORAGE_PATH = "current_path"
local STORAGE_NAME = "current_name"
local STORAGE_ENABLED = "enabled"

-- SoundProfiles.lua already owns this file. AutoEq writes "flat" here so the
-- next Sound Profile startup/selection will not replace the AutoEq curve.
local SOUND_PROFILE_STATE = SD .. "/.plugins/.eq_profile_state"

local INDEX_URL = "https://raw.githubusercontent.com/jaakkopasanen/AutoEq/refs/heads/master/results/INDEX.md"
local RANKING_URL = "https://raw.githubusercontent.com/jaakkopasanen/AutoEq/refs/heads/master/results/RANKING.md"
local RAW_BASE = "https://raw.githubusercontent.com/jaakkopasanen/AutoEq/refs/heads/master/results/"

local function ensure_dirs()
    local ok, err = plugin.mkdir(ROOT)
    if not ok then return false, err or "cannot create AutoEq folder" end
    ok, err = plugin.mkdir(PROFILES_DIR)
    if not ok then return false, err or "cannot create Profiles folder" end
    ok, err = plugin.mkdir(IMPORTS_DIR)
    if not ok then return false, err or "cannot create Imports folder" end
    return true
end

local function write_text(path, value)
    local f = io.open(path, "w")
    if not f then return false end
    f:write(value or "")
    f:close()
    return true
end

local function storage_get(key)
    local ok, value = pcall(plugin.storage.get, key, nil)
    if not ok then return nil end
    return value
end

local function storage_set(key, value)
    pcall(plugin.storage.set, key, value or "")
end

local function current_path()
    local p = storage_get(STORAGE_PATH)
    return (p and p ~= "") and p or nil
end

local function current_name()
    local n = storage_get(STORAGE_NAME)
    return (n and n ~= "") and n or nil
end

local function is_enabled()
    return storage_get(STORAGE_ENABLED) == "1"
end

local function persist_current(path, name)
    storage_set(STORAGE_PATH, path or "")
    storage_set(STORAGE_NAME, name or "")
    storage_set(STORAGE_ENABLED, path and name and "1" or "0")
end

local function set_enabled(v)
    storage_set(STORAGE_ENABLED, v and "1" or "0")
end

local function set_sound_profile_flat()
    -- This is the same state file already used by SoundProfiles.lua.
    write_text(SOUND_PROFILE_STATE, "flat")
end

local function url_encode_component(s)
    return (s:gsub("([^%w%-%._~])", function(c)
        return string.format("%%%02X", string.byte(c))
    end))
end

local function slugify(s)
    s = s:lower():gsub("[^%w%-%._]+", "_"):gsub("^_+", ""):gsub("_+$", "")
    return s ~= "" and s or "profile"
end

local function profile_base(entry)
    local variant = entry.name .. "__" .. (entry.source or "source")
    if entry.rig and entry.rig ~= "" then variant = variant .. "__" .. entry.rig end
    local base = slugify(variant)
    if #base > 72 then base = base:sub(1, 72):gsub("_+$", "") end
    local hash = plugin.md5(entry.rel or entry.name) or "00000000"
    hash = hash:gsub("[^%x]", ""):sub(1, 8)
    return base .. "_" .. hash
end

local function http_get_to_file(url, dest, label, done)
    local handle, err = plugin.http_request({
        url = url,
        method = "GET",
        verify_tls = true,
        max_response_bytes = 262144,
        connect_timeout_ms = 10000,
        read_timeout_ms = 15000,
        total_timeout_ms = 30000,
        redirect_limit = 5,
    }, function(status, body, request_error)
        if request_error then
            plugin.show_toast("Download failed: " .. label .. " (" .. tostring(request_error) .. ")", 6000)
            if done then done(false, request_error) end
            return
        end
        if not status or status < 200 or status >= 300 or not body then
            plugin.show_toast("Download failed: HTTP " .. tostring(status or "?") .. " — " .. label, 6000)
            if done then done(false, "HTTP " .. tostring(status or "?")) end
            return
        end

        local f = io.open(dest, "w")
        if not f then
            plugin.show_toast("Cannot write " .. label, 6000)
            if done then done(false, "write failed") end
            return
        end
        f:write(body)
        f:close()

        local verify = io.open(dest, "r")
        if not verify then
            plugin.show_toast("File was not saved: " .. label, 6000)
            if done then done(false, "verify failed") end
            return
        end
        verify:close()

        if done then done(true, dest) end
    end)

    if not handle then
        plugin.show_toast("Download failed to start: " .. label .. " (" .. tostring(err or "unknown") .. ")", 6000)
        return false
    end
    return true
end

local function update_database(done)
    local ok = ensure_dirs()
    if not ok then
        plugin.show_toast("AutoEq storage error", 5000)
        if done then done(false) end
        return
    end

    -- The database can be much larger than a single profile, so use the
    -- streaming file downloader for INDEX/RANKING.
    local pending, failed = 2, false
    local function finished(good)
        if not good then failed = true end
        pending = pending - 1
        if pending == 0 then
            if failed then
                plugin.show_toast("AutoEq database update failed", 5000)
            else
                plugin.show_toast("AutoEq database ready", 3000)
            end
            if done then done(not failed) end
        end
    end

    local function stream(url, dest, label)
        local handle, err = plugin.download_file_async(url, dest, function(path, download_error)
            if download_error then
                plugin.show_toast("Download failed: " .. label .. " (" .. tostring(download_error) .. ")", 6000)
                finished(false)
                return
            end
            local f = io.open(path, "r")
            if not f then
                plugin.show_toast("Downloaded, but " .. label .. " was not saved", 6000)
                finished(false)
                return
            end
            f:close()
            finished(true)
        end)
        if not handle then
            plugin.show_toast("Download failed to start: " .. label .. " (" .. tostring(err or "unknown") .. ")", 6000)
            finished(false)
        end
    end

    stream(INDEX_URL, INDEX_PATH, "AutoEq database")
    stream(RANKING_URL, RANKING_PATH, "AutoEq ranking")
end

local function parse_index_line(line)
    local name, rel, source, rig = line:match("^%-%s+%[([^%]]+)%]%((%./[^%)]+)%)%s+by%s+(.+)%s+on%s+(.+)$")
    if not name then
        name, rel, source = line:match("^%-%s+%[([^%]]+)%]%((%./[^%)]+)%)%s+by%s+(.+)$")
    end
    if not name or not rel then return nil end
    rel = rel:gsub("^%./", "")
    return { name = name, rel = rel, source = source or "?", rig = rig or "" }
end

local function search_index(query)
    local f = io.open(INDEX_PATH, "r")
    if not f then return nil, "database missing" end

    query = query:lower()
    local results, seen = {}, {}
    for line in f:lines() do
        local e = parse_index_line(line)
        if e and e.rel:find("/in%-ear/") and e.name:lower():find(query, 1, true) then
            local key = e.name .. "\n" .. e.rel
            if not seen[key] then
                seen[key] = true
                table.insert(results, e)
                if #results >= 20 then break end
            end
        end
    end
    f:close()
    return results
end

local function autoeq_file_url(entry)
    return RAW_BASE .. entry.rel .. "/" .. url_encode_component(entry.name .. " ParametricEQ.txt")
end

local function parse_autoeq_file(path)
    local f = io.open(path, "r")
    if not f then return nil, "cannot open ParametricEQ.txt" end

    local preamp = 0
    local filters = {}

    for line in f:lines() do
        local p = line:match("^Preamp:%s*([%-%d%.]+)%s*dB")
        if p then preamp = tonumber(p) or 0 end

        local _, state, kind, fc, gain, q = line:match(
            "^Filter%s+(%d+):%s+(%S+)%s+(%S+)%s+Fc%s+([%-%d%.]+)%s+Hz%s+Gain%s+([%-%d%.]+)%s+dB%s+Q%s+([%-%d%.]+)"
        )

        if state == "ON" then
            local typ = kind == "PK" and "peaking"
                    or (kind == "LSC" and "low_shelf")
                    or (kind == "HSC" and "high_shelf")
                    or nil
            if typ then
                table.insert(filters, {
                    fc = tonumber(fc),
                    gain = tonumber(gain),
                    q = tonumber(q),
                    type = typ,
                })
            end
        end
    end

    f:close()
    if #filters == 0 then return nil, "no supported AutoEq filters found" end
    return { preamp = preamp, filters = filters }
end

-- This mirrors SoundProfiles.lua's live-EQ path exactly:
-- reset -> set each band -> set type -> enable/disable -> save a native .peq.
-- AutoEq simply supplies the band values instead of a hand-written profile.
local function apply_parsed_profile(parsed)
    if not parsed then return false end

    plugin.eq_reset()
    plugin.eq_set_preamp(parsed.preamp or 0)
    plugin.eq_set_bypass(false)

    local count = math.min(#parsed.filters, 10)
    for i = 1, count do
        local b = parsed.filters[i]
        if b.fc and b.gain and b.q then
            plugin.eq_set_band(i, b.fc, b.gain, b.q)
            plugin.eq_set_band_type(i, b.type)
            plugin.eq_set_band_enabled(i, true)
        end
    end
    for i = count + 1, 10 do
        plugin.eq_set_band_enabled(i, false)
    end
    return true
end

local function save_and_load_native(path)
    if not plugin.eq_save_profile(path) then
        return false, "could not save native .peq"
    end
    if not plugin.eq_load_profile(path) then
        return false, "could not reload native .peq"
    end
    return true
end

local function activate_saved(path, name, txt_path)
    if not path then
        return false, "no profile path"
    end

    -- AutoEq profiles are cached as both ParametricEQ.txt (source of truth)
    -- and a native .peq. Older AutoEq builds could have produced a flat or
    -- stale .peq, so when the source text is present we rebuild the native
    -- profile from it before loading. This makes every saved config use the
    -- exact same live EQ path as SoundProfiles.lua.
    if txt_path then
        local tf = io.open(txt_path, "r")
        if tf then
            tf:close()
            local parsed, parse_err = parse_autoeq_file(txt_path)
            if parsed then
                apply_parsed_profile(parsed)
                if not plugin.eq_set_bypass then
                    -- Kept for API compatibility; native API always exposes it
                    -- on the firmware this plugin targets.
                end
                plugin.eq_set_bypass(false)
                local saved, save_err = save_and_load_native(path)
                if not saved then
                    return false, save_err
                end
                persist_current(path, name)
                set_enabled(true)
                set_sound_profile_flat()
                return true
            end
            -- If the text exists but is malformed, fall back to the native
            -- cache below so a previously valid profile is still usable.
        end
    end

    local f = io.open(path, "r")
    if not f then
        return false, "saved .peq is missing"
    end
    f:close()

    if not plugin.eq_load_profile(path) then
        return false, "saved .peq could not be loaded"
    end
    -- Never allow a cached profile with bypass=true to make a valid EQ look
    -- like it did nothing. AutoEq profiles are intended to be active.
    plugin.eq_set_bypass(false)

    persist_current(path, name)
    set_enabled(true)
    set_sound_profile_flat()
    return true
end

local open_menu

local function refresh_main_menu()
    -- Do not reopen/nest the settings screen here. A previous implementation
    -- used a repeating timer to reopen AutoEq, which trapped the user on the
    -- AutoEq screen because the timer kept pushing a new screen back on top.
    -- The current config is persisted immediately; when the user backs out and
    -- opens AutoEq again, the row is rebuilt with the new name.
end

local function download_and_apply(entry)
    local ok, err = ensure_dirs()
    if not ok then
        plugin.show_toast("AutoEq storage error: " .. tostring(err), 6000)
        return
    end

    local base = profile_base(entry)
    local peq_path = PROFILES_DIR .. "/" .. base .. ".peq"
    local txt_path = PROFILES_DIR .. "/" .. base .. ".txt"
    local display = entry.name .. " [" .. (entry.source or "?") .. ((entry.rig ~= "") and (" / " .. entry.rig) or "") .. "]"

    -- Cached text is the source of truth. Always rebuild/apply from it when
    -- available instead of trusting an older .peq generated by a previous
    -- plugin version. This is important because old cached .peq files may
    -- have contained a flat/native state even though the UI reported Loaded.
    local existing_txt = io.open(txt_path, "r")
    if existing_txt then
        existing_txt:close()
        local loaded, load_err = activate_saved(peq_path, display, txt_path)
        if loaded then
            plugin.show_toast("Loaded — " .. display, 3500)
            refresh_main_menu()
        else
            plugin.show_toast("Could not load " .. display .. ": " .. tostring(load_err), 6000)
        end
        return
    end

    -- A native cache without its source text is still usable as a fallback.
    local existing = io.open(peq_path, "r")
    if existing then
        existing:close()
        local loaded, load_err = activate_saved(peq_path, display, nil)
        if loaded then
            plugin.show_toast("Loaded — " .. display, 3500)
        else
            plugin.show_toast("Could not load " .. display .. ": " .. tostring(load_err), 6000)
        end
        return
    end

    plugin.show_toast("Downloading " .. display .. "...", 4500)
    http_get_to_file(autoeq_file_url(entry), txt_path, display, function(ok_download, download_err)
        if not ok_download then return end

        local parsed, parse_err = parse_autoeq_file(txt_path)
        if not parsed then
            plugin.show_toast("Downloaded, but profile is invalid: " .. tostring(parse_err), 6000)
            return
        end

        if #parsed.filters > 10 then
            plugin.show_toast("10-band limit: first 10 AutoEq filters used", 3000)
        end

        if not apply_parsed_profile(parsed) then
            plugin.show_toast("Could not apply AutoEq profile", 6000)
            return
        end
        plugin.eq_set_bypass(false)

        -- Save exactly what SoundProfiles saves, then reload the native file.
        local saved, save_err = save_and_load_native(peq_path)
        if not saved then
            plugin.show_toast("EQ applied, but native profile failed: " .. tostring(save_err), 6000)
            return
        end

        persist_current(peq_path, display)
        set_enabled(true)
        set_sound_profile_flat()
        plugin.show_toast("Loaded — " .. display, 3500)
        refresh_main_menu()
    end)
end

local function saved_ui()
    local ok, err = ensure_dirs()
    if not ok then
        plugin.show_toast("AutoEq storage error: " .. tostring(err), 5000)
        return
    end

    local entries = plugin.list_dir(PROFILES_DIR)
    local files = {}
    for _, e in ipairs(entries) do
        if not e.dir and e.name:lower():match("%.peq$") then
            table.insert(files, e.name)
        end
    end
    table.sort(files)

    if #files == 0 then
        plugin.show_toast("No saved AutoEq configs", 3500)
        return
    end

    local selected = current_path()
    local labels = {}
    for i, filename in ipairs(files) do
        local base = filename:gsub("%.peq$", "")
        local label = base:gsub("_", " ")
        if selected == PROFILES_DIR .. "/" .. filename then
            label = "✓ " .. label .. " (Loaded)"
        end
        labels[i] = label
    end

    plugin.show_list("Saved Configs", labels, function(index)
        local filename = files[index]
        if not filename then return end
        local path = PROFILES_DIR .. "/" .. filename
        local base = filename:gsub("%.peq$", "")
        local label = base:gsub("_", " ")
        if selected == path then label = current_name() or label end

        local loaded, load_err = activate_saved(path, label, PROFILES_DIR .. "/" .. base .. ".txt")
        if loaded then
            plugin.show_toast("Loaded — " .. label, 3500)
        else
            plugin.show_toast("Could not load " .. label .. ": " .. tostring(load_err), 6000)
        end
    end)
end

local function remove_saved_ui()
    local ok, err = ensure_dirs()
    if not ok then
        plugin.show_toast("AutoEq storage error: " .. tostring(err), 5000)
        return
    end

    local entries = plugin.list_dir(PROFILES_DIR)
    local files = {}
    for _, e in ipairs(entries) do
        if not e.dir and e.name:lower():match("%.peq$") then
            table.insert(files, e.name)
        end
    end
    table.sort(files)

    if #files == 0 then
        plugin.show_toast("No saved AutoEq configs to remove", 3500)
        return
    end

    local current = current_path()
    local labels = {}
    for i, filename in ipairs(files) do
        local base = filename:gsub("%.peq$", "")
        local label = base:gsub("_", " ")
        if current == PROFILES_DIR .. "/" .. filename then
            label = "✓ " .. label .. " (Current)"
        end
        labels[i] = label
    end

    plugin.show_list("Remove Saved Config", labels, function(index)
        local filename = files[index]
        if not filename then return end

        local path = PROFILES_DIR .. "/" .. filename
        local base = filename:gsub("%.peq$", "")
        local txt = PROFILES_DIR .. "/" .. base .. ".txt"
        local label = base:gsub("_", " ")
        local was_current = (path == current_path())

        local removed_peq = os.remove(path)
        local txt_exists = io.open(txt, "r")
        if txt_exists then
            txt_exists:close()
            os.remove(txt)
        end

        if was_current then
            plugin.eq_reset()
            persist_current(nil, nil)
            set_enabled(false)
            set_sound_profile_flat()
            plugin.show_toast("Removed — " .. label .. " | AutoEq OFF", 4500)
        elseif removed_peq then
            plugin.show_toast("Removed — " .. label, 3500)
        else
            plugin.show_toast("Could not remove — " .. label, 5000)
        end
    end)
end

local function import_ui()
    local ok, err = ensure_dirs()
    if not ok then
        plugin.show_toast("AutoEq storage error: " .. tostring(err), 5000)
        return
    end

    local entries = plugin.list_dir(IMPORTS_DIR)
    local files = {}
    for _, e in ipairs(entries) do
        if not e.dir and e.name:lower():match("%.txt$") then
            table.insert(files, e.name)
        end
    end
    table.sort(files)

    if #files == 0 then
        plugin.show_toast("Put ParametricEQ.txt in SD/AutoEq/Imports", 4500)
        return
    end

    plugin.show_list("Import AutoEq File", files, function(index)
        local filename = files[index]
        if not filename then return end
        local path = IMPORTS_DIR .. "/" .. filename

        local parsed, parse_err = parse_autoeq_file(path)
        if not parsed then
            plugin.show_toast("Import failed: " .. tostring(parse_err), 6000)
            return
        end

        apply_parsed_profile(parsed)
        local native = PROFILES_DIR .. "/" .. slugify(filename:gsub("%.txt$", "")) .. ".peq"
        local saved, save_err = save_and_load_native(native)
        if not saved then
            plugin.show_toast("Applied, but native profile failed: " .. tostring(save_err), 6000)
            return
        end

        local name = filename:gsub("%.txt$", "")
        persist_current(native, name)
        set_enabled(true)
        set_sound_profile_flat()
        plugin.show_toast("Loaded — " .. name, 3500)
        refresh_main_menu()
    end)
end

local function search_ui()
    local f = io.open(INDEX_PATH, "r")
    if not f then
        plugin.show_toast("AutoEq database not found — downloading...", 4000)
        update_database(function(good)
            if good then search_ui() end
        end)
        return
    end
    f:close()

    plugin.show_text_input("Search IEM", "", false, function(query)
        query = query:gsub("^%s+", ""):gsub("%s+$", "")
        if query == "" then
            plugin.show_toast("Enter an IEM name", 2500)
            return
        end

        local results, search_err = search_index(query)
        if not results then
            plugin.show_toast(search_err or "Search failed", 5000)
            return
        end
        if #results == 0 then
            plugin.show_toast("No AutoEq result found", 4000)
            return
        end

        local labels = {}
        for i, e in ipairs(results) do
            labels[i] = e.name .. " [" .. e.source .. ((e.rig ~= "") and (" / " .. e.rig) or "") .. "]"
        end

        -- One list -> direct apply. No nested result/details list.
        plugin.show_list("AutoEq Results", labels, function(index)
            local e = results[index]
            if e then download_and_apply(e) end
        end)
    end)
end

local function current_config_ui()
    local path = current_path()
    local name = current_name()

    if not path or not name then
        plugin.show_toast("Current Config: None", 3000)
        return
    end

    local f = io.open(path, "r")
    if not f then
        plugin.show_toast("Current Config file is missing", 4000)
        return
    end
    f:close()

    local base = path:match("([^/]+)%.peq$") or ""
    local txt = PROFILES_DIR .. "/" .. base .. ".txt"
    local loaded, err = activate_saved(path, name, txt)
    if loaded then
        plugin.show_toast("Loaded — " .. name, 3500)
    else
        plugin.show_toast("Could not load current config: " .. tostring(err), 6000)
    end
end

local function reset_ui()
    plugin.eq_reset()
    persist_current(nil, nil)
    set_enabled(false)
    set_sound_profile_flat()
    plugin.show_toast("Done — AutoEq OFF, Sound Profile set to Flat", 3500)
end

local function about_ui()
    plugin.show_list("AutoEq", {
        "AutoEq precomputed PEQ profiles",
        "Database stays on SD",
        "Selected profiles are cached on SD",
        "The native R1 EQ is driven directly",
        "State is stored in plugin.storage",
        "Up to 10 PEQ filters are applied",
    }, function(_) end)
end

open_menu = function()
    local ok, err = ensure_dirs()
    if not ok then
        plugin.show_toast("AutoEq storage error: " .. tostring(err), 5000)
        return
    end

    local enabled = is_enabled()
    local name = current_name()
    local current_label = name and ("Current Config: " .. name) or "Current Config: None"

    plugin.show_settings_list("AutoEq", {
        {
            type = "toggle",
            label = "AutoEq Enabled",
            value = enabled,
            on_change = function(v)
                if v then
                    local path, n = current_path(), current_name()
                    if path and n then
                        local loaded, load_err = activate_saved(path, n,
                            path:match("([^/]+)%.peq$") and (PROFILES_DIR .. "/" .. path:match("([^/]+)%.peq$"):gsub("%.peq$", ".txt")) or nil)
                        if loaded then
                            plugin.show_toast("AutoEq ON — " .. n, 3500)
                        else
                            set_enabled(false)
                            plugin.show_toast("Could not enable AutoEq: " .. tostring(load_err), 6000)
                        end
                    else
                        set_enabled(true)
                        set_sound_profile_flat()
                        plugin.eq_reset()
                        plugin.show_toast("AutoEq ON — choose an IEM config", 3500)
                    end
                else
                    set_enabled(false)
                    plugin.eq_reset()
                    set_sound_profile_flat()
                    plugin.show_toast("AutoEq OFF — EQ is Flat", 3500)
                end
            end,
        },
        { type = "row", label = current_label, on_select = current_config_ui },
        { type = "row", label = "Find & Apply IEM", on_select = search_ui },
        { type = "row", label = "Saved Configs", on_select = saved_ui },
        { type = "row", label = "Remove Saved Config", on_select = remove_saved_ui },
        { type = "row", label = "Import ParametricEQ.txt", on_select = import_ui },
        { type = "row", label = "Update AutoEq Database", on_select = function() update_database() end },
        { type = "row", label = "Reset to Flat", on_select = reset_ui },
        { type = "row", label = "About", on_select = about_ui },
    })
end

-- Restore the AutoEq curve after SoundProfiles.lua has had a chance to apply
-- its own startup state. No SD AutoEq state files are created.
local function restore_current()
    if not is_enabled() then return end

    local path, name = current_path(), current_name()
    if not path or not name then return end

    local f = io.open(path, "r")
    if not f then
        set_enabled(false)
        return
    end
    f:close()

    local base = path:match("([^/]+)%.peq$")
    local txt = base and (PROFILES_DIR .. "/" .. base .. ".txt") or nil
    if txt then
        local tf = io.open(txt, "r")
        if tf then
            tf:close()
            local parsed = parse_autoeq_file(txt)
            if parsed then
                apply_parsed_profile(parsed)
                set_sound_profile_flat()
                return
            end
        end
    end

    if plugin.eq_load_profile(path) then
        set_sound_profile_flat()
    end
end

ensure_dirs()
restore_current()

local restore_timer
restore_timer = plugin.set_interval(1, function()
    if restore_timer then
        plugin.clear_interval(restore_timer)
        restore_timer = nil
    end
    restore_current()
end)

plugin.register_list_item("playback", "AutoEq", open_menu)
