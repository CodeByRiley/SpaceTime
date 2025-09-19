package render

import helpers "../helpers"
import world "../world"
import math "core:math"
import rl "vendor:raylib"
// ───────────────── Camera Controller (free-fly) ─────────────────

// `controller` is a package-level variable that holds the state for the free-fly camera,
// such as its orientation (yaw/pitch) and movement settings.
Camera_Controller :: struct {
	yaw, pitch:    f32,
	base_speed:    f32,
	mouse_sens:    f32,
	fast_mult:     f32,
	slow_mult:     f32,
	invert_y:      bool,
	cursor_locked: bool,
	// runtime
	min_pitch:     f32,
	max_pitch:     f32,
	fov_step:      f32,
}

v3_add :: proc(a, b: rl.Vector3) -> rl.Vector3 {return a + b}
v3_sub :: proc(a, b: rl.Vector3) -> rl.Vector3 {return a - b}
v3_scale :: proc(a: rl.Vector3, s: f32) -> rl.Vector3 {return a * s}
v3_len :: proc(a: rl.Vector3) -> f32 {return math.sqrt(a.x * a.x + a.y * a.y + a.z * a.z)}


// cam_init_defaults resets the camera controller to its default settings.
cam_ctrl_defaults :: proc() {
	w.state.ctrl = Camera_Controller {
		base_speed    = 500000,
		mouse_sens    = 0.2,
		fast_mult     = 4.0,
		slow_mult     = 0.25,
		invert_y      = false,
		cursor_locked = false,
		min_pitch     = -89,
		max_pitch     = +89,
		fov_step      = 1.0,
	}
}


// cam_init_from_current synchronizes the controller's yaw and pitch angles based on
// the camera's existing position and target vectors. This should be called once after
// the main camera is first set up to ensure the controller starts with the correct orientation.
cam_attach_from_current :: proc() {
	cam_ctrl_defaults()

	// Seed world camera at sector (0,0,0); keep render cam near origin.
	w.state.cam_in_world = world.WorldPos {
		sector = world.Sector3{0, 0, 0},
		local  = helpers.Vector3D{0, 0, 0}, // we render relative, so keep RL cam at origin
	}

	// Derive yaw/pitch from current RL cam
	dir := w.state.cam.target - w.state.cam.position
	len := math.sqrt(dir.x * dir.x + dir.y * dir.y + dir.z * dir.z)
	if len > 0.000001 do dir = dir / len
	w.state.ctrl.yaw = math.atan2(dir.z, dir.x) * rl.RAD2DEG
	w.state.ctrl.pitch = math.asin(dir.y) * rl.RAD2DEG
	if w.state.ctrl.pitch < -89 {w.state.ctrl.pitch = -89}
	if w.state.ctrl.pitch > +89 {w.state.ctrl.pitch = +89}

	// Snap RL cam to origin now (we’ll render relative)
	w.state.cam.position = rl.Vector3{0, 0, 0}
	w.state.cam.target = rl.Vector3{1, 0, 0} // will be overwritten every frame
}

cam_basis_from_yaw_pitch :: proc(yaw_deg, pitch_deg: f32) -> (fwd, right, up: rl.Vector3) {
	yaw := yaw_deg * rl.DEG2RAD
	pitch := pitch_deg * rl.DEG2RAD

	// Forward
	fwd = rl.Vector3 {
		math.cos(yaw) * math.cos(pitch),
		math.sin(pitch),
		math.sin(yaw) * math.cos(pitch),
	}
	// Normalize forward
	fl := math.sqrt(fwd.x * fwd.x + fwd.y * fwd.y + fwd.z * fwd.z)
	if fl > 0.000001 do fwd = fwd / fl

	// Up is world up for free-fly
	up = rl.Vector3{0, 1, 0}

	// Right = normalize(cross(fwd, up))
	right = rl.Vector3 {
		fwd.y * up.z - fwd.z * up.y,
		fwd.z * up.x - fwd.x * up.z,
		fwd.x * up.y - fwd.y * up.x,
	}
	rl2 := math.sqrt(right.x * right.x + right.y * right.y + right.z * right.z)
	if rl2 > 0.000001 do right = right / rl2

	// Recompute up to ensure orthogonality: up = normalize(cross(right, fwd))
	up = rl.Vector3 {
		right.y * fwd.z - right.z * fwd.y,
		right.z * fwd.x - right.x * fwd.z,
		right.x * fwd.y - right.y * fwd.x,
	}
	ul := math.sqrt(up.x * up.x + up.y * up.y + up.z * up.z)
	if ul > 0.000001 do up = up / ul

	return
}

