import clap
import nimgui
import nimgui/imploswindow

const consolaData = staticRead("consola.ttf")

var debugOutput = ""

type
  GainPluginParameter* = enum
    Gain

  GainPlugin* = ref object of clap.Plugin
    gui*: Gui

var gainPluginDescriptor = clap.descriptor(
  id = "com.alkamist.gain",
  name = "Gain",
  vendor = "Alkamist Audio",
  url = "",
  manualUrl = "",
  supportUrl = "",
  version = "0.1.0",
  description = "",
)

proc init*(plugin: GainPlugin) =
  plugin.addParameter(Gain, "Gain", 0.0, 1.0, 0.7)

proc createGui*(plugin: GainPlugin) =
  plugin.gui = newGui()
  plugin.gui.backgroundColor = rgb(49, 51, 56)
  plugin.gui.gfx.addFont("consola", consolaData)

  let window1 = plugin.gui.addWindow()
  window1.position = vec2(50, 50)
  window1.size = vec2(500, 500)
  window1.addTitle("Window 1")

  let txt = window1.body.addText()
  txt.dontClip = true
  txt.passInput = true
  txt.updateHook:
    self.size = window1.size
    self.data = debugOutput

  let p = plugin
  plugin.window.onFrame = proc() =
    implOsWindow(p.gui, p.window)

proc destroyGui*(plugin: GainPlugin) =
  plugin.gui = nil

proc processNote*(plugin: GainPlugin, note: Note) =
  debugOutput = $note

proc processAudio*(plugin: GainPlugin, inputs, outputs: openArray[AudioBuffer], startFrame, endFrame: int) =
  for c in 0 ..< outputs[0].channelCount:
    for s in startFrame ..< endFrame:
      outputs[0][c][s] = inputs[0][c][s] * plugin.parameter(Gain)

clap.exportPlugin(GainPlugin, gainPluginDescriptor)