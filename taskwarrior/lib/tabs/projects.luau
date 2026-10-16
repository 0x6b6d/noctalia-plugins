--!nonstrict
-- Projects tab: per-project open/done counts with progress. Filter jumps
-- back to the Tasks tab with the project preset; the star tracks the
-- project in the bar widget (runtime override, persisted).

local tasklib = require("../task.luau")
local S = require("../panel_state.luau")
local Ops = require("../panel_ops.luau")
local UI = require("../panel_ui.luau")

local T = {}

local function toggleTrack(name)
  local proj, src = Ops.trackingStatus()
  if proj ~= name then
    Ops.setOverride(name)
    if name == "" then
      S.setStatus(noctalia.tr("projects.track_set_all"), false)
    else
      S.setStatus(noctalia.tr("projects.track_set", { name = name }), false)
    end
    Ops.rerender()
    return
  end
  if src == "override" then
    Ops.clearOverride()
    S.setStatus(noctalia.tr("projects.track_reverted"), false)
    Ops.rerender()
    return
  end
  noctalia.notify(noctalia.tr("title"), noctalia.tr("projects.track_pinned"))
end

function T.render()
  local tracked, src = Ops.trackingStatus()
  local trackLabel = noctalia.tr("projects.tracking_all")
  if tracked ~= "" then
    if src == "setting" then
      trackLabel = noctalia.tr("projects.tracking_settings", { name = tracked })
    else
      trackLabel = noctalia.tr("projects.tracking", { name = tracked })
    end
  end

  local names, counts = tasklib.collectProjects(S.tasks)
  local rows = {
    ui.row({ key = "projrow-all", gap = 8, align = "center", justify = "start" }, {
      ui.button({
        key = "trackrow-all",
        glyph = (tracked == "" and src == "override") and "star-filled" or "star",
        glyphSize = 14,
        variant = "ghost",
        tooltip = noctalia.tr("projects.track_all_tooltip"),
        onClick = function()
          toggleTrack("")
        end,
      }),
      ui.label({ text = noctalia.tr("common.all_projects"), fontWeight = "bold", flexGrow = 1 }),
    }),
  }
  if #names == 0 then
    table.insert(rows, UI.emptyState("projects-empty", "folder", noctalia.tr("projects.empty_title"), noctalia.tr("projects.empty_hint")))
  end
  for _, name in ipairs(names) do
    local nm = name
    local pending = counts[nm] or 0
    local done = 0
    for _, t in ipairs(S.completedFull) do
      if tasklib.inProject(tostring(t["project"] or ""), nm) then
        done += 1
      end
    end
    local total = pending + done
    local prog = 0
    if total > 0 then
      prog = done / total
    end
    local isTracked = tracked == nm
    table.insert(rows, ui.column({ key = "proj-" .. nm, gap = 6, padding = 8, radius = 10, fill = "surface_variant/0.25", align = "stretch", justify = "start" }, {
      ui.row({ gap = 8, align = "center", justify = "start" }, {
        ui.button({
          key = "track-" .. nm,
          glyph = isTracked and "star-filled" or "star",
          glyphSize = 14,
          variant = "ghost",
          tooltip = isTracked and noctalia.tr("projects.tracked_tooltip") or noctalia.tr("projects.track_tooltip"),
          onClick = function()
            toggleTrack(nm)
          end,
        }),
        ui.label({ text = nm, fontWeight = "bold", flexGrow = 1 }),
        ui.label({ text = noctalia.tr("projects.counts", { open = tostring(pending), done = tostring(done) }), fontSize = 12, color = "on_surface_variant" }),
        ui.button({
          key = "proj-filter-" .. nm,
          text = noctalia.tr("common.filter"),
          variant = "ghost",
          controlSize = "sm",
          tooltip = noctalia.tr("projects.filter_tooltip"),
          onClick = function()
            S.filter.project = nm
            S.gotoTab("tasks")
            Ops.rerender()
          end,
        }),
      }),
      ui.progress({ progress = prog }),
    }))
  end
  return ui.column({ flexGrow = 1, gap = 10, align = "stretch", justify = "start" }, {
    ui.label({ text = trackLabel, fontSize = 12, color = "primary" }),
    ui.label({ text = noctalia.trp("projects.count", #names), color = "on_surface_variant" }),
    ui.scroll({ key = "projects-list-scroll", flexGrow = 1, gap = 8, align = "stretch" }, rows),
  })
end

return T
