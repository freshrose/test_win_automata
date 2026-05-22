#!/usr/bin/env python3
"""
MCP Server for Delphi 13 VCL Windows Application Control.
Run: set DELPHI_MCP_API_KEY=secret && python delphi_vcl_mcp.py
Listens on http://0.0.0.0:8765/mcp
pip install "mcp[cli]" pywinauto pywin32 comtypes pillow
"""
import asyncio, base64, io, json, os
from concurrent.futures import ThreadPoolExecutor
from typing import Optional, List, Any
from pydantic import BaseModel, Field, ConfigDict
from mcp.server.fastmcp import FastMCP

API_KEY = os.environ.get("DELPHI_MCP_API_KEY", "")
try:
    from pywinauto import Application
    from pywinauto.findwindows import ElementNotFoundError
    HAS_PYWINAUTO = True
except ImportError:
    HAS_PYWINAUTO = False

mcp = FastMCP(
    "delphi_vcl_mcp",
    host=os.environ.get("DELPHI_MCP_HOST", "0.0.0.0"),
    port=int(os.environ.get("DELPHI_MCP_PORT", "8765")),
)
_executor = ThreadPoolExecutor(max_workers=1)
_app: Optional[Any] = None

def _require_pywinauto():
    if not HAS_PYWINAUTO:
        raise RuntimeError("Run: pip install pywinauto pywin32 comtypes")

def _require_app():
    _require_pywinauto()
    if _app is None:
        raise ValueError("No app connected. Call delphi_launch_app or delphi_connect_app first.")
    return _app

async def _run(fn, *args, **kwargs):
    loop = asyncio.get_event_loop()
    return await loop.run_in_executor(_executor, lambda: fn(*args, **kwargs))

def _resolve_window(app, window_title):
    return app.window(title_re=f".*{window_title}.*") if window_title else app.top_window()

def _resolve_control(window, ctrl_name, ctrl_type, auto_id, class_name, found_index):
    kwargs = {}
    if ctrl_name:   kwargs["title"]        = ctrl_name
    if ctrl_type:   kwargs["control_type"] = ctrl_type
    if auto_id:     kwargs["auto_id"]      = auto_id
    if class_name:  kwargs["class_name"]   = class_name
    if found_index: kwargs["found_index"]  = found_index
    if not kwargs:
        raise ValueError("Provide at least one of: ctrl_name, ctrl_type, auto_id, class_name.")
    return window.child_window(**kwargs)

def _build_tree(ctrl, depth, max_depth):
    if depth > max_depth:
        return ["  " * depth + "... (truncated)"]
    lines = []
    try:
        info  = ctrl.element_info
        parts = [f"[{getattr(info,'control_type','?')}]"]
        name  = (info.name or "").strip()
        if name: parts.append(f'name="{name}"')
        aid = (getattr(info,"automation_id",None) or "").strip()
        if aid:  parts.append(f'auto_id="{aid}"')
        cls = (info.class_name or "").strip()
        if cls:  parts.append(f'class="{cls}"')
        try:
            r = ctrl.rectangle()
            parts.append(f"rect=({r.left},{r.top},{r.right},{r.bottom})")
        except: pass
        try:
            if not ctrl.is_visible(): parts.append("[hidden]")
        except: pass
        lines.append("  " * depth + " ".join(parts))
        try:
            for child in ctrl.children():
                lines.extend(_build_tree(child, depth+1, max_depth))
        except: pass
    except Exception as exc:
        lines.append("  " * depth + f"[error: {exc}]")
    return lines

def _capture_screenshot(window):
    try:
        img = window.capture_as_image()
    except:
        from PIL import ImageGrab
        r = window.rectangle()
        img = ImageGrab.grab(bbox=(r.left, r.top, r.right, r.bottom))
    buf = io.BytesIO()
    img.save(buf, format="PNG")
    return buf.getvalue()

class _Base(BaseModel):
    model_config = ConfigDict(str_strip_whitespace=True, extra="forbid")

