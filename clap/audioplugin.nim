{.experimental: "codeReordering".}

import ./binding
import ./plugin
import ./shared; export shared

proc registerAudioPlugin*(
  T: type AudioPlugin,
  id: string,
  name: string,
  vendor: string,
  url: string,
  manualUrl: string,
  supportUrl: string,
  version: string,
  description: string,
): AudioPluginInfo =
  result = AudioPluginInfo()
  result.clapDescriptor = clap_plugin_descriptor_t(
    id: id,
    name: name,
    vendor: vendor,
    url: url,
    manualUrl: manualUrl,
    supportUrl: supportUrl,
    version: version,
    description: description,
  )
  pluginInfo.add(result)
  result.createInstance = proc(index: int, host: ptr clap_host_t): ptr clap_plugin_t =
    let plugin = T()
    GcRef(plugin)
    plugin.info = pluginInfo[index]
    plugin.clapHost = host
    plugin.clapPlugin = clap_plugin_t(
      desc: addr(pluginInfo[index].clapDescriptor),
      pluginData: cast[pointer](plugin),
      init: pluginInit,
      destroy: pluginDestroy,
      activate: pluginActivate,
      deactivate: pluginDeactivate,
      startProcessing: pluginStartProcessing,
      stopProcessing: pluginStopProcessing,
      reset: pluginReset,
      process: pluginProcess,
      getExtension: pluginGetExtension,
      onMainThread: pluginOnMainThread,
    )
    return addr(plugin.clapPlugin)

proc addParameter*(
  plugin: AudioPluginInfo,
  id: enum,
  name: string,
  minValue: float,
  maxValue: float,
  defaultValue: float,
  flags: set[ParamInfoFlags],
  module = "",
) =
  let idInt = int(id)
  if plugin.parameterInfo.len < idInt + 1:
    plugin.parameterInfo.setLen(idInt + 1)
  plugin.parameterInfo[idInt] = ParameterInfo(
    id: idInt,
    name: name,
    minValue: minValue,
    maxValue: maxValue,
    defaultValue: defaultValue,
    flags: flags,
    module: module,
  )

proc sendMidiEvent*(plugin: AudioPlugin, event: MidiEvent) =
  plugin.outputMidiEvents.add(event)

proc setLatency*(instance: AudioPlugin, value: int) =
  instance.latency = value

  # Inform the host of the latency change.
  let hostLatency = cast[ptr clap_host_latency_t](instance.clapHost.get_extension(instance.clapHost, CLAP_EXT_LATENCY))
  hostLatency.changed(instance.clapHost)
  if instance.isActive:
    instance.clapHost.requestRestart(instance.clapHost)