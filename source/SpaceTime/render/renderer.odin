package render

import rl "vendor:raylib"
import rlgl "vendor:raylib/rlgl"; _ :: rlgl
import strings "core:strings"; ___ :: strings
import helpers "../helpers"
import fmt "core:fmt"; __ :: helpers
import world "../world"

// Thin wrapper over Raylib that keeps a small amount of state and provides
// RAII-style helpers (with_frame/with_cam3d) so call sites stay tidy.

cstr :: cstring
cf :: rl.ConfigFlags

// Window/camera mode the app is currently in.
fullscreen_state :: enum u8 {
	EXCLUSIVE = 0,
	BORDERLESS,
	WINDOWED,
}

// All mutable runtime state for the renderer.
State :: struct {
	initiated:    bool,              // InitWindow() called?
	maximised:    bool,              // (reserved) – your own tracking
	fullscreen:   fullscreen_state,  // which fullscreen mode is active
	vsync:        bool,              // vsync toggle (mirrors flag)
	active_flags: rl.ConfigFlags,    // cached snapshot of rl window flags
	target_fps:   u16,               // SetTargetFPS value (0 = uncapped)
	should_close: bool,              // app-requested close latch
	cam:          rl.Camera3D,       // current camera used by with_cam3d
	ctrl:         Camera_Controller, // (reserved) camera controller state
	cam_in_world: world.WorldPos,    // camera expressed in sector+local meters
}

// Immutable window basics + embedded state.
Window :: struct {
	width:  u16,
	height: u16,
	title:  cstr,
	state:  State,
}

window: Window
w := &window

// Initialise Raylib window & basic state. If flags are provided, pass them
// directly to SetConfigFlags before InitWindow; otherwise enable a sensible
// default (VSYNC + resizable). Returns true if this call performed init.
init :: proc(ww: u16, hh: u16, tt: cstr, ff: Maybe(cf), fff: Maybe(u16)) -> bool {
	if w.state.initiated do return true
	if ww == 0 || ww < 1 {w.width = 800} else {w.width = ww}
	if hh == 0 || hh < 1 {w.height = 600} else {w.height = hh}
	if tt == "" || tt == nil {w.title = "Forgot the title [idiot]"} else {w.title = tt}
	if fff != nil {w.state.target_fps = fff.(u16)} else {w.state.target_fps = 0}

	if (ff != nil) {
		w.state.active_flags = ff.?
		rl.SetConfigFlags(w.state.active_flags)
	} else {
		fmt.println("WARN: No flags provided, running with default flags")
		rl.SetConfigFlags(cf{.VSYNC_HINT, .WINDOW_RESIZABLE})
	}
	rl.InitWindow(cast(i32)w.width, cast(i32)w.height, w.title)

	rl.SetTargetFPS(cast(i32)w.state.target_fps)
	w.state.initiated = true
	w.state.should_close = false
	return true
}

// Tear down the window and reset the module-local state struct so the renderer
// can be cleanly re-initialised by the caller later if desired.
shutdown :: proc() -> bool {
	fmt.println("INFO: Renderer Shutting down")
	if !w.state.initiated {
		return false
	}
	rl.CloseWindow()
	window = Window{} // reset all fields (width/height/title/state)
	w = nil
	return true
}

// ─────────────────────────────────────────────────────────────────────────────
// Frame helpers
// ─────────────────────────────────────────────────────────────────────────────

// Begin + clear. Always pair with end_frame (or use with_frame below).
begin_frame :: proc(clear: rl.Color) {
	rl.BeginDrawing()
	rl.ClearBackground(clear)
}

// End the frame; swaps buffers.
end_frame :: proc() {
	rl.EndDrawing()
}

// RAII-style frame block. Safe to use with 'defer' at callsite.
with_frame :: proc(clear: rl.Color, body: proc()) {
	begin_frame(clear)
	defer end_frame()
	body()
}

