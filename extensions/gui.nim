{.experimental: "overloadableEnums".}

import opengl as gl
import ../clap
import ../userplugin

const consolaData = staticRead("consola.ttf")

proc onFrame(plugin: UserPlugin) =
  let (width, _) = plugin.window.size()
  let vg = plugin.vg
  vg.setTextAlign(Left, Top)
  vg.drawTextBox(0, 0, float(width), userplugin.debugString)

proc processFrame(plugin: UserPlugin) =
  plugin.window.makeContextCurrent()
  glClearColor(0.1, 0.1, 0.1, 1.0)
  glClear(GL_COLOR_BUFFER_BIT)
  let vg = plugin.vg
  let (width, height) = plugin.window.size
  let pixelDensity = plugin.window.dpi / 96.0
  vg.beginFrame(width, height, pixelDensity)
  onFrame(plugin)
  vg.endFrame(width, height)
  plugin.window.swapBuffers()

var extension* = clap.PluginGui(
  isApiSupported: proc(clapPlugin: ptr clap.Plugin, api: cstring, isFloating: bool): bool {.cdecl.} =
    return api == clap.windowApi and not isFloating
  ,
  getPreferredApi: proc(clapPlugin: ptr clap.Plugin, api: ptr cstring, isFloating: ptr bool): bool {.cdecl.} =
    api[] = clap.windowApi
    isFloating[] = false
    return true
  ,
  create: proc(clapPlugin: ptr clap.Plugin, api: cstring, isFloating: bool): bool {.cdecl.} =
    if not (api == clap.windowApi and not isFloating):
      return false

    let plugin = clapPlugin.getUserPlugin()
    plugin.window = OsWindow.new()
    plugin.window.makeContextCurrent()
    plugin.window.setDecorated(false)
    plugin.window.setPosition(0, 0)
    plugin.window.userData = cast[pointer](plugin)

    gl.loadExtensions()
    let (width, height) = plugin.window.size
    glViewport(0, 0, int32(width), int32(height))

    if plugin.vg == nil:
      plugin.vg = VectorGraphics.new()
      plugin.vg.addFont("Consola", consolaData)

    plugin.registerTimer("Gui", 0, proc(plugin: UserPlugin) =
      processFrame(plugin)
    )
    plugin.window.onClose = proc(window: OsWindow) =
      let plugin = cast[UserPlugin](window.userData)
      window.makeContextCurrent()
      if plugin.vg != nil:
        plugin.vg = nil
    plugin.window.onResize = proc(window: OsWindow, width, height: int) =
      glViewport(0, 0, int32(width), int32(height))
      processFrame(cast[UserPlugin](window.userData))
    plugin.window.onMouseMove = proc(window: OsWindow, x, y: int) =
      processFrame(cast[UserPlugin](window.userData))
    plugin.window.onMousePress = proc(window: OsWindow, button: MouseButton, x, y: int) =
      processFrame(cast[UserPlugin](window.userData))
    plugin.window.onMouseRelease = proc(window: OsWindow, button: MouseButton, x, y: int) =
      processFrame(cast[UserPlugin](window.userData))
    plugin.window.onMouseWheel = proc(window: OsWindow, x, y: float) =
      processFrame(cast[UserPlugin](window.userData))
    plugin.window.onMouseEnter = proc(window: OsWindow, x, y: int) =
      processFrame(cast[UserPlugin](window.userData))
    plugin.window.onMouseExit = proc(window: OsWindow, x, y: int) =
      processFrame(cast[UserPlugin](window.userData))
    plugin.window.onKeyPress = proc(window: OsWindow, key: KeyboardKey) =
      processFrame(cast[UserPlugin](window.userData))
    plugin.window.onKeyRelease = proc(window: OsWindow, key: KeyboardKey) =
      processFrame(cast[UserPlugin](window.userData))

    return true
  ,
  destroy: proc(clapPlugin: ptr clap.Plugin) {.cdecl.} =
    let plugin = clapPlugin.getUserPlugin()
    plugin.unregisterTimer("Gui")
    plugin.window.close()
  ,
  setScale: proc(clapPlugin: ptr clap.Plugin, scale: float64): bool {.cdecl.} =
    return false
  ,
  getSize: proc(clapPlugin: ptr clap.Plugin, width, height: ptr uint32): bool {.cdecl.} =
    let plugin = clapPlugin.getUserPlugin()
    let (w, h) = plugin.window.size()
    width[] = uint32(w)
    height[] = uint32(h)
    return true
  ,
  canResize: proc(clapPlugin: ptr clap.Plugin): bool {.cdecl.} =
    return true
  ,
  getResizeHints: proc(clapPlugin: ptr clap.Plugin, hints: ptr clap.GuiResizeHints): bool {.cdecl.} =
    hints.canResizeHorizontally = true
    hints.canResizeVertically = true
    hints.preserveAspectRatio = false
    return true
  ,
  adjustSize: proc(clapPlugin: ptr clap.Plugin, width, height: ptr uint32): bool {.cdecl.} =
    return true
  ,
  setSize: proc(clapPlugin: ptr clap.Plugin, width, height: uint32): bool {.cdecl.} =
    let plugin = clapPlugin.getUserPlugin()
    plugin.window.setPosition(0, 0)
    plugin.window.setSize(int(width), int(height))
    return true
  ,
  setParent: proc(clapPlugin: ptr clap.Plugin, window: ptr clap.Window): bool {.cdecl.} =
    let plugin = clapPlugin.getUserPlugin()
    plugin.window.embedInsideWindow(cast[pointer](window.union.win32))
    plugin.window.setPosition(0, 0)
    return true
  ,
  setTransient: proc(clapPlugin: ptr clap.Plugin, window: ptr clap.Window): bool {.cdecl.} =
    return false
  ,
  suggestTitle: proc(clapPlugin: ptr clap.Plugin, title: cstring) {.cdecl.} =
    discard
  ,
  show: proc(clapPlugin: ptr clap.Plugin): bool {.cdecl.} =
    let plugin = clapPlugin.getUserPlugin()
    plugin.window.show()
    return true
  ,
  hide: proc(clapPlugin: ptr clap.Plugin): bool {.cdecl.} =
    let plugin = clapPlugin.getUserPlugin()
    plugin.window.hide()
    return true
  ,
)