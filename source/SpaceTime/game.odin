package SpaceTime

import objects "./objects"
import world "./world"
import math "core:math"
import helpers "helpers"
import render "render"
import rl "vendor:raylib"
import rlgl "vendor:raylib/rlgl"; _ :: math
import physics "./physics"
import fmt "core:fmt"
import strings "core:strings"
import thread "core:thread"
import si "core:sys/info"

// Number of worker threads to use for physics by default. We read it from
// sysinfo once; physics.mt_init() ultimately governs the pool it manages.
NUM_THREADS: int = si.cpu.logical_cores
pool: thread.Pool // (unused here; the physics package owns its own pool)

// ── Bodies and their definitions (kg, m, etc.) ──────────────────────────────
sun: world.Body
moon: world.Body
earth: world.Body
sun_definition :: objects.ObjectDefinition {
	name    = "Sun",
	mass    = 1.98847e30,
	density = 1408,
	radius  = 6.95508e+8,
}
moon_definition :: objects.ObjectDefinition {
	name    = "Moon",
	mass    = 7.3477e22,
	density = 3344,
	radius  = 1.737e6,
}
earth_definition :: objects.ObjectDefinition {
	name    = "Earth",
	mass    = 5.9722e24,
	density = 5514,
	radius  = 6.371e6,
}
sun_vis   := render.VisualSizeParams{ min_px = 36, boost = 2.25, max_scale = 75 }
earth_vis := render.VisualSizeParams{ min_px = 24,  boost = 1.75, max_scale = 60 }
moon_vis  := render.VisualSizeParams{ min_px = 14,  boost = 1.5, max_scale = 55 }
// Pointers to the bodies and a matching acceleration buffer. The arrays are
// sized to 3 here; expand if you add more bodies.
bodies: [3]^world.Body
acc_buf: [3]helpers.Vector3D // m/s^2 per body

// Physics substep cap (in *simulation* seconds). We break a large sim_dt into
// chunks so integrator error stays in check at astronomical scales.
PHYS_DT_MAX: f64 = 900.0 // 15 min per substep

// Camera starts looking +X; controller can overwrite transform later.
camera: rl.Camera3D = {
	{0, 0, 0}, // position (will be overridden by controller anyway)
	{1, 0, 0}, // target: look along +X to start
	{0, 1, 0},
	75,
	.PERSPECTIVE,
}

Physics_Stepper :: struct {
    h: f64,            // fixed step, e.g. 600 s
    acc: f64,          // time accumulator (seconds)
    max_steps: int,    // safety cap per frame
}

following: ^world.Body

physics_stepper := Physics_Stepper{ h = 600.0, acc = 0.0, max_steps = 2000 }

run :: proc() {
	// Spin up physics worker pool first so it's ready when the loop begins.
	physics.mt_init(12)

	// Window + GL context
	render.init(
		1600,
		900,
		"balling",
		rl.ConfigFlags{.WINDOW_RESIZABLE, .MSAA_4X_HINT, .WINDOW_HIGHDPI},
		0,
	)

	// Load required GL entry points for custom helpers.
	helpers.init_gl_loader()
	if !helpers.gl_custom_init() {
		panic("FATAL: Failed to load required OpenGL procedures!")
	}
	fmt.println("INFO: OpenGL procedures loaded successfully.")
	fmt.println("INFO: Renderer initialised")

	// Seed camera state inside render module.
	fmt.println("INFO: Creating renderer camera")
	render.w.state.cam = camera
	render.w.state.follow = {}
	render.cam_attach_from_current()

	// Create bodies in world space (sector+local meters). Earth at ~1 AU.
	fmt.println("INFO: Creating physics bodies")
	sun = world.make_body(
		sun_definition,
		world.Sector3{0, 0, 0},
		helpers.Vector3D{0, 0, 0},
		rl.YELLOW,
	)
	moon = world.make_body(
		moon_definition,
		world.Sector3{0, 0, 0},
		helpers.Vector3D{1.496e11 + 384.4e6, 0, 0},
		rl.LIGHTGRAY,
	)
	earth = world.make_body(
		earth_definition,
		world.Sector3{0, 0, 0},
		helpers.Vector3D{1.496e11, 0, 0},
		rl.SKYBLUE,
	) // ~1 AU on +X

	// Hook arrays to the instances above.
	bodies = [3]^world.Body{&sun, &earth, &moon}

	// Expand far clip to comfortably include AU-scale visuals in render units.
	rlgl.SetClipPlanes(1,world.METERS_PER_UNIT)

	// Assign tangential velocities for near-circular orbits (Y up, XZ plane).
	fmt.println("INFO: Creating physics pairs")
	init_sun_earth_moon(&sun,&earth,&moon)
	
	physics.compute_accels_mt(bodies[:], acc_buf[:]) 
	// Main loop: tick update, input, draw, until window/system requests close.
	for !render.should_close() {
		update()
		handle_inputs()
		draw()
	}

	// Orderly teardown: stop physics workers and close the window.
	physics.mt_shutdown()
	render.shutdown()
	fmt.println("INFO: Renderer said should close")
}

