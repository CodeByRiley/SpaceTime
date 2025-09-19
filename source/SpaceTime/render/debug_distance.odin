package render

import rl "vendor:raylib"
import math "core:math"
import world "../world"

show_object_distance :: proc(
    cam: ^rl.Camera3D,
    a, b: ^world.Body,
    cam_in_world: world.WorldPos,
) {
    // Physics-space distance (meters)
    d := world.delta(a.world, b.world) // meters
    dm := math.sqrt(d.x*d.x + d.y*d.y + d.z*d.z)
    du := dm / world.METERS_PER_UNIT
    dau := dm / AU

    // Draw a 3D line between them (render units)
    ps := world.world_to_render(a.world,   cam_in_world)
    pe := world.world_to_render(b.world, cam_in_world)
    rl.DrawLine3D(ps, pe, rl.Color{0,200,255,100})

    // Annotate midpoint with AU
    mid := rl.Vector3{ (ps.x+pe.x)*0.5, (ps.y+pe.y)*0.5, (ps.z+pe.z)*0.5 }
    s := rl.GetWorldToScreenEx(mid, cam^, rl.GetScreenWidth(), rl.GetScreenHeight())
    rl.DrawText(rl.TextFormat("%.3f AU", dau), cast(i32)s.x+4, cast(i32)s.y-14, 14, rl.SKYBLUE)

    // UI readout (top-left)
    // rl.DrawText(rl.TextFormat("Earth–Sun: %.3f AU  (%.1f u, %.3e m)", dau, du, dm),
    //             10, 54, 16, rl.LIME)
    
    // Cross-check: render-space distance should match du (in units) within epsilon
    dx := pe.x - ps.x; dy := pe.y - ps.y; dz := pe.z - ps.z
    du_render := math.sqrt(dx*dx + dy*dy + dz*dz)
    err := math.abs(cast(f64)du_render - du)
    if err > 0.05 { // ~0.05 units ≈ 10,000 km at your scale
        rl.DrawText(rl.TextFormat("WARN world_to_render mismatch: %.3f u", err),
                    10, 72, 16, rl.RED)
    }
}

draw_distance_labels :: proc(
    cam: ^rl.Camera3D,
    a, b: ^world.Body,
    cam_in_world: world.WorldPos
) {
    // Get distance from obj A - B
    d := world.delta(a.world, b.world) // Meters
    dm := math.sqrt(d.x*d.x + d.y*d.y + d.z*d.z)

    // Convert to render units 1 : 2.0e8
    du := dm / world.METERS_PER_UNIT
    dau := dm / AU

    // Project and draw label at mid point
    pa := world.world_to_render(a.world, cam_in_world)
    pb := world.world_to_render(b.world, cam_in_world)
    mid := rl.Vector3{ (pa.x+pb.x)*0.5, (pa.y+pb.y)*0.5, (pa.z+pb.z)*0.5 }
    if ok, s := project_for_label(cam, mid); ok {
        rl.DrawText(
            rl.TextFormat("dist: %.3f AU  (%.1f u, %.3e m)", dau, cast(f32)du, dm),
            cast(i32)s.x + 6, cast(i32)s.y - 16, 16, rl.SKYBLUE,
        )
    }
}