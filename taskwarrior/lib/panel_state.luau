--!nonstrict
-- Shared mutable state for the tabbed panel entry. Every module in this
-- entry requires this file and gets the SAME table instance (per-entry
-- module cache), so tabs and ops coordinate without globals.

local S = {}

-- Option tables (also the settings-GUI vocabulary for future use).
S.TABS = { "tasks", "add", "edit", "projects", "tags", "stats" }
-- Option VALUES (order matches the translated option labels built at
-- render time; indices stored below must stay aligned with both).
S.STATUS_VALS = { "pending", "waiting", "completed", "all" }
S.SORT_VALS = { "urgency", "due", "entry", "priority" }
S.PRI_VALS = { "", "H", "M", "L", "none" }
S.DUE_VALS = { "all", "overdue", "today", "week", "nodue" }

function S.statusOpts()
  return {
    noctalia.tr("filter.status.pending"),
    noctalia.tr("filter.status.waiting"),
    noctalia.tr("filter.status.completed"),
    noctalia.tr("filter.status.all"),
  }
end

function S.sortOpts()
  return {
    noctalia.tr("filter.sort.urgency"),
    noctalia.tr("filter.sort.due"),
    noctalia.tr("filter.sort.created"),
    noctalia.tr("filter.sort.priority"),
  }
end

function S.priOpts()
  return {
    noctalia.tr("filter.pri.all"),
    noctalia.tr("filter.pri.high"),
    noctalia.tr("filter.pri.medium"),
    noctalia.tr("filter.pri.low"),
    noctalia.tr("filter.pri.none"),
  }
end

function S.dueOpts()
  return {
    noctalia.tr("filter.due.all"),
    noctalia.tr("filter.due.overdue"),
    noctalia.tr("filter.due.today"),
    noctalia.tr("filter.due.week"),
    noctalia.tr("filter.due.nodue"),
  }
end

function S.detailPriOpts()
  return {
    noctalia.tr("filter.detail_pri.none"),
    noctalia.tr("filter.detail_pri.high"),
    noctalia.tr("filter.detail_pri.medium"),
    noctalia.tr("filter.detail_pri.low"),
  }
end

-- Config (re-read via reloadConfig when the panel opens).
S.bin = "task"
S.rcPath = ""
S.showCompletedDefault = false

function S.reloadConfig()
  local bin = noctalia.getConfig("task_bin")
  if type(bin) == "string" and bin ~= "" then
    S.bin = bin
  end
  local rc = noctalia.getConfig("taskrc_path")
  if type(rc) == "string" then
    S.rcPath = rc
  end
  S.showCompletedDefault = noctalia.getConfig("show_completed") == true
end

S.reloadConfig()

-- Synced data (mirrors of noctalia.state, owned by service + panel fetch).
S.tasks = {}
S.completed = {}
S.completedFull = {}
S.meta = { pending = 0, waiting = 0, overdue = 0, today = 0, active = 0, completed = 0 }
S.backend = { ok = true, error = "" }

do
  local t = noctalia.state.get("tasks")
  if type(t) == "table" then
    S.tasks = t
  end
  local c = noctalia.state.get("completed")
  if type(c) == "table" then
    S.completed = c
  end
  local m = noctalia.state.get("meta")
  if type(m) == "table" then
    S.meta = m
  end
  local b = noctalia.state.get("backend")
  if type(b) == "table" then
    S.backend = b
  end
end

-- UI state.
S.activeTab = "tasks"
S.filter = {
  q = "",
  status = S.showCompletedDefault and "all" or "pending",
  project = "",
  tag = "",
  pri = "",
  due = "all",
  sort = "urgency",
}
S.statusIdx = 0
S.sortIdx = 0
S.priIdx = 0
S.dueIdx = 0
do
  for i, v in ipairs(S.STATUS_VALS) do
    if v == S.filter.status then
      S.statusIdx = i - 1
    end
  end
end

S.selectedUuid = ""
S.expandedMenuUuid = ""
S.deleteArmedAt = nil
S.statsProject = ""
S.detail = { desc = "", project = "", due = "", scheduled = "", wait = "", tags = "", priIdx = 0 }
S.detailOrig = { desc = "", project = "", due = "", scheduled = "", wait = "", tags = "", priIdx = 0 }
S.detailKey = 0
S.addForm = { desc = "", project = "", due = "", scheduled = "", wait = "", tags = "", priIdx = 0, note = "" }
S.addKey = 0
S.noteText = ""
S.noteKey = 0
S.searchKey = 0
S.searchFocus = false
S.setupDir = ""
S.setupKey = 0
S.statusMsg = ""
S.statusErr = false
S.closeButton = true
S.busy = false

function S.setStatus(msg, isErr)
  S.statusMsg = msg or ""
  S.statusErr = isErr == true
end

function S.gotoTab(id)
  S.activeTab = id
  S.searchFocus = false
  noctalia.state.set("activeTab", id)
end

function S.syncTabFromState()
  local want = noctalia.state.get("activeTab")
  if type(want) ~= "string" then
    return
  end
  for _, id in ipairs(S.TABS) do
    if id == want then
      S.activeTab = want
      return
    end
  end
end

function S.clearFilters()
  S.filter.q = ""
  S.filter.project = ""
  S.filter.tag = ""
  S.filter.pri = ""
  S.filter.due = "all"
  S.priIdx = 0
  S.dueIdx = 0
  S.searchKey += 1
end

return S
