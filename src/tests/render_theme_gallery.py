"""Generate docs/themes.html from real prompt output; requires Python 3 and pwsh."""
import html
import json
import os
from pathlib import Path
import re
import shutil
import subprocess
import tempfile

ROOT = Path(__file__).resolve().parents[2]
CATALOG = {
    'pure-default': 'Original green / yellow / cyan, italic folder.',
    'pure-glacier': 'Ice-blue folder and lavender branch.',
    'pure-ember': 'Amber folder and warm-white branch.',
    'pure-quiet': 'No user/host or duration; > on success, ! on failure.',
    'pure-daylight': 'Deep blue and purple for light terminal backgrounds.',
    'colorful-blue': 'Deep teal → lake green → bright teal → ice teal.',
    'colorful-green': 'Sage → matcha → spring green → pale mint.',
    'colorful-macaron': 'Lilac → sky blue → lake green → soft green.',
    'colorful-morandi': 'Sage grey → dusty pink → oat → linen.',
    'colorful-cyberpunk': 'Neon purple → electric blue → aqua → ice blue.',
    'colorful-retro': 'Forest green → ochre → warm tan → ivory.',
    'colorful-memphis': 'Pink → lemon yellow → cyan → pale blue.',
}


def literal(value):
    return "'" + str(value).replace("'", "''") + "'"


def ansi_html(text):
    output, last, opened = [], 0, False
    for match in re.finditer(r'\x1b\[([0-9;]+)m', text):
        output.append(html.escape(text[last:match.start()]))
        if opened:
            output.append('</span>')
        opened = False
        codes = list(map(int, match[1].split(';')))
        fg, bg, bold, italic = 'inherit', 'transparent', False, False
        i = 0
        while i < len(codes):
            code = codes[i]
            if code == 1:
                bold = True
            elif code == 3:
                italic = True
            elif code in (38, 48) and i + 4 < len(codes) and codes[i + 1] == 2:
                value = 'rgb(' + ','.join(map(str, codes[i + 2:i + 5])) + ')'
                if code == 38:
                    fg = value
                else:
                    bg = value
                i += 4
            i += 1
        if len(codes) > 1:
            output.append(f'<span style="color:{fg};background:{bg};font-weight:{700 if bold else 400};font-style:{"italic" if italic else "normal"}">')
            opened = True
        last = match.end()
    output.append(html.escape(text[last:]))
    if opened:
        output.append('</span>')
    return ''.join(output)


def render():
    with tempfile.TemporaryDirectory(prefix='upwsh-gallery-') as temp:
        work = Path(temp)
        runtime = work / 'runtime'
        (runtime / 'themes').mkdir(parents=True)
        for file in ['path.psm1', 'path_convert.ps1', 'theme.psm1', 'prompt.psm1']:
            shutil.copy2(ROOT / 'src' / file, runtime / file)
        for name in CATALOG:
            shutil.copy2(ROOT / 'src/themes' / (name + '.json'), runtime / 'themes')
        (work / 'project/.git').mkdir(parents=True)
        (work / 'project/.git/HEAD').write_text('ref: refs/heads/dev', encoding='utf-8')
        (work / 'outside').mkdir()
        ps = f"""$ErrorActionPreference='Stop'
Import-Module {literal(runtime / 'path.psm1')} -DisableNameChecking
Import-Module {literal(runtime / 'theme.psm1')}
Import-Module {literal(runtime / 'prompt.psm1')}
$env:USERNAME='user'
$hostName=[Environment]::MachineName.ToLowerInvariant().Split('.')[0]
$results=@(foreach($name in @({','.join(literal(n) for n in CATALOG)})) {{
    $null=Set-UpwshTheme $name
    foreach($repo in @($true,$false)) {{
        Set-Location $(if($repo){{{literal(work / 'project')}}}else{{{literal(work / 'outside')}}})
        foreach($success in @($true,$false)) {{
            foreach($ms in @(0,2345)) {{
                $text=Get-UpwshPromptText -Succeeded $success -ExitCode 7 -DurationMs $ms -Color Always
                [pscustomobject]@{{Name=$name;Repo=$repo;Success=$success;Ms=$ms;Text=$text.Replace($hostName,'host')}}
            }}
        }}
    }}
}})
ConvertTo-Json -InputObject $results -Compress
"""
        env = {k: v for k, v in os.environ.items() if not k.upper().startswith('GIT_')}
        env['GIT_CEILING_DIRECTORIES'] = str(work)
        result = subprocess.run(['pwsh', '-NoLogo', '-NoProfile', '-Command', ps], env=env, cwd=work,
                                encoding='utf-8', capture_output=True, timeout=60, check=True)
        return json.loads(result.stdout)


