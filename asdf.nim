var pluginDescriptor = clap_plugin_descriptor_t(
  clap_version: clap_version_t(major: 1, minor: 1, revision: 7),
  id: "test.Plugin",
  name: "Plugin",
  vendor: "test",
  url: "",
  manual_url: "",
  support_url: "",
  version: "1.0.0",
  description: "",
  features: nil,
)

var audioPortsExtension = clap_plugin_audio_ports_t(
  count: proc(plugin: ptr clap_plugin_t, is_input: bool): uint32 {.cdecl.} =
    return 1

  , get: proc(plugin: ptr clap_plugin_t, index: uint32, is_input: bool, info: ptr clap_audio_port_info_t): bool {.cdecl.} =
    if index > 0:
      return false
    info.id = 0
    info.channel_count = 2
    info.flags = CLAP_AUDIO_PORT_IS_MAIN
    info.port_type = CLAP_PORT_STEREO
    info.in_place_pair = CLAP_INVALID_ID
    return true
)

var plugin = clap_plugin_t(
  desc: pluginDescriptor.addr,
  plugin_data: nil,

  init: proc(plugin: ptr clap_plugin_t): bool {.cdecl.} =
    return true

  , destroy: proc(plugin: ptr clap_plugin_t) {.cdecl.} =
    discard

  , activate: proc(plugin: ptr clap_plugin_t, sample_rate: cdouble, min_frames_count, max_frames_count: uint32): bool {.cdecl.} =
    return true

  , deactivate: proc(plugin: ptr clap_plugin_t) {.cdecl.} =
    discard

  , start_processing: proc(plugin: ptr clap_plugin_t): bool {.cdecl.} =
    return true

  , stop_processing: proc(plugin: ptr clap_plugin_t) {.cdecl.} =
    discard

  , reset: proc(plugin: ptr clap_plugin_t) {.cdecl.} =
    discard

  , process: proc(plugin: ptr clap_plugin_t, process: ptr clap_process_t): clap_process_status {.cdecl.} =
    let frameCount = process.frames_count
    for i in 0 ..< frameCount:
      let in_l = process.audio_inputs[0].data32[0][i]
      let in_r = process.audio_inputs[0].data32[1][i]

      let out_l = in_r
      let out_r = in_l

      process.audio_outputs[0].data32[0][i] = out_l
      process.audio_outputs[0].data32[1][i] = out_r

    return CLAP_PROCESS_CONTINUE

  , get_extension: proc(plugin: ptr clap_plugin_t, id: cstring): pointer {.cdecl.} =
    if id == CLAP_EXT_AUDIO_PORTS:
      return audioPortsExtension.addr
    return nil

  , on_main_thread: proc(plugin: ptr clap_plugin_t) {.cdecl.} =
    discard
)

var pluginFactory = clap_plugin_factory_t(
  get_plugin_count: proc(factory: ptr clap_plugin_factory_t): uint32 {.cdecl.} =
    return 1

  , get_plugin_descriptor: proc(factory: ptr clap_plugin_factory_t, index: uint32): ptr clap_plugin_descriptor_t {.cdecl.} =
    return pluginDescriptor.addr

  , create_plugin: proc(factory: ptr clap_plugin_factory_t, host: ptr clap_host_t, plugin_id: cstring): ptr clap_plugin_t {.cdecl.} =
    if not clap_version_is_compatible(host.clap_version):
      return nil

    return plugin.addr
)

proc NimMain() {.importc.}

proc init(plugin_path: cstring): bool {.cdecl.} =
  NimMain()
  return true

proc deinit() {.cdecl.} =
  discard

proc get_factory(factory_id: cstring): pointer {.cdecl.} =
  if factory_id == CLAP_PLUGIN_FACTORY_ID:
    return pluginFactory.addr

{.emit: """
CLAP_EXPORT const clap_plugin_entry_t clap_entry = {
  .clap_version = CLAP_VERSION_INIT,
  .init = `init`,
  .deinit = `deinit`,
  .get_factory = `get_factory`,
};
""".}