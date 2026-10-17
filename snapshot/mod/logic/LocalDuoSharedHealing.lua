-- Exact free HealDropMinor only. One stock consumption, personal stock Heal per living owner.
local M={}
function M.New(d)
 local g,p,c=d.Game,d.Players,d.Context
 local records=setmetatable({},{__mode='k'})
 local active=setmetatable({},{__mode='k'}) -- only the coroutine executing this stock consumption
 local function enabled()return d.Gate.IsTestProfile()==true and g.LocalDuoCoopModeActive==true and p.GetPlayersCount()==2 end
 local function pair()
  local a,b=p.GetHero(1),p.GetHero(2)
  if not a or not b or a==b or p.GetPlayerByHero(a)~=1 or p.GetPlayerByHero(b)~=2 then return end
  return {a,b}
 end
 local function world(r)return enabled()and g.CurrentRun==r.Run and r.Run.CurrentRoom==r.Room end
 local function sourceLive(r,item)
  return world(r)and item.ObjectId==r.ItemId and g.MapState.ActiveObstacles[item.ObjectId]==item
 end
 local function heroLive(r,hero,index)
  return world(r)and p.GetHero(index)==hero and hero.ObjectId==r.Ids[index]
   and p.GetPlayerByHero(hero)==index and not hero.IsDead
   and type(hero.Health)=='number'and hero.Health>0 and hero.Health<math.huge
 end
 local self={}
 function self.Owns(item)return records[item]~=nil end
 function self.Create(base,id,name,cost,args)
  local item=base(id,name,cost,args)
  if item and enabled()and pair()and name=='HealDropMinor' and item.Name=='HealDropMinor'
   and cost==0 and item.HealFixed==10 and item.HealFraction==nil
   and not item.BoughtFromShop and not item.ScreenNameOnUse
   and g.MapState.ActiveObstacles[item.ObjectId]==item then
   local free=true
   for _,amount in pairs(item.ResourceCosts or {})do if amount~=0 then free=false end end
   if free then records[item]={Run=g.CurrentRun,Room=g.CurrentRun.CurrentRoom,ItemId=item.ObjectId} end
  end
  return item
 end
 function self.Use(base,item,args,user)
  local r=records[item];if not r then return base(item,args,user)end
  if r.Busy or r.Done or r.Failed or not sourceLive(r,item)then return false end
  local heroes=pair();local owner=g.CurrentRun.Hero
  if not heroes or not owner or owner.IsDead or type(owner.Health)~='number'
   or not(owner.Health>0 and owner.Health<math.huge)or(owner~=heroes[1]and owner~=heroes[2])then return false end
  r.Heroes=heroes;r.Ids={heroes[1].ObjectId,heroes[2].ObjectId};r.Owner=owner
  r.Eligible={not heroes[1].IsDead,not heroes[2].IsDead};r.Applied={};r.Item=item;r.Busy=true
  local co=coroutine.running();local previous=active[co];active[co]=r
  local result=table.pack(pcall(base,item,args,user))
  active[co]=previous;r.Busy=false
  if not result[1]then r.Failed=true;error(result[2],0)end
  if next(r.Applied)then r.Done=true end -- stock HealDropMinor has CanDuplicate=false
  return table.unpack(result,2,result.n)
 end
 function self.Heal(base,victim,args)
  local r=active[coroutine.running()]
  if not r or not r.Busy or victim~=r.Owner or not args or args.SourceName~='HealDropMinor' then
   return base(victim,args)
  end
  if args.HealFraction~=nil or type(args.HealAmount)~='number' or r.Item.CanDuplicate==true then
   error('Shared healing: unexpected stock minor-heal path',0)
  end
  if r.Applied[victim]then return end
  local ownerIndex=p.GetPlayerByHero(victim)
  if not ownerIndex or not heroLive(r,victim,ownerIndex)or not sourceLive(r,r.Item)then
   error('Shared healing: collector/world changed',0)
  end
  local function apply(hero,index,healArgs)
   if not heroLive(r,hero,index)then return end
   r.Applied[hero]=true -- latch before any stock mutation/callback
   local stockArgs=g.DeepCopyTable(healArgs);local silent=stockArgs.Silent
   stockArgs.Silent=true -- avoid stock's cross-owner PresentationQueue merging
   local result=table.pack(base(hero,stockArgs))
   g.FrameState.RequestUpdateHealthUI=true
   if not silent and (stockArgs.ActualHealAmount or 0)>0 then
    local presentation=g.DeepCopyTable(stockArgs);presentation.Silent=silent
    -- Stock presentation body and inherited explicit owner context, not a new UI implementation.
    g.thread(function()
     if heroLive(r,hero,index)then c.RunWithHeroContextAwait(hero,function()
      if heroLive(r,hero,index)then return g.OnPlayerHealed(hero,presentation)end
     end)end
    end)
   end
   return table.unpack(result,1,result.n)
  end
  local result=table.pack(apply(victim,ownerIndex,args)) -- collector uses exact stock-computed amount
  for index,hero in ipairs(r.Heroes)do
   if hero~=victim and r.Eligible[index]then
    if not world(r)or p.GetHero(index)~=hero or hero.ObjectId~=r.Ids[index]then
     error('Shared healing: partner/world changed',0)
    end
    if not hero.IsDead then
     c.RunWithHeroContextAwait(hero,function()
      if not heroLive(r,hero,index)then return end
      local amount=r.Item.HealFixed*g.CalculateHealingMultiplier()
      amount=g.round(amount*g.GetTotalHeroTraitValue('MaxHealthMultiplier',{IsMultiplier=true}))
      apply(hero,index,{HealAmount=amount,SourceName=r.Item.Name})
     end)
    end
   end
  end
  return table.unpack(result,1,result.n)
 end
 return self
end
return M
