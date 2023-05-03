{.experimental: "overloadableEnums".}
{.experimental: "codeReordering".}

import std/unicode; export unicode
import winim/lean as win32

const WM_DPICHANGED = 0x02E0
const DPI_AWARENESS_CONTEXT_PER_MONITOR_AWARE_V2 = -4
proc SetProcessDpiAwarenessContext(value: int): BOOL {.discardable, stdcall, dynlib: "user32", importc.}
proc GetDpiForWindow(hWnd: HWND): UINT {.discardable, stdcall, dynlib: "user32", importc.}

type
  ChildStatus* = enum
    None
    Embedded
    Floating

  CursorStyle* = enum
    Arrow
    IBeam
    Crosshair
    PointingHand
    ResizeLeftRight
    ResizeTopBottom
    ResizeTopLeftBottomRight
    ResizeTopRightBottomLeft

  MouseButton* = enum
    Unknown,
    Left, Middle, Right,
    Extra1, Extra2, Extra3,
    Extra4, Extra5,

  KeyboardKey* = enum
    Unknown,
    A, B, C, D, E, F, G, H, I,
    J, K, L, M, N, O, P, Q, R,
    S, T, U, V, W, X, Y, Z,
    Key1, Key2, Key3, Key4, Key5,
    Key6, Key7, Key8, Key9, Key0,
    Pad1, Pad2, Pad3, Pad4, Pad5,
    Pad6, Pad7, Pad8, Pad9, Pad0,
    F1, F2, F3, F4, F5, F6, F7,
    F8, F9, F10, F11, F12,
    Backtick, Minus, Equal, Backspace,
    Tab, CapsLock, Enter, LeftShift,
    RightShift, LeftControl, RightControl,
    LeftAlt, RightAlt, LeftMeta, RightMeta,
    LeftBracket, RightBracket, Space,
    Escape, Backslash, Semicolon, Quote,
    Comma, Period, Slash, ScrollLock,
    Pause, Insert, End, PageUp, Delete,
    Home, PageDown, LeftArrow, RightArrow,
    DownArrow, UpArrow, NumLock, PadDivide,
    PadMultiply, PadSubtract, PadAdd, PadEnter,
    PadPeriod, PrintScreen,

  OsWindow* = ref object
    userData*: pointer
    onClose*: proc(window: OsWindow)
    onMove*: proc(window: OsWindow, x, y: int)
    onResize*: proc(window: OsWindow, width, height: int)
    onMouseMove*: proc(window: OsWindow, x, y: int)
    onMousePress*: proc(window: OsWindow, button: MouseButton, x, y: int)
    onMouseRelease*: proc(window: OsWindow, button: MouseButton, x, y: int)
    onMouseEnter*: proc(window: OsWindow, x, y: int)
    onMouseExit*: proc(window: OsWindow, x, y: int)
    onMouseWheel*: proc(window: OsWindow, x, y: float)
    onKeyPress*: proc(window: OsWindow, key: KeyboardKey)
    onKeyRelease*: proc(window: OsWindow, key: KeyboardKey)
    onRune*: proc(window: OsWindow, r: unicode.Rune)
    onDpiChange*: proc(window: OsWindow, dpi: float)
    isOpen*: bool
    isDecorated*: bool
    isHovered*: bool
    childStatus*: ChildStatus
    m_cursorX: int
    m_cursorY: int
    m_hwnd: win32.HWND
    m_hdc: win32.HDC
    m_hglrc: win32.HGLRC

var windowCount = 0
const windowClassName = "DefaultWindowClass"

proc `=destroy`*(window: var type OsWindow()[]) =
  if window.isOpen:
    window.isOpen = false
    win32.DestroyWindow(window.m_hwnd)

