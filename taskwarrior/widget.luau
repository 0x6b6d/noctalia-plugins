--!nonstrict
-- Bar widget: configurable Taskwarrior button. Every visible piece toggles
-- via widget settings; click targets pick which panel tab to open.

local tasklib = require("./lib/task.luau")

local function cfgStr(key, fallback)
  local v = noctalia.getConfig(key)
  if type(v) ~= "string" or v == "" then
    return fallback
  end
  return v
end

local function cfgBool(key, fallback)
  local v = noctalia.getConfig(key)
  if v == nil then
    return fallback
  end
  return v == true
end

local showGlyph = cfgBool("show_glyph", true)
local glyph = cfgStr("glyph", "checklist")
local showCount = cfgBool("show_count", true)
local showRefresh = cfgBool("show_refresh", true)
local useOverdueGlyph = cfgBool("use_overdue_glyph", true)
local overdueGlyph = cfgStr("overdue_glyph", "alert-triangle")
local showOverdue = cfgBool("show_overdue", false)
local showActive = cfgBool("show_active", false)
local showToday = cfgBool("show_today", false)
local showNextTask = cfgBool("show_next_task", false)
local highlightOverdue = cfgBool("highlight_overdue", true)
local hideWhenEmpty = cfgBool("hide_when_empty", false)
local showNextInTooltip = cfgBool("show_next_in_tooltip", true)

local clickTab = cfgStr("click_tab", "tasks")
if clickTab ~= "tasks" and clickTab ~= "add" then
  clickTab = "tasks"
end
local rightClickTab = cfgStr("right_click_tab", "add")
if rightClickTab ~= "tasks" and rightClickTab ~= "add" then
  rightClickTab = "add"
end

local settingFilter = noctalia.string.trim(cfgStr("project_filter", ""))

-- Tracking override from the panel's star (shared state + persisted file).
-- Beats the setting while active; cleared override reverts to the setting.
local trackOverride = { active = false, project = "" }
do
  local ok, dir = pcall(function()
    return noctalia.pluginDataDir()
  end)
  if ok and type(dir) == "string" and dir ~= "" then
    local raw = noctalia.readFile(dir .. "/tracked.json")
    if type(raw) == "string" and raw ~= "" then
      local ok2, val = pcall(function()
        return noctalia.json.decode(raw)
      end)
      if ok2 and type(val) == "table" and val["active"] == true then
        trackOverride = { active = true, project = tostring(val["project"] or "") }
      end
    end
  end
  local st = noctalia.state.get("trackOverride")
  if type(st) == "table" and st["active"] == true then
    trackOverride = { active = true, project = tostring(st["project"] or "") }
  end
end

local function effectiveProject()
  if trackOverride.active then
    return trackOverride.project, "override"
  end
  return settingFilter, "setting"
end

local badgeMode = cfgStr("badge_mode", "pending")

local tasks = noctalia.state.get("tasks")
if type(tasks) ~= "table" then
  tasks = {}
end
local backend = noctalia.state.get("backend")
if type(backend) ~= "table" then
  backend = { ok = true, error = "" }
end

local function scopedTasks()
  -- Project scoping with hierarchical rollup (Home matches Home.Kitchen).
  -- An unknown or empty project falls back to everything, flagged for
  -- the tooltip.
  local eff = effectiveProject()
  if eff == "" then
    return tasks, false
  end
  local out = {}
  for _, t in ipairs(tasks) do
    if tasklib.inProject(tostring(t["project"] or ""), eff) then
      table.insert(out, t)
    end
  end
  if #out == 0 then
    return tasks, true
  end
  return out, false
end

local function scopedMeta(list)
  return tasklib.computeMeta(list, {})
end

local function badgeCount(m)
  if badgeMode == "overdue" then
    return m["overdue"] or 0
  elseif badgeMode == "active" then
    return m["active"] or 0
  elseif badgeMode == "today" then
    return m["today"] or 0
  end
  return m["pending"] or 0
end

local function nextPending(list)
  local now = tasklib.nowUtcStr()
  local copy = {}
  for _, t in ipairs(list) do
    if (t["status"] or "pending") == "pending" and not tasklib.isWaiting(t, now) then
      table.insert(copy, t)
    end
  end
  tasklib.sortTasks(copy, "urgency")
  return copy[1]
end

local function countPill(count, alert)
  local fill = "secondary/0.25"
  local color = "secondary"
  if alert and highlightOverdue then
    fill = "error/0.25"
    color = "error"
  end
  return ui.row({ fill = fill, radius = 8, paddingH = 6, align = "center" }, {
    ui.label({ text = tostring(count), color = color, fontWeight = "bold" }),
  })
end

local function visibleCounts(m)
  -- Numeric values of every enabled part; drives hide_when_empty.
  local vals = {}
  if showCount then
    table.insert(vals, badgeCount(m))
  end
  if showActive then
    table.insert(vals, m["active"] or 0)
  end
  if showToday then
    table.insert(vals, m["today"] or 0)
  end
  if showOverdue then
    table.insert(vals, m["overdue"] or 0)
  end
  if #vals == 0 then
    table.insert(vals, m["pending"] or 0)
  end
  return vals
end

