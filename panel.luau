--!nonstrict
-- Main task management panel with TaskChampion sync support.
-- Features distinct views: Main Task List View and Dedicated New Task View.

local utils = require("./utils.luau")

local allTasks = {}
local pendingCount = 0
local completedCount = 0
local isSyncing = false
local lastSyncTime = 0
local lastSyncStatus = "never"
local lastSyncError = ""
local projects = {}

-- UI State
local filterStatus = "pending" -- "pending" | "completed" | "all"
local searchQuery = ""
local selectedProjectFilter = "" -- "" means all projects
local projectFilterIndex = 0

-- New task view state
local isAddFormOpen = false
local newDescription = ""
local newProject = ""
local newDue = ""
local newTags = ""
local newPriorityIndex = 0 -- 0: None, 1: Low, 2: Med, 3: High
local priorityValues = { "", "L", "M", "H" }
local inputRev = 0

local function refreshLocalData()
  local raw = noctalia.state.get("tasks.items")
  if raw and raw ~= "" then
    local decoded = noctalia.json.decode(raw)
    if type(decoded) == "table" then
      allTasks = decoded
    end
  end

  local rawProjects = noctalia.state.get("tasks.projects")
  if rawProjects and rawProjects ~= "" then
    local decoded = noctalia.json.decode(rawProjects)
    if type(decoded) == "table" then
      projects = decoded
    end
  end

  pendingCount = tonumber(noctalia.state.get("tasks.pendingCount")) or 0
  completedCount = tonumber(noctalia.state.get("tasks.completedCount")) or 0
  isSyncing = noctalia.state.get("tasks.syncing") == true
  lastSyncTime = tonumber(noctalia.state.get("tasks.lastSyncTime")) or 0
  lastSyncStatus = tostring(noctalia.state.get("tasks.lastSyncStatus") or "never")
  lastSyncError = tostring(noctalia.state.get("tasks.syncError") or "")
end

local function getFilteredTasks()
  local result = {}
  local queryLower = searchQuery:lower()

  for _, task in ipairs(allTasks) do
    local matchesStatus = true
    if filterStatus == "pending" then
      matchesStatus = task.status == "pending" or task.status == "waiting" or task.status == "recurring"
    elseif filterStatus == "completed" then
      matchesStatus = task.status == "completed"
    end

    local matchesProject = true
    if selectedProjectFilter ~= "" then
      matchesProject = task.project == selectedProjectFilter
    end

    local matchesSearch = true
    if queryLower ~= "" then
      local descMatch = task.description and task.description:lower():find(queryLower, 1, true) ~= nil
      local projMatch = task.project and task.project:lower():find(queryLower, 1, true) ~= nil
      local tagMatch = false
      if task.tags and type(task.tags) == "table" then
        for _, tag in ipairs(task.tags) do
          if tag:lower():find(queryLower, 1, true) ~= nil then
            tagMatch = true
            break
          end
        end
      end
      matchesSearch = descMatch or projMatch or tagMatch
    end

    if matchesStatus and matchesProject and matchesSearch then
      table.insert(result, task)
    end
  end

  return result
end

local render