class LaunchAppInput(_Base):
    app_path: str           = Field(..., description=r"Full path to the .exe, e.g. C:\MyApp\MyApp.exe")
    work_dir: Optional[str] = Field(default=None, description="Working directory (optional).")
    backend:  str           = Field(default="uia", description="'uia' (recommended) or 'win32'.")

class ConnectAppInput(_Base):
    title_pattern: Optional[str] = Field(default=None, description="Regex matched against window title.")
    process_name:  Optional[str] = Field(default=None, description="Executable name, e.g. 'MyApp.exe'.")
    process_id:    Optional[int] = Field(default=None, description="Windows process ID (PID).")
    backend:       str           = Field(default="uia", description="'uia' or 'win32'.")

class WindowInput(_Base):
    window_title: Optional[str] = Field(default=None, description="Window title regex. Omit for top window.")

class TreeInput(_Base):
    window_title: Optional[str] = Field(default=None)
    max_depth:    int            = Field(default=5, ge=1, le=12)

class ControlInput(_Base):
    window_title: Optional[str] = Field(default=None)
    ctrl_name:    Optional[str] = Field(default=None, description="Control title/name.")
    ctrl_type:    Optional[str] = Field(default=None, description="UIA type: Button, Edit, ComboBox, ListBox, ListView, TreeView, CheckBox, RadioButton, TabItem…")
    auto_id:      Optional[str] = Field(default=None, description="UIA AutomationId.")
    class_name:   Optional[str] = Field(default=None, description="Win32 class: TEdit, TButton, TDBGrid…")
    found_index:  int            = Field(default=0, ge=0)

class TypeTextInput(ControlInput):
    text:        str  = Field(...)
    clear_first: bool = Field(default=True)

class SelectItemInput(ControlInput):
    item_text:  Optional[str] = Field(default=None)
    item_index: Optional[int] = Field(default=None, ge=0)

class MenuInput(_Base):
    window_title: Optional[str] = Field(default=None)
    menu_path:    str            = Field(..., description="E.g. 'File->Open' or 'Edit->Find->Replace'.")

class KeyInput(_Base):
    window_title: Optional[str] = Field(default=None)
    keys:         str            = Field(..., description="'^s' Ctrl+S, '%F4' Alt+F4, '{ENTER}', '{F5}', '+{F10}'.")

class CheckBoxInput(ControlInput):
    checked: Optional[bool] = Field(default=None, description="True=check, False=uncheck, None=toggle.")

class ScrollInput(ControlInput):
    direction: str = Field(default="down", description="up/down/left/right.")
    amount:    int = Field(default=3, ge=1, le=30)

@mcp.tool(name="delphi_launch_app", annotations={"title":"Launch App","readOnlyHint":False,"destructiveHint":False,"idempotentHint":False,"openWorldHint":False})
async def delphi_launch_app(params: LaunchAppInput) -> str:
    """Launch a Windows application from its .exe path and connect to it."""
    _require_pywinauto(); global _app
    def _do():
        global _app
        kwargs = {"backend": params.backend}
        if params.work_dir: kwargs["work_dir"] = params.work_dir
        _app = Application(**kwargs).start(params.app_path)
        _app.wait_cpu_usage_lower(threshold=15, timeout=30)
        win = _app.top_window()
        return {"success": True, "process_id": _app.process, "window_title": win.window_text(), "backend": params.backend}
    try:    return json.dumps(await _run(_do), indent=2)
    except Exception as exc: return json.dumps({"success": False, "error": str(exc)})

