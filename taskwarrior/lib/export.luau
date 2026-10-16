--!nonstrict
-- Shared task-export readers. Service and panel entries run in separate VMs
-- but speak the same CLI; this keeps argv shapes and decode handling in one
-- place. Each function takes (bin, rcPath, cb) and calls back with a plain
-- value or nil + error string. Reads pass rc.gc=off so they never contend
-- with concurrent writes.

local tasklib = require("./task.luau")

local X = {}

function X.fetchPending(bin, rcPath, cb)
  local argv = tasklib.withBase(bin, rcPath, {
    "rc.verbose=nothing",
    "rc.json.array=on",
    "rc.gc=off",
    "(status:pending or status:waiting)",
    "export",
  })
  noctalia.runAsync(argv, function(res)
    if res == nil then
      cb(nil, noctalia.tr("status.export_empty"))
      return
    end
    if res.exitCode ~= 0 then
      -- Keep stderr verbatim: it carries the missing-rc signal that
      -- decides between the Setup view and the plain error card.
      local err = tostring(res.stderr or "")
      if err == "" then
        err = noctalia.tr("status.export_failed_exit", { code = tostring(res.exitCode) })
      end
      cb(nil, err)
      return
    end
    local list, derr = tasklib.decodeExport(res.stdout or "")
    if list == nil then
      cb(nil, derr or noctalia.tr("status.export_unreadable"))
      return
    end
    cb(list)
  end)
end

function X.fetchWindowed(bin, rcPath, daysBack, cb)
  local argv = tasklib.withBase(bin, rcPath, {
    "rc.verbose=nothing",
    "rc.json.array=on",
    "rc.gc=off",
    "status:completed",
    "end.after:" .. tasklib.cutoffDate(daysBack or 14),
    "export",
  })
  noctalia.runAsync(argv, function(res)
    if res == nil or res.exitCode ~= 0 then
      cb(nil, noctalia.tr("status.history_unreadable"))
      return
    end
    local list, derr = tasklib.decodeExport(res.stdout or "")
    if list == nil then
      cb(nil, derr or noctalia.tr("status.history_unreadable"))
      return
    end
    cb(list)
  end)
end

function X.fetchDoneTotal(bin, rcPath, cb)
  local argv = tasklib.withBase(bin, rcPath, { "status:completed", "count" })
  noctalia.runAsync(argv, function(res)
    if res == nil or res.exitCode ~= 0 then
      cb(nil, noctalia.tr("status.count_unreadable"))
      return
    end
    local n = tonumber(noctalia.string.trim(res.stdout or ""))
    if n == nil then
      cb(nil, noctalia.tr("status.count_unreadable"))
      return
    end
    cb(n)
  end)
end

function X.fetchFullCompleted(bin, rcPath, cb)
  local argv = tasklib.withBase(bin, rcPath, {
    "rc.verbose=nothing",
    "rc.json.array=on",
    "rc.gc=off",
    "status:completed",
    "export",
  })
  noctalia.runAsync(argv, function(res)
    if res == nil or res.exitCode ~= 0 then
      cb(nil, noctalia.tr("status.history_unreadable"))
      return
    end
    local list, derr = tasklib.decodeExport(res.stdout or "")
    if list == nil then
      cb(nil, derr or noctalia.tr("status.history_unreadable"))
      return
    end
    cb(list)
  end)
end

return X
