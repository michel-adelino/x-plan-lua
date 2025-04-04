# FlyWithLua Showcase Scripts for X-Plane 11

Three self-contained FlyWithLua scripts that demonstrate different parts of the
FlyWithLua API. They are independent of each other and of the Failure Inducer
project, so any one can be installed or removed on its own.

| Script | What it does | FlyWithLua features shown |
|---|---|---|
| `flight_hud_overlay.lua` | Translucent in-sim HUD with speed, altitude, heading, vertical-speed bar, peak G and a sink-rate warning | OpenGL drawing, `do_every_draw`, `do_every_frame`, signal smoothing, custom commands, macros |
| `landing_analyzer.lua` | Detects every landing and reports touchdown rate, peak G, pitch, bounces and a grade; logs to CSV | State machine, event detection from DataRefs, file I/O, ImGui window, on-screen toast |
| `smart_checklist.lua` | Phase-based checklist that ticks itself from live cockpit state, with FIX buttons | Table-driven design, ImGui buttons, `command_once`, custom commands |

**Requirements:** X-Plane 11 and FlyWithLua NG (2.7.x or newer; ImGui support is required for scripts 2 and 3).
**Tested with:** X-Plane 11.__ / FlyWithLua NG __ (fill in after testing)

---

## Installation

1. Copy the `.lua` files you want into:
   `X-Plane 11/Resources/plugins/FlyWithLua/Scripts/`
2. Start X-Plane, or choose **Plugins -> FlyWithLua -> Reload all Lua script files**.
3. Check **Special -> Show Dev Console** for a line such as
   `flight_hud_overlay v1.0 loaded`. Any error message appears there and in `Log.txt`.

To uninstall, delete the file and reload the scripts.

---

## 1. `flight_hud_overlay.lua`

A heads-up display drawn directly over the sim view, bottom centre of the screen.

**Shows**
- IAS, altitude (MSL), magnetic heading
- Ground speed, height AGL, current G and peak G
- Smoothed vertical speed, as a number and as a bar (full scale is 2000 fpm)
- A flashing **SINK RATE** warning when below 1000 ft AGL descending faster than 1000 fpm

**Controls**
- Command `FlyWithLua/hud/toggle` shows or hides the HUD (bind it in *Settings -> Keyboard / Joystick*)
- Command `FlyWithLua/hud/reset_peak_g` resets the peak-G figure
- Menu entry: *Plugins -> FlyWithLua -> FlyWithLua Macros -> Flight HUD overlay*

**How it works**
Raw vertical speed is noisy, so a per-frame exponential filter (about 0.5 s time
constant) smooths it before display. All drawing happens in a `do_every_draw`
callback using OpenGL rectangles, lines and bitmap text.

**How to test**
1. Load any aircraft and start the engine.
2. The HUD appears immediately. Taxi and check that IAS and heading respond.
3. Take off and climb: the VS bar grows green. Descend: it turns orange.
4. To see the warning, descend below 1000 ft AGL faster than 1000 fpm.
5. Toggle the HUD with the macro menu entry or your bound key.

---

## 2. `landing_analyzer.lua`

Measures every landing and keeps a session history.

**Reported per landing**
- Touchdown vertical speed (fpm), IAS, pitch angle
- Peak G in the first 2 seconds after touchdown
- Bounce count (ground contact lost and regained within 4 s)
- Grade: EXCELLENT (<150 fpm), GOOD (<300), FIRM (<500), HARD (<700), VERY HARD

**Outputs**
- ImGui window with session statistics (count, average, best, worst) and the last 8 landings
- A 10-second on-screen banner after each landing
- `landing_log.csv` next to the script, one line per landing:
  `timestamp, vs_fpm, ias_kt, pitch_deg, peak_g, bounces, grade`

**How it works**
A small state machine watches the `onground_any` DataRef. The last airborne
sample of vertical speed, airspeed and pitch is kept every frame, because the
values at the instant of contact are already disturbed. A touchdown only counts
as a landing after at least 5 seconds in the air, which filters out taxi bumps.
The record is finalised after the bounce window closes, then logged.

**Controls**
- Command `FlyWithLua/landing/toggle_window` shows or hides the window
- Menu entry: *Plugins -> FlyWithLua -> FlyWithLua Macros -> Landing Analyzer window*
- *Clear history* button resets the session statistics (the CSV file is kept)

**How to test**
1. Take off in any aircraft, fly a short circuit (at least 5 seconds airborne), and land.
2. About 4 seconds after touchdown the banner and window entry appear.
3. Open `landing_log.csv` in a spreadsheet to confirm the row was written.
4. Land again with a different descent rate to compare grades.
5. Taxi over a bump or do a very short hop (under 5 s): nothing should be recorded.

---

## 3. `smart_checklist.lua`

A checklist that reads the aircraft state instead of relying on manual ticking.

**Phases**
- **Prep:** battery, avionics, beacon, parking brake set
- **Takeoff:** beacon, nav lights, strobes, landing lights, parking brake off, flaps below 60%
- **Landing:** gear down, landing lights, flaps 30% or more, speed below 140 kt

Each line shows `[OK]` in green or `[  ]` in red together with the current value.
Where a safe X-Plane command exists, a **Fix** button appears and runs it.
Items that cannot be fixed by a command are marked `(manual)`. A progress bar and a
"CHECKLIST COMPLETE" message summarise the phase.

**How it works**
The whole checklist is one Lua table. Each item has a label, a `test()` function,
a `value()` function for display and an optional command name. Adding an item or a
phase means adding one table entry, with no change to the GUI code.

**Controls**
- Phase buttons at the top of the window
- Command `FlyWithLua/checklist/next_phase` cycles through the phases (good for a joystick button)
- Command `FlyWithLua/checklist/toggle_window` shows or hides the window
- Menu entry: *Plugins -> FlyWithLua -> FlyWithLua Macros -> Smart Checklist window*

**How to test**
1. Start with a cold-and-dark aircraft. The **Prep** phase shows red items.
2. Click **Fix** next to *Battery ON* and watch the line turn green.
3. Switch to **Takeoff**, turn on the lights from the cockpit, and see the items tick by themselves.
4. In flight, select **Landing**, lower the gear with the handle, and confirm the gear item turns green.
5. Bind `next_phase` to a key and check that it cycles.

---

## Customising

- **Thresholds** (HUD sink rate, landing grades, bounce window): constants near the top of each script.
- **New checklist items:** copy any item in `smart_checklist.lua` and change its label, DataRef test and command.
- **Different aircraft:** these scripts use only standard `sim/...` DataRefs and commands. Add-on
  aircraft with custom systems may need their own DataRefs (find them with the DataRefEditor plugin).

## Troubleshooting

| Symptom | Likely cause |
|---|---|
| Nothing appears and no "loaded" message | FlyWithLua is not installed in `Resources/plugins/`, or the script is not in `Scripts/` |
| Window is blank, or shows `GUI ERROR:` | FlyWithLua older than NG 2.7 (no ImGui), or an unsupported function; the error text names the line |
| A `Fix` button has no effect | The add-on aircraft overrides that system; use the cockpit switch |
| `landing_log.csv` missing | X-Plane has no write permission on the Scripts folder; the window shows the path it tried |
| HUD too small or too large | Change `w, h` near the top of `fhud_draw()` |