@mcp.tool(name="delphi_connect_app", annotations={"title":"Connect to Running App","readOnlyHint":False,"destructiveHint":False,"idempotentHint":True,"openWorldHint":False})
async def delphi_connect_app(params: ConnectAppInput) -> str:
    """Attach to an already-running application by title pattern, exe name, or PID."""
    _require_pywinauto(); global _app
    def _do():
        global _app
        app = Application(backend=params.backend)
        if params.process_id:      app.connect(process=params.process_id)
        elif params.process_name:  app.connect(path=params.process_name)
        elif params.title_pattern: app.connect(title_re=params.title_pattern)
        else: raise ValueError("Provide title_pattern, process_name, or process_id.")
        _app = app
        win = app.top_window()
        return {"success": True, "process_id": app.process, "window_title": win.window_text(), "backend": params.backend}
    try:    return json.dumps(await _run(_do), indent=2)
    except Exception as exc: return json.dumps({"success": False, "error": str(exc)})

@mcp.tool(name="delphi_list_windows", annotations={"title":"List Windows","readOnlyHint":True,"destructiveHint":False,"idempotentHint":True,"openWorldHint":False})
async def delphi_list_windows(params: WindowInput) -> str:
    """List all top-level windows of the connected application."""
    def _do():
        result = []
        for w in _require_app().windows():
            try:
                r = w.rectangle()
                result.append({"title": w.window_text(), "handle": w.handle, "class_name": w.class_name(), "visible": w.is_visible(), "enabled": w.is_enabled(), "rect": {"left":r.left,"top":r.top,"right":r.right,"bottom":r.bottom}})
            except Exception as exc: result.append({"error": str(exc)})
        return result
    try:    return json.dumps(await _run(_do), indent=2)
    except Exception as exc: return json.dumps({"error": str(exc)})

@mcp.tool(name="delphi_get_window_tree", annotations={"title":"Inspect UI Control Tree","readOnlyHint":True,"destructiveHint":False,"idempotentHint":True,"openWorldHint":False})
async def delphi_get_window_tree(params: TreeInput) -> str:
    """Dump accessibility control hierarchy. Use first to discover control names, auto_ids and class names."""
    def _do():
        app = _require_app()
        win = _resolve_window(app, params.window_title)
        win.set_focus()
        return f"Window: \"{win.window_text()}\"\n" + "\n".join(_build_tree(win.wrapper_object(), 0, params.max_depth))
    try:    return await _run(_do)
    except Exception as exc: return f"Error: {exc}"

@mcp.tool(name="delphi_screenshot", annotations={"title":"Screenshot","readOnlyHint":True,"destructiveHint":False,"idempotentHint":True,"openWorldHint":False})
async def delphi_screenshot(params: WindowInput) -> str:
    """Capture the application window as a base64-encoded PNG."""
    def _do():
        win = _resolve_window(_require_app(), params.window_title)
        return base64.b64encode(_capture_screenshot(win)).decode()
    try:    return json.dumps({"success":True,"format":"png","data_base64": await _run(_do)})
    except Exception as exc: return json.dumps({"success":False,"error":str(exc)})

@mcp.tool(name="delphi_click", annotations={"title":"Click Control","readOnlyHint":False,"destructiveHint":False,"idempotentHint":False,"openWorldHint":False})
async def delphi_click(params: ControlInput) -> str:
    """Single-click a control by name, type, auto_id, or class_name."""
    def _do():
        win = _resolve_window(_require_app(), params.window_title)
        _resolve_control(win, params.ctrl_name, params.ctrl_type, params.auto_id, params.class_name, params.found_index).click_input()
        return {"success":True,"action":"click","control": params.ctrl_name or params.auto_id or params.class_name}
    try:    return json.dumps(await _run(_do), indent=2)
    except Exception as exc: return json.dumps({"success":False,"error":str(exc)})

@mcp.tool(name="delphi_double_click", annotations={"title":"Double-Click Control","readOnlyHint":False,"destructiveHint":False,"idempotentHint":False,"openWorldHint":False})
async def delphi_double_click(params: ControlInput) -> str:
    """Double-click a control (open row, enter edit mode, expand tree node)."""
    def _do():
        win = _resolve_window(_require_app(), params.window_title)
        _resolve_control(win, params.ctrl_name, params.ctrl_type, params.auto_id, params.class_name, params.found_index).double_click_input()
        return {"success":True,"action":"double_click"}
    try:    return json.dumps(await _run(_do), indent=2)
    except Exception as exc: return json.dumps({"success":False,"error":str(exc)})