local function buildTaskRow(task)
  local isCompleted = task.status == "completed"
  local uuid = task.uuid or ""
  local priority = task.priority
  local due = task.due
  local project = task.project
  local tags = task.tags

  local badges = {}

  -- Priority badge
  if priority and priority ~= "" then
    local pColor = utils.priorityColor(priority)
    local pText = utils.priorityLabel(priority)
    table.insert(badges, ui.row({
      fill = `{pColor}/0.2`,
      radius = 4,
      padding = 3,
      align = "center",
    }, {
      ui.label({ text = pText, fontSize = 10, fontWeight = "bold", color = pColor }),
    }))
  end

  -- Project badge
  if project and project ~= "" then
    table.insert(badges, ui.row({ gap = 3, align = "center" }, {
      ui.glyph({ name = "folder", size = 12, color = "primary" }),
      ui.label({ text = project, fontSize = 11, color = "primary", fontWeight = "medium" }),
    }))
  end

  -- Due date badge
  if due and due ~= "" then
    local dueText, isOverdue = utils.formatDueDate(due)
    local dueColor = if isCompleted then "on_surface_variant" elseif isOverdue then "error" else "secondary"
    table.insert(badges, ui.row({ gap = 3, align = "center" }, {
      ui.glyph({ name = "calendar", size = 12, color = dueColor }),
      ui.label({ text = dueText, fontSize = 11, color = dueColor, fontWeight = if isOverdue then "bold" else "normal" }),
    }))
  end

  -- Tags badges
  if tags and type(tags) == "table" and #tags > 0 then
    local tagStr = table.concat(tags, ", ")
    table.insert(badges, ui.row({ gap = 3, align = "center" }, {
      ui.glyph({ name = "tag", size = 12, color = "outline" }),
      ui.label({ text = tagStr, fontSize = 11, color = "outline" }),
    }))
  end

  local mainContent = ui.column({ flexGrow = 1, gap = 4 }, {
    ui.label({
      text = task.description or "Untitled Task",
      fontSize = 13,
      fontWeight = if isCompleted then "normal" else "medium",
      color = if isCompleted then "on_surface_variant" else "on_surface",
    }),
  })

  if #badges > 0 then
    table.insert(mainContent.children, ui.row({ gap = 8, align = "center" }, badges))
  end

  return ui.row({
    fill = if isCompleted then "surface_variant/0.15" else "surface_variant/0.35",
    radius = 8,
    padding = 8,
    border = "outline",
    borderWidth = 1,
    gap = 8,
    align = "center",
    justify = "space_between",
  }, {
    ui.button({
      glyph = if isCompleted then "check" else "square",
      variant = "ghost",
      controlSize = "sm",
      onClick = function()
        local cmd = {
          action = "TOGGLE_DONE",
          uuid = uuid,
          completed = isCompleted,
        }
        noctalia.state.set("tasks.cmd", noctalia.json.encode(cmd))
      end,
    }),
    mainContent,
    ui.button({
      glyph = "trash",
      variant = "ghost",
      controlSize = "sm",
      onClick = function()
        local cmd = {
          action = "DELETE",
          uuid = uuid,
        }
        noctalia.state.set("tasks.cmd", noctalia.json.encode(cmd))
      end,
    }),
  })
end

local function renderNewTaskView()
  panel.render(ui.column({ flexGrow = 1, gap = 16, padding = 14 }, {
    -- Header
    ui.row({ align = "center", justify = "space_between" }, {
      ui.row({ align = "center", gap = 8 }, {
        ui.button({
          glyph = "arrow-left",
          text = "Back",
          variant = "ghost",
          controlSize = "sm",
          onClick = "onToggleAddOpen",
        }),
        ui.label({ text = "Create New Task", fontSize = 16, fontWeight = "bold", color = "on_surface" }),
      }),
      ui.button({
        glyph = "close",
        variant = "ghost",
        controlSize = "sm",
        onClick = "onCloseClicked",
      }),
    }),

    -- Form Body
    ui.scroll({ flexGrow = 1, gap = 14 }, {
      -- 1. Description
      ui.column({ gap = 6 }, {
        ui.label({ text = "Description *", fontSize = 12, fontWeight = "medium", color = "on_surface_variant" }),
        ui.input({
          key = `task_desc_{inputRev}`,
          placeholder = "What needs to be done?",
          fontSize = 14,
          onChange = "onNewDescChange",
          onSubmit = "onAddSubmit",
        }),
      }),

      -- 2. Priority & Project Row
      ui.row({ gap = 12, align = "center" }, {
        ui.column({ gap = 6, flexGrow = 1 }, {
          ui.label({ text = "Priority", fontSize = 12, fontWeight = "medium", color = "on_surface_variant" }),
          ui.select({
            options = { "Priority: None", "Priority: Low (L)", "Priority: Med (M)", "Priority: High (H)" },
            selectedIndex = newPriorityIndex,
            onChange = "onPriorityChange",
          }),
        }),
        ui.column({ gap = 6, flexGrow = 1 }, {
          ui.label({ text = "Project", fontSize = 12, fontWeight = "medium", color = "on_surface_variant" }),
          ui.input({
            key = `task_proj_{inputRev}`,
            placeholder = "e.g. Work, Uni, Home",
            fontSize = 13,
            onChange = "onNewProjectChange",
            onSubmit = "onAddSubmit",
          }),
        }),
      }),

      -- 3. Due Date & Tags Row
      ui.row({ gap = 12, align = "center" }, {
        ui.column({ gap = 6, flexGrow = 1 }, {
          ui.label({ text = "Due Date", fontSize = 12, fontWeight = "medium", color = "on_surface_variant" }),
          ui.input({
            key = `task_due_{inputRev}`,
            placeholder = "e.g. today, tomorrow, 2026-08-30",
            fontSize = 13,
            onChange = "onNewDueChange",
            onSubmit = "onAddSubmit",
          }),
        }),
        ui.column({ gap = 6, flexGrow = 1 }, {
          ui.label({ text = "Tags", fontSize = 12, fontWeight = "medium", color = "on_surface_variant" }),
          ui.input({
            key = `task_tags_{inputRev}`,
            placeholder = "e.g. urgent, thesis (comma separated)",
            fontSize = 13,
            onChange = "onNewTagsChange",
            onSubmit = "onAddSubmit",
          }),
        }),
      }),
    }),

    -- Action Buttons
    ui.row({ gap = 10, justify = "end", align = "center", padding = 4 }, {
      ui.button({
        text = "Cancel",
        variant = "ghost",
        onClick = "onToggleAddOpen",
      }),
      ui.button({
        text = "Create Task",
        glyph = "plus",
        variant = "primary",
        onClick = "onAddSubmit",
      }),
    }),
  }))
