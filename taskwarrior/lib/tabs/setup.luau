--!nonstrict
-- Setup tab (shown when the backend is unhealthy): explains the missing
-- database and offers one-click init, terminal fallback, or retry.

local S = require("../panel_state.luau")
local Ops = require("../panel_ops.luau")
local UI = require("../panel_ui.luau")

local T = {}

function T.error()
  -- Backend failures that are NOT a missing database (locks, parse errors,
  -- version mismatch, missing binary): no Initialize offer here.
  return ui.column({ flexGrow = 1, gap = 12, align = "stretch", justify = "start" }, {
    ui.label({ text = noctalia.tr("setup.error_title"), fontSize = 16, fontWeight = "bold" }),
    ui.label({ text = tostring(S.backend["error"] or "Unknown error"), color = "error" }),
    UI.card("setup-error-card", {
      ui.label({
        text = noctalia.tr("setup.error_hint"),
        color = "on_surface_variant",
      }),
      ui.row({ gap = 8, align = "center", justify = "start" }, {
        ui.button({
          key = "setup-err-retry",
          text = noctalia.tr("setup.retry"),
          variant = "primary",
          onClick = function()
            Ops.fetchTasks()
          end,
        }),
        ui.button({
          key = "setup-err-terminal",
          text = noctalia.tr("setup.terminal_short"),
          variant = "outline",
          onClick = function()
            noctalia.runInTerminal(S.bin)
          end,
        }),
      }),
    }),
  })
end

function T.render()
  if S.setupDir == "" then
    S.setupDir = Ops.defaultDataDir()
  end
  return ui.column({ flexGrow = 1, gap = 12, align = "stretch", justify = "start" }, {
    ui.label({ text = noctalia.tr("setup.title"), fontSize = 16, fontWeight = "bold" }),
    ui.label({ text = tostring(S.backend["error"] or "Not configured"), color = "error" }),
    UI.card("setup-card", {
      UI.section(noctalia.tr("setup.data_title"), ui.input({
        key = "setup-dir-" .. tostring(S.setupKey),
        value = S.setupDir,
        placeholder = noctalia.tr("setup.data_placeholder"),
        onChange = function(value)
          S.setupDir = noctalia.string.trim(value or "")
        end,
      })),
      UI.section(noctalia.tr("setup.rc_title"), ui.label({ text = Ops.defaultRcPath(), color = "on_surface_variant" })),
      ui.row({ gap = 8, align = "center", justify = "start" }, {
        ui.button({
          key = "setup-init",
          text = noctalia.tr("setup.init"),
          variant = "primary",
          onClick = function()
            Ops.doSetupInit()
          end,
        }),
        ui.button({
          key = "setup-terminal",
          text = noctalia.tr("setup.terminal"),
          variant = "outline",
          onClick = function()
            noctalia.runInTerminal(S.bin)
          end,
        }),
        ui.button({
          key = "setup-retry",
          text = noctalia.tr("setup.retry"),
          variant = "ghost",
          onClick = function()
            Ops.fetchTasks()
          end,
        }),
      }),
    }),
    ui.label({
      text = noctalia.tr("setup.stuck_hint"),
      fontSize = 12,
      color = "on_surface_variant",
    }),
  })
end

return T