@mcp.tool(name="delphi_right_click", annotations={"title":"Right-Click Control","readOnlyHint":False,"destructiveHint":False,"idempotentHint":False,"openWorldHint":False})
async def delphi_right_click(params: ControlInput) -> str:
    """Right-click a control to open its context menu. Follow with delphi_click to select a menu item."""
    def _do():
        win = _resolve_window(_require_app(), params.window_title)
        _resolve_control(win, params.ctrl_name, params.ctrl_type, params.auto_id, params.class_name, params.found_index).right_click_input()
        return {"success":True,"action":"right_click"}
    try:    return json.dumps(await _run(_do), indent=2)
    except Exception as exc: return json.dumps({"success":False,"error":str(exc)})

@mcp.tool(name="delphi_get_text", annotations={"title":"Get Control Text","readOnlyHint":True,"destructiveHint":False,"idempotentHint":True,"openWorldHint":False})
async def delphi_get_text(params: ControlInput) -> str:
    """Read the text value of an Edit, Label, StatusBar, or similar control."""
    def _do():
        win  = _resolve_window(_require_app(), params.window_title)
        ctrl = _resolve_control(win, params.ctrl_name, params.ctrl_type, params.auto_id, params.class_name, params.found_index)
        try:    text = ctrl.get_value()
        except AttributeError:
            try: text = ctrl.window_text()
            except: text = " | ".join(ctrl.texts())
        return {"success":True,"text":text}
    try:    return json.dumps(await _run(_do), indent=2)
    except Exception as exc: return json.dumps({"success":False,"error":str(exc)})

@mcp.tool(name="delphi_set_text", annotations={"title":"Set Text","readOnlyHint":False,"destructiveHint":False,"idempotentHint":True,"openWorldHint":False})
async def delphi_set_text(params: TypeTextInput) -> str:
    """Replace content of a TEdit/TMemo via UIA Value pattern. Use delphi_type_text for masked fields."""
    def _do():
        win  = _resolve_window(_require_app(), params.window_title)
        ctrl = _resolve_control(win, params.ctrl_name, params.ctrl_type, params.auto_id, params.class_name, params.found_index)
        ctrl.set_focus()
        if params.clear_first: ctrl.set_edit_text(params.text)
        else:                  ctrl.type_keys(params.text, with_spaces=True)
        return {"success":True,"action":"set_text","text":params.text}
    try:    return json.dumps(await _run(_do), indent=2)
    except Exception as exc: return json.dumps({"success":False,"error":str(exc)})

@mcp.tool(name="delphi_type_text", annotations={"title":"Type Text (keystroke simulation)","readOnlyHint":False,"destructiveHint":False,"idempotentHint":False,"openWorldHint":False})
async def delphi_type_text(params: TypeTextInput) -> str:
    """Simulate keyboard input character-by-character. Better for masked fields or validators."""
    def _do():
        win  = _resolve_window(_require_app(), params.window_title)
        ctrl = _resolve_control(win, params.ctrl_name, params.ctrl_type, params.auto_id, params.class_name, params.found_index)
        ctrl.click_input()
        if params.clear_first: ctrl.type_keys("^a{DELETE}")
        ctrl.type_keys(params.text, with_spaces=True)
        return {"success":True,"action":"type_text","text":params.text}
    try:    return json.dumps(await _run(_do), indent=2)
    except Exception as exc: return json.dumps({"success":False,"error":str(exc)})

