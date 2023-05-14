type
  reaper_plugin_info_t* {.bycopy.} = object
    caller_version*: cint
    hwnd_main*: pointer
    Register*: proc(name: cstring, infostruct: pointer): cint {.cdecl.}
    GetFunc*: proc(name: cstring): pointer {.cdecl.}

var showConsoleMsg*: proc(msg: cstring) {.cdecl.}

proc loadReaperFunctions*(reaperPluginInfo: ptr reaper_plugin_info_t) =
  if reaperPluginInfo == nil:
    return
  showConsoleMsg = cast[typeof(showConsoleMsg)](reaperPluginInfo.GetFunc("ShowConsoleMsg"))