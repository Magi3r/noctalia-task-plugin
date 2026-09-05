--!nonstrict
-- Headless background service for Taskwarrior & TaskChampion synchronization.
-- Owns data loading, execution of task CLI commands, and automated sync intervals.

noctalia.setUpdateInterval(5000)

local isSyncing = false
local lastSyncTime = 0
local lastSyncStatus = "never"
local lastSyncError = ""
local tasksList = {}
local pendingCount = 0
local completedCount = 0
local projectList = {}
local tagList = {}

local function getTaskCmd()
  local bin = noctalia.getConfig("task_binary")
  if not bin or bin == "" then
    return "task"
  end
  return bin
end

-- Initialize state keys
noctalia.state.set("tasks.items", "[]")
noctalia.state.set("tasks.pendingCount", 0)
noctalia.state.set("tasks.completedCount", 0)
noctalia.state.set("tasks.syncing", false)
noctalia.state.set("tasks.lastSyncTime", 0)
noctalia.state.set("tasks.lastSyncStatus", "never")
noctalia.state.set("tasks.syncError", "")
noctalia.state.set("tasks.projects", "[]")
noctalia.state.set("tasks.tags", "[]")
noctalia.state.set("tasks.hasTaskwarrior", true)

local function escapeShellArg(arg: string): string
  return "'" .. arg:gsub("'", "'\\''") .. "'"
end

local loadTasks
local syncTasks

loadTasks = function()
  local taskBin = getTaskCmd()
  local cmd = `{escapeShellArg(taskBin)} rc.confirmation=no rc.verbose=nothing export`

  noctalia.runAsync(cmd, function(result)
    if result.exitCode == 0 then
      local raw = result.stdout or "[]"
      local decoded, err = noctalia.json.decode(raw)
      if type(decoded) == "table" then
        tasksList = decoded
        noctalia.state.set("tasks.hasTaskwarrior", true)

        local pCount = 0
        local cCount = 0
        local projectsMap = {}
        local tagsMap = {}

        for _, item in ipairs(tasksList) do
          if item.status == "pending" or item.status == "waiting" or item.status == "recurring" then
            pCount += 1
          elseif item.status == "completed" then
            cCount += 1
          end

          if item.project and item.project ~= "" then
            projectsMap[item.project] = true
          end

          if item.tags and type(item.tags) == "table" then
            for _, tag in ipairs(item.tags) do
              if tag ~= "" then
                tagsMap[tag] = true
              end
            end
          end
        end

        pendingCount = pCount
        completedCount = cCount

        projectList = {}
        for proj, _ in pairs(projectsMap) do
          table.insert(projectList, proj)
        end
        table.sort(projectList)

        tagList = {}
        for tag, _ in pairs(tagsMap) do
          table.insert(tagList, tag)
        end
        table.sort(tagList)

        -- Sort tasks by urgency descending
        table.sort(tasksList, function(a, b)
          local aUrg = a.urgency or 0
          local bUrg = b.urgency or 0
          return aUrg > bUrg
        end)

        noctalia.state.set("tasks.items", noctalia.json.encode(tasksList) or "[]")
        noctalia.state.set("tasks.pendingCount", pendingCount)
        noctalia.state.set("tasks.completedCount", completedCount)
        noctalia.state.set("tasks.projects", noctalia.json.encode(projectList) or "[]")
        noctalia.state.set("tasks.tags", noctalia.json.encode(tagList) or "[]")
      else
        noctalia.log(`Failed to decode tasks JSON: {err or "unknown"}`)
      end
    else
      noctalia.state.set("tasks.hasTaskwarrior", false)
      noctalia.log(`Taskwarrior export exited with code {result.exitCode}: {result.stderr}`)
    end
  end, 10000)
end

syncTasks = function()
  if isSyncing then
    return
  end

  isSyncing = true
  noctalia.state.set("tasks.syncing", true)

  local taskBin = getTaskCmd()
  local cmd = `{escapeShellArg(taskBin)} rc.confirmation=no rc.verbose=nothing sync`

  noctalia.runAsync(cmd, function(result)
    isSyncing = false
    noctalia.state.set("tasks.syncing", false)

    if result.exitCode == 0 then
      lastSyncTime = os.time()
      lastSyncStatus = "success"
      lastSyncError = ""
      noctalia.state.set("tasks.lastSyncTime", lastSyncTime)
      noctalia.state.set("tasks.lastSyncStatus", "success")
      noctalia.state.set("tasks.syncError", "")
      -- Reload local task state after pulling changes from TaskChampion server
      loadTasks()
    else
      lastSyncStatus = "error"
      lastSyncError = result.stderr ~= "" and result.stderr or result.stdout
      noctalia.state.set("tasks.lastSyncStatus", "error")
      noctalia.state.set("tasks.syncError", lastSyncError)
      noctalia.log(`TaskChampion sync error: {lastSyncError}`)

      local notify = noctalia.getConfig("notify_on_sync")
      if notify == true then
        noctalia.notifyError("Task Sync Error", lastSyncError)
      end
    end
  end, 30000)
