-- Profile3 prototype: root alpha only. Import/construction do not change presentation.
local M={}
local stockBoonVisuals={
 HermesUpgrade={Graphic='BoonDropHermes',Child='BoonDropHermesIcon'},
 WeaponUpgrade={Graphic='WeaponUpgrade',Child='ResourceGlow_Base',StopRoot=true},
 StackUpgrade={Graphic='StackUpgrade',Child='ResourceGlow_Base',StopRoot=true},
 StackUpgradeBig={Graphic='StackUpgradeBig',Child='ResourceGlow_Base',StopRoot=true},
 StackUpgradeTriple={Graphic='StackUpgradeTriple',Child='ResourceGlow_Base',StopRoot=true},
 ApolloUpgrade={Graphic='BoonDropApollo',Child='BoonDropApolloIcon'},
 AphroditeUpgrade={Graphic='BoonDropAphrodite',Child='BoonDropAphroditeIcon'},
 AresUpgrade={Graphic='BoonDropAres',Child='BoonDropAresIcon'},
 DemeterUpgrade={Graphic='BoonDropDemeter',Child='BoonDropDemeterIcon'},
 HephaestusUpgrade={Graphic='BoonDropHephaestus',Child='BoonDropHephaestusIcon'},
 HeraUpgrade={Graphic='BoonDropHera',Child='BoonDropHeraIcon'},
 HestiaUpgrade={Graphic='BoonDropHestia',Child='BoonDropHestiaIcon'},
 PoseidonUpgrade={Graphic='BoonDropPoseidon',Child='BoonDropPoseidonIcon'},
 ZeusUpgrade={Graphic='BoonDropZeus',Child='BoonDropZeusIcon'},
}

local stockPomLevels={StackUpgrade=1,StackUpgradeBig=2,StackUpgradeTriple=3}

