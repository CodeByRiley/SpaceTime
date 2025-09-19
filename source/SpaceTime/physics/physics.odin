package physics

import "core:sync"
import "core:fmt"
import math    "core:math"
import world   "../world"
import helpers "../helpers"

import thread "core:thread"
import si     "core:sys/info"

// ─────────────────────────────────────────────────────────────────────────────
// Constants
// G: gravitational constant in SI units.  SOFTENING2: small ε² to avoid 1/r²
// blow‑ups at very short distances (acts like Plummer softening).
// ─────────────────────────────────────────────────────────────────────────────
G          : f64 = 6.67430e-11
SOFTENING2 : f64 = 1.0e6 // (1 km)^2 softening

// ─────────────────────────────────────────────────────────────────────────────
// Job payloads (data passed to worker tasks)
// Each worker gets a slice of bodies and writes only to its *own* accumulator.
// This removes write contention; we sum the per‑thread accumulators afterward.
// ─────────────────────────────────────────────────────────────────────────────
Compute_Accels_Job_Data :: struct {
    b:         []^world.Body,        // all bodies (shared, read‑only)
    local_acc: []helpers.Vector3D,   // this worker's acceleration buffer
    start_i:   int,                  // inclusive i‑range this worker owns
    end_i:     int,                  // exclusive
}

// Payload for each chunk of the Velocity–Verlet step.
Verlet_Step_Job_Data :: struct {
    b:         []^world.Body,        // all bodies (positions & velocities)
    acc:       []helpers.Vector3D,   // current accelerations (read‑only)
    dt_half:   f64,                  // 0.5*dt (used by both kicks)
    dt_full:   f64,                  // dt (only used by kick+drift stage)
    start_idx: int,
    end_idx:   int,
}

// ─────────────────────────────────────────────────────────────────────────────
// Persistent multi‑threading state (1 pool reused every frame)
// ─────────────────────────────────────────────────────────────────────────────
Physics_MT_State :: struct {
    pool:          thread.Pool,             // core:thread worker pool
    workers:       int,                     // logical worker count
    tls:           [][]helpers.Vector3D,    // per‑worker accel buffers
    acc_jobs:      []Compute_Accels_Job_Data, // pre‑built job payloads
    step_jobs:     []Verlet_Step_Job_Data,  // pre‑built job payloads
    wg:            sync.Wait_Group,         // fences each submitted batch
    shutting_down: bool,                    // blocks new submissions
    inited:        bool,
}

ps: Physics_MT_State

// ─────────────────────────────────────────────────────────────────────────────
// Split N work items into ~equal contiguous chunks. First (N%P) chunks get one
// extra item: [base+1,…] then [base,…]. Returns [start,end) for chunk idx.
// ─────────────────────────────────────────────────────────────────────────────
chunk_range :: proc(n, idx, num_chunks: int) -> (int, int) {
    if num_chunks <= 0 || n <= 0 { return 0, 0 }
    base := n / num_chunks
    rem  := n % num_chunks

    start := idx * base
    extra: int
    if idx < rem {
        start += idx   // each earlier chunk shifted by its index
        extra = 1
    } else {
        start += rem   // later chunks start after the rem one‑larger chunks
        extra = 0
    }
    end_ := start + base + extra

    if start > n do start = n
    if end_  > n do end_  = n
    return start, end_
}

// Ensure per‑worker TLS arrays exist and match current body count.
ensure_tls :: proc(n_bodies: int) {
    if len(ps.tls) != ps.workers {
        // (Re)allocate outer slots if worker count changed.
        for i in 0 ..< len(ps.tls) {
            if ps.tls[i] != nil do delete(ps.tls[i])
        }
        ps.tls = make([][]helpers.Vector3D, ps.workers)
    }
    // Resize/allocate each worker's buffer to exactly n_bodies.
    for i in 0 ..< ps.workers {
        if ps.tls[i] == nil || len(ps.tls[i]) != n_bodies {
            if ps.tls[i] != nil do delete(ps.tls[i])
            ps.tls[i] = make([]helpers.Vector3D, n_bodies)
        }
    }
}

