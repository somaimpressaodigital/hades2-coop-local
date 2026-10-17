-- Own Lua expiry marker only; no native epoch or health/state rollback.
local M={};local latest=setmetatable({},{__mode='k'});local last=setmetatable({},{__mode='k'})
local function clock(game)
 local t=game._worldTimeUnmodified
 if type(t)=='number' and t==t then return t end
end
function M.Read(victim)
 local s=last[victim];if not s then return nil end
 local current=s.Players.GetHero(s.Player)
 return {State=s.State,Reason=s.Reason,StartedWorldTime=s.StartedWorldTime,ExpiryAttemptWorldTime=s.ExpiryAttemptWorldTime,
  CompletedWorldTime=s.CompletedWorldTime,WorldTimeField='_worldTimeUnmodified',ActorAtStart=s.ActorAtStart,
  ActorCurrent=current and current.ObjectId,Player=s.Player,ScopeIdentity=tostring(s),Latest=latest[victim]==s,
  RunCurrent=s.Game.CurrentRun==s.Run,MapCurrent=s.Game.MapState==s.Map,SessionCurrent=s.Game.SessionMapState==s.Session,
  HeroCurrent=current==s.Hero,FlagStorageCurrent=s.Hero.InvulnerableFlags==s.Flags,
  LastProbeStatus=s.LastProbeStatus,LastProbeValidated=s.LastProbeValidated,CaughtError=s.CaughtError,
  ClearAttemptWorldTime=s.ClearAttemptWorldTime,ClearReturned=s.ClearReturned,NativeInvulnerableObserved=s.NativeInvulnerableObserved,OwnFlagPresent=s.Flags and s.Flags.LocalDuoRescue~=nil and s.Flags.LocalDuoRescue~=false or false,MaximumWaitSeconds=2.5,NativeReceipt=false}
end
local function report(s,state,reason,write)
 s.State=state;s.Reason=reason;s.CompletedWorldTime=clock(s.Game)
 if write then write('rescueExpiryState','state='..state..' reason='..tostring(reason)..' scope='..tostring(s)
  ..' world='..tostring(s.CompletedWorldTime)..' start='..tostring(s.StartedWorldTime)..' attempt='..tostring(s.ExpiryAttemptWorldTime)
  ..' actorStart='..tostring(s.ActorAtStart)..' actorCurrent='..tostring(s.Players.GetHero(s.Player)and s.Players.GetHero(s.Player).ObjectId)
  ..' probe='..tostring(s.LastProbeStatus)..' error='..tostring(s.CaughtError)..' maxWait=2.5')end
end
function M.Protect(game,players,context,victim,write)
 local player=players.GetPlayerByHero(victim)
 assert(player and players.GetHero(player)==victim and not victim.IsDead,'Current rescue victim required')
 local scope={Run=game.CurrentRun,Map=game.MapState,Session=game.SessionMapState,Hero=victim,Player=player,ActorAtStart=victim.ObjectId}
 scope.Game=game;scope.Players=players;scope.State='protected';scope.StartedWorldTime=clock(game);last[victim]=scope
 context.RunWithHeroContext(victim,game.SetPlayerInvulnerable,'LocalDuoRescue')
 scope.Flags=victim.InvulnerableFlags;latest[victim]=scope
 game.thread(function()
  game.waitUnmodified(1.5)
  scope.ExpiryAttemptWorldTime=clock(game)
  for attempt=1,21 do
   if latest[victim]~=scope then report(scope,'superseded','A newer local rescue expiry owns this hero',write);return end
   if game.CurrentRun~=scope.Run or game.MapState~=scope.Map or game.SessionMapState~=scope.Session then latest[victim]=nil;report(scope,'foreignscope','Run/Map/Session changed',write);return end
   if players.GetHero(player)~=victim or victim.InvulnerableFlags~=scope.Flags or victim.IsDead then latest[victim]=nil;report(scope,'foreignscope','Hero/flag storage changed or hero dead',write);return end
   local a,b=players.GetHero(1),players.GetHero(2)
   local ok,probe=false,nil
   if a and b and a.ObjectId and b.ObjectId and type(game.LocalDuoNativeBindingProbe)=='function'then ok,probe=pcall(game.LocalDuoNativeBindingProbe,a.ObjectId,b.ObjectId)end
   scope.LastProbeValidated=ok and probe and probe.Validated==true or false
   scope.LastProbeStatus=ok and type(probe)=='table'and probe.Status or nil
   scope.CaughtError=not ok and tostring(probe)or nil
   if ok and probe and probe.Validated==true and probe.Player1NativeId==a.ObjectId and probe.Player2NativeId==b.ObjectId then
    scope.State='clearing';scope.ClearAttemptWorldTime=clock(game)
    -- No automatic replay after a possible partial native clear.
    local cleared,clearError=pcall(context.RunWithHeroContext,victim,game.SetPlayerVulnerable,'LocalDuoRescue')
    scope.ClearReturned=cleared
    if not cleared then
     scope.CaughtError=tostring(clearError)
     if type(game.IsInvulnerable)=='function' and victim.ObjectId then
      local read,value=pcall(game.IsInvulnerable,{Id=victim.ObjectId})
      if read and type(value)=='boolean'then scope.NativeInvulnerableObserved=value end
     end
     report(scope,'clear-error','Current context/vulnerability clear threw; native state uncertain, no retry',write)
     return
    end
    latest[victim]=nil
    for _,hero in players.PlayersIterator()do
     if hero.InvulnerableFlags and hero.InvulnerableFlags.LocalDuoRescue then scope.Run.InvulnerableFlags.LocalDuoRescue=true end
    end
    report(scope,'expired','Current actor ownership verified; own rescue flag released',write)
    return
   end
   if attempt<21 then game.waitUnmodified(0.05)end
  end
  report(scope,'refused','Native ownership unknown after bounded retry; protection retained',write)
 end)
end
return M