function M.New(d)
 local records={};local serial=0;local self={Enabled=true}
 local function present(s)return type(d.Game.LootObjects)=='table'and d.Game.LootObjects[s.ObjectId]==s end
 local function current(r)
  return d.IsCurrentPair(r.Args)==true and r.Args.sources[1].UpgradeOptions==r.Pools[1]
   and r.Args.sources[2].UpgradeOptions==r.Pools[2]and present(r.Args.sources[1])and present(r.Args.sources[2])
 end
 local function restore(r)
  local s=r.Args.sources[2]
  local sameWorld=d.Game.CurrentRun==r.Run and r.Run and r.Run.CurrentRoom==r.Room
  local function retire()
   if s.InteractBlocks then s.InteractBlocks[r.Flag]=nil end
   r.State='retired-source-gone';return true
  end
  if s.LocalDuoCommonCarrier then return retire()end -- private BlankObstacle never gains a loot graphic or usability
  if not sameWorld or s.LocalDuoConsumed==true or s.ObjectId~=r.HiddenId or not present(s)then return retire()end
  local alive=true
  if sameWorld and type(d.Game.IsAlive)=='function'then
   local ok,value=pcall(d.Game.IsAlive,{Id=r.HiddenId})
   if ok and value==false then alive=false
   elseif not ok or value~=true then r.State='restore-uncertain';r.Error='Loot IsAlive unknown';return false,r.Error end
  end
  if not alive then return retire()end -- own Lua block only; no native setter to destroyed ID
  if r.ChildRestoreAttempted and not r.ChildRestored then
   r.State='restore-uncertain';r.Error='Boon graphic restoration uncertain; no automatic native replay'
   return false,r.Error
  end
  local ok,err=pcall(function()
   if r.AlphaAttempted then d.Game.SetAlpha({Id=s.ObjectId,Fraction=r.DefaultRootAlpha,Duration=0})end
   if r.ChildStopAttempted and not r.ChildRestored then
    assert(not r.ChildRestoreAttempted,'Boon graphic restoration uncertain; no automatic native replay')
    r.ChildRestoreAttempted=true
    -- Gameplay.sjson stock Thing.Graphic; restart the stock root/child chain.
    d.Game.SetAnimation({DestinationId=r.HiddenId,Name=r.StockGraphic})
    r.ChildRestored=true
   end
   if r.BlockAttempted then d.Game.RemoveInteractBlock(s,r.Flag)end
  end)
  r.State=ok and'restored'or'restore-uncertain';r.Error=not ok and err or nil
  return ok,err
 end
 function self.Prepare(args)
  if not self.Enabled or d.Gate.IsTestProfile()~=true or d.CoopTwoPlayers()~=true then return nil,'inactive'end
  if records[args.key]then return records[args.key]end
  local a,b=args.sources[1],args.sources[2]
  local run=d.Game.CurrentRun;local room=run and run.CurrentRoom
  if not run or not room or args.room~=room then return nil,'unknown-current-world'end
  if not a or not b or a==b or a.ObjectId==b.ObjectId or a.LocalDuoOwner~=1 or b.LocalDuoOwner~=2
   or a.LocalDuoBundle~=b.LocalDuoBundle or not a.LocalDuoBundle or not present(a)or not present(b)
   or type(a.UpgradeOptions)~='table'or type(b.UpgradeOptions)~='table'or a.UpgradeOptions==b.UpgradeOptions then return nil,'invalid-pair'end
  for _,source in ipairs({a,b})do
   if source.StackOnly and not(stockPomLevels[source.Name]~=nil
    and(source.StackNum or 1)==stockPomLevels[source.Name]
    and not source.ResourceCosts and not source.BoughtFromShop and not source.UpgradeOnPick)then return nil,'unsupported-stack-visual'end
  end
  -- Exact stock GodLoot and Pom variant graphics/alpha255 verified in source.
  if a.Name=='WeaponUpgrade'or b.Name=='WeaponUpgrade'then
   for _,source in ipairs({a,b})do
    if source.Name~='WeaponUpgrade'or source.GodLoot~=false or source.StackOnly or source.ResourceCosts
     or source.BoughtFromShop or source.UpgradeOnPick then return nil,'unsupported-hammer-visual'end
   end
  end
  local visual=stockBoonVisuals[b.Name]
  if not visual or type(b.LootColor)~='table' or b.LootColor[4]~=255 then return nil,'unknown-default-root-alpha'end
  if type(d.Game.StopAnimation)~='function' or type(d.Game.SetAnimation)~='function'then
   return nil,'boon-animation-api-unavailable'
  end
  local checked,allowed=pcall(d.Host.CanOpen,d.Host,args)
  if not checked or allowed~=true or d.IsCurrentPair(args)~=true then return nil,'preflight-not-ready'end
  local pinned={};for k,v in pairs(args)do pinned[k]=v end;pinned.sources={a,b}
  serial=serial+1;local r={Args=pinned,Run=run,Room=room,HiddenId=b.ObjectId,StockGraphic=visual.Graphic,ChildAnimation=visual.Child,StopRoot=visual.StopRoot,Pools={a.UpgradeOptions,b.UpgradeOptions},DefaultRootAlpha=1,
   Flag='LocalDuoSingleRootAlpha:'..tostring(self)..':'..serial,State='hiding'}
  records[args.key]=r
  local ok,err=pcall(function()
   assert(current(r),'scope changed before root-alpha prototype')
   r.BlockAttempted=true;d.Game.AddInteractBlock(b,r.Flag)
   assert(current(r),'scope changed during block')
   r.AlphaAttempted=true;d.Game.SetAlpha({Id=b.ObjectId,Fraction=0,Duration=0})
   assert(current(r),'scope changed during alpha')
   if r.ChildAnimation then
    r.ChildStopAttempted=true
    -- Named child on this loot only; stock CombatLogic supports created-animation removal.
    d.Game.StopAnimation({DestinationId=r.HiddenId,Name=r.StopRoot and r.StockGraphic or r.ChildAnimation,
     IncludeCreatedAnimations=true,PreventChain=true})
    r.ChildStopReturned=true
    assert(current(r),'scope changed during stock boon child stop')
   end
  end)
  if not ok then restore(r);return nil,err end
  r.State='hidden';return r
 end
 function self.BeforeStockOrDecision(loot,decision)
  for _,r in pairs(records)do if r.Args.sources[1]==loot or r.Args.sources[2]==loot then
   if decision.Handled==true then r.State=decision.Route=='duo'and'active'or'uncertain';return decision end
   local ok,err=restore(r)
   if not ok then return {Handled=true,Route='waiting',SuppressAutoOther=true,Reason='single-root restore pending: '..tostring(err)}end
   return decision -- restoration completed before owner eligibility/stock code.
  end end
  return decision
 end
 function self.Update()
  for _,r in pairs(records)do
   if r.State=='restore-uncertain'or((r.State=='hidden'or r.State=='active'or r.State=='uncertain')
    and(not self.Enabled or d.Gate.IsTestProfile()~=true or not current(r)))then restore(r)end
  end
 end
 function self.Disable()self.Enabled=false;self.Update()end
 return self
end
return M
