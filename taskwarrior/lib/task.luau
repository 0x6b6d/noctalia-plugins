--!nonstrict
-- Shared Taskwarrior helpers. Required from widget/service/panel entries.
-- Must return exactly one non-nil value and keep no host calls at top level
-- except pure transforms (entries own their noctalia.* calls).

local M = {}

-- A virtual tag is all-caps (OVERDUE, PENDING, TODAY, ...). Real user tags
-- are kept; virtual ones are filtered out of tag facets.
function M.isVirtualTag(tag)
  if type(tag) ~= "string" or tag == "" then
    return true
  end
  return string.match(tag, "^[A-Z0-9_%-]+$") ~= nil
end

function M.shortUuid(uuid)
  if type(uuid) ~= "string" then
    return ""
  end
  return string.sub(uuid, 1, 8)
end

function M.nowUtcStr()
  local ok, s = pcall(function()
    return os.date("!%Y%m%dT%H%M%SZ")
  end)
  if ok and type(s) == "string" then
    return s
  end
  return os.date("%Y%m%dT%H%M%SZ")
end

-- Calendar-day number for date-only diffs (noon-anchored to dodge DST
-- edges). Plain epoch diffs misfile same-day stamps before local noon.
local function dayNum(y, mo, d)
  return math.floor(os.time({ year = y, month = mo, day = d, hour = 12 }) / 86400 + 0.5)
end

-- UTC offset in effect at a local instant, for interpreting export stamps
-- (which are always UTC) as true epochs. DST-safe except within an hour of
-- a transition, which task data never resolves anyway.
local function utcOffsetAt(localEpoch)
  -- NB: os.date tables carry isdst, and mktime honors it as a hint. A UTC
  -- breakdown always says isdst=false, which would force standard time, so
  -- strip it and let mktime determine DST from the date itself.
  local utc = os.date("!*t", localEpoch)
  utc.isdst = nil
  return os.difftime(localEpoch, os.time(utc))
end

-- True Unix epoch for a taskwarrior stamp (YYYYMMDDTHHMMSSZ, always UTC).
-- Returns nil for malformed input instead of guessing.
function M.stampToEpoch(stamp)
  if type(stamp) ~= "string" or #stamp < 15 then
    return nil
  end
  local y = tonumber(string.sub(stamp, 1, 4))
  local mo = tonumber(string.sub(stamp, 5, 6))
  local d = tonumber(string.sub(stamp, 7, 8))
  local hh = tonumber(string.sub(stamp, 10, 11)) or 0
  local mm = tonumber(string.sub(stamp, 12, 13)) or 0
  local ss = tonumber(string.sub(stamp, 14, 15)) or 0
  if y == nil or mo == nil or d == nil or mo < 1 or mo > 12 or d < 1 or d > 31 then
    return nil
  end
  local asLocal = os.time({ year = y, month = mo, day = d, hour = hh, min = mm, sec = ss })
  -- asLocal is the instant whose LOCAL display equals the stamp fields; the
  -- true instant displays offset later locally, so shift forward by it.
  return asLocal + utcOffsetAt(asLocal)
end

-- Local calendar-day number for an epoch.
local function epochDayNum(epoch)
  local t = os.date("*t", epoch)
  return dayNum(t.year, t.month, t.day)
end

-- Resolve a "now" argument (UTC stamp or nil) to an epoch.
local function nowEpoch(nowStr)
  if nowStr ~= nil then
    return M.stampToEpoch(nowStr)
  end
  return os.time()
end

function M.isOverdue(task, nowStr)
  local due = task["due"]
  if type(due) ~= "string" or due == "" then
    return false
  end
  local dueE = M.stampToEpoch(due)
  local nowE = nowEpoch(nowStr)
  if dueE == nil or nowE == nil then
    return false
  end
  return dueE < nowE
end

function M.isDueToday(task, nowStr)
  local due = task["due"]
  if type(due) ~= "string" or #due < 8 then
    return false
  end
  local dueE = M.stampToEpoch(due)
  local nowE = nowEpoch(nowStr)
  if dueE == nil or nowE == nil then
    return false
  end
  return epochDayNum(dueE) == epochDayNum(nowE)
end