// Nudge camera by x meters in dir
cam_nudge_relative_meters :: proc(dx, dy, dz: f64) {
	c := &w.state.ctrl
	fwd, right, up := basis64_from_yaw_pitch(c.yaw, c.pitch) // f64 basis
	offset := helpers.v3d_add(
		helpers.v3d_add(helpers.v3d_scale(right, dx), helpers.v3d_scale(up, dy)),
		helpers.v3d_scale(fwd, dz),
	)
	w.state.cam_in_world.local = helpers.v3d_add(w.state.cam_in_world.local, offset)
	world.normalize_world_pos(&w.state.cam_in_world)
}

// Set camera relative position with offset
cam_place_relative_to :: proc(target: world.WorldPos, off_right, off_up, off_fwd: f64) {
	c := &w.state.ctrl
	_, right, up := basis64_from_yaw_pitch(c.yaw, c.pitch)
	// forward is where camera looks; to be "behind", use negative off_fwd
	fwd, _, _ := basis64_from_yaw_pitch(c.yaw, c.pitch)

	pos := target // start at target
	local_off := helpers.v3d_add(
		helpers.v3d_add(helpers.v3d_scale(right, off_right), helpers.v3d_scale(up, off_up)),
		helpers.v3d_scale(fwd, off_fwd),
	)
	pos.local = helpers.v3d_add(pos.local, local_off)
	world.normalize_world_pos(&pos)

	w.state.cam_in_world = pos
}

basis64_from_yaw_pitch :: proc(yaw_deg, pitch_deg: f32) -> (fwd, right, up: helpers.Vector3D) {
	yaw := cast(f64)(yaw_deg) * cast(f64)(rl.DEG2RAD)
	pitch := cast(f64)(pitch_deg) * cast(f64)(rl.DEG2RAD)

	fwd = helpers.Vector3D {
		math.cos(yaw) * math.cos(pitch),
		math.sin(pitch),
		math.sin(yaw) * math.cos(pitch),
	}
	// normalize
	fl := math.sqrt(fwd.x * fwd.x + fwd.y * fwd.y + fwd.z * fwd.z)
	if fl > 0.0 do fwd = helpers.v3d_scale(fwd, 1.0 / fl)

	up = helpers.Vector3D{0, 1, 0}
	// right = normalize(cross(fwd, up))
	right = helpers.Vector3D {
		fwd.y * up.z - fwd.z * up.y,
		fwd.z * up.x - fwd.x * up.z,
		fwd.x * up.y - fwd.y * up.x,
	}
	rl2 := math.sqrt(right.x * right.x + right.y * right.y + right.z * right.z)
	if rl2 > 0.0 do right = helpers.v3d_scale(right, 1.0 / rl2)
	// up = normalize(cross(right, fwd))
	up = helpers.Vector3D {
		right.y * fwd.z - right.z * fwd.y,
		right.z * fwd.x - right.x * fwd.z,
		right.x * fwd.y - right.y * fwd.x,
	}
	ul := math.sqrt(up.x * up.x + up.y * up.y + up.z * up.z)
	if ul > 0.0 do up = helpers.v3d_scale(up, 1.0 / ul)

	return
}

// cam_lock_cursor hides and locks the cursor to the center of the screen for mouse look.
cam_lock_cursor :: proc() {rl.DisableCursor(); w.state.ctrl.cursor_locked = true}
cam_unlock_cursor :: proc() {rl.EnableCursor(); w.state.ctrl.cursor_locked = false}
cam_toggle_cursor :: proc() {if w.state.ctrl.cursor_locked {cam_unlock_cursor()}
	else {cam_lock_cursor()}}
cam_cursor_locked :: proc() -> bool {return w.state.ctrl.cursor_locked}