end

local function syncOnChange()
  local shouldSync = noctalia.getConfig("sync_on_change")
  if shouldSync == nil or shouldSync == true then
    syncTasks()
  end
end

local function addTask(payload)
  local desc = payload.description
  if not desc or desc == "" then
    return
  end

  local taskBin = getTaskCmd()
  local args = {
    escapeShellArg(taskBin),
    "rc.confirmation=no",
    "rc.verbose=nothing",
    "add",
    escapeShellArg(desc),
  }

  if payload.project and payload.project ~= "" then
    table.insert(args, escapeShellArg(`project:{payload.project}`))
  end

  if payload.priority and payload.priority ~= "" and payload.priority ~= "none" then
    table.insert(args, escapeShellArg(`priority:{payload.priority}`))
  end

  if payload.due and payload.due ~= "" then
    table.insert(args, escapeShellArg(`due:{payload.due}`))
  end

  if payload.tags and type(payload.tags) == "table" then
    for _, tag in ipairs(payload.tags) do
      if tag ~= "" then
        table.insert(args, escapeShellArg(`+{tag}`))
      end
    end
  elseif payload.tags and type(payload.tags) == "string" and payload.tags ~= "" then
    for tag in payload.tags:gmatch("([^,%s]+)") do
      table.insert(args, escapeShellArg(`+{tag}`))
    end
  end

  local cmd = table.concat(args, " ")
  noctalia.runAsync(cmd, function(result)
    if result.exitCode == 0 then
      loadTasks()
      syncOnChange()
    else
      noctalia.log(`Add task error: {result.stderr}`)
      noctalia.notifyError("Failed to add task", result.stderr)
    end
  end, 10000)
end

local function completeTask(uuid: string)
  if not uuid or uuid == "" then
    return
  end

  local taskBin = getTaskCmd()
  local cmd = `{escapeShellArg(taskBin)} rc.confirmation=no rc.verbose=nothing {escapeShellArg(uuid)} done`

  noctalia.runAsync(cmd, function(result)
    if result.exitCode == 0 then
      loadTasks()
      syncOnChange()
    else
      noctalia.log(`Complete task error: {result.stderr}`)
    end
  end, 10000)
end

local function uncompleteTask(uuid: string)
  if not uuid or uuid == "" then
    return
  end

  local taskBin = getTaskCmd()
  local cmd = `{escapeShellArg(taskBin)} rc.confirmation=no rc.verbose=nothing {escapeShellArg(uuid)} modify status:pending`

  noctalia.runAsync(cmd, function(result)
    if result.exitCode == 0 then
      loadTasks()
      syncOnChange()
    else
      noctalia.log(`Uncomplete task error: {result.stderr}`)
    end
  end, 10000)
end

local function deleteTask(uuid: string)
  if not uuid or uuid == "" then
    return
  end

  local taskBin = getTaskCmd()
  local cmd = `{escapeShellArg(taskBin)} rc.confirmation=no rc.verbose=nothing {escapeShellArg(uuid)} delete`

  noctalia.runAsync(cmd, function(result)
    if result.exitCode == 0 then
      loadTasks()
      syncOnChange()
    else
      noctalia.log(`Delete task error: {result.stderr}`)
    end
  end, 10000)
end

-- Command dispatcher
noctalia.state.watch("tasks.cmd", function(rawCmd)
  if not rawCmd or rawCmd == "" then
    return
  end

  local payload, err = noctalia.json.decode(rawCmd)
  if type(payload) ~= "table" then
    if rawCmd == "SYNC" then
      syncTasks()
    elseif rawCmd == "REFRESH" then
      loadTasks()
    end
    return
  end

  local action = payload.action
  if action == "SYNC" then
    syncTasks()
  elseif action == "REFRESH" then
    loadTasks()
  elseif action == "ADD" then
    addTask(payload)
  elseif action == "COMPLETE" then
    completeTask(payload.uuid)
  elseif action == "UNCOMPLETE" then
    uncompleteTask(payload.uuid)
  elseif action == "TOGGLE_DONE" then
    if payload.completed == true or payload.status == "completed" then
      uncompleteTask(payload.uuid)
    else
      completeTask(payload.uuid)
    end
  elseif action == "DELETE" then
    deleteTask(payload.uuid)
  end
end)

-- Initial data load and background auto-sync loop
loadTasks()

function update()
  local autoSync = noctalia.getConfig("auto_sync")
  if autoSync == nil or autoSync == true then
    local intervalMins = tonumber(noctalia.getConfig("sync_interval_mins")) or 10
    if intervalMins > 0 then
      local intervalSecs = intervalMins * 60
      local now = os.time()

      if (now - lastSyncTime) >= intervalSecs and not isSyncing then
        syncTasks()
      end
    end
  end
end

function onIpc(event: string, payload: string?)
  local ev = (event or ""):upper()
  local pl = (payload or ""):upper()
  if ev == "SYNC" or pl == "SYNC" then
    syncTasks()
  elseif ev == "REFRESH" or pl == "REFRESH" then
    loadTasks()
  end
end