end

local function renderTaskListView()
  local filtered = getFilteredTasks()

  -- Task item list or empty state
  local taskElements = {}
  if #filtered == 0 then
    local emptyMessage = if searchQuery ~= "" or selectedProjectFilter ~= "" then "No matching tasks found" else "You're all caught up!"
    local emptyGlyph = if filterStatus == "completed" then "checklist" else "check"

    table.insert(taskElements, ui.column({ align = "center", justify = "center", gap = 12, padding = 40 }, {
      ui.glyph({ name = emptyGlyph, color = "primary", size = 36 }),
      ui.label({ text = emptyMessage, fontSize = 14, color = "on_surface_variant", fontWeight = "medium" }),
    }))
  else
    for _, t in ipairs(filtered) do
      table.insert(taskElements, buildTaskRow(t))
    end
  end

  -- Project options for dropdown filter
  local projectOptions = { "All Projects" }
  for _, p in ipairs(projects) do
    table.insert(projectOptions, p)
  end

  -- Sync status formatting
  local syncStatusText = "Not synced"
  local syncStatusColor = "outline"
  if isSyncing then
    syncStatusText = "Syncing with TaskChampion..."
    syncStatusColor = "tertiary"
  elseif lastSyncStatus == "success" and lastSyncTime > 0 then
    syncStatusText = `Synced {utils.formatTimeAgo(lastSyncTime)}`
    syncStatusColor = "primary"
  elseif lastSyncStatus == "error" then
    syncStatusText = "Sync failed"
    syncStatusColor = "error"
  end

  local children = {
    -- 1. Header Row
    ui.row({ align = "center", justify = "space_between", gap = 8 }, {
      ui.row({ align = "center", gap = 8 }, {
        ui.glyph({ name = "checklist", color = "primary", size = 20 }),
        ui.label({ text = "Tasks", fontSize = 17, fontWeight = "bold", color = "on_surface" }),
        ui.row({
          fill = "primary/0.2",
          radius = 12,
          padding = 4,
          align = "center",
        }, {
          ui.label({ text = `{pendingCount} pending`, fontSize = 11, fontWeight = "bold", color = "primary" }),
        }),
      }),
      ui.row({ align = "center", gap = 4 }, {
        ui.button({
          text = "New Task",
          glyph = "plus",
          variant = "primary",
          controlSize = "sm",
          onClick = "onToggleAddOpen",
        }),
        ui.button({
          glyph = "refresh",
          variant = if isSyncing then "secondary" else "ghost",
          controlSize = "sm",
          enabled = not isSyncing,
          onClick = "onSyncClicked",
        }),
        ui.button({
          glyph = "close",
          variant = "ghost",
          controlSize = "sm",
          onClick = "onCloseClicked",
        }),
      }),
    }),

    -- 2. Filter & Search Toolbar
    ui.row({ gap = 8, align = "center", justify = "space_between" }, {
      ui.input({
        key = "search_box",
        placeholder = "Search tasks...",
        fontSize = 12,
        flexGrow = 1,
        onChange = "onSearchChange",
      }),
      ui.row({ gap = 4 }, {
        ui.button({
          text = "Pending",
          variant = if filterStatus == "pending" then "primary" else "ghost",
          controlSize = "sm",
          onClick = "onFilterPending",
        }),
        ui.button({
          text = "Completed",
          variant = if filterStatus == "completed" then "primary" else "ghost",
          controlSize = "sm",
          onClick = "onFilterCompleted",
        }),
        ui.button({
          text = "All",
          variant = if filterStatus == "all" then "primary" else "ghost",
          controlSize = "sm",
          onClick = "onFilterAll",
        }),
      }),
    }),
  }

  -- Project filter row (if projects exist)
  if #projects > 0 then
    table.insert(children, ui.row({ gap = 8, align = "center" }, {
      ui.label({ text = "Filter Project:", fontSize = 11, color = "on_surface_variant" }),
      ui.select({
        options = projectOptions,
        selectedIndex = projectFilterIndex,
        onChange = "onProjectFilterSelect",
      }),
    }))
  end

  -- 3. Scrollable Task List
  table.insert(children, ui.scroll({ flexGrow = 1, gap = 6 }, taskElements))

  -- 4. Footer Row
  table.insert(children, ui.row({ align = "center", justify = "space_between", padding = 2 }, {
    ui.row({ gap = 6, align = "center" }, {
      ui.glyph({ name = "refresh", size = 12, color = syncStatusColor }),
      ui.label({ text = syncStatusText, fontSize = 11, color = syncStatusColor }),
    }),
    ui.label({
      text = `{pendingCount} active • {completedCount} completed`,
      fontSize = 11,
      color = "on_surface_variant",
    }),
  }))

  panel.render(ui.column({ flexGrow = 1, gap = 12, padding = 14 }, children))