local function render()
  local list, fellBack = scopedTasks()
  local m = scopedMeta(list)
  local overdue = (m["overdue"] or 0) > 0
  local container = barWidget.isVertical() and ui.column or ui.row

  if hideWhenEmpty and backend["ok"] ~= false then
    local empty = true
    for _, v in ipairs(visibleCounts(m)) do
      if v > 0 then
        empty = false
      end
    end
    if empty then
      barWidget.setVisible(false)
      return
    end
  end
  barWidget.setVisible(true)

  local children = {}

  if backend["ok"] == false then
    if showGlyph then
      table.insert(children, ui.glyph({ name = "alert-triangle", size = 14, color = "error" }))
    end
    if showCount then
      table.insert(children, countPill("!", true))
    end
    if #children == 0 then
      barWidget.setVisible(false)
      return
    end
    barWidget.render(container({ gap = 6, align = "center" }, children))
    barWidget.setTooltip(noctalia.tr("widget.backend_error", { error = tostring(backend["error"] or "not configured") }))
    return
  end

  if showGlyph then
    local gname = glyph
    local gcolor = "secondary"
    if overdue then
      if useOverdueGlyph then
        gname = overdueGlyph
      end
      if highlightOverdue then
        gcolor = "error"
      end
    end
    table.insert(children, ui.glyph({ name = gname, size = 14, color = gcolor }))
  end

  if showCount then
    table.insert(children, countPill(badgeCount(m), overdue))
  end
  if showActive then
    table.insert(children, countPill(m["active"] or 0, false))
  end
  if showToday then
    table.insert(children, countPill(m["today"] or 0, false))
  end
  if showOverdue and overdue then
    table.insert(children, countPill(m["overdue"] or 0, true))
  end
  if showNextTask then
    local nxt = nextPending(list)
    if nxt ~= nil then
      table.insert(children, ui.label({ text = tostring(nxt["description"] or ""), maxWidth = 180, maxLines = 1 }))
    end
  end
  -- Overdue dot only when the overdue pill is off: same signal, no duplication.
  if overdue and not showOverdue then
    table.insert(children, ui.box({ width = 8, height = 8, radius = 4, fill = "error" }))
  end

  if showRefresh then
    table.insert(children, ui.button({
      key = "tw-refresh",
      glyph = "refresh",
      glyphSize = 12,
      variant = "ghost",
      tooltip = noctalia.tr("widget.refresh"),
      onClick = function()
        noctalia.state.set("refreshReq", noctalia.nowMs())
      end,
    }))
  end

  if #children == 0 then
    barWidget.setVisible(false)
    return
  end

  barWidget.render(container({ gap = 6, align = "center" }, children))

  local rows = {
    { key = noctalia.tr("widget.pending"), value = tostring(m["pending"] or 0) },
    { key = noctalia.tr("widget.overdue"), value = tostring(m["overdue"] or 0) },
    { key = noctalia.tr("widget.due_today"), value = tostring(m["today"] or 0) },
    { key = noctalia.tr("widget.waiting"), value = tostring(m["waiting"] or 0) },
  }
  if settingFilter ~= "" or trackOverride.active then
    local eff, via = effectiveProject()
    if eff ~= "" then
      if fellBack then
        table.insert(rows, 1, { key = noctalia.tr("widget.project"), value = noctalia.tr("widget.not_found", { name = eff }) })
      elseif via == "override" then
        table.insert(rows, 1, { key = noctalia.tr("widget.tracking"), value = eff })
      else
        table.insert(rows, 1, { key = noctalia.tr("widget.project"), value = eff })
      end
    end
  end
  if showNextInTooltip then
    local nxt = nextPending(list)
    if nxt ~= nil then
      local dueTxt = ""
      if type(nxt["due"]) == "string" then
        dueTxt = noctalia.tr("widget.next_due", { due = tasklib.formatDue(nxt["due"]) })
      end
      table.insert(rows, { key = noctalia.tr("widget.next"), value = tostring(nxt["description"] or "") .. dueTxt })
    end
  end
  barWidget.setTooltip(rows)
end

noctalia.state.watch("tasks", function(value)
  if type(value) == "table" then
    tasks = value
  else
    tasks = {}
  end
  render()
end)

noctalia.state.watch("backend", function(value)
  if type(value) == "table" then
    backend = value
  end
  render()
end)

noctalia.state.watch("trackOverride", function(value)
  if type(value) == "table" and value["active"] == true then
    trackOverride = { active = true, project = tostring(value["project"] or "") }
  else
    trackOverride = { active = false, project = "" }
  end
  render()
end)

function update()
  noctalia.setUpdateInterval(5000)
  render()
end

function onClick()
  noctalia.state.set("activeTab", clickTab)
  noctalia.togglePanel("kurai/taskwarrior:tasks")
end

-- Offline testing / scripting surface:
--   noctalia msg plugin kurai/taskwarrior:bar focused refresh
function onIpc(event, _payload)
  if event == "refresh" then
    noctalia.state.set("refreshReq", noctalia.nowMs())
  end
end

function onRightClick()
  noctalia.state.set("activeTab", rightClickTab)
  noctalia.togglePanel("kurai/taskwarrior:tasks")
end

function onScroll(axis, _steps, startsGesture)
  if axis ~= "vertical" or not startsGesture then
    return
  end
  -- Cycle the count source on scroll for quick triage views.
  if badgeMode == "pending" then
    badgeMode = "overdue"
  elseif badgeMode == "overdue" then
    badgeMode = "active"
  elseif badgeMode == "active" then
    badgeMode = "today"
  else
    badgeMode = "pending"
  end
  render()
end
