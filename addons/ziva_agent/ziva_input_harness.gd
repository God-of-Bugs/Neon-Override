extends Node

# Injected-input harness for the run_scene tool, registered as the
# "ZivaPlaytestIO" autoload before the embed plays. It runs INSIDE the live
# game, so get_tree().get_root() is the real game viewport (autoload/root
# CanvasLayers included) and Input.parse_input_event is the same channel a
# player's hardware feeds.
#
# Every parameter arrives through the sidecar JSON the tool writes - nothing is
# substituted into this file - so the tool and the QA session drive one tested
# implementation, and this file ships as a normal addon asset.
#
# It runs in one of two modes, chosen by which sidecar the tool left behind:
#
# - batch (run_scene): replay the timed `inputs`, record what each press/release
#   edge actually cost in frames and ms, capture the root texture onto
#   results_path and reply "ziva_pt:captured" through the debugger.
# - session (QA session): dial plugin-server's socket and serve
#   act/observe/watch/drive/stop ops turn by turn, holding the tree paused
#   between them so the world cannot move while the caller is deciding. Probe
#   expressions come entirely from the caller; nothing here knows anything about
#   the game being played.

const PARAMS_PATH := "res://.godot/ziva_playtest_inputs.json"
const SESSION_PATH := "res://.godot/ziva_qa_session.json"

# A press released in the same frame it was issued is invisible to
# Input.is_action_pressed / is_physical_key_pressed pollers, which sample once
# per frame: a 0ms hold delivers zero observed frames. Every press is therefore
# held at least this many PHYSICS frames and the clamp is reported. Physics
# frames, not render frames: game logic polls input on the fixed physics tick,
# while render frames run as fast as the machine draws - measured 165fps against
# a 60Hz tick, where a 2-render-frame tap spans 0-1 ticks and simply vanishes
# from the game's point of view while the delivery record says it landed.
const MIN_HOLD_FRAMES := 2

# Full process+draw cycles between the last input and the read, so autoload
# CanvasLayer HUDs, the post-input scene state, and layout are in the frame.
const SETTLE_FRAMES := 5

# Anthropic rejects images whose longest edge pushes the request past its
# 5MB-per-image limit; mirrors clamp_image_longest_edge in gdext/src/common.h so
# an oversized viewport does not bill a 4K PNG per observation.
const MAX_FRAME_EDGE := 1568

# Process frames a capture waits for a drawn frame before giving up. At 60fps
# this is ~1s: long enough for any window that is drawing at all, short enough
# that a window that is not costs one op instead of the session's 120s deadline.
const CAPTURE_DRAW_TIMEOUT_FRAMES := 60

# Nodes the purity digest walks before it stops. A bound, not a target: the digest
# runs twice per probe, and a scene big enough to exceed this is one where a
# partial digest still catches anything a probe does to the nodes it reached.
const DIGEST_NODE_LIMIT := 4000
# How far the aim ray reaches, and how many Controls the UI census will count
# before it stops. Both bound the per-act cost of measuring the world.
const AIM_RAY_LENGTH := 50.0
const UI_CENSUS_LIMIT := 400

# Hard stop on an `until` wait, in wall-clock time rather than frames. The session
# gives an op 120s (OP_TIMEOUT_MS in qa-session/service.ts); an op that outruns
# that leaves this harness serving a request nobody is waiting for, which stalls
# every op behind it. This is that ceiling with room for the reply to land.
const UNTIL_WALL_CLOCK_BUDGET_MS := 90_000

# Render-FPS ceiling while the tree is frozen between ops. A paused game still
# draws, and with vsync off it draws as fast as the machine allows - measured
# ~165fps, 31k frames rendered during one 191s stall, all of them identical.
# Ten per second keeps the socket served and the window alive at ~6% of the
# cost; _thaw() restores the game's own cap before any act runs.
const PAUSED_RENDER_FPS_CAP := 10

# A probe can evaluate to the whole world: one real run returned a 248,127-char
# value, and everything a probe returns crosses the socket into model context.
# The prefix keeps enough to be useful; the marker carries the full length and a
# hash of the full text, so a change past the cap still reads as a change.
const PROBE_VALUE_MAX_CHARS := 4096

# Physics frames a servo pulse tolerates the probed value not moving at all
# before it stops blaming timing and names the real cause: this input does not
# drive that probe. Two seconds at a 20Hz tick - a mechanic that ramps from
# zero still shows SOME movement well inside that.
const SERVO_STALL_FRAMES := 40

# Watched-signal events buffered between op replies. A signal wired to a
# per-frame emitter would otherwise grow without bound; past the cap the count
# of dropped events rides the reply instead, so the overflow is loud.
const MAX_PENDING_EVENTS := 100

# Foreign-input labels an act carries back. The count is the measurement; these
# only have to say WHAT arrived, and a key somebody leant on repeats forever.
const MAX_FOREIGN_LABELS := 8

# A game_drive body longer than this is not one maneuver, and every byte of it
# is model output that crossed the socket. Split it.
const DRIVE_SOURCE_MAX_CHARS := 8000

# ---------------------------------------------------------------- recording
#
# One JPEG per CAPTURE_EVERY_PHYSICS physics frames while the game is actually
# running, with the agent's stated goal and the input the game really received
# drawn into the frame. Off unless the session sidecar carries `record`.

# PHYSICS frames between captures, not a frame rate: two ticks is 30fps of game
# time in a 60Hz game and 10fps in a 20Hz one, and in both cases the video plays
# back at real speed with no timestamp math. Anything reading this back has to
# derive the rate from the project's physics rate, not assume 60.
const CAPTURE_EVERY_PHYSICS := 2

# Measured on a real GPU: 2.9ms average to read the viewport back and 15.0ms to
# encode at this quality, so the encode dominates. That cost lands on drawn
# frames (159fps -> 129fps) and NOT on game time - physics measured 59.08Hz
# while recording against 59.05Hz while not.
const RECORD_JPEG_QUALITY := 0.75

# Frames on disk before the stride DOUBLES and every second frame already
# written is deleted. p90 of a real run is 498s of live play - about 15k frames
# - so a recorder that simply stopped at the cap would bite one run in five and
# lose the END, which is where the verdict is decided. Overridable per session
# by the `record_max_frames` sidecar key.
const MAX_FRAMES := 9000

# The overlay's geometry is fixed VIEWPORT pixels rather than scaled to the
# game. A recorded frame keeps the viewport's own resolution - MAX_FRAME_EDGE
# exists because an observation crosses a socket, and these go straight to disk
# - so a canvas coordinate here is a pixel coordinate in the file, which is what
# lets the e2e gate probe the caption panel and the REC badge by coordinate.
const OVERLAY_LAYER := 128
const OVERLAY_PAD := 24.0
const CAPTION_HEIGHT := 132.0
const CHIP_HEIGHT := 34.0
const CAPTION_FONT_SIZE := 28
# The floor the caption is allowed to shrink to before it is ellipsized instead.
const CAPTION_FONT_MIN := 16
const CHIP_FONT_SIZE := 22
# Opaque, not translucent: the gate reads these colours back out of a lossy
# JPEG, and a panel blended over the game is a different colour in every frame.
const PANEL_COLOR := Color(0.05, 0.06, 0.09)
# The caption floats OVER the game, so it is translucent - the look the minigolf
# spike had before the gate's pixel probes forced an opaque band.
const CAPTION_PANEL_COLOR := Color(0.05, 0.06, 0.09, 0.72)
const CHIP_PANEL_COLOR := Color(0.06, 0.07, 0.10, 0.82)
const CAPTION_SUB_FONT_SIZE := 20
const CHIP_ROW_GAP := 62.0
# Where the gate reads, and nowhere else.
const SENTINEL_X := 24.0
const SENTINEL_Y := 46.0
const SENTINEL_W := 60.0
const SENTINEL_H := 6.0
# Under the overlay, above the game.
const SEAT_LAYER := 1
const HARNESS_GROUP := "ziva_input_harness"
const BARE_MODIFIERS := ["Alt", "Ctrl", "Shift", "Meta", "Command", "Option", "Super"]
const REC_COLOR := Color(0.86, 0.13, 0.15)
const CHIP_COLOR := Color(0.16, 0.55, 0.36)
const CURSOR_COLOR := Color(1.0, 0.95, 0.4)
const TRAIL_COLOR := Color(1.0, 0.85, 0.2, 0.55)
const RIPPLE_MS := 450
const TRAIL_POINTS := 40
const MOUSE_LABELS := {
	MOUSE_BUTTON_LEFT: "LMB", MOUSE_BUTTON_RIGHT: "RMB", MOUSE_BUTTON_MIDDLE: "MMB"
}

# Inputs left pressed across acts by `sustain`, label -> the entry that pressed
# them, so the release edge is dispatched through exactly the same channel.
var _sustained: Dictionary = {}
# Inputs auto-held for the duration of an in-flight `until` wait, label -> entry.
# Always emptied before the act returns; only `sustain` outlives an act.
var _wait_held: Dictionary = {}
# Signal taps armed by game_watch, "node_path:signal" -> true. Recorders stay
# connected for the session's life; the session ends with the process.
var _watches: Dictionary = {}
# Events those taps recorded since the last op reply drained them.
var _events: Array = []
var _events_dropped := 0
# The game's own Engine.max_fps, captured at the first freeze so _thaw() can
# restore it. -1 = not captured yet (max_fps itself is never negative).
var _running_max_fps: int = -1
var _params: Dictionary = {}
var _entries: Array = []
var _start_ms: int = 0
var _start_frame: int = 0
# target -> Control, for the click-to-focus + text readback below.
var _typed_targets: Dictionary = {}

var _ws: WebSocketPeer = null
var _greeted := false
# Ops are strictly one at a time: each one is a coroutine spanning many frames,
# and a second op entering mid-flight would interleave two games' worth of input.
var _serving := false
# Set the moment a probe is caught writing to the game. A side effect cannot be
# undone, so the run is poisoned from that point on and no verdict drawn from it
# is worth anything: every later op refuses, and stop reports it.
var _tainted := ""
# Non-zero while this harness is inside its own parse_input_event/flush pair.
# Both dispatch synchronously, so the window is exact: whatever _input() sees
# with this at zero, nobody in this session sent.
var _injecting := 0
# Foreign edges seen since the act in flight thawed the tree, and what they
# were. Reset by _op_act, so a stray press between ops is never billed to an act.
var _foreign_in_act := 0
var _foreign_labels: Array = []

# Empty unless this session was told to record; every recorder path is gated on
# it, so a session without the sidecar keys behaves exactly as it always did.
var _record_dir := ""
var _record_max_frames := MAX_FRAMES
var _record_stride := CAPTURE_EVERY_PHYSICS
# The next frame_%06d index to write. Names are never reused, so decimation can
# delete from the middle without renumbering anything the encoder will read.
var _record_next := 0
var _record_kept := PackedInt32Array()
# Milliseconds the game was actually RUNNING. This, not wall clock, is what the
# encoder turns into a frame rate: a session spends most of its life frozen
# while the agent thinks, and none of that is in the video.
var _record_live_ms := 0.0
var _record_last_physics := -1
var _record_error := ""
var _capturing := false
var _capture_waited := 0
var _overlay: CanvasLayer = null
var _overlay_draw: Node2D = null
# The agent's stated goal for the op in flight - the caption's top line. The
# line under it is derived from _held, which is what the game actually got, so
# the two can disagree on screen. That disagreement is the whole point.
var _intent := ""
var _held: Dictionary = {}
var _caption_fit: Dictionary = {}
var _seat: SubViewport = null
var _seat_requested := false
var _seated_scene: Node = null
var _session_goal := ""
var _sig_cursor := Vector2i(-9999, -9999)
var _sig_held := -1
var _sig_intent := -1
var _sig_ripples := -1
var _sig_frozen := false
var _trail: Array = []
var _ripples: Array = []


func _ready() -> void:
	# Owning the "ziva_pt" capture reserves the channel and mirrors the editor-side
	# EditorDebuggerPlugin; the actual capture below is self-driven.
	if EngineDebugger.is_active() and not EngineDebugger.has_capture("ziva_pt"):
		EngineDebugger.register_message_capture("ziva_pt", _on_capture)
	if FileAccess.file_exists(SESSION_PATH):
		# Two autoloads pointing at this script means two harnesses dialling one
		# session. The second socket is refused with a 409 and the game then quits
		# - silent, baffling, and it cost a spike an hour. A duplicate now stands
		# down loudly and lets the first one work.
		if get_tree().get_nodes_in_group(HARNESS_GROUP).size() > 0:
			printerr(
				"ziva_input_harness: this script is registered as MORE THAN ONE autoload in "
				+ "project.godot. Only the first will drive the session; remove the duplicate "
				+ "entry (both point at res://addons/ziva_agent/ziva_input_harness.gd)."
			)
			return
		add_to_group(HARNESS_GROUP)
		_start_session()
		return
	_params = _load_params()
	if _params.is_empty():
		return
	# Marker the editor polls: it separates "the game never booted this far" (a
	# startup failure, e.g. a script that fails to instantiate) from "the game is
	# running but never rendered a frame". Without it both look identical. (#1129)
	var marker := FileAccess.open(String(_params["started_path"]), FileAccess.WRITE)
	if marker != null:
		marker.store_string("1")
		marker.close()
	_run.call_deferred()


func _on_capture(_message: String, _data: Array) -> bool:
	return true


# The sidecar is written by the tool immediately before the run. Anything wrong
# with it is a bug in that writer, never a state to paper over: say so and stop,
# so the tool's timeout message and this line name the same failure.
func _read_sidecar(path: String, required: Array) -> Dictionary:
	if not FileAccess.file_exists(path):
		printerr("ziva_input_harness: no parameter sidecar at " + path)
		return {}
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		printerr("ziva_input_harness: could not open " + path)
		return {}
	var text := f.get_as_text()
	f.close()
	var parsed: Variant = JSON.parse_string(text)
	if not (parsed is Dictionary):
		printerr("ziva_input_harness: parameter sidecar was not a JSON object: " + text)
		return {}
	for key in required:
		if not (parsed as Dictionary).has(key):
			printerr("ziva_input_harness: parameter sidecar is missing '" + String(key) + "': " + text)
			return {}
	return parsed


func _load_params() -> Dictionary:
	return _read_sidecar(
		PARAMS_PATH,
		["results_path", "results_tmp", "report_path", "started_path", "duration_ms", "inputs"]
	)


# ---------------------------------------------------------------- injection

# Every edge this harness sends leaves through here, flagged. parse_input_event
# and flush_buffered_events both dispatch synchronously, so _input() below runs
# inside this call for the harness's own events and outside it for everyone
# else's - which is the whole discrimination the detector rests on.
func _inject(event: InputEvent) -> void:
	_injecting += 1
	if _seat != null:
		# BOTH paths, deliberately. push_input reaches the game's own nodes and the
		# SubViewport's private cursor - which is what answers a game polling
		# get_viewport().get_mouse_position(), and therefore what lets warp_mouse
		# go. parse_input_event reaches nothing inside the seat (a bare
		# SubViewport gets no input from the root) but it DOES set the global
		# Input singleton, which is the only thing a game polling
		# Input.is_physical_key_pressed can see. Neither path alone covers both
		# kinds of game; together they cover every archetype measured.
		Input.parse_input_event(event)
		Input.flush_buffered_events()
		# The virtual seat: the game lives in a bare SubViewport, which receives
		# only what is pushed into it. Nothing from the real keyboard or pointer
		# can arrive, and the SubViewport keeps its OWN mouse position - so a game
		# polling get_viewport().get_mouse_position() is answered without ever
		# calling warp_mouse on the machine the user is sitting at.
		_seat.push_input(event)
	else:
		Input.parse_input_event(event)
		Input.flush_buffered_events()
	_injecting -= 1


