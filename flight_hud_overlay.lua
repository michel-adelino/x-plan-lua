-- ============================================================
--  FLIGHT HUD OVERLAY  v1.0  |  FlyWithLua for X-Plane 11
--  Showcases : OpenGL drawing (do_every_draw), per-frame signal
--              smoothing (do_every_frame), custom commands,
--              plugin-menu macros.
--  Result    : a translucent HUD at the bottom of the screen with
--              IAS / ALT / HDG, a smoothed vertical-speed bar,
--              peak-G tracking and a flashing SINK RATE warning.
-- ============================================================

-- ---- DataRefs (read-only) ----
dataref("FH_IAS",  "sim/flightmodel/position/indicated_airspeed", "readonly") -- knots
dataref("FH_ELEV", "sim/flightmodel/position/elevation",          "readonly") -- metres MSL
dataref("FH_AGL",  "sim/flightmodel/position/y_agl",              "readonly") -- metres AGL
dataref("FH_VS",   "sim/flightmodel/position/vh_ind_fpm",         "readonly") -- feet/min
dataref("FH_HDG",  "sim/flightmodel/position/mag_psi",            "readonly") -- degrees
dataref("FH_G",    "sim/flightmodel/forces/g_nrml",               "readonly") -- G
dataref("FH_GS",   "sim/flightmodel/position/groundspeed",        "readonly") -- m/s

-- ---- State ----
fhud_on = true
local vs_smooth = 0
local g_peak    = 1.0

-- ---- Helpers ----
local function clamp(v, lo, hi)
    if v < lo then return lo end
    if v > hi then return hi end
    return v
end

-- Filled rectangle that is safe for any corner order
local function fill(r, g, b, a, x1, y1, x2, y2)
    glColor4f(r, g, b, a)
    glRectf(math.min(x1, x2), math.min(y1, y2), math.max(x1, x2), math.max(y1, y2))
end

-- ---- Functions used by commands / macros (must be global) ----
function fhud_set(state)  fhud_on = state end
function fhud_toggle()    fhud_on = not fhud_on end
function fhud_reset_peak() g_peak = FH_G end

-- ---- Per-frame update: exponential smoothing of vertical speed ----
function fhud_update()
    local dt = SIM_PERIOD or 0.02
    local k  = 1 - math.exp(-dt / 0.5)          -- ~0.5 s time constant
    vs_smooth = vs_smooth + (FH_VS - vs_smooth) * k
    if FH_G > g_peak then g_peak = FH_G end
end
do_every_frame("fhud_update()")

-- ---- Drawing ----
function fhud_draw()
    if not fhud_on then return end
    XPLMSetGraphicsState(0, 0, 0, 1, 1, 0, 0)

    local sw   = SCREEN_WIDTH or 1280
    local w, h = 420, 120
    local x    = sw / 2 - w / 2
    local y    = 20

    local alt_ft = FH_ELEV * 3.28084
    local agl_ft = FH_AGL  * 3.28084
    local gs_kt  = FH_GS   * 1.94384

    -- panel + border
    fill(0, 0, 0, 0.55, x, y, x + w, y + h)
    glColor4f(0.35, 0.9, 1.0, 0.9)
    glBegin_LINES()
    glVertex2f(x,     y);     glVertex2f(x + w, y)
    glVertex2f(x + w, y);     glVertex2f(x + w, y + h)
    glVertex2f(x + w, y + h); glVertex2f(x,     y + h)
    glVertex2f(x,     y + h); glVertex2f(x,     y)
    glEnd()

    -- primary readouts
    glColor4f(1, 1, 1, 1)
    draw_string_Helvetica_18(x + 14, y + h - 30, string.format("IAS %3.0f kt",  FH_IAS))
    draw_string_Helvetica_18(x + 14, y + h - 58, string.format("ALT %5.0f ft",  alt_ft))
    draw_string_Helvetica_18(x + 14, y + h - 86, string.format("HDG %03.0f",    FH_HDG))

    -- secondary readouts
    glColor4f(0.8, 0.8, 0.8, 1)
    draw_string_Helvetica_12(x + 210, y + h - 28, string.format("GS  %3.0f kt",  gs_kt))
    draw_string_Helvetica_12(x + 210, y + h - 50, string.format("AGL %5.0f ft",  agl_ft))
    draw_string_Helvetica_12(x + 210, y + h - 72, string.format("G   %4.2f  (peak %4.2f)", FH_G, g_peak))
    draw_string_Helvetica_12(x + 210, y + h - 94, string.format("VS  %+5.0f fpm", vs_smooth))

    -- vertical-speed bar (+/- 2000 fpm full scale)
    local bx     = x + w - 36
    local cy     = y + h / 2
    local maxlen = h / 2 - 12
    local len    = clamp(vs_smooth / 2000, -1, 1) * maxlen
    fill(1, 1, 1, 0.12, bx, y + 12, bx + 14, y + h - 12)               -- track
    if vs_smooth >= 0 then
        fill(0.3, 0.9, 0.4, 0.9, bx, cy, bx + 14, cy + len)           -- climbing
    else
        fill(1.0, 0.6, 0.2, 0.9, bx, cy, bx + 14, cy + len)           -- descending
    end
    glColor4f(1, 1, 1, 0.9)
    glBegin_LINES()
    glVertex2f(bx - 4, cy); glVertex2f(bx + 18, cy)                    -- zero line
    glEnd()
    glColor4f(1, 1, 1, 1)
    draw_string_Helvetica_10(bx + 1, y + 2, "VS")

    -- flashing sink-rate warning
    if agl_ft > 50 and agl_ft < 1000 and vs_smooth < -1000 then
        if math.floor(os.clock() * 3) % 2 == 0 then
            glColor4f(1, 0.2, 0.2, 1)
            draw_string_Helvetica_18(x + w / 2 - 45, y + h + 12, "SINK RATE")
        end
    end
end
do_every_draw("fhud_draw()")

-- ---- Custom commands (bindable to keys / joystick buttons) ----
create_command("FlyWithLua/hud/toggle",
               "Show or hide the flight HUD overlay",
               "fhud_toggle()", "", "")
create_command("FlyWithLua/hud/reset_peak_g",
               "Reset the HUD peak-G value",
               "fhud_reset_peak()", "", "")

-- ---- Entry in Plugins > FlyWithLua > FlyWithLua Macros ----
add_macro("Flight HUD overlay", "fhud_set(true)", "fhud_set(false)", "activate")

logMsg("flight_hud_overlay v1.0 loaded")
