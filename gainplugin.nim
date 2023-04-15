import clap

let gainPlugin = clap.Plugin()

gainPlugin.id = "com.alkamist.gain"
gainPlugin.name = "Gain"
gainPlugin.vendor = "Alkamist Audio"
gainPlugin.url = ""
gainPlugin.manualUrl = ""
gainPlugin.supportUrl = ""
gainPlugin.version = "0.1.0"
gainPlugin.description = ""

gainPlugin.init = proc(plugin: Plugin) =
  plugin.addParameter(
    name = "Gain",
    module = "",
    minValue = 0.0,
    maxValue = 1.0,
    defaultValue = 0.7,
  )

gainPlugin.processAudio = proc(plugin: Plugin, inputs, outputs: openArray[AudioBuffer], startFrame, endFrame: int) =
  for c in 0 ..< outputs[0].channelCount:
    for s in startFrame ..< endFrame:
      outputs[0][c][s] = inputs[0][c][s] * plugin.parameter(0)

clap.plugins.add(gainPlugin)