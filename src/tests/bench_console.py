"""Measure real empty Enter events through Windows ConPTY (no third-party packages)."""
import argparse
import ctypes as c
from ctypes import wintypes as w
import json
import os
from pathlib import Path
import queue
import shutil
import statistics
import subprocess
import sys
import tempfile
import threading
import time

if sys.platform != 'win32':
    raise SystemExit('ConPTY requires Windows')
k = c.WinDLL('kernel32', use_last_error=True)
class COORD(c.Structure):
    _fields_ = [('X', c.c_short), ('Y', c.c_short)]
class STARTUPINFO(c.Structure):
    _fields_ = [('cb', w.DWORD), ('lpReserved', w.LPWSTR), ('lpDesktop', w.LPWSTR), ('lpTitle', w.LPWSTR), ('dwX', w.DWORD), ('dwY', w.DWORD), ('dwXSize', w.DWORD), ('dwYSize', w.DWORD), ('dwXCountChars', w.DWORD), ('dwYCountChars', w.DWORD), ('dwFillAttribute', w.DWORD), ('dwFlags', w.DWORD), ('wShowWindow', w.WORD), ('cbReserved2', w.WORD), ('lpReserved2', c.POINTER(c.c_byte)), ('hStdInput', w.HANDLE), ('hStdOutput', w.HANDLE), ('hStdError', w.HANDLE)]
class STARTUPINFOEX(c.Structure):
    _fields_ = [('StartupInfo', STARTUPINFO), ('lpAttributeList', c.c_void_p)]
class PROCESSINFO(c.Structure):
    _fields_ = [('hProcess', w.HANDLE), ('hThread', w.HANDLE), ('dwProcessId', w.DWORD), ('dwThreadId', w.DWORD)]
k.CreatePipe.argtypes = [c.POINTER(w.HANDLE), c.POINTER(w.HANDLE), c.c_void_p, w.DWORD]
k.CreatePseudoConsole.argtypes = [COORD, w.HANDLE, w.HANDLE, w.DWORD, c.POINTER(w.HANDLE)]
k.CreatePseudoConsole.restype = c.c_long
k.InitializeProcThreadAttributeList.argtypes = [c.c_void_p, w.DWORD, w.DWORD, c.POINTER(c.c_size_t)]
k.UpdateProcThreadAttribute.argtypes = [c.c_void_p, w.DWORD, c.c_size_t, c.c_void_p, c.c_size_t, c.c_void_p, c.c_void_p]
k.CreateProcessW.argtypes = [w.LPCWSTR, w.LPWSTR, c.c_void_p, c.c_void_p, w.BOOL, w.DWORD, c.c_void_p, w.LPCWSTR, c.POINTER(STARTUPINFOEX), c.POINTER(PROCESSINFO)]
k.ReadFile.argtypes = [w.HANDLE, c.c_void_p, w.DWORD, c.POINTER(w.DWORD), c.c_void_p]
k.WriteFile.argtypes = k.ReadFile.argtypes
k.CloseHandle.argtypes = [w.HANDLE]
k.ClosePseudoConsole.argtypes = [w.HANDLE]
k.TerminateProcess.argtypes = [w.HANDLE, w.UINT]
k.DeleteProcThreadAttributeList.argtypes = [c.c_void_p]

def check(ok):
    if not ok:
        raise c.WinError(c.get_last_error())

parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument('profile', nargs='?', default='src/profile.ps1')
parser.add_argument('--samples', type=int, default=40)
parser.add_argument('--budget-ms', type=float, default=30)
parser.add_argument('--enforce', action='store_true')
options = parser.parse_args()
if options.samples < 1:
    parser.error('--samples must be positive')
runtime = Path(options.profile).resolve()
bench_home = Path(tempfile.mkdtemp(prefix='upwsh-console-'))
in_read, in_write, out_read, out_write, console = [w.HANDLE() for _ in range(5)]
process = PROCESSINFO()
attributes = None
chunks = queue.Queue()

def send(data):
    written = w.DWORD()
    check(k.WriteFile(in_write, data, len(data), c.byref(written), None))