@mcp.tool(name="delphi_press_key", annotations={"title":"Press Keys","readOnlyHint":False,"destructiveHint":False,"idempotentHint":False,"openWorldHint":False})
async def delphi_press_key(params: KeyInput) -> str:
    """Send keyboard shortcut. '^s' Ctrl+S, '%F4' Alt+F4, '{ENTER}', '{F5}', '+{F9}'.
    Forces the target window to foreground, then synthesizes real hardware-level
    keypresses via keybd_event so modifier+function key combos (Shift+F9, Ctrl+F9,
    etc.) reach the app's global accelerator table."""
    import time, re
    import win32api, win32con, win32gui
    MOD = {"+": win32con.VK_SHIFT, "^": win32con.VK_CONTROL, "%": win32con.VK_MENU}
    NAMED = {
        "ENTER": win32con.VK_RETURN, "RETURN": win32con.VK_RETURN,
        "TAB": win32con.VK_TAB, "ESC": win32con.VK_ESCAPE, "ESCAPE": win32con.VK_ESCAPE,
        "SPACE": win32con.VK_SPACE, "BACKSPACE": win32con.VK_BACK, "BS": win32con.VK_BACK,
        "DEL": win32con.VK_DELETE, "DELETE": win32con.VK_DELETE, "INS": win32con.VK_INSERT,
        "HOME": win32con.VK_HOME, "END": win32con.VK_END,
        "PGUP": win32con.VK_PRIOR, "PGDN": win32con.VK_NEXT,
        "UP": win32con.VK_UP, "DOWN": win32con.VK_DOWN, "LEFT": win32con.VK_LEFT, "RIGHT": win32con.VK_RIGHT,
        **{f"F{n}": getattr(win32con, f"VK_F{n}") for n in range(1, 25)},
    }

    def _force_foreground(hwnd: int) -> None:
        try:
            if win32gui.IsIconic(hwnd):
                win32gui.ShowWindow(hwnd, win32con.SW_RESTORE)
            # AttachThreadInput trick to bypass SetForegroundWindow restrictions
            import ctypes
            user32 = ctypes.windll.user32
            fg = user32.GetForegroundWindow()
            target_tid = user32.GetWindowThreadProcessId(hwnd, 0)
            curr_tid = ctypes.windll.kernel32.GetCurrentThreadId()
            if fg != hwnd:
                user32.AttachThreadInput(curr_tid, target_tid, True)
                try:
                    win32gui.SetForegroundWindow(hwnd)
                    win32gui.BringWindowToTop(hwnd)
                finally:
                    user32.AttachThreadInput(curr_tid, target_tid, False)
        except Exception:
            pass

    def _parse(keys: str):
        """Parse pywinauto-style key string into a list of (modifiers_tuple, vk, char_or_none).
        Handles: '+{F9}', '^s', '%{F4}', '{ENTER}', '+^{F11}', plain 'abc'."""
        events = []
        i = 0
        pending_mods: list = []
        while i < len(keys):
            c = keys[i]
            if c in MOD and i + 1 < len(keys):
                pending_mods.append(MOD[c])
                i += 1
                continue
            if c == "{":
                end = keys.find("}", i)
                if end < 0:
                    raise ValueError(f"Unterminated brace in: {keys}")
                name = keys[i+1:end].strip().upper()
                if name in NAMED:
                    events.append((tuple(pending_mods), NAMED[name], None))
                elif len(name) == 1:
                    events.append((tuple(pending_mods), ord(name.upper()), name))
                else:
                    raise ValueError(f"Unknown key token: {{{name}}}")
                pending_mods = []
                i = end + 1
                continue
            # plain character
            vk = win32api.VkKeyScan(c) & 0xFF
            # If char requires shift (uppercase letters, symbols), include VK_SHIFT
            needs_shift = (win32api.VkKeyScan(c) >> 8) & 1
            mods = list(pending_mods)
            if needs_shift and win32con.VK_SHIFT not in mods:
                mods.append(win32con.VK_SHIFT)
            events.append((tuple(mods), vk, c))
            pending_mods = []
            i += 1
        return events

    # ---- SendInput wrapper (modern API, more reliable than keybd_event) ----
    import ctypes
    from ctypes import wintypes
    PUL = ctypes.POINTER(ctypes.c_ulong)
    class _KBDINPUT(ctypes.Structure):
        _fields_ = [("wVk", wintypes.WORD), ("wScan", wintypes.WORD),
                    ("dwFlags", wintypes.DWORD), ("time", wintypes.DWORD),
                    ("dwExtraInfo", PUL)]
    class _MOUSEINPUT(ctypes.Structure):
        _fields_ = [("dx", wintypes.LONG), ("dy", wintypes.LONG),
                    ("mouseData", wintypes.DWORD), ("dwFlags", wintypes.DWORD),
                    ("time", wintypes.DWORD), ("dwExtraInfo", PUL)]
    class _HARDWAREINPUT(ctypes.Structure):
        _fields_ = [("uMsg", wintypes.DWORD), ("wParamL", wintypes.WORD), ("wParamH", wintypes.WORD)]
    class _INPUTunion(ctypes.Union):
        _fields_ = [("ki", _KBDINPUT), ("mi", _MOUSEINPUT), ("hi", _HARDWAREINPUT)]
    class _INPUT(ctypes.Structure):
        _fields_ = [("type", wintypes.DWORD), ("u", _INPUTunion)]
    INPUT_KEYBOARD = 1
    KEYEVENTF_KEYUP = 0x0002
    KEYEVENTF_SCANCODE = 0x0008
    KEYEVENTF_EXTENDEDKEY = 0x0001
    EXTENDED = {win32con.VK_UP, win32con.VK_DOWN, win32con.VK_LEFT, win32con.VK_RIGHT,
                win32con.VK_HOME, win32con.VK_END, win32con.VK_PRIOR, win32con.VK_NEXT,
                win32con.VK_INSERT, win32con.VK_DELETE, win32con.VK_NUMLOCK}

    def _make_kbd(vk: int, up: bool) -> _INPUT:
        scan = win32api.MapVirtualKey(vk, 0)  # MAPVK_VK_TO_VSC
        flags = KEYEVENTF_SCANCODE
        if up: flags |= KEYEVENTF_KEYUP
        if vk in EXTENDED: flags |= KEYEVENTF_EXTENDEDKEY
        inp = _INPUT(type=INPUT_KEYBOARD)
        inp.u.ki = _KBDINPUT(wVk=0, wScan=scan, dwFlags=flags, time=0, dwExtraInfo=None)
        return inp

    def _send_one(mods, vk):
        seq = [_make_kbd(m, False) for m in mods]
        seq.append(_make_kbd(vk, False))
        seq.append(_make_kbd(vk, True))
        seq.extend(_make_kbd(m, True) for m in reversed(mods))
        arr = (_INPUT * len(seq))(*seq)
        n = ctypes.windll.user32.SendInput(len(seq), arr, ctypes.sizeof(_INPUT))
        return n

    def _is_elevated() -> bool:
        try:
            return bool(ctypes.windll.shell32.IsUserAnAdmin())
        except Exception:
            return False

    def _fg_hwnd_title() -> str:
        try:
            h = ctypes.windll.user32.GetForegroundWindow()
            buf = ctypes.create_unicode_buffer(256)
            ctypes.windll.user32.GetWindowTextW(h, buf, 256)
            return f"hwnd={h} title='{buf.value}'"
        except Exception as e:
            return f"err:{e}"

    def _do():
        win = _resolve_window(_require_app(), params.window_title)
        try:
            hwnd = win.handle
        except Exception:
            hwnd = None
        fg_before = _fg_hwnd_title()
        if hwnd:
            _force_foreground(hwnd)
        try:
            win.set_focus()
        except Exception:
            pass
        time.sleep(0.15)
        fg_after = _fg_hwnd_title()
        events = _parse(params.keys)
        total_injected = 0
        for mods, vk, _ in events:
            total_injected += _send_one(mods, vk)
            time.sleep(0.03)
        return {
            "success": True,
            "action": "key_press",
            "keys": params.keys,
            "events": len(events),
            "inputs_injected": total_injected,
            "target_hwnd": hwnd,
            "foreground_before": fg_before,
            "foreground_after": fg_after,
            "python_elevated": _is_elevated(),
        }
    try:    return json.dumps(await _run(_do), indent=2)
    except Exception as exc: return json.dumps({"success":False,"error":str(exc)})