// ─────────────────────────────────────────────────────────────────────────────
// Thread pool lifecycle
// ─────────────────────────────────────────────────────────────────────────────
mt_init :: proc(desired_threads: int = 0) {
    if ps.inited do return

    // Pick a worker count (defaults to logical cores).
    n := desired_threads
    if n <= 0 {
        n = si.cpu.logical_cores
        if n <= 0 do n = 1
    }
    ps.workers = n

    fmt.println("Initialising the thread pool", n)
    thread.pool_init(&ps.pool, context.allocator, n)
    fmt.println("Starting thread pool")
    thread.pool_start(&ps.pool)

    // Preallocate per‑worker buffers and job payload slots.
    ps.tls       = make([][]helpers.Vector3D, ps.workers)
    ps.acc_jobs  = make([]Compute_Accels_Job_Data, ps.workers)
    ps.step_jobs = make([]Verlet_Step_Job_Data, ps.workers)

    fmt.println("Thread pool created successfully")
    ps.inited = true
}

// Change the worker count by rebuilding the pool and buffers.
mt_set_threads :: proc(nn: int) {
    n := nn
    if n <= 0 {
        n = si.cpu.logical_cores
        if n <= 0 do n = 1
    }
    if !ps.inited { mt_init(n); return }

    fmt.println("Setting thread count to", n)
    if n == ps.workers do return

    // Safe order: finish outstanding work → join → destroy → rebuild.
    sync.wait_group_wait(&ps.wg)
    thread.pool_join(&ps.pool)
    thread.pool_destroy(&ps.pool)

    for i in 0 ..< ps.workers { if ps.tls[i] != nil do delete(ps.tls[i]) }
    delete(ps.tls)
    delete(ps.acc_jobs)
    delete(ps.step_jobs)

    ps.workers = n
    thread.pool_init(&ps.pool, context.allocator, n)
    thread.pool_start(&ps.pool)

    ps.tls       = make([][]helpers.Vector3D, n)
    ps.acc_jobs  = make([]Compute_Accels_Job_Data, n)
    ps.step_jobs = make([]Verlet_Step_Job_Data, n)
}

// Shut the pool down gracefully: block new submissions, wait for all batches,
// join workers, destroy pool, then free memory.
mt_shutdown :: proc() {
    if !ps.inited do return
    ps.shutting_down = true
    fmt.println("Shutting down threads")

    // Fence any in‑flight frame work (no‑op if count == 0).
    sync.wait_group_wait(&ps.wg)

    // Join worker threads, then destroy the pool implementation.
    thread.pool_join(&ps.pool)
    thread.pool_destroy(&ps.pool)

    // Free TLS and job arrays after threads are gone.
    for i in 0 ..< ps.workers { if ps.tls[i] != nil do delete(ps.tls[i]) }
    delete(ps.tls)
    delete(ps.acc_jobs)
    delete(ps.step_jobs)

    ps = {} // reset state
}

// ─────────────────────────────────────────────────────────────────────────────
// Pool task procedures
// Each task signals completion via ps.wg so callers can wait precisely for the
// batch they submitted (no spinning on pool state).
// ─────────────────────────────────────────────────────────────────────────────
compute_accels_task :: proc(task: thread.Task) {
    jd := cast(^Compute_Accels_Job_Data) task.data
    b  := jd.b
    la := jd.local_acc

    // Pairwise Newtonian gravity on this worker's i‑range.
    for i in jd.start_i ..< jd.end_i {
        for j in i+1 ..< len(b) {
            rij := world.delta(b[i].world, b[j].world) // vector (j - i)
            r2  := rij.x*rij.x + rij.y*rij.y + rij.z*rij.z + SOFTENING2
            inv := 1.0 / math.sqrt(r2)
            s   := G * inv*inv*inv              // 1/|r|³ factor

            ai := helpers.v3d_scale(rij,  s*b[j].def.mass) // accel on i
            aj := helpers.v3d_scale(rij, -s*b[i].def.mass) // accel on j

            // Write only to local buffer (no contention with other workers).
            la[i] = helpers.v3d_add(la[i], ai)
            la[j] = helpers.v3d_add(la[j], aj)
        }
    }
    sync.wait_group_done(&ps.wg)
}

