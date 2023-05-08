# import ../binding

# type
#   reaper_plugin_info_t* {.bycopy.} = object
#     caller_version*: cint
#     hwnd_main*: pointer
#     Register*: proc(name: cstring, infostruct: pointer): cint {.cdecl.}
#     GetFunc*: proc(name: cstring): pointer {.cdecl.}

# var showConsoleMsg*: proc(msg: cstring) {.cdecl.}
# var showMessageBox*: proc(msg: cstring, title: cstring, `type`: cint): cint {.cdecl.}

# proc loadReaperFunctions*(host: ptr clap_host_t) =
#   var reaperPluginInfo = cast[ptr reaper_plugin_info_t](host.get_extension(host, "cockos.reaper_extension"))
#   showConsoleMsg = cast[typeof(showConsoleMsg)](reaperPluginInfo.GetFunc("ShowConsoleMsg"))
#   showMessageBox = cast[typeof(showMessageBox)](reaperPluginInfo.GetFunc("ShowMessageBox"))