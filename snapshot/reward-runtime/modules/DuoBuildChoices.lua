-- Isolated reward coordinator. No hooks, engine globals or weapon changes.
-- New/Drain must run in an engine coroutine after host integration.
local Choices={};Choices.__index=Choices
local function tables(value,out)
 if type(value)~='table' or out[value]then return end
 out[value]=true;for _,v in pairs(value)do tables(v,out)end
end
local function isolated(a,b)
 local left,right={},{}
 for _,key in ipairs({'Traits','TraitDictionary','LocalDuoBuildReceipts','LocalDuoBoonReceipts'})do
  tables(a[key],left);tables(b[key],right)
 end
 for t in pairs(left)do assert(not right[t],'Heroes share mutable build state')end
end
function Choices.New(host)
 assert(type(host.rewardKey)=='string' and host.rewardKey~='','Stable run/room/bundle reward key required')
 assert(host.Context and host.Context.RunWithHeroContextAwait and host.Context.GetCurrentHeroContext,'HeroContext required')
 assert(host.Apply and host.Apply.commit and host.Apply.supported and host.clone and host.valid,'Application, clone and validity callbacks required')
 local a,b=host.heroes[1],host.heroes[2]
 assert(a and b and a~=b and a.ObjectId and b.ObjectId and a.ObjectId~=b.ObjectId,'Two distinct actors required')
 isolated(a,b)
 local self=setmetatable({Host=host,Panels={},Queue={},Draining=false,Closed=false},Choices)
 local bundle
 for p=1,2 do
  local hero,source=host.heroes[p],assert(host.sources[p],'Missing personal reward')
  assert(source.LocalDuoOwner==p,'Reward owner mismatch')
  assert(source.LocalDuoBundle~=nil,'Missing LootIndividual bundle')
  if p==1 then bundle=source.LocalDuoBundle else assert(bundle==source.LocalDuoBundle,'Rewards from different bundles')end
  local panel={Hero=hero,Source=host.clone(source),Offers=host.clone(host.offers[p]),Status='choosing',Player=p}
  assert(type(panel.Offers)=='table' and #panel.Offers>0,'Missing personal offers')
  for _,choice in ipairs(panel.Offers)do assert(choice.Owner==p,'Offer owner mismatch')end
  panel.Key=host.rewardKey..':J'..p
  local prior=hero.LocalDuoBuildReceipts and hero.LocalDuoBuildReceipts[panel.Key]
  if prior then
   assert(prior.Player==p,'Receipt owner mismatch')
   panel.Status=prior.Status=='committed' and 'committed' or 'uncertain';panel.Receipt=prior
  elseif hero.IsDead then panel.Status='dead' end
  self.Panels[p]=panel
 end
 return self
end
function Choices:Confirm(player,index)
 local panel=assert(self.Panels[player],'Unknown player')
 if self.Closed or panel.Status~='choosing'then return false end
 if panel.Hero.IsDead then panel.Status='dead';return false end
 local choice=panel.Offers[index]
 if not choice or choice.Blocked then return false end
 panel.Status='queued'
 self.Queue[#self.Queue+1]={Player=player,Index=index,Choice=self.Host.clone(choice)}
 return true
end
function Choices:RequestReroll(player)
 local panel=assert(self.Panels[player],'Unknown player')
 if self.Closed or panel.Status~='choosing'or panel.Hero.IsDead or type(self.Host.reroll)~='function'then return false end
 panel.Status='queued'
 self.Queue[#self.Queue+1]={Player=player,Kind='reroll',ExpectedOffers=panel.Offers}
 return true
end
function Choices:Cancel(player)
 local panel=assert(self.Panels[player],'Unknown player')
 if panel.Status~='choosing' and panel.Status~='queued'then return false end
 panel.Status='cancelled'
 for i=#self.Queue,1,-1 do if self.Queue[i].Player==player then table.remove(self.Queue,i)end end
 return true
end
function Choices:Abort(reason)
 self.Closed=true;self.AbortReason=reason
 self:Cancel(1);self:Cancel(2)
 -- A yielding application already in progress cannot be rolled back.
end
function Choices:Drain()
 if self.Draining or self.Closed then return end
 self.Draining=true
 while #self.Queue>0 and not self.Closed do
  local request=table.remove(self.Queue,1);local panel=self.Panels[request.Player];local hero=panel.Hero
  if request.Kind=='reroll' and panel.Status=='queued'then
   if hero.IsDead then panel.Status='dead'
   else
    panel.Status='applying'
    local ok,result=pcall(function()
     local outcome=self.Host.reroll(request.Player,request)
     if type(outcome)=='table'and outcome.Status=='rerolled'then
      assert(type(outcome.Offers)=='table'and #outcome.Offers>0 and type(outcome.Source)=='table','Missing rerolled owner data')
      for _,offer in ipairs(outcome.Offers)do assert(offer.Owner==request.Player,'Reroll offer owner mismatch')end
      return {Status='rerolled',Source=self.Host.clone(outcome.Source),Offers=self.Host.clone(outcome.Offers)}
     end
     return outcome
    end)
    panel.RerollAttemptSerial=(panel.RerollAttemptSerial or 0)+1
    if not ok or type(result)~='table'or result.Status=='uncertain'then
     panel.Status='uncertain';panel.Error=tostring(ok and result and result.Error or result)
    elseif result.Status=='rerolled'then
     panel.Source=result.Source;panel.Offers=result.Offers
     panel.RerollRevision=(panel.RerollRevision or 0)+1;panel.Status='choosing';panel.RerollError=nil
    else panel.Status='choosing';panel.RerollError='Não foi possível alterar as opções'end
   end
  elseif panel.Status=='queued'then
   if hero.IsDead then panel.Status='dead'
   else
    panel.Status='applying'
    local started=false
    local ok,result=pcall(function()
     return self.Host.Context.RunWithHeroContextAwait(hero,function()
      assert(self.Host.Context.GetCurrentHeroContext()==hero,'Wrong hero context')
      assert(not self.Closed and not hero.IsDead,'Reward cancelled or hero dead')
      assert(self.Host.heroes[request.Player]==hero,'Controlled hero changed')
      assert(self.Host.valid(hero,panel.Source,request.Player),'Room or reward no longer valid')
      if self.Host.LootIndividual then
       local original=self.Host.sources[request.Player];local root=self.Host.sources[1]
       if original and original.LocalDuoCommonCarrier then
        -- Only the private UI application may use J2's registered carrier; world pickup stays forbidden.
        assert(request.Player==2 and root and root.LocalDuoCommonRoot==true and root.LocalDuoOwner==1
         and original==self.Host.sources[2] and original.LocalDuoOwner==2 and panel.Source.LocalDuoOwner==2
         and original.ObjectId==panel.Source.ObjectId and panel.Source.LocalDuoCommonCarrier==true
         and original.LocalDuoCommonRootId==root.ObjectId and panel.Source.LocalDuoCommonRootId==root.ObjectId
         and original.LocalDuoBundle~=nil and original.LocalDuoBundle==root.LocalDuoBundle
         and panel.Source.LocalDuoBundle==original.LocalDuoBundle
         and original.Name==root.Name and panel.Source.Name==original.Name,'Invalid internal common reward carrier')
       else
        assert(self.Host.LootIndividual.CanUseHeroLoot(panel.Source,hero),'Personal loot denied')
       end
      end
      isolated(self.Host.heroes[1],self.Host.heroes[2])
      assert(panel.Source.LocalDuoOwner==request.Player and request.Choice.Owner==request.Player,'Owner mismatch')
      local supported,reason=self.Host.Apply.supported(hero,panel.Source,request.Choice)
      assert(supported,reason)
      hero.LocalDuoBuildReceipts=hero.LocalDuoBuildReceipts or {}
      local prior=hero.LocalDuoBuildReceipts[panel.Key]
      if prior then assert(prior.Status=='committed','Uncertain reward cannot retry');return prior end
      local receipt={Status='applying',Player=request.Player,Index=request.Index,Name=request.Choice.ItemName,Key=panel.Key}
      hero.LocalDuoBuildReceipts[panel.Key]=receipt;started=true;panel.Receipt=receipt
      -- Stable reward token: never use a UI revision or fresh screen ID.
      local applied=self.Host.Apply.commit(hero,panel.Source,self.Host.clone(request.Choice),
       {Token=panel.Key,Player=request.Player,Index=request.Index})
      assert(type(applied)=='table' and applied.Status=='committed','Application did not acknowledge commit')
      receipt.Status='committed';return receipt
     end)
    end)
    if ok then panel.Status='committed';panel.Receipt=result
    elseif started then
     panel.Status='uncertain';panel.Receipt.Status='uncertain';panel.Receipt.Error=tostring(result)
    else panel.Status=hero.IsDead and 'dead' or 'rejected';panel.Error=tostring(result)end
   end
  end
  -- Let the session supervisor abort pending choices after an application error.
  if panel.Status=='uncertain' or panel.Status=='rejected'then break end
 end
 self.Draining=false
end
function Choices:Result()
 return {ReadyForCleanup=self.Panels[1].Status=='committed' and self.Panels[2].Status=='committed',
  Closed=self.Closed,J1=self.Panels[1].Status,J2=self.Panels[2].Status}
end
return Choices