def main():
    themes = {name: json.loads((ROOT / 'src/themes' / (name + '.json')).read_text(encoding='utf-8')) for name in CATALOG}
    assert set(themes) == {p.stem for p in (ROOT / 'src/themes').glob('*.json')}, 'Update CATALOG for new themes'
    renders = render()
    assert len(renders) == len(CATALOG) * 8
    for row in renders:
        plain = re.sub(r'\x1b\[[0-9;]*m', '', row['Text'])
        assert ('dev' in plain) == row['Repo']
        assert ('2s345ms' in plain) == (row['Ms'] == 2345 and row['Name'] != 'pure-quiet')
        assert ('7' in plain) != row['Success']
        assert plain.startswith('\n') == themes[row['Name']]['AddNewline']
        if row['Name'].startswith('colorful-'):
            tail = ('2s345ms' if row['Ms'] else '') + ('' if row['Success'] else '7') + '❯ '
            assert plain.endswith(' ' + tail)
    states = [(repo, success, ms) for repo in [True, False] for success in [True, False] for ms in [0, 2345]]
    options = ''.join(f'<option value="{i}" {"selected" if i == 3 else ""}>{"Git" if repo else "No Git"} · {"success" if success else "exit 7"} · {"2.345 s" if ms else "short command"}</option>' for i, (repo, success, ms) in enumerate(states))
    groups = []
    for series in ['pure', 'colorful']:
        entries = []
        for name, description in CATALOG.items():
            if not name.startswith(series + '-'):
                continue
            samples = [row for row in renders if row['Name'] == name]
            examples = ''.join(f'<pre data-state="{i}" tabindex="0" aria-label="{name} prompt" {"hidden" if i != 3 else ""}>{ansi_html(row["Text"]).replace(chr(10), '<span></span>' + chr(10))}</pre>' for i, row in enumerate(samples))
            comment = themes[name]['_Comment']
            notes = ''
            if series == 'colorful':
                notes = '<details><summary>Palette adjustments / 配色调整</summary><ul>' + ''.join('<li>' + html.escape(s) + '</li>' for s in comment['ContrastAdjustments']) + '</ul></details>'
            entries.append(f'<article><h3><a href="../src/themes/{name}.json">{name}</a></h3><p>{html.escape(description)}</p><div class="sample {"light" if name == "pure-daylight" else ""}">{examples}</div>{notes}</article>')
        introduction = 'Transparent backgrounds, colored text. No added blank line. Default: pure-default.' if series == 'pure' else 'Connected color blocks with one blank line before each prompt. Duration, exit code and symbol join without extra spaces.'
        groups.append(f'<section id="{series}"><h2>{series}-*</h2><p>{introduction}</p>' + ''.join(entries) + '</section>')
    page = '''<!doctype html>
<html lang="en"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1"><link rel="icon" href="data:,"><title>upwsh theme gallery</title><style>
:root{color-scheme:light;--paper:#f8fafc;--ink:#172033;--muted:#475569;--line:#cbd5e1;--link:#1d4ed8}*{box-sizing:border-box}body{margin:0;background:var(--paper);color:var(--ink);font:16px/1.6 system-ui,sans-serif}main{max-width:1000px;margin:auto;padding:32px 24px}h1{font-size:30px;line-height:1.3;margin:0 0 16px}h2{font-size:26px;margin:0}h3{font:600 16px/1.6 system-ui,sans-serif;margin:0}p{margin:4px 0 12px;color:var(--muted);max-width:76ch}.controls{display:flex;gap:16px;align-items:center;flex-wrap:wrap;margin:24px 0}select{font:inherit;min-height:44px;padding:6px 12px;max-width:100%;color:var(--ink);background:white;border:1px solid #64748b}section{padding:24px;margin:24px 0;background:var(--paper);border:1px solid var(--line)}article{padding:18px 0;border-top:1px solid var(--line);min-width:0}article:last-child{padding-bottom:0}pre{margin:0;padding:18px 16px;overflow-x:auto;white-space:pre;font:18px/1.6 "JetBrainsMono NFM","UbuntuMono Nerd Font Mono",Consolas,monospace;scrollbar-color:#64748b #1a1b26}.sample{color:#dce3eb;background:#1a1b26}.sample.light{color:#172033;background:#ffffff}a{color:var(--link);text-underline-offset:4px}a:hover{text-decoration-thickness:2px}summary{padding:8px 0;cursor:pointer;color:var(--muted);font-size:14px}details ul{font-size:14px;margin:0;padding-left:24px}a:focus-visible,select:focus-visible,pre:focus-visible,summary:focus-visible{outline:3px solid var(--link);outline-offset:4px}::selection{background:#bfdbfe;color:#172033}code{font-family:Consolas,monospace;overflow-wrap:anywhere}@media(max-width:680px){main{padding:24px 12px}section{padding:16px}h1{font-size:26px}pre{font-size:16px;padding:16px 12px}}
</style></head><body><main><h1>upwsh theme gallery</h1><p><a href="../README.md#themes">README</a> · <a href="../README.zh-CN.md#主题">中文介绍</a> · <a href="themes.zh-CN.md">配置说明</a></p><p>Real renderer output with sample username/hostname, local fixture branch and simulated command results. All themes show only the current folder. This page works offline; it does not change your shell.</p><p>Colorful uses the approved Starship palette reference with readability corrections. Backgrounds remain terminal settings; screenshots use #1a1b26, except pure-daylight. Powerline icons require a compatible font such as JetBrainsMono Nerd Font.</p><div class="controls"><label for="state">Prompt state / 显示状态</label><select id="state">OPTIONS</select></div>GROUPS<p>Generated by <code>python src/tests/render_theme_gallery.py</code>. Edit theme JSON, regenerate, then refresh the README screenshots; see <a href="assets/themes/README.md">capture instructions</a>.</p></main><script>document.querySelector('#state').addEventListener('change',event=>{document.querySelectorAll('pre[data-state]').forEach(pre=>{pre.hidden=pre.dataset.state!==event.target.value;});});</script></body></html>'''.replace('OPTIONS', options).replace('GROUPS', ''.join(groups))
    (ROOT / 'docs/themes.html').write_text(page, encoding='utf-8')
    print(f'Generated docs/themes.html: {len(themes)} themes, {len(renders)} validated states.')


if __name__ == '__main__':
    main()
