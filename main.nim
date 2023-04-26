{.experimental: "overloadableEnums".}

import clap
import plugin
import reaper

var clapFactory = clap.PluginFactory(
  getPluginCount: proc(factory: ptr clap.PluginFactory): uint32 {.cdecl.} =
    return 1
  ,
  getPluginDescriptor: proc(factory: ptr clap.PluginFactory, index: uint32): ptr clap.PluginDescriptor {.cdecl.} =
    plugin.descriptor.addr
  ,
  createPlugin: proc(factory: ptr clap.PluginFactory, host: ptr clap.Host, pluginId: cstring): ptr clap.Plugin {.cdecl.} =
    if not clap.versionIsCompatible(host.clapVersion):
      return nil

    reaper.loadFunctions(host)

    if pluginId == plugin.descriptor.id:
      return plugin.createInstance(host)
)

proc NimMain() {.importc.}

proc mainInit(plugin_path: cstring): bool {.cdecl.} =
  NimMain()
  return true

proc mainDeinit() {.cdecl.} =
  discard

proc mainGetFactory(factoryId: cstring): pointer {.cdecl.} =
  if factoryId == clap.pluginFactoryId:
    return clapFactory.addr

type MainPluginEntry = clap.PluginEntry

{.emit: """/*VARSECTION*/
#if !defined(CLAP_EXPORT)
#   if defined _WIN32 || defined __CYGWIN__
#      ifdef __GNUC__
#         define CLAP_EXPORT __attribute__((dllexport))
#      else
#         define CLAP_EXPORT __declspec(dllexport)
#      endif
#   else
#      if __GNUC__ >= 4 || defined(__clang__)
#         define CLAP_EXPORT __attribute__((visibility("default")))
#      else
#         define CLAP_EXPORT
#      endif
#   endif
#endif

CLAP_EXPORT const `MainPluginEntry` clap_entry = {
  .clapVersion = {1, 1, 7},
  .init = `mainInit`,
  .deinit = `mainDeinit`,
  .getFactory = `mainGetFactory`,
};
""".}