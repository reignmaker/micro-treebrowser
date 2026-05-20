# treebrowser

`treebrowser` provides a file tree in a left split.

Commands:

* `tree` toggles the tree.
* `treebrowser [dir]` opens the tree at the current directory or at `dir`.

Settings:

* `treebrowser.openonstart`: open the tree automatically when micro starts.

Keys while the tree has focus:

* Up/Down select entries. Selecting a file previews it.
* `..` moves the tree root to the parent directory.
* Left/Right collapse and expand directories.
* Single-click on a directory collapses or expands it.
* Enter or double-click on a directory makes that directory the tree root.
* Enter opens the selected file and moves focus into it.
* Single-click selects and previews a file.
* Double-click opens the selected file and moves focus into it.

Preview mode keeps focus in the tree. If the current target pane is unmodified,
the selected file replaces that pane. If the current target pane is modified,
the selected file opens in a new vertical pane.
