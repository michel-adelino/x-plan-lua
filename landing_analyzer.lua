-- ============================================================
--  LANDING ANALYZER  v1.0  |  FlyWithLua for X-Plane 11
--  Showcases : a small state machine, event detection from
--              datarefs, file I/O (CSV log), ImGui window with
--              coloured text, on-screen toast, custom command.
--  Result    : after every landing you get touchdown vertical
--              speed, peak G, pitch, bounce count and a grade.
--              Results are appended to landing_log.csv.
-- ============================================================

-- ---- DataRefs ----
dataref("LA_GND",   "sim/flightmodel/failures/onground_any",       "readonly") -- 1 = any wheel on ground
dataref("LA_VS",    "sim/flightmodel/position/vh_ind_fpm",         "readonly")
dataref("LA_IAS",   "sim/flightmodel/position/indicated_airspeed", "readonly")
dataref("LA_G",     "sim/flightmodel/forces/g_nrml",               "readonly")
dataref("LA_PITCH", "sim/flightmodel/position/theta",              "readonly")

-- ---- Settings ----
local LOG_PATH      = (SCRIPT_DIRECTORY or "") .. "landing_log.csv"
local MIN_AIR_TIME  = 5     -- s airborne before a touchdown counts as a landing
local BOUNCE_WINDOW = 4     -- s after touchdown in which re-contact = bounce
local G_WINDOW      = 2     -- s after touchdown in which peak G is measured
local MAX_HISTORY   = 8

local IMG_COL = { 0xFF60E060, 0xFF30D8FF, 0xFF5050FF }   -- ImGui 0xAABBGGRR
local GL_COL  = { {0.4, 0.9, 0.4}, {1.0, 0.85, 0.2}, {1.0, 0.35, 0.35} }
local COL_CYAN, COL_GREY = 0xFFFFE655, 0xFFB0B0B0

-- ---- State ----
local sim_t        = 0
local initialised  = false
local prev_ground  = true
local air_time     = 0
local last_vs, last_ias, last_pitch = 0, 0, 0
local current      = nil          -- landing currently being measured
local history      = {}           -- newest first
local status_msg   = "Waiting for a landing..."
local log_msg      = "Log file: " .. LOG_PATH
local toast_until  = 0
local total_count, sum_vs, best_vs, worst_vs = 0, 0, nil, nil

-- ---- Helpers ----
local function ctext(color, text)
    if imgui.PushStyleColor and imgui.constant and imgui.constant.Col then
        imgui.PushStyleColor(imgui.constant.Col.Text, color)
        imgui.TextUnformatted(text)
        imgui.PopStyleColor()
    else
        imgui.TextUnformatted(text)
    end
end

local function grade(vs_abs)
    if     vs_abs < 150 then return "EXCELLENT", 1
    elseif vs_abs < 300 then return "GOOD",      1
    elseif vs_abs < 500 then return "FIRM",      2
    elseif vs_abs < 700 then return "HARD",      3
    else                     return "VERY HARD", 3 end
end

local function write_log(rec)
    local probe = io.open(LOG_PATH, "r")
    local need_header = (probe == nil)
    if probe then probe:close() end

    local f = io.open(LOG_PATH, "a")
    if not f then
        log_msg = "Could not write: " .. LOG_PATH
        return
    end
    if need_header then
        f:write("timestamp,vs_fpm,ias_kt,pitch_deg,peak_g,bounces,grade\n")
    end
    f:write(string.format("%s,%.0f,%.1f,%.1f,%.2f,%d,%s\n",
        os.date("%Y-%m-%d %H:%M:%S"), rec.vs, rec.ias, rec.pitch,
        rec.peak_g, rec.bounces, rec.grade))
    f:close()
    log_msg = "Saved to " .. LOG_PATH
end

local function finalize()
    local text, level = grade(math.abs(current.vs))
    current.grade, current.level = text, level

    table.insert(history, 1, current)
    while #history > MAX_HISTORY do table.remove(history) end

    total_count = total_count + 1
    sum_vs = sum_vs + math.abs(current.vs)
    if best_vs  == nil or math.abs(current.vs) < best_vs  then best_vs  = math.abs(current.vs) end
    if worst_vs == nil or math.abs(current.vs) > worst_vs then worst_vs = math.abs(current.vs) end

    write_log(current)
    status_msg  = string.format("Last landing: %s (%+.0f fpm)", text, current.vs)
    toast_until = sim_t + 10
    current = nil
end