@mcp.tool(name="delphi_select_menu", annotations={"title":"Select Menu Item","readOnlyHint":False,"destructiveHint":False,"idempotentHint":False,"openWorldHint":False})
async def delphi_select_menu(params: MenuInput) -> str:
    """Navigate menu by path: 'File->Open' or 'Edit->Find->Replace'."""
    def _do():
        win = _resolve_window(_require_app(), params.window_title)
        win.menu_select(params.menu_path)
        return {"success":True,"action":"menu_select","path":params.menu_path}
    try:    return json.dumps(await _run(_do), indent=2)
    except Exception as exc: return json.dumps({"success":False,"error":str(exc)})

@mcp.tool(name="delphi_get_items", annotations={"title":"Get List/Combo Items","readOnlyHint":True,"destructiveHint":False,"idempotentHint":True,"openWorldHint":False})
async def delphi_get_items(params: ControlInput) -> str:
    """Get all items from TListBox, TComboBox, or TListView."""
    def _do():
        win  = _resolve_window(_require_app(), params.window_title)
        ctrl = _resolve_control(win, params.ctrl_name, params.ctrl_type, params.auto_id, params.class_name, params.found_index)
        try:    items = ctrl.item_texts()
        except: items = ctrl.texts()
        items = [t for t in items if t.strip()]
        return {"success":True,"count":len(items),"items":items}
    try:    return json.dumps(await _run(_do), indent=2)
    except Exception as exc: return json.dumps({"success":False,"error":str(exc)})

