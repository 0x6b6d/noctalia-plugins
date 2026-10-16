--!nonstrict
-- Taskwarrior subprocess operations for the panel entry. Operates on the
-- shared state store; re-renders through the entry-bound renderer
-- (Ops.bind(render) in panel.luau) so tab modules never touch render order.

local tasklib = require("./task.luau")
local S = require("./panel_state.luau")
local X = require("./export.luau")

local Ops = {}

local R = function() end

function Ops.bind(fn)
  R = fn
end

function Ops.rerender()
  R()
end

-- Widget tracking override (the star in Projects). Settings are read-only
-- for plugins, so the panel stores {active, project} in shared state and
-- mirrors it to a file for durability across restarts.
Ops.TRACK_KEY = "trackOverride"
Ops.TRACK_FILE = "tracked.json"

local function trackFilePath()
  local ok, dir = pcall(function()
    return noctalia.pluginDataDir()
  end)
  if not ok or type(dir) ~= "string" or dir == "" then
    return nil
  end
  return dir .. "/" .. Ops.TRACK_FILE
end

function Ops.getOverride()
  local v = noctalia.state.get(Ops.TRACK_KEY)
  if type(v) == "table" and v["active"] == true then
    return { active = true, project = tostring(v["project"] or "") }
  end
  return { active = false, project = "" }
end

function Ops.loadPersistedOverride()
  local path = trackFilePath()
  if path == nil then
    return { active = false, project = "" }
  end
  local raw = noctalia.readFile(path)
  if type(raw) ~= "string" or raw == "" then
    return { active = false, project = "" }
  end
  local ok, val = pcall(function()
    return noctalia.json.decode(raw)
  end)
  if not ok or type(val) ~= "table" or val["active"] ~= true then
    return { active = false, project = "" }
  end
  return { active = true, project = tostring(val["project"] or "") }
end

function Ops.persistOverride(ov)
  local path = trackFilePath()
  if path == nil then
    return
  end
  local ok, raw = pcall(function()
    return noctalia.json.encode(ov)
  end)
  if ok and type(raw) == "string" then
    noctalia.writeFile(path, raw)
  end
end

function Ops.setOverride(project)
  local ov = { active = true, project = project or "" }
  noctalia.state.set(Ops.TRACK_KEY, ov)
  Ops.persistOverride(ov)
end

function Ops.clearOverride()
  local ov = { active = false, project = "" }
  noctalia.state.set(Ops.TRACK_KEY, ov)
  Ops.persistOverride(ov)
end

-- After a restart the state channel is empty; restore a persisted override
-- so the panel (and anything reading state) agrees with the widget.
function Ops.syncOverrideFromFile()
  if Ops.getOverride().active then
    return
  end
  local ov = Ops.loadPersistedOverride()
  if ov.active then
    noctalia.state.set(Ops.TRACK_KEY, ov)
  end
end

-- Effective tracked project + where it came from ("override", "setting", "all").
function Ops.trackingStatus()
  local ov = Ops.getOverride()
  if ov.active then
    if ov.project == "" then
      return "", "override"
    end
    return ov.project, "override"
  end
  local s = noctalia.string.trim(tostring(noctalia.getConfig("project_filter") or ""))
  if s ~= "" then
    return s, "setting"
  end
  return "", "all"
end

function Ops.defaultRcPath()
  if S.rcPath ~= "" then
    return S.rcPath
  end
  return noctalia.expandPath("~/.taskrc")
end

function Ops.defaultDataDir()
  local d = noctalia.getConfig("data_location")
  if type(d) == "string" and d ~= "" then
    return d
  end
  return noctalia.expandPath("~/.task")
end

function Ops.findTask(uuid)
  for _, t in ipairs(S.tasks) do
    if t["uuid"] == uuid then
      return t
    end
  end
  for _, t in ipairs(S.completedFull) do
    if t["uuid"] == uuid then
      return t
    end
  end
  for _, t in ipairs(S.completed) do
    if t["uuid"] == uuid then
      return t
    end
  end
  return nil
end

