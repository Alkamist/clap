import ./binding
import ./shared
import ./extensions/reaper

var clapFactory = clap_plugin_factory_t(
  get_plugin_count: proc(factory: ptr clap_plugin_factory_t): uint32 {.cdecl.} =
    return uint32(pluginDispatchers.len)
  ,
  get_plugin_descriptor: proc(factory: ptr clap_plugin_factory_t, index: uint32): ptr clap_plugin_descriptor_t {.cdecl.} =
    return addr(pluginDispatchers[index].clapDescriptor)
  ,
  create_plugin: proc(factory: ptr clap_plugin_factory_t, host: ptr clap_host_t, plugin_id: cstring): ptr clap_plugin_t {.cdecl.} =
    if not clap_version_is_compatible(host.clap_version):
      return nil

    loadReaperFunctions(host)

    for i in 0 ..< pluginDispatchers.len:
      if pluginId == pluginDispatchers[i].clapDescriptor.id:
        return pluginDispatchers[i].createInstance(i, host)
)

proc NimMain() {.importc.}

proc mainInit(plugin_path: cstring): bool {.cdecl.} =
  NimMain()
  return true

proc mainDeinit() {.cdecl.} =
  discard

proc mainGetFactory(factoryId: cstring): pointer {.cdecl.} =
  if factoryId == CLAP_PLUGIN_FACTORY_ID:
    return addr(clapFactory)

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

CLAP_EXPORT const `clap_plugin_entry_t` clap_entry = {
  .clap_version = {1, 1, 8},
  .init = `mainInit`,
  .deinit = `mainDeinit`,
  .get_factory = `mainGetFactory`,
};
""".}