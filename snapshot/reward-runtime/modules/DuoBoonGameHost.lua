-- Factory only: explicit native API injection, no hooks/files/installation.
-- Default restricted to disposable Profile3. No native hero context across yield.
local Factory={};local serial=0
local function requireFunctions(t,names,label)
 for _,name in ipairs(names)do assert(type(t[name])=='function',label..'.'..name..' required')end
end
function Factory.New(deps)
 local api=assert(deps.Game,'Native APIs required');local modules=assert(deps.Modules)
 local context=assert(deps.Context)
 requireFunctions(context,{'RunWithHeroContextAwait','GetCurrentHeroContext'},'HeroContext')
 requireFunctions(deps,{'state','getHero','read','now','isTestProfile','acceptTrait','isOriginalSword'},'deps')
 requireFunctions(api,{'DeepCopyTable','AddInputBlock','RemoveInputBlock','Stop','SetInvulnerable','SetVulnerable','IsInvulnerable',
  'AddInteractBlock','RemoveInteractBlock','AddTimerBlock','RemoveTimerBlock','SetTraitsOnLoot',
  'GetProcessedTraitData','GetTotalHeroTraitValue','HasHeroTraitValue','RemoveRandomValue',
  'AddTraitToHero','IncreaseTraitLevel','RemoveWeaponTrait','LogUpgradeChoice','IncrementTableValue',
  'CheckCodexUnlock','CheckAndAddOlympianDuo','CheckNewTraitManaReserveShrineUpgrade',
  'Destroy','RemoveScreenEdgeIndicator','CheckRoomExitsReady','UnlockRoomExits','thread'},'Game')
 local testOnly=deps.testOnly~=false
 assert(testOnly or deps.enableProduction==true,'Production requires explicit enableProduction')
 serial=serial+1
 local service={Records={},TestOnly=testOnly,Serial=serial}
 local host={Modules={},Context=context,Game=setmetatable({}, {__index=api}),LootIndividual=deps.LootIndividual,
  read=deps.read,now=deps.now,thread=api.thread}
 service.Host=host
 for k,v in pairs(modules)do host.Modules[k]=v end
 host.Modules.View={New=function(game,model,args)
  local r=service.Records[model.Id];local allocated=args.onAllocated
  args.onAllocated=function(view)if r then r.View=view end;if allocated then allocated(view)end end
  return modules.View.New(game,model,args)
 end}
 host.Modules.Choices={New=function(args)
  local choices=modules.Choices.New(args);service.Records[args.rewardKey].Choices=choices;return choices
 end}
 local function gate()return not testOnly or deps.isTestProfile()==true end
 local function record(scope)return assert(service.Records[scope.Key],'Unknown reward session')end
 local function current(r)
  local state=deps.state();return state.Run==r.State.Run and state.Run.CurrentRoom==r.Scope.Room and state.MapState==r.State.MapState
 end
 local function live(r,hero)
  return current(r) and (not deps.actorExists or deps.actorExists(hero.ObjectId))
 end
 local function runAs(hero,fn,...)return context.RunWithHeroContextAwait(hero,fn,...)end
 local function findSource(source)
  if source.LocalDuoUIRewardKey then
   local r=assert(service.Records[source.LocalDuoUIRewardKey],'Stale personal reward key')
   local p=source.LocalDuoOwner;local original=r.Scope.Sources[p]
   assert(original and original.ObjectId==source.ObjectId,'Personal reward identity mismatch')
   return r,p,original
  end
  for _,r in pairs(service.Records)do for p,loot in ipairs(r.Scope.Sources)do
   if loot.ObjectId==source.ObjectId then return r,p,loot end
  end end
  error('Unregistered personal reward')
 end
 local chaos=modules.ChaosOffer
 local function freeChaos(source)return chaos and chaos.SourceAllowed(source)==true end
 local hermesPersonal={HermesWeaponBoon=true,HermesSpecialBoon=true,SorcerySpeedBoon=true,DodgeChanceBoon=true}
 local function dodgeSessionReady()
  local target=api.SessionMapState
  if type(target)~='table' then return false end
  local mt=getmetatable(target);local handler=type(mt)=='table' and mt.handler
  if type(handler)~='table' or handler.target~=target or type(handler.keys)~='table'
   or type(handler.data)~='table' or type(mt.__index)~='function' or type(mt.__newindex)~='function' then return false end
  local keys={};for _,key in ipairs(handler.keys)do keys[key]=true end
  if not keys.OlympianBoonCountBoost or not keys.OlympianBoonCountBoostPropertyChanges then return false end
  local a,b=handler.data[1],handler.data[2]
  if type(a)~='table' or type(b)~='table' or a==b or a==target or b==target then return false end
  if rawget(target,'OlympianBoonCountBoost')~=nil or rawget(target,'OlympianBoonCountBoostPropertyChanges')~=nil then return false end
  local ca,cb=a.OlympianBoonCountBoostPropertyChanges,b.OlympianBoonCountBoostPropertyChanges
  if ca~=nil and type(ca)~='table' or cb~=nil and type(cb)~='table' then return false end
  if ca~=nil and ca==cb then return false end
  return true
 end
 local function hermesChoiceReady(name)
  return hermesPersonal[name]==true and (name~='DodgeChanceBoon' or dodgeSessionReady())
 end
 local function freeHermes(source)
  return source.Name=='HermesUpgrade' and source.GodLoot==false and source.TreatAsGodLootByShops==true
   and source.OnUsedFunctionName=='UseLoot' and not source.StackOnly
   and source.ResourceCosts==nil and not source.BoughtFromShop and not source.LocalDuoShopOwner
 end
 local function special(hero,source)
  local hammer=source.Name=='WeaponUpgrade'
  if hammer then
   if not deps.freeHammer then return 'Free hammer backend unavailable'end
   local allowed,why=deps.freeHammer:Check(hero,source);if allowed~=true then return why or 'Hammer owner not eligible'end
  end
  if source.UpgradeOnPick or source.Cost or source.AltCost or source.TransformingTrait then return 'special purchase' end
  if not source.GodLoot and not source.StackOnly and not hammer and not freeHermes(source)and not freeChaos(source)then return 'only ordinary god boons, common hammer/poms and exact free Hermes supported'end
  if source.CanDuplicate and api.GetTotalHeroTraitValue('DoubleRewardChance')>0 then return 'reward duplication proc' end
  local ban=api.MetaUpgradeData and api.MetaUpgradeData.BanUnpickedBoonsShrineUpgrade
  if source.BanUnpickedBoonsEligible and ban and (ban.ChangeValue or 0)>0 then return 'ban-unpicked modifier' end
  local double=api.HasHeroTraitValue('DoubleBoonChance')
  if double and (double.Uses or 0)>0 and not source.BlockDoubleBoon then return 'double boon proc' end
  if api.IsFateValid and api.IsFateValid() and
   (api.GetTotalHeroTraitValue('FatedPomLevelBonus')>0 or api.GetTotalHeroTraitValue('FatedBoonLevelBonus')>0)then return 'fated extra levels' end
  if (source.Name=='TrialUpgrade' or source.Name=='ChaosUpgrade')and not freeChaos(source)then return 'Chaos flow' end
 end
 function service:CanOpen(args)
  if not gate()then return false,'requires disposable Profile3' end
  if type(args.key)~='string'or not args.room or not args.heroes or not args.sources then return false,'invalid pair arguments' end
  if not args.sources[1]or not args.sources[2]or args.sources[1].LocalDuoBundle==nil
   or args.sources[1].LocalDuoBundle~=args.sources[2].LocalDuoBundle then return false,'reward bundle mismatch' end
  local state=deps.state()
  if not state.Run or state.Run.CurrentRoom~=args.room then return false,'stale room' end
  for p=1,2 do
   local hero=args.heroes[p];local source=args.sources[p]
   if not hero or hero~=deps.getHero(p)or hero.IsDead or source.LocalDuoOwner~=p then return false,'missing/dead/wrong owner' end
   if deps.isOriginalSword(hero)and(not deps.prepareTrait or source.StackOnly and not deps.personalLevel)then
    return false,'original sword requires private prepare/personal-level backend'
   end
   local reason=runAs(hero,special,hero,source);if reason then return false,reason end
   if source.UpgradeOptions then for _,option in ipairs(source.UpgradeOptions)do
    if option.Type=='TransformingTrait'and not freeChaos(source)or option.ItemName=='FallbackGold'then return false,'special option' end
   end end
  end
  return true
 end
 -- Intentional personal reroll only: preserve native args and the registered source identity.
 host.rerollLoot=function(source,args)
  local r,p,original=findSource(source)
  assert(source==original and gate()and current(r)and context.GetCurrentHeroContext()==r.Scope.Heroes[p],
   'Wrong reroll source/context')
  local reason=special(r.Scope.Heroes[p],source);assert(not reason,reason)
  return api.SetTraitsOnLoot(source,args)
 end
 host.Game.SetTraitsOnLoot=function(source)
  local r,p,original=findSource(source)
  assert(gate()and current(r)and context.GetCurrentHeroContext()==r.Scope.Heroes[p],'Wrong generation context')
  local reason=special(r.Scope.Heroes[p],source);assert(not reason,reason)
  api.SetTraitsOnLoot(source)
  -- Preserve the rolled personal offers for fallback/reopening. No fresh reroll.
  original.UpgradeOptions=api.DeepCopyTable(source.UpgradeOptions)
 end
 host.Game.GetProcessedTraitData=function(args,source)
  local data=api.GetProcessedTraitData(args)
  assert(data and args.Unit==context.GetCurrentHeroContext(),'Trait processing owner mismatch')
  if source and freeHermes(source) and not hermesChoiceReady(data.Name) then
   local reason='Esta melhoria de Hermes ainda não foi validada para builds separadas.'
   assert(type(deps.markChoiceUnsupported)=='function',reason)
   local row=deps.markChoiceUnsupported(args.Unit,{ItemName=data.Name,Data=data},reason)
   assert(row and row.Blocked==true and row.Data,'Unsupported Hermes row annotation required')
   return row.Data
  end
  if type(deps.markChoiceUnsupported)=='function'then
   -- Optional row-safe legacy mode: keep the already-generated option visible and blocked.
   local original=data
   local ok,prepared,reason=pcall(function()
    if deps.isOriginalSword(args.Unit)then return deps.prepareTrait(args.Unit,api.DeepCopyTable(original))end
    return original
   end)
   local accepted,why=false,reason
   if ok and prepared then
    local checked,value,message=pcall(deps.acceptTrait,args.Unit,prepared)
    accepted=checked and value==true;why=message or why
   end
   if accepted then return prepared end
   local row=deps.markChoiceUnsupported(args.Unit,{ItemName=original.Name,Data=original},
    why or 'Bênção ainda não compatível com este jogador.')
   assert(row and row.Blocked==true and row.Data,'Unsupported row annotation required')
   return row.Data
  end
  if deps.isOriginalSword(args.Unit)then
   assert(deps.prepareTrait,'Original sword prepare backend required')
   data=deps.prepareTrait(args.Unit,api.DeepCopyTable(data))
  end
  local accepted,reason=deps.acceptTrait(args.Unit,data)
  assert(accepted==true,reason or 'Trait backend not approved for this hero')
  return data
 end
 host.selectVisibleOptions=function(hero,source,candidates,limit)
  -- Match vanilla: random blocked indexes, then native slot ordering.
  local blocked={};for i=1,#candidates do blocked[i]=i end
  for _=1,limit do if #blocked>0 then api.RemoveRandomValue(blocked)end end
  local order={Melee=0,Secondary=1,Ranged=2,Rush=3,Mana=4}
  table.sort(candidates,function(a,b)
   local da,db=api.TraitData[a.ItemName],api.TraitData[b.ItemName]
   return(order[da and da.Slot]or 99)<(order[db and db.Slot]or 99)
  end)
  local blockedLookup={};for _,i in ipairs(blocked)do blockedLookup[i]=true end
  local visible={}
  for i,option in ipairs(candidates)do option.Blocked=blockedLookup[i]or nil;if not option.Blocked then visible[#visible+1]=option end end
  source.UpgradeOptions=candidates
  local _,_,original=findSource(source);original.UpgradeOptions=api.DeepCopyTable(candidates)
  return visible
 end
 host.ApplyApi={chaosChoiceAllowed=function(hero,source,choice)
  return freeChaos(source)and chaos.ChoiceAllowed(api,hero,source,choice)==true
 end,currentHero=context.GetCurrentHeroContext,clone=api.DeepCopyTable,
  AddTraitToHero=api.AddTraitToHero,RemoveWeaponTrait=api.RemoveWeaponTrait,
  IncreaseTraitLevel=function(trait,stacks)
   local hero=context.GetCurrentHeroContext()
   if deps.isOriginalSword(hero)then
    assert(deps.personalLevel,'Never use unadapted native IncreaseTraitLevel for original sword')
    local owner=hero==deps.getHero(1)and 1 or hero==deps.getHero(2)and 2
    assert(owner,'Unknown level recipient');return deps.personalLevel(hero,owner,trait,stacks)
   end
   return api.IncreaseTraitLevel(trait,stacks)
  end,
  duplicateChance=function()return api.GetTotalHeroTraitValue('DoubleRewardChance')end,
  banCount=function()return api.MetaUpgradeData.BanUnpickedBoonsShrineUpgrade.ChangeValue end,
  hasDoubleBoon=function()local t=api.HasHeroTraitValue('DoubleBoonChance');return t and(t.Uses or 0)>0 end}
 host.ApplyApi.recordPick=function(hero,source,choice,request)
  assert(context.GetCurrentHeroContext()==hero and gate(),'Wrong application context/profile')
  local r,p=findSource(source);assert(r.Scope.Heroes[p]==hero and p==request.Player and current(r),'Stale application')
  local run,state=r.State.Run,r.State
  local button={Data=choice.Data,LootData=source,UpgradeName=source.Name}
  api.LogUpgradeChoice(button)
  local pickedName=choice.ChaosPair and choice.Data.Name or choice.ItemName
  run.PickedTraits=run.PickedTraits or {};run.PickedTraits[pickedName]=true
  hero.LocalDuoLastUpgradeChoice=pickedName
  state.SessionMapState.LastUpgradeChoice=pickedName -- vanilla informational field
  if choice.Raw and choice.Raw.TraitToReplace then api.IncrementTableValue(run,'SacrificeTraitCount')end
  local common=source.LocalDuoCommonRoot or source.LocalDuoCommonCarrier
  if not common or not r.CommonWorldPick then
   r.CommonWorldPick=true -- before world-side mutation; partial failure must never repeat it
   api.IncrementTableValue(state.GameState.LootPickups,source.Name)
   api.CheckCodexUnlock('OlympianGods',source.Name);api.CheckCodexUnlock('ChthonicGods',source.Name);api.CheckCodexUnlock('Items',source.Name)
  end
  local added=not source.StackOnly and hero.TraitDictionary[choice.Data.Name]and hero.TraitDictionary[choice.Data.Name][1]or nil
  api.CheckAndAddOlympianDuo(source)
  api.CheckNewTraitManaReserveShrineUpgrade(added,{IsGodLoot=source.GodLoot or source.TreatAsGodLootByShops})
 end
 host.Modules.Apply={New=function(appApi)
  local native=modules.Apply.New(appApi)
  return {supported=function(hero,source,choice)
   local reason=special(hero,source);if reason then return false,reason end
   if choice.ItemName=='FallbackGold'then return false,'special choice'end
   if choice.Raw and choice.Raw.Type=='TransformingTrait'and not host.ApplyApi.chaosChoiceAllowed(hero,source,choice)then return false,'Unprepared or unsupported Chaos pair'end
   if freeHermes(source) and not hermesChoiceReady(choice.ItemName) then return false,'Hermes choice not yet validated for this pilot' end
   local ok,why=deps.acceptTrait(hero,choice.Data);if ok~=true then return false,why end
   if choice.ChaosPair then local accepted,why=deps.acceptTrait(hero,choice.BlessingData);if accepted~=true then return false,why end end
   return native.supported(hero,source,choice)
  end,commit=function(hero,source,choice,request)
   local reason=special(hero,source);assert(not reason,reason)
   assert(gate(),'Profile changed before commit')
   if choice.Raw and choice.Raw.Type=='TransformingTrait'then
    assert(host.ApplyApi.chaosChoiceAllowed(hero,source,choice),'Chaos pair changed before commit')
    assert(deps.acceptTrait(hero,choice.Data)==true and deps.acceptTrait(hero,choice.BlessingData)==true,'Chaos backend owner refused')
   end
   assert(not freeHermes(source) or hermesChoiceReady(choice.ItemName),'Unsupported Hermes choice')
   return native.commit(hero,source,choice,request)
  end}
 end}
 host.roomValid=function(scope)return gate()and current(record(scope))end
 host.connected=function(scope,owner,p)
  local r=record(scope);local input=deps.read(r.Args.devices[p]);return input.Connected==true
 end
 host.alive=function(scope,owner,p)return deps.getHero(p)==scope.Heroes[p] and not scope.Heroes[p].IsDead end
 host.choiceValid=function(hero,source,p)
  local r,owner,original=findSource(source)
  return gate()and current(r)and owner==p and deps.getHero(p)==hero and not hero.IsDead
   and not original.LocalDuoConsumed and original.LocalDuoBundle==source.LocalDuoBundle
 end
 host.acquire=function(scope,owner,resource)
  local r=record(scope);r.Owner=owner
  r.Acquired=r.Acquired or {};r.Acquired[resource]=true -- Before a partial native call.
  local p=resource:match('^combat:J([12])$')
  if p then
   p=tonumber(p);local hero=scope.Heroes[p];local flag=r.Flag..':J'..p
   r.NativeOpaque=r.NativeOpaque or {}
   local invulnerable=api.IsInvulnerable({Id=hero.ObjectId})
   assert(type(invulnerable)=='boolean','Native invulnerability query must be authoritative')
   r.NativeOpaque[p]=invulnerable and not next(hero.InvulnerableFlags or {})
   api.AddInputBlock({Name=flag,PlayerIndex=p});api.Stop({Id=hero.ObjectId})
   hero.InvulnerableFlags=hero.InvulnerableFlags or {};hero.InvulnerableFlags[flag]=true
   api.SetInvulnerable({Id=hero.ObjectId})
  elseif resource=='rewards'then
   for _,source in ipairs(scope.Sources)do api.AddInteractBlock(source,r.Flag)end
  elseif resource=='exits'then
   local screen={Name=r.Flag,Components={},BlockExitsReady=true,BlockPause=true,IgnoreOtherScreenInput=true,KeepOpen=true}
   r.Screen=screen;r.State.ActiveScreens[r.Flag]=screen;table.insert(r.State.ActiveScreenOrder,r.Flag)
   api.AddTimerBlock(r.State.Run,r.Flag,{MapState=true})
  end
  return true
 end
 local function guard(r,source,reason)
  local flag=r.Flag..':recovery:'..source.LocalDuoOwner
  r.State.MapState.RoomRequiredObjects[flag]={Name='LocalDuoRewardRecovery',Reason=reason,Reward=source.ObjectId}
  source.InteractBlocks=source.InteractBlocks or {};source.InteractBlocks[flag]=true
  if current(r) and (not deps.actorExists or deps.actorExists(source.ObjectId))then api.AddInteractBlock(source,flag)end
  r.Recovery=r.Recovery or {};r.Recovery[source.LocalDuoOwner]=reason
 end
 host.secureRewards=function(scope,owner,report,result)
  local r=record(scope)
  if scope.Sources[1].LocalDuoCommonRoot then
   local complete=true
   for p,source in ipairs(scope.Sources)do
    local hero=scope.Heroes[p];local receipt=hero.LocalDuoBuildReceipts and hero.LocalDuoBuildReceipts[scope.Key..':J'..p]
    if not receipt or receipt.Status~='committed'then complete=false end
   end
   if not complete then
    -- Keep the one visible root while a personal choice is pending, even after a partial commit.
    for p,source in ipairs(scope.Sources)do
     local hero=scope.Heroes[p];local receipt=hero.LocalDuoBuildReceipts and hero.LocalDuoBuildReceipts[scope.Key..':J'..p]
     if receipt and receipt.Status~='committed'then guard(r,source,'uncertain build application')end
     r.State.MapState.RoomRequiredObjects[source.ObjectId]=r.State.MapState.RoomRequiredObjects[source.ObjectId]or source
    end
    r.FinalReport=report;r.Secured=true;return true
   end
  end
  for p,source in ipairs(scope.Sources)do
   local hero=scope.Heroes[p];local receipt=hero.LocalDuoBuildReceipts and hero.LocalDuoBuildReceipts[scope.Key..':J'..p]
   if receipt and receipt.Status=='committed'then
    r.Consumption=r.Consumption or {};local progress=r.Consumption[p]
    if not progress then progress={Status='started'};r.Consumption[p]=progress
     local ok,err=pcall(function()
      assert(current(r),'room changed before consumption')
      if source.DestroyOnPickup then api.Destroy({Id=source.ObjectId});api.RemoveScreenEdgeIndicator(source)end
      r.State.MapState.RoomRequiredObjects[source.ObjectId]=nil
      source.LocalDuoConsumed=true
      if source.LastRewardEligible then r.State.Run.LastReward={Type='Boon',Name=source.Name,DisplayName=source.Name}end
     end)
     progress.Status=ok and 'committed'or 'uncertain';progress.Error=not ok and tostring(err)or nil
    end
    if progress.Status~='committed'then guard(r,source,progress.Error)end
   elseif receipt then guard(r,source,'uncertain build application')
   else
    -- Restore the actual pending object if a previous callback removed it.
    r.State.MapState.RoomRequiredObjects[source.ObjectId]=r.State.MapState.RoomRequiredObjects[source.ObjectId]or source
   end
  end
  r.FinalReport=report;r.Secured=true
  return true -- Every incomplete/uncertain reward is protected by a persistent guard.
 end
 host.release=function(scope,owner,resource)
  local r=record(scope);assert(r.Owner==owner,'Wrong lease owner')
  local p=resource:match('^combat:J([12])$')
  if p then
   p=tonumber(p);local hero=scope.Heroes[p];local flag=r.Flag..':J'..p
   api.RemoveInputBlock({Name=flag,PlayerIndex=p})
   if hero.InvulnerableFlags then hero.InvulnerableFlags[flag]=nil end
   if r.NativeOpaque and r.NativeOpaque[p]==false and live(r,hero)and not hero.IsDead and not next(hero.InvulnerableFlags or {})then api.SetVulnerable({Id=hero.ObjectId})end
  elseif resource=='rewards'then
   for _,source in ipairs(scope.Sources)do
    if current(r)and not source.LocalDuoConsumed and(not deps.actorExists or deps.actorExists(source.ObjectId))then
     api.RemoveInteractBlock(source,r.Flag)
    elseif source.InteractBlocks then source.InteractBlocks[r.Flag]=nil end
   end
  elseif resource=='exits'then
   assert(r.Secured,'Reward invariants not protected')
   if r.State.ActiveScreens[r.Flag]==r.Screen then r.State.ActiveScreens[r.Flag]=nil end
   for i=#r.State.ActiveScreenOrder,1,-1 do if r.State.ActiveScreenOrder[i]==r.Flag then table.remove(r.State.ActiveScreenOrder,i)end end
   if current(r)then api.RemoveTimerBlock(r.State.Run,r.Flag)
   else
    r.State.MapState.BlockTimerFlags[r.Flag]=nil;r.State.Run.BlockTimerFlags[r.Flag]=nil
   end
   -- Existing final release only; no new observer, polling or gameplay mutation.
   if not r.CloseReasonLogged and deps.Diagnostics and type(deps.Diagnostics.Write)=='function'then
    r.CloseReasonLogged=true -- Diagnostic failure must never retry or block cleanup.
    pcall(function()
     local report=r.FinalReport or{};local count=0;local statuses={};local consumed={}
     for p,source in ipairs(scope.Sources)do
      local hero=scope.Heroes[p]
      local receipt=hero.LocalDuoBuildReceipts and hero.LocalDuoBuildReceipts[scope.Key..':J'..p]
      statuses[p]=receipt and tostring(receipt.Status)or 'absent'
      if receipt and receipt.Status=='committed'then count=count+1 end
      consumed[p]=source.LocalDuoConsumed==true and 'true'or 'false'
     end
     local errors={}
     for i,errorText in ipairs(report.Errors or{})do
      if i>3 then break end
      errors[#errors+1]=type(errorText)=='string'and errorText:sub(1,180)or '<non-string error>'
     end
     deps.Diagnostics.Write('boon-close','key='..scope.Key..' reason='..tostring(report.Reason or 'unknown')
      ..' J1='..statuses[1]..' J2='..statuses[2]..' committed='..count
      ..' commonWorldPick='..tostring(r.CommonWorldPick==true)
      ..' consumed='..consumed[1]..','..consumed[2]..' errors='..table.concat(errors,' | '))
    end)
   end
  end
  return true
 end
 function service:CanReopen(args)
  local r=self.Records[args.key]
  if not r or not args.sources[1].LocalDuoCommonRoot or r.EntryFault or r.Recovery
   or args.room~=r.Scope.Room or not current(r)or r.State.SessionMapState~=deps.state().SessionMapState
   or not modules.Entry.CanRetireClosed(host,args.key,r.Handle)then return false,'A escolha anterior ainda precisa terminar a limpeza.'end
  if r.State.ActiveScreens[r.Flag]or r.State.MapState.BlockTimerFlags[r.Flag]or r.State.Run.BlockTimerFlags[r.Flag]then
   return false,'A escolha anterior ainda mantém bloqueios próprios.'
  end
  for p=1,2 do
   local hero,source=r.Scope.Heroes[p],r.Scope.Sources[p]
   if args.heroes[p]~=hero or args.sources[p]~=source or hero~=deps.getHero(p)
    or source.LocalDuoConsumed or r.State.MapState.RoomRequiredObjects[source.ObjectId]~=source
    or(type(api.LootObjects)=='table'and api.LootObjects[source.ObjectId]~=source)
    or(source.InteractBlocks and source.InteractBlocks[r.Flag])then return false,'A recompensa ou jogador original mudou.'end
   local lease=r.OperationalLeases and r.OperationalLeases[p]
   if lease and(not lease.Released or lease.ReleaseUncertain)then return false,'A liberação anterior do controle não foi concluída.'end
   local flag=r.Flag..':J'..p
   if hero.InvulnerableFlags and hero.InvulnerableFlags[flag]then return false,'A proteção anterior ainda está ativa.'end
   local key=args.key..':J'..p
   local build=hero.LocalDuoBuildReceipts and hero.LocalDuoBuildReceipts[key]
   local applied=hero.LocalDuoBoonReceipts and hero.LocalDuoBoonReceipts[key]
   if (build and(build.Status~='committed'or build.Player~=p))
    or(applied and(applied.Status~='committed'or applied.Player~=p))or(build~=nil and applied==nil)
    or(applied~=nil and build==nil)then return false,'Uma aplicação anterior é incerta; ela não será repetida.'end
   local consumed=r.Consumption and r.Consumption[p]
   if consumed then return false,'A coleta anterior já iniciou o consumo.'end
  end
  return true
 end
 function service:Open(args)
  local previousWorldPick
  local allowed,reason
  if self.Records[args.key]then
   local existing=self.Records[args.key]
   if existing.EntryFault then return nil,false,{FallbackVanilla=false,PendingCleanup=not existing.EmergencyDone,Reason=existing.EntryFault}end
   local reopen,why=self:CanReopen(args)
   if not reopen then return existing.Handle,false,{FallbackVanilla=false,Reason=why}end
   allowed,reason=self:CanOpen(args) -- May yield; do not retire the old record before this gate.
   if not allowed then return nil,false,{FallbackVanilla=false,Reason=reason,EffectsStarted=false}end
   reopen,why=self:CanReopen(args) -- Recheck ownership/cleanup after the yielding gate.
   if not reopen or self.Records[args.key]~=existing then return nil,false,{FallbackVanilla=false,Reason=why or 'Reward record changed',EffectsStarted=false}end
   assert(modules.Entry.RetireClosed(host,args.key,existing.Handle),'Closed session retirement changed')
   previousWorldPick=existing.CommonWorldPick;self.Records[args.key]=nil
  else
   allowed,reason=self:CanOpen(args)
   if not allowed then return nil,false,{FallbackVanilla=true,Reason=reason,Applied=false}end
  end
  local state=deps.state();local r={Args=args,Scope={Key=args.key,Room=args.room,Heroes=args.heroes,Sources=args.sources},
   State={Run=state.Run,MapState=state.MapState,SessionMapState=state.SessionMapState,GameState=state.GameState,
    ActiveScreens=state.ActiveScreens,ActiveScreenOrder=state.ActiveScreenOrder}}
  -- Keyed Records are not a sequence; use an explicit per-factory monotonic counter.
  self.Count=(self.Count or 0)+1;r.Flag='LocalDuoBoonHost:'..self.Serial..':'..self.Count
  r.CommonWorldPick=previousWorldPick
  self.Records[args.key]=r
  for _,source in ipairs(args.sources)do source.LocalDuoUIRewardKey=args.key end
  local ok,h,created,why=pcall(modules.Entry.Open,host,args)
  if not ok then
   -- Never lose recovery state after a caller/Entry throws beyond its own guard.
   r.EntryFault=tostring(h)
   return nil,false,{FallbackVanilla=false,PendingCleanup=true,Reason=r.EntryFault}
  end
  if not h then self.Records[args.key]=nil;return nil,created,why end
  r.Handle=h
  if r.Screen and h and h.View then r.Screen.Components=h.View.Components end
  return h,created,why
 end
 function service:Update()
  for _,r in pairs(self.Records)do
   if r.EntryFault and not r.EmergencyDone then
    local ok,err=pcall(function()
     if r.Choices then r.Choices:Abort('entry-error');if r.Choices.Draining then return end end
     if r.View then r.View:Destroy()end
     assert(host.secureRewards(r.Scope,r.Owner,{Key=r.Scope.Key,Reason='entry-error'})==true)
     for _,resource in ipairs({'combat:J1','combat:J2','rewards','exits'})do
      if r.Acquired and r.Acquired[resource]then
       assert(host.release(r.Scope,r.Owner,resource)==true);r.Acquired[resource]=nil
      end
     end
     r.EmergencyDone=true
    end)
    if not ok then r.EmergencyError=tostring(err)end
   end
   if r.Handle then
    r.Handle:Update()
    if r.Handle.Session.State=='closed'and not r.UnlockRequested and current(r)and not r.Recovery
     and r.Consumption and r.Consumption[1]and r.Consumption[2]
     and r.Consumption[1].Status=='committed'and r.Consumption[2].Status=='committed'then
     local hero=not r.Scope.Heroes[1].IsDead and r.Scope.Heroes[1]or not r.Scope.Heroes[2].IsDead and r.Scope.Heroes[2]
     if hero and runAs(hero,api.CheckRoomExitsReady,r.Scope.Room)then
      r.UnlockRequested=true
      local scheduled,scheduleError=pcall(api.thread,function()
       local ok,err=pcall(function()if current(r)then runAs(hero,api.UnlockRoomExits,r.State.Run,r.Scope.Room)end end)
       if not ok then r.UnlockError=tostring(err)end
      end)
      if not scheduled then r.UnlockError=tostring(scheduleError)end
     end
    end
   end
  end
 end
 return service
end
return Factory
