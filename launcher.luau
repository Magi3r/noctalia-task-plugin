--!nonstrict
-- Launcher search provider for Tasks.
-- Type `/todo` or `/todo <search>` in the Noctalia launcher to find tasks.
-- Selecting a task marks it completed.

local utils = require("./utils.luau")

local function getTasks()
  local raw = noctalia.state.get("tasks.items")
  if raw and raw ~= "" then
    local decoded = noctalia.json.decode(raw)
    if type(decoded) == "table" then
      return decoded
    end
  end
  return {}
end

function onQuery(query: string)
  local all = getTasks()
  local results = {}
  local queryLower = (query or ""):lower():gsub("^%s+", ""):gsub("%s+$", "")

  for _, t in ipairs(all) do
    if t.status == "pending" or t.status == "waiting" or t.status == "recurring" then
      local desc = t.description or ""
      local proj = t.project or ""
      local score = 1.0

      if queryLower ~= "" then
        score = noctalia.fuzzyScore(queryLower, desc)
        if not score and proj ~= "" then
          score = noctalia.fuzzyScore(queryLower, proj)
        end
      end

      if score or queryLower == "" then
        local subtitleParts = {}
        if proj ~= "" then
          table.insert(subtitleParts, `Project: {proj}`)
        end
        if t.due then
          local dueText = utils.formatDueDate(t.due)
          table.insert(subtitleParts, `Due: {dueText}`)
        end

        table.insert(results, {
          id = t.uuid or "",
          title = desc,
          subtitle = table.concat(subtitleParts, " • "),
          glyph = "check-square",
          badge = t.priority and utils.priorityLabel(t.priority) or nil,
          score = score or 0.5,
        })
      end
    end
  end

  launcher.setResults(query, results)
end

function onActivate(uuid: string)
  if uuid and uuid ~= "" then
    local cmd = {
      action = "COMPLETE",
      uuid = uuid,
    }
    noctalia.state.set("tasks.cmd", noctalia.json.encode(cmd))
    noctalia.notify("Task Completed", "Marked task as done.")
  end
end
