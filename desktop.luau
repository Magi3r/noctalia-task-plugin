--!nonstrict
-- Desktop widget for Tasks & Todo.
-- Displays prioritized pending tasks directly on the desktop wallpaper layer.
-- Allows quick completion of tasks directly from the desktop.

local utils = require("./utils.luau")

local PANEL_ID = "magi3r/noctalia-task-plugin:panel"

local tasks = {}
local pendingCount = 0
local isSyncing = false
local lastSyncTime = 0

local function refresh()
  local raw = noctalia.state.get("tasks.items")
  if raw and raw ~= "" then
    local decoded = noctalia.json.decode(raw)
    if type(decoded) == "table" then
      tasks = {}
      for _, item in ipairs(decoded) do
        if item.status == "pending" or item.status == "waiting" or item.status == "recurring" then
          table.insert(tasks, item)
        end
      end
    end
  end

  pendingCount = tonumber(noctalia.state.get("tasks.pendingCount")) or 0
  isSyncing = noctalia.state.get("tasks.syncing") == true
  lastSyncTime = tonumber(noctalia.state.get("tasks.lastSyncTime")) or 0
end

local function render()
  refresh()

  local maxTasks = tonumber(noctalia.getConfig("desktop_max_tasks")) or 8
  local itemsToShow = {}

  for i = 1, math.min(maxTasks, #tasks) do
    table.insert(itemsToShow, tasks[i])
  end

  local taskRows = {}

  if #itemsToShow == 0 then
    table.insert(taskRows, ui.column({
      fill = "surface_variant/0.2",
      radius = 8,
      padding = 16,
      align = "center",
      gap = 8,
    }, {
      ui.glyph({ name = "check", color = "primary", size = 28 }),
      ui.label({ text = "All tasks completed!", fontSize = 13, color = "on_surface_variant" }),
    }))
  else
    for _, t in ipairs(itemsToShow) do
      local uuid = t.uuid or ""
      local priority = t.priority
      local due = t.due
      local project = t.project

      local metaRow = {}

      if priority and priority ~= "" then
        local pColor = utils.priorityColor(priority)
        table.insert(metaRow, ui.label({
          text = `[{utils.priorityLabel(priority)}]`,
          fontSize = 10,
          fontWeight = "bold",
          color = pColor,
        }))
      end

      if project and project ~= "" then
        table.insert(metaRow, ui.label({
          text = project,
          fontSize = 10,
          color = "primary",
          fontWeight = "medium",
        }))
      end

      if due and due ~= "" then
        local dueText, isOverdue = utils.formatDueDate(due)
        table.insert(metaRow, ui.label({
          text = dueText,
          fontSize = 10,
          color = if isOverdue then "error" else "secondary",
        }))
      end

      local taskContent = ui.column({ flexGrow = 1, gap = 2 }, {
        ui.label({
          text = t.description or "Untitled",
          fontSize = 12,
          fontWeight = "medium",
          color = "on_surface",
        }),
      })

      if #metaRow > 0 then
        table.insert(taskContent.children, ui.row({ gap = 6, align = "center" }, metaRow))
      end

      table.insert(taskRows, ui.row({
        fill = "surface_variant/0.3",
        radius = 6,
        padding = 6,
        border = "outline",
        borderWidth = 1,
        gap = 8,
        align = "center",
        justify = "space_between",
      }, {
        ui.button({
          glyph = "square",
          variant = "ghost",
          controlSize = "sm",
          onClick = function()
            local cmd = {
              action = "COMPLETE",
              uuid = uuid,
            }
            noctalia.state.set("tasks.cmd", noctalia.json.encode(cmd))
          end,
        }),
        taskContent,
      }))
    end
  end

  local syncText = if isSyncing then "Syncing..." elseif lastSyncTime > 0 then `Synced {utils.formatTimeAgo(lastSyncTime)}` else ""

  local rootChildren = {
    -- Header
    ui.row({ align = "center", justify = "space_between" }, {
      ui.row({ align = "center", gap = 6 }, {
        ui.glyph({ name = "checklist", color = "primary", size = 16 }),
        ui.label({ text = "Tasks", fontSize = 14, fontWeight = "bold", color = "on_surface" }),
        ui.label({ text = `({pendingCount})`, fontSize = 12, color = "on_surface_variant" }),
      }),
      ui.row({ gap = 4 }, {
        ui.button({
          glyph = "refresh",
          variant = "ghost",
          controlSize = "sm",
          enabled = not isSyncing,
          onClick = function()
            noctalia.state.set("tasks.cmd", '{"action":"SYNC"}')
          end,
        }),
        ui.button({
          glyph = "plus",
          variant = "ghost",
          controlSize = "sm",
          onClick = function()
            noctalia.togglePanel(PANEL_ID)
          end,
        }),
      }),
    }),

    -- Task Rows
    ui.column({ gap = 4 }, taskRows),
  }

  -- Footer
  if syncText ~= "" then
    table.insert(rootChildren, ui.row({ align = "center", justify = "space_between", padding = 2 }, {
      ui.label({ text = syncText, fontSize = 10, color = "on_surface_variant" }),
      ui.button({
        text = "Open Panel",
        variant = "ghost",
        controlSize = "sm",
        onClick = function()
          noctalia.togglePanel(PANEL_ID)
        end,
      }),
    }))
  end

  desktopWidget.render(ui.column({
    fill = "surface/0.85",
    radius = 12,
    padding = 12,
    border = "outline",
    borderWidth = 1,
    gap = 8,
  }, rootChildren))
end

noctalia.state.watch("tasks.items", function()
  render()
end)

noctalia.state.watch("tasks.syncing", function()
  render()
end)

function update()
  render()
end

render()
