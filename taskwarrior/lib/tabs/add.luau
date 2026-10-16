--!nonstrict
-- Add tab: new-task form. Natural dates accepted; Add keeps the form, Add +
-- clear resets it (fresh input keys recreate the fields).

local S = require("../panel_state.luau")
local Ops = require("../panel_ops.luau")
local UI = require("../panel_ui.luau")

local T = {}

function T.render()
  return ui.column({ flexGrow = 1, gap = 10, align = "stretch", justify = "start" }, {
    UI.card("add-form-card", {
    UI.section(noctalia.tr("add.description"), ui.input({
      key = "add-desc-" .. tostring(S.addKey),
      value = S.addForm.desc,
      placeholder = noctalia.tr("add.description_placeholder"),
      focus = true,
      onChange = function(value)
        S.addForm.desc = value or ""
      end,
      onSubmit = function(value)
        S.addForm.desc = value or ""
        Ops.doAdd(false)
      end,
    })),
    ui.row({ gap = 8, align = "stretch", justify = "start" }, {
      ui.column({ gap = 8, flexGrow = 1, align = "stretch", justify = "start" }, {
        UI.section(noctalia.tr("common.form.project"), ui.input({
          key = "add-proj-" .. tostring(S.addKey),
          value = S.addForm.project,
          placeholder = noctalia.tr("add.project_placeholder"),
          onChange = function(value)
            S.addForm.project = noctalia.string.trim(value or "")
          end,
        })),
      }),
      ui.column({ gap = 8, flexGrow = 1, align = "stretch", justify = "start" }, {
        UI.section(noctalia.tr("common.form.priority"), ui.select({
          key = "add-pri",
          options = S.detailPriOpts(),
          selectedIndex = S.addForm.priIdx,
          onChange = function(index)
            S.addForm.priIdx = tonumber(index) or 0
          end,
        })),
      }),
    }),
    ui.row({ gap = 8, align = "stretch", justify = "start" }, {
      ui.column({ gap = 8, flexGrow = 1, align = "stretch", justify = "start" }, {
        UI.section(noctalia.tr("common.form.due"), ui.input({
          key = "add-due-" .. tostring(S.addKey),
          value = S.addForm.due,
          placeholder = noctalia.tr("add.due_placeholder"),
          onChange = function(value)
            S.addForm.due = noctalia.string.trim(value or "")
          end,
        })),
      }),
      ui.column({ gap = 8, flexGrow = 1, align = "stretch", justify = "start" }, {
        UI.section(noctalia.tr("common.form.scheduled"), ui.input({
          key = "add-sch-" .. tostring(S.addKey),
          value = S.addForm.scheduled,
          placeholder = noctalia.tr("add.scheduled_placeholder"),
          onChange = function(value)
            S.addForm.scheduled = noctalia.string.trim(value or "")
          end,
        })),
      }),
      ui.column({ gap = 8, flexGrow = 1, align = "stretch", justify = "start" }, {
        UI.section(noctalia.tr("common.form.wait"), ui.input({
          key = "add-wait-" .. tostring(S.addKey),
          value = S.addForm.wait,
          placeholder = noctalia.tr("add.wait_placeholder"),
          onChange = function(value)
            S.addForm.wait = noctalia.string.trim(value or "")
          end,
        })),
      }),
    }),
    UI.section(noctalia.tr("common.form.tags"), ui.input({
      key = "add-tags-" .. tostring(S.addKey),
      value = S.addForm.tags,
      placeholder = noctalia.tr("add.tags_placeholder"),
      onChange = function(value)
        S.addForm.tags = value or ""
      end,
    })),
    UI.section(noctalia.tr("add.note_title"), ui.input({
      key = "add-note-" .. tostring(S.addKey),
      value = S.addForm.note,
      placeholder = noctalia.tr("add.note_placeholder"),
      onChange = function(value)
        S.addForm.note = value or ""
      end,
      onSubmit = function(value)
        S.addForm.note = value or ""
        Ops.doAdd(false)
      end,
    })),
    ui.row({ gap = 8, align = "stretch", justify = "start" }, {
      ui.button({
        key = "add-save",
        text = noctalia.tr("add.save"),
        variant = "primary",
        onClick = function()
          Ops.doAdd(false)
        end,
      }),
      ui.button({
        key = "add-save-clear",
        text = noctalia.tr("add.save_clear"),
        variant = "outline",
        onClick = function()
          Ops.doAdd(true)
        end,
      }),
    }),
    }),
    ui.label({ text = noctalia.tr("add.date_hint"), fontSize = 12, color = "on_surface_variant" }),
  })
end

return T