## Move the running game into a SubViewport nothing but this session can reach.
##
## OFF by default, and it must stay that way until the caller knows which kind of
## game it is driving. A SubViewport delivers pushed events to its own nodes'
## _input/_unhandled_input and answers get_viewport().get_mouse_position() from
## its own pointer - so an event-driven game, or one that polls the VIEWPORT
## cursor, is fully seated: measured, real xdotool keys and clicks reached the
## window and the game saw none of them, while pushed input landed and the cursor
## never moved on the host.
##
## It does NOT reach a game that polls the global Input singleton
## (`Input.is_physical_key_pressed`, `Input.is_mouse_button_pressed`). That state
## is fed by real devices only, so such a game ignores pushed keys entirely -
## measured on Godotcraft, whose player reads KEY_W that way and did not take a
## step while seated. Those games need display isolation instead; the seat can
## neither drive them nor protect them.
## Done here rather than by the launcher so the seat needs no wrapper scene, no
## gdext change and no new launch path: the scene is already loaded and running,
## and it simply changes parent.
## The node the game's own scripts live under. Once seated, the scene is nested
## inside a SubViewport and SceneTree.current_scene no longer points at it, so
## every probe, screenshot and scene-name lookup asks here instead.
func _game_scene() -> Node:
	if _seated_scene != null and is_instance_valid(_seated_scene):
		return _seated_scene
	return get_tree().current_scene


func _take_seat() -> bool:
	var scene: Node = get_tree().current_scene
	if scene == null:
		printerr("ziva_input_harness: no current scene to seat")
		return false
	var root := get_tree().get_root()
	var seat := SubViewport.new()
	seat.size = Vector2i(root.get_visible_rect().size)
	seat.handle_input_locally = true
	seat.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	# The game keeps rendering while the tree is paused, exactly as it did in the
	# root viewport - the freeze/thaw contract and the recorder both rely on it.
	seat.process_mode = Node.PROCESS_MODE_INHERIT
	var view := TextureRect.new()
	view.set_anchors_preset(Control.PRESET_FULL_RECT)
	view.mouse_filter = Control.MOUSE_FILTER_IGNORE
	view.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	view.stretch_mode = TextureRect.STRETCH_SCALE
	var holder := CanvasLayer.new()
	holder.layer = SEAT_LAYER
	holder.add_child(view)
	root.add_child(seat)
	root.add_child(holder)
	root.remove_child(scene)
	seat.add_child(scene)
	# SceneTree.current_scene will not follow a node into a SubViewport, so the
	# harness remembers the game root itself and _game_scene() answers for it.
	_seated_scene = scene
	view.texture = seat.get_texture()
	_seat = seat
	return true


# Input nobody in this session sent: a hand on the real keyboard, a click into
# the game's window while it is under test. It is not a defect in the game, but
# it reads exactly like one - a run that reports "jump did nothing" because
# somebody else's Escape opened a menu blames the game for a person.
#
# Bare mouse MOTION is deliberately NOT foreign. _move_mouse warps the real
# cursor (the only way a game that polls the cursor mid-drag sees a gesture at
# all) and the OS emits its own motion event for that warp asynchronously,
# outside the flag above - so counting motion makes every drag self-report as
# contamination. Keys, mouse buttons and actions have no such echo.
func _input(event: InputEvent) -> void:
	# Deliberately BEFORE the injection gate: the overlay's second caption line
	# is what the game received, whoever sent it.
	if not _record_dir.is_empty():
		_note_overlay_event(event)
	if _injecting > 0:
		return
	var what := ""
	if event is InputEventKey:
		var key: InputEventKey = event
		what = "key %s %s" % [OS.get_keycode_string(key.keycode), "down" if key.pressed else "up"]
	elif event is InputEventMouseButton:
		var button: InputEventMouseButton = event
		what = "mouse button %d %s" % [button.button_index, "down" if button.pressed else "up"]
	elif event is InputEventAction:
		var action: InputEventAction = event
		what = "action %s %s" % [action.action, "down" if action.pressed else "up"]
	else:
		return
	_foreign_in_act += 1
	if _foreign_labels.size() < MAX_FOREIGN_LABELS:
		_foreign_labels.append(what)
	# Frozen between ops is the case that cannot be survived: the game was
	# supposed to be perfectly still, and something moved it. Whatever the next
	# op observes is a state this run did not produce, so it poisons the session
	# exactly like a mutating probe - later ops refuse, stop reports it.
	if not get_tree().paused or _tainted != "":
		return
	_tainted = (
		"foreign input reached the game while it was FROZEN between ops: %s. " % what
		+ "This session did not send it, so something outside the run - a hand on the "
		+ "keyboard, a click into the game's window - is playing the same game you are "
		+ "judging, and the world was supposed to be motionless. Everything observed from "
		+ "here on mixes your inputs with someone else's, so no verdict drawn from it is "
		+ "worth anything: report `blocked` and say the game was touched during the test, "
		+ "not that the game is broken."
	)


func _button_index(entry: Dictionary) -> MouseButton:
	return MOUSE_BUTTON_RIGHT if str(entry.get("button", "left")) == "right" else MOUSE_BUTTON_LEFT


# `button` is a word, not a Godot button index. A caller sending 1 means "left",
# but str(1) is not "left", so it would quietly become a left click - and a
# right-click test that passes by left-clicking is worse than one that fails.
# Until this check existed, an integer here crashed on String(int), which has no
# constructor, and the run saw only "Invalid call 'String' constructor".
func _button_error(entry: Dictionary) -> String:
	if not entry.has("button"):
		return ""
	var button := str(entry["button"])
	if button == "left" or button == "right":
		return ""
	return 'button must be "left" or "right", got ' + JSON.stringify(entry["button"])


# Push a mouse press (pressed=true) or release at a viewport pixel. The cursor
# is MOVED there first (warp + motion event, via _move_mouse) the way a real
# device would: a game that polls get_viewport().get_mouse_position() during the
# click otherwise reads the HOST cursor, wherever it happens to be - measured
# under canvas_items stretch, clicks polled a third of the screen away from
# where they reported landing.
#
# The event's position is WINDOW pixels, like a real device's: Godot applies the
# window's stretch transform to injected events exactly as it does to OS input,
# so a canvas-space position would be transformed TWICE under stretch. Measured:
# a viewport-space click at a 48px button's centre missed it entirely in a
# 1280x720 window showing a 1920x1080 canvas.
func _click_at(pos: Vector2, button: MouseButton, pressed: bool) -> void:
	if pressed:
		_move_mouse(pos, Vector2.ZERO)
	var btn := InputEventMouseButton.new()
	btn.button_index = button
	btn.position = _to_window(pos)
	btn.global_position = btn.position
	btn.pressed = pressed
	if pressed:
		btn.button_mask = (
			MOUSE_BUTTON_MASK_RIGHT if button == MOUSE_BUTTON_RIGHT else MOUSE_BUTTON_MASK_LEFT
		)
	_inject(btn)


# Godot 4.7 leaves a programmatically focused LineEdit focused but NOT editing,
# and it then discards every key it receives without a trace. A real click is
# what puts it in editing state, so a typed target is always clicked first.
func _focus_click(node: Control) -> void:
	var center: Vector2 = node.get_global_rect().get_center()
	_click_at(center, MOUSE_BUTTON_LEFT, true)
	await get_tree().process_frame
	_click_at(center, MOUSE_BUTTON_LEFT, false)
	await get_tree().process_frame


# Returns "" when the edge was dispatched, else why it was not.
func _dispatch_key(entry: Dictionary, pressed: bool) -> String:
	var key_str: String = String(entry.get("key", ""))
	var ev := InputEventKey.new()
	ev.pressed = pressed
	if key_str.length() == 1:
		ev.unicode = key_str.unicode_at(0)
		ev.keycode = OS.find_keycode_from_string(key_str.to_upper())
	else:
		ev.keycode = OS.find_keycode_from_string(key_str)
	# A name Godot does not know resolves to keycode 0, and the multi-character
	# branch sets no unicode either - so the event reaches the game as nothing at
	# all while the delivery record still says it landed. A real run spent its
	# whole first session sending key:"Player" at a name field, read the silence
	# as the game ignoring valid input, and finally reached for a scene-changing
	# probe that poisoned the session. Refuse it instead.
	if ev.keycode == 0 and ev.unicode == 0:
		return (
			"'%s' is not a key: it is neither a single character nor a Godot key name "
			% key_str
			+ "(Enter, Space, Escape, Tab, F1...). To type a word, send one entry per "
			+ "character, each carrying the same 'target' so the field is focused first."
		)
	if ev.keycode != 0:
		ev.physical_keycode = ev.keycode
	_inject(ev)
	return ""


# Deliver one input entry's press (pressed=true) or release edge. This game runs
# in ONE real viewport (no SubViewport split), so parse_input_event is the
# correct channel: it reaches the focused Control and any /root autoload's
# _input/_unhandled_input - e.g. a settings-menu autoload toggling on Esc.
# Each edge is dispatched exactly once, so toggles fire once per edge.
#
# Returns "" when the edge was dispatched, else why it was not. An entry the
# harness cannot act on must never read back as delivered: the model would take
# the silence for "the game ignored my input" and blame the game.
func _dispatch_input(entry: Dictionary, pressed: bool) -> String:
	# A typed target is click-focused before its first key (Godot 4.7 leaves a
	# programmatically focused LineEdit not editing, silently discarding every
	# key) - the one edge that cannot dispatch inside a single frame.
	if String(entry.get("type", "action")) == "key" and not String(entry.get("target", "")).is_empty():
		var target: String = String(entry.get("target", ""))
		var control: Control = _resolve_target(target)
		if control == null:
			return "no Control matched target '" + target + "'"
		if pressed and not _typed_targets.has(target):
			_typed_targets[target] = control
			await _focus_click(control)
	return _dispatch_edge(entry, pressed)


# The synchronous rest of delivery: every branch dispatches within this frame.
# Split out so game_drive's api and the servo loop can press and release as
# plain calls - a coroutine a forgotten `await` silently abandons is exactly
# the kind of failure a drive body cannot be allowed to have.
func _dispatch_edge(entry: Dictionary, pressed: bool) -> String:
	var button_error := _button_error(entry)
	if not button_error.is_empty():
		return button_error
	var kind: String = String(entry.get("type", "action"))
	match kind:
		"key":
			return _dispatch_key(entry, pressed)
		"mouse":
			# Missing coordinates used to default to (0,0) - a click in the screen
			# corner that reads as the game ignoring valid input.
			if not entry.has("x") or not entry.has("y"):
				return (
					"a mouse click needs both x and y in viewport pixels (got keys "
					+ str(entry.keys())
					+ "); without them it would land at (0,0), the corner of the screen"
				)
			_click_at(
				Vector2(float(entry.get("x", 0)), float(entry.get("y", 0))),
				_button_index(entry),
				pressed
			)
		"target":
			var node: Control = _resolve_target(String(entry.get("target", "")))
			if node == null:
				return "no Control matched target '" + String(entry.get("target", "")) + "'"
			_click_at(node.get_global_rect().get_center(), _button_index(entry), pressed)
		"motion":
			# Relative motion is what drives a MOUSE_MODE_CAPTURED first-person
			# camera; it has no release edge, so only the press edge dispatches.
			var mv := InputEventMouseMotion.new()
			mv.relative = _to_window(Vector2(float(entry.get("dx", 0)), float(entry.get("dy", 0))))
			# The event's position is where the pointer actually is (in window
			# pixels, like every parsed event - see _click_at), not a hardcoded
			# viewport centre the polled cursor never matched.
			mv.position = _to_window(get_viewport().get_mouse_position())
			mv.global_position = mv.position
			_inject(mv)
		_:
			var action: String = String(entry.get("action", ""))
			if action.is_empty():
				return (
					"entry has no action name; it reached the 'action' branch with keys "
					+ str(entry.keys())
					+ " (a misspelled or missing 'type' lands here)"
				)
			# An InputEventAction routes through the same pipeline a player
			# triggers, so both is_action_pressed pollers and action-edge
			# handlers fire - even when the action has no key mapping.
			var ev := InputEventAction.new()
			ev.action = action
			ev.pressed = pressed
			_inject(ev)
	return ""


# Resolve a target selector to a Control: first as a node path under the running
# scene, else by recursively matching a Control whose .text or .name equals it.
func _resolve_target(target: String) -> Control:
	if target.is_empty():
		return null
	var scene_root: Node = _game_scene()
	if scene_root == null:
		return null
	var by_path: Node = scene_root.get_node_or_null(NodePath(target))
	if by_path is Control:
		return by_path
	return _find_control_by_text(scene_root, target)


func _find_control_by_text(node: Node, target: String) -> Control:
	for child in node.get_children(false):
		if child is Control:
			if String(child.name) == target:
				return child
			if "text" in child and String(child.get("text")) == target:
				return child
		var found: Control = _find_control_by_text(child, target)
		if found != null:
			return found
	return null


# ------------------------------------------------------------------ schedule

func _label(entry: Dictionary) -> String:
	var kind: String = String(entry.get("type", "action"))
	match kind:
		"key":
			return "key:" + String(entry.get("key", ""))
		"mouse":
			return (
				"mouse:%s@%d,%d"
				% [
					String(entry.get("button", "left")),
					int(entry.get("x", 0)),
					int(entry.get("y", 0)),
				]
			)
		"target":
			return "target:%s:%s" % [String(entry.get("button", "left")), String(entry.get("target", ""))]
		"drag":
			return "drag:%s" % String(entry.get("button", "left"))
		"servo":
			return "servo:%s->%s" % [String(entry.get("probe", "")), str(entry.get("target", ""))]
		"motion":
			return "motion:%d,%d" % [int(entry.get("dx", 0)), int(entry.get("dy", 0))]
		_:
			return "action:" + String(entry.get("action", ""))


func _now_ms() -> int:
	return Time.get_ticks_msec() - _start_ms


func _new_record(index: int, entry: Dictionary) -> Dictionary:
	return {
		"index": index,
		"type": String(entry.get("type", "action")),
		"label": _label(entry),
		"requested_at_ms": int(entry.get("at_ms", 0)),
		"requested_hold_ms": int(entry.get("hold_ms", 0)),
		"press_ms": -1,
		"press_frame": -1,
		"release_ms": -1,
		"release_frame": -1,
		"hold_frames": 0,
		"hold_clamped": false,
		"delivered": false,
	}


# Wall-clock scheduling (vsync-off frames run faster than real time) with a
# frame floor on every hold: dispatch each entry at its at_ms, release it once
# BOTH its hold_ms has elapsed and MIN_HOLD_FRAMES have passed, and keep the
# loop alive until duration_ms with nothing still held.
func _replay(inputs: Array, duration_ms: int, records: Array) -> void:
	var pending: Array = []  # {entry, record, release_at_ms, press_engine_frame}
	var issued := {}
	while true:
		var elapsed: int = _now_ms()
		for i in inputs.size():
			if issued.has(i) or elapsed < int(inputs[i].get("at_ms", 0)):
				continue
			issued[i] = true
			var entry: Dictionary = inputs[i]
			var record: Dictionary = records[i]
			var dropped: String = await _dispatch_input(entry, true)
			if dropped != "":
				record["dropped"] = dropped
				continue
			record["press_ms"] = _now_ms()
			record["press_frame"] = Engine.get_process_frames() - _start_frame
			record["delivered"] = true
			if String(entry.get("type", "action")) == "motion":
				continue  # edgeless: a motion event has no release
			pending.append(
				{
					"entry": entry,
					"record": record,
					"release_at_ms": record["press_ms"] + int(entry.get("hold_ms", 0)),
					"press_physics_frame": Engine.get_physics_frames(),
				}
			)

		var still_pending: Array = []
		for p in pending:
			# Physics frames, because that is the tick the game samples input on;
			# see MIN_HOLD_FRAMES. hold_frames in the report is physics frames too.
			var held_frames: int = Engine.get_physics_frames() - int(p["press_physics_frame"])
			if held_frames < MIN_HOLD_FRAMES:
				if _now_ms() >= int(p["release_at_ms"]):
					p["record"]["hold_clamped"] = true
				still_pending.append(p)
				continue
			if _now_ms() < int(p["release_at_ms"]):
				still_pending.append(p)
				continue
			await _dispatch_input(p["entry"], false)
			p["record"]["release_ms"] = _now_ms()
			p["record"]["release_frame"] = Engine.get_process_frames() - _start_frame
			p["record"]["hold_frames"] = held_frames
		pending = still_pending

		if _now_ms() >= duration_ms and pending.is_empty() and issued.size() == inputs.size():
			return
		await get_tree().process_frame


