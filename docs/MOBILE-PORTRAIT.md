# Phone in portrait

Design of the Android interface since 0.7.0: the app is held in portrait, like a city builder on a phone. The Mac does
not change (landscape window, picture in picture, keyboard shortcuts). Code comments refer to the sections below
(for example section 3.3 for the camera).

> Since 0.8.0 the colours and fonts follow the app's design tokens (roman gold, cream or dark fir green, Bricolage
> Grotesque and Figtree, flat and rounded), defined in `godot/ui_kit.gd`. The purple, gold borders, gradient scrim and
> Inter mentioned below describe 0.7.0; sizes, spacing and behaviour are unchanged.

Differences from the design below, found while building it: the Settings switches and radio rows are drawn with style
boxes (the default check boxes were nearly invisible); toasts have a background; the fog density follows the camera
distance in portrait (at 220 units a fixed haze veiled the whole overview); the village sheet lets touches through for
400 ms after a tap opens it (so the second tap of a double tap reaches the map); back notifications are deduplicated
per frame (one gesture used to arrive twice).

Units: in phone mode one interface unit is one Android dp (1/160 inch), see section 3.2. "sp" below means a font size
in those units.

## 1. Why

Before 0.7.0 the phone app was forced into landscape. In a portrait window the old layout scaled every text to about
0.56 of its size, cut the top bar, the floating buttons and the pairing screen, and the camera (18 degree horizontal
field) could never show the whole Empire. Section 2 lists what depended on landscape; section 3 is the design that
replaced it.

## 2. Before 0.7.0: what depended on landscape

| Where | What | Effect in portrait |
|---|---|---|
| `project.godot` | `window/handheld/orientation=4` (sensor landscape), viewport 1280 x 720, stretch `canvas_items` + `expand` | manifest forces landscape |
| `mobile.gd` `preparer()` | `screen_set_orientation(SCREEN_SENSOR_LANDSCAPE)` | forces landscape at runtime |
| `mobile.gd` `_calcul_echelle()` | `dp * 720 / min(w, h)`: assumes the stretch is limited by the height | in portrait the stretch is limited by the width (1280), UI shrinks to 0.56 |
| `mobile.gd` `preparer()` | `label_scale = clamp(echelle, 1, 2)` | 3D labels sized for the landscape FOV |
| `mobile.gd` `_calcul_marges()` | safe area: left and right only (punch hole on a short edge in landscape) | top cutout and bottom ignored |
| `mobile.gd` `_construire_boutons()` | 7 buttons in one row, bottom right, 48 dp, about 560 dp wide | wider than the screen |
| `mobile.gd` `_construire_bandeau()`, `_placer()` | banner bottom left, right edge stops before the buttons | negative width, one letter per line |
| `mobile.gd` `_construire_ecran()` | pairing frame `offset_left/right = -330/+330`; suggestions in an HBox (5 x 80 dp); relay button on one line (about 420 dp) | cut on both sides |
| `mobile.gd` `habiller_menu()` | settings menu 480 dp wide, centered, bottom at -72 | cut on both sides |
| `mobile.gd` `setup()` | minimap offsets `-244 - 64` | bottom left, collides with the buttons |
| `hud.gd` `_ready()` | top bar: title line + resources row with a 220 dp harvest column (about 590 dp) | cut on the right |
| `hud.gd` | village/report/journal `panel` 420 dp anchored right (`-440..-20`), `forum` 400 dp at `-420`, `cockpit` 440 dp min, `senat` 268 dp at `-280`, `actions_row` at `-440` | cut on the left, overlapping |
| `hud.gd` | `log_label` 3 lines at `haut_panneaux` 112; toast at y 90, Cinzel 26 | covers the world in a narrow screen |
| `hud.gd` | `_fermer()` "Close at the bottom right" | wrong once the Close button is gone |
| `minimap.gd` | fixed 230 x 230; view frame drawn as `0.45 * zoom` with landscape ratios 1.4 / 0.8 | wrong footprint in portrait |
| `camera_rig.gd` | `fov = 38` (vertical, KEEP_HEIGHT), pitch 41.35 degrees (`0.66 / 0.75`), zoom 14 to 110, linear pan formula `k = zoom * 2 tan(fov/2) / height` with x1.5 in depth | narrow view, no inertia, no bounds |
| `camera_rig.gd` | double tap = fly to the Forum; tap = physics ray on a 3.6 x 5 x 3.6 box | small targets for a thumb |
| `about.gd` | panel 640 dp wide on phone, texts `custom_minimum_size.x = _largeur - 64` | cut on both sides |
| `settings.gd` | `OptionButton` popups with items under 48 dp, checkbox labels on one line (up to about 400 dp) | cut, small targets |
| `sync_panel.gd` | Mac only (`LARGEUR = 420`), not built in phone mode | no change needed |
| `power.gd` | phone cap = setting 30 or 60, 15 after 20 s without touch, vsync on | no "60 while touching" |
| `ui_kit.gd` | small labels `visibility_range_end = 55` | building labels culled at the portrait framing distance (58) |