end

render = function()
  refreshLocalData()
  if isAddFormOpen then
    renderNewTaskView()
  else
    renderTaskListView()
  end
end

function onOpen(_context)
  refreshLocalData()
  render()
end

function onCloseClicked()
  panel.close()
end

function onToggleAddOpen()
  isAddFormOpen = not isAddFormOpen
  render()
end

function onSyncClicked()
  noctalia.state.set("tasks.cmd", '{"action":"SYNC"}')
end

function onNewDescChange(val: string)
  newDescription = val or ""
end

function onNewProjectChange(val: string)
  newProject = val or ""
end

function onNewDueChange(val: string)
  newDue = val or ""
end

function onNewTagsChange(val: string)
  newTags = val or ""
end

function onPriorityChange(index: number)
  newPriorityIndex = tonumber(index) or 0
end

function onAddSubmit()
  if newDescription == "" or newDescription:gsub("%s", "") == "" then
    return
  end

  local cmd = {
    action = "ADD",
    description = newDescription,
    project = newProject,
    priority = priorityValues[newPriorityIndex + 1] or "",
    due = newDue,
    tags = newTags,
  }

  noctalia.state.set("tasks.cmd", noctalia.json.encode(cmd))

  -- Clear inputs and return to list view
  newDescription = ""
  newProject = ""
  newDue = ""
  newTags = ""
  newPriorityIndex = 0
  isAddFormOpen = false
  inputRev += 1
  render()
end

function onSearchChange(val: string)
  searchQuery = val or ""
  render()
end

function onFilterPending()
  filterStatus = "pending"
  render()
end

function onFilterCompleted()
  filterStatus = "completed"
  render()
end

function onFilterAll()
  filterStatus = "all"
  render()
end

function onProjectFilterSelect(index: number, text: string)
  projectFilterIndex = tonumber(index) or 0
  if projectFilterIndex == 0 then
    selectedProjectFilter = ""
  else
    selectedProjectFilter = projects[projectFilterIndex] or ""
  end
  render()
end

noctalia.state.watch("tasks.items", function()
  render()
end)

noctalia.state.watch("tasks.syncing", function()
  render()
end)

noctalia.state.watch("tasks.lastSyncTime", function()
  render()
end)

noctalia.state.watch("tasks.lastSyncStatus", function()
  render()
end)
