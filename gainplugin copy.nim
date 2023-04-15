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

method processAudio*(plugin: GainPlugin, inputs, outputs: HostAudioBuffer, start, finish: int) =
  let channelCount = outputs[0].channelCount
  for c in 0 ..< channelCount:
    for s in start ..< finish:
      outputs[0].data32[c][s] = inputs[0].data32[c][s] * plugin.parameters[0].value
      # outputs[0].data32[c][s] = inputs[0].data32[c][s] * plugin.parameterValueAudioThread[0]

clap.addPlugin(GainPlugin,
  id = "com.alkamist.gain",
  name = "Gain",
  vendor = "Alkamist Audio",
  url = "",
  manualUrl = "",
  supportUrl = "",
  version = "0.1.0",
  description = "",
  features = ["utility", "mixing"],
)