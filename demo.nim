import clap

type
  AudioPlugin* = ref object of RootObj
    clapPlugin*: clap_plugin_t

proc pluginInit[T](plugin: ptr clap_plugin_t): bool {.cdecl.} =
  mixin init
  let plugin = cast[T](plugin.plugin_data)
  plugin.init()
  return true

proc pluginDestroy[T](plugin: ptr clap_plugin_t) {.cdecl.} =
  mixin destroy
  let plugin = cast[T](plugin.plugin_data)
  plugin.destroy()
  GcUnref(plugin)

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

proc pluginProcess(plugin: ptr clap_plugin_t, process: ptr clap_process_t): clap_process_status {.cdecl.} =
  return CLAP_PROCESS_CONTINUE

proc pluginOnMainThread(plugin: ptr clap_plugin_t) {.cdecl.} =
  discard

proc pluginGetExtension(plugin: ptr clap_plugin_t, id: cstring): pointer {.cdecl.} =
  return nil

proc exportClapPlugin*[T](
  id: string,
  name: string,
  vendor: string,
  url: string,
  manualUrl: string,
  supportUrl: string,
  version: string,
  description: string,
) =
  var clapDescriptor {.global.}: clap_plugin_descriptor_t
  clapDescriptor.clap_version = CLAP_VERSION_INIT
  clapDescriptor.id = id
  clapDescriptor.name = name
  clapDescriptor.vendor = vendor
  clapDescriptor.url = url
  clapDescriptor.manualUrl = manualUrl
  clapDescriptor.supportUrl = supportUrl
  clapDescriptor.version = version
  clapDescriptor.description = description

  var clapFactory {.global.} = clap_plugin_factory_t(
    get_plugin_count: proc(factory: ptr clap_plugin_factory_t): uint32 {.cdecl.} =
      return 1
    ,
    get_plugin_descriptor: proc(factory: ptr clap_plugin_factory_t, index: uint32): ptr clap_plugin_descriptor_t {.cdecl.} =
      return addr(clapDescriptor)
    ,
    create_plugin: proc(factory: ptr clap_plugin_factory_t, host: ptr clap_host_t, plugin_id: cstring): ptr clap_plugin_t {.cdecl.} =
      if not clap_version_is_compatible(host.clap_version):
        return nil

      if pluginId == clapDescriptor.id:
        var plugin = T()
        GcRef(plugin)
        plugin.clapPlugin = clap_plugin_t(
          desc: addr(clapDescriptor),
          plugin_data: cast[pointer](plugin),
          init: pluginInit[T],
          destroy: pluginDestroy[T],
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
    ,
  )

  var clapEntry {.global, exportc: "clap_entry", dynlib.} = clap_plugin_entry_t(
    clap_version: CLAP_VERSION_INIT,
    init: proc(plugin_path: cstring): bool {.cdecl.} =
      return true
    ,
    deinit: proc() {.cdecl.} =
      discard
    ,
    get_factory: proc(factoryId: cstring): pointer {.cdecl.} =
      if factoryId == CLAP_PLUGIN_FACTORY_ID:
        return addr(clapFactory)
    ,
  )