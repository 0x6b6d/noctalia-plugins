--!nonstrict
-- Stats tab: scoped headline counts, 14-day completion graph (burndown
-- precursor), waiting/due-today cards, oldest pending, plus Sync / Undo.

local tasklib = require("../task.luau")
local S = require("../panel_state.luau")
local Ops = require("../panel_ops.luau")
local UI = require("../panel_ui.luau")

local T = {}

function T.render()
  local names = tasklib.collectAllProjects(S.tasks, S.completedFull)
  local opts = { noctalia.tr("common.all_projects") }
  for _, p in ipairs(names) do
    table.insert(opts, p)
  end
  local scopeIdx = 0
  for i, p in ipairs(names) do
    if p == S.statsProject then
      scopeIdx = i
    end
  end

  local st = tasklib.projectStats(S.tasks, S.completed, S.statsProject)
  local m = st.meta
  local oldestTxt = noctalia.tr("stats.oldest_none")
  if st.oldest ~= nil then
    oldestTxt = tostring(st.oldest["description"] or "")
    if st.oldestAgeDays ~= nil then
      oldestTxt = noctalia.tr("stats.oldest_age", { desc = oldestTxt, age = tostring(st.oldestAgeDays) })
    end
  end

  return ui.column({ flexGrow = 1, gap = 12, align = "stretch", justify = "start" }, {
    ui.select({
      key = "stats-scope",
      options = opts,
      selectedIndex = scopeIdx,
      onChange = function(index, text)
        if (tonumber(index) or 0) == 0 then
          S.statsProject = ""
        else
          S.statsProject = text or ""
        end
        Ops.rerender()
      end,
    }),
    ui.row({ gap = 8, align = "stretch", justify = "start" }, {
      UI.statCard(m["pending"] or 0, noctalia.tr("stats.pending")),
      UI.statCard(m["overdue"] or 0, noctalia.tr("stats.overdue"), "error"),
      UI.statCard(m["active"] or 0, noctalia.tr("stats.active")),
      UI.statCard(m["completed"] or 0, noctalia.tr("stats.done")),
    }),
    ui.row({ gap = 8, align = "stretch", justify = "start" }, {
      UI.statCard(m["waiting"] or 0, noctalia.tr("stats.waiting")),
      UI.statCard(m["today"] or 0, noctalia.tr("stats.due_today")),
    }),
    UI.section(noctalia.tr("stats.graph_title"), ui.graph({ values = st.vals, height = 90, color = "primary" })),
    UI.section(noctalia.tr("stats.oldest"), ui.label({ text = oldestTxt })),
    ui.row({ gap = 8, align = "center", justify = "start" }, {
      ui.button({
        key = "stats-sync",
        text = noctalia.tr("stats.sync"),
        variant = "outline",
        controlSize = "sm",
        onClick = function()
          Ops.doSync()
        end,
      }),
      ui.button({
        key = "stats-undo",
        text = noctalia.tr("stats.undo"),
        variant = "ghost",
        controlSize = "sm",
        tooltip = noctalia.tr("stats.undo_tooltip"),
        onClick = function()
          Ops.doUndo()
        end,
      }),
    }),
  })
end

return T
