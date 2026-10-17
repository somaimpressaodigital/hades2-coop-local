-- Build once per run/runtime. Main supplies real module/API references; no installation.
local M={}
local requiredModules={'HostFactory','Protection','CompatibleRows','SwordAdapter','Entry','Model','Adapter','Apply','Choices','Session','View','Input','CacheRuntime','PickupBridge'}
function M.Build(d)
 d=d or {};local missing={};local modules=d.Modules or {}
 for _,name in ipairs(requiredModules)do if type(modules[name])~='table'then missing[#missing+1]='Modules.'..name end end
 for _,name in ipairs({'Game','Context','Players','Control','Gate','PhysicalInput','Character','Events','Layout','Templates'})do
  if type(d[name])~='table'then missing[#missing+1]=name end
 end
 if type(d.Now)~='function'then missing[#missing+1]='Now'end
 if #missing>0 then return nil,{State='missing-dependencies',Missing=missing,EffectsStarted=false}end
 local function need(t,key,label)if type(t[key])~='function'then missing[#missing+1]=label..'.'..key end end
 need(d.Context,'RunWithHeroContextAwait','Context');need(d.Context,'GetCurrentHeroContext','Context')
 need(d.Context,'ScheduleServiceThread','Context');need(d.Players,'GetHero','Players');need(d.Players,'GetPlayerByHero','Players')
 need(d.Gate,'IsTestProfile','Gate');need(d.PhysicalInput,'read','PhysicalInput');need(d.PhysicalInput,'devices','PhysicalInput')
 need(d.Character,'Name','Character');need(d.Game,'LocalDuoNativeBindingProbe','Game')
 for _,name in ipairs({'GetProcessedTraitData','SetTraitTextData','GetTraitTooltipTitle','GetTraitFrame'})do need(d.Game,name,'Game')end
 for _,name in ipairs({'DeepCopyTable','AddInputBlock','RemoveInputBlock','Stop','SetInvulnerable','SetVulnerable','IsInvulnerable',
  'AddInteractBlock','RemoveInteractBlock','AddTimerBlock','RemoveTimerBlock','SetTraitsOnLoot','GetTotalHeroTraitValue',
  'HasHeroTraitValue','RemoveRandomValue','AddTraitToHero','IncreaseTraitLevel','RemoveWeaponTrait','LogUpgradeChoice',
  'IncrementTableValue','CheckCodexUnlock','CheckAndAddOlympianDuo','CheckNewTraitManaReserveShrineUpgrade',
  'Destroy','RemoveScreenEdgeIndicator','CheckRoomExitsReady','UnlockRoomExits','thread','AreScreensActive'})do need(d.Game,name,'Game')end
 if type(d.Players.PlayerUnitIdToHero)~='table'then missing[#missing+1]='Players.PlayerUnitIdToHero'end
 if not d.Events.engine or type(d.Events.engine.on)~='function'then missing[#missing+1]='Events.engine.on'end
 if #missing>0 then return nil,{State='missing-dependencies',Missing=missing,EffectsStarted=false}end
 local api,ctx,players=d.Game,d.Context,d.Players
 local function state()return {Run=api.CurrentRun,MapState=api.MapState,SessionMapState=api.SessionMapState,
  GameState=api.GameState,ActiveScreens=api.ActiveScreens,ActiveScreenOrder=api.ActiveScreenOrder}end
 -- Visual reskin markers NEVER select legacy H1 mechanics or restrict native H2 boons.
 local function originalSword(h)
  return h and (h.LocalDuoUsesLegacySwordMechanics==true or h.LocalDuoOriginalSword==true)or false
 end
 local rows=modules.CompatibleRows.New{SwordAdapter=modules.SwordAdapter,isOriginalSword=d.IsOriginalSword or originalSword,
  GetOwner=players.GetPlayerByHero,GetHero=players.GetHero,NativeMap=players.PlayerUnitIdToHero,NativeMana=d.NativeMana}
 local input=modules.Input.New{schemas=function()return d.Control.Schemas.Current end,
  gameHasFocus=function()return d.PhysicalInput.read(-1).Focused==true end,
  gamepadDevices=d.PhysicalInput.devices,gamepadRead=d.PhysicalInput.read,keyboardRead=d.KeyboardRead}
 local ui={ChaosOffer=modules.ChaosOffer,Entry=modules.Entry,Model=modules.Model,Adapter=modules.Adapter,Apply=modules.Apply,Choices=modules.Choices,
  Session=modules.Session,View=modules.View.WithTemplates(d.Layout,d.Templates)}
 local hammer=d.FreeHammer or modules.FreeHammer and modules.FreeHammer.New{Game=api,Context=ctx,Gate=d.Gate}
 local hd={freeHammer=hammer,Game=api,Modules=ui,Context=ctx,NativeContext=d.NativeContext,LootIndividual=d.LootIndividual,state=state,getHero=players.GetHero,
  read=function(device)return input:ReadDevice(device)end,now=d.Now,isTestProfile=d.Gate.IsTestProfile,
  isOriginalSword=d.IsOriginalSword or originalSword,prepareTrait=rows.prepareTrait,acceptTrait=rows.acceptTrait,
  Diagnostics=d.Diagnostics,markChoiceUnsupported=rows.markChoiceUnsupported,personalLevel=d.PersonalLevel,actorExists=d.ActorExists,testOnly=true}
 local host=modules.HostFactory.New(hd);modules.Protection.Wrap(host,hd)
 local function validate(args)
  if d.Gate.IsTestProfile()~=true or not api.CurrentRun or api.CurrentRun.CurrentRoom~=args.room then return false end
  for p=1,2 do
   local h,s=args.heroes[p],args.sources[p]
   if players.GetHero(p)~=h or h.IsDead or type(h.Health)~='number' or not(h.Health>0 and h.Health<math.huge)
    or players.GetPlayerByHero(h)~=p or s.LocalDuoOwner~=p then return false end
  end
  return true
 end
 local common=assert(modules.CommonOffers,'Common raw-offer module required')
 local cached=modules.CacheRuntime.New{Service=host,Validate=validate,VisibleIndices=d.VisibleIndices,
  PrepareCommon=function(args)return common.Normalize(api,args)end,
  PrepareOffer=function(hero,raw,p,source)
   -- Chaos pairs were already drawn personally. Preserve the native raw pair.
   if raw.Type=='TransformingTrait'and modules.ChaosOffer and modules.ChaosOffer.SourceAllowed(source)then
    return modules.ChaosOffer.Prepare(api,host.Host.Game.GetProcessedTraitData,hero,raw,p,source)
   end
   raw=common.PersonalRaw(api,hero,raw,source)
   local why=common.Reason(api,hero,raw,source)
   if why then return common.Blocked(api,hero,raw,p,source,why)end
   if source.Name=='WeaponUpgrade'then local allowed,why=hammer and hammer:Check(hero,source);assert(allowed==true,why or 'Free hammer backend unavailable')end
   if source.StackOnly then
    local prepare=d.PreparePomOffer or modules.PomOffer and modules.PomOffer.Prepare
    assert(type(prepare)=='function','Native pom preview dependency required')
    return prepare(api,host.Host.Game.GetProcessedTraitData,hero,raw,p,source)
   end
   local stack=raw.StackNum
   if source.StackOnly then
    local owned=assert(api.GetHeroTrait(raw.ItemName),'Owned boon required')
    stack=(owned.StackNum or 1)+(source.StackNum or 1)
   elseif raw.TraitToReplace then stack=api.GetTraitCount(hero,{Name=raw.TraitToReplace})+api.GetTotalHeroTraitValue('ExchangeLevelBonus')end
   local data=host.Host.Game.GetProcessedTraitData({Unit=hero,TraitName=raw.ItemName,Rarity=raw.Rarity,StackNum=stack},source)
   local definition=assert(api.TraitData[raw.ItemName],'Unknown native boon')
   data.TraitToReplace=raw.TraitToReplace;api.SetTraitTextData(data)
   return {ItemName=raw.ItemName,Rarity=raw.Rarity or 'Common',Owner=p,Data=data,Icon=data.Icon,
    Title=api.GetTraitTooltipTitle(definition),Description=api.GetTraitTooltip and api.GetTraitTooltip(data,{Default=definition.Title})or raw.ItemName,
    Frame=api.GetTraitFrame(data),StackOnly=source.StackOnly,StackNum=source.StackNum,Raw=raw,
    Blocked=data.LocalDuoUnsupported==true,UnsupportedReason=data.LocalDuoUnsupportedReason}
  end}
 local runKeys=setmetatable({},{__mode='k'});local roomKeys=setmetatable({},{__mode='k'});local serial=0
 local inputKey
 local function key(run,room,bundle)
  if not runKeys[run]then serial=serial+1;runKeys[run]=serial end
  if not roomKeys[room]then serial=serial+1;roomKeys[room]=serial end
  local value='DuoRuntime6:'..runKeys[run]..':'..roomKeys[room]..':'..tostring(bundle)
  if inputKey~=value then inputKey=value;input:Begin(value)end
  input:Poll(d.Now());return value
 end
 local stockPomLevels={StackUpgrade=1,StackUpgradeBig=2,StackUpgradeTriple=3}
 local function supportedFreePom(source)
  local levels=stockPomLevels[source.Name]
  return levels~=nil and source.StackOnly==true and(source.StackNum or 1)==levels
   and not source.ResourceCosts and not source.BoughtFromShop and not source.UpgradeOnPick
 end
 local shop=d.Shop
 local bridge=modules.PickupBridge.New{Host=cached,Context=ctx,Players=players,Game=api,Gate=d.Gate,
  Devices=function()return input:Devices()end,Key=key,
  SourcesFor=shop and function(source)return shop:SourcesFor(source)end,
  BeforeOpen=shop and function(args)return shop:BeforeOpen(args)end,
  Names=function()return {d.Character.Name(1),d.Character.Name(2)}end}
 local runtime={Shop=shop,Host=host,Cached=cached,Bridge=bridge,Input=input,Enabled=true,NativeProof=false,Profile3Only=true}
 if d.RootAlpha then
  local function coop()return api.LocalDuoCoopModeActive==true and players.GetPlayersCount()==2 end
  runtime.SingleVisible=d.RootAlpha.New{Game=api,Gate=d.Gate,Host=cached,CoopTwoPlayers=coop,
   IsCurrentPair=function(args)
    if not runtime.Enabled or not coop() or not validate(args) then return false end
    local required=api.MapState and api.MapState.RoomRequiredObjects
    local currentShop=shop and shop:IsCurrentPair(args)==true
    for p=1,2 do
     local source=args.sources[p]
     if source.LocalDuoConsumed or (not currentShop and (not required or required[source.ObjectId]~=source))then return false end
    end
    return true
   end}
  function runtime:PrepareVisiblePair(rewards,room,bundle)
   if not self.Enabled or not coop() or d.Gate.IsTestProfile()~=true
    or not api.CurrentRun or api.CurrentRun.CurrentRoom~=room or not bundle
    or not api.RequiredKillEnemies or next(api.RequiredKillEnemies) or api.AreScreensActive() then return nil,'not-ready' end
   local sources={}
   for _,source in pairs(rewards or {}) do
    local owner=source.LocalDuoOwner
    if source.StackOnly and not supportedFreePom(source)then return nil,'unsupported-stack-reward' end
    if (owner~=1 and owner~=2) or sources[owner] or source.LocalDuoBundle~=bundle
     or source.OnUsedFunctionName~='UseLoot'
     or ((source.ResourceCosts or source.BoughtFromShop)and not(shop and shop:Owns(source)))
     or source.UpgradeOnPick then return nil,'not-personal-free-pair' end
    sources[owner]=source
   end
   if not sources[1] or not sources[2] then return nil,'incomplete-pair' end
   local args={room=room,sources=sources,heroes={players.GetHero(1),players.GetHero(2)},
    devices=input:Devices(),names={d.Character.Name(1),d.Character.Name(2)}}
   if not args.heroes[1] or not args.heroes[2] or not validate(args) then return nil,'stale-pair' end
   local ownedShop=shop and (shop:Owns(sources[1])or shop:Owns(sources[2]))
   if ownedShop and shop:IsCurrentPair(args)~=true then return nil,'stale-shop-pair' end
   args.key=key(api.CurrentRun,room,bundle) -- same closure as the actual pickup bridge
   return self.SingleVisible.Prepare(args)
  end
 end
 function runtime:Disable()
  if self.SingleVisible then self.SingleVisible.Disable() end
  self.Enabled=false;self.Bridge.Enabled=false
 end
 function runtime:BeforeUseLoot(source,user)
  if not self.Enabled then return {Handled=false,Reason='Retired runtime'}end
  if source.StackOnly and not supportedFreePom(source)then return {Handled=false,Reason='Only exact free stock Pom variants supported'}end
  if shop and shop:Owns(source)then
   local allowed,why=shop:CanUse(source,user)
   if not allowed then return {Handled=true,Route='waiting',SuppressAutoOther=true,Reason=why}end
   local decision=self.Bridge:BeforeUseLoot(source,user)
   if not decision.Handled then return {Handled=true,Route='waiting',SuppressAutoOther=true,Reason=decision.Reason or 'Shop pair preflight refused'}end
   return decision
  end
  if source.LocalDuoShopPayment then return {Handled=true,Route='waiting',SuppressAutoOther=true,Reason='Shop payment record requires recovery; never replay'}end
  if source.ResourceCosts or source.BoughtFromShop or source.UpgradeOnPick then return {Handled=false,Reason='Ordinary free room rewards only'}end
  return self.Bridge:BeforeUseLoot(source,user)
 end
 function runtime:Update()
  if not self.Enabled or self.Updating then return end
  self.Updating=true;self.UpdateCount=(self.UpdateCount or 0)+1
  local ok,err=pcall(function()input:Poll(d.Now());bridge:Update();if self.SingleVisible then self.SingleVisible.Update() end end)
  self.Updating=false;if not ok then self.Error=err end
  if type(d.UIInputSnapshot)=='function'then
   local read,snapshot=pcall(d.UIInputSnapshot,self)
   if read then self.LastUIInputSnapshot=snapshot else self.DiagnosticError=tostring(snapshot)end
  end
  return ok,err
 end
 function runtime:Subscribe()
  if self.Subscribed then return false end
  self.Subscribed=true
  d.Events.engine:on('tick',function()
   if not self.Enabled then return end -- Retired runtimes must not publish stale diagnostics.
   self.TickCount=(self.TickCount or 0)+1
   if self.TickCount%30==0 and type(d.UIInputSnapshot)=='function'then
    local ok,snapshot=pcall(d.UIInputSnapshot,self)
    if ok then self.LastUIInputSnapshot=snapshot else self.DiagnosticError=tostring(snapshot)end
   end
   if not self.Enabled or self.Scheduled then return end
   self.Scheduled=true
   local ok,err=pcall(ctx.ScheduleServiceThread,function()
    local success,why=pcall(self.Update,self);self.Scheduled=false
    if not success then self.Error=why end
   end)
   if not ok then self.Scheduled=false;self.Error=err end
  end)
  return true
 end
 -- Main explicitly publishes runtime as LocalDuoRewardRouting and subscribes after validation.
 return runtime,{State='constructed-not-installed',NativeProof=false,Profile3Only=true,OffersRegenerated=false}
end
return M
