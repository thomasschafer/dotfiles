-- Rex reads this from ~/.config/rex/init.lua. It doesn't watch the file: run
-- `rex config reload` after changing it. Shortcuts set in the app's own settings
-- win over these.

local terminal = "com.superlogical.terminal"

-- Types text into the focused terminal as if it were typed, for keys whose
-- bytes Rex would otherwise encode differently.
rex.action{
  name  = "type_text",
  title = "Type Text",
  args  = { text = "string" },
  run   = function(ctx, args)
    if ctx.block_id == nil then error("type_text: no focused terminal", 0) end
    local _, err = rex.block.call(terminal, "write", {
      block_id = ctx.block_id,
      data     = args.text,
    })
    if err ~= nil then error(err, 0) end
  end,
}

-- Rex selects sessions by ID, so this looks up the one at a position in the
-- server's session order.
rex.action{
  name  = "go_to_session",
  title = "Go to Session by Position",
  args  = { index = "integer" },
  run   = function(ctx, args)
    local result, err = rex.call("session.list")
    if err ~= nil then error(err, 0) end
    local session = result.sessions[args.index]
    if session == nil then
      error("go_to_session: there is no session " .. args.index, 0)
    end
    rex.client.queue("session.select", { session_id = session.session_id })
  end,
}

-- rex-kiosk's picker, as the "kiosk" action. Setup links kiosk.lua and builds rex-kiosk
-- from its checkout.
require("kiosk").setup{
  command = { os.getenv("HOME") .. "/Development/Personal/rex-kiosk/target/release/rex-kiosk" },
}
rex.bind("cmd+p", "kiosk")

-- --- Sessions (herdr workspaces) ---

rex.bind("cmd+n", "session.new")
rex.bind("cmd+ctrl+j", "session.next")
rex.bind("cmd+ctrl+k", "session.previous")
rex.bind("cmd+alt+]", "session.next")
rex.bind("cmd+alt+[", "session.previous")
rex.bind("shift+f2", "session.rename")
for i = 1, 9 do
  rex.bind("ctrl+" .. i, "go_to_session", { index = i })
end

-- --- Tabs ---

rex.bind("cmd+t", "client.tab.new")
rex.bind("cmd+shift+w", "client.tab.close")
rex.bind("f2", "client.tab.rename")
for _, key in ipairs({ "cmd+ctrl+h", "cmd+ctrl+left", "cmd+shift+[", "ctrl+shift+tab" }) do
  rex.bind(key, "client.tab.previous")
end
for _, key in ipairs({ "cmd+ctrl+l", "cmd+ctrl+right", "cmd+shift+]", "ctrl+tab" }) do
  rex.bind(key, "client.tab.next")
end
for i = 1, 9 do
  rex.bind("cmd+" .. i, "client.tab.goto", { index = i })
end

-- --- Panes ---

rex.bind("cmd+d", "pane.split.right")
rex.bind("cmd+shift+d", "pane.split.down")
rex.bind("cmd+w", "pane.close")
rex.bind("cmd+shift+enter", "pane.zoom")

local directions = {
  left  = { "h", "left" },
  down  = { "j", "down" },
  up    = { "k", "up" },
  right = { "l", "right" },
}
for direction, keys in pairs(directions) do
  for _, key in ipairs(keys) do
    rex.bind("cmd+shift+" .. key, "pane.focus." .. direction)
  end
  rex.bind("cmd+alt+" .. keys[2], "pane.focus." .. direction)
  rex.bind("cmd+alt+shift+" .. keys[2], "pane.move." .. direction)
end

-- --- App ---

rex.bind("cmd+shift+p", "client.palette.toggle")
rex.bind("cmd+s", "client.settings")
rex.bind("cmd+b", "client.sidebar.toggle")
rex.bind("cmd+=", "client.font.increase")
rex.bind("cmd+shift+=", "client.font.increase")
rex.bind("cmd+-", "client.font.decrease")
rex.bind("cmd+0", "client.font.reset")

-- --- Line editing, sent to the terminal ---

local typed = {
  ["alt+3"]         = "#",           -- Option as Alt would otherwise swallow it
  ["alt+left"]      = "\27[1;3D",    -- previous word
  ["alt+right"]     = "\27[1;3C",    -- next word
  ["alt+backspace"] = "\23",         -- delete previous word (ctrl+w)
  ["cmd+backspace"] = "\21",         -- delete to start of line (ctrl+u)
  ["cmd+left"]      = "\27[H",       -- start of line
  ["cmd+right"]     = "\27[F",       -- end of line
}
for key, text in pairs(typed) do
  rex.bind(key, "type_text", { text = text })
end