func _read_back_text() -> Dictionary:
	var readback: Dictionary = {}
	for target in _typed_targets:
		var control: Control = _typed_targets[target]
		if is_instance_valid(control) and "text" in control:
			readback[target] = String(control.get("text"))
	return readback


# ------------------------------------------------------------------- capture

func _run() -> void:
	var inputs: Array = _params["inputs"]
	var duration_ms: int = int(_params["duration_ms"])
	# The tool refuses these before launching; checked again here because a run
	# that starts anyway would do zero work and publish a report saying so as if
	# it were a result (backstop for the sidecar's writer).
	if duration_ms <= 0:
		printerr(
			"ziva_input_harness: duration_ms is %d - a run of zero length does zero work; refusing"
			% duration_ms
		)
		return
	# The loop below waits for every entry to be issued, and an entry scheduled
	# past the end of the run would never be - leaving the game spinning until
	# the tool times out with nothing to show for it.
	for i in inputs.size():
		var end_ms: int = int(inputs[i].get("at_ms", 0)) + int(inputs[i].get("hold_ms", 0))
		if end_ms > duration_ms:
			printerr(
				"ziva_input_harness: input %d ends at %dms but duration_ms is %d - refusing a schedule that cannot complete"
				% [i, end_ms, duration_ms]
			)
			return
	var records: Array = []
	for i in inputs.size():
		records.append(_new_record(i, inputs[i]))

	_start_ms = Time.get_ticks_msec()
	_start_frame = Engine.get_process_frames()
	await _replay(inputs, duration_ms, records)

	var undelivered: Array = []
	for record in records:
		if not record["delivered"]:
			undelivered.append(record)
	if not undelivered.is_empty():
		printerr(
			"ziva_input_harness: %d of %d inputs were never delivered"
			% [undelivered.size(), records.size()]
		)

	var report := {
		"duration_ms": duration_ms,
		"elapsed_ms": _now_ms(),
		"frames": Engine.get_process_frames() - _start_frame,
		"entries": records,
		"undelivered": undelivered,
		"text_readback": _read_back_text(),
	}

	for i in range(SETTLE_FRAMES):
		await get_tree().process_frame
		await RenderingServer.frame_post_draw

	var tex := get_tree().get_root().get_texture()
	if tex == null:
		printerr("ziva_input_harness: root viewport texture is null")
		return
	var img: Image = tex.get_image()
	if img == null:
		printerr("ziva_input_harness: get_image() returned null")
		return
	if img.is_empty():
		printerr("ziva_input_harness: captured image is empty")
		return
	var longest: int = maxi(img.get_width(), img.get_height())
	if longest > MAX_FRAME_EDGE:
		img.resize(
			img.get_width() * MAX_FRAME_EDGE / longest,
			img.get_height() * MAX_FRAME_EDGE / longest,
			Image.INTERPOLATE_LANCZOS
		)
	var results_tmp := String(_params["results_tmp"])
	var err: int = img.save_png(results_tmp)
	if err != OK:
		printerr("ziva_input_harness: save_png failed err " + str(err))
		return

	var report_file := FileAccess.open(String(_params["report_path"]), FileAccess.WRITE)
	if report_file == null:
		printerr("ziva_input_harness: could not write the delivery report to " + String(_params["report_path"]))
		return
	report_file.store_string(JSON.stringify(report))
	report_file.close()

	# Atomic publish, LAST: every poller gates on results_path existing, so it
	# must appear only once the report beside it is complete too.
	var d := DirAccess.open("res://")
	if d == null:
		printerr("ziva_input_harness: DirAccess.open(res://) failed")
		return
	var results_path := String(_params["results_path"])
	if d.file_exists(results_path):
		d.remove(results_path)
	err = d.rename(results_tmp, results_path)
	if err != OK:
		printerr("ziva_input_harness: rename to results path failed err " + str(err))
		return

	if EngineDebugger.is_active():
		EngineDebugger.send_message("ziva_pt:captured", [results_path])


# ------------------------------------------------------------------- session
#
# plugin-server owns the QA session socket and writes {port, token, path} here
# before the game launches. The token is the only credential, so it never leaves
# this file and the sidecar it came from.

func _start_session() -> void:
	var cfg := _read_sidecar(SESSION_PATH, ["port", "token", "path"])
	if cfg.is_empty():
		return
	# The whole point of a session is that the world is frozen between ops, so
	# this node is the one thing that may keep running while it is.
	process_mode = Node.PROCESS_MODE_ALWAYS
	_put_up_glass()
	if bool(cfg.get("record", false)):
		_record_dir = String(cfg.get("record_dir", ""))
		if _record_dir.is_empty():
			printerr("ziva_input_harness: the sidecar set record=true but named no record_dir")
		else:
			_record_max_frames = maxi(int(cfg.get("record_max_frames", MAX_FRAMES)), 2)
			_build_overlay()
	var url := (
		"ws://127.0.0.1:%d%s?token=%s"
		% [int(cfg["port"]), String(cfg["path"]), String(cfg["token"]).uri_encode()]
	)
	_seat_requested = bool(cfg.get("seat", false))
	_session_goal = String(cfg.get("goal", ""))
	_ws = WebSocketPeer.new()
	# A screenshot reply is a base64 PNG of a whole frame - megabytes, against a
	# 64 KiB default that silently refuses anything larger. MAX_FRAME_EDGE already
	# caps a frame at Anthropic's 5MB, so this is that ceiling with headroom for
	# the JSON around it, and still under Bun's 16MB receive limit.
	_ws.outbound_buffer_size = 8 << 20
	var err := _ws.connect_to_url(url)
	if err != OK:
		printerr("ziva_input_harness: could not dial the QA session socket at %s (err %d)" % [url, err])
		_ws = null


# A native window becomes a pane of glass when a session owns it: mouse events
# pass through to whatever is behind it, so it can never be clicked, so it can
# never take focus, so the host's keystrokes can never reach the game. Six
# sessions of the Godotcraft run died to exactly that click-then-type path.
#
# Measured on X11 with a peer window holding focus: a plain window took 3 keys
# and 2 clicks from the host; this takes 0 of each. A passthrough REGION was the
# other candidate and leaks - the degenerate polygon it needs (an empty one means
# "disable") stays live, and a click aimed at that corner landed.
#
# NO_FOCUS is not redundant with it: under focus-follows-mouse the pointer alone
# gives a window the keyboard, with no click for passthrough to swallow.
#
# This is also the half of the isolation the virtual seat cannot do. A bare
# SubViewport ignores host input, but a game polling Input.is_physical_key_pressed
# reads the global singleton, which the host's real keyboard sets whether the game
# is seated or not.
func _put_up_glass() -> void:
	# macOS's embedded display renders into the editor's Game tab. It has no
	# native game window and only implements WINDOW_FLAG_TRANSPARENT; both flags
	# below are no-ops that always read back false, not failed isolation attempts.
	# The editor can still forward input, so _input's foreign-input detection
	# remains necessary. Do not infer that an embedded session is isolated.
	if DisplayServer.get_name() == "embedded":
		return
	DisplayServer.window_set_flag(DisplayServer.WINDOW_FLAG_MOUSE_PASSTHROUGH, true)
	DisplayServer.window_set_flag(DisplayServer.WINDOW_FLAG_NO_FOCUS, true)
	if not DisplayServer.window_get_flag(DisplayServer.WINDOW_FLAG_MOUSE_PASSTHROUGH):
		printerr(
			"ziva_input_harness: %s refused WINDOW_FLAG_MOUSE_PASSTHROUGH, so the game window "
			% DisplayServer.get_name()
			+ "still accepts the host's clicks. Anything clicked or typed at it while the agent "
			+ "drives will reach the game and taint the session."
		)
	if not DisplayServer.window_get_flag(DisplayServer.WINDOW_FLAG_NO_FOCUS):
		printerr(
			"ziva_input_harness: %s refused WINDOW_FLAG_NO_FOCUS. Clicks are still passed "
			% DisplayServer.get_name()
			+ "through, but under focus-follows-mouse the host's pointer can hand this window "
			+ "the keyboard without one."
		)


func _process(delta: float) -> void:
	_tick_recorder(delta)
	if _ws == null:
		return
	_ws.poll()
	var state := _ws.get_ready_state()
	if state == WebSocketPeer.STATE_CLOSED:
		# plugin-server is the only thing that can drive this game now, so losing
		# it means the game is unreachable - end it rather than leave it running.
		printerr("ziva_input_harness: QA session socket closed (code %d)" % _ws.get_close_code())
		_ws = null
		get_tree().quit()
		return
	if state != WebSocketPeer.STATE_OPEN or _serving:
		return
	if not _greeted:
		_greeted = true
		_serving = true
		_greet()
		return
	if _ws.get_available_packet_count() == 0:
		return
	_serving = true
	_serve(_ws.get_packet().get_string_from_utf8())


# The scene gets a few live frames to reach its initial state before the first
# freeze, so the caller's first observation is of an initialized game and not of
# frame zero, where _process-driven setup has not run yet.
func _greet() -> void:
	for i in range(SETTLE_FRAMES):
		await get_tree().process_frame
	if _seat_requested:
		if _take_seat():
			# The seat is a new viewport, so the scene needs a frame in it before
			# anything is measured or captured through it.
			await get_tree().process_frame
		else:
			printerr("ziva_input_harness: could not take the virtual seat; running unseated")
	_freeze()
	# Session frame counters are PHYSICS frames throughout: the tick game logic
	# samples input on, and the unit every frames parameter is documented in.
	_start_frame = Engine.get_physics_frames()
	var scene: Node = _game_scene()
	_send({"op": "hello", "scene": "" if scene == null else scene.scene_file_path})
	_serving = false


# Freeze/thaw pair every op goes through, so no path can pause the tree without
# capping the render rate or resume it without restoring the game's own cap.
func _freeze() -> void:
	if _running_max_fps == -1:
		_running_max_fps = Engine.max_fps
	Engine.max_fps = PAUSED_RENDER_FPS_CAP
	get_tree().paused = true


func _thaw() -> void:
	if _running_max_fps != -1:
		Engine.max_fps = _running_max_fps
	get_tree().paused = false


func _send(payload: Dictionary) -> void:
	var text := JSON.stringify(payload)
	if _ws.send_text(text) == OK:
		return
	# A reply that never goes out leaves the caller waiting on the session
	# deadline with no idea why, so report the drop over the same socket - a few
	# hundred bytes will fit where the frame did not. Losing this one too is the
	# end of the conversation, so it also goes to the editor log.
	printerr("ziva_input_harness: could not send a %d-byte reply for op %s" % [text.length(), str(payload.get("id", -1))])
	var notice := {
		"id": payload.get("id", -1),
		"ok": false,
		"error": (
			"the harness could not put a %d-byte reply on the socket. " % text.length()
			+ "A screenshot of this game is larger than the WebSocket outbound buffer "
			+ "(currently %d bytes); lower MAX_FRAME_EDGE or raise outbound_buffer_size."
			% _ws.outbound_buffer_size
		),
	}
	if _ws.send_text(JSON.stringify(notice)) != OK:
		printerr("ziva_input_harness: the failure notice would not send either; the caller will time out")


func _serve(text: String) -> void:
	var msg: Variant = JSON.parse_string(text)
	if not (msg is Dictionary) or not msg.has("id") or not msg.has("op"):
		printerr("ziva_input_harness: malformed QA session op: " + text)
		_serving = false
		return
	var op := String(msg["op"])
	var reply: Dictionary
	# Once a probe has written to the game, every later answer is drawn from a
	# state the agent partly authored. Refuse them all rather than let the run
	# reach a verdict; stop still works, so the evidence bundle gets finalized
	# with the violation in it.
	if _tainted != "" and op != "stop":
		reply = {"ok": false, "error": _tainted}
		reply["id"] = msg["id"]
		_send(reply)
		_serving = false
		return
	match op:
		"observe":
			reply = await _op_observe(msg)
		"act":
			reply = await _op_act(msg)
		"watch":
			reply = _op_watch(msg)
		"drive":
			reply = await _op_drive(msg)
		"stop":
			# The tree is frozen between ops, so lifting a sustained input needs a
			# live frame for the game to see the release edge.
			_thaw()
			var lifted: Array = await _release_all_sustained()
			_freeze()
			# The process ends a few frames from here, so this is the last chance
			# to publish a live_ms that includes the thaw above.
			if not _record_dir.is_empty():
				_write_recording_json()
			reply = {"ok": true, "released_on_stop": lifted}
			if _tainted != "":
				reply["tainted"] = _tainted
		_:
			reply = {"ok": false, "error": "unknown QA session op '" + op + "'"}
	# Whatever watched signals emitted since the last reply ride this one,
	# whichever op it answers: an event's whole value is that nobody had to be
	# probing at the right moment to see it.
	if not _events.is_empty():
		reply["events"] = _events
		_events = []
		if _events_dropped > 0:
			reply["events_dropped"] = _events_dropped
			_events_dropped = 0
	reply["id"] = msg["id"]
	_send(reply)
	if op == "stop":
		# Give the socket frames to actually flush the reply before the process ends.
		for i in range(3):
			_ws.poll()
			await get_tree().process_frame
		get_tree().quit()
		return
	_serving = false


# ------------------------------------------------------------------- probes

# Probe values cross a JSON socket and are compared for equality, so every
# non-JSON Variant becomes its var_to_str form ("Vector2(4, 5)") rather than
# being silently dropped or mangled by JSON.stringify. Text is capped: a probe
# that evaluates to the whole world otherwise ships the whole world into model
# context every time it runs (measured: one value of 248,127 chars).
func _jsonable(value: Variant) -> Variant:
	match typeof(value):
		TYPE_NIL, TYPE_BOOL, TYPE_INT, TYPE_FLOAT:
			return value
		TYPE_STRING:
			return _capped(value)
		TYPE_STRING_NAME, TYPE_NODE_PATH:
			return _capped(String(value))
		_:
			return _capped(var_to_str(value))


# The marker carries the full length and a hash of the FULL text: without the
# hash, a value whose first PROBE_VALUE_MAX_CHARS never change would compare
# equal across an act and read as "the input did nothing".
func _capped(text: String) -> String:
	if text.length() <= PROBE_VALUE_MAX_CHARS:
		return text
	return (
		text.substr(0, PROBE_VALUE_MAX_CHARS)
		+ (
			" ...truncated: %d chars total, full-value hash %d - refine the expression to return just the part you need"
			% [text.length(), hash(text)]
		)
	)


# Expressions are evaluated against the running scene root, so "get_node("HUD")"
# reads the way it does inside the game's own scripts; `tree` and `root` are
# there for anything that has to reach an autoload or the viewport.
func _eval(expression: String) -> Dictionary:
	var result := _eval_raw(expression)
	if result.has("error"):
		return result
	return {"value": _jsonable(result["value"])}


