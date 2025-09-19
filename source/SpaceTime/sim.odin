package SpaceTime

import render "./render"
import math "core:math"; _ :: math

// Useful constant for orbit debugging or UI readouts.
SECONDS_PER_YEAR: f64 = 365.25 * 24.0 * 3600.0

// The clock separates real (wall) time from simulation time via a scalar.
// Call update_sim_clock() once per frame, then consume sim_dt in physics.
Sim_Clock :: struct {
	real_dt:    f64, // seconds (wall-clock)
	time_scale: f64, // 1.0 = realtime, 0 = paused, 1000 = 1000x, etc.
	sim_dt:     f64, // seconds *after* scaling
	sim_time:   f64, // accumulated simulated seconds
}

sim_clock: Sim_Clock = {
	time_scale = 1.0,
}

update_sim_clock :: proc() {
	// Frame delta from renderer; clamp big spikes so physics remains stable
	// after e.g. window drags or breakpoint resumes.
	sim_clock.real_dt = cast(f64)render.delta_time()
	if sim_clock.real_dt > 0.1 do sim_clock.real_dt = 0.1

	// Apply scale and accumulate simulated time.
	sim_clock.sim_dt = sim_clock.real_dt * sim_clock.time_scale
	sim_clock.sim_time += sim_clock.sim_dt
}
