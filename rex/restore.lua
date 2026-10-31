-- Starts programs again in their panes after the Rex server restarts, as herdr does.
-- Rex brings back sessions, tabs, splits and each pane's working directory itself, but
-- not what ran in them. This keeps a snapshot of the programs worth starting again, and
-- when it first sees a new server, types each one into its restored pane's shell:
-- helix with its arguments, and Claude Code and Codex resuming their sessions.
--
-- The rex-restore launchd agent (modules/rex.nix) runs it as
--   rex do --all restore.lua snapshot=PATH procinfo=PATH
-- and starts it again whenever it stops, including when the server it watches stops.

local terminal = "com.superlogical.terminal"
local home = assert(os.getenv("HOME"), "HOME isn't set")
local snapshot_path = assert(rex.args.snapshot, "pass snapshot=PATH")
local procinfo = assert(rex.args.procinfo, "pass procinfo=PATH")
local snapshot_version = 1

-- herdr's [session] restore_commands: programs started again with the same arguments.
local restore_commands = { hx = true }

local function call(method, params)
  local result, err = rex.call(method, params)
  if err ~= nil then error(method .. ": " .. err, 0) end
  return result
end

local function exec(argv, opts)
  local r, err = rex.exec(argv, opts)
  if r == nil then error(argv[1] .. ": " .. err, 0) end
  return r
end

local function applescript_string(text)
  return '"' .. text:gsub("[\\\"]", "\\%0"):gsub("%s+", " ") .. '"'
end

local function notify(text)
  rex.log("error", text)
  local r = exec{
    "/usr/bin/osascript", "-e",
    "display notification " .. applescript_string(text) .. ' with title "Rex restore"',
  }
  if not r.ok then rex.log("error", "osascript failed: " .. r.stderr) end
end

local function read_file(path)
  local f = io.open(path, "r")
  if f == nil then return nil end
  local text = f:read("*a")
  f:close()
  return text
end

local function server_instance()
  return call("server.status").instance_id
end

local function basename(path)
  return path:match("([^/]+)$")
end

-- --- Reading what runs in each pane ---

local function block_call(block, method, params)
  params = params or {}
  params.session_id, params.block_id = block.session_id, block.block_id
  local result, err = rex.block.call(terminal, method, params)
  if err ~= nil then error(method .. " of " .. block.block_id .. ": " .. err, 0) end
  return result
end

-- A pane is at its shell when the foreground process is the shell Rex started, the
-- child of the terminal's own process (login), or that process itself.
local function at_shell(p)
  local fg, child = p.foreground, p.child
  if fg == nil or child == nil then return false end
  if fg.pid == child.pid then return true end
  local parent = p.ancestors and p.ancestors[1]
  return parent ~= nil and parent.pid == child.pid
end

local function program_name(fg)
  return (basename(fg.argv0 or fg.name):gsub("^%-", ""))
end

local function terminal_blocks()
  local blocks = {}
  local sessions = call("session.list").sessions
  for _, session in ipairs(sessions) do
    -- A script can only see into sessions it's attached to, and attaching gives the view.
    local view = call("session.attach", { session_id = session.session_id }).view
    for _, window in ipairs(view.windows) do
      for _, layer in ipairs(window.layers) do
        for _, block in ipairs(layer.blocks) do
          if block.creator_name == terminal then
            table.insert(blocks, {
              block_id = block.block_id,
              session_id = session.session_id,
              session = session.label,
              window = window.label,
            })
          end
        end
      end
    end
  end
  return blocks, #sessions
end

local function process_info(pids)
  if #pids == 0 then return {} end
  local argv = { procinfo }
  for _, pid in ipairs(pids) do table.insert(argv, tostring(pid)) end
  local r = exec(argv)
  if not r.ok then error("procinfo failed: " .. r.stderr, 0) end
  return assert(rex.json.decode(r.stdout))
end

-- Claude Code records each running instance's current session, which changes on /clear
-- and /resume, in a file named for its PID.
local function claude_session(pid)
  local text = read_file(home .. "/.claude/sessions/" .. pid .. ".json")
  if text == nil then return nil, "Claude Code hasn't recorded its session" end
  local state = rex.json.decode(text)
  if state == nil or state.pid ~= pid or type(state.sessionId) ~= "string" then
    return nil, "Claude Code's session file for PID " .. pid .. " isn't as expected"
  end
  -- A session gets a transcript with its first message; before that there is nothing
  -- to resume.
  local found = exec({
    "/bin/sh", "-c",
    'for f in "$HOME"/.claude/projects/*/"$1".jsonl; do [ -e "$f" ] && exit 0; done; exit 1',
    "sh", state.sessionId,
  }).ok
  return found and state.sessionId or nil
end

local function sql_string(value)
  return "'" .. value:gsub("'", "''") .. "'"
end

