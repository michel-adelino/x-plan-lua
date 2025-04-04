-- ============================================================
--  SMART CHECKLIST  v1.0  |  FlyWithLua for X-Plane 11
--  Showcases : a table-driven design (add an item = add one
--              table entry), live DataRef evaluation, ImGui
--              buttons that call X-Plane commands, custom
--              commands for joystick/keyboard binding.
--  Result    : a checklist whose items tick themselves green
--              when the cockpit state is correct. Items that
--              are wrong get a FIX button where possible.
-- ============================================================

-- ---- DataRefs ----
dataref("CK_BATT",     "sim/cockpit/electrical/battery_on",         "readonly")
dataref("CK_AVIONICS", "sim/cockpit/electrical/avionics_on",        "readonly")
dataref("CK_BEACON",   "sim/cockpit/electrical/beacon_lights_on",   "readonly")
dataref("CK_NAV",      "sim/cockpit/electrical/nav_lights_on",      "readonly")
dataref("CK_STROBE",   "sim/cockpit/electrical/strobe_lights_on",   "readonly")
dataref("CK_LANDING",  "sim/cockpit/electrical/landing_lights_on",  "readonly")
dataref("CK_PBRAKE",   "sim/cockpit2/controls/parking_brake_ratio", "readonly")
dataref("CK_FLAPS",    "sim/cockpit2/controls/flap_ratio",          "readonly")
dataref("CK_GEAR",     "sim/cockpit/switches/gear_handle_status",   "readonly")
dataref("CK_IAS",      "sim/flightmodel/position/indicated_airspeed","readonly")

-- ---- Colours (ImGui 0xAABBGGRR) ----
local COL_CYAN  = 0xFFFFE655
local COL_AMBER = 0xFF30D8FF
local COL_GREEN = 0xFF60E060
local COL_RED   = 0xFF5050FF
local COL_GREY  = 0xFFB0B0B0

local function ctext(color, text)
    if imgui.PushStyleColor and imgui.constant and imgui.constant.Col then
        imgui.PushStyleColor(imgui.constant.Col.Text, color)
        imgui.TextUnformatted(text)
        imgui.PopStyleColor()
    else
        imgui.TextUnformatted(text)
    end
end

local function onoff(v) return (v == 1) and "ON" or "OFF" end

-- ---- The checklist definition (edit here to add items / phases) ----
--   label : text shown        test  : returns true when OK
--   value : current state     fix   : X-Plane command (nil = manual)
local phases = {
    { key = "Prep", title = "Cockpit Preparation", items = {
        { label = "Battery ON",        test = function() return CK_BATT == 1 end,
          value = function() return onoff(CK_BATT) end,       fix = "sim/electrical/battery_1_on" },
        { label = "Avionics ON",       test = function() return CK_AVIONICS == 1 end,
          value = function() return onoff(CK_AVIONICS) end,   fix = "sim/systems/avionics_on" },
        { label = "Beacon ON",         test = function() return CK_BEACON == 1 end,
          value = function() return onoff(CK_BEACON) end,     fix = "sim/lights/beacon_lights_on" },
        { label = "Parking brake SET", test = function() return CK_PBRAKE > 0.5 end,
          value = function() return string.format("%.0f%%", CK_PBRAKE * 100) end, fix = nil },
    }},
    { key = "Takeoff", title = "Before Takeoff", items = {
        { label = "Beacon ON",         test = function() return CK_BEACON == 1 end,
          value = function() return onoff(CK_BEACON) end,     fix = "sim/lights/beacon_lights_on" },
        { label = "Nav lights ON",     test = function() return CK_NAV == 1 end,
          value = function() return onoff(CK_NAV) end,        fix = "sim/lights/nav_lights_on" },
        { label = "Strobes ON",        test = function() return CK_STROBE == 1 end,
          value = function() return onoff(CK_STROBE) end,     fix = "sim/lights/strobe_lights_on" },
        { label = "Landing lights ON", test = function() return CK_LANDING == 1 end,
          value = function() return onoff(CK_LANDING) end,    fix = "sim/lights/landing_lights_on" },
        { label = "Parking brake OFF", test = function() return CK_PBRAKE < 0.1 end,
          value = function() return string.format("%.0f%%", CK_PBRAKE * 100) end, fix = nil },
        { label = "Flaps below 60%",   test = function() return CK_FLAPS < 0.6 end,
          value = function() return string.format("%.0f%%", CK_FLAPS * 100) end, fix = nil },
    }},
    { key = "Landing", title = "Before Landing", items = {
        { label = "Gear DOWN",         test = function() return CK_GEAR == 1 end,
          value = function() return (CK_GEAR == 1) and "DOWN" or "UP" end,
          fix = "sim/flight_controls/landing_gear_down" },
        { label = "Landing lights ON", test = function() return CK_LANDING == 1 end,
          value = function() return onoff(CK_LANDING) end,    fix = "sim/lights/landing_lights_on" },
        { label = "Flaps 30% or more", test = function() return CK_FLAPS >= 0.3 end,
          value = function() return string.format("%.0f%%", CK_FLAPS * 100) end, fix = nil },
        { label = "Speed below 140 kt", test = function() return CK_IAS < 140 end,
          value = function() return string.format("%.0f kt", CK_IAS) end, fix = nil },
    }},
}

