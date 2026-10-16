--!nonstrict
-- Edit tab: detail editor for the selected task. Empty state when nothing
-- is selected; the whole form scrolls inside the fixed panel height.

local tasklib = require("../task.luau")
local S = require("../panel_state.luau")
local Ops = require("../panel_ops.luau")
local UI = require("../panel_ui.luau")

local T = {}

local function goTasks()
  S.gotoTab("tasks")
  Ops.rerender()
end

function T.render()
  local sel = Ops.findTask(S.selectedUuid)
  if sel == nil then
    return ui.column({ flexGrow = 1, gap = 10, align = "stretch", justify = "start" }, {
      UI.emptyState("edit-empty", "pencil", noctalia.tr("edit.empty_title"), noctalia.tr("edit.empty_hint")),
      ui.button({ key = "edit-gotasks", text = noctalia.tr("edit.go_to_tasks"), variant = "outline", onClick = goTasks }),
    })
  end
  local anns = {}
  if type(sel["annotations"]) == "table" then
    for idx, a in ipairs(sel["annotations"]) do
      local txt = tostring(a["description"] or "")
      local note = txt
      table.insert(anns, ui.row({ key = "ann-" .. S.selectedUuid .. "-" .. tostring(idx), gap = 8, align = "center", justify = "start" }, {
        ui.label({ text = "• " .. txt, fontSize = 12, color = "on_surface_variant", flexGrow = 1 }),
        ui.button({
          key = "denote-" .. S.selectedUuid .. "-" .. tostring(idx),
          glyph = "trash",
          glyphSize = 12,
          variant = "ghost",
          controlSize = "sm",
          tooltip = noctalia.tr("edit.remove_note"),
          onClick = function()
            Ops.doDenotate(note)
          end,
        }),
      }))
    end
  end
  if #anns == 0 then
    anns = { ui.label({ text = noctalia.tr("edit.no_notes"), fontSize = 12, color = "on_surface_variant" }) }
  end
  local startLabel = noctalia.tr("edit.start")
  if sel["start"] ~= nil then
    startLabel = noctalia.tr("edit.stop")
  end
  local function deleteTask()
    if S.selectedUuid ~= "" then
      S.gotoTab("tasks")
      Ops.doDelete(S.selectedUuid)
    end
  end
  -- Starting a completed/deleted/recurring task silently reopens it, so the
  -- timer button only exists for actionable tasks. Done is meaningless on
  -- an already-completed task.
  local st = sel["status"] or "pending"
  local actionable = st == "pending" or st == "waiting"
  local header = {
    ui.button({ key = "edit-back", text = noctalia.tr("common.back_to_tasks"), variant = "ghost", controlSize = "sm", onClick = goTasks }),
    ui.label({ text = noctalia.tr("edit.title", { id = tasklib.shortUuid(S.selectedUuid) }), fontWeight = "bold", flexGrow = 1 }),
  }
  if st == "completed" then
    table.insert(header, UI.pill("edit-status", noctalia.tr("edit.status_completed"), "secondary", false))
  elseif st == "recurring" then
    table.insert(header, UI.pill("edit-status", noctalia.tr("edit.status_recurring"), "secondary", false))
  elseif st ~= "pending" and st ~= "waiting" then
    table.insert(header, UI.pill("edit-status", st, "error", true))
  end
  if actionable then
    table.insert(header, ui.button({
      key = "edit-timer-" .. ((sel["start"] ~= nil) and "stop" or "start"),
      text = startLabel,
      variant = "outline",
      controlSize = "sm",
      onClick = function()
        if S.selectedUuid ~= "" then
          Ops.doToggleStart(S.selectedUuid)
        end
      end,
    }))
  end
  if st ~= "completed" then
    table.insert(header, ui.button({
      key = "edit-done",
      text = noctalia.tr("edit.done"),
      variant = "primary",
      controlSize = "sm",
      onClick = function()
        if S.selectedUuid ~= "" then
          S.gotoTab("tasks")
          Ops.doDone(S.selectedUuid)
        end
      end,
    }))
  end
  return ui.column({ flexGrow = 1, gap = 10, align = "stretch", justify = "start" }, {
    ui.row({ gap = 8, align = "center", justify = "start" }, header),
    ui.scroll({ key = "edit-form-scroll", flexGrow = 1, gap = 10, align = "stretch" }, {
      UI.card("edit-form-card", {
      UI.section(noctalia.tr("common.form.description"), ui.input({
        key = "d-desc-" .. tostring(S.detailKey) .. "-" .. S.selectedUuid,
        value = S.detail.desc,
        placeholder = noctalia.tr("common.form.description"),
        onChange = function(value)
          S.detail.desc = value or ""
        end,
      })),
      ui.row({ gap = 8, align = "stretch", justify = "start" }, {
        ui.column({ gap = 8, flexGrow = 1, align = "stretch", justify = "start" }, {
          UI.section(noctalia.tr("common.form.project"), ui.input({
            key = "d-proj-" .. tostring(S.detailKey),
            value = S.detail.project,
            placeholder = noctalia.tr("edit.project_placeholder"),
            onChange = function(value)
              S.detail.project = noctalia.string.trim(value or "")
            end,
          })),
        }),
        ui.column({ gap = 8, flexGrow = 1, align = "stretch", justify = "start" }, {
          UI.section(noctalia.tr("common.form.priority"), ui.select({
            key = "edit-pri",
            options = S.detailPriOpts(),
            selectedIndex = S.detail.priIdx,
            onChange = function(index)
              S.detail.priIdx = tonumber(index) or 0
            end,
          })),
        }),
      }),
      ui.row({ gap = 8, align = "stretch", justify = "start" }, {
        ui.column({ gap = 8, flexGrow = 1, align = "stretch", justify = "start" }, {
          UI.section(noctalia.tr("common.form.due"), ui.input({
            key = "d-due-" .. tostring(S.detailKey),
            value = S.detail.due,
            placeholder = noctalia.tr("edit.due_hint"),
            onChange = function(value)
              S.detail.due = noctalia.string.trim(value or "")
            end,
          })),
        }),
        ui.column({ gap = 8, flexGrow = 1, align = "stretch", justify = "start" }, {
          UI.section(noctalia.tr("common.form.scheduled"), ui.input({
            key = "d-sch-" .. tostring(S.detailKey),
            value = S.detail.scheduled,
            placeholder = noctalia.tr("edit.scheduled_hint"),
            onChange = function(value)
              S.detail.scheduled = noctalia.string.trim(value or "")
            end,
          })),
        }),
        ui.column({ gap = 8, flexGrow = 1, align = "stretch", justify = "start" }, {
          UI.section(noctalia.tr("common.form.wait"), ui.input({
            key = "d-wait-" .. tostring(S.detailKey),
            value = S.detail.wait,
            placeholder = noctalia.tr("edit.wait_hint"),
            onChange = function(value)
              S.detail.wait = noctalia.string.trim(value or "")
            end,
          })),
        }),
      }),
      UI.section(noctalia.tr("common.form.tags"), ui.input({
        key = "d-tags-" .. tostring(S.detailKey),
        value = S.detail.tags,
        placeholder = noctalia.tr("edit.tags_placeholder"),
        onChange = function(value)
          S.detail.tags = value or ""
        end,
      })),
      UI.section(noctalia.tr("edit.notes_title") .. " (" .. tostring(#anns) .. ")", ui.column({ gap = 4, align = "stretch", justify = "start" }, anns)),
      ui.row({ gap = 8, align = "center", justify = "start" }, {
        ui.input({
          key = "note-" .. tostring(S.noteKey),
          value = S.noteText,
          placeholder = noctalia.tr("edit.note_placeholder"),
          flexGrow = 1,
          onChange = function(value)
            S.noteText = value or ""
          end,
          onSubmit = function(value)
            S.noteText = value or ""
            Ops.doAnnotate()
          end,
        }),
        ui.button({
          key = "edit-note-add",
          text = noctalia.tr("edit.note_add"),
          onClick = function()
            Ops.doAnnotate()
          end,
        }),
      }),
      ui.button({
        key = "edit-save",
        text = noctalia.tr("edit.save"),
        variant = "primary",
        onClick = function()
          Ops.doSaveDetail()
        end,
      }),
      }),
      UI.card("edit-danger-card", {
        ui.button({
          key = "edit-delete",
          text = S.deleteArmedAt ~= nil and noctalia.tr("edit.confirm_delete") or noctalia.tr("edit.delete"),
          variant = "destructive",
          onClick = function()
            if S.deleteArmedAt == nil then
              S.deleteArmedAt = os.time()
              S.setStatus(noctalia.tr("edit.confirm_delete_hint"), false)
              Ops.rerender()
              return
            end
            S.deleteArmedAt = nil
            deleteTask()
          end,
        }),
      }),
    }),
  })
end

return T
