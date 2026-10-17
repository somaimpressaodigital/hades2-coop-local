-- Drain existing personal sessions before the world/actor identity is destroyed.
-- No forced closed state, native old-id release, trait rollback or runtime replacement.
local M={}
function M.HasPending(game)
 if game.LocalDuoCoopModeActive~=true then return false end
 local runtime=game.LocalDuoRewardRouting
 if not runtime or runtime.Profile3Only~=true or not runtime.Host or type(runtime.Host.Records)~='table' then return false end
 for _,r in pairs(runtime.Host.Records)do
  if (r.Handle and (not r.Handle.Session or r.Handle.Session.State~='closed'))or(r.EntryFault and not r.EmergencyDone)or(not r.Handle and not r.EntryFault)then return true end
 end
 return false
end
function M.Wait(game,players,reason,write)
 if game.LocalDuoCoopModeActive~=true then return true end
 local runtime=game.LocalDuoRewardRouting
 if not runtime or runtime.Profile3Only~=true or not runtime.Host or type(runtime.Host.Records)~='table' then return true end
 local service=runtime.Host
 local run,map,session,room=game.CurrentRun,game.MapState,game.SessionMapState,game.CurrentHubRoom or (game.CurrentRun and game.CurrentRun.CurrentRoom)
 local function refuse(why)
  runtime.PreTransitionError=reason..': '..tostring(why)
  if write then write('preTransitionBlocked',runtime.PreTransitionError)end
  return false,runtime.PreTransitionError
 end
 local function pending(r)
  return (r.Handle and (not r.Handle.Session or r.Handle.Session.State~='closed')) or (r.EntryFault and not r.EmergencyDone) or (not r.Handle and not r.EntryFault)
 end
 local function validate(r)
  if game.LocalDuoRewardRouting~=runtime or game.CurrentRun~=run or game.MapState~=map or game.SessionMapState~=session
   or (game.CurrentHubRoom or (game.CurrentRun and game.CurrentRun.CurrentRoom))~=room then return false,'World/router changed during cleanup' end
  local state,scope=r.State,r.Scope
  if not state or not scope or state.Run~=run or state.MapState~=map or state.SessionMapState~=session or scope.Room~=room
   or state.ActiveScreens~=game.ActiveScreens or state.ActiveScreenOrder~=game.ActiveScreenOrder then return false,'Pending record belongs to another world/registry' end
  local modal=r.Handle and r.Handle.Session
  if modal and r.Owner~=modal.Owner then return false,'Reward session owner changed' end
  local exitHeld=r.EntryFault and r.Acquired and r.Acquired.exits
  if modal then for _,lease in ipairs(modal.Leases or{})do if lease.Resource=='exits'and not lease.Released then exitHeld=true end end end
  if exitHeld and (not r.Flag or not r.Screen or state.ActiveScreens[r.Flag]~=r.Screen)then return false,'Foreign screen replaced own exit lease' end
  for p=1,2 do
   local hero=players.GetHero(p)
   if not hero or not scope.Heroes or scope.Heroes[p]~=hero or hero.IsDead or not hero.ObjectId then return false,'Pending hero/actor unavailable' end
   local lease=r.OperationalLeases and r.OperationalLeases[p]
   if lease and lease.ReleaseUncertain then return false,'Partial native release requires review' end
   if lease and lease.Owner~=r.Owner then return false,'Operational lease owner changed' end
   if lease and lease.FlagsOwned and hero.InvulnerableFlags~=lease.Flags then return false,'Foreign invulnerability storage replaced' end
   if lease and lease.InputStarted and not lease.InputReleased and (lease.ControlBlocks~=session.PlayerControlBlocks or lease.MoveBlocks~=session.PlayerMoveBlocks)then return false,'Foreign freeze storage replaced' end
  end
  if type(game.LocalDuoNativeBindingProbe)~='function' then return false,'Native binding reader unavailable' end
  local a,b=players.GetHero(1).ObjectId,players.GetHero(2).ObjectId
  local ok,probe=pcall(game.LocalDuoNativeBindingProbe,a,b)
  if not ok or not probe or probe.Validated~=true or probe.Player1NativeId~=a or probe.Player2NativeId~=b then return false,'Current native ownership not validated' end
  return true
 end
 -- At most ten seconds of engine coroutine waits; failed ownership never reaches stock transition.
 for attempt=1,201 do
  local records={}
  for _,r in pairs(service.Records)do if pending(r)then records[#records+1]=r end end
  if #records==0 then runtime.PreTransitionError=nil;return true end
  for _,r in ipairs(records)do local ok,why=validate(r);if not ok then return refuse(why)end end
  for _,r in ipairs(records)do
   local s=r.Handle and r.Handle.Session
   if s then
    local errors=#(s.Errors or{})
    local ok,why=pcall(function()
     if s.State~='stopping' and s.State~='cleanup' then s:Finish('pre-transition:'..reason)
     else s:RetryCleanup()end
    end)
    if not ok then return refuse(why)end
    if #(s.Errors or{})>errors then return refuse(s.Errors[#s.Errors])end
   end
  end
  -- EntryFault recovery uses the host's existing abort/secure/release journal.
  local ok,why=pcall(service.Update,service)
  if not ok then return refuse(why)end
  for _,r in ipairs(records)do if r.EmergencyError then return refuse(r.EmergencyError)end end
  local active=false
  for _,r in pairs(service.Records)do if pending(r)then active=true;break end end
  if not active then runtime.PreTransitionError=nil;return true end
  if attempt==201 then return refuse('Cleanup still busy after bounded wait; transition not executed')end
  game.waitUnmodified(0.05)
 end
end
return M
