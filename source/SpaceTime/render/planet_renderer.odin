package render

import world "../world"
import math "core:math"
import rl "vendor:raylib"

min_angular_deg := 0.35 // tweak: 0.1–0.5° feels nice
min_angular_rad := min_angular_deg * rl.DEG2RAD

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
