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

local function call(method, params)
  local result, err = rex.call(method, params)
  if err ~= nil then error(method .. ": " .. err, 0) end
  return result
end

-- Rex keeps no focus history, so the last-session and last-pane keys keep their
-- own. Every action below records where it ran and where it leaves focus. A move
-- made some other way, such as a click, shows up as one step the next time one of
-- them runs, so a single such move between keys is remembered correctly.
local history = { session = {}, pane_by_window = {} }

local function visit(h, from, to)
  if h.seen ~= nil and h.seen ~= from then h.other = h.seen end
  if to ~= from then h.other = from end
  h.seen = to
end

local function require_ctx(ctx, field, action)
  if ctx[field] == nil then error(action .. ": Rex gave no " .. field, 0) end
  return ctx[field]
end

-- --- Session switching ---

local function session_ids()
  local ids = {}
  for _, session in ipairs(call("session.list").sessions) do
    table.insert(ids, session.session_id)
  end
  return ids
end

local function index_of(list, value)
  for i, item in ipairs(list) do
    if item == value then return i end
  end
  return nil
end

local function switch_session(from, to)
  visit(history.session, from, to)
  rex.client.queue("session.select", { session_id = to })
end

-- Rex selects sessions by ID, so this looks up the one at a position in the
-- server's session order.
rex.action{
  name  = "go_to_session",
  title = "Go to Session by Position",
  args  = { index = "integer" },
  run   = function(ctx, args)
    local from = require_ctx(ctx, "session_id", "go_to_session")
    local to = session_ids()[args.index]
    if to == nil then
      error("go_to_session: there is no session " .. args.index, 0)
    end
    switch_session(from, to)
  end,
}

