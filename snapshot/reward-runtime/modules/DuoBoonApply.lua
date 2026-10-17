-- Concrete application for standard traits, exchanges and poms only.
-- Lifecycle/purchase side effects remain the host's responsibility.
local Apply={}
function Apply.New(api)
 assert(api.currentHero and api.clone,'Context and copy helpers required')
 local function supported(hero,source,choice)
  if choice.Raw and choice.Raw.Type=='TransformingTrait'and(not api.chaosChoiceAllowed or api.chaosChoiceAllowed(hero,source,choice)~=true)then return false,'Exact prepared personal Chaos pair required'end
  if source.UpgradeOnPick or source.Cost or source.AltCost then
   return false,'Special purchase semantics need vanilla purchase flow'
  end
  if source.CanDuplicate and (not api.duplicateChance or api.duplicateChance(hero)>0)then
   return false,'Reward duplication needs vanilla purchase flow'
  end
  if source.BanUnpickedBoonsEligible and (not api.banCount or api.banCount()>0)then
   return false,'Unpicked boon bans need vanilla purchase flow'
  end
  if api.hasDoubleBoon and api.hasDoubleBoon(hero)then return false,'Double boon needs vanilla purchase flow'end
  return true
 end
 local function commit(hero,source,choice,request)
  assert(api.currentHero()==hero,'Wrong hero context at application')
  assert(not hero.IsDead,'Dead hero cannot receive a new build choice')
  assert(request and type(request.Token)=='string' and request.Token~='' and (request.Player==1 or request.Player==2),'Stable owner token required')
  assert(not source.LocalDuoOwner or source.LocalDuoOwner==request.Player,'Reward belongs to partner')
  assert(not choice.Owner or choice.Owner==request.Player,'Choice belongs to partner')
  local ok,reason=supported(hero,source,choice);assert(ok,reason)
  local prior=hero.LocalDuoBoonReceipts and hero.LocalDuoBoonReceipts[request.Token]
  if prior then
   assert(prior.Player==request.Player,'Receipt belongs to partner')
   assert(prior.Status=='committed','Previous application is uncertain; do not retry')
   return prior
  end
  if source.StackOnly and choice.ItemName~='FallbackGold'then
   assert(hero.TraitDictionary and hero.TraitDictionary[choice.ItemName] and hero.TraitDictionary[choice.ItemName][1],'Missing owned boon for pom')
   local levels=source.StackNum or 1
   assert(type(levels)=='number' and levels>0 and levels%1==0,'Invalid pom level count')
   assert(api.IncreaseTraitLevel,'Missing pom application callback')
  else
   assert(type(choice.Data)=='table' and api.AddTraitToHero,'Missing processed boon or add callback')
   if choice.Raw and choice.Raw.TraitToReplace then
    assert(hero.TraitDictionary and hero.TraitDictionary[choice.Raw.TraitToReplace] and hero.TraitDictionary[choice.Raw.TraitToReplace][1],'Missing owned boon for exchange')
    assert(api.RemoveWeaponTrait,'Missing exchange callback')
   end
  end
  hero.LocalDuoBoonReceipts=hero.LocalDuoBoonReceipts or {}
  local receipt={Status='applying',Player=request.Player,Name=choice.ItemName,Token=request.Token}
  hero.LocalDuoBoonReceipts[request.Token]=receipt
  local success,errorText=pcall(function()
   if source.StackOnly and choice.ItemName~='FallbackGold'then
    local existing=assert(hero.TraitDictionary[choice.ItemName] and hero.TraitDictionary[choice.ItemName][1],'Missing owned boon for pom')
    api.IncreaseTraitLevel(existing,source.StackNum or 1)
   else
    local data=api.clone(choice.Data)
    if choice.Raw and choice.Raw.TraitToReplace then
     api.RemoveWeaponTrait(choice.Raw.TraitToReplace)
    end
    api.AddTraitToHero({TraitData=data,PreProcessedForDisplay=true,FromLoot=true})
   end
   hero.LocalDuoPickedTraits=hero.LocalDuoPickedTraits or {}
   hero.LocalDuoPickedTraits[choice.ChaosPair and choice.Data.Name or choice.ItemName]=true
   if api.recordPick then api.recordPick(hero,source,choice,request)end
  end)
  if not success then receipt.Status='uncertain';receipt.Error=tostring(errorText);error(errorText)end
  receipt.Status='committed';return receipt
 end
 return {supported=supported,commit=commit}
end
return Apply