## 3. Design

### 3.1 Orientation and window

- `project.godot`: `window/handheld/orientation=5` (sensor portrait). The export writes `screenOrientation=12`
  (USER_PORTRAIT): portrait, or upside down portrait if the user allows it, never landscape on a phone.
- `mobile.gd` `preparer()`: `DisplayServer.screen_set_orientation(DisplayServer.SCREEN_SENSOR_PORTRAIT)` (kept for
  consistency with the manifest; the manifest alone avoids a relayout at launch).
- Keep `screen/immersive_mode=true` (system bars hidden).
- Android 16 ignores orientation requests on large screens (smallest width 600 dp or more) for apps targeting API 36,
  and split screen or picture in picture can give a landscape window. The phone layout below is responsive, so a
  landscape window must still work (not polished, not a goal).

### 3.2 Interface scale, labels and safe area

One unit = one dp in every orientation:

```
dp       = float(AIMPIRE_DENSITE) if set, else clamp(DisplayServer.screen_get_dpi() / 160, 1, 3)
base     = min(window_px.x / 1280.0, window_px.y / 720.0)     # canvas_items + expand
echelle  = clamp(dp / base, 0.5, 6.0)                         # Window.content_scale_factor
```

Check: landscape 2340 x 1080 at 420 dpi gives `2.625 / 1.5 = 1.75` (today's value); portrait 1080 x 2340 gives
`2.625 / 0.84375 = 3.111`, visible 411 x 891 units. `AIMPIRE_ECHELLE` keeps forcing the raw value.

3D labels (`Label3D.fixed_size`) have an on-screen height proportional to `viewport_px.y / tan(vfov / 2)`. To keep the
physical size they had on the landscape phone:

```
vfov        = 38 deg (landscape)  or  2 * atan(tan(HFOV / 2) * h / w) (portrait, see 3.3)
label_scale = clamp(dp * (720 / window_px.y) * tan(vfov / 2) / tan(19 deg), 0.75, 2.5)
```

Landscape phone: same as today (1.75). Portrait emulator: 1.36. Labels are created once, so the value is computed in
`preparer()` from the starting window. `ui_kit.label_range` (new, 55 by default) becomes 95 in portrait so building
labels show at the village framing distance.

Safe area, in units (`k = visible_rect.size.x / window_px.x`, which is `1 / dp`):

```
safe          = DisplayServer.get_display_safe_area()   # screen px; cutout only in immersive mode
inset.top     = safe.position.y * k
inset.left    = safe.position.x * k
inset.right   = (window_px.x - safe.end.x) * k
inset.bottom  = (window_px.y - safe.end.y) * k
```

Zero when not on a phone or when `safe.size` is empty. `AIMPIRE_ZONE_SURE="top,right,bottom,left"` (dp) overrides it
for Mac captures. Margins used by the layout: `T = inset.top + 8` (at least 12), `B = inset.bottom + 16` (keeps the
bottom bar clear of the swipe up zone), `L = inset.left + 12`, `R = inset.right + 12`. Recomputed on `size_changed`.

### 3.3 Camera

Fixed angle, no rotation by the fingers. The pivot (`camera_rig` node) stays on the ground, yaw 45 degrees as today.

| | Mac, and phone in a landscape window | Phone in portrait (`h > w`) |
|---|---|---|
| `Camera3D.keep_aspect` | KEEP_HEIGHT | KEEP_WIDTH |
| `fov` | 38 (vertical) | HFOV = 30 (horizontal) |
| pitch | 41.35 deg, camera at `(0, 0.66 d, 0.75 d)` (unchanged) | 55 deg, camera at `(0, d sin 55, d cos 55)` |
| distance `d` (`zoom`) | 14 to 110, wheel +-3, magnify gesture (unchanged) | D_NEAR = 18 to D_FAR (below) |
| touch gestures | new state machine (pan with inertia, pinch about the fingers) | same |

`zoom` keeps meaning the camera to pivot distance (used by `main.zoom`, captures, `AIMPIRE_ZOOM`). Pitch 55 and HFOV 30
are starting values, to tune on real phones; with them the visible width at the pivot is `W = 2 d tan(15 deg) = 0.536 d`.

Far limit: the whole Empire as it stands fits the width (the "whole base" view of city builders):

```
R_occ  = max(24, max over villages of hypot(v.x, v.z) + 14)     # 14 = parcel walls (13.5) + margin
D_FAR  = clamp(1.08 * R_occ / tan(HFOV / 2), 70, 300)
```

| villages | outer ring | R_occ | D_FAR | one village on screen |
|---|---|---|---|---|
| none yet | Forum only | 24 | 97 | |
| up to 8 | 22 | 36 | 145 | |
| up to 22 | 40 | 54 | 218 | about 100 dp wide |
| up to 42 | 58 | 72 | 290 | |
| more | 76 | 90 | 300 (cap) | edges slightly outside |

Other distances: D_VILLAGE = 58 (a 28 unit parcel fills 90 % of the width), D_BUILDING = 30 (cockpit focus), D_NEAR = 18
(a 3.6 unit building is a third of the width). Launch view in portrait: pivot on the Forum, `d = D_FAR` (this also
renders every material once, so shaders are compiled before the first gesture). `R_occ` and `D_FAR` are updated by
`main._apply_state()`.

At D_FAR the top 12 % of the screen looks past the edge of the ground mesh (340 units square). That band sits under the
top bar and its scrim (3.4); if a capture still shows the void, add one flat outer ground quad in `world.gd` (1 draw call).

#### State machine

```
IDLE --1 finger down--> PRESS
PRESS --moved > 12 dp--> PAN            (anchor at the crossing point: no jump)
PRESS --up < 450 ms, no move--> TAP --> IDLE         (double tap: see below)
PRESS --held > 450 ms--> PRESS (no selection on release; becomes PAN if it moves)
PAN --2nd finger--> PINCH
PAN --up--> GLIDE if |v0| >= 150 dp/s, else SETTLE if out of bounds, else IDLE
PINCH --one finger up--> PAN (re-anchored on the remaining finger)
PINCH --all up--> SETTLE if zoom or position out of bounds, else IDLE
GLIDE --|v| < 10 dp/s--> SETTLE if out of bounds, else IDLE
SETTLE --within 0.5 % of limits--> IDLE
FLY (fly_to: double tap, cockpit, villages list, minimap) --done--> IDLE
any state --finger down--> PRESS (glide, settle and fly stop where they are)
```

The rig is "active" in every state but IDLE; `power.gd` uses it (3.8). Touch events only store finger positions; the
camera is moved once per frame in `_process` from the previous and current positions (both fingers of a pinch move
together, never one event at a time). No allocation per frame.

#### Ground point

```
func ground_point(cam, s):            # s in viewport units, same space as today's _hit_under(event.position)
    o = cam.project_ray_origin(s); n = cam.project_ray_normal(s)
    if n.y > -0.05: return null       # near the horizon: fall back to the linear formula
    return o + n * (-o.y / n.y)
```

#### Pan (one finger) and soft bounds

Each frame, with the current camera: `delta = ground_point(prev) - ground_point(cur)`; `raw += delta` where `raw` is the
unconstrained pivot. The ground under the finger stays under the finger, at any height on the screen.

Displayed pivot from `raw` (rubber band, radial):

```
R_bound = R_occ
O_MAX   = 0.12 * W                       # W = visible width at the pivot, so it scales with the zoom
rubber(o, m) = m * (1 - exp(-o / m))
r = |raw.xz|
pivot = raw                                   if r <= R_bound
pivot = raw.normalized() * (R_bound + rubber(r - R_bound, O_MAX))   otherwise
```

One haptic tick the first time a gesture reaches the bound. On release `raw = pivot`.

#### Inertia

Velocity from the pivot samples of the last 100 ms (`(p_last - p_first) / (t_last - t_first)`, needs at least 16 ms);
0 if the finger rested 50 ms or more before lifting. Thresholds are given on screen and converted with
`k_dp = W / viewport_width_units` (world units per dp at the pivot): minimum fling 150 dp/s, stop below 10 dp/s, cap
6000 dp/s.

```
v     = v * exp(-dt / TAU)     # TAU = 0.325 s: a fling travels v0 * TAU (2000 dp/s glides about 650 dp)
pivot = pivot + v * dt
```

Outside the bound during a glide the outward radial part of `v` decays with a 0.06 s time constant and the position is
shown through the rubber band; when the glide stops, SETTLE takes over.

#### Pinch (two fingers)

Zoom in log space, about the point between the fingers. Per frame, with `s` the spread and `m` the midpoint, previous
frame `(s0, m0)` and current `(s1, m1)`, ignored while `s < 24 dp`:

```
G0     = ground_point(m0)                         # camera before
z_raw += ln(s0 / s1)                              # z = ln d
d      = exp(soft(z_raw))                         # place() the camera
G1     = ground_point(m1)                         # camera after
raw   += G0 - G1                                  # focal point stays under the fingers, midpoint pans
soft(z) = z inside [ln D_NEAR, ln D_FAR], else limit +- rubber(excess, ln 1.15)
```

One haptic tick when a limit is crossed. No zoom inertia. Twisting the fingers does nothing.

#### Settle (back inside the limits)

Critically damped spring, exact step, for the radial overshoot and for `z`:

```
w = 2 * PI / 0.4           # settles in about 0.35 s
e = exp(-w * dt)
x' = (x + (v + w * x) * dt) * e          # x = value - target
v' = (v - w * (v + w * x) * dt) * e
```

#### Fly to

`fly_to(target_pivot, target_d)` replaces the tweens of `main.focus_village`, `main.focus_building` and
`aller_au_forum`: duration `clamp(0.3 + 0.1 * log2(1 + dist / W), 0.3, 0.6)` s, cubic ease in-out, pivot interpolated
linearly, distance in log space, interrupted by any touch. When a peek sheet will cover the bottom of the screen, the
target is shifted so the village sits in the middle of the free area: with the camera placed at the target, take
`y_c = (top_block_bottom + sheet_top) / 2` and `target += target - ground_point((w / 2, y_c))` (one correction step).

#### Tap, double tap, selection

- Tap: candidates are the buildings (their top center, y = 2.5, projected with `cam.unproject_position`) and the Forum
  center. The nearest within 28 dp of the finger is selected (village + building). Otherwise today's physics ray.
  Otherwise the village whose center is within 14 units of the ground point (village selected, no building). Otherwise
  nothing: an open peek sheet closes (deselect). Haptic tick when the selection changes.
- Double tap (`InputEventScreenTouch.double_tap`): village within 16 units of the ground point: fly to it at
  D_VILLAGE and keep it selected (peek sheet). Forum (within 10 units of the center): fly to it at D_VILLAGE, no sheet.
  Elsewhere: fly to the overview (Forum, D_FAR) and clear the selection. The first tap of the pair already selected
  something; the double tap overrides it.
- Mouse and keyboard on the Mac: unchanged (wheel, right or middle drag, arrows, magnify, P, Tab, R, W, J, H, M, Esc).

### 3.4 Portrait HUD

Reference screen 411 x 891 dp (a common phone width). Must also fit 360 x 740 dp. Thumb zone at the
bottom, information at the top.

```
+---------------------------------------------+  y = 0   (inset.top: camera hole)
| scrim: purple 0.85 -> 0 alpha, to T + 112    |
| [W 1.2k] [S 340] [Sc 88] [G 4.1k] [wheat ==] |  top bar   y = T,      h 44, L..R
| Imperator  4/12 active      (! 2 need you)   |  status    y = T + 48, h 48
| (sync banner, wraps, only when needed)       |  banner    y = T + 100
|                                              |
|           world: pan, pinch, tap             |
|                                              |
| [Cockpit] [Villages] [Senate] [Settings]     |  bottom bar h 56, bottom edge at H - B
+---------------------------------------------+
```

- Scrim behind the top block (mouse ignore): legibility over the world and hides the far edge of the ground.
- Top bar: `PanelContainer`, purple 0.88, gold 1 dp border, radius 12, 8 dp padding. Four resource chips (icon 20 dp,
  4 dp gap, number Inter 16 sp, numbers shortened to 4 characters: 999, 1.2k, 12k, 1.2M; full values in the Senate
  sheet), 6 to 10 dp between chips, then wheat icon 20 dp + harvest bar 40 to 56 dp (food 8 dp, winter 4 dp below).
  Width budget: 322 dp at the tightest, fits 360 dp minus margins.
- Status row (transparent, text with outline like `log_label`, 16 sp): `Empire title  active/total active`, ellipsized
  if needed; right side, a gold pill "! N need you" (48 dp hit area, opens Cockpit); a "Discreet" pill when discreet mode
  is on (opens Settings); the update button (`update.gd`) when an update exists.
- Banner (`mobile.bandeau`): below the status row, full width L..R, 16 sp, wraps and grows downward, mouse ignore.
- Toast: on the top layer (it must show over sheets), y = T + 108 (+ banner height), width `W - 48`, Cinzel 22 sp,
  wraps.
- `log_label` hidden in portrait (the journal is in the Cockpit sheet). With "Measure FPS" on, a 14 sp FPS readout
  under the status row.
- Senate column (`hud.senat`), `actions_row`, `goal_dialog`: hidden on the phone (Senate sheet; actions and goals are
  Mac only, as today). Minimap: never on screen in portrait; a reduced copy lives in the Villages sheet.
- Bottom bar: 4 equal buttons, 8 dp apart, L..R, 56 dp tall, radius 14, purple 0.92 with a 1 dp gold border, label
  Inter 16 sp. Pressed: scale 0.97 spring on the first frame (like `about.gd _ressort`) + haptic. Active (its sheet
  open): gold fill, dark text. Badges: Cockpit = attention count (pill 20 dp), Senate = claimable rewards, Settings = dot
  when an update exists. Labels: Cockpit, Villages, Senate, Settings.
- Layers: 1 HUD (top bar, status row, scrim), 2 bottom bar + banner + pairing screen, 3 sheets and their scrim,
  5 toast, 6 About.
- Everything is placed by anchors from T, B, L, R; nothing assumes 411 dp. Text sizes: 16 sp minimum for anything to
  read, 14 sp only for metadata (ages, FPS), sheet titles Cinzel 22 sp. Touch targets 48 dp minimum.
- The phone layout is the same in a landscape window; the bar and sheets are then capped at 560 dp wide and centered.

### 3.5 Bottom sheets (`sheet.gd`)

A sheet is a `Control` on layer 3: full width (max 560 dp, centered), purple 0.97, top corners radius 20, gold 1 dp top
border. Header 56 dp: drag handle 36 x 5 dp centered 8 dp from the top (parchment 0.5 alpha), title Cinzel 22 sp at
20 dp from the left, close button "x" 48 x 48 dp on the right. Body: the hosted content in a `ScrollContainer`
(vertical only, `scroll_deadzone` 8 dp so a tap on a row does not scroll), 20 dp side padding, bottom padding `B`.

Detents:

| Detent | Top edge | Scrim | Map |
|---|---|---|---|
| full | `T + 48` (the resource bar stays visible) | VOILE, tap closes | blocked |
| peek (village only) | `H - clamp(content, 240, 0.45 H)` | none | gestures work above the sheet |
| closed | `H` | | |

Gestures and animation:

- The header drags the sheet 1:1 (downward); above the top detent the motion is damped x0.3.
- Release: downward speed over 700 dp/s or dragged more than 30 % of the sheet height: full goes to peek if the sheet
  has one and it was dragged less than 60 %, else closes; peek closes. Upward speed over 700 dp/s or 25 % up: peek goes
  to full. Otherwise back to the current detent.
- Motion: the critically damped spring of 3.3 with `w = 2 PI / 0.35`, starting with the finger velocity; grabbing the
  header during an animation takes over from the current position (interruptible). Opening slides up from `H` with the
  same spring (about 300 ms). Haptic "gesture end" when a drag settles on a detent.
- Back gesture (`retour()`): About page, then pairing screen, then the open sheet (closes, not to peek), then the
  selection, then "Back again to quit" as today. The header "x" closes too.
- One sheet at a time: opening another replaces it (no stack). About and the pairing screen are pages above sheets.
- Closing started by the user (swipe, x, back, scrim) animates first, then updates the state (`main.selected = ""`,
  etc.). A close caused by the state (another sheet opens, selection changed from the cockpit) is immediate.
- Content dragged from the body only scrolls in 0.7.0 (no hand-off from the scroll to the sheet).
- Text fields (pairing words and link, ERASE): when `DisplayServer.virtual_keyboard_get_height()` is above 0, add that
  height (in units) as bottom padding and `ensure_control_visible()` on the focused field.

State: in phone mode one value, `feuille`, held by `phone_ui.gd`: "", "village", "cockpit", "senate", "villages",
"settings", plus the cockpit tab ("now", "today", "week", "journal"). Setting it keeps `main.selected`,
`main.selected_building`, `main.cockpit_open`, `hud.report_open` and `settings.menu.visible` in sync so `hud.refresh()`
renders the right content. The check runs every frame (cheap string compares) and calls `mobile.rafraichir_hud()` at
once on a change, so a tap opens its sheet within the same frame instead of after the 0.25 s refresh tick.

### 3.6 Panel by panel

| Today | Portrait | Notes |
|---|---|---|
| village panel (`hud.panel`, tap on a building or village) | Village sheet, peek then full | `_panel()` already puts the selected building first: peek shows the village header + the selected building, swipe up for the whole village. Title: village name. |
| cockpit (Tab) | Cockpit sheet, tab Now | Rows wrap on two lines (`autowrap_mode` on the buttons) instead of being cut. A row flies to the building (D_BUILDING) and opens the Village sheet in peek. |
| daily summary (R) and week report (W) | Cockpit sheet, tabs Today and Week | Segmented control of 4 toggle buttons, 48 dp, sticky above the scroll. Reports render into a second `RichTextLabel` (`report_text`) so the village panel and the reports no longer share `panel_text`. No "Close at the bottom right" hint. |
| journal (J) | Cockpit sheet, tab Journal | same `report_text`. |
| Forum panel + Senate orders column | Senate sheet | Treasury (full numbers), festival (Mac only, disabled), orders with Claim (gold filled, the one primary action), monuments with Build. Tapping the Forum in the world opens it too. Buttons 48 dp, text wraps. |
| minimap + Map button | Villages sheet | Reduced minimap at the top (content width x 0.55 high) then the list of villages, 56 dp rows: level color dot, name 16 sp (wraps), activity 14 sp ("3 active", "asleep 4 d"), attention mark. Attention first, then active, then by name. A row or a tap on the minimap closes the sheet and flies to the place (village: D_VILLAGE + peek). |
| settings menu (Esc) + Phone section | Settings sheet | Order: Discreet mode (switch, was a floating button), Smoothness (segmented: Adaptive / Battery saver, see 3.8), Quality (5 radio rows of 48 dp; "Auto" without "100 FPS min."), Renderer (segmented OpenGL / Vulkan + current driver line), Music, Voices, Effects (label above a full width slider), Villagers speak, Detailed voices, Check for updates (+ Update), Phone: chain id and relay (wraps), Measure FPS, Forget this sync chain (two steps), About AImpire. No bottom Close button (the header has one). Every `CheckBox` and `Button` gets `autowrap_mode = AUTOWRAP_WORD_SMART`. |
| About, What leaves your device, privacy, what's new, Erase | page on layer 6, full width | `_largeur = min(640, viewport_w - L - R)`, recomputed at each `open()`; panel margins 16 instead of 22 on the phone; text width from `_largeur`; top at `T`, bottom at `B`; keyboard padding on the Erase page. |
| pairing screen | full screen page | frame anchored to the full rect with L, T, R, B margins; suggestions in an `HFlowContainer`; relay button wraps; Join button 56 dp; keyboard padding. |
| sync chain section (`sync_panel.gd`) | not on the phone | Mac only, unchanged. On the phone the chain is shown in the Settings sheet (Phone section) and created from the Mac. |
| Close, Report, Journal, Discreet, Map buttons | gone | replaced by the bar, the sheets, the "x" and the back gesture |

### 3.7 Haptics (`haptics.gd`)

Through the view, so the system setting is respected and no `VIBRATE` permission is needed (`Input.vibrate_handheld`
would need it, and `tools/check-repo.mjs` fails on any permission not in `docs/permissions.txt`):

```
var rt = Engine.get_singleton("AndroidRuntime")        # only if Engine.has_singleton("AndroidRuntime")
var activity = rt.getActivity()
activity.runOnUiThread(rt.createRunnableFromGodotCallable(func():
    var v = activity.getWindow().getDecorView()
    if not v.performHapticFeedback(constant): v.performHapticFeedback(fallback)))
```

| Function | Constant (fallback) | When |
|---|---|---|
| `press()` | VIRTUAL_KEY 1 | bottom bar, sheet "x", segmented controls |
| `tick()` | CLOCK_TICK 4 | selection changes, pan bound reached, zoom limit crossed |
| `snap()` | GESTURE_END 13 (CLOCK_TICK 4) | sheet settles on a detent after a drag |
| `confirm()` | CONFIRM 16 (VIRTUAL_KEY 1) | "Applied by the Mac" |
| `reject()` | REJECT 17 (LONG_PRESS 0) | command refused, Mac offline, relay error toast |

At most one haptic per 50 ms. No-op on the Mac. Same frame as the visual change. No new UI sounds in 0.7.0.

### 3.8 Frame rate and smoothness

`power.gd` on the phone:

| Situation | `Engine.max_fps` |
|---|---|
| finger down, or rig not IDLE, or a sheet moving, and 1.0 s after | 60 |
| at rest, Smoothness "Adaptive" (default) | 30 |
| Smoothness "Battery saver" | 30, and 15 after 20 s without a touch (today's behavior) |
| app paused (unchanged) | 5 |

- `power.poke()` is called by the rig and the sheets; `_apply()` runs only on a transition, never every frame. The
  switch to 60 happens on touch down, before the first drag frame.
- Vsync stays on (power.gd comment: a sleeping cap without vsync paces badly). On a 120 Hz panel the 60 cap gives two
  vsyncs per frame; if a phone shows uneven pacing, try `max_fps = 0` with vsync during interaction and compare.
- Setting stored under a new key (`fluidite = "adaptive" | "battery"`, default adaptive); the old `fps` key is ignored so
  a saved 30 from 0.6.0 does not lock anyone in battery saver.
- No saccade while pinching: one camera update per frame; no HUD rebuild, minimap redraw or quality change during a
  gesture (`world.adapt()` skipped while the rig is active; the phone default quality is fixed, "performance"); no
  allocation in the gesture code; the launch overview compiles the shaders.
- FPS log (`mobile._journaliser_fps`, every 2 s): add the camera state, p50 and p95 frame time, frames over 25 ms and the
  longest frame of the window, for example
  `FPS 60 cap 60 cam PINCH p50 16.6 p95 17.2 over25 0 max 18.9 draw 130 prim 210000 driver opengl3 win (1080, 2340)`.
- The target is 60 while touching; 120 Hz is reconsidered later (section 5).

### 3.9 The Mac does not change

Every new behavior is gated by `main.mobile != null` (phone mode) and, for the camera parameters, by the window being
taller than wide. On the Mac: same camera constants, wheel, drag, arrows, PiP (960 x 600), keyboard shortcuts, HUD,
settings with the sync column, About at 560 dp. `tests/test_tactile.gd` keeps its desktop assertions (zoom capped at
110 in a 1280 x 720 viewport).

## 4. Verification

### 4.1 Headless tests

```
godot --headless --path godot -s tests/test_camera_portrait.gd
godot --headless --path godot -s tests/test_sheet.gd
godot --headless --path godot -s tests/test_tactile.gd
godot --headless --path godot -s tests/test_mobile.gd
godot --headless --path godot -s tests/test_about.gd
godot --headless --path godot -s tests/test_sync_panel.gd
godot --headless --path godot -s tests/test_sync_crypto.gd
godot --headless --path godot -s tests/test_update.gd
cd daemon && node --test ; cd relay && node --test
node tools/check-repo.mjs
```

`test_camera_portrait.gd` at least: the ground point under the finger moves less than 0.5 units during a pan at the
top and at the bottom of the screen; a fling keeps moving after release, slows down and stops; the pivot never goes
past `R_bound + O_MAX` while dragging and ends within `R_bound` after settle; the point under the pinch midpoint stays
put while zooming; zoom ends within `[D_NEAR, D_FAR]`; `D_FAR` matches the table of 3.3; a tap 20 dp beside a building
selects it, 40 dp beside does not; double tap on a village, the Forum and empty ground; `active` is true during a
gesture and false when IDLE; desktop limits unchanged in a landscape viewport. The camera math is in static functions,
so the viewport size can be passed in rather than resizing a headless window.

`test_sheet.gd`: detent chosen for releases at several offsets and speeds; back closes; spring reaches the target
within 0.5 s at 60 and at 30 FPS.

### 4.2 Mac captures in a portrait window

`tools/capture-portrait.sh <scene> [out dir]`:

- writes `godot/override.cfg` with the window size and deletes it on exit (`trap`), never committed;
- starts `node tools/faux-relais.mjs --port 8787 --etat godot/tests/etat-demo.json` if nothing listens on 8787;
- writes a temporary `chaine.cfg` with the public test vector secret (`000102...0f`, docs/SYNC-VECTEURS.json) and relay
  `http://127.0.0.1:8787/`, passed with `AIMPIRE_CHAINE`;
- runs `AIMPIRE_MOBILE=1 AIMPIRE_DENSITE=... godot --path godot --write-movie <tmp>/f.png --quit-after N` and keeps the
  last frame in `build/captures-portrait/` (ignored by git).

Sizes: 540 x 1170 px with `AIMPIRE_DENSITE=1.3125` (411 x 891 dp, a common phone width), 540 x 1110 px with
`AIMPIRE_DENSITE=1.5` (360 x 740 dp, small phone), and once with `AIMPIRE_ZONE_SURE=48,0,0,0` (punch hole).

Scenes: pairing (no chain); overview at launch; near limit (`AIMPIRE_ZOOM=18`); village peek
(`AIMPIRE_SELECT` + `AIMPIRE_BATIMENT`); village full; Cockpit Now, Today, Week, Journal; Senate; Villages; Settings;
About, What leaves your device, Erase (`AIMPIRE_APROPOS`); banner "Relay unreachable" (chain pointing to a closed
port); toast (`AIMPIRE_TEST_COMMANDE=/reglage?cle=privacy&val=flou`); mid pinch and mid fling (`AIMPIRE_GESTE`).

Pass: `godot/tests/audit_portrait.gd`, run on the same scene, walks the visible `Control` tree and lists any control
whose global rect leaves the viewport minus the insets, any `Label` or `Button` without autowrap whose minimum width is
larger than its width, any touch target under 48 dp and any font under 14 sp; it must list nothing. On the images: no
cut text, nothing under the punch hole, bottom bar clear of the edge, village titles readable and not overlapping on
the overview, no void visible below the top block. A Mac (1280 x 720, not phone mode) capture before and after, with
the same data, must look the same.

### 4.3 On a device or emulator

Build with `AIMPIRE_PUBLIER=0 tools/release-android.sh`, install with `adb install -r build/AImpire.apk`, and pair with
the fake relay (`node tools/faux-relais.mjs --etat godot/tests/etat-demo.json` on the Mac, relay
`http://10.0.2.2:8787/` from the emulator) and the 12 test words of `docs/SYNC-VECTEURS.json`. Check: portrait at
launch and after rotating the device, no cut text, top bar clear of the camera hole (also with the emulator's
"hole" display cutout), gestures (`adb shell input swipe` for pan and fling, two taps in one shell call for a double
tap), every sheet and About page, back gesture, and with "Measure FPS" on, `cap 60` during gestures and `cap 30` about
1 s after. Frame times are only meaningful on a real phone: 10 s of panning and pinching should show p95 at or under
17.5 ms and no frame over 50 ms.

## 5. Open points

- The far limit shows the whole Empire as it stands, since one village alone would hide the Forum and the other
  villages. Framing one village is the double tap.
- Pitch 55 degrees, HFOV 30 degrees, TAU 0.325 s and the spring times are first values, to tune on real phones.
- The status row keeps the day streak; streak counters are to be reconsidered.
- 120 Hz is reconsidered once real phones show frame times under 7 ms.