function M.isDueWeek(task, nowStr)
  local due = task["due"]
  if type(due) ~= "string" or #due < 8 then
    return false
  end
  local dueE = M.stampToEpoch(due)
  local nowE = nowEpoch(nowStr)
  if dueE == nil or nowE == nil then
    return false
  end
  local diff = epochDayNum(dueE) - epochDayNum(nowE)
  return diff >= 0 and diff <= 7
end

function M.isWaiting(task, nowStr)
  -- Waiting is derived (+WAITING virtual tag): stored status stays "pending"
  -- while the wait date is in the future.
  local wait = task["wait"]
  if type(wait) ~= "string" or wait == "" then
    return (task["status"] or "") == "waiting"
  end
  local waitE = M.stampToEpoch(wait)
  local nowE = nowEpoch(nowStr)
  if waitE == nil or nowE == nil then
    return (task["status"] or "") == "waiting"
  end
  return waitE > nowE
end

function M.formatDue(due)
  -- Rendered in LOCAL time: export stamps are UTC, and showing them raw
  -- puts midnight tasks on the wrong day off-UTC. Local text also
  -- round-trips through task's own (local) date parser on save.
  local epoch = M.stampToEpoch(due)
  if epoch == nil then
    -- Lenient fallback for date-only stamps: show the calendar date as-is.
    if type(due) == "string" and #due >= 8 then
      local y = tonumber(string.sub(due, 1, 4))
      local mo = tonumber(string.sub(due, 5, 6))
      local d = tonumber(string.sub(due, 7, 8))
      if y ~= nil and mo ~= nil and d ~= nil then
        return string.format("%04d-%02d-%02d", y, mo, d)
      end
    end
    return ""
  end
  if type(due) == "string" and #due >= 15 then
    return os.date("%Y-%m-%d %H:%M", epoch)
  end
  return os.date("%Y-%m-%d", epoch)
end

function M.dueColor(task, nowStr)
  if M.isOverdue(task, nowStr) then
    return "error"
  end
  if M.isDueToday(task, nowStr) then
    return "primary"
  end
  return "on_surface_variant"
end

function M.priorityWeight(pri)
  if pri == "H" then
    return 3
  elseif pri == "M" then
    return 2
  elseif pri == "L" then
    return 1
  end
  return 0
end

function M.decodeExport(raw)
  if type(raw) ~= "string" or noctalia.string.trim(raw) == "" then
    return {}
  end
  local ok, val, derr = pcall(noctalia.json.decode, raw)
  if not ok or type(val) ~= "table" then
    local why = ""
    if type(derr) == "string" and derr ~= "" then
      why = ": " .. derr
    end
    return nil, noctalia.tr("status.decode_error") .. why
  end
  return val
end

function M.isMissingRc(err)
  -- Locks, parse errors and version mismatches must NOT offer Initialize.
  if type(err) ~= "string" then
    return false
  end
  local e = string.lower(err)
  return string.find(e, "rc file", 1, true) ~= nil
    or string.find(e, "could not read", 1, true) ~= nil
    or string.find(e, "no such file", 1, true) ~= nil
end

