--!nonstrict
-- Headless [[service]] entry: polls `task export` and publishes plain data
-- to noctalia.state for the widget + panel. Owns backend health detection.

local tasklib = require("./lib/task.luau")
local X = require("./lib/export.luau")

local bin = noctalia.getConfig("task_bin")
if type(bin) ~= "string" or bin == "" then
  bin = "task"
end
local rcPath = noctalia.getConfig("taskrc_path")
if type(rcPath) ~= "string" then
  rcPath = ""
end
local pollSeconds = noctalia.getConfig("poll_seconds")
if type(pollSeconds) ~= "number" then
  pollSeconds = 15
end
pollSeconds = math.max(5, math.min(300, math.floor(pollSeconds)))

local fetching = false
local pollCount = 0

local function publishBackend(ok, err)
  local e = err or ""
  -- Only missing-rc failures offer the Setup view; locks, parse errors and
  -- version mismatches get the plain error card instead.
  noctalia.state.set("backend", { ok = ok, error = e, setup = (not ok) and tasklib.isMissingRc(e) })
end

local function publishEmpty(reason)
  noctalia.state.set("tasks", {})
  noctalia.state.set("completed", {})
  noctalia.state.set("meta", {
    pending = 0,
    waiting = 0,
    overdue = 0,
    today = 0,
    active = 0,
    completed = 0,
    total = 0,
  })
  noctalia.state.set("last_sync", 0)
  if reason ~= nil then
    noctalia.state.set("sync_error", reason)
  end
end

-- Lightweight completed reads: a 14-day window for the graph plus cheap
-- totals. A full-history export on every poll would churn parse + state
-- copies for data nobody displays past the window.
local winCompleted = {}
local doneTotal = 0

local function parseAndPublishPending(pending)
  local meta = tasklib.computeMeta(pending, winCompleted)
  meta.completed = doneTotal
  noctalia.state.set("tasks", pending)
  noctalia.state.set("completed", winCompleted)
  noctalia.state.set("meta", meta)
  noctalia.state.set("last_sync", os.time())
  noctalia.state.set("sync_error", "")
  publishBackend(true, "")
end

local function fetchCompleted(pending)
  X.fetchWindowed(bin, rcPath, 14, function(win, werr)
    if win ~= nil then
      winCompleted = win
    elseif werr ~= nil then
      noctalia.log(werr)
    end
    X.fetchDoneTotal(bin, rcPath, function(total)
      fetching = false
      if total ~= nil then
        doneTotal = total
      end
      parseAndPublishPending(pending)
    end)
  end)
end

local function fetchNow()
  if fetching then
    return
  end
  if not noctalia.commandExists(bin) then
    publishBackend(false, "Task binary not found: " .. bin)
    publishEmpty("missing binary")
    return
  end
  fetching = true
  pollCount += 1
  X.fetchPending(bin, rcPath, function(pending, err)
    if pending == nil then
      fetching = false
      publishBackend(false, err or "task export failed")
      publishEmpty(err)
      return
    end
    -- Refresh the lightweight completed reads every 4th poll.
    if pollCount % 4 == 0 then
      fetchCompleted(pending)
    else
      fetching = false
      parseAndPublishPending(pending)
    end
  end)
end

noctalia.setUpdateInterval(pollSeconds * 1000)

function update()
  fetchNow()
end

-- Offline testing / scripting surface:
--   noctalia msg plugin kurai/taskwarrior:sync all refresh
function onIpc(event, _payload)
  if event == "refresh" then
    fetchNow()
  end
end

function onConfigChanged()
  local nb = noctalia.getConfig("task_bin")
  if type(nb) == "string" and nb ~= "" then
    bin = nb
  end
  local nr = noctalia.getConfig("taskrc_path")
  if type(nr) == "string" then
    rcPath = nr
  end
  local np = noctalia.getConfig("poll_seconds")
  if type(np) == "number" then
    pollSeconds = math.max(5, math.min(300, math.floor(np)))
    noctalia.setUpdateInterval(pollSeconds * 1000)
  end
  fetchNow()
end

-- Panel/widgets bump this key after a mutation to skip waiting for poll.
noctalia.state.watch("refreshReq", function(_value)
  fetchNow()
end)

-- Initial state so widget renders before first export lands.
publishEmpty("")
fetchNow()
