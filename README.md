# micro-treebrowser

A file tree browser plugin for the [micro](https://micro-editor.github.io/) editor.

`treebrowser` opens a persistent tree pane and lets you browse files without
leaving the tree. Selecting a file previews it; explicitly opening a file moves
focus into the file so you can edit normally.

## Features

- Left-side file tree pane.
- Keyboard and mouse navigation.
- Preview mode that keeps focus in the tree.
- Explicit edit mode with `Enter` or double-click.
- Safe pane behavior:
  - Preview replaces the current target pane when it is unmodified.
  - Preview opens a new pane when the current target pane has unsaved changes.
  - `quit` from the tree closes file panes first and the tree last.
- Optional startup setting to open the tree automatically.

## Install

Clone the repository into micro's plugin directory:

```sh
git clone git@github.com:reignmaker/micro-treebrowser.git ~/.config/micro/plug/treebrowser
```

Restart micro, then verify the plugin is installed:

```sh
micro -plugin list
```

You should see `treebrowser (0.1.0)`.

## Commands

Run commands from micro's command prompt with `Ctrl-e`.

```text
tree
```

Toggle the tree pane.

```text
treebrowser [dir]
```

Open the tree at the current working directory, or at `dir` when provided.

## Settings

Open the tree automatically when micro starts:

```json
{
  "treebrowser.openonstart": true
}
```

Set it to `false` to disable startup behavior.

## Navigation

When the tree has focus:

- `Up` / `Down`: move through entries.
- Select a file: preview it in the target pane and keep focus in the tree.
- `Enter` on a file: open it and move focus into the file.
- Single-click a file: preview it.
- Double-click a file: open it and move focus into the file.
- `Left` / `Right`: collapse or expand directories.
- Single-click a directory: collapse or expand it.
- `Enter` or double-click a directory: make it the tree root.
- `../`: move the tree root to the parent directory.

The header shows a compact form of the current tree root, for example:

```text
..coder/work/project/
```

## Pane Behavior

Preview mode is designed for quick browsing:

- If the target pane is clean, selecting another file replaces that pane.
- If the target pane has unsaved changes, selecting another file opens a new
  vertical pane instead.
- Focus remains in the tree while previewing.

Opening a file with `Enter` or double-click moves focus into the file pane for
editing.

## License

No license has been specified yet.