// First half of Velocity–Verlet: kick by ½dt, then drift by dt.
verlet_kick_drift_task :: proc(task: thread.Task) {
    jd := cast(^Verlet_Step_Job_Data) task.data
    b  := jd.b
    for i in jd.start_idx ..< jd.end_idx {
        b[i].v = helpers.v3d_add(b[i].v, helpers.v3d_scale(jd.acc[i], jd.dt_half))
        world.worldpos_add_local(&b[i].world, helpers.v3d_scale(b[i].v, jd.dt_full))
    }
    sync.wait_group_done(&ps.wg)
}

// Second half of Velocity–Verlet: final kick by ½dt using new accelerations.
verlet_kick_task :: proc(task: thread.Task) {
    jd := cast(^Verlet_Step_Job_Data) task.data
    b  := jd.b
    for i in jd.start_idx ..< jd.end_idx {
        b[i].v = helpers.v3d_add(b[i].v, helpers.v3d_scale(jd.acc[i], jd.dt_half))
    }
    sync.wait_group_done(&ps.wg)
}

// Helper to submit a single Task; guarded so shutdown can't enqueue more work.
submit_task :: proc(t: thread.Task) {
    if ps.shutting_down do return
    thread.pool_add_task(&ps.pool, context.allocator, t.procedure, t.data, 0)
}

// ─────────────────────────────────────────────────────────────────────────────
// Multi‑threaded front‑ends
// ─────────────────────────────────────────────────────────────────────────────
compute_accels_mt :: proc(b: []^world.Body, acc: []helpers.Vector3D) {
    if !ps.inited do mt_init(0)
    n := len(b); if n == 0 { return }

    ensure_tls(n)

    // Zero final and per‑worker accumulators.
    for i in 0 ..< n do acc[i] = {}
    for t in 0 ..< ps.workers {
        la := ps.tls[t]; if la == nil do continue
        for i in 0 ..< n do la[i] = {}
    }

    // Build job payloads per worker for their i‑ranges.
    scheduled := 0
    for t in 0 ..< ps.workers {
        s, e := chunk_range(n, t, ps.workers)
        if s >= e { continue }
        ps.acc_jobs[t] = Compute_Accels_Job_Data{
            b         = b,
            local_acc = ps.tls[t],
            start_i   = s,
            end_i     = e,
        }
        scheduled += 1
    }
    if scheduled == 0 { return }

    // Fence this batch: add N, enqueue tasks, wait until all signal done.
    sync.wait_group_add(&ps.wg, scheduled)
    for t in 0 ..< ps.workers {
        s, e := ps.acc_jobs[t].start_i, ps.acc_jobs[t].end_i
        if s >= e { continue }
        thread.pool_add_task(&ps.pool, context.allocator, compute_accels_task, rawptr(&ps.acc_jobs[t]), t)
    }
    sync.wait_group_wait(&ps.wg)

    // Reduce per‑worker accumulators into the final output.
    for t in 0 ..< ps.workers {
        la := ps.tls[t]; if la == nil { continue }
        for i in 0 ..< n { acc[i] = helpers.v3d_add(acc[i], la[i]) }
    }
}

// Three‑stage Velocity–Verlet using the pool.
step_verlet_mt :: proc(b: []^world.Body, acc: []helpers.Vector3D, dt: f64) {
    if !ps.inited do mt_init(0)
    n := len(b); if n == 0 { return }
    if ps.workers <= 1 { step_verlet(b, acc, dt); return }

    half := 0.5*dt

    // Stage 1: kick+drift in parallel (uses current acc).
    s1 := 0
    for t in 0 ..< ps.workers {
        s, e := chunk_range(n, t, ps.workers)
        if s >= e { continue }
        ps.step_jobs[t] = Verlet_Step_Job_Data{
            b = b, acc = acc, dt_half = half, dt_full = dt,
            start_idx = s, end_idx = e,
        }
        s1 += 1
    }
    if s1 > 0 {
        sync.wait_group_add(&ps.wg, s1)
        for t in 0 ..< ps.workers {
            s, e := ps.step_jobs[t].start_idx, ps.step_jobs[t].end_idx
            if s >= e { continue }
            submit_task(thread.Task{ procedure = verlet_kick_drift_task, data = rawptr(&ps.step_jobs[t]) })
        }
        sync.wait_group_wait(&ps.wg)
    }

    // Stage 2: recompute accelerations at new positions.
    compute_accels_mt(b, acc)

    // Stage 3: final kick in parallel.
    s3 := 0
    for t in 0 ..< ps.workers {
        s, e := chunk_range(n, t, ps.workers)
        if s >= e { continue }
        ps.step_jobs[t] = Verlet_Step_Job_Data{
            b = b, acc = acc, dt_half = half,
            start_idx = s, end_idx = e,
        }
        s3 += 1
    }
    if s3 > 0 {
        sync.wait_group_add(&ps.wg, s3)
        for t in 0 ..< ps.workers {
            s, e := ps.step_jobs[t].start_idx, ps.step_jobs[t].end_idx
            if s >= e { continue }
            thread.pool_add_task(&ps.pool, context.allocator, verlet_kick_task, rawptr(&ps.step_jobs[t]), t)
        }
        sync.wait_group_wait(&ps.wg)
    }
}

