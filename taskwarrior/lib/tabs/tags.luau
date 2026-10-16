--!nonstrict
-- Tags tab: tag chips with counts. Tapping filters Tasks; tapping again
-- clears.

local tasklib = require("../task.luau")
local S = require("../panel_state.luau")
local Ops = require("../panel_ops.luau")
local UI = require("../panel_ui.luau")

local T = {}

function T.render()
  local names, counts = tasklib.collectTags(S.tasks)
  local chips = {}
  if #names == 0 then
    chips = { UI.emptyState("tags-empty", "tags", noctalia.tr("tags.empty_title"), noctalia.tr("tags.empty_hint")) }
  end
  for _, name in ipairs(names) do
    local nm = name
    local cnt = counts[nm] or 0
    table.insert(chips, ui.button({
      key = "tag-" .. nm,
      text = nm .. " (" .. tostring(cnt) .. ")",
      variant = "outline",
      selected = S.filter.tag == nm,
      controlSize = "sm",
      onClick = function()
        if S.filter.tag == nm then
          S.filter.tag = ""
        else
          S.filter.tag = nm
        end
        S.gotoTab("tasks")
        Ops.rerender()
      end,
    }))
  end
  return ui.column({ flexGrow = 1, gap = 10, align = "stretch", justify = "start" }, {
    ui.label({ text = noctalia.tr("tags.hint"), color = "on_surface_variant" }),
    ui.scroll({ key = "tags-list-scroll", flexGrow = 1, gap = 8, align = "stretch" }, {
      ui.column({ gap = 8, align = "stretch", justify = "start" }, chips),
    }),
  })
end

return T
