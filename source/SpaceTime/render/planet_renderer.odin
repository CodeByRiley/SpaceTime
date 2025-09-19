package render

import world "../world"
import math "core:math"
import rl "vendor:raylib"

min_angular_deg := 0.35 // tweak: 0.1–0.5° feels nice
min_angular_rad := min_angular_deg * rl.DEG2RAD

VisualSizeParams :: struct {
    min_px:    f32, // keep at least this many pixels of radius on screen
    boost:     f32, // multiply physical radius visually (1..~2 is nice)
    max_scale: f32, // if >0, cap r_vis <= r_units*max_scale
}

// Convert a pixel radius to a world radius at distance d (render units).
pixels_to_world_radius :: proc(cam: ^rl.Camera3D, d_units, px: f32) -> f32 {
    if px <= 0 || d_units <= 0 do return 0
    // angular *diameter* covered by 'px' vertically: (px / H) * fovy
    fovy_rad    := (cam.fovy * (math.PI/180.0))
    theta_rad   := (px / cast(f32)rl.GetScreenHeight()) * fovy_rad
    // We want angular *radius* → theta/2, and r = d * tan(theta/2)
    return d_units * math.tan(theta_rad * 0.5)
}

// Distance from camera (render units)
dist_to_cam :: proc(cam: ^rl.Camera3D, p: rl.Vector3) -> f32 {
    dx := p.x - cam.position.x
    dy := p.y - cam.position.y
    dz := p.z - cam.position.z
    return math.sqrt(dx*dx + dy*dy + dz*dz)
}

// Draw a body with screen-space clamped visual size.
// - b.world is in world coords; we convert with your floating-origin camera.
// - Physics still uses the true radius; only visuals are adjusted.
draw_body_visual :: proc(b: ^world.Body, vis: VisualSizeParams = VisualSizeParams{}) {
    // position relative to camera (render units)
    p := world.world_to_render(b.world, w.state.cam_in_world)

    // distance from camera (render units)
    d := math.sqrt(p.x*p.x + p.y*p.y + p.z*p.z)

    // physical radius in render units
    r_units := world.meters_to_units(b.def.radius)

    // start from boosted physical size
    r_vis := r_units * math.max(vis.boost, 0.0)

    // clamp to a minimum on-screen radius (in pixels)
    min_r := pixels_to_world_radius(&w.state.cam, d, vis.min_px)
    if min_r > r_vis do r_vis = min_r

    // optional cap so things don't get comically big
    if vis.max_scale > 0 {
        max_r := r_units * vis.max_scale
        if r_vis > max_r do r_vis = max_r
    }

    rl.DrawSphereEx(p, r_vis, 24, 24, b.color)
}

draw_body :: proc(b: ^world.Body) {
	// position relative to camera (already f32 units)
	p := world.world_to_render(b.world, w.state.cam_in_world)
	d := math.sqrt(p.x * p.x + p.y * p.y + p.z * p.z) // distance in render units

	// physical radius in render units
	r_units := world.meters_to_units(b.def.radius)

	// apparent-size clamp: r_vis >= d * tan(theta)
	r_vis := r_units
	if d > 0.0 {
		min_r := d * cast(f32)math.tan(min_angular_rad)
		if min_r > r_vis do r_vis = min_r
	}


	rl.DrawSphereEx(p, r_vis, 24, 24, b.color)
}


