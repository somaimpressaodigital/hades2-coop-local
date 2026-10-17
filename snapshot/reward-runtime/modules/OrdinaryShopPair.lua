-- One ordinary Olympian shop item; real CreateLoot base creates the companion.
-- No hooks installed here. Main injects the existing APIs/context/runtime.
local M={}
local names={ApolloUpgrade=true,AphroditeUpgrade=true,AresUpgrade=true,DemeterUpgrade=true,
 HeraUpgrade=true,HephaestusUpgrade=true,HestiaUpgrade=true,PoseidonUpgrade=true,ZeusUpgrade=true}
function M.New(d)
 local api,ctx,players=assert(d.Game),assert(d.Context),assert(d.Players)
 local self={BySource=setmetatable({},{__mode='k'}),Serial=0}
 local function current(r)
  if api.LocalDuoCoopModeActive~=true or api.CurrentRun~=r.Run or r.Run.CurrentRoom~=r.Room or api.MapState~=r.Map or r.Room.Store~=r.Store then return false end
  for p=1,2 do if players.GetHero(p)~=r.Heroes[p]or r.Heroes[p].IsDead or players.GetPlayerByHero(r.Heroes[p])~=p then return false end end
  for p=1,2 do if r.Heroes[p].ObjectId~=r.ActorIds[p]then return false end end
  return true
 end
 local function ordinary(source)
  return source and names[source.Name] and source.GodLoot==true and source.BoughtFromShop==true
   and type(source.ResourceCosts)=='table'and not source.UpgradeOnPick and not source.Cost and not source.AltCost
   and not source.TransformingTrait and not source.StackOnly
 end
 function self:Owns(source)return self.BySource[source]~=nil end
 function self:SourcesFor(source)local r=self.BySource[source];return r and r.Sources end
 function self:AfterCreateLoot(base,args,source)
  if api.LocalDuoCoopModeActive~=true or args.LocalDuoCopy or self:Owns(source) or d.Gate.IsTestProfile()~=true or not ordinary(source)then return source end
  local run=api.CurrentRun;local room=run and run.CurrentRoom
  local owner=players.GetPlayerByHero(ctx.GetCurrentHeroContext())
  local heroes={players.GetHero(1),players.GetHero(2)}
  if not room or not room.Store or not(owner==1 or owner==2)or not heroes[1]or not heroes[2]
   or heroes[1]==heroes[2]or heroes[1].IsDead or heroes[2].IsDead then return source end
  self.Serial=self.Serial+1
  local r={Run=run,Room=room,Store=room.Store,Map=api.MapState,Heroes=heroes,Sources={},Original=source,
   Owner=owner,Bundle='OrdinaryShop:'..self.Serial,ActorIds={heroes[1].ObjectId,heroes[2].ObjectId},Phase='spawning'}
  self.BySource[source]=r;r.Sources[owner]=source
  source.LocalDuoOwner=owner;source.LocalDuoBundle=r.Bundle
  local ok,err=pcall(function()
   local other=3-owner;local options=api.DeepCopyTable(args)
   options.LocalDuoCopy=true;options.ResourceCosts=nil;options.DoesNotBlockExit=true
   options.SuppressSpawnSounds=true;options.SuppressFlares=true
   options.SpawnPoint=source.ObjectId;options.OffsetX=owner==1 and 150 or -150
   local companion=assert(ctx.RunWithHeroContextAwait(heroes[other],base,options),'Shop companion was not created')
   self.BySource[companion]=r;r.Sources[other]=companion
   companion.LocalDuoOwner=other;companion.LocalDuoBundle=r.Bundle;companion.BoughtFromShop=true
   companion.CanReceiveGift=false;companion.UseText=companion.PurchaseText or 'Shop_UseText'
   companion.ResourceCosts=api.DeepCopyTable(source.ResourceCosts)
   api.UpdateCostText(companion)
   assert(current(r),'Shop scene changed during spawn')
   for p=1,2 do assert(type(r.Sources[p].UpgradeOptions)=='table'and #r.Sources[p].UpgradeOptions>0,'Missing actual generated shop pool')end
   assert(r.Sources[1].UpgradeOptions~=r.Sources[2].UpgradeOptions,'Aliased shop pools')
   r.Pools={r.Sources[1].UpgradeOptions,r.Sources[2].UpgradeOptions};r.SourceIds={r.Sources[1].ObjectId,r.Sources[2].ObjectId}
  end)
  r.Phase=ok and 'ready'or 'uncertain';r.Error=not ok and tostring(err)or nil
  return source
 end
 function self:CanUse(source,user)
  local r=self.BySource[source]
  if not r or not current(r)or d.Gate.IsTestProfile()~=true then return false,'Shop scene unavailable'end
  if user~=r.Heroes[1]and user~=r.Heroes[2]then return false,'Unknown shop user'end
  if r.Phase=='active'then return true end
  if r.Phase~='ready'then return false,r.Error or r.Phase end
  local usee=r.Original
  if not api.HasResources(usee.ResourceCosts)then api.CantAffordPresentation(usee);return false,'Cannot afford shop item'end
  if not api.HasResourceCost(usee.ResourceCosts)then return false,'This adapter requires an ordinary paid item'end
  return true
 end
 function self:IsCurrentPair(args)
  if type(args)~='table'or type(args.sources)~='table'or type(args.heroes)~='table' or d.Gate.IsTestProfile()~=true then return false end
  local r=self.BySource[args.sources[1]]
  if not r or self.BySource[args.sources[2]]~=r or not current(r)or args.room~=r.Room
   or not(r.Phase=='ready'or r.Phase=='paying'or r.Phase=='active')then return false end
  for p=1,2 do
   local source=args.sources[p]
   if r.Sources[p]~=source or r.Heroes[p]~=args.heroes[p]or source.ObjectId~=r.SourceIds[p]
    or source.LocalDuoOwner~=p or source.LocalDuoBundle~=r.Bundle or source.LocalDuoConsumed
    or source.UpgradeOptions~=r.Pools[p]or type(r.Pools[p])~='table'or #r.Pools[p]==0 then return false end
  end
  return r.Pools[1]~=r.Pools[2]
 end
 function self:BeforeOpen(args)
  local r=self.BySource[args.sources[1]]
  if not r then return true end -- unchanged free-room rewards
  assert(self.BySource[args.sources[2]]==r and current(r),'Wrong shop pair/scene')
  assert(r.Phase=='ready','Shop payment cannot be replayed')
  for p=1,2 do assert(r.Sources[p]==args.sources[p]and r.Heroes[p]==args.heroes[p],'Shop owner changed')end
  local usee=r.Original
  if not api.HasResources(usee.ResourceCosts)then api.CantAffordPresentation(usee);return false,'Cannot afford shop item'end
  assert(api.HasResourceCost(usee.ResourceCosts),'Cost vanished before shop payment')
  -- Reservation precedes ANY native purchase effect. Errors never retry payment.
  r.Phase='paying';r.Payment={Status='started',PaymentOwner=r.Owner,SourceActive=usee.ObjectId,
   Costs=api.DeepCopyTable(usee.ResourceCosts)}
  for p=1,2 do r.Sources[p].LocalDuoShopPayment=r.Payment end
  local ok,err=pcall(ctx.RunWithHeroContextAwait,r.Heroes[r.Owner],function()
   -- Exact stock UseLoot payment prefix, InteractLogic.lua:645-654.
   usee.Purchased = true
   api.DestroyTextBox({ Id = usee.ObjectId })
   api.SpendResources( usee.ResourceCosts, usee.Name or "Loot" )
   api.RemoveStoreItem( { Id = usee.ObjectId, Name = usee.Name, IsBoon = true, BoonRaritiesOverride = usee.BoonRaritiesOverride, StackNum = usee.StackNum, ScreenName = api.UIData.BoonMenuId } )
   if (usee.ResourceCosts.Money or 0) > 0 then
    api.HandleCharonPurchase( "UseLoot", usee.ResourceCosts.Money )
   end
   api.PlaySound({ Name = "/Leftovers/Menu Sounds/StoreBuyingItem" })
   api.thread( api.PlayVoiceLines, api.GlobalVoiceLines.PurchasedConsumableVoiceLines, true )
   assert(current(r),'Shop scene changed after payment')
  end)
  if not ok then r.Phase='uncertain';r.Payment.Status='uncertain';r.Error=tostring(err);return false,r.Error end
  r.Payment.Status='paid';r.Phase='active'
  for p=1,2 do
   local source=r.Sources[p];source.Purchased=true;source.ResourceCosts=nil
   source.LocalDuoShopPayment=r.Payment
   r.Map.RoomRequiredObjects[source.ObjectId]=source -- paid choices must complete before exit
  end
  return true
 end
 return self
end
return M
