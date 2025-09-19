package objects

// Unit aliases for readability when specifying masses/radii/densities.
Meter   :: f64
Kilogram:: f64
KgPerM3 :: f64

ObjectDefinition :: struct {
	name:    cstring,
	mass:    Kilogram, // total mass in kg
	density: KgPerM3,  // kg/m^3 (optional if you derive mass from radius)
	radius:  Meter,    // meters
}

// Convenience: derive mass from density & radius (sphere assumption).
pi := 3.141592653589793
make_from_density :: proc(density: KgPerM3, radius: Meter) -> ObjectDefinition {
	volume := (4.0 / 3.0) * pi * radius * radius * radius
	mass := density * volume
	return ObjectDefinition{mass = mass, density = density, radius = radius}
}