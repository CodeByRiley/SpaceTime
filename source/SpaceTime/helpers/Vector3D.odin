package helpers

// Vector3D :: struct { x, y, z: f64 }
Vector3D :: [3]f64
v3d_add :: proc(a, b: Vector3D) -> Vector3D {return a + b}
v3d_mul :: proc(a, b: Vector3D) -> Vector3D {return a * b}
v3d_sub :: proc(a, b: Vector3D) -> Vector3D {return a - b}
v3d_scale :: proc(a: Vector3D, s: f64) -> Vector3D {return Vector3D{a.x * s, a.y * s, a.z * s}}