// ─────────────────────────────────────────────────────────────────────────────
// Single‑threaded fallbacks (reference implementation, useful for debugging)
// ─────────────────────────────────────────────────────────────────────────────
compute_accels :: proc(b: []^world.Body, acc: []helpers.Vector3D) {
    for i in 0 ..< len(b) do acc[i] = helpers.Vector3D{}
    for i in 0 ..< len(b) {
        for j in i+1 ..< len(b) {
            rij := world.delta(b[i].world, b[j].world) // b - a
            r2  := rij.x*rij.x + rij.y*rij.y + rij.z*rij.z + SOFTENING2
            inv := 1.0 / math.sqrt(r2)
            inv3:= inv*inv*inv
            s   := G * inv3

            ai := helpers.v3d_scale(rij,  s * b[j].def.mass)
            aj := helpers.v3d_scale(rij, -s * b[i].def.mass)

            acc[i] = helpers.v3d_add(acc[i], ai)
            acc[j] = helpers.v3d_add(acc[j], aj)
        }
    }
}

// Velocity–Verlet (kick–drift–kick) single‑threaded variant.
step_verlet :: proc(b: []^world.Body, acc: []helpers.Vector3D, dt: f64) {
    half := 0.5*dt
    // kick + drift
    for i in 0 ..< len(b) {
        b[i].v = helpers.v3d_add(b[i].v, helpers.v3d_scale(acc[i], half))
        world.worldpos_add_local(&b[i].world, helpers.v3d_scale(b[i].v, dt))
    }
    // refresh accels
    compute_accels(b, acc)
    // final kick
    for i in 0 ..< len(b) {
        b[i].v = helpers.v3d_add(b[i].v, helpers.v3d_scale(acc[i], half))
    }
}

// Utility: give sat a circular orbit around primary, correcting both bodies'
// velocities so the pair orbits their mutual center of mass (CM‑consistent).
init_circular_pair :: proc(primary, sat: ^world.Body, up: helpers.Vector3D, dir: f64) {
    r := world.delta(primary.world, sat.world)      // sat - primary
    rlen := math.sqrt(r.x*r.x + r.y*r.y + r.z*r.z); if rlen == 0 do return
    rhat := helpers.v3d_scale(r, 1.0/rlen)

    // Tangent = normalize(up × r̂); 'dir' selects CW/CCW.
    t := helpers.Vector3D{
        up.y*rhat.z - up.z*rhat.y,
        up.z*rhat.x - up.x*rhat.z,
        up.x*rhat.y - up.y*rhat.x,
    }
    tlen := math.sqrt(t.x*t.x + t.y*t.y + t.z*t.z); if tlen == 0 do return
    t = helpers.v3d_scale(t, dir/tlen)

    // Circular‑orbit speed v = sqrt( μ / r ), μ = G(M+m)
    mu := G * (primary.def.mass + sat.def.mass)
    v  := math.sqrt(mu / rlen)

    // Split opposite velocities according to mass so CM stays fixed.
    mP := primary.def.mass; mS := sat.def.mass
    primary.v = helpers.v3d_add(primary.v, helpers.v3d_scale(t, -v * (mS/(mP+mS))))
    sat.v     = helpers.v3d_add(sat.v,     helpers.v3d_scale(t,  v * (mP/(mP+mS))))
}