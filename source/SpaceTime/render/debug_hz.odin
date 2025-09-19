package render

import rl   "vendor:raylib"
import rlgl "vendor:raylib/rlgl"
import math "core:math"
import world "../world"

AU            : f64 = 1.495978707e11
M_SUN         : f64 = 1.98847e30
L_REL_EXP     : f64 = 3.5 // mass–luminosity exponent (main-sequence approx)

// Solar-system baseline (Kasting/Kopparapu-style simple scaling)
HZ_INNER_CONSERVATIVE_AU : f64 = 0.95  // Runaway greenhouse
HZ_OUTER_CONSERVATIVE_AU : f64 = 1.67  // Maximum greenhouse
HZ_INNER_OPTIMISTIC_AU   : f64 = 0.75  // Recent Venus
HZ_OUTER_OPTIMISTIC_AU   : f64 = 1.77  // Early Mars

// -----------------------------------------------------------------------------
// Basic helpers
// -----------------------------------------------------------------------------
hz_from_mass :: proc(star_mass_kg: f64) -> (ic_m, oc_m, io_m, oo_m: f64) {
    cons_in_au, cons_out_au := 0.95, 1.67
    opt_in_au,  opt_out_au  := 0.75, 1.77
    Lrel := math.pow(math.max(star_mass_kg/M_SUN, 0.01), L_REL_EXP)
    s := math.sqrt(Lrel)
    return cons_in_au*s*AU, cons_out_au*s*AU, opt_in_au*s*AU, opt_out_au*s*AU
}


// Draw a circle in XZ-plane with N segments (thin line).
draw_circle_xz :: proc(center: rl.Vector3, r: f32, segments: int, color: rl.Color) {
    if segments < 8 { return }
    prev := rl.Vector3{ center.x + r, center.y, center.z }
    for i in 1 ..= segments {
        t := cast(f32)(2.0*math.PI * cast(f64)i / cast(f64)segments)
        cur := rl.Vector3{ center.x + r*math.cos(t), center.y, center.z + r*math.sin(t) }
        rl.DrawLine3D(prev, cur, color)
        prev = cur
    }
}

// filled annulus in XZ-plane (translucent).
// XZ-plane annulus using pure raylib (no rlgl/GL enums needed).
draw_annulus_xz :: proc(center: rl.Vector3, r0, r1: f32, segments: int, color: rl.Color) {
    if r1 <= r0 || segments < 8 { return }
    cnt := 2*(segments+1)
    pts := make([]rl.Vector3, cnt)
    k := 0
    for i in 0 ..= segments {
        t  := cast(f32)(2.0*math.PI * cast(f64)i / cast(f64)segments)
        ct := math.cos(t); st := math.sin(t)
        pts[k+0] = rl.Vector3{ center.x + r1*ct, center.y, center.z + r1*st }
        pts[k+1] = rl.Vector3{ center.x + r0*ct, center.y, center.z + r0*st }
        k += 2
    }
    rl.DrawTriangleStrip3D(&pts[0], cast(i32)len(pts), color)
    delete(pts)
}


// Optional: outline the inner/outer circles with lines (XZ plane).
draw_annulus_outline_xz :: proc(center: rl.Vector3, r0, r1: f32, segments: int, col: rl.Color) {
    if segments < 8 { return }
    // Inner ring
    prev_i := rl.Vector3{ center.x + r0, center.y, center.z }
    prev_o := rl.Vector3{ center.x + r1, center.y, center.z }
    for i in 1 ..= segments {
        t  := cast(f32)(2.0*math.PI * cast(f64)i / cast(f64)segments)
        ct := math.cos(t)
        st := math.sin(t)
        cur_i := rl.Vector3{ center.x + r0*ct, center.y, center.z + r0*st }
        cur_o := rl.Vector3{ center.x + r1*ct, center.y, center.z + r1*st }
        rl.DrawLine3D(prev_i, cur_i, col)
        rl.DrawLine3D(prev_o, cur_o, col)
        prev_i, prev_o = cur_i, cur_o
    }
}

// Screen label helper (centered over band mid-radius).
label_hz :: proc(cam: ^rl.Camera3D, world_pos: rl.Vector3, text: cstring, col: rl.Color) {
    // Is the point in front of the camera?
    f := rl.Vector3{ cam.target.x - cam.position.x,
                     cam.target.y - cam.position.y,
                     cam.target.z - cam.position.z }
    d := rl.Vector3{ world_pos.x - cam.position.x,
                     world_pos.y - cam.position.y,
                     world_pos.z - cam.position.z }
    if (f.x*d.x + f.y*d.y + f.z*d.z) <= 0 {
        return // behind camera → don't draw label
    }

    // Project to screen (Vector2)
    s := rl.GetWorldToScreenEx(world_pos, cam^, rl.GetScreenWidth(), rl.GetScreenHeight())
    // (or: s := rl.GetWorldToScreen(world_pos, cam^))

    rl.DrawText(text, cast(i32)(s.x) + 6, cast(i32)(s.y) - 18, 16, col)
}