proc new*(T: type OsWindow, parentHandle: pointer = nil): OsWindow =
  result = OsWindow()

  var hinstance = win32.GetModuleHandle(nil)

  if windowCount == 0:
    var windowClass = win32.WNDCLASSEX(
      cbSize: win32.UINT(sizeof(win32.WNDCLASSEX)),
      style: win32.CS_OWNDC,
      lpfnWndProc: windowProc,
      hInstance: hinstance,
      hCursor: win32.LoadCursor(0, win32.IDC_ARROW),
      lpszClassName: windowClassName,
    )
    win32.RegisterClassEx(addr(windowClass))

  var windowStyle = win32.WS_OVERLAPPEDWINDOW
  if parentHandle != nil:
    result.childStatus = Floating
    windowStyle = windowStyle or win32.WS_POPUP

  result.m_hwnd = win32.CreateWindowEx(
    0,
    windowClassName,
    nil,
    win32.DWORD(windowStyle),
    win32.DWORD(win32.CW_USEDEFAULT),
    win32.DWORD(win32.CW_USEDEFAULT),
    win32.DWORD(win32.CW_USEDEFAULT),
    win32.DWORD(win32.CW_USEDEFAULT),
    GetDesktopWindow(),
    0,
    hinstance,
    cast[pointer](result),
  )
  if result.m_hwnd == 0:
    echo "Failed to open window."

  result.isOpen = true
  result.isDecorated = true
  (result.m_cursorX, result.m_cursorY) = result.cursorPosition

  SetProcessDpiAwarenessContext(DPI_AWARENESS_CONTEXT_PER_MONITOR_AWARE_V2)

  initOpenGlContext(result)

  windowCount += 1

proc close*(window: OsWindow) =
  if window.isOpen:
    window.isOpen = false
    win32.DestroyWindow(window.m_hwnd)

proc pollEvents*(window: OsWindow) =
  if window.childStatus == None:
    var msg: win32.MSG
    while win32.PeekMessage(addr(msg), window.m_hwnd, 0, 0, win32.PM_REMOVE) != win32.FALSE:
      win32.TranslateMessage(addr(msg))
      win32.DispatchMessage(addr(msg))

proc swapBuffers*(window: OsWindow) =
  win32.SwapBuffers(window.m_hdc)

proc makeContextCurrent*(window: OsWindow) =
  win32.wglMakeCurrent(window.m_hdc, window.m_hglrc)

proc setCursorStyle*(window: OsWindow, style: CursorStyle) =
  win32.SetCursor(win32.LoadCursor(0, style.toWin32CursorStyle))

proc cursorPosition*(window: OsWindow): (int, int) =
  var pos: win32.POINT
  if win32.GetCursorPos(addr(pos)):
    win32.ScreenToClient(window.m_hwnd, addr(pos))
    return (int(pos.x), int(pos.y))

proc position*(window: OsWindow): (int, int) =
  var pos: win32.POINT
  win32.ClientToScreen(window.m_hwnd, addr(pos))
  return (int(pos.x), int(pos.y))

proc setPosition*(window: OsWindow, x, y: int) =
  win32.SetWindowPos(
    window.m_hwnd, 0,
    int32(x), int32(y),
    0, 0,
    win32.SWP_NOACTIVATE or win32.SWP_NOZORDER or win32.SWP_NOSIZE,
  )

proc size*(window: OsWindow): (int, int) =
  var area: win32.RECT
  win32.GetClientRect(window.m_hwnd, addr(area))
  return (int(area.right), int(area.bottom))

proc setSize*(window: OsWindow, width, height: int) =
  win32.SetWindowPos(
    window.m_hwnd, 0,
    0, 0,
    int32(width), int32(height),
    win32.SWP_NOACTIVATE or win32.SWP_NOOWNERZORDER or win32.SWP_NOMOVE or win32.SWP_NOZORDER,
  )

proc dpi*(window: OsWindow): float =
  return float(GetDpiForWindow(window.m_hwnd))

proc setDecorated*(window: OsWindow, decorated: bool) =
  window.isDecorated = decorated

proc embedInsideWindow*(window: OsWindow, parent: pointer) =
  if window.childStatus != Embedded:
    win32.SetWindowLongPtr(
      window.m_hwnd,
      win32.GWL_STYLE,
      int(win32.WS_CHILDWINDOW or win32.WS_CLIPSIBLINGS),
    )
    window.childStatus = Embedded
    window.setDecorated(false)
    var (x, y) = window.position()
    var (width, height) = window.size()
    win32.SetWindowPos(
      window.m_hwnd,
      win32.HWND_TOPMOST,
      int32(x), int32(y),
      int32(width), int32(height),
      win32.SWP_SHOWWINDOW,
    )
  win32.SetParent(window.m_hwnd, cast[win32.HWND](parent))

proc show*(window: OsWindow) =
  win32.ShowWindow(window.m_hwnd, win32.SW_SHOW)

