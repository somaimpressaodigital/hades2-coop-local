-- Only NarcissusA's native random pom; shared seed drops and NPC dialogue stay stock once.
local M={}
function M.New(d)
 local g,p,c=d.Game,d.Players,d.Context
 local spawning=setmetatable({},{__mode='k'});local consuming=setmetatable({},{__mode='k'})
 local items=setmetatable({},{__mode='k'});local pending={};local serial=0
 local function enabled()return g.LocalDuoCoopModeActive==true and d.Gate.IsTestProfile()==true and p.GetPlayersCount()==2 end
 local function alive(h)return h and not h.IsDead and type(h.Health)=='number'and h.Health>0 and h.Health<math.huge end
 local function world(r)return enabled()and g.CurrentRun==r.Run and r.Run.CurrentRoom==r.Room and g.MapState==r.Map end
 local function current(r,h,i)return world(r)and p.GetHero(i)==h and type(h.ObjectId)=='number'and h.ObjectId>0
  and h.ObjectId==r.Ids[i]and p.GetPlayerByHero(h)==i and alive(h)end
 local self={}
 function self.Owns(item)return items[item]~=nil end
 function self.Give(base,args,trait,contextArgs)
  if not enabled()or not trait or trait.Name~='NarcissusA' then return base(args,trait,contextArgs)end
  local co=coroutine.running();local previous=spawning[co]
  spawning[co]={Run=g.CurrentRun,Room=g.CurrentRun.CurrentRoom,Map=g.MapState}
  local r=table.pack(pcall(base,args,trait,contextArgs));spawning[co]=previous
  if not r[1]then error(r[2],0)end;return table.unpack(r,2,r.n)
 end
 function self.Create(base,id,name,cost,args)
  local item=base(id,name,cost,args);local scope=spawning[coroutine.running()]
  if scope and world(scope)and item and name=='StoreRewardRandomStack'and item.Name==name and cost==0
   and item.UseFunctionName=='UseStoreRewardRandomStack' and not item.BoughtFromShop and not item.ScreenNameOnUse
   and g.MapState.ActiveObstacles[item.ObjectId]==item then
   local free=true;for _,v in pairs(item.ResourceCosts or{})do if v~=0 then free=false end end
   if free then items[item]={Run=scope.Run,Room=scope.Room,Map=scope.Map,Id=item.ObjectId}end
  end
  return item
 end
 function self.Use(base,item,args,user)
  local r=items[item];if not r then return base(item,args,user)end
  if r.Busy or r.Used or r.Failed or not world(r)or item.ObjectId~=r.Id or g.MapState.ActiveObstacles[r.Id]~=item then return false end
  local h={p.GetHero(1),p.GetHero(2)};local owner=g.CurrentRun.Hero
  if not h[1]or not h[2]or h[1]==h[2]or not alive(owner)or type(owner.ObjectId)~='number'or owner.ObjectId<=0
   or (owner~=h[1]and owner~=h[2])then return false end
  r.Heroes=h;r.Ids={h[1].ObjectId,h[2].ObjectId};r.Eligible={alive(h[1])==true,alive(h[2])==true};r.Owner=owner;r.Busy=true;r.WorldSucceeded=false
  local co=coroutine.running();local previous=consuming[co];consuming[co]=r
  local result=table.pack(pcall(base,item,args,user));consuming[co]=previous;r.Busy=false
  if not result[1]then r.Failed=true;error(result[2],0)end
  r.WorldSucceeded=true;return table.unpack(result,2,result.n)
 end
 function self.UseRandomPom(base,args)
  local r=consuming[coroutine.running()]
  if not r then return base(args)end
  if r.Used then return end
  assert(world(r)and g.CurrentRun.Hero==r.Owner,'Narcissus pom owner changed')
  r.Used=true;r.OriginalArgs=g.DeepCopyTable(args or{})
  serial=serial+1;r.Token=serial;pending[serial]=r
  local copy=g.DeepCopyTable(args or{});copy.LocalDuoNarcissusPomToken=serial
  return base(copy) -- checkpoint invalidation/pickup presentation exactly once
 end
 function self.Stacks(base,source,args)
  local options=args or source;local token=type(options)=='table'and options.LocalDuoNarcissusPomToken
  if not token then return base(source,args)end
  local r=pending[token];if not r or r.Started then return end
  r.Started=true
  local result=table.pack(pcall(function()
   g.wait(options.Delay) -- stock delay once, before checking current recipients
   if r.Failed or not r.WorldSucceeded or not world(r)then return end
   for i,hero in ipairs(r.Heroes)do
    if r.Eligible[i]and current(r,hero,i)then
     c.RunWithHeroContextAwait(hero,function()
      if not current(r,hero,i)then return end
      local own=g.DeepCopyTable(hero==r.Owner and options or r.OriginalArgs)
      own.LocalDuoNarcissusPomToken=nil;own.Thread=false;own.Delay=nil
      if hero~=r.Owner and own.NumStacks and g.IsFateValid()then
       own.NumStacks=own.NumStacks+g.GetTotalHeroTraitValue('FatedPomLevelBonus')
      end
      -- Actual stock random choice from THIS owner's eligible traits, no manual selection substitution.
      base({},own)
     end)
    end
   end
  end))
  pending[token]=nil
  if not result[1]then r.Failed=true;error(result[2],0)end
  return table.unpack(result,2,result.n)
 end
 return self
end
return M