-- The Codex TUI keeps its threads in a daemon, so nothing ties a TUI's process to its
-- thread. Its candidates are the threads TUIs in its directory have written since it
-- started, and the one it was started to resume with `codex resume ID`. The only TUI in
-- a directory has the latest of them. Several are told apart by thread name, which
-- Codex shows in the terminal's title as "NAME | DIRECTORY".
local function codex_thread(block, info, shared)
  local argv = info.argv
  local resumed = argv[2] == "resume" and argv[3] ~= nil and argv[3]:sub(1, 1) ~= "-"
    and argv[3] or nil
  local r = exec{
    "/usr/bin/sqlite3", "-readonly", "-json", home .. "/.codex/state_5.sqlite",
    "SELECT id, name FROM threads WHERE originator = 'codex-tui'"
      .. " AND thread_source = 'user' AND archived = 0"
      .. " AND cwd = " .. sql_string(block.fg.cwd)
      .. " AND (updated_at_ms >= " .. string.format("%d", info.started_at * 1000)
      .. (resumed and " OR id = " .. sql_string(resumed) or "")
      .. ") ORDER BY updated_at_ms DESC",
  }
  if not r.ok then return nil, "reading Codex's threads failed: " .. r.stderr end
  local rows = r.stdout:match("%S") and assert(rex.json.decode(r.stdout)) or {}
  if not shared or #rows == 0 then return rows[1] and rows[1].id end
  local title = block_call(block, "title").title or ""
  local name = title:match("^(.*) | [^|]*$")
  local matches = {}
  for _, row in ipairs(rows) do
    if name ~= nil and row.name == name then table.insert(matches, row.id) end
  end
  if #matches == 1 then return matches[1] end
  return nil, string.format(
    "more than one Codex runs in %s, and this one's title, %q, names %s of their sessions",
    block.fg.cwd, title, #matches == 0 and "none" or "several")
end

-- What to start again in a pane: { argv = ... }, { error = ... } when it ran something
-- that should come back but can't, or nil.
local function capture(block, info, codex_shared)
  local name = program_name(block.fg)
  if restore_commands[name] then
    if info == nil then return { error = name .. "'s arguments couldn't be read" } end
    local argv = { name }
    for i = 2, #info.argv do argv[i] = info.argv[i] end
    return { argv = argv }
  elseif name == "claude" then
    local id, err = claude_session(block.fg.pid)
    if err ~= nil then return { error = err } end
    return id and { argv = { "claude", "--resume", id }, agent_session = "claude:" .. id }
  elseif name == "codex" then
    if info == nil then return { error = "Codex's arguments couldn't be read" } end
    local id, err = codex_thread(block, info, codex_shared)
    if err ~= nil then return { error = err } end
    return id and { argv = { "codex", "resume", id }, agent_session = "codex:" .. id }
  end
  return nil
end

local function snapshot_programs()
  local blocks, session_count = terminal_blocks()
  local running, pids, codex_per_cwd = {}, {}, {}
  for _, block in ipairs(blocks) do
    local p = block_call(block, "process")
    if not at_shell(p) and p.foreground ~= nil and p.foreground.cwd ~= nil then
      block.fg = p.foreground
      table.insert(running, block)
      table.insert(pids, p.foreground.pid)
      if program_name(p.foreground) == "codex" then
        codex_per_cwd[p.foreground.cwd] = (codex_per_cwd[p.foreground.cwd] or 0) + 1
      end
    end
  end
  local infos = process_info(pids)
  local programs = {}
  for _, block in ipairs(running) do
    local entry = capture(block, infos[tostring(block.fg.pid)],
      (codex_per_cwd[block.fg.cwd] or 0) > 1)
    if entry ~= nil then
      entry.block_id = block.block_id
      entry.session = block.session
      entry.window = block.window
      entry.cwd = block.fg.cwd
      entry.program = program_name(block.fg)
      table.insert(programs, entry)
    end
  end
  table.sort(programs, function(a, b) return a.block_id < b.block_id end)
  return programs, session_count
end

-- --- The snapshot file ---

local function valid_snapshot(snapshot)
  if type(snapshot) ~= "table" or snapshot.version ~= snapshot_version
    or type(snapshot.server_instance) ~= "string" then
    return false
  end
  snapshot.programs = snapshot.programs or {}
  for _, entry in ipairs(snapshot.programs) do
    if type(entry.block_id) ~= "string" or type(entry.cwd) ~= "string"
      or (type(entry.argv) ~= "table") == (type(entry.error) ~= "string") then
      return false
    end
  end
  return true
end

local function load_snapshot()
  local text = read_file(snapshot_path)
  if text == nil then return nil end
  local snapshot = rex.json.decode(text)
  if valid_snapshot(snapshot) then return snapshot end
  local aside = snapshot_path .. ".unreadable-" .. os.time()
  assert(os.rename(snapshot_path, aside))
  notify("The snapshot of programs to restore was unreadable, so nothing was restored. It's kept at " .. aside)
  return nil
end

local function write_atomically(path, text)
  local tmp = path .. ".tmp"
  local f = assert(io.open(tmp, "w"))
  assert(f:write(text))
  assert(f:close())
  assert(os.rename(tmp, path))
end

local function write_snapshot(snapshot)
  local text = assert(rex.json.encode(snapshot, { indent = true })) .. "\n"
  if text ~= read_file(snapshot_path) then write_atomically(snapshot_path, text) end
end

-- --- Restoring ---

local function shell_quote(arg)
  if arg:match("^[%w_./:=@%%+,-]+$") then return arg end
  return "'" .. arg:gsub("'", [['\'']]) .. "'"
end

local function command_line(argv)
  local quoted = {}
  for i, arg in ipairs(argv) do quoted[i] = shell_quote(arg) end
  return table.concat(quoted, " ")
end

local function describe(entry)
  return string.format("%s in %s › %s", entry.program, entry.session or "?", entry.window or "?")
end

-- Waits for a restored pane's shell to be in the foreground, which it is as soon as it
-- starts, then a little longer for it to start reading input. Returns the shell's
-- process, or nil and the pane's foreground process if it never is.
local function wait_for_shell(block)
  local p
  for _ = 1, 40 do
    p = block_call(block, "process")
    if at_shell(p) then
      rex.sleep(1)
      return p.foreground
    end
    rex.sleep(0.25)
  end
  return nil, p.foreground
end

-- Starts one program again, returning why it couldn't be.
local function restore_program(entry, block, resumed)
  if entry.error ~= nil then return entry.error end
  if block == nil then return "Rex didn't restore its pane" end
  if entry.agent_session ~= nil and resumed[entry.agent_session] then
    return "its session is already resumed in another pane"
  end
  -- A pane already running its program, as when the program outlived the server that
  -- started it, is left alone.
  local fg = block_call(block, "process").foreground
  if fg ~= nil and program_name(fg) == entry.program then
    if entry.agent_session ~= nil then resumed[entry.agent_session] = true end
    rex.log("info", describe(entry) .. " is still running")
    return nil
  end
  local shell, busy = wait_for_shell(block)
  if shell == nil then
    return "its pane is running " .. (busy and program_name(busy) or "something else")
  end
  if shell.cwd ~= entry.cwd then
    return "its pane is in " .. tostring(shell.cwd) .. ", not " .. entry.cwd
  end
  block_call(block, "write", { data = command_line(entry.argv) .. "\r" })
  if entry.agent_session ~= nil then resumed[entry.agent_session] = true end
  rex.log("info", "restored " .. describe(entry) .. ": " .. command_line(entry.argv))
  return nil
end

local function restore(snapshot)
  local blocks = {}
  for _, block in ipairs((terminal_blocks())) do blocks[block.block_id] = block end
  local failures, resumed = {}, {}
  for _, entry in ipairs(snapshot.programs) do
    local ok, why = pcall(restore_program, entry, blocks[entry.block_id], resumed)
    if not ok or why ~= nil then
      local failure = describe(entry) .. ": " .. tostring(why)
      rex.log("error", "couldn't restore " .. failure)
      table.insert(failures, failure)
    end
  end
  if #failures > 0 then
    notify(string.format("Couldn't restore %d of %d programs: %s", #failures,
      #snapshot.programs, table.concat(failures, "; ")))
  end
  rex.log("info", string.format("restored %d of %d programs",
    #snapshot.programs - #failures, #snapshot.programs))
end

-- --- Main ---

local instance = server_instance()
local previous = load_snapshot()
-- Each server's restore is tried once, even if this stops partway through, so a
-- program is never typed into its pane twice.
local restored_for = snapshot_path .. ".restored-for"
if previous ~= nil and previous.server_instance ~= instance
  and read_file(restored_for) ~= instance then
  write_atomically(restored_for, instance)
  -- Kept, as saving this server's programs replaces the snapshot.
  write_atomically(snapshot_path .. ".previous", read_file(snapshot_path))
  restore(previous)
end

local function save()
  if server_instance() ~= instance then
    rex.log("error", "the Rex server restarted; stopping so the restart restores its programs")
    rex.stop(1)
  end
  local programs, session_count = snapshot_programs()
  -- A server with no sessions, such as one started without its saved sessions, would
  -- otherwise replace a snapshot that may still be wanted.
  if session_count == 0 then return end
  write_snapshot{
    version = snapshot_version,
    server_instance = instance,
    programs = programs,
  }
end

save()

local pending
local function save_soon()
  if pending ~= nil then pending:cancel() end
  pending = rex.after(2, save)
end
for _, event in ipairs({ "terminal.process_changed", "block_closed", "session_destroyed" }) do
  rex.on(event, save_soon)
end
-- Agents change sessions without changing process, as on /clear.
rex.every(30, save)
