import std/algorithm
import clap

# This is a small demo of attempting to make a CLAP plugin with Nim.
# I am compiling with -d:release --app:lib --gc:arc --debugger:native
# https://github.com/free-audio/clap

type
  AudioPlugin* = ptr AudioPluginObj
  AudioPluginObj* = object
    clapPlugin*: clap_plugin_t
    foo*: seq[int]

var clapDescriptor = clap_plugin_descriptor_t(
  clap_version: CLAP_VERSION_INIT,
  id: "com.alkamist.DemoPlugin",
  name: "Demo Plugin",
  vendor: "Alkamist Audio",
  url: "",
  manual_url: "",
  support_url: "",
  version: "0.1.0",
  description: "",
)

proc pluginInit(plugin: ptr clap_plugin_t): bool {.cdecl.} =
  return true

# The plugin instance gets cleaned up here.
# This is called on the non-realtime main thread.
proc pluginDestroy(plugin: ptr clap_plugin_t) {.cdecl.} =
  let plugin = cast[AudioPlugin](plugin.plugin_data)
  freeShared(plugin)

proc pluginActivate(plugin: ptr clap_plugin_t, sample_rate: cdouble, min_frames_count, max_frames_count: uint32): bool {.cdecl.} =
  return true

proc pluginDeactivate(plugin: ptr clap_plugin_t) {.cdecl.} =
  discard

proc pluginStartProcessing(plugin: ptr clap_plugin_t): bool {.cdecl.} =
  return true

proc pluginStopProcessing(plugin: ptr clap_plugin_t) {.cdecl.} =
  discard

proc pluginReset(plugin: ptr clap_plugin_t) {.cdecl.} =
  discard

# This is called by the host on the realtime audio thread.
proc pluginProcess(plugin: ptr clap_plugin_t, process: ptr clap_process_t): clap_process_status {.cdecl.} =
  let plugin = cast[AudioPlugin](plugin.plugin_data)

  # This segfaults with --threads:on, no idea why.
  # The process ptr isn't even something I am allocating.
  # It works with --threads:off.
  let eventCount = process.in_events.size(process.in_events)

  plugin.foo.add(1)
  plugin.foo.add(3)
  plugin.foo.add(2)
  plugin.foo.add(5)
  plugin.foo.add(7)

  # This segfaults with threads on or off.
  plugin.foo.sort do (x, y: int) -> int:
    cmp(x, y)

  return CLAP_PROCESS_CONTINUE

proc pluginOnMainThread(plugin: ptr clap_plugin_t) {.cdecl.} =
  discard

proc pluginGetExtension(plugin: ptr clap_plugin_t, id: cstring): pointer {.cdecl.} =
  return nil

var clapFactory = clap_plugin_factory_t(
  get_plugin_count: proc(factory: ptr clap_plugin_factory_t): uint32 {.cdecl.} =
    return 1
  ,
  get_plugin_descriptor: proc(factory: ptr clap_plugin_factory_t, index: uint32): ptr clap_plugin_descriptor_t {.cdecl.} =
    return addr(clapDescriptor)
  ,

  # This function is threadsafe.
  create_plugin: proc(factory: ptr clap_plugin_factory_t, host: ptr clap_host_t, plugin_id: cstring): ptr clap_plugin_t {.cdecl.} =
    if not clap_version_is_compatible(host.clap_version):
      return nil

    # The plugin instance gets created here.
    # I've tried create, createShared, and calloc and nothing seems to work.
    if pluginId == clapDescriptor.id:
      var plugin = createShared(AudioPluginObj)
      plugin.clapPlugin = clap_plugin_t(
        desc: addr(clapDescriptor),
        plugin_data: cast[pointer](plugin),
        init: pluginInit,
        destroy: pluginDestroy,
        activate: pluginActivate,
        deactivate: pluginDeactivate,
        start_processing: pluginStartProcessing,
        stop_processing: pluginStopProcessing,
        reset: pluginReset,
        process: pluginProcess,
        get_extension: pluginGetExtension,
        on_main_thread: pluginOnMainThread,
      )
      return addr(plugin.clapPlugin)
)

# These three functions go in the plugin entry struct.
# I don't know how to do this without the emit pragma
# since Nim doesn't seem to want to export a struct variable.

proc mainInit(plugin_path: cstring): bool {.cdecl.} =
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