proc hide*(window: OsWindow) =
  win32.ShowWindow(window.m_hwnd, win32.SW_HIDE)

proc initOpenGlContext(window: OsWindow) =
  var pfd = PIXELFORMATDESCRIPTOR(
    nSize: sizeof(PIXELFORMATDESCRIPTOR).WORD,
    nVersion: 1,
    dwFlags: PFD_DRAW_TO_WINDOW or PFD_SUPPORT_OPENGL or PFD_SUPPORT_COMPOSITION or PFD_DOUBLEBUFFER,
    iPixelType: PFD_TYPE_RGBA,
    cColorBits: 32,
    cRedBits: 0, cRedShift: 0,
    cGreenBits: 0, cGreenShift: 0,
    cBlueBits: 0, cBlueShift: 0,
    cAlphaBits: 0, cAlphaShift: 0,
    cAccumBits: 0,
    cAccumRedBits: 0,
    cAccumGreenBits: 0,
    cAccumBlueBits: 0,
    cAccumAlphaBits: 0,
    cDepthBits: 32,
    cStencilBits: 8,
    cAuxBuffers: 0,
    iLayerType: PFD_MAIN_PLANE,
    bReserved: 0,
    dwLayerMask: 0,
    dwVisibleMask: 0,
    dwDamageMask: 0,
  )

  window.m_hdc = win32.GetDC(window.m_hwnd)
  win32.SetPixelFormat(
    window.m_hdc,
    win32.ChoosePixelFormat(window.m_hdc, addr(pfd)),
    addr(pfd),
  )

  window.m_hglrc = win32.wglCreateContext(window.m_hdc)
  win32.wglMakeCurrent(window.m_hdc, window.m_hglrc)

  win32.ReleaseDC(window.m_hwnd, window.m_hdc)

proc windowProc(hwnd: win32.HWND, msg: win32.UINT, wparam: win32.WPARAM, lparam: win32.LPARAM): win32.LRESULT {.stdcall.} =
  if msg == win32.WM_CREATE:
    var lpcs = cast[win32.LPCREATESTRUCT](lparam)
    win32.SetWindowLongPtr(hwnd, win32.GWLP_USERDATA, cast[win32.LONG_PTR](lpcs.lpCreateParams))

  var window = cast[OsWindow](win32.GetWindowLongPtr(hwnd, win32.GWLP_USERDATA))
  if window == nil or hwnd != window.m_hwnd:
    return win32.DefWindowProc(hwnd, msg, wparam, lparam)

  case msg:

  of win32.WM_MOVE:
    if window.onMove != nil:
      window.onMove(
        window,
        int(win32.GET_X_LPARAM(lparam)),
        int(win32.GET_Y_LPARAM(lparam)),
      )

  of win32.WM_SIZE:
    if window.onResize != nil:
      window.onResize(
        window,
        int(win32.LOWORD(cast[win32.DWORD](lparam))),
        int(win32.HIWORD(cast[win32.DWORD](lparam))),
      )

  of win32.WM_CLOSE:
    window.close()

  of win32.WM_DESTROY:
    if window.onClose != nil:
      window.onClose(window)
    if windowCount > 0:
      windowCount -= 1
      if windowCount == 0:
        win32.UnregisterClass(windowClassName, 0)

  of WM_DPICHANGED:
    if window.onDpiChange != nil:
      window.onDpiChange(window, float(GetDpiForWindow(window.m_hwnd)))

  of win32.WM_MOUSEMOVE:
    window.m_cursorX = int(win32.GET_X_LPARAM(lparam))
    window.m_cursorY = int(win32.GET_Y_LPARAM(lparam))

    if not window.isHovered:
      var tme: win32.TTRACKMOUSEEVENT
      tme.cbSize = win32.DWORD(sizeof(tme))
      tme.dwFlags = win32.TME_LEAVE
      tme.hwndTrack = window.m_hwnd
      win32.TrackMouseEvent(addr(tme))
      window.isHovered = true
      if window.onMouseEnter != nil:
        window.onMouseEnter(window, window.m_cursorX, window.m_cursorY)

    if window.onMouseMove != nil:
      window.onMouseMove(window, window.m_cursorX, window.m_cursorY)

  of win32.WM_MOUSELEAVE:
      window.isHovered = false
      if window.onMouseExit != nil:
        window.onMouseExit(window, window.m_cursorX, window.m_cursorY)

  of win32.WM_MOUSEWHEEL:
    if window.onMouseWheel != nil:
      window.onMouseWheel(
        window,
        0,
        float(win32.GET_WHEEL_DELTA_WPARAM(wparam)) / win32.WHEEL_DELTA,
      )

  of win32.WM_MOUSEHWHEEL:
    if window.onMouseWheel != nil:
      window.onMouseWheel(
        window,
        float(win32.GET_WHEEL_DELTA_WPARAM(wparam)) / win32.WHEEL_DELTA,
        0,
      )

  of win32.WM_LBUTTONDOWN, win32.WM_LBUTTONDBLCLK,
     win32.WM_MBUTTONDOWN, win32.WM_MBUTTONDBLCLK,
     win32.WM_RBUTTONDOWN, win32.WM_RBUTTONDBLCLK,
     win32.WM_XBUTTONDOWN, win32.WM_XBUTTONDBLCLK:
    window.m_cursorX = int(win32.GET_X_LPARAM(lparam))
    window.m_cursorY = int(win32.GET_Y_LPARAM(lparam))
    win32.SetCapture(window.m_hwnd)
    if window.onMousePress != nil:
      window.onMousePress(window, toMouseButton(msg, wparam), window.m_cursorX, window.m_cursorY)

  of win32.WM_LBUTTONUP, win32.WM_MBUTTONUP, win32.WM_RBUTTONUP, win32.WM_XBUTTONUP:
    window.m_cursorX = int(win32.GET_X_LPARAM(lparam))
    window.m_cursorY = int(win32.GET_Y_LPARAM(lparam))
    win32.ReleaseCapture()
    if window.onMouseRelease != nil:
      window.onMouseRelease(window, toMouseButton(msg, wparam), window.m_cursorX, window.m_cursorY)

  of win32.WM_KEYDOWN, win32.WM_SYSKEYDOWN:
    if window.on_key_press != nil:
      window.on_key_press(window, toKeyboardKey(wparam, lparam))

  of win32.WM_KEYUP, win32.WM_SYSKEYUP:
    if window.onKeyRelease != nil:
      window.onKeyRelease(window, toKeyboardKey(wparam, lparam))

  of win32.WM_CHAR, win32.WM_SYSCHAR:
    if wparam > 0 and wparam < 0x10000:
      if window.onRune != nil:
          window.onRune(window, cast[unicode.Rune](wparam))

  of win32.WM_NCCALCSIZE:
    if not window.isDecorated:
      return 0

  else:
    discard

  return win32.DefWindowProc(hwnd, msg, wparam, lparam)