// 3D camera block; wraps BeginMode3D/EndMode3D for the provided camera.
with_cam3d :: proc(cam: ^rl.Camera3D, body: proc()) {
	rl.BeginMode3D(cam^)
	defer rl.EndMode3D()
	body()
}

// Scissor helpers for UI clipping.
push_scissor :: proc(x, y, w, h: i32) {rl.BeginScissorMode(x, y, w, h)}
pop_scissor  :: proc() {rl.EndScissorMode()}

// ─────────────────────────────────────────────────────────────────────────────
// Misc helpers
// ─────────────────────────────────────────────────────────────────────────────

delta_time      :: proc() -> f32 {return rl.GetFrameTime()}
fps             :: proc() -> i32 {return rl.GetFPS()}
frame_counter   :: proc() -> i32 {return rl.GetFrameTime() == 0 ? 0 : rl.GetFPS()}

set_target_fps  :: proc(fps: i32) {rl.SetTargetFPS(fps)}

// Snapshot the current window flags from Raylib into a bitset we keep locally.
get_active_flags_snapshot :: proc() -> rl.ConfigFlags {
	acc: rl.ConfigFlags
	for f in rl.ConfigFlag {
		if rl.IsWindowState(cf{f}) do acc |= cf{f}
	}
	return acc
}

// Toggle a Raylib window flag and keep our cache in sync.
set_config_flag :: proc(flag: rl.ConfigFlag, enabled: bool) {
	if enabled {
		fmt.println("INFO: Enabled window flag: {0}", flag)
		if !rl.IsWindowState(cf{flag}) do rl.SetWindowState(cf{flag})
	} else {
		fmt.println("INFO: Disabled window flag: {0}", flag)
		if rl.IsWindowState(cf{flag}) do rl.ClearWindowState(cf{flag})
	}
	// Snap local cache to actual state
	w.state.active_flags = get_active_flags_snapshot()
}

// Query convenience – asks Raylib and latches it into our own state so a
// system can also request shutdown via request_close().
should_close :: proc() -> bool {
	if rl.WindowShouldClose() {
		w.state.should_close = true
	}
	return w.state.should_close
}

// Allow other systems to request/cancel app shutdown.
request_close :: proc() { w.state.should_close = true }
cancel_close  :: proc() { w.state.should_close = false }

// Current sizes and aspect; render_size is a placeholder in case you later add
// high-DPI backbuffer scaling that differs from window size.
window_size          :: proc() -> (i32, i32) {return rl.GetScreenWidth(), rl.GetScreenHeight()}
render_size          :: proc() -> (i32, i32) {return window_size()}
framebuffer_aspect   :: proc() -> f32 {
	rw, rh := render_size()
	return cast(f32)rw / cast(f32)rh
}

// ─────────────────────────────────────────────────────────────────────────────
// Camera helpers
// ─────────────────────────────────────────────────────────────────────────────

// Replace the active camera and update any cached projection state.
set_camera :: proc(cam: rl.Camera3D) {
	w.state.cam = cam
	update_camera_projection()
}

// If you later cache a custom projection matrix or handle orthographic mode,
// do it here. Currently this is a placeholder since we query per-frame.
update_camera_projection :: proc() {
	// Raylib Camera3D stores fovy in degrees and projection mode
}

// Accessors to the current view/projection matrices from Raylib.
camera_view :: proc() -> rl.Matrix {return rl.GetCameraMatrix(w.state.cam)}
camera_proj :: proc() -> rl.Matrix {
	rw, rh := render_size()
	if rh <= 0 { 	// can happen during minimize/resize
		return rl.Matrix(1) // identity
	}
	aspect := cast(f32)rw / cast(f32)rh
	return rl.GetCameraProjectionMatrix(&w.state.cam, aspect)
}

// Optional render pass registration stubs for future layering.
Render_Pass_Proc :: proc()

register_passes :: proc(
	geometry: Render_Pass_Proc,
	transparents: Render_Pass_Proc,
	ui: Render_Pass_Proc,
) {
	// LATER
}

execute_passes :: proc() {
	// LATER
}