function Ops.ensureDetail(t)
  S.detail.desc = tostring(t["description"] or "")
  S.detail.project = tostring(t["project"] or "")
  S.detail.due = ""
  S.detail.scheduled = ""
  S.detail.wait = ""
  -- Export dates are UTC stamps; keep the short form for editing.
  if type(t["due"]) == "string" then
    S.detail.due = tasklib.formatDue(t["due"])
  end
  if type(t["scheduled"]) == "string" then
    S.detail.scheduled = tasklib.formatDue(t["scheduled"])
  end
  if type(t["wait"]) == "string" then
    S.detail.wait = tasklib.formatDue(t["wait"])
  end
  local real = {}
  if type(t["tags"]) == "table" then
    for _, tg in ipairs(t["tags"]) do
      if not tasklib.isVirtualTag(tg) then
        table.insert(real, tg)
      end
    end
  end
  S.detail.tags = table.concat(real, " ")
  local p = t["priority"]
  S.detail.priIdx = 0
  if p == "H" then
    S.detail.priIdx = 1
  elseif p == "M" then
    S.detail.priIdx = 2
  elseif p == "L" then
    S.detail.priIdx = 3
  end
  -- Snapshot of what the form shows: save sends only fields that differ
  -- from this, so untouched dates keep their exact export stamps.
  S.detailOrig = {
    desc = S.detail.desc,
    project = S.detail.project,
    due = S.detail.due,
    scheduled = S.detail.scheduled,
    wait = S.detail.wait,
    tags = S.detail.tags,
    priIdx = S.detail.priIdx,
  }
  S.detailKey += 1
  S.noteText = ""
  S.noteKey += 1
  S.deleteArmedAt = nil
end

function Ops.selectTask(uuid)
  S.selectedUuid = uuid
  local t = Ops.findTask(uuid)
  if t ~= nil then
    Ops.ensureDetail(t)
  end
end

function Ops.dropSelectionIfGone()
  if S.selectedUuid ~= "" and Ops.findTask(S.selectedUuid) == nil then
    S.selectedUuid = ""
  end
  if S.expandedMenuUuid ~= "" and Ops.findTask(S.expandedMenuUuid) == nil then
    S.expandedMenuUuid = ""
  end
end

function Ops.openEditor(uuid)
  Ops.selectTask(uuid)
  S.gotoTab("edit")
  R()
end

function Ops.requestRefresh()
  noctalia.state.set("refreshReq", noctalia.nowMs())
end

function Ops.fetchTasks()
  if not noctalia.commandExists(S.bin) then
    S.backend = { ok = false, error = noctalia.tr("status.no_binary", { bin = S.bin }), setup = false }
    noctalia.state.set("backend", S.backend)
    R()
    return
  end
  X.fetchPending(S.bin, S.rcPath, function(pending, err)
    if pending == nil then
      local msg = err or noctalia.tr("status.export_failed")
      S.backend = { ok = false, error = msg, setup = tasklib.isMissingRc(msg) }
      noctalia.state.set("backend", S.backend)
      S.setStatus(msg, true)
      R()
      return
    end
    S.tasks = pending
    S.backend = { ok = true, error = "" }
    noctalia.state.set("tasks", S.tasks)
    noctalia.state.set("backend", S.backend)
    noctalia.state.set("last_sync", os.time())
    -- Windowed completed for the graph (mirrored to shared state),
    -- totals via count, full history kept panel-local for detail +
    -- per-project progress. Mutations never touch the busy flag here:
    -- it belongs to runTask/doAdd, and clearing it from a fetch allows
    -- double submits.
    X.fetchWindowed(S.bin, S.rcPath, 14, function(win)
      if win ~= nil then
        S.completed = win
        noctalia.state.set("completed", S.completed)
      end
      X.fetchDoneTotal(S.bin, S.rcPath, function(total)
        X.fetchFullCompleted(S.bin, S.rcPath, function(full)
          if full ~= nil then
            S.completedFull = full
          end
          S.meta = tasklib.computeMeta(S.tasks, S.completed)
          if total ~= nil then
            S.meta.completed = total
          end
          noctalia.state.set("meta", S.meta)
          R()
        end)
      end)
    end)
  end)
end