proc toWin32CursorStyle(style: CursorStyle): win32.LPTSTR =
  return case style:
    of Arrow: win32.IDC_ARROW
    of IBeam: win32.IDC_IBEAM
    of Crosshair: win32.IDC_CROSS
    of PointingHand: win32.IDC_HAND
    of ResizeLeftRight: win32.IDC_SIZEWE
    of ResizeTopBottom: win32.IDC_SIZENS
    of ResizeTopLeftBottomRight: win32.IDC_SIZENWSE
    of ResizeTopRightBottomLeft: win32.IDC_SIZENESW

func toMouseButton(msg: win32.UINT, wParam: win32.WPARAM): MouseButton =
  return case msg:
  of WM_LBUTTONDOWN, WM_LBUTTONUP, WM_LBUTTONDBLCLK:
    MouseButton.Left
  of WM_MBUTTONDOWN, WM_MBUTTONUP, WM_MBUTTONDBLCLK:
    MouseButton.Middle
  of WM_RBUTTONDOWN, WM_RBUTTONUP, WM_RBUTTONDBLCLK:
    MouseButton.Right
  of WM_XBUTTONDOWN, WM_XBUTTONUP, WM_XBUTTONDBLCLK:
    if HIWORD(wParam) == 1:
      MouseButton.Extra1
    else:
      MouseButton.Extra2
  else:
    MouseButton.Unknown