// -----------------------------------------------------------------------------
// Public: draw habitable zone debug for a star at position `center_world`.
// - star_mass_kg:       mass of the star
// - meters_per_unit:    your render scale (e.g., 1000 for 1 unit == 1 km)
// - conservative_only:  show just the conservative band if true
// - with_fill:          draw translucent fill
// -----------------------------------------------------------------------------
draw_habitable_zone_debug_world :: proc(
    cam: ^rl.Camera3D,
    star_wp: world.WorldPos,       // star in WORLD coords
    cam_in_world: world.WorldPos,  // your floating-origin camera
    star_mass_kg: f64,
    conservative_only: bool = true,
    with_fill: bool = true,
    segs: int = 256,
) {
    // center in render units, relative to current floating origin
    center := world.world_to_render(star_wp, cam_in_world)

    // radii (meters -> units) using world.METERS_PER_UNIT (e.g., 2.0e8)
    ic_m, oc_m, io_m, oo_m := hz_from_mass(star_mass_kg)
    ic := world.meters_to_units(ic_m)
    oc := world.meters_to_units(oc_m)
    io := world.meters_to_units(io_m)
    oo := world.meters_to_units(oo_m)

    // draw geometry
    if with_fill do draw_annulus_xz(center, ic, oc, segs, rl.Color{0,255,128,48})
    rl.BeginBlendMode(rl.BlendMode.ADDITIVE)
    rlgl.EnableDepthTest()
    rlgl.DisableDepthMask()
    draw_circle_xz(center, ic, segs, rl.Color{0,255,128,200})
    draw_circle_xz(center, oc, segs, rl.Color{0,255,128,200})

    if !conservative_only {
        if with_fill do draw_annulus_xz(center, io, oo, segs, rl.Color{255,220,0,32})
        draw_circle_xz(center, io, segs, rl.Color{255,220,0,180})
        draw_circle_xz(center, oo, segs, rl.Color{255,220,0,180})
    }
    rlgl.DisableDepthTest()
    rlgl.EnableDepthMask()
    rl.EndBlendMode()
}

project_for_label :: proc(cam: ^rl.Camera3D, world_pos: rl.Vector3) -> (ok: bool, s: rl.Vector2) {
    // in-front test
    f := rl.Vector3{ cam.target.x - cam.position.x, cam.target.y - cam.position.y, cam.target.z - cam.position.z }
    d := rl.Vector3{ world_pos.x - cam.position.x, world_pos.y - cam.position.y, world_pos.z - cam.position.z }
    if (f.x*d.x + f.y*d.y + f.z*d.z) <= 0 { return false, {} }
    return true, rl.GetWorldToScreenEx(world_pos, cam^, rl.GetScreenWidth(), rl.GetScreenHeight())
}

draw_habitable_zone_labels :: proc(
    cam: ^rl.Camera3D,
    center_world: rl.Vector3, // already in render units
    star_mass_kg: f64,
) {
    ic_m, oc_m, io_m, oo_m := hz_from_mass(star_mass_kg)

    mid_c := rl.Vector3{
        center_world.x + cast(f32)(((ic_m + oc_m) * 0.5) * world.UNITS_PER_METER),
        center_world.y, center_world.z,
    }
    if ok, s := project_for_label(cam, mid_c); ok {
        rl.DrawText(rl.TextFormat("HZ (cons): %.2f–%.2f AU", ic_m/AU, oc_m/AU),
                    cast(i32)s.x + 6, cast(i32)s.y - 18, 16, rl.Color{0,255,128,255})
    }

    mid_o := rl.Vector3{
        center_world.x + cast(f32)(((io_m + oo_m) * 0.5) * world.UNITS_PER_METER),
        center_world.y, center_world.z,
    }
    if ok, s := project_for_label(cam, mid_o); ok {
        rl.DrawText(rl.TextFormat("HZ (opt): %.2f–%.2f AU", io_m/AU, oo_m/AU),
                    cast(i32)s.x + 6, cast(i32)s.y + 2, 16, rl.Color{255,220,0,255})
    }
}