@mcp.tool(name="delphi_select_item", annotations={"title":"Select List/Combo Item","readOnlyHint":False,"destructiveHint":False,"idempotentHint":True,"openWorldHint":False})
async def delphi_select_item(params: SelectItemInput) -> str:
    """Select entry in TListBox, TComboBox, or TListView by text or index."""
    def _do():
        win  = _resolve_window(_require_app(), params.window_title)
        ctrl = _resolve_control(win, params.ctrl_name, params.ctrl_type, params.auto_id, params.class_name, params.found_index)
        if params.item_text is not None:   ctrl.select(params.item_text);  selected = params.item_text
        elif params.item_index is not None: ctrl.select(params.item_index); selected = str(params.item_index)
        else: raise ValueError("Provide item_text or item_index.")
        return {"success":True,"selected":selected}
    try:    return json.dumps(await _run(_do), indent=2)
    except Exception as exc: return json.dumps({"success":False,"error":str(exc)})

@mcp.tool(name="delphi_check_box", annotations={"title":"Check/Uncheck Checkbox","readOnlyHint":False,"destructiveHint":False,"idempotentHint":True,"openWorldHint":False})
async def delphi_check_box(params: CheckBoxInput) -> str:
    """Set TCheckBox or TRadioButton state. checked=true/false/null(toggle)."""
    def _do():
        win  = _resolve_window(_require_app(), params.window_title)
        ctrl = _resolve_control(win, params.ctrl_name, params.ctrl_type, params.auto_id, params.class_name, params.found_index)
        cur  = bool(ctrl.get_check_state())
        if params.checked is None:           ctrl.toggle();   new = not cur
        elif params.checked and not cur:      ctrl.check();    new = True
        elif not params.checked and cur:      ctrl.uncheck();  new = False
        else:                                                  new = cur
        return {"success":True,"checked":new}
    try:    return json.dumps(await _run(_do), indent=2)
    except Exception as exc: return json.dumps({"success":False,"error":str(exc)})