// cam_set_speed sets the base movement speed of the camera.
cam_set_speed :: proc(v: f32) {w.state.ctrl.base_speed = v}
cam_set_speed_scales :: proc(fast_mult, slow_mult: f32) {w.state.ctrl.fast_mult = fast_mult
	w.state.ctrl.slow_mult = slow_mult}
cam_set_sensitivity :: proc(sens: f32) {w.state.ctrl.mouse_sens = sens}
cam_set_invert_y :: proc(on: bool) {w.state.ctrl.invert_y = on}

cam_wheel_affects_fov := false

camera_update :: proc(dt_f32: f32) {
	c := &w.state.ctrl

	if rl.IsMouseButtonPressed(rl.MouseButton.RIGHT) do cam_toggle_cursor()

	if c.cursor_locked {
		dm := rl.GetMouseDelta()
		if dm.x != 0 || dm.y != 0 {
			c.yaw += dm.x * c.mouse_sens
			dy := dm.y * c.mouse_sens
			if c.invert_y {dy = -dy}
			c.pitch -= dy
			if c.pitch < c.min_pitch {c.pitch = c.min_pitch}
			if c.pitch > c.max_pitch {c.pitch = c.max_pitch}
		}
	}

	// wheel → speed (still fine)
	wheel := rl.GetMouseWheelMove()
	if wheel != 0 {
		c.base_speed *= (1.0 + wheel * 0.1)
		if c.base_speed < 10000 {c.base_speed = 10000}
		if c.base_speed > 500000000000 {c.base_speed = 500000000000}
	}

	// f64 basis & movement
	fwd, right, up := basis64_from_yaw_pitch(c.yaw, c.pitch)

	spd := cast(f64)(c.base_speed) // meters/sec
	if rl.IsKeyDown(rl.KeyboardKey.LEFT_SHIFT) do spd *= cast(f64)(c.fast_mult)
	if rl.IsKeyDown(rl.KeyboardKey.LEFT_ALT) do spd *= cast(f64)(c.slow_mult)

	vel := helpers.Vector3D{} // direction
	if rl.IsKeyDown(rl.KeyboardKey.W) do vel = helpers.v3d_add(vel, fwd)
	if rl.IsKeyDown(rl.KeyboardKey.S) do vel = helpers.v3d_sub(vel, fwd)
	if rl.IsKeyDown(rl.KeyboardKey.D) do vel = helpers.v3d_add(vel, right)
	if rl.IsKeyDown(rl.KeyboardKey.A) do vel = helpers.v3d_sub(vel, right)
	if rl.IsKeyDown(rl.KeyboardKey.SPACE) do vel = helpers.v3d_add(vel, up)
	if rl.IsKeyDown(rl.KeyboardKey.LEFT_CONTROL) do vel = helpers.v3d_sub(vel, up)

	// integrate in f64 world space
	dt := cast(f64)(dt_f32)
	l := math.sqrt(vel.x * vel.x + vel.y * vel.y + vel.z * vel.z)
	if l > 1e-9 {
		vel = helpers.v3d_scale(vel, (spd * dt) / l) // normalize * speed * dt
		w.state.cam_in_world.local = helpers.v3d_add(w.state.cam_in_world.local, vel)
		world.normalize_world_pos(&w.state.cam_in_world)
	}

	// keep RL camera near origin; just point it with f32 forward
	w.state.cam.position = rl.Vector3{0, 0, 0}
	w.state.cam.target = rl.Vector3{cast(f32)fwd.x, cast(f32)fwd.y, cast(f32)fwd.z}
}

focus_on_body :: proc(b: ^world.Body, angle_deg: f32) {
	c := &w.state.ctrl

	// basis in world (f64)
	fwd, _, _ := basis64_from_yaw_pitch(c.yaw, c.pitch)

	// distance so that sphere of radius r subtends `angle_deg`
	r_m := b.def.radius
	angle_rad := cast(f64)(angle_deg) * cast(f64)(rl.DEG2RAD)
	dist_m := r_m / math.tan(angle_rad * 0.5)

	// target world pos
	target := b.world
	// place camera `dist_m` *behind* target along -fwd
	offset := helpers.v3d_scale(fwd, -dist_m)
	w.state.cam_in_world = target
	w.state.cam_in_world.local = helpers.v3d_add(target.local, offset)
	world.normalize_world_pos(&w.state.cam_in_world)
}
