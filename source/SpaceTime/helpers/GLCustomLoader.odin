package helpers

import _ "vendor:OpenGL" // constants only

// Minimal typedefs to keep wrappers readable.
GLenum :: i32
GLint  :: i32
GLsizei:: i32
GLuint :: u32
GLboolean :: u8

// Declare C-callable function pointer types for the GL calls we want.
PFNGLBEGIN_PROC       :: proc "system" (mode: i32)
PFNGLEND_PROC         :: proc "system" ()
PFNGLVERTEX3F_PROC    :: proc "system" (x, y, z: f32)
PFNGLCOLOR4UB_PROC    :: proc "system" (r, g, b, a: u8)
PFNGLTEXCOORD2F_PROC  :: proc "system" (u, v: f32)
PFNGLNORMAL3F_PROC    :: proc "system" (nx, ny, nz: f32)
PFNGLBINDTEXTURE_PROC :: proc "system" (target: i32, texture: u32)
PFNGLDELETETEXTURES_PROC :: proc "system" (n: i32, textures: [^]u32)
PFNGLGENTEXTURES_PROC :: proc "system" (n: i32, textures: [^]u32)
PFNGLTEXIMAGE3D_PROC :: proc "system" (
	target: i32,
	level: i32,
	internalformat: i32,
	width: i32,
	height: i32,
	depth: i32,
	border: i32,
	format: i32,
	typ: i32,
	pixels: rawptr,
)
PFNGLTEXPARAMETERI_PROC :: proc "system" (target: i32, pname: i32, param: i32)
PFNGLACTIVETEXTURE_PROC :: proc "system" (texture: i32)
PFNGLPIXELSTOREI_PROC :: proc "system" (pname: i32, param: i32)
PFNGLENABLE_PROC   :: proc "system" (cap: i32)
PFNGLDISABLE_PROC  :: proc "system" (cap: i32)
PFNGLENABLEI_PROC  :: proc "system" (cap: i32, index: u32)
PFNGLDISABLEI_PROC :: proc "system" (cap: i32, index: u32)
PFNGLBLENDFUNC_PROC   :: proc "system" (sfactor: i32, dfactor: i32)
PFNGLCULLFACE_PROC    :: proc "system" (mode: i32)
PFNGLDEPTHMASK_PROC   :: proc "system" (flag: u8)
PFNGLDEPTHFUNC_PROC   :: proc "system" (func: i32)
PFNGLCOLORMASK_PROC   :: proc "system" (r, g, b, a: u8)
PFNGLLINEWIDTH_PROC   :: proc "system" (width: f32)
PFNGLPOLYGONMODE_PROC :: proc "system" (face: i32, mode: i32)
PFNGLSCISSOR_PROC     :: proc "system" (x, y, w, h: i32)
PFNGLVIEWPORT_PROC    :: proc "system" (x, y, w, h: i32)
PFNGLCLEARCOLOR_PROC  :: proc "system" (r, g, b, a: f32)
PFNGLCLEAR_PROC       :: proc "system" (mask: u32)
PFNGLGETERROR_PROC    :: proc "system" () -> u32

// Function pointers filled at runtime via load_gl_proc.
_GenTextures:      PFNGLGENTEXTURES_PROC
_DeleteTextures:   PFNGLDELETETEXTURES_PROC
_BindTexture:      PFNGLBINDTEXTURE_PROC
_TexImage3D:       PFNGLTEXIMAGE3D_PROC
_TexParameteri:    PFNGLTEXPARAMETERI_PROC
_ActiveTexture:    PFNGLACTIVETEXTURE_PROC
_PixelStorei:      PFNGLPIXELSTOREI_PROC
_GlEnable:         PFNGLENABLE_PROC
_GlDisable:        PFNGLDISABLE_PROC
_GlEnablei:        PFNGLENABLEI_PROC
_GlDisablei:       PFNGLDISABLEI_PROC

_GlBegin:        PFNGLBEGIN_PROC
_GlEnd:          PFNGLEND_PROC
_GlVertex3f:     PFNGLVERTEX3F_PROC
_GlColor4ub:     PFNGLCOLOR4UB_PROC
_GlTexCoord2f:   PFNGLTEXCOORD2F_PROC
_GlNormal3f:     PFNGLNORMAL3F_PROC