@mcp.tool(name="delphi_get_control_state", annotations={"title":"Get Control State","readOnlyHint":True,"destructiveHint":False,"idempotentHint":True,"openWorldHint":False})
async def delphi_get_control_state(params: ControlInput) -> str:
    """Read full state: enabled, visible, text, value, rect, type."""
    def _do():
        win  = _resolve_window(_require_app(), params.window_title)
        ctrl = _resolve_control(win, params.ctrl_name, params.ctrl_type, params.auto_id, params.class_name, params.found_index)
        s = {"enabled":ctrl.is_enabled(),"visible":ctrl.is_visible(),"class_name":ctrl.class_name(),"window_text":ctrl.window_text()}
        try:    s["control_type"] = str(ctrl.element_info.control_type)
        except: pass
        try:
            r = ctrl.rectangle()
            s["rect"] = {"left":r.left,"top":r.top,"right":r.right,"bottom":r.bottom}
        except: pass
        try:    s["value"]   = ctrl.get_value()
        except: pass
        try:    s["checked"] = bool(ctrl.get_check_state())
        except: pass
        return s
    try:    return json.dumps(await _run(_do), indent=2)
    except Exception as exc: return json.dumps({"success":False,"error":str(exc)})

@mcp.tool(name="delphi_scroll", annotations={"title":"Scroll Control","readOnlyHint":False,"destructiveHint":False,"idempotentHint":False,"openWorldHint":False})
async def delphi_scroll(params: ScrollInput) -> str:
    """Scroll TGrid, TMemo, TListBox. Direction: up/down/left/right."""
    def _do():
        if params.direction not in {"up","down","left","right"}:
            raise ValueError(f"Invalid direction: {params.direction}")
        win  = _resolve_window(_require_app(), params.window_title)
        ctrl = _resolve_control(win, params.ctrl_name, params.ctrl_type, params.auto_id, params.class_name, params.found_index)
        ctrl.scroll(params.direction, params.amount)
        return {"success":True,"direction":params.direction,"amount":params.amount}
    try:    return json.dumps(await _run(_do), indent=2)
    except Exception as exc: return json.dumps({"success":False,"error":str(exc)})

@mcp.tool(name="delphi_close_app", annotations={"title":"Close App","readOnlyHint":False,"destructiveHint":True,"idempotentHint":False,"openWorldHint":False})
async def delphi_close_app(params: WindowInput) -> str:
    """Send WM_CLOSE to the window. App may show unsaved-changes dialog."""
    def _do():
        _resolve_window(_require_app(), params.window_title).close()
        return {"success":True,"action":"close"}
    try:    return json.dumps(await _run(_do), indent=2)
    except Exception as exc: return json.dumps({"success":False,"error":str(exc)})

if __name__ == "__main__":
    import uvicorn as _uv
    host = os.environ.get("DELPHI_MCP_HOST", "0.0.0.0")
    port = int(os.environ.get("DELPHI_MCP_PORT", "8765"))
    cert = os.environ.get("DELPHI_MCP_CERT", "cert.pem")
    key  = os.environ.get("DELPHI_MCP_KEY",  "key.pem")
    ssl_kwargs: dict = {"ssl_certfile": cert, "ssl_keyfile": key} if (os.path.exists(cert) and os.path.exists(key)) else {}
    proto = "https" if ssl_kwargs else "http"
    print(f"Delphi VCL MCP server starting on {proto}://{host}:{port}/mcp", flush=True)
    print("API key: " + ("ENABLED" if API_KEY else "WARNING: not set — set DELPHI_MCP_API_KEY"), flush=True)
    print("TLS: " + ("ENABLED" if ssl_kwargs else "disabled"), flush=True)
    # Monkey-patch uvicorn.run to inject host, port and SSL regardless of
    # what FastMCP passes internally (mcp 1.x ignores FASTMCP_HOST/PORT env vars).
    _orig = _uv.run
    def _patched(app, **kwargs):
        kwargs["host"] = host
        kwargs["port"] = port
        kwargs.update(ssl_kwargs)
        return _orig(app, **kwargs)
    _uv.run = _patched
    mcp.run(transport="streamable-http")
