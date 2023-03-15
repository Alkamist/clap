import clap

type
  GainPlugin* = ref object of ClapPlugin
    gain*: float

method processParameterValueEvent*(plugin: GainPlugin, event: ParameterValueEvent) =
  plugin.gain = event.value

method processAudio*(plugin: GainPlugin, inputs, outputs: HostAudioBuffer, start, finish: int) =
  let channelCount = outputs[0].channelCount
  for c in 0 ..< channelCount:
    for s in start ..< finish:
      outputs[0].data32[c][s] = inputs[0].data32[c][s] * 0.5

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