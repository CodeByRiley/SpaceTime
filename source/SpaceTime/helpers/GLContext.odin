package helpers

import "core:fmt"
_ :: fmt
GLGetProcAddress :: proc "system" (name: cstring) -> rawptr

// Basic pointer validity test for wglGetProcAddress results.
is_valid_wgl_ptr :: proc "contextless" (p: rawptr) -> bool {
	v := transmute(uintptr)p
	return v > 3 && v != ~uintptr(0) // Simplified check
}

when ODIN_OS == .Windows {
	// Minimal Windows declarations so we can call kernel32 and opengl32 directly.
	HMODULE :: rawptr
	FARPROC :: rawptr

	// Link kernel32 and import the functions we use.
	foreign import kernel32 "system:kernel32.lib"
	foreign kernel32 {
		GetModuleHandleA :: proc "stdcall" (lpModuleName: cstring) -> HMODULE ---
		LoadLibraryA     :: proc "stdcall" (lpLibFileName: cstring) -> HMODULE ---
		GetProcAddress   :: proc "stdcall" (hModule: HMODULE, lpProcName: cstring) -> FARPROC ---
	}

	// Link opengl32 and import wglGetProcAddress.
	foreign import opengl32 "system:opengl32.lib"
	foreign opengl32 {
		wglGetProcAddress :: proc "system" (name: cstring) -> rawptr ---
	}
}
when ODIN_OS == .Linux {
	// Linux: try glXGetProcAddress, fall back to dlsym for core symbols.
	foreign import libGL "system:GL"
	foreign libGL {
		glXGetProcAddress :: proc "c" (name: cstring) -> rawptr ---
	}

	foreign import libdl "system:dl"
	foreign libdl {
		dlsym :: proc "c" (handle: rawptr, symbol: cstring) -> rawptr ---
	}
}
when ODIN_OS == .Darwin { 	// macOS/iOS
	RTLD_DEFAULT :: rawptr(-2) // On Darwin, RTLD_DEFAULT is -2

	foreign import libSystem "system:System"
	foreign libSystem {
		dlsym :: proc "c" (handle: rawptr, symbol: cstring) -> rawptr ---
	}
}

// Handle to opengl32.dll (Windows) cached after first call.
_opengl32_handle: HMODULE

// Returns the address of an OpenGL function across platforms. On Windows we
// try wglGetProcAddress first, then fall back to GetProcAddress from opengl32.
// On Linux we use glXGetProcAddress and dlsym; on macOS we use dlsym only.
get_gl_proc_address_smart :: proc "system" (name: cstring) -> rawptr {
	when ODIN_OS == .Windows {
		p := wglGetProcAddress(name)
		if is_valid_wgl_ptr(p) {
			return p
		}
		if _opengl32_handle == nil {
			_opengl32_handle = GetModuleHandleA("opengl32.dll")
			if _opengl32_handle == nil {
				_opengl32_handle = LoadLibraryA("opengl32.dll")
			}
		}
		return GetProcAddress(_opengl32_handle, name)
	} else when ODIN_OS == .Linux {
		p := glXGetProcAddress(name)
		if p != nil { return p }
		RTLD_DEFAULT :: rawptr(nil)
		return dlsym(RTLD_DEFAULT, name)
	} else when ODIN_OS == .Darwin {
		return dlsym(RTLD_DEFAULT, name)
	} else {
		#panic("Unsupported OS")
		return nil
	}
}

// Bind our platform loader and expose helpers to populate function pointers.
_platform_loader: GLGetProcAddress

init_gl_loader :: proc() {
	_platform_loader = get_gl_proc_address_smart
	assert(_platform_loader != nil, "Could not get platform GL proc address loader.")
}

load_gl_proc :: proc(proc_ptr: ^rawptr, name: cstring) -> bool {
	assert(
		_platform_loader != nil,
		"gl_loader has not been initialized. Call Init_GL_Loader() first.",
	)

	address := _platform_loader(name)
	if address == nil {
		// Use stderr to emit a clear error line per missing symbol.
		fmt.eprintf("Failed to load GL procedure: %s\n", name)
		return false
	}
	proc_ptr^ = address
	return true
}