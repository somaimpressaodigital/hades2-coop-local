-- Intentional campaign-only end requested by the pause UI. Actual native death path;
-- no HP/last-stand/rescue counters, campaign records, wins or save flags manufactured here.
local Players=ModRequire 'CoopPlayers.lua'
local Context=ModRequire 'HeroContext.lua'
local M={};local pending,last
local function same(r)
 if not r or CurrentRun~=r.Run or CurrentRun.CurrentRoom~=r.Room or MapState~=r.Map or SessionMapState~=r.Session then return false end
 for p=1,2 do if Players.GetHero(p)~=r.Heroes[p]or r.Heroes[p].ObjectId~=r.Ids[p]then return false end end
 return true
end
local function refresh()
 if pending and not same(pending)then last=pending;pending=nil end
end
local function arenaOwned()
 local arena=LocalDuoArenaRuntime
 if arena==nil then return false end
 if type(arena)~='table'or type(arena.IsDuelSceneOwned)~='function'then return true end
 local ok,value=pcall(arena.IsDuelSceneOwned,arena)
 return not ok or value~=false -- unknown/stale Arena lifetime is never campaign permission
end
function M.IsEnding(run)
 return pending~=nil and pending.Run==run and same(pending)and pending.State~='failed'
end
function M.CanRequest()
 refresh()
 if LocalDuoCoopModeActive~=true or Players.GetPlayersCount()~=2 then return false,'Encerramento da dupla exige campanha coop'end
 if arenaOwned()then return false,'A Arena privada possui encerramento separado'end
 if CurrentHubRoom or type(CurrentRun)~='table'or type(CurrentRun.CurrentRoom)~='table'
  or type(MapState)~='table'or type(SessionMapState)~='table'then return false,'Nenhuma corrida de campanha em andamento'end
 if pending or CurrentRun.LocalDuoEnding or SessionMapState.HandlingDeath then return false,'Encerramento da corrida já iniciado'end
 local a,b=Players.GetHero(1),Players.GetHero(2);local main=Players.GetMainHero()
 if type(a)~='table'or type(b)~='table'or a==b or type(a.ObjectId)~='number'or type(b.ObjectId)~='number'
  or a.ObjectId<=0 or b.ObjectId<=0 or a.ObjectId==b.ObjectId or(main~=a and main~=b)then return false,'Referências atuais da dupla indisponíveis'end
 -- One player may already be fallen. Do not require both alive to end the run.
 if type(KillHero)~='function'or type(Context.ScheduleServiceThread)~='function'
  or type(Context.RunWithHeroContextAwait)~='function'or type(waitUnmodified)~='function'then return false,'Fluxo nativo de morte indisponível'end
 return true
end
function M.ReadStatus()
 refresh();local r=pending or last
 if not r then return {State='idle',NativeGameplayValidated=false}end
 return {State=r.State,Accepted=r.Accepted,Error=r.Error,ActorIds={r.Ids[1],r.Ids[2]},
  NativeCallbackInvoked=r.Invoked==true,NativeCallbackReturnedNormally=r.Returned==true,NativeGameplayValidated=false}
end
function M.Request(triggerArgs)
 local allowed,why=M.CanRequest();if not allowed then return false,why end
 if triggerArgs~=nil and type(triggerArgs)~='table'then return false,'Argumentos nativos inválidos'end
 local args={};for k,v in pairs(triggerArgs or{})do args[k]=v end
 local a,b=Players.GetHero(1),Players.GetHero(2)
 local r={Run=CurrentRun,Room=CurrentRun.CurrentRoom,Map=MapState,Session=SessionMapState,
  Heroes={a,b},Ids={a.ObjectId,b.ObjectId},Main=Players.GetMainHero(),State='queued',Accepted=false}
 r.Victim=not r.Main.IsDead and r.Main or not a.IsDead and a or not b.IsDead and b or r.Main
 pending=r;last=r -- actual pending intent, before asynchronous cleanup; never a native receipt
 local function fail(err)
  r.Error=tostring(err)
  if r.Run.LocalDuoEnding or r.Session.HandlingDeath then r.State='failed_after_dispatch'
  else r.State='failed';if pending==r then pending=nil end end
 end
 local function worker()
  local ok,err=pcall(function()
   -- Native thread() resumes immediately: yield before any death/context work.
   waitUnmodified(0.01)
   assert(pending==r and same(r)and not CurrentHubRoom and not arenaOwned(),'Contexto da corrida mudou antes do encerramento')
   if r.Run.LocalDuoEnding or r.Session.HandlingDeath then r.State='terminal_already_started';return end
   r.State='dispatching'
   local result,reason=Context.RunWithHeroContextAwait(r.Victim,function()
    assert(pending==r and same(r)and not arenaOwned(),'Contexto da dupla mudou antes da morte')
    if r.Run.LocalDuoEnding or r.Session.HandlingDeath then return end
    r.Invoked=true
    return KillHero(r.Victim,args) -- existing RunHooks paired terminal path, then stock DeathLoopLogic once
   end)
   assert(result~=false,reason or'Fluxo nativo recusou o encerramento')
   r.Returned=true
   assert(r.Run.LocalDuoEnding or r.Session.HandlingDeath,'Fluxo terminal da dupla não foi iniciado')
   r.State='terminal_requested' -- not completion, no fabricated record/save proof
  end)
  if not ok then fail(err)end
 end
 local scheduled,err=pcall(Context.ScheduleServiceThread,worker)
 if not scheduled then fail(err);return false,r.Error end
 if r.State=='failed'or r.State=='failed_after_dispatch'then return false,r.Error end
 r.Accepted=true;return true -- accepted request only; UI must already be closed/unpaused
end
return M