-- filter: { q, status, project, tag, pri, due }
function M.filterTasks(tasks, filter)
  local out = {}
  local q = ""
  local status = "pending"
  local project = ""
  local tag = ""
  local pri = ""
  local due = "all"
  if filter ~= nil then
    if type(filter["q"]) == "string" then
      q = string.lower(noctalia.string.trim(filter["q"]))
    end
    if type(filter["status"]) == "string" then
      status = filter["status"]
    end
    if type(filter["project"]) == "string" then
      project = filter["project"]
    end
    if type(filter["tag"]) == "string" then
      tag = filter["tag"]
    end
    if type(filter["pri"]) == "string" then
      pri = filter["pri"]
    end
    if type(filter["due"]) == "string" then
      due = filter["due"]
    end
  end
  local now = M.nowUtcStr()
  for _, t in ipairs(tasks) do
    local ok = true
    local st = t["status"] or "pending"
    if status == "pending" then
      -- Actionable pending only, like the `next` report (hidden waiting excluded).
      ok = st == "pending" and not M.isWaiting(t, now)
    elseif status == "waiting" then
      ok = st == "waiting" or M.isWaiting(t, now)
    elseif status == "completed" then
      ok = st == "completed"
    elseif status == "all" then
      ok = true
    else
      ok = st == "pending"
    end
    if ok and project ~= "" and not M.inProject(t["project"] or "", project) then
      ok = false
    end
    if ok and tag ~= "" then
      local tags = t["tags"]
      if tag:sub(1, 1) == "-" then
        local want = tag:sub(2)
        if type(tags) == "table" then
          for _, tg in ipairs(tags) do
            if tg == want then
              ok = false
              break
            end
          end
        end
      else
        local want = tag
        if want:sub(1, 1) == "+" then
          want = want:sub(2)
        end
        local found = false
        if type(tags) == "table" then
          for _, tg in ipairs(tags) do
            if tg == want then
              found = true
              break
            end
          end
        end
        if not found then
          ok = false
        end
      end
    end
    if ok and pri ~= "" then
      if pri == "none" then
        ok = t["priority"] == nil
      else
        ok = (t["priority"] or "") == pri
      end
    end
    if ok and due ~= "all" then
      if due == "overdue" then
        ok = M.isOverdue(t, now)
      elseif due == "today" then
        ok = M.isDueToday(t, now)
      elseif due == "week" then
        ok = M.isDueWeek(t, now)
      elseif due == "nodue" then
        ok = t["due"] == nil
      end
    end
    if ok and q ~= "" then
      local hay = string.lower(
        tostring(t["description"] or "")
          .. " "
          .. tostring(t["project"] or "")
          .. " "
          .. tostring(t["uuid"] or "")
      )
      local tags = t["tags"]
      if type(tags) == "table" then
        hay = hay .. " " .. string.lower(table.concat(tags, " "))
      end
      if not string.find(hay, q, 1, true) then
        ok = false
      end
    end
    if ok then
      table.insert(out, t)
    end
  end
  return out
end

function M.sortTasks(tasks, sortKey)
  local key = sortKey or "urgency"
  table.sort(tasks, function(a, b)
    if key == "due" then
      local da = a["due"]
      local db = b["due"]
      if da == nil and db == nil then
        return (a["urgency"] or 0) > (b["urgency"] or 0)
      elseif da == nil then
        return false
      elseif db == nil then
        return true
      else
        return da < db
      end
    elseif key == "entry" then
      return (a["entry"] or "") > (b["entry"] or "")
    elseif key == "priority" then
      local pa = M.priorityWeight(a["priority"])
      local pb = M.priorityWeight(b["priority"])
      if pa == pb then
        return (a["urgency"] or 0) > (b["urgency"] or 0)
      end
      return pa > pb
    else
      return (a["urgency"] or 0) > (b["urgency"] or 0)
    end
  end)
  return tasks
end

function M.collectProjects(tasks)
  local map = {}
  for _, t in ipairs(tasks) do
    if (t["status"] or "pending") == "pending" then
      local p = t["project"]
      if type(p) == "string" and p ~= "" then
        map[p] = (map[p] or 0) + 1
      end
    end
  end
  local names = {}
  for name in pairs(map) do
    table.insert(names, name)
  end
  table.sort(names)
  return names, map
end

-- Union of project names across open and completed tasks (for dropdowns
-- that must offer completed-only projects too).
function M.collectAllProjects(tasks, completed)
  local seen = {}
  local names = {}
  local function add(list)
    if type(list) ~= "table" then
      return
    end
    for _, t in ipairs(list) do
      local p = t["project"]
      if type(p) == "string" and p ~= "" and not seen[p] then
        seen[p] = true
        table.insert(names, p)
      end
    end
  end
  add(tasks)
  add(completed)
  table.sort(names)
  return names
end

function M.collectTags(tasks)
  local map = {}
  for _, t in ipairs(tasks) do
    if (t["status"] or "pending") == "pending" then
      local tags = t["tags"]
      if type(tags) == "table" then
        for _, tg in ipairs(tags) do
          if not M.isVirtualTag(tg) then
            map[tg] = (map[tg] or 0) + 1
          end
        end
      end
    end
  end
  local names = {}
  for name in pairs(map) do
    table.insert(names, name)
  end
  table.sort(names)
  return names, map