# The un-jsonabled form, for callers that COMPUTE on the value: game_drive's
# api.eval and the servo loop need the real Variant, where the wire form
# "Vector2(4, 5)" would be a useless string.
func _eval_raw(expression: String) -> Dictionary:
	var scene: Node = _game_scene()
	if scene == null:
		return {"error": "there is no current scene to evaluate '" + expression + "' against"}
	var parsed := Expression.new()
	if parsed.parse(expression, ["tree", "root"]) != OK:
		return {"error": "could not parse '" + expression + "': " + parsed.get_error_text()}
	# The tree is frozen while a probe runs, so nothing but the probe itself can
	# move the game's state between these two digests.
	var before := _state_digest()
	var value: Variant = parsed.execute([get_tree(), get_tree().get_root()], scene, false)
	if parsed.has_execute_failed():
		return {"error": "could not evaluate '" + expression + "': " + parsed.get_error_text()}
	var after := _state_digest()
	if after != before:
		if _tainted == "":
			_tainted = (
				"the probe '%s' CHANGED the game instead of reading it " % expression
				+ "(declared state digest %d -> %d). A probe that puts the game into the "
				% [before, after]
				+ "state it was supposed to reach by playing destroys the evidence it looks "
				+ "like it produced. The side effect cannot be undone, so this session can no "
				+ "longer settle anything: start a new one and reach the state with game_act, "
				+ "or report that you could not."
			)
		return {"error": _tainted}
	return {"value": value}


# A hash of the game's OWN declared state: for every scripted node, the values of
# the variables its script declares. Engine properties are skipped - there are
# thousands per node and none of them are what a game calls its state - which is
# what keeps this cheap enough to run either side of every probe. Deliberately
# knows nothing about any particular game: `_slots`, `health` and `score` are all
# just script variables here.
#
# Values are hashed, never stringified. var_to_str() on a game that keeps its
# world in a declared variable serializes that whole world every call: measured
# on Godotcraft, whose world.gd holds ~9800 voxels across four Dictionaries, one
# digest built 5.28 MB of text and took 167 ms. This runs twice per probe and
# once per frame inside an `until` wait, so that shape turned a 600-frame wait
# into 200 s of harness CPU and blew straight through the session's 120 s op
# deadline. Hashing the same values costs 6.5 ms - 26x cheaper, and strictly
# more sensitive than the text form (see the identity fold below).
# ---------------------------------------------------- what the WORLD did
#
# `effect` used to mean "did the GDScript strings the caller happened to choose
# change value". That is not what the caller reads it as: the system prompt
# turns a null result into a verdict about the GAME. Measured cost of the
# difference - a run pressed E while probing `_hud.visible`, got `effect: none`,
# and concluded the inventory was broken. It was not; the right probe was
# `is_inventory_open()`. The agent abandoned a working mechanic and paid for it.
#
# So the world is measured independently of the caller's probes. Everything here
# is derivable with NO per-game knowledge - verified against two unrelated games
# (a voxel sandbox and a golf game): the current camera and its transform, what
# that camera is looking at (a raycast through the viewport centre), the visible
# UI census, and the whole-tree digest that already exists for probe purity.
func _world_snapshot() -> Dictionary:
	var snap := {"digest": _state_digest(), "mouse_mode": int(Input.mouse_mode)}
	var cam := get_viewport().get_camera_3d()
	if cam != null:
		snap["cam_pos"] = cam.global_position
		snap["cam_fwd"] = -cam.global_transform.basis.z
		# What the crosshair is on. This is the single most useful fact for an
		# agent that is playing rather than inspecting, and it needs no adapter.
		var space := cam.get_world_3d().direct_space_state
		if space != null:
			var from := cam.global_position
			var query := PhysicsRayQueryParameters3D.create(from, from + (-cam.global_transform.basis.z) * AIM_RAY_LENGTH)
			query.collide_with_areas = true
			var hit := space.intersect_ray(query)
			if not hit.is_empty() and hit.has("collider") and hit["collider"] != null:
				snap["aim"] = String((hit["collider"] as Node).name)
				snap["aim_at"] = hit["position"]
	var focus := get_viewport().gui_get_focus_owner()
	snap["focus"] = "" if focus == null else String(focus.name)
	var shown := 0
	for c in get_tree().get_root().find_children("*", "Control", true, false):
		if (c as Control).visible:
			shown += 1
		if shown > UI_CENSUS_LIMIT:
			break
	snap["ui_visible"] = shown
	return snap


## Readable, world-first: what moved, in the game's own terms.
##
## Returns `lines` (everything worth telling the caller) and `moved` (whether any
## of it counts as the game RESPONDING). They differ on purpose. Clicking any
## Button hands it focus, so if focus alone counted, every dead button would look
## alive and the "delivered, no observable effect" refusal - the one thing that
## catches a broken control - would stop firing. Focus is reported, never counted.
func _world_diff(before: Dictionary, after: Dictionary) -> Dictionary:
	var out: Array = []
	var moved_meaningfully := false
	if before.has("cam_pos") and after.has("cam_pos"):
		var moved: float = (after["cam_pos"] as Vector3).distance_to(before["cam_pos"])
		if moved > 0.05:
			out.append("viewpoint moved %.2fm" % moved)
			moved_meaningfully = true
	if before.has("cam_fwd") and after.has("cam_fwd"):
		var turned: float = rad_to_deg((before["cam_fwd"] as Vector3).angle_to(after["cam_fwd"]))
		if turned > 1.0:
			out.append("view turned %.0f deg" % turned)
			moved_meaningfully = true
	if String(before.get("aim", "")) != String(after.get("aim", "")):
		out.append("aiming at %s (was %s)" % [
			("nothing" if String(after.get("aim", "")).is_empty() else String(after["aim"])),
			("nothing" if String(before.get("aim", "")).is_empty() else String(before["aim"])),
		])
		moved_meaningfully = true
	if int(before.get("ui_visible", 0)) != int(after.get("ui_visible", 0)):
		out.append("UI changed (%d -> %d visible controls)" % [
			int(before.get("ui_visible", 0)), int(after.get("ui_visible", 0))])
		moved_meaningfully = true
	if String(before.get("focus", "")) != String(after.get("focus", "")):
		out.append("keyboard focus -> %s" % ("nothing" if String(after.get("focus","")).is_empty() else String(after["focus"])))
	if int(before.get("mouse_mode", 0)) != int(after.get("mouse_mode", 0)):
		out.append("mouse mode %d -> %d" % [int(before.get("mouse_mode",0)), int(after.get("mouse_mode",0))])
		moved_meaningfully = true
	# The whole-tree digest is deliberately NOT a fallback signal here. A living
	# game moves on its own - day/night, animals, particles - so in Godotcraft it
	# differs on every act, which would make `none` unreachable and strip the one
	# state that is a real finding of all meaning. Measured: an unbound keypress
	# reported "changed" purely from ambient motion.
	return {"lines": out, "moved": moved_meaningfully}


func _state_digest() -> int:
	var parts := PackedInt64Array()
	var stack: Array = [get_tree().get_root()]
	var visited := 0
	# Every node's identity, folded over the WHOLE tree. The property scan below
	# is capped, and its count saturates at that cap on any big scene - so on its
	# own it cannot see a node appear or vanish, and hashing a container of node
	# references does not change when one of them is freed. Walking the tree is
	# the cheap half of this function; only the per-property work is not.
	var identities := 0
	while not stack.is_empty():
		var node: Node = stack.pop_back()
		visited += 1
		identities ^= node.get_instance_id()
		for child in node.get_children():
			stack.push_back(child)
		if visited > DIGEST_NODE_LIMIT:
			continue
		var script: Variant = node.get_script()
		if script == null:
			continue
		for prop in (script as Script).get_script_property_list():
			if int(prop.get("usage", 0)) & PROPERTY_USAGE_SCRIPT_VARIABLE == 0:
				continue
			var name := String(prop.get("name", ""))
			parts.append(node.get_instance_id())
			parts.append(hash(name))
			parts.append(hash(node.get(name)))
	# Node count catches a probe that spawns or frees something without touching
	# any declared variable.
	parts.append(visited)
	parts.append(identities)
	return hash(parts)


func _is_number(v: Variant) -> bool:
	return v is float or v is int


# `until` is satisfied when its expression HOLDS, GDScript-truthily: false, 0,
# 0.0, "" and null do not hold, everything else does. It used to be satisfied by
# the value merely CHANGING from its pre-act baseline, which inverted on a
# predicate that was already true - "distance < 2" starting true waited for it
# to become FALSE, burned its whole timeout on a condition that held the entire
# time, and then reported failure.
func _truthy(value: Variant) -> bool:
	match typeof(value):
		TYPE_NIL:
			return false
		TYPE_BOOL:
			return value
		TYPE_INT:
			return value != 0
		TYPE_FLOAT:
			return value != 0.0
		TYPE_STRING:
			return value != ""
		_:
			return true


func _eval_all(probes: Array) -> Dictionary:
	var values := {}
	for probe in probes:
		values[String(probe)] = _eval(String(probe))
	return values


# A probe that cannot be evaluated compares equal to itself, which would read as
# "the input did nothing" - the single most misleading answer this can give. So
# a bad probe fails the whole op instead.
func _first_probe_error(values: Dictionary) -> String:
	for key in values:
		if (values[key] as Dictionary).has("error"):
			return String(values[key]["error"])
	return ""


# ---------------------------------------------------------------- signal taps

# game_watch: connect recorders so emissions between op boundaries stop being
# invisible. A signal that fires MID-act - a latch, a death, a level-complete -
# lands in no probe unless one happens to run at exactly the right op; a tap
# catches it the frame it fires and the next reply carries it.
#
# Watching is exempt from the purity digest BY DESIGN: a connection is
# observation infrastructure, not game state - no variable the game's scripts
# declare changes when a recorder is connected.
func _op_watch(msg: Dictionary) -> Dictionary:
	var specs: Array = msg.get("signals", [])
	if specs.is_empty():
		return {"ok": false, "error": "game_watch needs at least one {node_path, signal} entry"}
	var scene: Node = _game_scene()
	if scene == null:
		return {"ok": false, "error": "there is no current scene to watch"}
	for spec_v in specs:
		if (
			not (spec_v is Dictionary)
			or not (spec_v as Dictionary).has("node_path")
			or not (spec_v as Dictionary).has("signal")
		):
			return {"ok": false, "error": "each watch entry needs node_path and signal, got %s" % str(spec_v)}
		var spec: Dictionary = spec_v
		var node_path := String(spec["node_path"])
		var signal_name := String(spec["signal"])
		var key := node_path + ":" + signal_name
		if _watches.has(key):
			return {
				"ok": false,
				"error": (
					"already watching %s - its events arrive on every reply, there is nothing further to arm"
					% key
				),
			}
		var node: Node = scene.get_node_or_null(NodePath(node_path))
		if node == null:
			return {
				"ok": false,
				"error": (
					"no node at '%s' (paths resolve against the running scene root; '.' is the root itself)"
					% node_path
				),
			}
		if not node.has_signal(signal_name):
			return {
				"ok": false,
				"error": (
					"node '%s' has no signal '%s'. Its script declares: %s"
					% [node_path, signal_name, str(_script_signal_names(node))]
				),
			}
		var recorder: Variant = _recorder(_signal_arg_count(node, signal_name), key)
		if recorder is String:
			return {"ok": false, "error": String(recorder)}
		node.connect(signal_name, recorder)
		_watches[key] = true
	return {"ok": true, "watching": _watches.keys()}


func _script_signal_names(node: Node) -> Array:
	var names: Array = []
	var script: Variant = node.get_script()
	if script != null:
		for s in (script as Script).get_script_signal_list():
			names.append(String(s.get("name", "")))
	return names


func _signal_arg_count(node: Node, signal_name: String) -> int:
	for s in node.get_signal_list():
		if String(s.get("name", "")) == signal_name:
			return (s.get("args", []) as Array).size()
	return 0


# A Callable whose arity matches the signal's, or an error string: Godot drops
# an emission whose receiver takes a different argument count, so the recorder
# has to be built per arity.
func _recorder(argc: int, key: String) -> Variant:
	match argc:
		0:
			return func() -> void: _record_event(key, [])
		1:
			return func(a1: Variant) -> void: _record_event(key, [a1])
		2:
			return func(a1: Variant, a2: Variant) -> void: _record_event(key, [a1, a2])
		3:
			return func(a1: Variant, a2: Variant, a3: Variant) -> void: _record_event(key, [a1, a2, a3])
		4:
			return func(a1: Variant, a2: Variant, a3: Variant, a4: Variant) -> void: _record_event(key, [a1, a2, a3, a4])
		5:
			return func(a1: Variant, a2: Variant, a3: Variant, a4: Variant, a5: Variant) -> void: _record_event(key, [a1, a2, a3, a4, a5])
		6:
			return func(a1: Variant, a2: Variant, a3: Variant, a4: Variant, a5: Variant, a6: Variant) -> void: _record_event(key, [a1, a2, a3, a4, a5, a6])
	return "the signal declares %d arguments; game_watch records up to 6" % argc


func _record_event(key: String, args: Array) -> void:
	if _events.size() >= MAX_PENDING_EVENTS:
		_events_dropped += 1
		return
	var capped_args: Array = []
	for arg in args:
		capped_args.append(_jsonable(arg))
	_events.append({
		"signal": key,
		"args": capped_args,
		"physics_frame": Engine.get_physics_frames() - _start_frame,
	})


# ---------------------------------------------------------------- session ops

func _op_observe(msg: Dictionary) -> Dictionary:
	var values := _eval_all(msg.get("probes", []))
	var bad := _first_probe_error(values)
	if bad != "":
		return {"ok": false, "error": bad}
	var reply := {
		"ok": true,
		"probes": values,
		"frame": Engine.get_physics_frames() - _start_frame,
		# Engine singletons are out of an Expression probe's reach, so the render
		# throttle facts ride on the reply: they are how a caller (and the e2e
		# gate) can tell that a frozen game is not burning CPU drawing itself.
		"render": {"max_fps": Engine.max_fps, "frames_drawn": Engine.get_frames_drawn()},
	}
	if bool(msg.get("screenshot", false)):
		var shot := await _capture_frame()
		if shot.has("error"):
			return {"ok": false, "error": String(shot["error"])}
		reply["screenshot"] = shot["png_base64"]
		reply["screenshot_size"] = shot["size"]
	return reply


# The tree keeps rendering while paused, so waiting for a drawn frame here reads
# the current frame without letting the game advance by one. But "keeps
# rendering" is only true while something is actually drawing this window: inside
# the editor's embedded Game tab a covered window can stop drawing altogether,
# and awaiting frame_post_draw there never returns. Wait on the drawn-frame
# counter instead, bounded, so a game that is not being drawn says so in one
# second rather than hanging the op until the session's 120s deadline.
func _capture_frame() -> Dictionary:
	# The overlay is up during pauses now (see _tick_recorder), and this is the
	# frame the agent reasons over - so it comes down for exactly this capture
	# and goes straight back. Hiding it costs one drawn frame, which the wait
	# below already needs anyway.
	var overlay_was_visible := _overlay != null and _overlay.visible
	if overlay_was_visible:
		_overlay.visible = false
	var shot := await _capture_frame_raw()
	if overlay_was_visible:
		_overlay.visible = true
	return shot


func _capture_frame_raw() -> Dictionary:
	var drawn_before := Engine.get_frames_drawn()
	var waited := 0
	while Engine.get_frames_drawn() == drawn_before:
		if waited >= CAPTURE_DRAW_TIMEOUT_FRAMES:
			return {
				"error": (
					"the game drew no frame in %d process frames, so there is nothing new to "
					% CAPTURE_DRAW_TIMEOUT_FRAMES
					+ (
						"capture (frames_drawn stuck at %d, window visible=%s). "
						% [drawn_before, get_window().visible]
					)
					+ "A game embedded in the editor's Game tab stops drawing while that window "
					+ "is covered or minimized; raise the editor to capture frames."
				)
			}
		await get_tree().process_frame
		waited += 1
	var tex := get_tree().get_root().get_texture()
	if tex == null:
		return {"error": "root viewport texture is null"}
	var img: Image = tex.get_image()
	if img == null or img.is_empty():
		return {"error": "the captured frame was empty"}
	var longest: int = maxi(img.get_width(), img.get_height())
	if longest > MAX_FRAME_EDGE:
		img.resize(
			img.get_width() * MAX_FRAME_EDGE / longest,
			img.get_height() * MAX_FRAME_EDGE / longest,
			Image.INTERPOLATE_LANCZOS
		)
	return {
		"png_base64": Marshalls.raw_to_base64(img.save_png_to_buffer()),
		"size": [img.get_width(), img.get_height()],
	}


