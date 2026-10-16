--!nonstrict
-- Tasks tab: filterable/sortable list (pending/waiting/completed/all).
-- Row tap opens the Edit tab; dots toggle inline Start/Done/Delete;
-- check completes. Notes show as a pill, in full when expanded.

local tasklib = require("../task.luau")
local S = require("../panel_state.luau")
local Ops = require("../panel_ops.luau")
local UI = require("../panel_ui.luau")

local T = {}

local function taskRow(t)
  local uuid = tostring(t["uuid"] or "")
  local desc = tostring(t["description"] or "(no description)")
  local due = t["due"]
  local pri = t["priority"]
  local now = tasklib.nowUtcStr()
  local dotColor = "outline"
  if tasklib.isOverdue(t, now) then
    dotColor = "error"
  elseif tasklib.isDueToday(t, now) then
    dotColor = "primary"
  elseif pri == "H" then
    dotColor = "error/0.6"
  end
  -- Second row: project + pills, glanceable without reading.
  local metaRow = {
    ui.label({ text = tasklib.shortUuid(uuid), fontSize = 11, color = "on_surface_variant" }),
  }
  if t["project"] ~= nil then
    table.insert(metaRow, ui.label({ text = tostring(t["project"]), fontSize = 11, color = "on_surface_variant", flexGrow = 1 }))
  else
    table.insert(metaRow, ui.spacer({ flexGrow = 1 }))
  end
  if pri == "H" then
    table.insert(metaRow, UI.pill("pill-" .. uuid .. "-pri", noctalia.tr("tasks.pri_high"), "error", true))
  elseif pri == "M" then
    table.insert(metaRow, UI.pill("pill-" .. uuid .. "-pri", noctalia.tr("tasks.pri_medium"), "secondary", false))
  elseif pri == "L" then
    table.insert(metaRow, UI.pill("pill-" .. uuid .. "-pri", noctalia.tr("tasks.pri_low"), nil, false))
  end
  if type(due) == "string" then
    if tasklib.isOverdue(t, now) then
      table.insert(metaRow, UI.pill("pill-" .. uuid .. "-due",
        noctalia.tr("tasks.due_overdue", { date = tasklib.formatDue(due) }), "error", true))
    elseif tasklib.isDueToday(t, now) then
      table.insert(metaRow, UI.pill("pill-" .. uuid .. "-due",
        noctalia.tr("tasks.due_today", { date = tasklib.formatDue(due) }), "primary", true))
    else
      table.insert(metaRow, UI.pill("pill-" .. uuid .. "-due", tasklib.formatDue(due), nil, false))
    end
  end
  if t["start"] ~= nil then
    table.insert(metaRow, ui.glyph({ name = "player-play", size = 12, color = "primary" }))
  end
  local anns0 = t["annotations"]
  local noteCount = (type(anns0) == "table") and #anns0 or 0
  if noteCount > 0 then
    table.insert(metaRow, UI.pill(
      "pill-" .. uuid .. "-notes",
      noctalia.trp("tasks.notes", noteCount),
      nil,
      false
    ))
  end
  local selected = S.selectedUuid == uuid
  local expanded = S.expandedMenuUuid == uuid
  local started = t["start"] ~= nil
  local textCol = {
    ui.row({ gap = 8, align = "center", justify = "start" }, {
      ui.box({ width = 8, height = 8, radius = 4, fill = dotColor }),
      ui.label({ text = desc, flexGrow = 1, maxLines = 2 }),
    }),
    ui.row({ gap = 6, align = "center", justify = "start" }, metaRow),
  }
  if expanded then
    local anns = t["annotations"]
    if type(anns) == "table" and #anns > 0 then
      for _, a in ipairs(anns) do
        table.insert(textCol, ui.label({
          text = "• " .. tostring(a["description"] or ""),
          fontSize = 11,
          color = "on_surface_variant",
          maxLines = 2,
        }))
      end
    end
    local tst = t["status"] or "pending"
    local actionBtns = {}
    if tst == "pending" or tst == "waiting" then
      table.insert(actionBtns, ui.button({
        key = "act-start-" .. uuid,
        text = started and noctalia.tr("tasks.stop") or noctalia.tr("tasks.start"),
        variant = "outline",
        controlSize = "sm",
        onClick = function()
          Ops.doToggleStart(uuid)
        end,
      }))
    end
    if tst ~= "completed" then
      table.insert(actionBtns, ui.button({
        key = "act-done-" .. uuid,
        text = noctalia.tr("tasks.done"),
        variant = "primary",
        controlSize = "sm",
        onClick = function()
          Ops.doDone(uuid)
        end,
      }))
    end
    if #actionBtns > 0 then
      table.insert(textCol, ui.row({ gap = 8, align = "center", justify = "start" }, actionBtns))
    end
  end
  return ui.row({
    key = "task-" .. uuid,
    gap = 8,
    padding = 8,
    radius = 10,
    fill = selected and "primary/0.15" or "surface_variant/0.25",
    align = "center",
    justify = "start",
    onClick = function()
      Ops.openEditor(uuid)
    end,
  }, {
    ui.column({ gap = 2, flexGrow = 1, align = "stretch", justify = "start" }, textCol),
    ui.button({
      key = "menu-" .. uuid,
      glyph = expanded and "chevron-up" or "dots",
      glyphSize = 16,
      variant = "ghost",
      tooltip = noctalia.tr("tasks.actions"),
      onClick = function()
        if S.expandedMenuUuid == uuid then
          S.expandedMenuUuid = ""
        else
          S.expandedMenuUuid = uuid
        end
        Ops.rerender()
      end,
    }),
    ui.button({
      key = "done-" .. uuid,
      glyph = "check",
      glyphSize = 16,
      variant = "ghost",
      tooltip = noctalia.tr("tasks.mark_done"),
      onClick = function()
        Ops.doDone(uuid)
      end,
    }),
  })
