-- Operational Profile3 bridge, separate from strict native authority contracts.
-- Uses existing generated pools. Construction performs no gameplay calls.
local M={}
function M.New(d)
 assert(d and d.Host and d.Context and d.Players and d.Game and d.Gate)
 assert(type(d.Devices)=='function'and type(d.Key)=='function')
 local service={Records={},BySource=setmetatable({},{__mode='k'}),Enabled=true,NativeGenerationKnown=false}
 local function current(r)
  if d.Game.CurrentRun~=r.Run or r.Run.CurrentRoom~=r.Room or d.Game.MapState~=r.Map then return false end
  for p=1,2 do
   local hero,source=r.Args.heroes[p],r.Args.sources[p]
   if d.Players.GetHero(p)~=hero or hero.ObjectId~=r.Ids[p] or hero.IsDead
    or source.LocalDuoOwner~=p or source.LocalDuoBundle~=r.Bundle then return false end
  end
  return true
 end
 local function handled(reason,route)
  return {Handled=true,Route=route or 'waiting',SuppressAutoOther=true,Reason=reason}
 end
 function service:BeforeUseLoot(loot,user)
  if not self.Enabled or d.Gate.IsTestProfile()~=true then return {Handled=false}end
  local prior=self.BySource[loot]
  if prior then
   if not current(prior)then return handled('scene-changed')end
   if prior.Phase=='closed'and prior.Args.sources[1].LocalDuoCommonRoot then
    if d.Game.AreScreensActive()then return handled('Feche o menu de pausa antes de escolher.')end
    local checked,allowed,reason=pcall(d.Host.CanOpen,d.Host,prior.Args)
    if not checked or allowed~=true then return handled(checked and reason or tostring(allowed))end
    prior.Phase='opening'
    local opened,handle,created,report=pcall(d.Host.Open,d.Host,prior.Args)
    if not opened or not handle or not handle.Session or handle.Session.State~='active'then
     prior.Phase='uncertain';prior.Error=opened and report or handle;return handled('Não foi possível reabrir a escolha com segurança.')
    end
    prior.Handle=handle;prior.Phase='active';return handled('Mesmas ofertas reabertas.','duo')
   end
   if prior.Phase=='active'then return handled('same-active-session','duo')end
   return handled(prior.Phase)
  end
  local run=d.Game.CurrentRun;local room=run and run.CurrentRoom
  local map=d.Game.MapState
  if not room or not map or type(d.Game.RequiredKillEnemies)~='table' or next(d.Game.RequiredKillEnemies)
   or d.Game.AreScreensActive() or not loot.LocalDuoBundle then return {Handled=false}end
  local sources=d.SourcesFor and d.SourcesFor(loot)
  if not sources then sources={}
  for _,source in pairs(map.RoomRequiredObjects or {})do
   if source.LocalDuoBundle==loot.LocalDuoBundle and source.OnUsedFunctionName=='UseLoot'
    and (source.LocalDuoOwner==1 or source.LocalDuoOwner==2)then
    if sources[source.LocalDuoOwner]then return {Handled=false,Reason='ambiguous-personal-pair'}end
    sources[source.LocalDuoOwner]=source
   end
  end
  end
  if sources[loot.LocalDuoOwner]~=loot or not sources[1]or not sources[2]then return {Handled=false}end
  local heroes={d.Players.GetHero(1),d.Players.GetHero(2)}
  if not heroes[1]or not heroes[2]or heroes[1]==heroes[2]or heroes[1].ObjectId==heroes[2].ObjectId
   or heroes[1].IsDead or heroes[2].IsDead or (user~=heroes[1]and user~=heroes[2])then return {Handled=false}end
  for p=1,2 do
   if type(sources[p].UpgradeOptions)~='table' or #sources[p].UpgradeOptions==0
    or sources[p].LocalDuoConsumed then return {Handled=false}end
  end
  if sources[1].UpgradeOptions==sources[2].UpgradeOptions then return {Handled=false,Reason='aliased-pools'}end
  local devices=d.Devices()
  if not devices or devices[1]==nil or devices[2]==nil or devices[1]==devices[2]then return {Handled=false}end
  local key=d.Key(run,room,loot.LocalDuoBundle)
  assert(type(key)=='string'and key~='','Explicit session key required')
  if self.Records[key]then return handled('existing-session-key')end
  local args={key=key,room=room,heroes=heroes,sources=sources,devices=devices,names=d.Names and d.Names(heroes)}
  local r={Run=run,Room=room,Map=map,Bundle=loot.LocalDuoBundle,Ids={heroes[1].ObjectId,heroes[2].ObjectId},Args=args,Phase='checking'}
  self.Records[key]=r;self.BySource[sources[1]]=r;self.BySource[sources[2]]=r
  local checked,allowed,reason=pcall(d.Host.CanOpen,d.Host,args)
  if not checked or allowed~=true or not current(r)then
   -- CanOpen is read-only by the existing host contract; no acquisition/application occurred.
   self.Records[key]=nil
   if self.BySource[sources[1]]==r then self.BySource[sources[1]]=nil end
   if self.BySource[sources[2]]==r then self.BySource[sources[2]]=nil end
   return {Handled=false,Reason=checked and reason or tostring(allowed)}
  end
  if d.BeforeOpen then
   local ok,allowed,reason=pcall(d.BeforeOpen,args)
   if not ok or allowed~=true then r.Phase='uncertain';r.Error=ok and reason or allowed;return handled('shop-payment-not-completed')end
  end
  r.Phase='opening'
  local opened,handle,created,report=pcall(d.Host.Open,d.Host,args)
  if not opened or not handle then
   r.Phase='uncertain';r.Error=opened and report or handle
   return handled('open-failed-after-reservation') -- never call stock pickup after possible effects
  end
  r.Handle=handle;r.Phase='active';return handled('two-panels-open','duo')
 end
 function service:Update()
  if not self.Enabled or self.Updating then return end
  self.Updating=true
  local ok,err=pcall(d.Host.Update,d.Host)
  self.Updating=false
  if not ok then self.Error=err end
  for _,r in pairs(self.Records)do
   if r.Handle and r.Handle.Session and r.Handle.Session.State=='closed'then r.Phase='closed'end
  end
 end
 return service
end
return M
