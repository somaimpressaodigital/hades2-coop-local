-- Existing Entry/Model/Choices/Session/View wiring. No install, imports or engine effects.
local M={}
local function copy(value,seen)
 if type(value)~='table'then return value end
 seen=seen or {};if seen[value]then return seen[value]end
 local out={};seen[value]=out;for k,v in pairs(value)do out[copy(k,seen)]=copy(v,seen)end;return out
end
local function equal(a,b,seen)
 if type(a)~=type(b)then return false end
 if type(a)~='table'then return a==b end
 seen=seen or {};if seen[a]==b then return true end;seen[a]=b
 for k,v in pairs(a)do if not equal(v,b[k],seen)then return false end end
 for k in pairs(b)do if a[k]==nil then return false end end;return true
end
local function samePair(a,b)
 if a.room~=b.room then return false end
 for p=1,2 do if a.heroes[p]~=b.heroes[p]or a.sources[p]~=b.sources[p]
  or a.devices[p]~=b.devices[p]then return false end end;return true
end
function M.New(d)
 assert(d and d.Service and d.Service.Host,'Supply a fresh existing GameHost service')
 for _,key in ipairs({'PrepareOffer','Validate'})do assert(type(d[key])=='function','Missing '..key)end
 local service,host=d.Service,d.Service.Host
 assert(type(service.Open)=='function'and type(service.Update)=='function')
 assert(host.Context and type(host.Context.RunWithHeroContextAwait)=='function')
 assert(type(host.Context.GetCurrentHeroContext)=='function')
 assert(not next(service.Records or {}),'Do not replace adapters on an active host')
 local runtime={Records={},Service=service,NativeProof=false,OffersRegenerated=false}
 local originalModules=assert(host.Modules)
 local modules={};for key,value in pairs(originalModules)do modules[key]=value end
 -- This is the sole replacement: generate means read the prepared cache, never roll/select.
 modules.Adapter={New=function(adapterHost)
  return {
   runAs=function(hero,fn,...)return adapterHost.Context.RunWithHeroContextAwait(hero,fn,...)end,
   generate=function(hero,source,player)
    local key=source.LocalDuoUIRewardKey
    local record=runtime.Records[key]
    assert(record and record.Args.heroes[player]==hero and source.LocalDuoOwner==player,'Unknown cached owner')
    assert(source.ObjectId==record.SourceIds[player]and hero.ObjectId==record.ActorIds[player],'Cached actor/source changed')
    assert(d.Validate(record.Args)==true,'Scene changed before reading cached offers')
    return copy(record.Offers[player])
   end,
   apply=function(hero,source,choice,request)
    assert(choice.Owner==request.Player,'Wrong choice owner')
    return adapterHost.commitChoice(hero,source,choice,request)
   end,
  }
 end}
 host.Modules=modules -- private per-host map; frozen module files/table remain intact
 local function poolsCurrent(r,allowActorChange)
  if d.Validate(r.Args)~=true or host.Game.CurrentRun~=r.Run or not r.Run
   or r.Run.CurrentRoom~=r.Args.room or host.Game.MapState~=r.Map then return false end
  for p=1,2 do
   local source=r.Args.sources[p]
   if (not allowActorChange and r.Args.heroes[p].ObjectId~=r.ActorIds[p])or source.ObjectId~=r.SourceIds[p]
    or source.LocalDuoBundle~=r.Bundle then return false end
   if source.UpgradeOptions~=r.Pools[p]or #r.Pools[p]~=#r.Rows[p]then return false end
   for i,row in ipairs(r.Rows[p])do
    if r.Pools[p][i]~=row.Ref or not equal(row.Snapshot,row.Ref)then return false end
   end
  end;return true
 end
 local function refreshReady(r)
  if r.Phase~='ready' or r.RefreshChecking or service.Records[r.Args.key] or not r.VisibleIndices then return false end
  local changed=false
  for p=1,2 do if r.Args.heroes[p].ObjectId~=r.ActorIds[p] then changed=true end end
  if not changed then return false end
  if d.Validate(r.Args)~=true or host.Game.CurrentRun~=r.Run or not r.Run
   or r.Run.CurrentRoom~=r.Args.room or host.Game.MapState~=r.Map then return false end
  -- Existing service preflight validates current native bindings before allowing ID-only refresh.
  r.RefreshChecking=true
  local checked,allowed=pcall(service.CanOpen,service,r.Args)
  r.RefreshChecking=false
  if not checked or allowed~=true or r.Phase~='ready' or service.Records[r.Args.key]
   or not poolsCurrent(r,true) then return false end
  local old={ActorIds=r.ActorIds,Offers=r.Offers}
  r.Phase='refreshing';r.PreviousPreview=old
  r.ActorIds={r.Args.heroes[1].ObjectId,r.Args.heroes[2].ObjectId};r.Offers={}
  local ok,why=pcall(function()
   for p=1,2 do
    local selectable=0;r.Offers[p]={}
    for _,index in ipairs(r.VisibleIndices[p])do
     local raw=r.Rows[p][index].Snapshot
     local offer=host.Context.RunWithHeroContextAwait(r.Args.heroes[p],function()
      assert(host.Context.GetCurrentHeroContext()==r.Args.heroes[p],'Wrong refresh hero')
      return d.PrepareOffer(r.Args.heroes[p],copy(raw),p,r.Args.sources[p])
     end)
     assert(type(offer)=='table' and offer.ItemName==raw.ItemName and offer.Data,'Invalid refreshed offer')
     offer=copy(offer);offer.Owner=p;offer.Raw=offer.Raw or copy(raw)
     r.Offers[p][#r.Offers[p]+1]=offer
     if not offer.Blocked then selectable=selectable+1 end
     assert(r.Phase=='refreshing' and poolsCurrent(r),'Pool/scene/actor changed during refresh')
    end
    if r.Args.sources[1].LocalDuoCommonRoot then
     assert(selectable>0,'Jogador '..p..': estas opções exigem um fluxo de recompensa ainda não suportado. A coleta continua pendente.')
    else assert(selectable>0,'No compatible refreshed choice for this player')end
   end
  end)
  if not ok then
   r.Phase='rejected';r.Error=why
   r.Rejection={Reason=tostring(why),FallbackVanilla=true,EffectsStarted=false}
   return false
  end
  r.RefreshCount=(r.RefreshCount or 0)+1;r.Phase='ready';return true
 end
 -- An explicit owner action is the only entry that may draw another native pool.
 local function rerollInfo(r,p)
  local hero,source=r.Args.heroes[p],r.Args.sources[p];local g=host.Game
  local bank=g.LocalDuoPersonalRerolls
  if not bank or type(bank.Read)~='function' or type(bank.CanAct)~='function' or type(bank.Spend)~='function'
   or type(bank.ReuseCounts)~='function' or type(host.rerollLoot)~='function'
   or type(g.HeroHasTrait)~='function' or type(g.RerollCosts)~='table'
   or type(g.GetRandomValue)~='function' or type(g.RandomSynchronize)~='function'
   or type(g.InvalidateCheckpoint)~='function' then return {Available=false,Reason='Alteração indisponível'}end
  assert(host.Context.GetCurrentHeroContext()==hero,'Wrong reroll-info context')
  if not bank.CanAct(r.Run,hero)or not g.HeroHasTrait('PanelRerollMetaUpgrade')or source.BlockReroll then
   return {Available=false,Reason='Alteração indisponível'}
  end
  local base=source.Name=='WeaponUpgrade'and g.RerollCosts.Hammer or g.RerollCosts.Boon
  if type(base)~='number' or base<=0 or base>=math.huge then return {Available=false,Reason='Alteração indisponível'}end
  local reuse=bank.ReuseCounts(r.Run,hero);local extra=reuse[source.ObjectId]or 0
  local balance=bank.Read(r.Run,hero);local cost=base+extra
  assert(type(extra)=='number'and extra>=0 and extra<math.huge and type(balance)=='number'
   and balance>=0 and balance<math.huge and cost==cost and cost<math.huge,'Invalid native reroll cost/balance')
  return {Available=balance>=cost,Cost=cost,Balance=balance,Reason=balance>=cost and nil or 'Saldo insuficiente'}
 end
 host.readOwnRerollInfo=function(key,p)
  local r=runtime.Records[key]
  if (p~=1 and p~=2)or not r or not poolsCurrent(r)or(r.RerollUncertain and r.RerollUncertain[p])then
   return {Available=false,Reason='Alteração indisponível'}
  end
  local ok,info=pcall(host.Context.RunWithHeroContextAwait,r.Args.heroes[p],rerollInfo,r,p)
  return ok and info or {Available=false,Reason='Alteração indisponível'}
 end
 host.requestOwnReroll=function(key,p,request)
  local r=runtime.Records[key]
  if (p~=1 and p~=2)or not r or r.Phase~='active' or not r.Handle or not r.Handle.Session
   or r.Handle.Session.State~='active' or not poolsCurrent(r)then return {Status='refused'}end
  local choices=r.Handle.Choices;local panel=choices and choices.Panels[p]
  if not panel or panel.Status~='applying' or choices.Closed or panel.Offers~=request.ExpectedOffers
   or(r.RerollUncertain and r.RerollUncertain[p])then return {Status='refused'}end
  r.RerollBusy=r.RerollBusy or {};if r.RerollBusy[p]then return {Status='refused'}end
  local hero,source=r.Args.heroes[p],r.Args.sources[p]
  local other=p==1 and 2 or 1
  local spent=false;r.RerollBusy[p]=true
  local function current(pool)
   if r.Handle.Session.State~='active' or choices.Closed or panel.Status~='applying'
    or r.Handle.Choices~=choices or panel.Offers~=request.ExpectedOffers
    or d.Validate(r.Args)~=true or host.Game.CurrentRun~=r.Run or host.Game.MapState~=r.Map
    or r.Run.CurrentRoom~=r.Args.room then return false end
   for owner=1,2 do
    local h,s=r.Args.heroes[owner],r.Args.sources[owner]
    if h.IsDead or h.ObjectId~=r.ActorIds[owner]or s.ObjectId~=r.SourceIds[owner]
     or s.LocalDuoOwner~=owner or s.LocalDuoBundle~=r.Bundle then return false end
   end
   if source.UpgradeOptions~=pool or r.Args.sources[other].UpgradeOptions~=r.Pools[other]then return false end
   if #r.Pools[other]~=#r.Rows[other]then return false end
   for i,row in ipairs(r.Rows[other])do if r.Pools[other][i]~=row.Ref or not equal(row.Snapshot,row.Ref)then return false end end
   local input=host.read(r.Args.devices[p])
   return input and input.Connected==true and input.Focused~=false
  end
  local ok,result=pcall(host.Context.RunWithHeroContextAwait,hero,function()
   assert(host.Context.GetCurrentHeroContext()==hero and current(r.Pools[p])and poolsCurrent(r),'Stale owner reroll')
   assert(not hero.LocalDuoBuildReceipts or not hero.LocalDuoBuildReceipts[key..':J'..p],'Owner already committed or uncertain')
   assert(host.choiceValid(hero,source,p),'Invalid personal reward')
   local info=rerollInfo(r,p);if not info.Available then return {Status='refused',Info=info}end
   local g=host.Game;local bank=g.LocalDuoPersonalRerolls
   local increment=g.RerollCosts.ReuseIncrement
   assert(type(increment)=='number'and increment>=0 and increment<math.huge,'Native reroll reuse increment unavailable')
   local names={};for _,row in ipairs(source.UpgradeOptions)do
    assert(type(row.ItemName)=='string','Native reroll item name missing');names[#names+1]=row.ItemName
   end
   assert(#names>0 and bank.CanAct(r.Run,hero)and current(r.Pools[p]),'Reroll preflight changed')
   if not bank.Spend(r.Run,hero,info.Cost)then return {Status='refused'}end
   spent=true -- From here, failure is uncertain and never retried/refunded automatically.
   local reuse=bank.ReuseCounts(r.Run,hero);reuse[source.ObjectId]=(reuse[source.ObjectId]or 0)+increment
   g.RandomSynchronize(bank.Read(r.Run,hero));g.InvalidateCheckpoint()
   assert(current(r.Pools[p]),'Scene changed after reroll debit')
   host.rerollLoot(source,{BoonRaritiesOverride=source.RarityChances,IgnoreAllRarityBonus=true,
    IgnoreRoomRarityBonus=true,ExclusionNames={g.GetRandomValue(names)}})
   local pool=source.UpgradeOptions
   assert(type(pool)=='table'and #pool>0 and pool~=r.Pools[other]and current(pool),'Native reroll pool invalid')
   local rows,offers={},{}
   for i,raw in ipairs(pool)do rows[i]={Ref=raw,Snapshot=copy(raw)}end
   local indices
   if d.VisibleIndices then indices=d.VisibleIndices(hero,source,p)
   else indices={};for i,raw in ipairs(pool)do if not raw.Blocked then indices[#indices+1]=i end end end
   assert(type(indices)=='table'and #indices>0 and #indices<=3,'Invalid native reroll visible count')
   local seen={};local selectable=0
   for _,index in ipairs(indices)do
    assert(type(index)=='number'and index%1==0 and not seen[index]and rows[index]and not rows[index].Ref.Blocked,'Invalid reroll visible row')
    seen[index]=true
    local raw=rows[index].Snapshot;local offer=d.PrepareOffer(hero,copy(raw),p,source)
    assert(type(offer)=='table'and offer.ItemName==raw.ItemName and offer.Data,'Invalid reroll preview')
    offer=copy(offer);offer.Owner=p;offer.Raw=offer.Raw or copy(raw);offers[#offers+1]=offer
    if not offer.Blocked then selectable=selectable+1 end
    assert(host.Context.GetCurrentHeroContext()==hero and current(pool),'Scene changed during reroll preview')
   end
   assert(selectable>0,'Native reroll returned no supported choice; reward stays pending')
   for i,row in ipairs(rows)do assert(pool[i]==row.Ref and equal(row.Snapshot,row.Ref),'Native reroll pool mutated')end
   -- Commit only this owner's coherent cache. Partner's refs/options/selection stay intact.
   r.Pools[p]=pool;r.Rows[p]=rows;r.VisibleIndices[p]=copy(indices);r.Offers[p]=offers
   return {Status='rerolled',Source=copy(source),Offers=copy(offers)}
  end)
  r.RerollBusy[p]=nil
  if ok then return result end
  if spent then r.RerollUncertain=r.RerollUncertain or {};r.RerollUncertain[p]=true end
  return {Status=spent and 'uncertain'or 'refused',Error=tostring(result)}
 end
 function runtime:Prepare(args)
  assert(args and type(args.key)=='string'and args.room and args.heroes and args.sources and args.devices)
  local existing=self.Records[args.key]
  if existing then
   if existing.RerollUncertain and next(existing.RerollUncertain)then
    return nil,false,{Reason='Uma alteração de opções foi interrompida; ela não será repetida.',FallbackVanilla=false}
   end
   if existing.Args.sources[1].LocalDuoCommonRoot and (host.Game.CurrentRun~=existing.Run
    or not existing.Run or existing.Run.CurrentRoom~=existing.Args.room or host.Game.MapState~=existing.Map
    or d.Validate(existing.Args)~=true)then
    return nil,false,{Reason='A corrida, sala ou jogador desta recompensa mudou.',FallbackVanilla=false}
   end
   if not samePair(existing.Args,args)then return nil,false,{Reason='Reward key belongs to another pair',FallbackVanilla=false}end
   if existing.Phase=='ready' then refreshReady(existing) end
   if existing.Phase=='ready'or existing.Phase=='active'or existing.Phase=='closed'then return existing,false end
   if existing.Phase=='rejected'and existing.Rejection then return nil,false,copy(existing.Rejection)end
   return nil,false,{Reason=existing.Phase,FallbackVanilla=false}
  end
  if d.Validate(args)~=true then return nil,false,{Reason='Invalid current pair',FallbackVanilla=true}end
  if args.heroes[1]==args.heroes[2]or args.devices[1]==args.devices[2]then
   return nil,false,{Reason='Distinct heroes and devices required',FallbackVanilla=true}
  end
  local r={Args={key=args.key,room=args.room,heroes={args.heroes[1],args.heroes[2]},
   sources={args.sources[1],args.sources[2]},devices={args.devices[1],args.devices[2]},names=args.names},
   Phase='preparing',ActorIds={args.heroes[1].ObjectId,args.heroes[2].ObjectId},
   SourceIds={args.sources[1].ObjectId,args.sources[2].ObjectId},Pools={},Rows={},Offers={},VisibleIndices={},
   Run=host.Game.CurrentRun,Map=host.Game.MapState,Bundle=args.sources[1].LocalDuoBundle}
  self.Records[args.key]=r -- reserve before a processing callback can yield/reenter
  local ok,reason=pcall(function()
   if d.PrepareCommon then d.PrepareCommon(args)end
   local bundle
   for p=1,2 do
    local source=args.sources[p];local pool=source.UpgradeOptions
    assert(source.LocalDuoOwner==p and source.LocalDuoBundle~=nil,'Personal source required')
    if p==1 then bundle=source.LocalDuoBundle else assert(source.LocalDuoBundle==bundle,'Different bundles')end
    assert(type(pool)=='table'and #pool>0,'Existing generated pool required; no reroll fallback')
    if p==2 then assert(pool~=r.Pools[1],'Aliased personal pools')end
    r.Pools[p]=pool;r.Rows[p]={}
    for i,raw in ipairs(pool)do r.Rows[p][i]={Ref=raw,Snapshot=copy(raw)}end
   end
   for p=1,2 do
    local indices
    if d.VisibleIndices then indices=host.Context.RunWithHeroContextAwait(args.heroes[p],d.VisibleIndices,args.heroes[p],args.sources[p],p)
    else indices={}
     for i,raw in ipairs(r.Pools[p])do if not raw.Blocked then indices[#indices+1]=i end end
    end
    assert(type(indices)=='table'and #indices>0 and #indices<=3,'One to three cached visible offers required')
    r.VisibleIndices[p]=copy(indices) -- preserve already selected indices; never select again on ID refresh
    local seen,selectable={},0;r.Offers[p]={}
    for _,index in ipairs(indices)do
     assert(type(index)=='number'and index%1==0 and not seen[index]and r.Rows[p][index],'Invalid visible index')
     seen[index]=true;assert(not r.Rows[p][index].Ref.Blocked,'Native blocked option is not visible')
     local offer=host.Context.RunWithHeroContextAwait(args.heroes[p],function()
      assert(host.Context.GetCurrentHeroContext()==args.heroes[p],'Wrong processing hero')
      return d.PrepareOffer(args.heroes[p],copy(r.Rows[p][index].Snapshot),p,args.sources[p])
     end)
     assert(type(offer)=='table'and offer.ItemName==r.Rows[p][index].Snapshot.ItemName and offer.Data,'Invalid prepared offer')
     offer=copy(offer);offer.Owner=p;offer.Raw=offer.Raw or copy(r.Rows[p][index].Snapshot)
     r.Offers[p][#r.Offers[p]+1]=offer;if not offer.Blocked then selectable=selectable+1 end
     assert(d.Validate(r.Args)==true and poolsCurrent(r),'Pool/scene changed during preparation')
    end
    if args.sources[1].LocalDuoCommonRoot then
     assert(selectable>0,'Jogador '..p..': estas opções exigem um fluxo de recompensa ainda não suportado. A coleta continua pendente.')
    else assert(selectable>0,'No compatible choice for this player')end
   end
  end)
  if not ok then
   r.Phase='rejected';r.Error=reason
   r.Rejection={Reason=tostring(reason),FallbackVanilla=true,EffectsStarted=false}
   return nil,false,copy(r.Rejection)
  end
  r.Phase='ready';return r,true
 end
 function runtime:CanOpen(args)
  local r,_,reason=self:Prepare(args)
  if not r then
   if args.sources[1].LocalDuoCommonRoot and type(reason)=='table'then return false,reason.Reason end
   return false,reason
  end
  if r.Phase=='closed'then
   if not poolsCurrent(r)then return false,'As ofertas ou atores desta recompensa mudaram.'end
   local allowed,why=service:CanReopen(r.Args);if not allowed then return false,why end
   for p=1,2 do local input=host.read(r.Args.devices[p])
    if not input or input.Connected~=true or input.Focused==false then return false,'O controle ainda está indisponível.'end
   end
   return service:CanOpen(r.Args)
  end
  if r.Phase~='ready' then return r.Phase=='active' end
  if d.Validate(r.Args)~=true or not poolsCurrent(r)then return false,'Cached preparation is stale'end
  for p=1,2 do local input=host.read(r.Args.devices[p])
   if not input or input.Connected~=true or input.Focused==false then return false,'Controller unavailable before opening'end
  end
  return service:CanOpen(r.Args)
 end
 function runtime:Open(args)
  local r,_,reason=self:Prepare(args)
  if not r then return nil,false,reason end
  if r.Phase=='active'then return r.Handle,false end
  if d.Validate(r.Args)~=true or not poolsCurrent(r)then return nil,false,{Reason='Cached preparation is stale',FallbackVanilla=true}end
  local allowed,why=self:CanOpen(args)
  if not allowed then return nil,false,{Reason=why,FallbackVanilla=true,EffectsStarted=false}end
  if r.Phase=='closed'then r.PreviousHandle=r.Handle end
  r.Phase='opening'
  local opened,handle,created,report=pcall(service.Open,service,r.Args)
  if not opened then r.Phase='uncertain';r.Error=handle;return nil,false,{Reason=tostring(handle),FallbackVanilla=false}end
  if not handle then r.Phase='uncertain';r.Error=report;return nil,false,report end
  if not handle.Session or handle.Session.State~='active'then
   r.Phase='uncertain';r.Handle=handle
   return nil,false,{Reason='Session did not reach active state',FallbackVanilla=false}
  end
  r.Handle=handle;r.Phase='active';return handle,created,report
 end
 function runtime:Update()
  self.Service:Update()
  for _,r in pairs(self.Records)do
   if r.Handle and r.Handle.Session and r.Handle.Session.State=='closed'then r.Phase='closed'end
  end
 end
 return runtime
end
return M