end

function T.render()
  -- Completed tasks live apart: filter that list for Completed, merge both
  -- for All (show_completed), pending/waiting otherwise.
  local source = S.tasks
  if S.filter.status == "completed" then
    source = S.completedFull
  elseif S.filter.status == "all" then
    source = {}
    for _, t in ipairs(S.tasks) do
      table.insert(source, t)
    end
    for _, t in ipairs(S.completedFull) do
      table.insert(source, t)
    end
  end
  local filtered = tasklib.sortTasks(tasklib.filterTasks(source, S.filter), S.filter.sort)
  local rows = {}
  for _, t in ipairs(filtered) do
    table.insert(rows, taskRow(t))
  end
  if #rows == 0 then
    rows = { UI.emptyState("tasks-empty", "inbox", noctalia.tr("tasks.empty_title"), noctalia.tr("tasks.empty_hint")) }
  end

  local projectNames = tasklib.collectAllProjects(S.tasks, S.completedFull)
  local projectOpts = { noctalia.tr("common.all_projects") }
  for _, p in ipairs(projectNames) do
    table.insert(projectOpts, p)
  end
  local projectIdx = 0
  for i, p in ipairs(projectNames) do
    if p == S.filter.project then
      projectIdx = i
    end
  end

  local filters = {
    ui.input({
      key = "search-" .. tostring(S.searchKey),
      value = S.filter.q,
      placeholder = noctalia.tr("tasks.search_placeholder"),
      focus = S.searchFocus,
      controlSize = "sm",
      onChange = function(value)
        S.filter.q = value or ""
        Ops.rerender()
      end,
    }),
    ui.row({ gap = 8, align = "stretch", justify = "start" }, {
      ui.column({ gap = 0, flexGrow = 1, align = "stretch", justify = "start" }, {
        ui.select({
          key = "tasks-status",
          options = S.statusOpts(),
          selectedIndex = S.statusIdx,
          controlSize = "sm",
          onChange = function(index)
            S.statusIdx = tonumber(index) or 0
            S.filter.status = S.STATUS_VALS[S.statusIdx + 1] or "pending"
            Ops.rerender()
          end,
        }),
      }),
      ui.column({ gap = 0, flexGrow = 1, align = "stretch", justify = "start" }, {
        ui.select({
          key = "tasks-sort",
          options = S.sortOpts(),
          selectedIndex = S.sortIdx,
          controlSize = "sm",
          onChange = function(index)
            S.sortIdx = tonumber(index) or 0
            S.filter.sort = S.SORT_VALS[S.sortIdx + 1] or "urgency"
            Ops.rerender()
          end,
        }),
      }),
    }),
    ui.row({ gap = 8, align = "stretch", justify = "start" }, {
      ui.column({ gap = 0, flexGrow = 1, align = "stretch", justify = "start" }, {
        ui.select({
          key = "tasks-due",
          options = S.dueOpts(),
          selectedIndex = S.dueIdx,
          controlSize = "sm",
          onChange = function(index)
            S.dueIdx = tonumber(index) or 0
            S.filter.due = S.DUE_VALS[S.dueIdx + 1] or "all"
            Ops.rerender()
          end,
        }),
      }),
      ui.column({ gap = 0, flexGrow = 1, align = "stretch", justify = "start" }, {
        ui.select({
          key = "tasks-pri",
          options = S.priOpts(),
          selectedIndex = S.priIdx,
          controlSize = "sm",
          onChange = function(index)
            S.priIdx = tonumber(index) or 0
            S.filter.pri = S.PRI_VALS[S.priIdx + 1] or ""
            Ops.rerender()
          end,
        }),
      }),
    }),
    ui.select({
      key = "tasks-project",
      options = projectOpts,
      selectedIndex = projectIdx,
      controlSize = "sm",
      onChange = function(index, text)
        if (tonumber(index) or 0) == 0 then
          S.filter.project = ""
        else
          S.filter.project = text or ""
        end
        Ops.rerender()
      end,
    }),
  }
  if S.filter.tag ~= "" or S.filter.project ~= "" then
    local active = noctalia.tr("tasks.filters_label")
    if S.filter.project ~= "" then
      active = active .. " project=" .. S.filter.project
    end
    if S.filter.tag ~= "" then
      active = active .. " tag=" .. S.filter.tag
    end
    table.insert(filters, ui.row({ gap = 8, align = "center", justify = "start" }, {
      ui.label({ text = active, fontSize = 12, color = "on_surface_variant", flexGrow = 1 }),
      ui.button({
        key = "tasks-clear",
        text = noctalia.tr("common.clear"),
        variant = "ghost",
        controlSize = "sm",
        onClick = function()
          S.clearFilters()
          Ops.rerender()
        end,
      }),
    }))
  end
  local body = { UI.card("tasks-filters-card", filters) }
  table.insert(body, ui.label({
    text = noctalia.tr("tasks.count_line", {
      shown = tostring(#filtered),
      pending = tostring(S.meta["pending"] or 0),
      overdue = tostring(S.meta["overdue"] or 0),
    }),
    fontSize = 12,
    color = "on_surface_variant",
  }))
  table.insert(body, ui.scroll({ key = "tasks-list-scroll", flexGrow = 1, gap = 6, align = "stretch" }, rows))
  return ui.column({ flexGrow = 1, gap = 10, align = "stretch", justify = "start" }, body)
end

return T