init_sun_earth_moon :: proc(sun, earth, moon: ^world.Body) {
    // Orbit plane normal: Y+ gives orbits in the XZ plane
    up := helpers.Vector3D{0, 1, 0}

    // --- positions already set at spawn: Sun at 0, Earth at 1 AU, Moon at Earth+384,400 km ---

    // zero then build up velocities
    sun.v   = {}
    earth.v = {}
    moon.v  = {}

    // 1) Sun–Earth circular pair (sets Earth ≈ 29.78 km/s around Sun)
    physics.init_circular_pair(sun, earth, up, +1.0)

    // 2) Give Moon the parent's baseline translation first
    moon.v = earth.v

    // 3) Earth–Moon circular pair (adds ±1.022 km/s about their CM)
    physics.init_circular_pair(earth, moon, up, +1.0)

    // prime accels after final positions/velocities are set
    physics.compute_accels_mt(bodies[:], acc_buf[:])
}

// Camera helpers for quick focus and relative placement, plus time-scale hotkeys.
handle_inputs :: proc() {
	if rl.IsKeyPressed(.I) do render.focus_on_body(&sun, 20)
	if rl.IsKeyPressed(.O) do render.focus_on_body(&earth, 30)
	if rl.IsKeyPressed(.P) do render.focus_on_body(&moon, 40)
	if rl.IsKeyPressed(.U) do render.follow_stop()
	if (rl.IsKeyPressed(.V)) {
		off_unit := 10.0
		off_m := off_unit * world.METERS_PER_UNIT
		render.cam_place_relative_to(earth.world, 0.0, 0.0, off_m)
	}
}

// Call once after spawning bodies, BEFORE the first step
prime_accels :: proc(bodies: []^world.Body, acc: []helpers.Vector3D) {
    physics.compute_accels_mt(bodies, acc)
}

// Each frame:
tick_physics :: proc(bodies: []^world.Body, acc: []helpers.Vector3D, frame_dt: f64, time_scale: f64) {
    physics_stepper.acc += frame_dt * time_scale
    steps := 0
    for physics_stepper.acc >= physics_stepper.h {
        physics.step_verlet_mt(bodies, acc, physics_stepper.h)
        physics_stepper.acc -= physics_stepper.h
        steps += 1
        if steps >= physics_stepper.max_steps { break } // avoid death spiral on stalls
    }
}

// Time-scale control: multiplicative stepping, numeric presets, and clamps to
// keep values sane over long sessions.
handle_time_scale_input :: proc() {
	// step up/down multiplicatively (feels better across wide ranges)
	if rl.IsKeyPressed(rl.KeyboardKey.KP_ADD) || rl.IsKeyPressed(rl.KeyboardKey.EQUAL) { 	// + or =
		sim_clock.time_scale *= 2.0
		if sim_clock.time_scale == 0 do sim_clock.time_scale = 1.0
	}
	if rl.IsKeyPressed(rl.KeyboardKey.KP_SUBTRACT) || rl.IsKeyPressed(rl.KeyboardKey.MINUS) { 	// -
		sim_clock.time_scale *= 0.5
	}

	// quick presets
	if rl.IsKeyPressed(rl.KeyboardKey.ONE) do sim_clock.time_scale = 0.0 // pause
	if rl.IsKeyPressed(rl.KeyboardKey.TWO) do sim_clock.time_scale = 1.0 // realtime
	if rl.IsKeyPressed(rl.KeyboardKey.THREE) do sim_clock.time_scale = 60.0 // 1 minute / sec
	if rl.IsKeyPressed(rl.KeyboardKey.FOUR) do sim_clock.time_scale = 3600.0 // 1 hour / sec
	if rl.IsKeyPressed(rl.KeyboardKey.FIVE) do sim_clock.time_scale = 86400.0 // 1 day / sec
	if rl.IsKeyPressed(rl.KeyboardKey.SIX) do sim_clock.time_scale = 4 * 86400.0 // 4 day / sec
	if rl.IsKeyPressed(rl.KeyboardKey.SEVEN) do sim_clock.time_scale = 6 * 86400.0 // 6 day / sec
	if rl.IsKeyPressed(rl.KeyboardKey.EIGHT) do sim_clock.time_scale = 8 * 86400.0 // 8 day / sec
	if rl.IsKeyPressed(rl.KeyboardKey.NINE) do sim_clock.time_scale = 10 * 86400.0 // 10 day / sec
	if rl.IsKeyPressed(rl.KeyboardKey.ZERO) do sim_clock.time_scale = 15 * 86400.0 // 15 day / sec

	// hold to fast-forward / slow-mo
	if rl.IsKeyDown(rl.KeyboardKey.RIGHT_SHIFT) && sim_clock.time_scale < 1e12 do sim_clock.time_scale *= 1.05
	if rl.IsKeyDown(rl.KeyboardKey.RIGHT_CONTROL) && sim_clock.time_scale > 0.00 do sim_clock.time_scale *= 0.95

	// clamp
	if sim_clock.time_scale < 0.0 do sim_clock.time_scale = 0.0
	if sim_clock.time_scale > 1e12 do sim_clock.time_scale = 1e12
}

