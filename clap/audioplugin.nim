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
): AudioPluginDispatcher =
  result = AudioPluginDispatcher()

  result.clapDescriptor = clap_plugin_descriptor_t(
    clap_version: clap_version_t(major: 1, minor: 1, revision: 8),
    id: id,
    name: name,
    vendor: vendor,
    url: url,
    manualUrl: manualUrl,
    supportUrl: supportUrl,
    version: version,
    description: description,
  )

  result.createInstance = proc(index: int, host: ptr clap_host_t): ptr clap_plugin_t =
    let plugin = T()
    GcRef(plugin)
    plugin.dispatcher = pluginDispatchers[index]
    plugin.clapHost = host
    plugin.clapPlugin = clap_plugin_t(
      desc: addr(pluginDispatchers[index].clapDescriptor),
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

  pluginDispatchers.add(result)

proc addParameter*(
  dispatcher: AudioPluginDispatcher,
  id: enum,
  name: string,
  minValue: float,
  maxValue: float,
  defaultValue: float,
  flags: set[ParamInfoFlags],
  module = "",
) =
  let idInt = int(id)

  if dispatcher.parameterInfo.len < idInt + 1:
    dispatcher.parameterInfo.setLen(idInt + 1)

  dispatcher.parameterInfo[idInt] = ParameterInfo(
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