local phase_idx = 1

-- ---- Functions used by commands (global) ----
function cl_next_phase()
    phase_idx = phase_idx % #phases + 1
end

-- ---- GUI ----
local function draw_gui()
    -- phase selector
    ctext(COL_CYAN, "--- SELECT PHASE ---")
    for i, ph in ipairs(phases) do
        if imgui.Button(ph.key, 90, 26) then phase_idx = i end
        if i < #phases then imgui.SameLine() end
    end
    imgui.Separator()

    local ph = phases[phase_idx]
    ctext(COL_AMBER, ph.title)

    local done = 0
    for i, it in ipairs(ph.items) do
        local ok = it.test()
        if ok then done = done + 1 end
        ctext(ok and COL_GREEN or COL_RED,
              string.format("%s  %s  :  %s", ok and "[OK]" or "[  ]", it.label, it.value()))
        if not ok then
            if it.fix then
                imgui.SameLine()
                if imgui.Button("Fix##" .. i, 50, 20) then command_once(it.fix) end
            else
                imgui.SameLine()
                ctext(COL_GREY, "(manual)")
            end
        end
    end
    imgui.Separator()

    local total = #ph.items
    local bar = string.rep("#", done) .. string.rep("-", total - done)
    imgui.TextUnformatted(string.format("Progress [%s] %d / %d", bar, done, total))
    if done == total then
        ctext(COL_GREEN, "CHECKLIST COMPLETE")
    else
        ctext(COL_AMBER, string.format("%d item(s) outstanding", total - done))
    end
end

function cl_build_gui(wnd, x, y)
    local ok, err = pcall(draw_gui)
    if not ok then
        imgui.TextUnformatted("GUI ERROR:")
        imgui.TextUnformatted(tostring(err))
        logMsg("SmartChecklist GUI error: " .. tostring(err))
    end
end

-- ---- Window open / close handling ----
local cl_wnd = nil

function cl_on_close(wnd) cl_wnd = nil end

function cl_open()
    if cl_wnd then return end
    cl_wnd = float_wnd_create(440, 360, 1, true)
    float_wnd_set_title(cl_wnd, "Smart Checklist v1.0")
    float_wnd_set_imgui_builder(cl_wnd, "cl_build_gui")
    float_wnd_set_position(cl_wnd, 200, 200)
    if float_wnd_set_onclose then float_wnd_set_onclose(cl_wnd, "cl_on_close") end
end

function cl_close()
    if cl_wnd then float_wnd_destroy(cl_wnd); cl_wnd = nil end
end

function cl_toggle()
    if cl_wnd then cl_close() else cl_open() end
end

create_command("FlyWithLua/checklist/toggle_window",
               "Show or hide the Smart Checklist window",
               "cl_toggle()", "", "")
create_command("FlyWithLua/checklist/next_phase",
               "Switch the Smart Checklist to the next phase",
               "cl_next_phase()", "", "")
add_macro("Smart Checklist window", "cl_open()", "cl_close()", "activate")

cl_open()
logMsg("smart_checklist v1.0 loaded")