end

function M.computeMeta(tasks, completed)
  local now = M.nowUtcStr()
  local meta = {
    pending = 0,
    waiting = 0,
    overdue = 0,
    today = 0,
    active = 0,
    completed = 0,
    total = #tasks,
  }
  for _, t in ipairs(tasks) do
    local st = t["status"] or "pending"
    if st == "pending" then
      if M.isWaiting(t, now) then
        meta.waiting += 1
      else
        meta.pending += 1
        if t["start"] ~= nil then
          meta.active += 1
        end
        if M.isOverdue(t, now) then
          meta.overdue += 1
        end
        if M.isDueToday(t, now) then
          meta.today += 1
        end
      end
    elseif st == "waiting" then
      meta.waiting += 1
    end
  end
  if type(completed) == "table" then
    meta.completed = #completed
  end
  return meta
end

-- Scoped statistics for the Stats tab. project == "" means everything.
-- Returns { meta, vals (14 normalized day buckets), counts, oldest, oldestAgeDays }.
function M.projectStats(tasks, completed, project)
  local t = {}
  for _, x in ipairs(tasks) do
    if M.inProject(tostring(x["project"] or ""), project) then
      table.insert(t, x)
    end
  end
  local c = {}
  if type(completed) == "table" then
    for _, x in ipairs(completed) do
      if M.inProject(tostring(x["project"] or ""), project) then
        table.insert(c, x)
      end
    end
  end
  local meta = M.computeMeta(t, c)

  -- Bucketed on LOCAL calendar days: UTC components would split days
  -- at the wrong boundary off-UTC.
  local todayN = epochDayNum(os.time())

  local byDay = {}
  for i = 1, 14 do
    byDay[i] = 0
  end
  local maxV = 1
  for _, x in ipairs(c) do
    local endE = M.stampToEpoch(x["end"])
    if endE ~= nil then
      local diff = todayN - epochDayNum(endE)
      if diff >= 0 and diff < 14 then
        local idx = 14 - diff
        byDay[idx] += 1
        if byDay[idx] > maxV then
          maxV = byDay[idx]
        end
      end
    end
  end
  local vals = {}
  for i = 1, 14 do
    vals[i] = byDay[i] / maxV
  end

  local oldest = nil
  for _, x in ipairs(t) do
    if (x["status"] or "") == "pending" then
      if oldest == nil or (x["entry"] or "") < (oldest["entry"] or "") then
        oldest = x
      end
    end
  end
  local oldestAge = nil
  if oldest ~= nil then
    local entryE = M.stampToEpoch(oldest["entry"])
    if entryE ~= nil then
      oldestAge = todayN - epochDayNum(entryE)
      if oldestAge < 0 then
        oldestAge = 0
      end
    end
  end

  return { meta = meta, vals = vals, counts = byDay, oldest = oldest, oldestAgeDays = oldestAge }
end

-- Explicit local calendar date N days back (YYYY-MM-DD) for windowed
-- completed queries. Noon-anchored against DST edges.
function M.cutoffDate(daysBack)
  local t = os.date("*t")
  local noon = os.time({ year = t.year, month = t.month, day = t.day, hour = 12 })
  return os.date("%Y-%m-%d", noon - (daysBack or 14) * 86400)
end

-- Project membership with hierarchical rollup: "Home" also matches
-- "Home.Kitchen", mirroring how taskwarrior itself treats dotted projects.
function M.inProject(taskProj, filter)
  if filter == "" then
    return true
  end
  if taskProj == filter then
    return true
  end
  return string.sub(taskProj, 1, #filter + 1) == filter .. "."
end

-- Build argv prefix: { bin, [rc:<path>], rc.confirmation=no, ...rest }
function M.withBase(bin, rcPath, extra)
  local argv = {}
  table.insert(argv, bin)
  if type(rcPath) == "string" and rcPath ~= "" then
    table.insert(argv, "rc:" .. rcPath)
  end
  table.insert(argv, "rc.confirmation=no")
  if type(extra) == "table" then
    for _, a in ipairs(extra) do
      table.insert(argv, a)
    end
  end
  return argv
end

return M