def read_loop():
    buffer = c.create_string_buffer(65536)
    size = w.DWORD()
    while k.ReadFile(out_read, buffer, len(buffer), c.byref(size), None) and size.value:
        chunks.put(buffer.raw[:size.value])

def await_prompt(timeout=15):
    data = b''
    deadline = time.perf_counter() + timeout
    while time.perf_counter() < deadline:
        try:
            part = chunks.get(timeout=max(0.01, deadline - time.perf_counter()))
        except queue.Empty:
            break
        data += part
        if b'\x1b[6n' in part:
            send(b'\x1b[1;1R')
        if b'\x1b]133;B\x07' in data:
            return
    raise RuntimeError('Timed out waiting for prompt; terminal output withheld')

try:
    check(k.CreatePipe(c.byref(in_read), c.byref(in_write), None, 0))
    check(k.CreatePipe(c.byref(out_read), c.byref(out_write), None, 0))
    hr = k.CreatePseudoConsole(COORD(120, 30), in_read, out_write, 0, c.byref(console))
    if hr != 0:
        raise RuntimeError(f'CreatePseudoConsole HRESULT={hr}')
    k.CloseHandle(in_read); in_read = w.HANDLE()
    k.CloseHandle(out_write); out_write = w.HANDLE()
    size = c.c_size_t()
    k.InitializeProcThreadAttributeList(None, 1, 0, c.byref(size))
    attributes = c.create_string_buffer(size.value)
    check(k.InitializeProcThreadAttributeList(attributes, 1, 0, c.byref(size)))
    check(k.UpdateProcThreadAttribute(attributes, 0, 0x20016, console, c.sizeof(w.HANDLE), None, None))
    startup = STARTUPINFOEX()
    startup.StartupInfo.cb = c.sizeof(startup)
    startup.StartupInfo.dwFlags = 0x00000100
    startup.lpAttributeList = c.cast(attributes, c.c_void_p)
    env = dict(os.environ)
    config = Path(env.get('STARSHIP_CONFIG', str(Path.home() / '.config/starship.toml')))
    if config.exists():
        env['STARSHIP_CONFIG'] = str(config)
    env['USERPROFILE'] = str(bench_home)
    env['UPWSH_SKIP_PERSIST_PATH'] = '1'
    env['UPWSH_PROFILE'] = str(bench_home / 'profile.ps1')
    env_block = c.create_unicode_buffer('\0'.join(f'{key}={value}' for key, value in sorted(env.items())) + '\0\0')
    script = ". '" + str(runtime).replace("'", "''") + "'"
    command = c.create_unicode_buffer(subprocess.list2cmdline([shutil.which('pwsh'), '-NoLogo', '-NoProfile', '-NoExit', '-Command', script]))
    start = time.perf_counter()
    check(k.CreateProcessW(None, command, None, None, False, 0x00080000 | 0x00000400, env_block, os.getcwd(), c.byref(startup), c.byref(process)))
    threading.Thread(target=read_loop, daemon=True).start()
    await_prompt()
    startup_ms = (time.perf_counter() - start) * 1000
    times = []
    for _ in range(options.samples + 5):
        time.sleep(0.04)
        while not chunks.empty(): chunks.get_nowait()
        start = time.perf_counter()
        send(b'\r')
        await_prompt()
        times.append((time.perf_counter() - start) * 1000)
    samples = sorted(times[5:])
    p95 = samples[min(len(samples) - 1, int(len(samples) * .95))]
    print(json.dumps({'samples': len(samples), 'startup_to_prompt_ms': round(startup_ms, 2), 'empty_enter_median_ms': round(statistics.median(samples), 2), 'empty_enter_p95_ms': round(p95, 2), 'max_ms': round(max(samples), 2), 'budget_ms': options.budget_ms, 'passed': p95 < options.budget_ms}))
    if options.enforce and p95 >= options.budget_ms:
        sys.exit(1)
finally:
    if process.hProcess: k.TerminateProcess(process.hProcess, 0)
    if console: k.ClosePseudoConsole(console)
    if attributes: k.DeleteProcThreadAttributeList(attributes)
    for handle in [process.hThread, process.hProcess, in_read, in_write, out_read, out_write]:
        if handle: k.CloseHandle(handle)
    shutil.rmtree(bench_home, ignore_errors=True)
