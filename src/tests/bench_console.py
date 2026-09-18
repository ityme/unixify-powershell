"""Measure empty Enter or Git candidate display through Windows ConPTY."""
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
parser.add_argument('--completion', action='store_true', help='Measure git pull origin <Tab> in an isolated repository')
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

def capture_buffer(keys, timeout=15):
    start = time.perf_counter()
    send(keys + bytes([7]))  # Ctrl+g captures state after the preceding key handler finishes.
    data = b''
    while time.perf_counter() - start < timeout:
        part = chunks.get(timeout=max(0.01, timeout - (time.perf_counter() - start)))
        data += part
        if b'\x1b[6n' in part:
            send(b'\x1b[1;1R')
        if b'UPWSH_CAPTURE_READY' in data:
            result = json.loads((bench_home / 'capture.json').read_text(encoding='utf-8'))
            result['ms'] = (time.perf_counter() - start) * 1000
            result['prompt_events'] = data.count(b'\x1b]133;A')
            result['candidates_visible'] = b'dev' in data and b'main' in data
            return result
    raise RuntimeError('Timed out capturing PSReadLine state')


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
    working_directory = os.getcwd()
    if options.completion:
        fixture = bench_home / 'repo'
        fixture.mkdir()
        working_directory = str(fixture)
        for key in list(env):
            if key.upper().startswith('GIT_'):
                del env[key]
        env['GIT_CONFIG_GLOBAL'] = os.devnull
        env['GIT_CONFIG_NOSYSTEM'] = '1'
        for args in [
            ['init', '--initial-branch=main'],
            ['-c', 'user.name=Fixture', '-c', 'user.email=fixture@example.invalid', '-c', 'commit.gpgsign=false', 'commit', '--allow-empty', '-m', 'fixture'],
            ['remote', 'add', 'origin', 'https://example.invalid/repo.git'],
            ['update-ref', 'refs/remotes/origin/dev', 'HEAD'],
            ['update-ref', 'refs/remotes/origin/main', 'HEAD'],
        ]:
            subprocess.run(['git', '-C', str(fixture), *args], env=env, check=True, capture_output=True)
    env_block = c.create_unicode_buffer('\0'.join(f'{key}={value}' for key, value in sorted(env.items())) + '\0\0')
    script = ". '" + str(runtime).replace("'", "''") + "'"
    if options.completion:
        script += r""";
$global:UpwshBenchRenders = 0
$module = (Get-Command prompt).Module
$global:UpwshBenchBase = & $module { $script:BasePrompt }
& $module { $script:BasePrompt = { $global:UpwshBenchRenders++; & $global:UpwshBenchBase } }
Set-PSReadLineKeyHandler -Chord Ctrl+g -ScriptBlock {
    $line = $null; $cursor = 0
    [Microsoft.PowerShell.PSConsoleReadLine]::GetBufferState([ref]$line, [ref]$cursor)
    $state = [pscustomobject]@{ Line = $line; Cursor = $cursor; Renders = $global:UpwshBenchRenders }
    [IO.File]::WriteAllText((Join-Path $HOME 'capture.json'), ($state | ConvertTo-Json -Compress))
    [Console]::Write('UPWSH_CAPTURE_READY')
}
"""
    command = c.create_unicode_buffer(subprocess.list2cmdline([shutil.which('pwsh'), '-NoLogo', '-NoProfile', '-NoExit', '-Command', script]))
    start = time.perf_counter()
    check(k.CreateProcessW(None, command, None, None, False, 0x00080000 | 0x00000400, env_block, working_directory, c.byref(startup), c.byref(process)))
    threading.Thread(target=read_loop, daemon=True).start()
    await_prompt()
    startup_ms = (time.perf_counter() - start) * 1000
    if options.completion:
        typed = capture_buffer(b'git pull origin ')
        rows = [capture_buffer(bytes([9])) for _ in range(options.samples + 5)]
        input_preserved = all(row['Line'] == 'git pull origin ' and row['Cursor'] == 16 for row in rows)
        redraw_reused = all(row['Renders'] == typed['Renders'] and row['prompt_events'] == 0 for row in rows)
        candidates_visible = any(row['candidates_visible'] for row in rows)
        correct = input_preserved and redraw_reused and candidates_visible
        samples = sorted(row['ms'] for row in rows[5:])
        p95 = samples[min(len(samples) - 1, int(len(samples) * .95))]
        print(json.dumps({'samples': len(samples), 'first_display_ms': round(rows[0]['ms'], 2),
                          'display_median_ms': round(statistics.median(samples), 2),
                          'display_p95_ms': round(p95, 2),
                          'extra_prompt_renders': rows[-1]['Renders'] - typed['Renders'],
                          'extra_prompt_events': sum(row['prompt_events'] for row in rows),
                          'input_preserved': input_preserved, 'candidates_visible': candidates_visible,
                          'executed_pull': False,
                          'budget_ms': options.budget_ms, 'passed': correct and p95 < options.budget_ms}))
        if not correct or (options.enforce and p95 >= options.budget_ms):
            sys.exit(1)
    else:
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