accum: f64
FIXED_DT: f64 = 1.0 / 120.0 // 120 tick rate physics (unused with PHYS_DT_MAX loop)

// Per-frame simulation step. We update the sim clock, then consume the
// accumulated *sim* time in PHYS_DT_MAX chunks while calling the MT integrator.
update :: proc() {
	handle_time_scale_input()
	update_sim_clock()
	render.camera_update(cast(f32)sim_clock.real_dt)

	remaining := sim_clock.sim_dt
	for remaining > 0.0 {
		dt := math.min(remaining, PHYS_DT_MAX)

		// Multi-threaded N-body step (kick+drift, recalc accels, kick).
		physics.step_verlet_mt(bodies[:], acc_buf[:], dt)
		remaining -= dt
	}
}

// Frame rendering: 3D pass with the solar bodies, then a small HUD.
draw :: proc() {
    render.with_frame(
        rl.Color{25,25,25,255},
        proc(){
            // 3D
            render.with_cam3d(&render.w.state.cam, proc() {
                render.draw_body_visual(&sun, sun_vis)
				render.draw_body_visual(&moon, moon_vis)
                render.draw_body_visual(&earth, earth_vis)
				
				render.show_object_distance(&render.w.state.cam, &sun, &earth, render.w.state.cam_in_world)
				render.draw_habitable_zone_debug_world(
					&render.w.state.cam,
					sun.world,
					render.w.state.cam_in_world,
					sun.def.mass,
					conservative_only = false,
					with_fill = true,
					segs = 256,
				)


                //draw_world_origin_grid()
            })

            // UI (labels in 2D, no state headaches)
			
			center_units := world.world_to_render(sun.world, render.w.state.cam_in_world)
			render.draw_habitable_zone_labels(&render.w.state.cam, center_units, sun.def.mass)
			render.draw_distance_labels(&render.w.state.cam, &sun,&earth,render.w.state.cam_in_world)
            rl.DrawFPS(10, 10)
            draw_time_hud(10, 32)
        },
    )
}


draw_time_hud :: proc(x, y: i32) {
	time_scale_cstr := strings.clone_to_cstring(
		fmt.tprintf("time_scale: %.3gx", sim_clock.time_scale),
	)
	sim_time_cstr := strings.clone_to_cstring(fmt.tprintf("sim_time: %.3gx", sim_clock.sim_time))
	rl.DrawText(time_scale_cstr, x, y, 20, rl.LIME)
	rl.DrawText(sim_time_cstr, x, y + 22, 20, rl.LIME)
}

// Draw a grid at the *world* origin by converting sector+local meters to the
// current camera's render-space units and pushing a transform.
draw_world_origin_grid :: proc() {
    // World origin (0/0/0) → render units relative to current floating origin
    origin := world.WorldPos{
        sector = world.Sector3{0, 0, 0},
        local  = helpers.Vector3D{0, 0, 0},
    }
    p := world.world_to_render(origin, render.w.state.cam_in_world) // -> rl.Vector3

    // Keep rlgl happy: flush before changing matrices, and after restoring.
    rlgl.DrawRenderBatchActive()

    rlgl.PushMatrix()
    rlgl.Translatef(p.x, p.y, p.z)
    rl.DrawGrid(20, 1) // Draws centered at true world origin (not camera)
    rlgl.PopMatrix()

    rlgl.DrawRenderBatchActive()
}

to_render_v3 :: proc(wp: world.WorldPos, meters_per_unit: f64) -> rl.Vector3 {
    return rl.Vector3{
        cast(f32)(wp.local.x / meters_per_unit),
        cast(f32)(wp.local.y / meters_per_unit),
        cast(f32)(wp.local.z / meters_per_unit),
    }
}

sanitize_for_2d_text :: proc() {
    // Finish any pending 3D batch
    rlgl.DrawRenderBatchActive()

    // Raylib’s defaults for text/sprites
    rlgl.ActiveTextureSlot(0)                     // GL_TEXTURE0
    rlgl.SetTexture(0)                            // so the next draw can bind its own
    rlgl.SetShader(rlgl.GetShaderIdDefault(), rlgl.GetShaderLocsDefault())   // default textured shader
    rlgl.SetBlendMode(rlgl.BLEND_SRC_ALPHA)        // srcAlpha/oneMinusSrcAlpha
    rlgl.DisableDepthTest()
    rlgl.DisableDepthMask()                         // avoid Z-writing in 2D
    rlgl.EnableBackfaceCulling()                  // raylib default
    rlgl.Color4ub(255, 255, 255, 255)

    // Start a clean batch for UI
    rlgl.DrawRenderBatchActive()
}
