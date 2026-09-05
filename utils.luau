--!strict
local utils = {}

export type ParsedDate = {
  year: number,
  month: number,
  day: number,
  hour: number,
  min: number,
  sec: number,
  formatted: string,
}

function utils.parseIsoDate(dateStr: string?): ParsedDate?
  if not dateStr or dateStr == "" then
    return nil
  end

  local y, m, d, h, min, s = dateStr:match("^(%d%d%d%d)(%d%d)(%d%d)T(%d%d)(%d%d)(%d%d)Z$")
  if not y then
    -- Try YYYYMMDD
    local y2, m2, d2 = dateStr:match("^(%d%d%d%d)(%d%d)(%d%d)")
    if y2 then
      return {
        year = tonumber(y2) or 0,
        month = tonumber(m2) or 0,
        day = tonumber(d2) or 0,
        hour = 0,
        min = 0,
        sec = 0,
        formatted = `{y2}-{m2}-{d2}`,
      }
    end
    return nil
  end

  return {
    year = tonumber(y) or 0,
    month = tonumber(m) or 0,
    day = tonumber(d) or 0,
    hour = tonumber(h) or 0,
    min = tonumber(min) or 0,
    sec = tonumber(s) or 0,
    formatted = `{y}-{m}-{d}`,
  }
end

function utils.formatDueDate(dateStr: string?): (string, boolean)
  local parsed = utils.parseIsoDate(dateStr)
  if not parsed then
    return "", false
  end

  local now = os.time()
  local nowTable = os.date("*t", now) :: { year: number, month: number, day: number }
  
  -- Create timestamp for target date
  local targetTs = os.time({
    year = parsed.year,
    month = parsed.month,
    day = parsed.day,
    hour = parsed.hour,
    min = parsed.min,
    sec = parsed.sec,
  })

  -- Today at midnight
  local todayMidnight = os.time({
    year = nowTable.year,
    month = nowTable.month,
    day = nowTable.day,
    hour = 0,
    min = 0,
    sec = 0,
  })

  local tomorrowMidnight = todayMidnight + 86400
  local dayAfterTomorrow = todayMidnight + 172800

  local isOverdue = targetTs < now
  local label = parsed.formatted

  if targetTs >= todayMidnight and targetTs < tomorrowMidnight then
    label = "Today"
    isOverdue = false
  elseif targetTs >= tomorrowMidnight and targetTs < dayAfterTomorrow then
    label = "Tomorrow"
    isOverdue = false
  elseif targetTs < todayMidnight then
    local daysAgo = math.floor((todayMidnight - targetTs) / 86400) + 1
    label = if daysAgo == 1 then "Yesterday" else `{daysAgo}d overdue`
    isOverdue = true
  end

  return label, isOverdue
end

function utils.formatTimeAgo(timestamp: number?): string
  if not timestamp or timestamp == 0 then
    return "never"
  end

  local elapsed = os.time() - timestamp
  if elapsed < 0 then
    return "just now"
  elseif elapsed < 60 then
    return `{elapsed}s ago`
  elseif elapsed < 3600 then
    local mins = math.floor(elapsed / 60)
    return `{mins}m ago`
  elseif elapsed < 86400 then
    local hours = math.floor(elapsed / 3600)
    return `{hours}h ago`
  else
    local days = math.floor(elapsed / 86400)
    return `{days}d ago`
  end
end

function utils.priorityColor(priority: string?): string
  if priority == "H" then
    return "error"
  elseif priority == "M" then
    return "tertiary"
  elseif priority == "L" then
    return "secondary"
  else
    return "outline"
  end
end

function utils.priorityLabel(priority: string?): string
  if priority == "H" then
    return "HIGH"
  elseif priority == "M" then
    return "MED"
  elseif priority == "L" then
    return "LOW"
  else
    return ""
  end
end

return utils