function Ops.runTask(args, okMsg, after)
  if S.busy then
    return
  end
  S.busy = true
  S.setStatus(noctalia.tr("status.running"), false)
  R()
  local argv = tasklib.withBase(S.bin, S.rcPath, args)
  noctalia.runAsync(argv, function(res)
    S.busy = false
    if res == nil or res.exitCode ~= 0 then
      local err = ""
      if res ~= nil then
        err = tostring(res.stderr or "")
        if err == "" then
          err = tostring(res.stdout or "")
        end
      end
      if err == "" then
        err = noctalia.tr("status.command_failed")
      end
      S.setStatus(err, true)
      noctalia.notifyError("Taskwarrior", err)
      R()
      return
    end
    if okMsg ~= nil and okMsg ~= "" then
      S.setStatus(okMsg, false)
    else
      S.setStatus("", false)
    end
    if after ~= nil then
      after()
    end
    Ops.requestRefresh()
    Ops.fetchTasks()
  end)
end

function Ops.doDone(uuid)
  Ops.runTask({ uuid, "done" }, noctalia.tr("status.task_completed"), function()
    if S.selectedUuid == uuid then
      S.selectedUuid = ""
    end
    if S.expandedMenuUuid == uuid then
      S.expandedMenuUuid = ""
    end
  end)
end

function Ops.doDelete(uuid)
  Ops.runTask({ uuid, "delete" }, noctalia.tr("status.task_deleted"), function()
    if S.selectedUuid == uuid then
      S.selectedUuid = ""
    end
    if S.expandedMenuUuid == uuid then
      S.expandedMenuUuid = ""
    end
  end)
end

function Ops.doToggleStart(uuid)
  local t = Ops.findTask(uuid)
  if t ~= nil and t["start"] ~= nil then
    Ops.runTask({ uuid, "stop" }, noctalia.tr("status.timer_stopped"))
  else
    Ops.runTask({ uuid, "start" }, noctalia.tr("status.timer_started"))
  end
end

function Ops.splitTags(s)
  -- Returns clean tags, skipped junk. Task tags can't carry :, / or = and
  -- those would be parsed as attributes, so refuse them loudly.
  local out, skipped = {}, {}
  if type(s) ~= "string" then
    return out, skipped
  end
  local cleaned = string.gsub(s, ",", " ")
  for w in string.gmatch(cleaned, "%S+") do
    local tag = w
    if tag:sub(1, 1) == "+" then
      tag = tag:sub(2)
    end
    if tag == "" then
      -- ignore
    elseif string.find(tag, "[:/=]") then
      table.insert(skipped, tag)
    else
      table.insert(out, tag)
    end
  end
  return out, skipped
end

local PRI_MAP = { [0] = "", [1] = "H", [2] = "M", [3] = "L" }

