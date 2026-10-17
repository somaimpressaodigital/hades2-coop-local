-- Source-only pilot. Only a free, exact MaxHealthDrop room reward in Profile 3.
local M={}
function M.New(d)
 local g,p,c=d.Game,d.Players,d.Context
 local records=setmetatable({},{__mode='k'})
 local function enabled()
  return d.Gate.IsTestProfile()==true and g.LocalDuoCoopModeActive==true
   and p.GetPlayersCount()==2
 end
 local function live(r,item)
  return enabled() and item.ObjectId==r.ItemId and g.CurrentRun==r.Run and g.CurrentRun.CurrentRoom==r.Room
   and g.MapState.ActiveObstacles[item.ObjectId]==item
 end
 local function pair(allowDead)
  local a,b=p.GetHero(1),p.GetHero(2)
  if not a or not b or a==b then return end
  if not allowDead and (a.IsDead or b.IsDead) then return end
  if p.GetPlayerByHero(a)~=1 or p.GetPlayerByHero(b)~=2 then return end
  return {a,b}
 end
 local self={}
 function self.IsRoomReward(room,args)
  local encounter=room.Encounter or {}
  local kind=(args or {}).RewardOverride or encounter.EncounterRoomRewardOverride
   or room.ChangeReward or room.ChosenRewardType
  return enabled() and pair()~=nil and kind=='MaxHealthDrop' and not room.DeferReward
   and not(room.Reward and room.Reward.FunctionName)
 end
 function self.Spawn(base,source,args)
  local run,room=g.CurrentRun,g.CurrentRun.CurrentRoom
  local options=g.DeepCopyTable(args or {})
  options.WaitUntilPickup=false
  local item=base(source,options) -- stock reward side effects/counters exactly once
  if item and item.Name=='MaxHealthDrop' and item.IgnorePurchase==true
   and item.AddMaxHealth~=nil and g.CurrentRun==run and run.CurrentRoom==room
   and g.MapState.ActiveObstacles[item.ObjectId]==item then
   records[item]={Run=run,Room=room,ItemId=item.ObjectId}
  end
  if args and args.WaitUntilPickup and item then
   while g.CurrentRun==run and run.CurrentRoom==room
    and g.MapState.RoomRequiredObjects[item.ObjectId] do g.wait(0.1) end
  end
  return item
 end
 function self.Use(base,item,args,user)
  local r=records[item]
  if not r then return base(item,args,user) end
  if r.Busy or r.Failed or r.Done then return false end
  if not live(r,item) then return false end
  local heroes=pair(true)
  if not heroes then return false end -- missing/replaced registration still refuses
  local owner=g.CurrentRun.Hero
  if not owner or owner.IsDead or (owner~=heroes[1] and owner~=heroes[2]) then return false end
  local ids={heroes[1].ObjectId,heroes[2].ObjectId}
  r.Busy=true;r.Heroes=heroes;r.Ids=ids;r.Applied={};r.Owner=owner
  r.Eligible={not heroes[1].IsDead,not heroes[2].IsDead} -- no pending grant to a dead partner
  local canDuplicate=item.CanDuplicate==true
  local result=table.pack(pcall(base,item,args,user))
  r.Busy=false
  if not result[1] then r.Failed=true;error(result[2],0) end
  if next(r.Applied) then
   r.Done=true
   -- Preserve stock DoubleRewardChance: stock explicitly re-arms this same item once.
   -- A reentrant callback while stock is running is rejected by Busy above.
   if canDuplicate and item.CanDuplicate==false and live(r,item) then r.Done=false end
  end
  return table.unpack(result,2,result.n)
 end
 function self.AddMaxHealth(base,amount,item,args)
  local r=records[item]
  if not r or not r.Busy then return base(amount,item,args) end
  if g.CurrentRun.Hero~=r.Owner then error('Shared Centaur Heart: collector context changed',0) end
  if amount~=item.AddMaxHealth or (args and (args.Thread or args.Delay or args.NoHealing)) then
   error('Shared Centaur Heart: unsupported delayed health application',0)
  end
  local function valid(hero,index)
   return live(r,item) and p.GetHero(index)==hero and hero.ObjectId==r.Ids[index]
    and p.GetPlayerByHero(hero)==index
  end
  for index,hero in ipairs(r.Heroes) do
   if not valid(hero,index) then error('Shared Centaur Heart: owner/world changed',0) end
  end
  if r.Owner.IsDead then error('Shared Centaur Heart: collector died before grant',0) end
  if r.Applied[r.Owner] then return end
  r.Applied[r.Owner]=true -- before mutation; failures must never replay a partial grant
  base(amount,item,args) -- collector keeps the complete stock path once
  for index,hero in ipairs(r.Heroes) do
   if hero~=r.Owner and r.Eligible[index] and not hero.IsDead then
    if not valid(hero,index) then error('Shared Centaur Heart: partner changed',0) end
    c.RunWithHeroContextAwait(hero,function()
     if not valid(hero,index) or g.CurrentRun.Hero~=hero then
      error('Shared Centaur Heart: stale partner context',0)
     end
     if hero.IsDead then return end -- partner death never locks the surviving collector
     r.Applied[hero]=true
     -- Same hidden stock health trait; no second purchase, quest check or LastPickedTraitName write.
     local before=hero.MaxHealth
     local trait=g.GetProcessedTraitData({Unit=hero,TraitName='RoomRewardMaxHealthTrait'})
     trait.PropertyChanges[1].ChangeValue=g.round(amount)
     g.ExtractValues(hero,trait,trait)
     g.AddTraitData(hero,trait,{SkipQuestStatusCheck=true})
     if not(args and args.Silent) then
      g.MaxHealthIncreaseText({MaxHealthGained=hero.MaxHealth-before,SpecialText='MaxHealthIncrease'})
      g.thread(g.UpdateHealthUI,{FalloffDelay=0.0})
     end
    end)
   end
  end
 end
 return self
end
return M