# --------------------------------------------------------- recording the run

# Called every process frame, recording or not. The pause check is the whole
# "only while playing" rule and the whole contamination guard at once: the
# session freezes the tree between every op, so thinking time is never captured,
# and game_observe screenshots - the evidence the agent judges - are only ever
# taken while frozen, which is exactly when the overlay is not on screen. No
# bookkeeping, no flag anybody has to keep correct.
func _tick_recorder(delta: float) -> void:
	if _record_dir.is_empty():
		return
	var playing := not get_tree().paused
	# The overlay stays UP while the tree is frozen. Between ops is most of a
	# run's wall clock, and it is exactly when somebody glancing at the Game tab
	# sees a motionless game and cannot tell whether Ziva is working or wedged.
	# Evidence stays clean because _capture_frame hides it for the one frame it
	# reads, not because the overlay is absent.
	if not playing:
		if _overlay_dirty():
			_overlay_draw.queue_redraw()
		return
	_record_live_ms += delta * 1000.0
	var cursor: Vector2 = get_viewport().get_mouse_position()
	if _trail.is_empty() or (_trail[-1] as Vector2).distance_squared_to(cursor) > 4.0:
		_trail.append(cursor)
		if _trail.size() > TRAIL_POINTS:
			_trail.remove_at(0)
	if _overlay_dirty():
		_overlay_draw.queue_redraw()
	if _capturing:
		# frame_post_draw never arrives while nothing is drawing this window, and
		# a Game tab covered by another editor panel is enough to stop it (see
		# _capture_frame). The recorder would then stall while live_ms kept
		# running, and the encoder would stretch the frames it did get across the
		# whole run - a video that is wrong about the game and says nothing.
		_capture_waited += 1
		if _capture_waited > CAPTURE_DRAW_TIMEOUT_FRAMES:
			_fail_recording(
				"the game drew no frame in %d process frames while a capture was pending"
				% CAPTURE_DRAW_TIMEOUT_FRAMES
			)
		return
	if not _record_error.is_empty():
		return
	var physics := Engine.get_physics_frames()
	if _record_last_physics >= 0 and physics - _record_last_physics < _record_stride:
		return
	_record_last_physics = physics
	_capture_waited = 0
	_capture_recording_frame()


# Awaiting frame_post_draw is what makes the readback land on a frame that was
# actually DRAWN; without it get_image() returns whatever the GPU last resolved,
# which on a paused-then-thawed game is the frame before the act. The await also
# makes this a coroutine, so _capturing keeps the next process frame from
# starting a second one on top of it.
func _capture_recording_frame() -> void:
	_capturing = true
	await RenderingServer.frame_post_draw
	var img: Image = get_viewport().get_texture().get_image()
	if img == null or img.is_empty():
		_fail_recording("the viewport read back an empty image")
		return
	var path := "%s/frame_%06d.jpg" % [_record_dir, _record_next]
	var err := img.save_jpg(path, RECORD_JPEG_QUALITY)
	if err != OK:
		_fail_recording("could not write %s (error %d)" % [path, err])
		return
	_record_kept.append(_record_next)
	_record_next += 1
	if _record_kept.size() >= _record_max_frames:
		_decimate()
	_write_recording_json()
	_capturing = false


# The cap is reached by long runs, and a long run's END is where the verdict is
# decided - so the stride doubles and every second frame already on disk goes,
# rather than the recorder stopping and losing the part that mattered. The frame
# rate stays uniform, disk stays bounded, and the whole run survives.
func _decimate() -> void:
	_record_stride *= 2
	var kept := PackedInt32Array()
	for i in range(_record_kept.size()):
		if i % 2 == 0:
			kept.append(_record_kept[i])
		else:
			DirAccess.remove_absolute("%s/frame_%06d.jpg" % [_record_dir, _record_kept[i]])
	_record_kept = kept


# Rewritten after every capture rather than once at the end: a game that crashes
# or is killed mid-run still leaves the encoder an accurate account of what is
# on disk, and the frame rate is computed from live_ms - so a stale one would
# play the whole run back at the wrong speed.
func _write_recording_json() -> void:
	var payload := {
		"frames": _record_kept.size(),
		"live_ms": int(_record_live_ms),
		"stride": _record_stride,
		"physics_hz": Engine.physics_ticks_per_second,
	}
	if not _record_error.is_empty():
		payload["error"] = _record_error
	var f := FileAccess.open("%s/recording.json" % _record_dir, FileAccess.WRITE)
	if f == null:
		_record_error = "could not open recording.json in " + _record_dir
		printerr("ziva_input_harness: recording stopped - " + _record_error)
		return
	f.store_string(JSON.stringify(payload))
	f.close()


# A recording is evidence, so a capture that stops silently is the worst
# outcome: the video ends mid-run and looks like the GAME did. Say so once, stop
# trying, and carry the reason in recording.json so the encoder reports it with
# the run instead of shipping a truncated clip as a finding.
func _fail_recording(why: String) -> void:
	_record_error = why
	_capturing = false
	printerr("ziva_input_harness: recording stopped - " + why)
	_write_recording_json()


func _build_overlay() -> void:
	_overlay = CanvasLayer.new()
	# Above the game's own HUD layers, and running while the tree is frozen so
	# _tick_recorder can hide it before the next observation is captured.
	_overlay.layer = OVERLAY_LAYER
	_overlay.process_mode = Node.PROCESS_MODE_ALWAYS
	_overlay_draw = Node2D.new()
	_overlay_draw.draw.connect(_draw_overlay)
	_overlay.add_child(_overlay_draw)
	add_child(_overlay)


# Every event the game receives, ours and anyone else's. _held is therefore a
# measurement rather than a claim: an act that says it is holding W while the
# game never saw a W draws an empty chip row under a caption promising one.
func _note_overlay_event(event: InputEvent) -> void:
	var label := ""
	var pressed := false
	if event is InputEventKey:
		var key: InputEventKey = event
		if key.is_echo():
			return
		var code: Key = key.keycode if key.keycode != KEY_NONE else key.physical_keycode
		label = OS.get_keycode_string(code) if code != KEY_NONE else String.chr(key.unicode)
		pressed = key.pressed
	elif event is InputEventMouseButton:
		var button: InputEventMouseButton = event
		label = String(MOUSE_LABELS.get(button.button_index, "mouse %d" % button.button_index))
		pressed = button.pressed
		if pressed:
			# The POLLED cursor, not the event's position: the event carries
			# window pixels (see _click_at) and everything drawn here is in
			# canvas pixels, which is what get_mouse_position reports.
			_ripples.append([get_viewport().get_mouse_position(), Time.get_ticks_msec()])
	elif event is InputEventAction:
		var action: InputEventAction = event
		label = String(action.action)
		pressed = action.pressed
	else:
		return
	if label.is_empty():
		return
	# A bare modifier is never something this session sends, so one appearing is
	# the HOST's keyboard reaching the game. Worse, a desktop that grabs the
	# key-up (KWin swallows Super) never delivers the release, so the chip sticks
	# for the rest of the run - a real run showed "Meta" pinned over every frame.
	if label in BARE_MODIFIERS:
		return
	if pressed:
		_held[label] = true
	else:
		_held.erase(label)


# Pointer first and the panels over it: the gate probes the caption panel, the
# REC badge and the first held-key chip by coordinate, and a cursor that wandered
# into any of them would change the pixel it reads.
func _draw_overlay() -> void:
	var size: Vector2 = get_viewport().get_visible_rect().size
	var font: Font = ThemeDB.fallback_font
	var frozen := get_tree().paused

	if _trail.size() > 1:
		_overlay_draw.draw_polyline(PackedVector2Array(_trail), TRAIL_COLOR, 3.0)
	var now := Time.get_ticks_msec()
	var alive: Array = []
	for ripple in _ripples:
		var age: float = float(now - int(ripple[1])) / float(RIPPLE_MS)
		if age > 1.0:
			continue
		alive.append(ripple)
		_overlay_draw.draw_arc(
			ripple[0], 12.0 + age * 48.0, 0.0, TAU, 32, Color(CURSOR_COLOR, 1.0 - age), 3.0
		)
	_ripples = alive
	var cursor: Vector2 = get_viewport().get_mouse_position()
	_overlay_draw.draw_arc(cursor, 14.0, 0.0, TAU, 24, CURSOR_COLOR, 3.0)
	_overlay_draw.draw_line(cursor - Vector2(22, 0), cursor + Vector2(22, 0), CURSOR_COLOR, 2.0)
	_overlay_draw.draw_line(cursor - Vector2(0, 22), cursor + Vector2(0, 22), CURSOR_COLOR, 2.0)

	# Two lines, sized to their own text and floated over the game rather than a
	# band laid across it. The full-width opaque bar this replaces existed only so
	# the gate could read a flat colour out of a lossy JPEG; the sentinel strips
	# below carry that job now, and cost ~700 pixels instead of a fifth of the
	# frame.
	# Falls back to the SESSION's goal, not to a shrug. The five settle frames
	# after every game_start are recorded before any act exists, and across a run
	# with many restarts those frames were most of the footage - all of them
	# captioned "no stated goal" while the agent knew perfectly well what it was
	# there for. The brief now rides the whole session.
	var goal := _intent
	if goal.is_empty():
		goal = ("GOAL: " + _session_goal) if not _session_goal.is_empty() else "no stated goal"
	var under := (
		"paused between actions - Ziva is deciding what to do next"
		if frozen
		else _input_line(cursor)
	)
	var pad := 22.0
	# Only the GOAL is fitted. The line under it carries the live pointer, so its
	# text changes every frame - fitting that thrashes the memo and costs render
	# frames the GAME samples input on: measured, a drag landed at x=270 instead
	# of 300 because the fixture polls the cursor once per drawn frame.
	var goal_size := _fit_caption(font, goal, size.x - 120.0, CAPTION_FONT_SIZE)
	var under_size := CAPTION_SUB_FONT_SIZE
	var goal_w: float = font.get_string_size(goal, HORIZONTAL_ALIGNMENT_LEFT, -1, goal_size).x
	var under_w: float = font.get_string_size(under, HORIZONTAL_ALIGNMENT_LEFT, -1, under_size).x
	var block_w: float = maxf(goal_w, under_w) + pad * 2.0
	var block_h: float = float(goal_size) + float(under_size) + pad * 2.0
	var bx: float = (size.x - block_w) * 0.5
	var by: float = size.y - CHIP_ROW_GAP - block_h
	_overlay_draw.draw_rect(Rect2(bx, by, block_w, block_h), CAPTION_PANEL_COLOR)
	_overlay_draw.draw_rect(Rect2(bx, by, 3.0, block_h), REC_COLOR)
	_overlay_draw.draw_string(
		font, Vector2(bx + pad, by + pad + float(goal_size) * 0.78), goal,
		HORIZONTAL_ALIGNMENT_LEFT, -1, goal_size, Color(0.99, 0.95, 0.74)
	)
	_overlay_draw.draw_string(
		font, Vector2(bx + pad, by + pad + float(goal_size) + float(under_size) * 0.82), under,
		HORIZONTAL_ALIGNMENT_LEFT, -1, under_size, Color(0.74, 0.87, 0.99)
	)

	# Held-input chips, centred under the caption.
	# _held is keyed by label, so take the keys once: indexing it positionally
	# throws inside the draw callback, and everything after the throw - the
	# sentinels included - silently stops rendering.
	var labels: Array = _held.keys()
	if not labels.is_empty():
		var widths: Array = []
		var total := 0.0
		for label in labels:
			var w: float = font.get_string_size(
				String(label), HORIZONTAL_ALIGNMENT_LEFT, -1, CHIP_FONT_SIZE
			).x + 30.0
			widths.append(w)
			total += w + 10.0
		var cx: float = (size.x - total) * 0.5
		for i in range(labels.size()):
			var w2: float = widths[i]
			var chip := Rect2(cx, size.y - CHIP_ROW_GAP + 14.0, w2, CHIP_HEIGHT)
			_overlay_draw.draw_rect(chip, CHIP_PANEL_COLOR)
			_overlay_draw.draw_rect(chip, CURSOR_COLOR, false, 2.0)
			_overlay_draw.draw_string(
				font, Vector2(cx + 15.0, chip.position.y + 24.0), String(labels[i]),
				HORIZONTAL_ALIGNMENT_LEFT, -1, CHIP_FONT_SIZE, Color(1, 1, 1, 0.97)
			)
			cx += w2 + 10.0

	# REC: a dot and a word, no box, bottom-left as the spike had it. Top-left is
	# where games put their own debug text - Godotcraft's "Press ` to toggle this
	# panel" ran straight through the badge - and the corner under the caption is
	# the one place nothing competes for.
	var rec_y := size.y - OVERLAY_PAD - 7.0
	_overlay_draw.draw_circle(
		Vector2(OVERLAY_PAD + 7.0, rec_y), 7.0,
		Color(0.55, 0.55, 0.6) if frozen else REC_COLOR
	)
	# The word sits on raw gameplay with no panel behind it, so it needs its own
	# contrast: white on Godotcraft's lit grass was unreadable without this.
	var rec_label := "PAUSED" if frozen else "REC"
	_overlay_draw.draw_string(
		font, Vector2(OVERLAY_PAD + 23.0, rec_y + 8.0), rec_label,
		HORIZONTAL_ALIGNMENT_LEFT, -1, CHIP_FONT_SIZE, Color(0, 0, 0, 0.55)
	)
	_overlay_draw.draw_string(
		font, Vector2(OVERLAY_PAD + 22.0, rec_y + 7.0), rec_label,
		HORIZONTAL_ALIGNMENT_LEFT, -1, CHIP_FONT_SIZE, Color(1, 1, 1, 0.93)
	)

	# Sentinel strips: the ONLY thing the e2e reads by coordinate. Opaque, so a
	# lossy JPEG keeps their colour; tiny, so they cost the viewer nothing. The
	# overlay above is now free to be designed for a person instead of a probe.
	_overlay_draw.draw_rect(Rect2(SENTINEL_X, SENTINEL_Y, SENTINEL_W, SENTINEL_H), PANEL_COLOR)
	if not labels.is_empty():
		_overlay_draw.draw_rect(
			Rect2(SENTINEL_X + SENTINEL_W + 8.0, SENTINEL_Y, SENTINEL_W, SENTINEL_H), CHIP_COLOR
		)
	# Recording state gets a sentinel of its own so the gate never has to sample
	# the badge itself - that coupling is what dragged the badge into the corner
	# a game was already using.
	if not frozen:
		_overlay_draw.draw_rect(
			Rect2(SENTINEL_X + (SENTINEL_W + 8.0) * 2.0, SENTINEL_Y, SENTINEL_W, SENTINEL_H),
			REC_COLOR
		)


## Redraw only when the overlay would come out different. It is drawn every DRAWN
## frame, and the game samples input on those same frames - repainting an
## identical picture 60 times a second takes render budget straight out of the
## game it is filming. Compared field by field rather than through a formatted
## key: building one string per frame cost more than the repaint it saved.
func _overlay_dirty() -> bool:
	var cursor: Vector2i = Vector2i(get_viewport().get_mouse_position())
	var frozen := get_tree().paused
	if (
		cursor == _sig_cursor
		and _held.size() == _sig_held
		and _intent.length() == _sig_intent
		and _ripples.size() == _sig_ripples
		and frozen == _sig_frozen
	):
		return false
	_sig_cursor = cursor
	_sig_held = _held.size()
	_sig_intent = _intent.length()
	_sig_ripples = _ripples.size()
	_sig_frozen = frozen
	return true