_GlBlendFunc:    PFNGLBLENDFUNC_PROC
_GlCullFace:     PFNGLCULLFACE_PROC
_GlDepthMask:    PFNGLDEPTHMASK_PROC
_GlDepthFunc:    PFNGLDEPTHFUNC_PROC
_GlColorMask:    PFNGLCOLORMASK_PROC
_GlLineWidth:    PFNGLLINEWIDTH_PROC
_GlPolygonMode:  PFNGLPOLYGONMODE_PROC
_GlScissor:      PFNGLSCISSOR_PROC
_GlViewport:     PFNGLVIEWPORT_PROC
_GlClearColor:   PFNGLCLEARCOLOR_PROC
_GlClear:        PFNGLCLEAR_PROC
_GlGetError:     PFNGLGETERROR_PROC

// Load the entry points we need. Returns true if all were resolved.
gl_custom_init :: proc() -> bool {
	ok := true
	_ = load_gl_proc(cast(^rawptr)&_GlEnablei,               "glEnablei")
    _ = load_gl_proc(cast(^rawptr)&_GlDisablei,              "glDisablei")
	_ = load_gl_proc(cast(^rawptr)&_GlBegin,      "glBegin")
    _ = load_gl_proc(cast(^rawptr)&_GlEnd,        "glEnd")
    _ = load_gl_proc(cast(^rawptr)&_GlVertex3f,   "glVertex3f")
    _ = load_gl_proc(cast(^rawptr)&_GlColor4ub,   "glColor4ub")
    _ = load_gl_proc(cast(^rawptr)&_GlTexCoord2f, "glTexCoord2f")
    _ = load_gl_proc(cast(^rawptr)&_GlNormal3f,   "glNormal3f")
	ok = ok && load_gl_proc(cast(^rawptr)&_BindTexture,   "glBindTexture")
	ok = ok && load_gl_proc(cast(^rawptr)&_DeleteTextures, "glDeleteTextures")
	ok = ok && load_gl_proc(cast(^rawptr)&_GenTextures,    "glGenTextures")
	ok = ok && load_gl_proc(cast(^rawptr)&_TexImage3D,     "glTexImage3D")
	ok = ok && load_gl_proc(cast(^rawptr)&_TexParameteri,  "glTexParameteri")
	ok = ok && load_gl_proc(cast(^rawptr)&_ActiveTexture,  "glActiveTexture")
	ok = ok && load_gl_proc(cast(^rawptr)&_PixelStorei,    "glPixelStorei")
    ok = ok && load_gl_proc(cast(^rawptr)&_GlEnable,         "glEnable")
    ok = ok && load_gl_proc(cast(^rawptr)&_GlDisable,        "glDisable")
    ok = ok && load_gl_proc(cast(^rawptr)&_GlBlendFunc,   "glBlendFunc")
    ok = ok && load_gl_proc(cast(^rawptr)&_GlCullFace,    "glCullFace")
    ok = ok && load_gl_proc(cast(^rawptr)&_GlDepthMask,   "glDepthMask")
    ok = ok && load_gl_proc(cast(^rawptr)&_GlDepthFunc,   "glDepthFunc")
    ok = ok && load_gl_proc(cast(^rawptr)&_GlColorMask,   "glColorMask")
    ok = ok && load_gl_proc(cast(^rawptr)&_GlLineWidth,   "glLineWidth")
    ok = ok && load_gl_proc(cast(^rawptr)&_GlPolygonMode, "glPolygonMode")
    ok = ok && load_gl_proc(cast(^rawptr)&_GlScissor,     "glScissor")
    ok = ok && load_gl_proc(cast(^rawptr)&_GlViewport,    "glViewport")
    ok = ok && load_gl_proc(cast(^rawptr)&_GlClearColor,  "glClearColor")
    ok = ok && load_gl_proc(cast(^rawptr)&_GlClear,       "glClear")
    ok = ok && load_gl_proc(cast(^rawptr)&_GlGetError,    "glGetError")

	return ok
}

// Thin wrappers that assert the pointers are loaded before calling.
GL_Enable   :: proc(cap: GLenum) { assert(_GlEnable  != nil, "glEnable not loaded");  _GlEnable(cap) }
GL_Disable  :: proc(cap: GLenum) { assert(_GlDisable != nil, "glDisable not loaded"); _GlDisable(cap) }