func toKeyboardKey(wParam: win32.WPARAM, lParam: win32.LPARAM): KeyboardKey =
  let scanCode = win32.LOBYTE(win32.HIWORD(lParam))
  let isRight = (win32.HIWORD(lParam) and win32.KF_EXTENDED) == win32.KF_EXTENDED
  return case scanCode:
    of 42: KeyboardKey.LeftShift
    of 54: KeyboardKey.RightShift
    of 29:
      if isRight: KeyboardKey.RightControl else: KeyboardKey.LeftControl
    of 56:
      if isRight: KeyboardKey.RightAlt else: KeyboardKey.LeftAlt
    else:
      case wParam.int:
      of 8: KeyboardKey.Backspace
      of 9: KeyboardKey.Tab
      of 13: KeyboardKey.Enter
      of 19: KeyboardKey.Pause
      of 20: KeyboardKey.CapsLock
      of 27: KeyboardKey.Escape
      of 32: KeyboardKey.Space
      of 33: KeyboardKey.PageUp
      of 34: KeyboardKey.PageDown
      of 35: KeyboardKey.End
      of 36: KeyboardKey.Home
      of 37: KeyboardKey.LeftArrow
      of 38: KeyboardKey.UpArrow
      of 39: KeyboardKey.RightArrow
      of 40: KeyboardKey.DownArrow
      of 45: KeyboardKey.Insert
      of 46: KeyboardKey.Delete
      of 48: KeyboardKey.Key0
      of 49: KeyboardKey.Key1
      of 50: KeyboardKey.Key2
      of 51: KeyboardKey.Key3
      of 52: KeyboardKey.Key4
      of 53: KeyboardKey.Key5
      of 54: KeyboardKey.Key6
      of 55: KeyboardKey.Key7
      of 56: KeyboardKey.Key8
      of 57: KeyboardKey.Key9
      of 65: KeyboardKey.A
      of 66: KeyboardKey.B
      of 67: KeyboardKey.C
      of 68: KeyboardKey.D
      of 69: KeyboardKey.E
      of 70: KeyboardKey.F
      of 71: KeyboardKey.G
      of 72: KeyboardKey.H
      of 73: KeyboardKey.I
      of 74: KeyboardKey.J
      of 75: KeyboardKey.K
      of 76: KeyboardKey.L
      of 77: KeyboardKey.M
      of 78: KeyboardKey.N
      of 79: KeyboardKey.O
      of 80: KeyboardKey.P
      of 81: KeyboardKey.Q
      of 82: KeyboardKey.R
      of 83: KeyboardKey.S
      of 84: KeyboardKey.T
      of 85: KeyboardKey.U
      of 86: KeyboardKey.V
      of 87: KeyboardKey.W
      of 88: KeyboardKey.X
      of 89: KeyboardKey.Y
      of 90: KeyboardKey.Z
      of 91: KeyboardKey.LeftMeta
      of 92: KeyboardKey.RightMeta
      of 96: KeyboardKey.Pad0
      of 97: KeyboardKey.Pad1
      of 98: KeyboardKey.Pad2
      of 99: KeyboardKey.Pad3
      of 100: KeyboardKey.Pad4
      of 101: KeyboardKey.Pad5
      of 102: KeyboardKey.Pad6
      of 103: KeyboardKey.Pad7
      of 104: KeyboardKey.Pad8
      of 105: KeyboardKey.Pad9
      of 106: KeyboardKey.PadMultiply
      of 107: KeyboardKey.PadAdd
      of 109: KeyboardKey.PadSubtract
      of 110: KeyboardKey.PadPeriod
      of 111: KeyboardKey.PadDivide
      of 112: KeyboardKey.F1
      of 113: KeyboardKey.F2
      of 114: KeyboardKey.F3
      of 115: KeyboardKey.F4
      of 116: KeyboardKey.F5
      of 117: KeyboardKey.F6
      of 118: KeyboardKey.F7
      of 119: KeyboardKey.F8
      of 120: KeyboardKey.F9
      of 121: KeyboardKey.F10
      of 122: KeyboardKey.F11
      of 123: KeyboardKey.F12
      of 144: KeyboardKey.NumLock
      of 145: KeyboardKey.ScrollLock
      of 186: KeyboardKey.Semicolon
      of 187: KeyboardKey.Equal
      of 188: KeyboardKey.Comma
      of 189: KeyboardKey.Minus
      of 190: KeyboardKey.Period
      of 191: KeyboardKey.Slash
      of 192: KeyboardKey.Backtick
      of 219: KeyboardKey.LeftBracket
      of 220: KeyboardKey.BackSlash
      of 221: KeyboardKey.RightBracket
      of 222: KeyboardKey.Quote
      else: KeyboardKey.Unknown