VERSION = "0.1.0"

local micro = import("micro")
local config = import("micro/config")
local buffer = import("micro/buffer")
local os = import("os")
local ioutil = import("io/ioutil")
local filepath = import("filepath")
local time = import("time")

local tree_pane = nil
local target_pane = nil
local function cwd()
    local dir, err = os.Getwd()
    if err ~= nil or dir == nil then
        return "."
    end
    return dir
end

local root_dir = cwd()
local entries = {}
local expanded = {}
local target_path = nil
local last_click_y = -1
local last_click_ns = 0
local rendering_tree = false

local TREE_WIDTH = 32
local DOUBLE_CLICK_NS = 500000000

local function basename(path)
    return filepath.Base(path)
end

local function parent_dir(path)
    return filepath.Dir(path)
end

local function join_path(a, b)
    return filepath.Join(a, b)
end

local function root_label(path)
    local volume = filepath.VolumeName(path)
    local rest = path
    if volume ~= "" then
        rest = string.sub(path, string.len(volume) + 1)
    end

    local parts = {}
    for part in string.gmatch(rest, "[^/]+") do
        if part ~= "" then
            parts[#parts + 1] = part
        end
    end

    if #parts == 0 then
        if volume ~= "" then
            return volume .. "/"
        end
        return "/"
    end

    local start = #parts - 2
    if start < 1 then
        start = 1
    end

    local label = ""
    if start > 1 then
        label = ".."
    elseif filepath.IsAbs(path) or volume ~= "" then
        label = volume .. "/"
    end

    for i = start, #parts do
        label = label .. parts[i] .. "/"
    end
    return label
end

local function is_dir(path)
    local info, err = os.Stat(path)
    if err ~= nil or info == nil then
        return false
    end
    return info:IsDir()
end

local function pane_id(pane)
    if pane == nil then
        return nil
    end
    local ok, id = pcall(function()
        return pane:ID()
    end)
    if not ok then
        return nil
    end
    return id
end

local function active_pane_matches(id)
    local current = micro.CurPane()
    if current == nil then
        return false
    end
    return pane_id(current) == id
end

local function pane_index(pane)
    local id = pane_id(pane)
    if id == nil then
        return nil
    end
    local tab = micro.CurTab()
    if tab ~= nil then
        local index = tab:GetPane(id)
        tab:SetActive(index)
        if active_pane_matches(id) then
            return index
        end
        return nil
    end
    return 0
end

local function activate_pane(pane)
    local index = pane_index(pane)
    if index == nil then
        return false
    end
    local tab = micro.CurTab()
    if tab ~= nil then
        tab:SetActive(index)
    else
        pane:SetActive(true)
    end
    return true
end

local function pane_alive(pane)
    return pane_index(pane) ~= nil
end

local function clear_tree_buffer()
    tree_pane.Buf:remove(tree_pane.Buf:Start(), tree_pane.Buf:End())
end

local function append_line(y, text, newline)
    if newline then
        text = text .. "\n"
    end
    tree_pane.Buf:insert(buffer.Loc(0, y), text)
end

local function add_entry(path, depth, dir)
    entries[#entries + 1] = {
        path = path,
        depth = depth,
        dir = dir,
    }
end

local function scan_dir(path, depth)
    local files, err = ioutil.ReadDir(path)
    if err ~= nil or files == nil then
        micro.InfoBar():Error("treebrowser: cannot read ", path)
        return
    end

    local delayed_files = {}
    for i = 1, #files do
        local name = files[i]:Name()
        local full = join_path(path, name)
        local dir = files[i]:IsDir()
        if dir then
            add_entry(full, depth, true)
            if expanded[full] then
                scan_dir(full, depth + 1)
            end
        else
            delayed_files[#delayed_files + 1] = full
        end
    end

    for i = 1, #delayed_files do
        add_entry(delayed_files[i], depth, false)
    end
end

local function selected_entry()
    if tree_pane == nil then
        return nil
    end
    local y = tree_pane.Cursor.Loc.Y
    if y == 0 then
        return { path = root_dir, dir = true, root = true }
    end
    if y == 1 then
        return { path = parent_dir(root_dir), dir = true, parent = true }
    end
    return entries[y - 1]
end

local function render()
    if tree_pane == nil then
        return
    end

    local old_y = tree_pane.Cursor.Loc.Y
    entries = {}
    scan_dir(root_dir, 1)

    rendering_tree = true
    clear_tree_buffer()
    append_line(0, root_label(root_dir), true)
    append_line(1, "../", #entries > 0)
    for i = 1, #entries do
        local entry = entries[i]
        local prefix = string.rep("  ", entry.depth - 1)
        local marker = "  "
        if entry.dir then
            marker = expanded[entry.path] and "- " or "+ "
        end
        append_line(i + 1, prefix .. marker .. basename(entry.path) .. (entry.dir and "/" or ""), i < #entries)
    end
    rendering_tree = false

    if old_y > #entries + 1 then
        old_y = #entries + 1
    end
    if old_y < 0 then
        old_y = 0
    end
    tree_pane.Cursor.Loc.Y = old_y
    tree_pane.Cursor.Loc.X = 0
    tree_pane.Cursor:Relocate()
    tree_pane:Center()
    tree_pane.Cursor:SelectLine()
    micro.CurTab():Resize()
end

local function ensure_target()
    if target_pane ~= nil and target_pane ~= tree_pane then
        if pane_alive(target_pane) then
            return target_pane
        end
        target_pane = nil
        target_path = nil
    end
    local current = micro.CurPane()
    if current ~= nil and current ~= tree_pane then
        target_pane = current
        return target_pane
    end
    if tree_pane ~= nil then
        tree_pane:NextSplit()
        current = micro.CurPane()
        if current ~= nil and current ~= tree_pane then
            target_pane = current
            activate_pane(tree_pane)
            return target_pane
        end
    end
    return nil
end

local function restore_tree_focus()
    if tree_pane ~= nil then
        activate_pane(tree_pane)
        tree_pane.Cursor:SelectLine()
    end
end

local function focus_target_pane()
    if target_pane ~= nil and target_pane ~= tree_pane then
        activate_pane(target_pane)
        micro.After(10 * time.Millisecond, function()
            if target_pane ~= nil and target_pane ~= tree_pane then
                activate_pane(target_pane)
            end
        end)
    end
end

local function forget_pane(bp)
    if bp == target_pane then
        target_pane = nil
        target_path = nil
    end
end

local function load_file(path, focus_file)
    if path == nil or is_dir(path) then
        return
    end

    local pane = ensure_target()
    local newbuf = nil
    local err = nil

    if pane == nil or target_path ~= path then
        newbuf, err = buffer.NewBufferFromFile(path)
        if err ~= nil or newbuf == nil then
            micro.InfoBar():Error("treebrowser: cannot open ", path)
            return
        end
    end

    if pane == nil then
        if tree_pane == nil then
            micro.InfoBar():Error("treebrowser: no target pane")
            return
        end
        pane = tree_pane:VSplitIndex(newbuf, true)
        target_pane = pane
        target_path = path
    elseif pane.Buf ~= nil and pane.Buf:Modified() and target_path ~= path then
        pane = pane:VSplitIndex(newbuf, true)
        target_pane = pane
        target_path = path
    elseif target_path ~= path then
        pane:OpenBuffer(newbuf)
        target_pane = pane
        target_path = path
    end

    if focus_file then
        focus_target_pane()
    else
        restore_tree_focus()
    end
end

local function preview_selection()
    local entry = selected_entry()
    if entry ~= nil and not entry.dir then
        load_file(entry.path, false)
    else
        restore_tree_focus()
    end
end

local function open_selection(focus_file)
    local entry = selected_entry()
    if entry == nil then
        return
    end
    if entry.dir then
        root_dir = entry.path
        expanded[root_dir] = true
        tree_pane.Cursor.Loc.Y = 0
        render()
        restore_tree_focus()
    else
        load_file(entry.path, focus_file)
    end
end

local function toggle_dir_selection()
    local entry = selected_entry()
    if entry ~= nil and entry.dir and not entry.root and not entry.parent then
        expanded[entry.path] = not expanded[entry.path]
        render()
        restore_tree_focus()
    else
        preview_selection()
    end
end

local function select_after_move()
    if tree_pane == nil then
        return
    end
    if tree_pane.Cursor.Loc.Y < 0 then
        tree_pane.Cursor.Loc.Y = 0
    end
    if tree_pane.Cursor.Loc.Y > #entries + 1 then
        tree_pane.Cursor.Loc.Y = #entries + 1
    end
    tree_pane.Cursor.Loc.X = 0
    tree_pane.Cursor:Relocate()
    tree_pane:Center()
    tree_pane.Cursor:SelectLine()
    preview_selection()
end

local function open_tree(path)
    if path ~= nil then
        root_dir = path
    else
        root_dir = cwd()
    end
    expanded[root_dir] = true

    if tree_pane ~= nil then
        restore_tree_focus()
        render()
        return
    end

    target_pane = micro.CurPane()

    target_pane:VSplitIndex(buffer.NewBuffer("", ""), false)
    tree_pane = micro.CurPane()
    tree_pane.Buf:SetName("treebrowser")
    tree_pane.Buf.Type.Kind = buffer.BTScratch
    tree_pane.Buf.Type.Scratch = true
    tree_pane.Buf.Type.Syntax = false
    tree_pane:ResizePane(TREE_WIDTH)

    tree_pane.Buf:SetOption("ruler", "false")
    tree_pane.Buf:SetOption("statusline", "false")
    tree_pane.Buf:SetOption("scrollbar", "false")
    tree_pane.Buf:SetOption("softwrap", "false")
    tree_pane.Buf:SetOption("autosave", "false")

    render()
    restore_tree_focus()
    preview_selection()
end

local function close_tree()
    if tree_pane ~= nil then
        local closing = tree_pane
        tree_pane = nil
        closing:ForceQuit()
    end
end

local function close_non_tree_or_tree()
    if tree_pane == nil then
        return
    end

    activate_pane(tree_pane)
    tree_pane:NextSplit()

    local pane = micro.CurPane()
    if pane == nil or pane == tree_pane then
        close_tree()
        return
    end

    forget_pane(pane)
    pane:Quit()
    micro.After(10 * time.Millisecond, function()
        if target_pane == pane then
            target_pane = nil
            target_path = nil
        end
    end)
end

function toggle_tree()
    if tree_pane == nil then
        open_tree(nil)
    else
        close_tree()
    end
end

function open_root(args)
    local path = nil
    if args ~= nil and #args > 0 and args[1] ~= "" then
        path = args[1]
        if not is_dir(path) then
            micro.InfoBar():Error("treebrowser: not a directory: ", path)
            return
        end
    end
    open_tree(path)
end

local function cmd_open_root(bp, args)
    open_root(args)
end

local function cmd_toggle_tree(bp, args)
    toggle_tree()
end

local function open_on_start_enabled()
    local value = config.GetGlobalOption("treebrowser.openonstart")
    return value == true or value == "true"
end

function preQuit(bp)
    forget_pane(bp)
    if bp == tree_pane then
        close_non_tree_or_tree()
        return false
    end
end

function preForceQuit(bp)
    forget_pane(bp)
end

function preUnsplit(bp)
    forget_pane(bp)
end

function preQuitAll(bp)
    close_tree()
end

function onCursorUp(bp)
    if bp == tree_pane then
        select_after_move()
    end
end

function preCursorDown(bp)
    if bp == tree_pane then
        tree_pane.Cursor:Down()
        select_after_move()
        return false
    end
end

function preCursorLeft(bp)
    if bp == tree_pane then
        local entry = selected_entry()
        if entry ~= nil and entry.dir and not entry.root and not entry.parent and expanded[entry.path] then
            expanded[entry.path] = nil
            render()
        end
        return false
    end
end

function preCursorRight(bp)
    if bp == tree_pane then
        local entry = selected_entry()
        if entry ~= nil and entry.dir and not entry.root and not entry.parent then
            expanded[entry.path] = true
            render()
        end
        return false
    end
end

function preInsertNewline(bp)
    if bp == tree_pane then
        open_selection(true)
        return false
    end
end

function preMousePress(bp, event)
    if bp == tree_pane then
        local x, y = event:Position()
        local loc = tree_pane:LocFromVisual(buffer.Loc(x, y))
        local new_y = loc.Y
        tree_pane.Cursor.Loc.Y = new_y
        tree_pane.Cursor.Loc.X = 0
        tree_pane.Cursor:Relocate()
        tree_pane:Center()
        tree_pane.Cursor:SelectLine()

        local now = time.Now():UnixNano()
        if new_y == last_click_y and now - last_click_ns <= DOUBLE_CLICK_NS then
            open_selection(true)
        else
            toggle_dir_selection()
        end
        last_click_y = new_y
        last_click_ns = now
        return false
    end
end

function onSetActive(bp)
    if bp ~= tree_pane and bp ~= nil then
        target_pane = bp
        if bp.Buf ~= nil then
            target_path = nil
        end
    end
end

local function false_if_tree(bp)
    if bp == tree_pane then
        return false
    end
end

local function block_tree_edit(bp)
    if bp == tree_pane and not rendering_tree then
        return false
    end
end

function preRune(bp, rune) return block_tree_edit(bp) end
function preInsert(bp) return block_tree_edit(bp) end
function preInsertTab(bp) return block_tree_edit(bp) end
function preBackspace(bp) return block_tree_edit(bp) end
function preDelete(bp) return block_tree_edit(bp) end
function preDeleteWordLeft(bp) return block_tree_edit(bp) end
function preDeleteWordRight(bp) return block_tree_edit(bp) end
function preDeleteLine(bp) return block_tree_edit(bp) end
function preDuplicateLine(bp) return block_tree_edit(bp) end
function preIndentLine(bp) return block_tree_edit(bp) end
function preIndentSelection(bp) return block_tree_edit(bp) end
function preOutdentLine(bp) return block_tree_edit(bp) end
function preOutdentSelection(bp) return block_tree_edit(bp) end
function preStartOfLine(bp) return false_if_tree(bp) end
function preEndOfLine(bp) return false_if_tree(bp) end
function preSelectUp(bp) return false_if_tree(bp) end
function preSelectDown(bp) return false_if_tree(bp) end
function preSelectLeft(bp) return false_if_tree(bp) end
function preSelectRight(bp) return false_if_tree(bp) end
function preCut(bp) return false_if_tree(bp) end
function preCopy(bp) return false_if_tree(bp) end
function prePaste(bp) return false_if_tree(bp) end
function preSave(bp) return false_if_tree(bp) end

function init()
    config.RegisterGlobalOption("treebrowser", "openonstart", false)
    config.MakeCommand("treebrowser", cmd_open_root, config.FileComplete)
    config.MakeCommand("tree", cmd_toggle_tree, config.NoComplete)
    config.TryBindKey("F4", "lua:treebrowser.toggle_tree", false)
    config.AddRuntimeFile("treebrowser", config.RTHelp, "help/treebrowser.md")
end

function postinit()
    if open_on_start_enabled() then
        open_tree(nil)
    end
end
