import clap

type
  GainPlugin* = ref object of clap.Plugin

method init*(plugin: GainPlugin) =
  plugin.addParameter(
    name = "Gain",
    module = "",
    minValue = 0.0,
    maxValue = 1.0,
    defaultValue = 0.7,
  )

method processAudio*(plugin: GainPlugin, inputs, outputs: openArray[AudioBuffer], startFrame, endFrame: int) =
  for c in 0 ..< outputs[0].channelCount:
    for s in startFrame ..< endFrame:
      outputs[0][c][s] = inputs[0][c][s] * plugin.parameter(0)

clap.addPlugin(GainPlugin,
  id = "com.alkamist.gain",
  name = "Gain",
  vendor = "Alkamist Audio",
  url = "",
  manualUrl = "",
  supportUrl = "",
  version = "0.1.0",
  description = "",
)