rex.action{
  name  = "step_session",
  title = "Go to Next or Previous Session",
  args  = { offset = "integer" },
  run   = function(ctx, args)
    local from = require_ctx(ctx, "session_id", "step_session")
    local ids = session_ids()
    local i = index_of(ids, from)
    if i == nil then error("step_session: the current session isn't listed", 0) end
    switch_session(from, ids[(i - 1 + args.offset) % #ids + 1])
  end,
}

rex.action{
  name  = "last_session",
  title = "Go to Last Session",
  run   = function(ctx)
    local from = require_ctx(ctx, "session_id", "last_session")
    local h = history.session
    visit(h, from, from)
    if h.other == nil then error("last_session: no earlier session yet", 0) end
    if index_of(session_ids(), h.other) == nil then
      h.other = nil
      error("last_session: the last session has closed", 0)
    end
    switch_session(from, h.other)
  end,
}

-- --- Pane focus ---

local function window_holding(view, block_id)
  for _, window in ipairs(view.windows) do
    for _, layer in ipairs(window.layers) do
      for _, block in ipairs(layer.blocks) do
        if block.block_id == block_id then return window end
      end
    end
  end
  return nil
end

-- Pane history is per tab, as herdr's last pane is.
local function session_view(session)
  return call("session.view", { session_id = session })
end

local function pane_history(ctx, action)
  local session = require_ctx(ctx, "session_id", action)
  local block = require_ctx(ctx, "block_id", action)
  local window = window_holding(session_view(session), block)
  if window == nil then error(action .. ": the focused pane isn't in any tab", 0) end
  local h = history.pane_by_window[window.window_id] or {}
  history.pane_by_window[window.window_id] = h
  return h, session, block, window
end

rex.action{
  name  = "focus_pane",
  title = "Focus Pane in a Direction",
  args  = { direction = "string" },
  run   = function(ctx, args)
    local h, session, from, window = pane_history(ctx, "focus_pane")
    call("session.focus_direction", { session_id = session, direction = args.direction })
    local after = window_holding(session_view(session), from)
    if after == nil or after.window_id ~= window.window_id then
      error("focus_pane: the pane's tab changed while moving focus", 0)
    end
    visit(h, from, after.focused_block_id)
  end,
}

rex.action{
  name  = "last_pane",
  title = "Focus Last Pane in Tab",
  run   = function(ctx)
    local h, session, from, window = pane_history(ctx, "last_pane")
    visit(h, from, from)
    if h.other == nil then error("last_pane: no earlier pane in this tab yet", 0) end
    local target = window_holding(session_view(session), h.other)
    if target == nil or target.window_id ~= window.window_id then
      h.other = nil
      error("last_pane: the last pane in this tab has closed", 0)
    end
    local to = h.other
    call("session.focus_block", { session_id = session, block_id = to })
    visit(h, from, to)
  end,
}

-- --- Agent navigation ---

-- Steps through the panes whose programs report a status with OSC 7501 (Claude Code
-- and Codex do), across every session, as herdr's next and previous agent keys do
-- with agent_panel_sort = "priority": the most urgent first, and within a state the
-- most recently changed first. herdr has no error state, so error ranks with done.
local status_priority = { blocked = 4, done = 3, error = 3, working = 2, idle = 1 }

-- Rex stamps each record with the time of its latest report, and agents report again
-- without changing state (Claude Code each time it starts a tool), so this keeps when
-- each pane was first seen in its current state, to order panes by state changes as
-- herdr does.
local status_since = {}

local function root_status(session, block_id)
  local status = call(terminal .. ".program_status", {
    session_id = session,
    block_id   = block_id,
    args       = {},
  })
  for _, record in ipairs(status.records) do
    if record.id == nil then return record end
  end
  return nil
end

-- Every pane with a status, most urgent first. Calls about a session fail until the
-- action has attached to it, and attaching returns the session's view.
local function agent_panes()
  local panes = {}
  local seen = {}
  for _, session in ipairs(session_ids()) do
    local view = call("session.attach", { session_id = session }).view
    for _, window in ipairs(view.windows) do
      for _, layer in ipairs(window.layers) do
        for _, block in ipairs(layer.blocks) do
          local record = block.creator_name == terminal and root_status(session, block.block_id)
          if record then
            local previous = status_since[block.block_id]
            local since = record.updated_at
            if previous ~= nil and previous.state == record.state then since = previous.since end
            seen[block.block_id] = { state = record.state, since = since }
            table.insert(panes, {
              session  = session,
              window   = window,
              block_id = block.block_id,
              -- Rex says to read a state it doesn't document as idle.
              priority = status_priority[record.state] or status_priority.idle,
              since    = since,
              position = #panes,
            })
          end
        end
      end
    end
  end
  status_since = seen
  table.sort(panes, function(a, b)
    if a.priority ~= b.priority then return a.priority > b.priority end
    -- RFC 3339 times from the server's clock, so they order as strings.
    if a.since ~= b.since then return a.since > b.since end
    return a.position < b.position
  end)
  return panes
end

-- From a pane that isn't an agent's, the next agent is the first and the previous one
-- the last, as in herdr.
local function focus_agent(ctx, offset, action)
  local from_session = require_ctx(ctx, "session_id", action)
  local panes = agent_panes()
  if #panes == 0 then return end
  local current = nil
  for i, pane in ipairs(panes) do
    if pane.session == from_session and pane.block_id == ctx.block_id then current = i end
  end
  local target
  if current ~= nil then
    target = panes[(current - 1 + offset) % #panes + 1]
  elseif offset > 0 then
    target = panes[1]
  else
    target = panes[#panes]
  end

  local window_id = target.window.window_id
  local h = history.pane_by_window[window_id] or {}
  history.pane_by_window[window_id] = h
  call("session.focus_block", { session_id = target.session, block_id = target.block_id })
  visit(h, target.window.focused_block_id, target.block_id)
  if target.session ~= from_session then switch_session(from_session, target.session) end
end

rex.action{
  name  = "next_agent",
  title = "Focus Next Agent",
  run   = function(ctx) focus_agent(ctx, 1, "next_agent") end,
}

rex.action{
  name  = "previous_agent",
  title = "Focus Previous Agent",
  run   = function(ctx) focus_agent(ctx, -1, "previous_agent") end,
}

-- rex-kiosk's picker, as the "kiosk" action. Setup links kiosk.lua and builds rex-kiosk
-- from its checkout. A failed require would stop the rest of this file loading, so it's
-- logged instead.
local kiosk_loaded, kiosk = pcall(require, "kiosk")
if kiosk_loaded then
  kiosk.setup{
    command = { os.getenv("HOME") .. "/Development/Personal/rex-kiosk/target/release/rex-kiosk" },
  }
  rex.bind("cmd+p", "kiosk")
else
  rex.log("error", "rex-kiosk isn't set up, so Cmd+P does nothing: " .. tostring(kiosk))
end

-- --- Sessions (herdr workspaces) ---

rex.bind("cmd+n", "session.new")
for _, key in ipairs({ "cmd+ctrl+j", "cmd+alt+]" }) do
  rex.bind(key, "step_session", { offset = 1 })
end
for _, key in ipairs({ "cmd+ctrl+k", "cmd+alt+[" }) do
  rex.bind(key, "step_session", { offset = -1 })
end
rex.bind("cmd+,", "last_session")
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
rex.bind("cmd+l", "last_pane")

local directions = {
  left  = { "h", "left" },
  down  = { "j", "down" },
  up    = { "k", "up" },
  right = { "l", "right" },
}
for direction, keys in pairs(directions) do
  for _, key in ipairs(keys) do
    rex.bind("cmd+shift+" .. key, "focus_pane", { direction = direction })
  end
  rex.bind("cmd+alt+" .. keys[2], "focus_pane", { direction = direction })
  rex.bind("cmd+alt+shift+" .. keys[2], "pane.move." .. direction)
end

-- --- Agents ---

rex.bind("cmd+j", "next_agent")
rex.bind("cmd+k", "previous_agent")

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