-- ---- Per-frame state machine ----
function la_frame()
    local dt = SIM_PERIOD or 0.02
    sim_t = sim_t + dt
    local on_ground = (LA_GND == 1)

    if not initialised then
        prev_ground, initialised = on_ground, true
        return
    end

    if not on_ground then
        air_time = air_time + dt
        last_vs, last_ias, last_pitch = LA_VS, LA_IAS, LA_PITCH   -- last airborne sample
    elseif not prev_ground then                                    -- touchdown event
        if current and (sim_t - current.t0) < BOUNCE_WINDOW then
            current.bounces = current.bounces + 1
        elseif air_time >= MIN_AIR_TIME then
            current = { t0 = sim_t, vs = last_vs, ias = last_ias,
                        pitch = last_pitch, peak_g = LA_G, bounces = 0 }
            status_msg = "Touchdown! Measuring..."
        end
        air_time = 0
    end

    if current then
        local age = sim_t - current.t0
        if age < G_WINDOW and LA_G > current.peak_g then current.peak_g = LA_G end
        if age >= BOUNCE_WINDOW then finalize() end
    end
    prev_ground = on_ground
end
do_every_frame("la_frame()")

-- ---- Toast on screen ----
function la_draw()
    if sim_t >= toast_until or not history[1] then return end
    local r  = history[1]
    local sw = SCREEN_WIDTH or 1280
    local sh = SCREEN_HIGHT or SCREEN_HEIGHT or 720
    local w, h = 380, 60
    local x, y = sw / 2 - w / 2, sh - 110

    XPLMSetGraphicsState(0, 0, 0, 1, 1, 0, 0)
    glColor4f(0, 0, 0, 0.6)
    glRectf(x, y, x + w, y + h)
    local c = GL_COL[r.level]
    glColor4f(c[1], c[2], c[3], 1)
    draw_string_Helvetica_18(x + 14, y + h - 26, "LANDING: " .. r.grade)
    glColor4f(1, 1, 1, 1)
    draw_string_Helvetica_12(x + 14, y + 12,
        string.format("%+.0f fpm   %.2f G   %.0f kt   bounces: %d", r.vs, r.peak_g, r.ias, r.bounces))
end
do_every_draw("la_draw()")

-- ---- ImGui window ----
local function draw_gui()
    ctext(COL_CYAN, "--- LANDING ANALYZER ---")
    ctext(current and IMG_COL[2] or COL_GREY, status_msg)
    imgui.Separator()

    ctext(COL_CYAN, "--- SESSION ---")
    if total_count == 0 then
        imgui.TextUnformatted("No landings recorded yet.")
    else
        imgui.TextUnformatted(string.format("Landings : %d", total_count))
        imgui.TextUnformatted(string.format("Average  : %.0f fpm", sum_vs / total_count))
        imgui.TextUnformatted(string.format("Best     : %.0f fpm", best_vs))
        imgui.TextUnformatted(string.format("Worst    : %.0f fpm", worst_vs))
    end
    imgui.Separator()

    ctext(COL_CYAN, "--- RECENT LANDINGS ---")
    for i, r in ipairs(history) do
        ctext(IMG_COL[r.level], string.format("%d. %-9s %+5.0f fpm  %.2f G  %3.0f kt  pitch %+.1f  bounces %d",
            i, r.grade, r.vs, r.peak_g, r.ias, r.pitch, r.bounces))
    end
    if #history == 0 then ctext(COL_GREY, "(empty)") end
    imgui.Separator()

    if imgui.Button("Clear history", 120, 26) then
        history = {}
        total_count, sum_vs, best_vs, worst_vs = 0, 0, nil, nil
        status_msg = "History cleared."
    end
    ctext(COL_GREY, log_msg)
end

function la_build_gui(wnd, x, y)
    local ok, err = pcall(draw_gui)
    if not ok then
        imgui.TextUnformatted("GUI ERROR:")
        imgui.TextUnformatted(tostring(err))
        logMsg("LandingAnalyzer GUI error: " .. tostring(err))
    end
end

-- ---- Window open / close handling ----
local la_wnd = nil

function la_on_close(wnd) la_wnd = nil end

function la_open()
    if la_wnd then return end
    la_wnd = float_wnd_create(560, 420, 1, true)
    float_wnd_set_title(la_wnd, "Landing Analyzer v1.0")
    float_wnd_set_imgui_builder(la_wnd, "la_build_gui")
    float_wnd_set_position(la_wnd, 150, 150)
    if float_wnd_set_onclose then float_wnd_set_onclose(la_wnd, "la_on_close") end
end

function la_close()
    if la_wnd then float_wnd_destroy(la_wnd); la_wnd = nil end
end

function la_toggle()
    if la_wnd then la_close() else la_open() end
end

create_command("FlyWithLua/landing/toggle_window",
               "Show or hide the Landing Analyzer window",
               "la_toggle()", "", "")
add_macro("Landing Analyzer window", "la_open()", "la_close()", "activate")

logMsg("landing_analyzer v1.0 loaded")

la_open()