function Ops.doSaveDetail()
  local t = Ops.findTask(S.selectedUuid)
  if t == nil then
    return
  end
  -- Send only changed fields: untouched dates keep their exact stamps
  -- (re-sending our display format would shift them through task's parser).
  -- Descriptions travel after -- so metacharacters stay literal text.
  local o = S.detailOrig
  local mods = {}
  local desc = nil
  local skippedTags = nil
  local changed = 0
  if S.detail.desc ~= o.desc then
    changed += 1
    if noctalia.string.trim(S.detail.desc) ~= "" then
      desc = S.detail.desc
    else
      S.setStatus(noctalia.tr("status.kept_description"), false)
    end
  end
  if S.detail.project ~= o.project then
    changed += 1
    if S.detail.project ~= "" then
      table.insert(mods, "project:" .. S.detail.project)
    else
      table.insert(mods, "project:")
    end
  end
  if S.detail.priIdx ~= o.priIdx then
    changed += 1
    local pv = PRI_MAP[S.detail.priIdx] or ""
    if pv ~= "" then
      table.insert(mods, "pri:" .. pv)
    else
      table.insert(mods, "pri:")
    end
  end
  if S.detail.due ~= o.due then
    changed += 1
    if S.detail.due ~= "" then
      table.insert(mods, "due:" .. S.detail.due)
    else
      table.insert(mods, "due:")
    end
  end
  if S.detail.scheduled ~= o.scheduled then
    changed += 1
    if S.detail.scheduled ~= "" then
      table.insert(mods, "scheduled:" .. S.detail.scheduled)
    else
      table.insert(mods, "scheduled:")
    end
  end
  if S.detail.wait ~= o.wait then
    changed += 1
    if S.detail.wait ~= "" then
      table.insert(mods, "wait:" .. S.detail.wait)
    else
      table.insert(mods, "wait:")
    end
  end
  if S.detail.tags ~= o.tags then
    changed += 1
    -- Tag diff: remove stale, add new.
    local cur = {}
    if type(t["tags"]) == "table" then
      for _, tg in ipairs(t["tags"]) do
        if not tasklib.isVirtualTag(tg) then
          cur[tg] = true
        end
      end
    end
    local want = {}
    local fresh, skipped = Ops.splitTags(S.detail.tags)
    if #skipped > 0 then
      skippedTags = table.concat(skipped, ", ")
    end
    for _, tg in ipairs(fresh) do
      want[tg] = true
      if not cur[tg] then
        table.insert(mods, "+" .. tg)
      end
    end
    for tg in pairs(cur) do
      if not want[tg] then
        table.insert(mods, "-" .. tg)
      end
    end
  end
  if changed == 0 then
    S.setStatus(noctalia.tr("status.no_changes"), false)
    R()
    return
  end
  local args = { S.selectedUuid, "modify" }
  for _, m in ipairs(mods) do
    table.insert(args, m)
  end
  if desc ~= nil then
    table.insert(args, "--")
    table.insert(args, desc)
  end
  local updatedMsg = noctalia.tr("status.task_updated")
  if skippedTags ~= nil then
    updatedMsg = noctalia.tr("status.task_updated_skipped", { tags = skippedTags })
  end
  Ops.runTask(args, updatedMsg)
end

local function cmdErr(res)
  local err = ""
  if res ~= nil then
    err = tostring(res.stderr or "")
    if err == "" then
      err = tostring(res.stdout or "")
    end
  end
  if err == "" then
    err = "command failed"
  end
  return err
end

function Ops.doAdd(clearAfter)
  local desc = noctalia.string.trim(S.addForm.desc)
  if desc == "" then
    S.setStatus(noctalia.tr("status.required_description"), true)
    R()
    return
  end
  if S.busy then
    return
  end
  S.busy = true
  S.setStatus(noctalia.tr("status.running"), false)
  R()
  local mods = {}
  if S.addForm.project ~= "" then
    table.insert(mods, "project:" .. noctalia.string.trim(S.addForm.project))
  end
  local pv = PRI_MAP[S.addForm.priIdx] or ""
  if pv ~= "" then
    table.insert(mods, "pri:" .. pv)
  end
  if noctalia.string.trim(S.addForm.due) ~= "" then
    table.insert(mods, "due:" .. noctalia.string.trim(S.addForm.due))
  end
  if noctalia.string.trim(S.addForm.scheduled) ~= "" then
    table.insert(mods, "scheduled:" .. noctalia.string.trim(S.addForm.scheduled))
  end
  if noctalia.string.trim(S.addForm.wait) ~= "" then
    table.insert(mods, "wait:" .. noctalia.string.trim(S.addForm.wait))
  end
  local fresh, skipped = Ops.splitTags(S.addForm.tags)
  for _, tg in ipairs(fresh) do
    table.insert(mods, "+" .. tg)
  end
  local skippedTags = nil
  if #skipped > 0 then
    skippedTags = table.concat(skipped, ", ")
  end
  local function addedMsg(plain, skipped)
    if skippedTags ~= nil then
      return noctalia.tr(skipped, { tags = skippedTags })
    end
    return noctalia.tr(plain)
  end
  local args = { "add" }
  for _, m in ipairs(mods) do
    table.insert(args, m)
  end
  -- Description last behind -- so metacharacters stay literal text.
  table.insert(args, "--")
  table.insert(args, desc)
  local note = noctalia.string.trim(S.addForm.note)
  local function finish(msg, isErr)
    S.setStatus(msg, isErr)
    if clearAfter then
      S.addForm = { desc = "", project = "", due = "", scheduled = "", wait = "", tags = "", priIdx = 0, note = "" }
      S.addKey += 1
    end
    S.busy = false
    Ops.requestRefresh()
    Ops.fetchTasks()
  end
  noctalia.runAsync(tasklib.withBase(S.bin, S.rcPath, args), function(res)
    if res == nil or res.exitCode ~= 0 then
      local err = cmdErr(res)
      S.busy = false
      S.setStatus(err, true)
      noctalia.notifyError("Taskwarrior", err)
      R()
      return
    end
    if note == "" then
      finish(addedMsg("status.task_added", "status.task_added_skipped"), false)
      return
    end
    -- Resolve the new task: exact description + newest entry stamp.
    X.fetchPending(S.bin, S.rcPath, function(list, lerr)
      if list == nil then
        finish(noctalia.tr("status.note_skipped_unreadable"), true)
        return
      end
      local uuid = nil
      local bestEntry = nil
      for _, t in ipairs(list) do
        if tostring(t["description"] or "") == desc
          and (bestEntry == nil or tostring(t["entry"] or "") > bestEntry) then
          bestEntry = tostring(t["entry"] or "")
          uuid = t["uuid"]
        end
      end
      if type(uuid) ~= "string" or uuid == "" then
        finish(noctalia.tr("status.note_skipped_missing"), true)
        return
      end
      local argv3 = tasklib.withBase(S.bin, S.rcPath, { uuid, "annotate", note })
      noctalia.runAsync(argv3, function(res3)
        if res3 == nil or res3.exitCode ~= 0 then
          finish(noctalia.tr("status.note_failed", { error = cmdErr(res3) }), true)
          return
        end
        finish(addedMsg("status.task_note_added", "status.task_note_added_skipped"), false)
      end)
    end)
  end)
end

function Ops.doAnnotate()
  local note = noctalia.string.trim(S.noteText)
  if S.selectedUuid == "" or note == "" then
    return
  end
  Ops.runTask({ S.selectedUuid, "annotate", note }, noctalia.tr("status.note_added"), function()
    S.noteText = ""
    S.noteKey += 1
  end)
end

function Ops.doDenotate(text)
  if S.selectedUuid == "" then
    return
  end
  Ops.runTask({ S.selectedUuid, "denotate", text }, noctalia.tr("status.note_removed"))
end

function Ops.doUndo()
  Ops.runTask({ "undo" }, noctalia.tr("status.undo_done"))
end

function Ops.doSync()
  -- `task sync` needs a configured replica. Taskwarrior 2.x used
  -- sync.server; 3.x uses sync.server.url / gcp / aws / git / local keys.
  -- Without any of them the command is a no-op, so check first instead of
  -- reporting a fake success.
  local SYNC_KEYS = {
    "sync.server=",
    "sync.server.url=",
    "sync.gcp.bucket=",
    "sync.aws.bucket=",
    "sync.git.remote=",
    "sync.local.server_dir=",
  }
  local argv = tasklib.withBase(S.bin, S.rcPath, { "_config" })
  noctalia.runAsync(argv, function(res)
    local server = ""
    if res ~= nil and res.exitCode == 0 then
      for line in string.gmatch(res.stdout or "", "[^\n]+") do
        for _, key in ipairs(SYNC_KEYS) do
          if string.sub(line, 1, #key) == key
            and noctalia.string.trim(string.sub(line, #key + 1)) ~= "" then
            server = noctalia.string.trim(string.sub(line, #key + 1))
          end
        end
      end
    end
    if server == "" then
      S.setStatus(noctalia.tr("status.sync_none"), false)
      noctalia.notify(noctalia.tr("title"), noctalia.tr("status.sync_none_body"))
      R()
      return
    end
    Ops.runTask({ "sync" }, noctalia.tr("status.sync_done", { server = server }))
  end)
end

function Ops.doSetupInit()
  local dir = noctalia.expandPath(S.setupDir ~= "" and S.setupDir or Ops.defaultDataDir())
  local rc = noctalia.expandPath(Ops.defaultRcPath())
  -- Never clobber a real config: locks, parse errors and version mismatches
  -- all land here with an existing rc file.
  if noctalia.fileExists(rc) then
    local raw = noctalia.readFile(rc)
    if type(raw) == "string" and noctalia.string.trim(raw) ~= "" then
      S.setStatus(noctalia.tr("status.refuse_overwrite", { rc = rc }), true)
      R()
      return
    end
  end
  if not noctalia.mkdirAll(dir) then
    S.setStatus(noctalia.tr("status.mkdir_failed", { dir = dir }), true)
    R()
    return
  end
  local content = "data.location=" .. dir .. "\nconfirmation=no\nverbose=label\nrecurrence.confirmation=no\n"
  if not noctalia.writeFile(rc, content) then
    S.setStatus(noctalia.tr("status.write_failed", { rc = rc }), true)
    R()
    return
  end
  S.setStatus(noctalia.tr("status.initialized", { rc = rc }), false)
  noctalia.notify(noctalia.tr("title"), noctalia.tr("status.initialized", { rc = rc }))
  Ops.requestRefresh()
  Ops.fetchTasks()
end

return Ops
