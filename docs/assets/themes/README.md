# Theme preview assets

`pure.png` and `colorful.png` are browser captures of `docs/themes.html`, generated from the repository's real PowerShell renderer and bundled JSON themes. They are not AI-generated images. Sample identity is `user@host`; branch `dev`, failed exit code `7`, and elapsed time `2345ms` are fixture inputs. The screenshots use JetBrainsMono NFM (an installed Nerd Font) and a 1000px browser viewport.

Colorful backgrounds originate from the user-supplied `starship-colorful.toml` palette reference. Each theme records the palette identifier and foreground corrections under `_Comment`; no external TOML file is required to regenerate these assets. Pure preserves the project's original prompt styles.

## Regenerate

From the repository root, with Python 3 and PowerShell 7:

```powershell
python src/tests/render_theme_gallery.py
```

This uses a temporary runtime and local Git fixture; it does not write to the installed runtime. Open `docs/themes.html` in a browser with Powerline glyph support, set the viewport width to 1000px and keep the default state: Git, exit 7, 2.345 seconds. Capture the `#pure` and `#colorful` elements as `pure.png` and `colorful.png` here. Collapse the palette-adjustment disclosures before capture.

Example using an existing Playwright CLI session on that page:

```text
playwright-cli resize 1000 1000
playwright-cli screenshot '#pure' --filename docs/assets/themes/pure.png
playwright-cli screenshot '#colorful' --filename docs/assets/themes/colorful.png
```

Check glyph rendering, colors, text, and that both files contain their entire series. Both READMEs embed these same images. The HTML gallery contains eight states per theme and works offline; screenshots are the static GitHub-readable view.
