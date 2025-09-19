package world

import "../helpers"
import "../objects"
import math "core:math"
import rl "vendor:raylib"; _ :: objects

// Units & chunking
// -----------------
// We render in coarse "units" to avoid float precision issues at solar scales.
// A single render unit equals METERS_PER_UNIT meters in world space.
// UNITS_PER_METER converts meters → render units. Keep it consistent everywhere.
// SECTOR_SIZE_M defines the size of one spatial sector in meters; we keep each
// object's local coordinate inside one sector and track overflow in integer
// sector coordinates. This preserves precision far from origin.
//
// NOTE: METERS_PER_UNIT is defined elsewhere in your project. Here we derive
// the inverse for convenience.
// 1 unit = 1,000,000 meters  (== sector size)
UNITS_PER_METER: f64 = 1.0 / METERS_PER_UNIT

// Sector size (meters). Choose it equal to METERS_PER_UNIT so one render unit
// spans exactly one sector. That makes camera-relative math straightforward.
SECTOR_SIZE_M: f64 = METERS_PER_UNIT // 1,000 km per sector
// ──────────────────────────────────────────────────────────────

// Convert a meter length to render units (f32 for the GPU).
meters_to_units :: proc(m: f64) -> f32 {
	return cast(f32)(m * UNITS_PER_METER)
}

// Integer sector address (coarse chunk index). Using i64 keeps huge ranges safe.
Sector3 :: struct {
	x, y, z: i64,
}

// A precise position in the world: integer sector + high-precision local meters.
// Invariants:
//   - local is always kept in the half-open range [-S/2, +S/2) on each axis
//   - sector stores the coarse displacement in multiples of SECTOR_SIZE_M
WorldPos :: struct {
	sector: Sector3,
	local:  helpers.Vector3D, // meters, kept in [-S/2, +S/2)
}

// A simulated body with physical definition, world pose, velocity and color.
Body :: struct {
	def:   objects.ObjectDefinition,
	world: WorldPos,
	v:     helpers.Vector3D, // m/s
	color: rl.Color,
}

// normalize_world_pos keeps local in [-S/2, +S/2) by pushing overflow into the
// integer sector. The +(half) trick makes negatives split correctly at -S/2.
normalize_world_pos :: proc(p: ^WorldPos) {
	half := 0.5 * SECTOR_SIZE_M
	sx := cast(i64)math.floor((p.local.x + half) / SECTOR_SIZE_M)
	sy := cast(i64)math.floor((p.local.y + half) / SECTOR_SIZE_M)
	sz := cast(i64)math.floor((p.local.z + half) / SECTOR_SIZE_M)

	if sx != 0 || sy != 0 || sz != 0 {
		// Move the sector by the computed offsets…
		p.sector.x += sx; p.sector.y += sy; p.sector.z += sz
		// …and pull local back by the exact meter amounts.
		p.local.x -= cast(f64)sx * SECTOR_SIZE_M
		p.local.y -= cast(f64)sy * SECTOR_SIZE_M
		p.local.z -= cast(f64)sz * SECTOR_SIZE_M
	}
}

// worldpos_add_local adds a high-precision meter delta to local and then
// renormalizes so we never let local drift out of the stable range.
worldpos_add_local :: proc(p: ^WorldPos, delta_m: helpers.Vector3D) {
	p.local = helpers.v3d_add(p.local, delta_m)
	normalize_world_pos(p)
}

// delta returns the vector (b - a) in meters, fully accounting for sector
// differences plus the precise local parts. This is the backbone for physics
// (e.g., gravity) and camera-relative transforms.
delta :: proc(a, b: WorldPos) -> helpers.Vector3D {
	dx_sector := helpers.Vector3D {
		cast(f64)(b.sector.x - a.sector.x) * SECTOR_SIZE_M,
		cast(f64)(b.sector.y - a.sector.y) * SECTOR_SIZE_M,
		cast(f64)(b.sector.z - a.sector.z) * SECTOR_SIZE_M,
	}
	return helpers.v3d_add(helpers.v3d_sub(b.local, a.local), dx_sector)
}

// world_to_render converts an absolute world position to camera-local render
// coordinates (f32). We first compute the relative meters w.r.t. the camera
// (obj - cam), then scale to render units for the GPU.
world_to_render :: proc(obj: WorldPos, cam: WorldPos) -> rl.Vector3 {
	rel := delta(cam, obj) // obj - cam, meters
	return rl.Vector3 {
		cast(f32)(rel.x * UNITS_PER_METER),
		cast(f32)(rel.y * UNITS_PER_METER),
		cast(f32)(rel.z * UNITS_PER_METER),
	}
}

// Helper to construct a body at a given sector/local with definition & color.
// We normalize immediately so callers can pass any local value safely.
make_body :: proc(
	def: objects.ObjectDefinition,
	sector: Sector3,
	local_m: helpers.Vector3D,
	color: rl.Color,
) -> Body {
	b := Body {
		def = def,
		world = WorldPos{sector = sector, local = local_m},
		color = color,
	}
	normalize_world_pos(&b.world)
	return b
}
