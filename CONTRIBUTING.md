# Working on OmaRandom

## Layout

| Path | What it is |
| --- | --- |
| `manifest.json` | Omarchy plugin manifest (bar widget + panel) |
| `qml/BarWidget.qml` | Bar icon; opens and closes the window |
| `qml/Panel.qml` | The window: Wheels and Results tabs, spin view, saving |
| `qml/Wheel.qml` | One wheel: slices, labels, pictures, pointer, sway and spin |
| `qml/WheelEditor.qml` | Edit a wheel's name, colors, options and pictures |
| `qml/Logic.js` | Pure helpers: validation, colors, spin math, layout |
| `scripts/validate.sh` | Manifest, qmllint and safety checks |
| `docs/screenshots/` | README images |

## Developer copy

Copy the plugin into your plugins folder (a copy, never a symlink):

```bash
rsync -a --delete --exclude .git ./ ~/.config/omarchy/plugins/io.github.dankestrick.omarandom/
omarchy-shell shell rescanPlugins
omarchy plugin enable io.github.dankestrick.omarandom
```

Only do that for a folder you created this way. If the plugin came from
`omarchy plugin add`, remove it first with
`omarchy plugin remove io.github.dankestrick.omarandom`.

The shell keeps the window's QML loaded until it restarts, so run
`omarchy-restart-shell` after QML changes.

## Checks

```bash
./scripts/validate.sh
```

It runs `omarchy plugin validate`, `qmllint` against the shell's `qs.Ui` and
`qs.Commons`, checks that every `Text` sets `textFormat`, and fails if the QML
gains a process, socket or network URL.

## Driving it from a terminal

The shell's `call` command runs a function on the open window, which helps
when testing without a mouse:

```bash
id=io.github.dankestrick.omarandom
omarchy-shell shell summon $id '{}'
omarchy-shell shell call $id addWheel x
omarchy-shell shell call $id spinAll x
omarchy-shell shell call $id viewResults x
omarchy-shell shell hide $id
```

## Save file

`~/.local/share/omarandom/omarandom.json`:

```json
{
  "version": 1,
  "wheels": [
    { "id": "…", "name": "Dinner", "palette": "theme",
      "options": [ { "label": "Tacos", "color": "", "image": "file:///home/me/Pictures/tacos.jpg" } ] }
  ],
  "results": [
    { "id": "…", "batch": "…", "wheelId": "…", "wheel": "Dinner", "label": "Tacos",
      "color": "#e53935", "image": "", "time": 1790000000000 }
  ]
}
```

Results are newest first. Every field is checked on load (`Logic.parse`), and
a file that fails to parse is never overwritten.
