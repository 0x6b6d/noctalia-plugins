--!nonstrict
-- Small shared view primitives for the panel tabs. The future styling pass
-- lives here: one place for section headers, tab bars, footers and cards.
--
-- Layout discipline: EVERY container sets align/justify explicitly and
-- carries a key. The host retains native controls across renders and only
-- documented props reset on drop - an absent align can otherwise leak from
-- whatever tree rendered before (e.g. a centered column poisoning the next
-- tab). Explicit defaults cost nothing and make each tree self-describing.

local tasklib = require("./task.luau")

local UI = {}

function UI.section(title, control)
  return ui.column({ gap = 8, align = "stretch" }, {
    ui.label({ text = title, fontWeight = "medium", color = "on_surface_variant" }),
    control,
  })
end

-- Subtle grouping surface for things that belong together (filter blocks,
-- forms, setup steps). Keyed per instance so the host never confuses two
-- cards across tab switches.
function UI.card(key, children)
  return ui.column({ key = key, gap = 10, padding = 10, radius = 12, fill = "surface_variant/0.15", align = "stretch" }, children)
end

-- Small status badge. Semantic colors only so it tracks the theme.
function UI.pill(key, text, color, bold)
  local c = color or "on_surface_variant"
  local fill = "surface_variant/0.3"
  if c == "error" then
    fill = "error/0.2"
  elseif c == "primary" then
    fill = "primary/0.2"
  elseif c == "secondary" then
    fill = "secondary/0.2"
  end
  return ui.row({ key = key, fill = fill, radius = 6, paddingH = 6, paddingV = 2, align = "center", justify = "start" }, {
    ui.label({ text = text, fontSize = 11, color = c, fontWeight = bold and "bold" or nil }),
  })
end

function UI.emptyState(key, glyph, title, hint)
  return ui.column({ key = key, gap = 8, align = "center", justify = "start", padding = 16 }, {
    ui.glyph({ name = glyph, size = 28, color = "on_surface_variant" }),
    ui.label({ text = title, fontWeight = "bold" }),
    ui.label({ text = hint, fontSize = 12, color = "on_surface_variant" }),
  })
end

local function tabSuffix(S, id)
  if id == "tasks" then
    local p = S.meta["pending"] or 0
    if p > 0 then
      return " (" .. tostring(p) .. ")"
    end
  elseif id == "projects" then
    local names = tasklib.collectProjects(S.tasks)
    if #names > 0 then
      return " (" .. tostring(#names) .. ")"
    end
  elseif id == "tags" then
    local names = tasklib.collectTags(S.tasks)
    if #names > 0 then
      return " (" .. tostring(#names) .. ")"
    end
  end
  return ""
end

local TAB_GLYPHS = {
  tasks = "list",
  add = "plus",
  edit = "pencil",
  projects = "folder",
  tags = "tags",
  stats = "chart-bar",
}

-- Translation keys per tab id (explicit map: no dynamic key building, so
-- key coverage stays statically checkable).
local TAB_NAMES = {
  tasks = "tabs.tasks",
  add = "tabs.add",
  edit = "tabs.edit",
  projects = "tabs.projects",
  tags = "tabs.tags",
  stats = "tabs.stats",
}

function UI.tabRail(S, onSwitch)
  local btns = {}
  for i, id in ipairs(S.TABS) do
    local lid = id
    table.insert(btns, ui.button({
      key = "tab-" .. lid,
      glyph = TAB_GLYPHS[lid] or "dots",
      glyphSize = 16,
      width = 40,
      variant = "ghost",
      selected = S.activeTab == lid,
      tooltip = noctalia.tr(TAB_NAMES[lid] or "tabs.tasks") .. tabSuffix(S, lid),
      onClick = function()
        onSwitch(lid)
      end,
    }))
  end
  return ui.column({
    key = "nav-rail",
    gap = 4,
    padding = 8,
    radius = 16,
    fill = "primary/0.18",
    align = "center",
    justify = "start",
  }, btns)
end

function UI.footer(S)
  return ui.row({ gap = 8, align = "center", justify = "start" }, {
    ui.label({
      text = S.statusMsg ~= "" and S.statusMsg or ("synced " .. tostring(S.meta["pending"] or 0) .. " pending"),
      fontSize = 12,
      color = S.statusErr and "error" or "on_surface_variant",
      flexGrow = 1,
    }),
  })
end

function UI.statCard(value, label, color)
  return ui.column({ gap = 4, flexGrow = 1, padding = 8, radius = 10, fill = "surface_variant/0.25", align = "stretch", justify = "start" }, {
    ui.label({ text = tostring(value), fontSize = 20, fontWeight = "bold", color = color }),
    ui.label({ text = label, fontSize = 12, color = "on_surface_variant" }),
  })
end

return UI
