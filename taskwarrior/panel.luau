--!nonstrict
-- Tabbed Taskwarrior panel entry (thin orchestrator).
-- State lives in lib/panel_state.luau, task I/O in lib/panel_ops.luau,
-- shared primitives in lib/panel_ui.luau, one module per tab in lib/tabs/.
-- Mutations go through `task <uuid> ...` (stable UUIDs).

local S = require("./lib/panel_state.luau")
local Ops = require("./lib/panel_ops.luau")
local UI = require("./lib/panel_ui.luau")

local Tabs = {
  tasks = require("./lib/tabs/tasks.luau"),
  add = require("./lib/tabs/add.luau"),
  edit = require("./lib/tabs/edit.luau"),
  projects = require("./lib/tabs/projects.luau"),
  tags = require("./lib/tabs/tags.luau"),
  stats = require("./lib/tabs/stats.luau"),
  setup = require("./lib/tabs/setup.luau"),
}

local function render()
  local header = {
    ui.label({ text = noctalia.tr("title"), fontSize = 16, fontWeight = "bold", flexGrow = 1 }),
    ui.button({
      key = "hdr-refresh",
      glyph = "refresh",
      tooltip = "Refresh",
      onClick = function()
        Ops.requestRefresh()
        Ops.fetchTasks()
      end,
    }),
  }
  if S.closeButton then
    table.insert(header, ui.button({
      key = "hdr-close",
      glyph = "close",
      onClick = function()
        panel.close()
      end,
    }))
  end
  local body
  if S.backend["ok"] == false then
    if S.backend["setup"] then
      body = Tabs.setup.render()
    else
      body = Tabs.setup.error()
    end
  elseif S.activeTab == "add" then
    body = Tabs.add.render()
  elseif S.activeTab == "edit" then
    body = Tabs.edit.render()
  elseif S.activeTab == "projects" then
    body = Tabs.projects.render()
  elseif S.activeTab == "tags" then
    body = Tabs.tags.render()
  elseif S.activeTab == "stats" then
    body = Tabs.stats.render()
  else
    body = Tabs.tasks.render()
  end
  panel.render(ui.column({ flexGrow = 1, gap = 12, align = "stretch", justify = "start" }, {
    ui.row({ align = "center", justify = "space_between", gap = 8 }, header),
    ui.row({ gap = 12, flexGrow = 1, align = "stretch", justify = "start" }, {
      UI.tabRail(S, function(id)
        S.gotoTab(id)
        Ops.rerender()
      end),
      body,
    }),
    UI.footer(S),
  }))
end

Ops.bind(render)

function onOpen(_context)
  S.closeButton = noctalia.getSetting("shell.show_close_buttons") ~= false
  S.syncTabFromState()
  S.reloadConfig()
  noctalia.setUpdateInterval(1000)
  Ops.syncOverrideFromFile()
  Ops.fetchTasks()
  render()
end

function onClose()
  S.searchFocus = false
end

function update()
  -- Expire a Delete arm; ticks only run while the panel is open.
  if S.deleteArmedAt ~= nil and os.time() - S.deleteArmedAt > 8 then
    S.deleteArmedAt = nil
    render()
  end
end

function onKey(chord, pressed)
  local down = pressed == true or pressed == "true" or pressed == 1 or pressed == "1"
  if not down then
    return
  end
  if chord == "ctrl+n" then
    S.gotoTab("add")
    render()
  end
end

-- Scripting surface: switch tabs without opening the panel, e.g.
--   noctalia msg plugin kurai/taskwarrior:tasks all tab add
function onIpc(event, payload)
  if event ~= "tab" or type(payload) ~= "string" then
    return
  end
  for _, id in ipairs(S.TABS) do
    if id == payload then
      S.gotoTab(id)
      -- The panel may be closed; never let a render error escape IPC.
      pcall(render)
      return
    end
  end
end

-- Entry globals below are lifecycle + watches only.

noctalia.state.watch("tasks", function(value)
  if type(value) == "table" then
    S.tasks = value
    Ops.dropSelectionIfGone()
    render()
  end
end)

noctalia.state.watch("completed", function(value)
  if type(value) == "table" then
    S.completed = value
    render()
  end
end)

noctalia.state.watch("meta", function(value)
  if type(value) == "table" then
    S.meta = value
  end
end)

noctalia.state.watch("backend", function(value)
  if type(value) == "table" then
    S.backend = value
    render()
  end
end)

noctalia.state.watch("activeTab", function(value)
  if type(value) == "string" then
    S.activeTab = value
  end
end)

noctalia.state.watch("trackOverride", function(_value)
  render()
end)
