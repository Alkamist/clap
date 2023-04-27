{.experimental: "overloadableEnums".}

import nimgui/imploswindow
import ./timer
import ../clap
import ../userplugin

const consolaData = staticRead("consola.ttf")

proc makeGui*(plugin: UserPlugin) =
  let gui = plugin.gui
  let text = gui.addText()
  text.alignX = Center
  text.alignY = Baseline
  text.updateHook:
    self.size = self.gui.size
    if debugStringChanged:
      self.data = debugString
      debugString = ""
      debugStringChanged = false

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

    plugin.window = newOsWindow()
    plugin.window.setDecorated(false)
    plugin.window.setPosition(0, 0)
    plugin.window.setSize(plugin.window.widthPixels, plugin.window.heightPixels)
    plugin.gui = newGui()
    plugin.gui.backgroundColor = rgb(49, 51, 56)
    plugin.gui.gfx.addFont("consola", consolaData)
    plugin.makeGui()

    let gui = plugin.gui
    let window = plugin.window
    plugin.window.onFrame = proc() =
      implOsWindow(gui, window)

    plugin.registerTimer("Gui", 0, proc() =
      window.process()
    )

    return true
  ,
  destroy: proc(clapPlugin: ptr clap.Plugin) {.cdecl.} =
    let plugin = clapPlugin.getUserPlugin()
    plugin.unregisterTimer("Gui")
    plugin.window.close()
    plugin.gui = nil
  ,
  setScale: proc(clapPlugin: ptr clap.Plugin, scale: float64): bool {.cdecl.} =
    return false
  ,
  getSize: proc(clapPlugin: ptr clap.Plugin, width, height: ptr uint32): bool {.cdecl.} =
    let plugin = clapPlugin.getUserPlugin()
    width[] = uint32(plugin.window.widthPixels)
    height[] = uint32(plugin.window.heightPixels)
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
    plugin.window.setSize(width.int, height.int)
    return true
  ,
  setParent: proc(clapPlugin: ptr clap.Plugin, window: ptr clap.Window): bool {.cdecl.} =
    let plugin = clapPlugin.getUserPlugin()
    plugin.window.embedInsideWindow(cast[pointer](window.union.win32))
    plugin.window.setPosition(0, 0)
    plugin.window.setSize(plugin.window.widthPixels, plugin.window.heightPixels)
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