// Indexed versions fallback to non-indexed if unavailable (index must be 0)
GL_Enablei  :: proc(cap: GLenum, index: u32) {
    if _GlEnablei != nil { _GlEnablei(cap, index) }
    else { assert(index == 0, "glEnablei not available on this GL; index must be 0"); _GlEnable(cap) }
}
GL_Disablei :: proc(cap: GLenum, index: u32) {
    if _GlDisablei != nil { _GlDisablei(cap, index) }
    else { assert(index == 0, "glDisablei not available on this GL; index must be 0"); _GlDisable(cap) }
}

// ─────────── Corrected existing wrappers (copy-paste bug fixes) ───────────
GL_BindTexture    :: proc(target: GLenum, texture: GLuint) { assert(_BindTexture   != nil, "glBindTexture not loaded");   _BindTexture(target, texture) }
GL_DeleteTextures :: proc(n: i32, textures: [^]u32)        { assert(_DeleteTextures!= nil, "glDeleteTextures not loaded"); _DeleteTextures(n, textures) }
GL_GenTextures    :: proc(n: i32, textures: [^]u32)        { assert(_GenTextures   != nil, "glGenTextures not loaded");     _GenTextures(n, textures) }
GL_TexImage3D     :: proc(target, level, internal, width, height, depth, border, format, typ: i32, pixels: rawptr) {
    assert(_TexImage3D != nil, "glTexImage3D not loaded")
    _TexImage3D(target, level, internal, width, height, depth, border, format, typ, pixels)
}
GL_TexParameteri  :: proc(target, pname, param: i32)       { assert(_TexParameteri != nil, "glTexParameteri not loaded");  _TexParameteri(target, pname, param) }
GL_ActiveTexture  :: proc(texture: i32)                    { assert(_ActiveTexture != nil, "glActiveTexture not loaded");  _ActiveTexture(texture) }
GL_PixelStorei    :: proc(pname, param: i32)               { assert(_PixelStorei   != nil, "glPixelStorei not loaded");    _PixelStorei(pname, param) }

GL_Begin      :: proc(mode: GLenum)                { assert(_GlBegin   != nil, "glBegin not available (core profile). Use rlgl.rlBegin or a compat context."); _GlBegin(mode) }
GL_End        :: proc()                            { assert(_GlEnd     != nil, "glEnd not available (core profile)."); _GlEnd() }
GL_Vertex3f   :: proc(x, y, z: f32)                { assert(_GlVertex3f!= nil, "glVertex3f not available (core profile)."); _GlVertex3f(x, y, z) }
GL_Color4ub   :: proc(r, g, b, a: u8)              { assert(_GlColor4ub!= nil, "glColor4ub not available (core profile)."); _GlColor4ub(r,g,b,a) }
GL_TexCoord2f :: proc(u, v: f32)                   { assert(_GlTexCoord2f!= nil, "glTexCoord2f not available (core profile)."); _GlTexCoord2f(u,v) }
GL_Normal3f   :: proc(nx, ny, nz: f32)             { assert(_GlNormal3f!= nil, "glNormal3f not available (core profile)."); _GlNormal3f(nx,ny,nz) }

// State helpers
GL_BlendFunc  :: proc(sfactor, dfactor: GLenum)    { _GlBlendFunc(sfactor, dfactor) }
GL_CullFace   :: proc(mode: GLenum)                { _GlCullFace(mode) }
GL_DepthMask  :: proc(flag: GLboolean)             { _GlDepthMask(flag) }
GL_DepthFunc  :: proc(func: GLenum)                { _GlDepthFunc(func) }
GL_ColorMask  :: proc(r, g, b, a: GLboolean)       { _GlColorMask(r,g,b,a) }
GL_LineWidth  :: proc(w: f32)                      { _GlLineWidth(w) }
GL_PolygonMode:: proc(face, mode: GLenum)          { _GlPolygonMode(face, mode) }
GL_Scissor    :: proc(x, y, w, h: GLint)           { _GlScissor(x,y,w,h) }
GL_Viewport   :: proc(x, y, w, h: GLint)           { _GlViewport(x,y,w,h) }
GL_ClearColor :: proc(r, g, b, a: f32)             { _GlClearColor(r,g,b,a) }
GL_Clear      :: proc(mask: u32)                   { _GlClear(mask) }
GL_GetError   :: proc() -> u32                     { return _GlGetError() }