## Largest size at or below `base` whose string fits `limit`, floored at
## CAPTION_FONT_MIN. Memoised because it runs per caption line per DRAWN frame,
## and the search is a get_string_size call per step: uncached it cost measured
## render frames (94 against a floor of 100 in the gate's paused-cap arm).
func _fit_caption(font: Font, text: String, limit: float, base: int) -> int:
	var key := "%s|%d|%d" % [text, int(limit), base]
	if _caption_fit.has(key):
		return int(_caption_fit[key])
	var size_px := base
	while size_px > CAPTION_FONT_MIN:
		if font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, size_px).x <= limit:
			break
		size_px -= 1
	# The caption text changes with the act, not the frame, so this stays tiny;
	# the clear keeps a long run from accumulating one entry per distinct goal.
	if _caption_fit.size() > 64:
		_caption_fit.clear()
	_caption_fit[key] = size_px
	return size_px


# The caption is FITTED, never clipped. draw_string's width just cuts the glyphs
# off at the edge, so a goal one word too long ends mid-word and the reader
# cannot tell whether they are seeing all of it - and the Game tab, which sizes
# this overlay, gets narrower the more docks the user opens. The size steps down
# until the string fits; only a goal too long even at CAPTION_FONT_MIN is
# trimmed, and then with an ellipsis, which SAYS there is more.
func _draw_caption(font: Font, y: float, limit: float, text: String, color: Color) -> void:
	var width := limit - OVERLAY_PAD
	var size := CAPTION_FONT_SIZE
	while (
		size > CAPTION_FONT_MIN
		and font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, size).x > width
	):
		size -= 2
	var line := TextLine.new()
	line.add_string(text, font, size)
	line.width = width
	line.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	# TextLine draws from the top of its line box; draw_string drew from the
	# baseline, and every caption's y is a baseline.
	line.draw(_overlay_draw.get_canvas_item(), Vector2(OVERLAY_PAD, y - line.get_line_ascent()), color)


func _input_line(cursor: Vector2) -> String:
	var held := "nothing held" if _held.is_empty() else ", ".join(PackedStringArray(_held.keys()))
	return "game receives: %s | pointer %d,%d" % [held, int(cursor.x), int(cursor.y)]


# One press/hold/release cycle, counted in PHYSICS frames rather than wall-clock
# or render frames: an op has to be reproducible, and the fixed physics tick is
# the unit the game itself samples input in - render frames move with how fast
# the machine draws (see MIN_HOLD_FRAMES).
#
# `sustain` leaves the input DOWN when the act ends, and `release` lets a later
# act lift it. Without that, a mechanic needing a hold longer than one act was
# unreachable: every act released everything at its end, so a game that
# accumulates while held and decays while not (mining, a charged attack, a drawn
# bow, aim-down-sights) reset between acts and could never finish. Measured on
# Godotcraft: 301 frames of holding got mining to 1.9 of the 4.5 it needed, and
# the next act started from 0.667 and then 0.
#
# With `wait_active` (the act carries an `until`), a pressable input does not
# hold-and-release here at all: it stays DOWN for the whole wait and _op_act
# lifts it when the wait resolves. The old shape - release at hold_frames, then
# keep waiting - left the wait watching a game nobody was driving, which is why
# 0 of 13 historical travel attempts ever arrived.
func _deliver(entry: Dictionary, wait_active: bool) -> Dictionary:
	var label := _label(entry)
	var kind := String(entry.get("type", "action"))
	if bool(entry.get("release", false)):
		if not _sustained.has(label):
			return {
				"label": label,
				"type": kind,
				"dropped": (
					"nothing to release: %s is not being held. Held right now: %s"
					% [label, str(_sustained.keys())]
				),
			}
		await _dispatch_input(_sustained[label], false)
		await get_tree().physics_frame
		_sustained.erase(label)
		return {
			"label": label,
			"type": kind,
			"released": true,
			"release_frame": Engine.get_physics_frames() - _start_frame,
		}

	# A servo is a whole closed loop, not an edge pair: it presses and releases
	# its own inputs until the probed value sits on the target. Self-contained
	# like a drag, so `until` auto-holding does not apply to it.
	if kind == "servo":
		return await _dispatch_servo(entry, label)

	# A drag is one gesture, not three inputs the caller has to assemble: press,
	# absolute-position motion interpolated across frames while held, release at
	# the end point. It spans frames itself, so it cannot go through the
	# press/hold/release path below.
	#
	# It exists because tool affordances shape behaviour. Games commonly poll
	# `get_viewport().get_mouse_position()` for aiming and treat the drag as their
	# PRIMARY control, with keys as a coarse fallback - and for twelve runs this
	# harness offered easy keys and no drag at all, so every run used the fallback
	# and inherited its granularity.
	if kind == "drag":
		return await _dispatch_drag(entry, label)

	# Aligned to the physics tick before dispatching, so every press lands at the
	# same point in a tick and N identical taps poll identically - a press issued
	# mid-tick loses part of its first tick (measured: [3,4,4] for three
	# identical 4-frame taps, the first dispatched straight out of the freeze).
	await get_tree().physics_frame
	var press_frame := Engine.get_physics_frames() - _start_frame
	var dropped: String = await _dispatch_input(entry, true)
	if dropped != "":
		return {"label": label, "type": kind, "dropped": dropped}
	var record := {
		"label": label,
		"type": kind,
		"press_frame": press_frame,
	}
	if kind == "motion":
		record["released"] = false  # edgeless: a motion event has no release
		return record
	if wait_active:
		if bool(entry.get("sustain", false)):
			_sustained[label] = entry.duplicate()
			record["released"] = false
			record["sustained"] = true
			return record
		_wait_held[label] = entry.duplicate()
		record["released"] = false
		record["held_for_wait"] = true
		return record
	var hold: int = maxi(int(entry.get("hold_frames", MIN_HOLD_FRAMES)), MIN_HOLD_FRAMES)
	var held := 0
	while held < hold:
		await get_tree().physics_frame
		held += 1
	record["hold_frames"] = held
	if bool(entry.get("sustain", false)):
		_sustained[label] = entry.duplicate()
		record["released"] = false
		record["sustained"] = true
		return record
	await _dispatch_input(entry, false)
	await get_tree().physics_frame
	record["released"] = true
	record["release_frame"] = Engine.get_physics_frames() - _start_frame
	return record


# Lift everything the act auto-held for its `until` wait, stamping the release
# into each entry's delivery record so the trace shows the hold's true length.
# Returns whether anything was lifted.
func _release_wait_held(delivered: Array) -> bool:
	if _wait_held.is_empty():
		return false
	for label in _wait_held.keys():
		await _dispatch_input(_wait_held[label], false)
		for record in delivered:
			if record.get("label") == label and bool(record.get("held_for_wait", false)):
				record["released"] = true
				record["release_frame"] = Engine.get_physics_frames() - _start_frame
				record["hold_frames"] = int(record["release_frame"]) - int(record["press_frame"])
	_wait_held.clear()
	await get_tree().physics_frame
	return true


# Resolve a drag endpoint: either explicit viewport pixels, or the centre of a
# Control, or the projected screen position of a 3D point the caller names.
func _drag_point(entry: Dictionary, key: String) -> Variant:
	var spec: Variant = entry.get(key)
	if spec is Dictionary and (spec as Dictionary).has("x") and (spec as Dictionary).has("y"):
		return Vector2(float(spec["x"]), float(spec["y"]))
	if spec is String:
		var control: Control = _resolve_target(String(spec))
		if control == null:
			return "no Control matched %s '%s'" % [key, String(spec)]
		return control.get_global_rect().get_center()
	return "drag needs %s as {\"x\":<px>,\"y\":<px>} or a Control name" % key


# Press at `from`, glide to `to` across `frames`, release. Every step sends the
# ABSOLUTE position, because a game that polls get_viewport().get_mouse_position()
# never sees `relative` at all - the existing `motion` type is relative-only and
# pins position to the viewport centre, which such a game reads as "the cursor
# never moved".
func _dispatch_drag(entry: Dictionary, label: String) -> Dictionary:
	var from_point: Variant = _drag_point(entry, "from")
	if from_point is String:
		return {"label": label, "type": "drag", "dropped": from_point}
	var to_point: Variant = _drag_point(entry, "to")
	if to_point is String:
		return {"label": label, "type": "drag", "dropped": to_point}
	var start: Vector2 = from_point
	var end: Vector2 = to_point
	var steps: int = maxi(int(entry.get("frames", 12)), 2)
	var button: MouseButton = _button_index(entry)

	var press_frame := Engine.get_physics_frames() - _start_frame
	_move_mouse(start, Vector2.ZERO)
	await get_tree().physics_frame
	_click_at(start, button, true)
	await get_tree().physics_frame

	var previous := start
	for step in range(1, steps + 1):
		var point: Vector2 = start.lerp(end, float(step) / float(steps))
		_move_mouse(point, point - previous)
		previous = point
		await get_tree().physics_frame

	# Held for however long the caller asked beyond the glide, so a game that
	# needs to settle its aim before the release gets those frames.
	var extra: int = maxi(int(entry.get("hold_frames", 0)), 0)
	for _i in range(extra):
		await get_tree().physics_frame

	if bool(entry.get("sustain", false)):
		_sustained[label] = {"type": "mouse", "button": entry.get("button", "left"), "x": end.x, "y": end.y}
		return {
			"label": label,
			"type": "drag",
			"press_frame": press_frame,
			"from": [start.x, start.y],
			"to": [end.x, end.y],
			"frames": steps,
			"released": false,
			"sustained": true,
		}
	_click_at(end, button, false)
	await get_tree().physics_frame
	return {
		"label": label,
		"type": "drag",
		"press_frame": press_frame,
		"release_frame": Engine.get_physics_frames() - _start_frame,
		"from": [start.x, start.y],
		"to": [end.x, end.y],
		"frames": steps,
		"released": true,
	}


# Signed distance from value to target. With `wrap` (e.g. TAU for radians) the
# error is folded into [-wrap/2, wrap/2], so an angular servo takes the short
# way round instead of unwinding a whole turn.
func _servo_error(target: float, value: float, wrap: float) -> float:
	if wrap > 0.0:
		return wrapf(target - value, -wrap / 2.0, wrap / 2.0)
	return target - value


# Closed-loop input: drive a probed value onto a target using a pair of held
# inputs. This is the loop a caller otherwise runs across ops - press, re-probe,
# correct - moved to frame speed: at op speed it costs two tool calls per
# correction and the caller has to know the per-tap quantum, here neither is
# needed. Bang-bang: hold whichever input shrinks the error, release on
# tolerance or overshoot, settle a frame, pulse again. Sampled per PROCESS
# frame, the fastest the engine exposes, so the release lands within one frame
# of the value crossing the band - open-loop taps cannot do better than their
# whole-tick quantum.
func _dispatch_servo(entry: Dictionary, label: String) -> Dictionary:
	for field in ["probe", "target", "increase", "decrease"]:
		if not entry.has(field):
			return {
				"label": label,
				"type": "servo",
				"dropped": "a servo needs '%s' (got keys %s)" % [field, str(entry.keys())],
			}
	var probe_expr := String(entry["probe"])
	# Models keep sending the computed target as a quoted number - measured
	# "-0.507" x5 and "2.077" x75 across two real runs, each a spiral of
	# identical refusals. A string that IS a number is accepted as the number it
	# names; only a genuine non-number is refused, by type.
	if entry["target"] is String and String(entry["target"]).is_valid_float():
		entry["target"] = String(entry["target"]).to_float()
	if not _is_number(entry["target"]):
		return {
			"label": label,
			"type": "servo",
			"dropped": (
				"servo target must be a JSON number, got the %s %s"
				% [type_string(typeof(entry["target"])), str(entry["target"])]
			),
		}
	var target := float(entry["target"])
	var tolerance: float = absf(float(entry.get("tolerance", 0.01)))
	var wrap := float(entry.get("wrap", 0.0))
	var budget: int = maxi(int(entry.get("max_physics_frames", 600)), 1)
	var start_physics := Engine.get_physics_frames()
	var deadline := Time.get_ticks_msec() + UNTIL_WALL_CLOCK_BUDGET_MS

	var first := _eval_raw(probe_expr)
	if first.has("error"):
		return {"label": label, "type": "servo", "dropped": "servo probe: " + String(first["error"])}
	if not _is_number(first["value"]):
		return {
			"label": label,
			"type": "servo",
			"dropped": (
				"servo probe '%s' evaluates to %s - a servo can only drive a number"
				% [probe_expr, str(first["value"])]
			),
		}
	var value: float = float(first["value"])
	var start_value := value
	var pulses := 0
	var held := {}  # the increase/decrease entry currently pressed
	var held_sign := 0
	var pulse_error := 0.0  # |error| when the current pulse began
	var last_value := value
	var last_moved_physics := start_physics
	var settled := 0
	var fail := ""

	while true:
		if Engine.get_physics_frames() - start_physics >= budget:
			fail = "ran out of frames"
			break
		if Time.get_ticks_msec() >= deadline:
			fail = "ran out of wall clock (%ds)" % (UNTIL_WALL_CLOCK_BUDGET_MS / 1000)
			break
		var probed := _eval_raw(probe_expr)
		if probed.has("error"):
			fail = "the probe stopped evaluating mid-servo: " + String(probed["error"])
			break
		value = float(probed["value"])
		var error := _servo_error(target, value, wrap)
		# An EDGELESS channel (relative mouse motion - a captured first-person
		# camera reads nothing else) has no held state to bang-bang: a pulse
		# EMITS one scaled delta instead, and the closed loop absorbs the game's
		# unknown sensitivity. Measured before this mode existed: a servo aimed
		# at a mouse-look yaw could not deliver at all - the single reason 3D
		# navigation failed where a keyboard-turned camera succeeded.
		var side: Dictionary = (entry["increase"] if error > 0.0 else entry["decrease"]) as Dictionary
		if held.is_empty() and String(side.get("type", "action")) == "motion":
			if absf(error) <= tolerance:
				settled += 1
				if settled >= 2:
					break
				await get_tree().process_frame
				continue
			settled = 0
			var sign_now := 1 if error > 0.0 else -1
			if sign_now != held_sign:
				held_sign = sign_now
				pulse_error = absf(error)
			if value != last_value:
				last_moved_physics = Engine.get_physics_frames()
			elif pulses > 0 and Engine.get_physics_frames() - last_moved_physics >= SERVO_STALL_FRAMES:
				return {
					"label": label,
					"type": "servo",
					"dropped": (
						"%d motion pulses over %d physics frames never moved '%s' from %s. "
						% [pulses, SERVO_STALL_FRAMES, probe_expr, str(value)]
						+ "This channel does not drive that probe: find the one the game "
						+ "actually reads (grep its input handling), or the value this "
						+ "channel does change."
					),
				}
			if absf(error) > pulse_error + maxf(tolerance * 4.0, 0.000001):
				return {
					"label": label,
					"type": "servo",
					"dropped": (
						"the %s motion pulses made the error GROW (|%.4f| -> |%.4f| against target %s): "
						% [
							"increase" if held_sign > 0 else "decrease",
							pulse_error,
							absf(error),
							str(target),
						]
						+ "the increase/decrease pair is inverted for '%s'. Swap them and servo again."
						% probe_expr
					),
				}
			last_value = value
			# The caller's dx/dy is the LARGEST pulse; near the target it scales
			# down so one pulse cannot fly across the tolerance band.
			var factor := clampf(absf(error) / maxf(tolerance * 8.0, 0.000001), 0.05, 1.0)
			var pulse := side.duplicate()
			pulse["dx"] = float(side.get("dx", 0)) * factor
			pulse["dy"] = float(side.get("dy", 0)) * factor
			var dropped_pulse := _dispatch_edge(pulse, true)
			if dropped_pulse != "":
				return {"label": label, "type": "servo", "dropped": "servo motion pulse: " + dropped_pulse}
			pulses += 1
			await get_tree().process_frame
			continue
		if held.is_empty():
			if absf(error) <= tolerance:
				settled += 1
				if settled >= 2:
					break
			else:
				settled = 0
				held_sign = 1 if error > 0.0 else -1
				held = (entry["increase"] if held_sign > 0 else entry["decrease"]) as Dictionary
				var dropped := _dispatch_edge(held, true)
				if dropped != "":
					return {
						"label": label,
						"type": "servo",
						"dropped": (
							"servo %s input: %s"
							% ["increase" if held_sign > 0 else "decrease", dropped]
						),
					}
				pulses += 1
				pulse_error = absf(error)
				last_value = value
				last_moved_physics = Engine.get_physics_frames()
		else:
			if value != last_value:
				last_moved_physics = Engine.get_physics_frames()
			elif Engine.get_physics_frames() - last_moved_physics >= SERVO_STALL_FRAMES:
				_dispatch_edge(held, false)
				return {
					"label": label,
					"type": "servo",
					"dropped": (
						"the %s input was held %d physics frames and '%s' never moved from %s. "
						% [
							"increase" if held_sign > 0 else "decrease",
							SERVO_STALL_FRAMES,
							probe_expr,
							str(value),
						]
						+ "This input does not drive that probe: find the channel the game "
						+ "actually reads (grep its input handling), or the value this input "
						+ "does change."
					),
				}
			last_value = value
			if absf(error) <= tolerance or signf(error) != float(held_sign):
				_dispatch_edge(held, false)
				held = {}
			elif absf(error) > pulse_error + maxf(tolerance * 4.0, 0.000001):
				_dispatch_edge(held, false)
				return {
					"label": label,
					"type": "servo",
					"dropped": (
						"holding the %s input made the error GROW (|%.4f| -> |%.4f| against target %s): "
						% [
							"increase" if held_sign > 0 else "decrease",
							pulse_error,
							absf(error),
							str(target),
						]
						+ "the increase/decrease pair is inverted for '%s'. Swap them and servo again."
						% probe_expr
					),
				}
		await get_tree().process_frame

	if not held.is_empty():
		_dispatch_edge(held, false)
		await get_tree().physics_frame
	if fail != "":
		return {
			"label": label,
			"type": "servo",
			"dropped": (
				"servo on '%s' %s: start %s, end %s (target %s +/- %s) after %d pulses and %d physics frames. "
				% [
					probe_expr,
					fail,
					str(start_value),
					str(value),
					str(target),
					str(tolerance),
					pulses,
					Engine.get_physics_frames() - start_physics,
				]
				+ "If it was oscillating, the tolerance is finer than this input's smallest "
				+ "step - widen it; if it was still converging, raise max_physics_frames."
			),
		}
	return {
		"label": label,
		"type": "servo",
		"probe": probe_expr,
		"start": start_value,
		"end": value,
		"target": target,
		"tolerance": tolerance,
		"satisfied": true,
		"pulses": pulses,
		"physics_frames": Engine.get_physics_frames() - start_physics,
		"press_frame": start_physics - _start_frame,
		"release_frame": Engine.get_physics_frames() - _start_frame,
		"released": true,
	}


