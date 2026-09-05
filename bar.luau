--!nonstrict
-- Status bar widget for Tasks & Todo.
-- Displays pending task count, sync indicator, and rich tooltip.
-- Click opens the panel, middle click triggers TaskChampion sync.

local utils = require("./utils.luau")

local PANEL_ID = "magi3r/noctalia-task-plugin:panel"

local pendingCount = 0
local isSyncing = false
local lastSyncTime = 0
local lastSyncStatus = "never"
local isVertical = false
local topTasks = {}

local function updateTooltip()
  local lines = {}
  table.insert(lines, `Tasks: {pendingCount} pending`)

  local syncStatusText = "Never"
  if lastSyncTime > 0 then
    syncStatusText = utils.formatTimeAgo(lastSyncTime)
    if lastSyncStatus == "error" then
      syncStatusText = syncStatusText .. " (Error)"
    end
  end
  table.insert(lines, `Last Sync: {syncStatusText}`)

  if #topTasks > 0 then
    table.insert(lines, "── Recent Tasks ──")
    for i = 1, math.min(3, #topTasks) do
      local t = topTasks[i]
      local prefix = t.priority and `[{t.priority}] ` or ""
      local dueText = ""
      if t.due then
        local dueFormatted, isOverdue = utils.formatDueDate(t.due)
        dueText = ` ({dueFormatted})`
      end
      table.insert(lines, `• {prefix}{t.description}{dueText}`)
    end
  end

  barWidget.setTooltip(table.concat(lines, "\n"))
end

local function render()
  local showCount = noctalia.getConfig("show_count")
  if showCount == nil then
    showCount = true
  end

  local glyphName = noctalia.getConfig("glyph") or "checklist"
  local glyphColor = if isSyncing then "tertiary" elseif pendingCount > 0 then "primary" else "on_surface"

  if isVertical then
    barWidget.render(ui.column({ align = "center", gap = 2 }, {
      ui.glyph({ name = glyphName, color = glyphColor }),
    }))
  else
    if showCount then
      local labelColor = if pendingCount > 0 then "on_surface" else "on_surface_variant"
      barWidget.render(ui.row({ gap = 6, align = "center" }, {
        ui.glyph({ name = glyphName, color = glyphColor }),
        ui.label({
          text = tostring(pendingCount),
          fontWeight = if pendingCount > 0 then "bold" else "normal",
          color = labelColor,
        }),
      }))
    else
      barWidget.render(ui.row({ align = "center" }, {
        ui.glyph({ name = glyphName, color = glyphColor }),
      }))
    end
  end

  updateTooltip()
end

noctalia.state.watch("tasks.pendingCount", function(value)
  pendingCount = tonumber(value) or 0
  render()
end)

noctalia.state.watch("tasks.syncing", function(value)
  isSyncing = value == true
  render()
end)

noctalia.state.watch("tasks.lastSyncTime", function(value)
  lastSyncTime = tonumber(value) or 0
  updateTooltip()
end)

noctalia.state.watch("tasks.lastSyncStatus", function(value)
  lastSyncStatus = tostring(value) or "never"
  updateTooltip()
end)

noctalia.state.watch("tasks.items", function(raw)
  if raw and raw ~= "" then
    local decoded = noctalia.json.decode(raw)
    if type(decoded) == "table" then
      topTasks = {}
      for _, item in ipairs(decoded) do
        if item.status == "pending" then
          table.insert(topTasks, item)
        end
      end
      updateTooltip()
    end
  end
end)

function update()
  isVertical = barWidget.isVertical()
  pendingCount = tonumber(noctalia.state.get("tasks.pendingCount")) or 0
  isSyncing = noctalia.state.get("tasks.syncing") == true
  lastSyncTime = tonumber(noctalia.state.get("tasks.lastSyncTime")) or 0
  lastSyncStatus = tostring(noctalia.state.get("tasks.lastSyncStatus") or "never")
  render()
end

function onClick()
  noctalia.togglePanel(PANEL_ID)
end

function onMiddleClick()
  noctalia.state.set("tasks.cmd", '{"action":"SYNC"}')
end