# Move the pointer to an absolute position, both ways, because games read it two
# different ways and only one of them is an event.
#
# `warp_mouse` is the load-bearing half: `get_viewport().get_mouse_position()`
# reports where the real cursor is, and a synthesized InputEventMouseMotion does
# NOT move it however carefully `position` is set. A game that polls the cursor
# while a button is held - which is every slingshot aim, every drawing tool -
# sees a parsed-only event as no movement at all. Measured: with the event alone
# the fixture's drag distance stayed exactly 0 across a full 10-frame gesture.
#
# The parsed event is still sent, for the games that listen for `relative`
# instead (a captured first-person camera reads nothing else). Its coordinates
# are WINDOW pixels like a real device's - see _click_at.
func _move_mouse(position: Vector2, relative: Vector2) -> void:
	# Seated, the SubViewport tracks the pointer from the motion event below, so
	# warping is both unnecessary and the exact thing that steals the user's
	# cursor. Unseated, the warp is still load-bearing (see the note above).
	if _seat == null:
		Input.warp_mouse(_to_window(position))
	var motion := InputEventMouseMotion.new()
	motion.position = _to_window(position)
	motion.global_position = motion.position
	motion.relative = _to_window(relative)
	_inject(motion)


# Callers speak VIEWPORT pixels - the space `unproject_position`, Control rects
# and `get_viewport().get_mouse_position()` all use. `warp_mouse` speaks WINDOW
# pixels, and the two differ whenever the window is not the viewport's size: a
# 900px-tall window showing a 1080px viewport scales every coordinate by 1.2, so
# a drag aimed at the ball landed 170px below it and the game never saw the grab.
func _to_window(position: Vector2) -> Vector2:
	var viewport_size: Vector2 = get_viewport().get_visible_rect().size
	if viewport_size.x <= 0.0 or viewport_size.y <= 0.0:
		return position
	var window: Window = get_window()
	if window == null:
		return position
	var window_size: Vector2 = Vector2(window.size)
	return Vector2(
		position.x * window_size.x / viewport_size.x,
		position.y * window_size.y / viewport_size.y
	)


# A game must never be left with a key stuck down: the next session, or the
# player who takes the editor back, would inherit it.
func _release_all_sustained() -> Array:
	var lifted: Array = []
	for label in _sustained.keys():
		await _dispatch_input(_sustained[label], false)
		lifted.append(label)
	_sustained.clear()
	if not lifted.is_empty():
		await get_tree().physics_frame
	return lifted


func _op_act(msg: Dictionary) -> Dictionary:
	_intent = String(msg.get("intent", ""))
	var probes: Array = msg.get("probes", [])
	var before := _eval_all(probes)
	var world_before := _world_snapshot()
	var bad := _first_probe_error(before)
	if bad != "":
		return {"ok": false, "error": bad}

	var until_spec: Dictionary = msg.get("until", {})
	var until := String(until_spec.get("expression", ""))
	var baseline: Variant = null
	if until != "":
		var probed := _eval(until)
		if probed.has("error"):
			return {"ok": false, "error": "until: " + String(probed["error"])}
		baseline = probed["value"]

	var start := Engine.get_physics_frames()
	_thaw()
	_foreign_in_act = 0
	_foreign_labels = []
	var delivered: Array = []
	for entry in msg.get("inputs", []):
		delivered.append(await _deliver(entry, until != ""))

	# An undeliverable input makes the whole act a lie: the rest of the sequence
	# ran against a state the caller never asked for. Say so instead of returning
	# probe values that look like the game misbehaved. Anything already pressed
	# for the wait is lifted first - a refused act must not leave keys down.
	for record in delivered:
		if record.has("dropped"):
			await _release_wait_held(delivered)
			_freeze()
			return {
				"ok": false,
				"error": (
					"input %s could not be delivered: %s" % [record["label"], record["dropped"]]
				),
				"delivered": delivered,
			}

	# Sampled at the release edge, because "ended lower than it started" cannot
	# tell a decaying hold from an input that simply drives the value DOWN - a left
	# turn lowering a camera angle, a restart zeroing a stroke count. Both read
	# identically at the act boundary, and calling the second one a decay told one
	# real run "more acts can never finish this" 23 times while it was aiming
	# correctly. Only a value that ROSE while held and FELL once let go is the
	# mechanic this warning is for. For an `until` act the release edge is where
	# the wait resolves, so the sample happens after the wait below instead.
	var released_something := false
	for record in delivered:
		if bool(record.get("released", false)) and record.has("press_frame"):
			released_something = true
	var at_release := {}
	if released_something and _sustained.is_empty():
		at_release = _eval_all(probes)

	var satisfied := false
	var satisfied_at_release := false
	var waited := 0
	var exhausted_wall_clock := false
	var settled: Variant = baseline
	if until != "":
		var budget := int(until_spec.get("timeout_frames", 0))
		var deadline := Time.get_ticks_msec() + UNTIL_WALL_CLOCK_BUDGET_MS
		while true:
			var probed := _eval(until)
			if probed.has("error"):
				await _release_wait_held(delivered)
				_freeze()
				return {"ok": false, "error": "until stopped evaluating mid-act: " + String(probed["error"])}
			settled = probed["value"]
			# Truthiness, not change-from-baseline: a predicate that is ALREADY
			# true - including immediately after the inputs land - is satisfied
			# now, not after a timeout spent waiting for it to become false.
			if _truthy(settled):
				satisfied = true
				break
			if waited >= budget:
				break
			# timeout_frames bounds frames, not time, and a frame costs whatever
			# this game costs. Without a wall-clock stop a heavy game can spend
			# longer here than the session is willing to wait, and then the op
			# deadline fires while this loop still holds `_serving` - so the
			# harness stops reading the socket and every later op dies too.
			if Time.get_ticks_msec() >= deadline:
				exhausted_wall_clock = true
				break
			await get_tree().physics_frame
			waited += 1
		# The wait is over, however it ended: lift the inputs it was holding, and
		# sample the release edge now that it exists.
		var lifted_for_wait := await _release_wait_held(delivered)
		if lifted_for_wait and _sustained.is_empty():
			at_release = _eval_all(probes)
		if not satisfied and lifted_for_wait:
			# A release-triggered mechanic - a Button firing on release, a throw
			# on letting go - can only come true AFTER the wait lets its inputs
			# go, so a timeout gets one look at the release edge before it is
			# reported as a failure.
			await get_tree().physics_frame
			var post := _eval(until)
			if not post.has("error") and _truthy(post["value"]):
				settled = post["value"]
				satisfied = true
				satisfied_at_release = true
	else:
		for i in range(int(msg.get("advance_frames", 0))):
			await get_tree().physics_frame
	_freeze()

	var after := _eval_all(probes)
	var world_after := _world_snapshot()
	var world := _world_diff(world_before, world_after)
	var changes: Array = world["lines"]
	var probes_moved := JSON.stringify(after) != JSON.stringify(before)
	var reply := {
		"ok": true,
		"delivered": delivered,
		"frames_advanced": Engine.get_physics_frames() - start,
		"probes_before": before,
		"probes_after": after,
		# Three states, not two. `world_only` is the one that matters: the act DID
		# something, the probes chosen just could not see it. Reporting that as
		# "none" is what teaches an agent to call a working mechanic broken.
		"effect": (
			"observed" if probes_moved
			else ("world_only" if bool(world["moved"]) else "none")
		),
		"world_changed": changes,
		# A first-person game typically gates ALL movement and mining on having the
		# mouse captured, and releases it whenever it opens a menu. When that
		# happens every later input lands and does nothing, which reads exactly
		# like a broken game - a false "fail" is the worst answer a QA agent can
		# give - so the caller is told the mode rather than left to infer it.
		"mouse_mode": int(Input.mouse_mode),
	}
	# What is STILL down when this act ends. Without it the caller cannot tell a
	# sustained hold from a finished one, and a stuck input is invisible.
	if not _sustained.is_empty():
		reply["still_held"] = _sustained.keys()

	# Foreign input DURING an act is reported and survivable, unlike the frozen
	# case: the world was moving anyway, and a run costs up to $1 and 250 tool
	# calls - one stray keypress that changed nothing must not kill it. But the
	# caller has to be told, because it is the one explanation for a surprising
	# act that no probe value can ever show.
	if _foreign_in_act > 0:
		reply["foreign_input"] = {
			"count": _foreign_in_act,
			"what": _foreign_labels,
			"why": (
				"input this session did not send reached the game while this act ran - somebody "
				+ "touched the game under test. Anything unexpected in this act may be theirs "
				+ "rather than the game's; if it decided your finding, report `blocked` and say "
				+ "the game was touched instead of blaming the game."
			),
		}

	# A value that builds while an input is held and falls once it is let go is the
	# fingerprint of a hold-driven mechanic - and this act just let go of it. The
	# world is frozen BETWEEN acts, so the fall happens inside the act, after the
	# release edge: exactly what Godotcraft's mining did (1.9 -> 0.667 -> 0). The
	# model cannot infer "splitting this across acts is futile" from a number
	# going down, so name it.
	# Only a press-and-release inside THIS act counts. An explicit release:true is
	# the caller deliberately letting go, and telling them they let go too early
	# would be noise.
	var decayed: Array = []
	for key in at_release:
		if not before.has(key) or not after.has(key):
			continue
		var was_v: Variant = (before[key] as Dictionary).get("value")
		var peak_v: Variant = (at_release[key] as Dictionary).get("value")
		var now_v: Variant = (after[key] as Dictionary).get("value")
		if not _is_number(was_v) or not _is_number(peak_v) or not _is_number(now_v):
			continue
		if float(peak_v) > float(was_v) and float(now_v) < float(peak_v):
			decayed.append({
				"probe": key,
				"at_press": was_v,
				"at_release": peak_v,
				"after_release": now_v,
			})
	if not decayed.is_empty():
		reply["decayed_after_release"] = {
			"probes": decayed,
			"why": (
				"these rose while the input was held and fell back once it was released. That is "
				+ "what a hold-driven mechanic does when the hold ends, and every input is released "
				+ "when its act ends unless you pass sustain - so spending more acts on it can never "
				+ "finish it. Press the input once with \"sustain\": true, keep observing while it "
				+ "runs, then send the same input with \"release\": true when done."
			),
		}
	if until != "":
		reply["until"] = {
			"expression": until,
			"satisfied": satisfied,
			"frames_waited": waited,
			"before": baseline,
			"after": settled,
		}
		if satisfied_at_release:
			reply["until"]["satisfied_at_release"] = (
				"the expression became true only once the inputs were RELEASED at the end of the "
				+ "wait - this game reacts to the release edge (a Button fires on release, a throw "
				+ "happens on letting go). Next time make it two calls: the click in one act, the "
				+ "until wait in the next with no inputs, and it will resolve without burning the "
				+ "timeout."
			)
		# A timeout must say what call WOULD work, not just that this one did not.
		if not satisfied:
			var held_labels: Array = []
			for record in delivered:
				if bool(record.get("held_for_wait", false)) or bool(record.get("sustained", false)):
					held_labels.append(record.get("label"))
			if held_labels.is_empty():
				reply["until"]["suggestion"] = (
					"nothing was held while this waited (drags and motions end on their own). If "
					+ "the game needs an input held while the condition ripens - walking, holding "
					+ "to mine - send that input IN THIS SAME CALL: it will stay pressed for the "
					+ "whole wait automatically."
				)
			else:
				reply["until"]["suggestion"] = (
					"%s stayed held for the entire %d-frame wait and the expression still never "
					% [str(held_labels), waited]
					+ "became true (it ended at %s). Either these inputs do not drive what it "
					% JSON.stringify(_jsonable(settled))
					+ "watches - probe something this input must change to find out - or the goal "
					+ "needs longer: retry with timeout_frames %d." % maxi(int(until_spec.get("timeout_frames", 0)) * 2, 60)
				)
		if exhausted_wall_clock:
			reply["until"]["stopped"] = (
				"wall clock: only %d of the %d requested physics frames fit in %ds, because a "
				% [waited, int(until_spec.get("timeout_frames", 0)), UNTIL_WALL_CLOCK_BUDGET_MS / 1000]
				+ "frame of this game costs more than the wait assumed. Ask for fewer "
				+ "timeout_frames, or split the goal into steps."
			)
	return reply


# ------------------------------------------------------------------- drivers
#
# game_drive: the caller submits a GDScript function body and the harness runs
# it against a constrained api - input injection, read-only eval, frame waits -
# so a control loop an LLM can describe but not execute across ops runs at code
# speed instead. GDScript cannot hide the engine's globals from the body, so
# the sandbox is not scope: it is the same state digest probes answer to, taken
# as each api call begins and ends. The body's own code runs synchronously
# between awaits - the tree cannot advance under it - so digest drift between
# one api call's end and the next one's start is something the body did to the
# game directly, and physics frames passing there mean the body awaited the
# engine behind the api's back. Both poison the run exactly like a mutating
# probe. (A body determined enough to also rewrite the api's own bookkeeping
# could launder that; the drive source is recorded verbatim in the evidence
# bundle, so even that leaves its fingerprints where the reconciler reads.)
class DriveApi:
	var _h: Node
	var calls: Array = []
	var logs: Array = []
	var held: Dictionary = {}
	var fault := ""
	# run() has returned: a coroutine the body abandoned without `await` must do
	# nothing more when it resumes.
	var dead := false
	# Api calls entered but never finished. Non-zero once run() returns means the
	# body called an async api function without `await` - a zombie coroutine that
	# would otherwise keep injecting input into later ops.
	var unfinished := 0
	var start_physics: int
	var frame_budget: int
	var deadline_ms: int
	var last_digest: int
	var last_physics: int

	func _init(harness: Node, budget: int) -> void:
		_h = harness
		frame_budget = budget
		start_physics = Engine.get_physics_frames()
		last_physics = start_physics
		deadline_ms = Time.get_ticks_msec() + harness.UNTIL_WALL_CLOCK_BUDGET_MS
		last_digest = harness._state_digest()

	# Every api call passes through here first. The digest/frame comparison
	# against the previous call's exit is the sandbox described above.
	func _enter(name: String, summary: String) -> bool:
		if dead:
			return false
		calls.append({
			"call": name,
			"args": summary.left(160),
			"physics_frame": Engine.get_physics_frames() - _h._start_frame,
		})
		if fault != "":
			return false
		var physics_now := Engine.get_physics_frames()
		if physics_now != last_physics:
			fault = (
				"the drive body let the game run outside its api: %d physics frame(s) passed "
				% (physics_now - last_physics)
				+ "between api calls (a raw `await` on an engine signal?). The harness cannot "
				+ "attribute what happened during frames it did not run, so this session is "
				+ "tainted: start a new one and keep every wait inside api.until / "
				+ "api.wait_physics."
			)
			_h._tainted = fault
			return false
		if _h._state_digest() != last_digest:
			fault = (
				"the drive body CHANGED the game between api calls (declared state digest "
				+ "moved with no frame advanced). A drive may act on the game only through its "
				+ "api; setting a variable or calling a mutating method destroys the evidence "
				+ "like a mutating probe does. This session can no longer settle anything: "
				+ "start a new one."
			)
			_h._tainted = fault
			return false
		if physics_now - start_physics >= frame_budget:
			fault = "the drive's %d-physics-frame budget is exhausted" % frame_budget
			return false
		if Time.get_ticks_msec() >= deadline_ms:
			fault = "the drive ran out of wall clock (%ds)" % (_h.UNTIL_WALL_CLOCK_BUDGET_MS / 1000)
			return false
		unfinished += 1
		return true

	func _finish(outcome: Variant = null) -> void:
		if outcome != null:
			(calls.back() as Dictionary)["outcome"] = outcome
		unfinished -= 1
		last_digest = _h._state_digest()
		last_physics = Engine.get_physics_frames()

	func _press_now(entry: Dictionary) -> String:
		var kind := String(entry.get("type", "action"))
		if kind == "drag":
			return "use `await api.drag(from, to, frames)` for drags"
		if kind == "servo":
			return "use `await api.servo({...})` for servos"
		if kind == "key" and not String(entry.get("target", "")).is_empty():
			return (
				"a drive cannot press a key at a 'target': `await api.tap({\"type\": \"target\", "
				+ "\"target\": ...})` to click-focus the field first, then press keys with no target"
			)
		return _h._dispatch_edge(entry, true)

	# Press and keep down. Anything still held when the drive ends is released
	# and reported - a drive is one complete maneuver.
	func press(entry: Dictionary) -> bool:
		if not _enter("press", str(entry)):
			return false
		var problem := _press_now(entry)
		if problem == "" and String(entry.get("type", "action")) != "motion":
			held[_h._label(entry)] = entry.duplicate()
		if problem != "":
			fault = "press: " + problem
		_finish()
		return problem == ""

	func release(entry: Dictionary) -> bool:
		if not _enter("release", str(entry)):
			return false
		var label: String = _h._label(entry)
		var problem := ""
		if not held.has(label):
			problem = "release: %s is not held by this drive (held: %s)" % [label, str(held.keys())]
		else:
			problem = _h._dispatch_edge(entry, false)
			held.erase(label)
		if problem != "":
			fault = problem
		_finish()
		return problem == ""

	# A refused coroutine call must still yield one frame before returning:
	# these are exactly the calls loop-shaped bodies await, and a sync refusal
	# turns such a loop into a zero-await spin that freezes the game's main
	# thread - measured live: a faulted 15-shot drive froze the game until the
	# process was killed. One frame per refused call keeps the tree serving
	# while the body runs itself out (or the drive watchdog abandons it).
	func _refuse_yielding() -> bool:
		await _h.get_tree().physics_frame
		return false

	# One press-hold-release, tick-aligned like an act's, so identical taps poll
	# identically.
	func tap(entry: Dictionary, hold_frames: int = 4) -> bool:
		if not _enter("tap", str(entry)):
			return await _refuse_yielding()
		await _h.get_tree().physics_frame
		if dead:
			return false
		var problem := _press_now(entry)
		if problem == "":
			var edgeless := String(entry.get("type", "action")) == "motion"
			for _i in range(maxi(hold_frames, _h.MIN_HOLD_FRAMES)):
				await _h.get_tree().physics_frame
				if dead:
					if not edgeless:
						_h._dispatch_edge(entry, false)
					return false
			if not edgeless:
				problem = _h._dispatch_edge(entry, false)
				await _h.get_tree().physics_frame
				if dead:
					return false
		if problem != "":
			fault = "tap: " + problem
		_finish()
		return problem == ""

	func drag(from: Variant, to: Variant, frames: int = 12) -> bool:
		if not _enter("drag", "%s -> %s over %d" % [str(from), str(to), frames]):
			return await _refuse_yielding()
		var entry := {"type": "drag", "from": _point(from), "to": _point(to), "frames": frames}
		var record: Dictionary = await _h._dispatch_drag(entry, _h._label(entry))
		if dead:
			return false
		var problem := String(record.get("dropped", ""))
		if problem != "":
			fault = "drag: " + problem
		_finish()
		return problem == ""

	func move_mouse(to: Variant) -> bool:
		if not _enter("move_mouse", str(to)):
			return false
		var problem := ""
		var point: Variant = _point(to)
		if point is Dictionary and (point as Dictionary).has("x") and (point as Dictionary).has("y"):
			_h._move_mouse(Vector2(float(point["x"]), float(point["y"])), Vector2.ZERO)
		elif point is String:
			var control: Control = _h._resolve_target(String(point))
			if control == null:
				problem = "move_mouse: no Control matched '%s'" % String(point)
			else:
				_h._move_mouse(control.get_global_rect().get_center(), Vector2.ZERO)
		else:
			problem = "move_mouse needs a Vector2, an {x, y} dictionary, or a Control name"
		if problem != "":
			fault = problem
		_finish()
		return problem == ""

	# The same closed loop game_act's servo entry runs; spec takes the same keys
	# (probe, target, increase, decrease, tolerance?, wrap?, max_physics_frames?).
	func servo(spec: Dictionary) -> bool:
		if not _enter("servo", str(spec)):
			return await _refuse_yielding()
		var entry := spec.duplicate()
		entry["type"] = "servo"
		var record: Dictionary = await _h._dispatch_servo(entry, _h._label(entry))
		if dead:
			return false
		var problem := String(record.get("dropped", ""))
		if problem != "":
			fault = "servo: " + problem
		_finish({
			"start": record.get("start"),
			"end": record.get("end"),
			"pulses": record.get("pulses"),
			"satisfied": record.get("satisfied", false),
		})
		return problem == ""

	# Read-only, same purity digest and 4KB cap as a probe - but the body gets
	# the real Variant back, so it can compute with it.
	func eval(expression: String) -> Variant:
		if not _enter("eval", expression):
			return null
		var result: Dictionary = _h._eval_raw(expression)
		if result.has("error"):
			fault = "eval: " + String(result["error"])
			_finish()
			return null
		_finish(_h._jsonable(result["value"]))
		return result["value"]

	# Wait until the expression is truthy, at most max_physics_frames. Returns
	# whether it was satisfied - a timeout is the body's to branch on.
	func until(expression: String, max_physics_frames: int) -> bool:
		if not _enter("until", expression):
			return await _refuse_yielding()
		var waited := 0
		var satisfied := false
		while true:
			var probed: Dictionary = _h._eval_raw(expression)
			if probed.has("error"):
				fault = "until: " + String(probed["error"])
				_finish({"satisfied": false, "frames_waited": waited})
				return false
			if _h._truthy(probed["value"]):
				satisfied = true
				break
			if waited >= max_physics_frames:
				break
			if Engine.get_physics_frames() - start_physics >= frame_budget:
				fault = (
					"the drive's %d-physics-frame budget ran out inside until(\"%s\")"
					% [frame_budget, expression]
				)
				break
			if Time.get_ticks_msec() >= deadline_ms:
				fault = "the drive ran out of wall clock inside until(\"%s\")" % expression
				break
			await _h.get_tree().physics_frame
			if dead:
				return false
			waited += 1
		_finish({"satisfied": satisfied, "frames_waited": waited})
		return satisfied

	func wait_physics(frames: int) -> bool:
		if not _enter("wait_physics", str(frames)):
			return await _refuse_yielding()
		for _i in range(maxi(frames, 0)):
			if Engine.get_physics_frames() - start_physics >= frame_budget:
				fault = "the drive's %d-physics-frame budget ran out inside wait_physics" % frame_budget
				break
			if Time.get_ticks_msec() >= deadline_ms:
				fault = "the drive ran out of wall clock inside wait_physics"
				break
			await _h.get_tree().physics_frame
			if dead:
				return false
		_finish()
		return fault == ""

	func log(message: Variant) -> void:
		if not _enter("log", ""):
			return
		logs.append(_h._capped(str(message)))
		_finish()

	static func _point(p: Variant) -> Variant:
		if p is Vector2:
			return {"x": (p as Vector2).x, "y": (p as Vector2).y}
		return p


# Wrap the body so its statements sit inside a callable the harness owns. The
# indent prefix must match the body's own style: GDScript refuses files mixing
# tabs and spaces, and bodies arrive written in either.
func _compile_drive(source: String) -> Variant:
	var uses_tabs := false
	for line in source.split("\n"):
		if line.begins_with("\t"):
			uses_tabs = true
			break
	var indent := "\t" if uses_tabs else "    "
	var body := ""
	for line in source.split("\n"):
		body += indent + line + "\n"
	var script := GDScript.new()
	script.source_code = "extends RefCounted\nfunc run(api):\n" + body
	if script.reload() != OK:
		return (
			"the drive source did not compile. Send only the statements of a function BODY "
			+ "(no `func` header), indent nested blocks consistently with tabs or spaces "
			+ "(never both), and remember this is GDScript, not Python: `var x = ...`, "
			+ "`str(...)`, no f-strings. The editor log has the parser's exact message."
		)
	return script


# Runs the compiled body to completion and reports through `done`, so _op_drive
# can watch it against a deadline instead of awaiting it unconditionally.
func _run_drive_body(runner: RefCounted, api: DriveApi, done: Dictionary) -> void:
	done["returned"] = await runner.run(api)
	# The closing segment check runs HERE, in the same synchronous block as the
	# body's return. Between this return and the watchdog's next poll the game
	# runs real frames, and a check delayed until then blames the body for them
	# - measured: a clean drive tainted on camera variables the game's own
	# _physics_process had just written. Skipped when a call was abandoned
	# without await: the zombie may already have pressed something, which would
	# read as body mutation here.
	if api.fault == "" and api.unfinished == 0 and api._enter("end", ""):
		api._finish()
	done["finished"] = true


func _op_drive(msg: Dictionary) -> Dictionary:
	_intent = String(msg.get("intent", ""))
	var source := String(msg.get("source", ""))
	if source.strip_edges().is_empty():
		return {"ok": false, "error": "game_drive needs `source`: the statements of a GDScript function body"}
	if source.length() > DRIVE_SOURCE_MAX_CHARS:
		return {
			"ok": false,
			"error": (
				"the drive source is %d chars; more than %d is not one maneuver - split it"
				% [source.length(), DRIVE_SOURCE_MAX_CHARS]
			),
		}
	var compiled: Variant = _compile_drive(source)
	if compiled is String:
		return {"ok": false, "error": compiled}
	var runner: RefCounted = (compiled as GDScript).new()
	var api := DriveApi.new(self, maxi(int(msg.get("max_physics_frames", 600)), 1))
	var start := Engine.get_physics_frames()
	_thaw()
	# The body is watched, not awaited: a GDScript coroutine cannot be killed
	# from outside, so a body that never returns (an unbounded loop over faulted
	# api calls - the shape a budget-exhausted drive degenerates into) would
	# otherwise hold _serving forever and wedge every later op. On the wall
	# clock the body is abandoned instead: its api goes dead, the op fails
	# loudly, and the session keeps serving.
	var done := {"finished": false, "returned": null}
	_run_drive_body(runner, api, done)
	var body_deadline := Time.get_ticks_msec() + UNTIL_WALL_CLOCK_BUDGET_MS
	var fault_grace := -1
	while not bool(done["finished"]) and Time.get_ticks_msec() < body_deadline:
		# Nothing legitimate runs after a fault: the body gets a short grace to
		# unwind on its own, then is abandoned, rather than waiting out the full
		# wall clock at one refused call per frame.
		if fault_grace == -1 and api.fault != "":
			fault_grace = Time.get_ticks_msec() + 3000
		if fault_grace != -1 and Time.get_ticks_msec() >= fault_grace:
			break
		await get_tree().process_frame
	var returned: Variant = done["returned"]
	if not bool(done["finished"]):
		var note := (
			"The body never returned and was abandoned mid-flight: its api is dead and "
			+ "anything it held was released, but its coroutine cannot be killed - avoid "
			+ "unbounded loops in drive bodies; give every loop an exit."
		)
		api.fault = note if api.fault == "" else api.fault + " | " + note
	# The closing segment check happened inside _run_drive_body, in the body's
	# own sync block; here only the missing-await diagnosis is left to name.
	if api.fault == "" and api.unfinished > 0:
		api.fault = (
			"%d api call(s) were started but never finished: the body called an async api "
			% api.unfinished
			+ "function without `await`. The calls that span time (tap, drag, servo, until, "
			+ "wait_physics) must be awaited: `await api.tap(...)`. The abandoned call may "
			+ "have left an input pressed, so this drive's results are unusable."
		)
	api.dead = true
	# A drive is one complete maneuver: the next op must find a clean input
	# state, so anything the body left pressed is lifted and reported.
	var released: Array = []
	for label in api.held:
		_dispatch_edge(api.held[label], false)
		released.append(label)
	if not released.is_empty():
		await get_tree().physics_frame
	_freeze()
	var reply := {
		"ok": api.fault == "",
		"calls": api.calls,
		"physics_frames": Engine.get_physics_frames() - start,
	}
	if not api.logs.is_empty():
		reply["log"] = api.logs
	if not released.is_empty():
		reply["released_at_end"] = released
	if api.fault != "":
		# The reject path carries only the error string, so the call log - the
		# debugging gold for a failed drive - travels inside it.
		reply["error"] = api.fault + " | calls so far: " + _capped(JSON.stringify(api.calls))
	else:
		reply["returned"] = _jsonable(returned)
	return reply
