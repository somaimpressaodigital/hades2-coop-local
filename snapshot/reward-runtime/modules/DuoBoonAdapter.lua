-- Factory only. No hooks, weapon rewrites, save changes or automatic installation.
local Adapter={}
function Adapter.New(host)
 assert(host.Context and host.Context.RunWithHeroContextAwait,'HeroContext required')
 assert(host.commitChoice,'Provide a validated vanilla-equivalent purchase callback')
 local api=host.Game
 return {
  runAs=function(hero,fn,...)
   -- Must be called from an engine coroutine, as in LocalDuoLobby.
   return host.Context.RunWithHeroContextAwait(hero,fn,...)
  end,
  generate=function(hero,source,player)
   if source.UpgradeOptions==nil then api.SetTraitsOnLoot(source)end
   local result={}
   local limit=math.min(3,api.CalcNumLootChoices(source))
   local candidates=source.UpgradeOptions or {}
   if #candidates>limit then
    assert(host.selectVisibleOptions,'Supply vanilla visible-choice selection; do not bias toward first entries')
    candidates=host.selectVisibleOptions(hero,source,candidates,limit)
   end
   for _,option in ipairs(candidates)do
    if not option.Blocked and #result<limit then
     if option.Type=='TransformingTrait'then
      local chaos=assert(host.Modules.ChaosOffer,'Personal Chaos backend required')
      result[#result+1]=chaos.Prepare(api,api.GetProcessedTraitData,hero,option,player,source)
     else
     local stack=option.StackNum
     if source.StackOnly then
      local owned=assert(api.GetHeroTrait(option.ItemName),'Missing owned boon for pom')
      stack=(owned.StackNum or 1)+(source.StackNum or 1)
     elseif option.TraitToReplace then
      stack=api.GetTraitCount(hero,{Name=option.TraitToReplace})+api.GetTotalHeroTraitValue('ExchangeLevelBonus')
     end
     local data=api.GetProcessedTraitData({Unit=hero,TraitName=option.ItemName,
      Rarity=option.Rarity,StackNum=stack},source)
     data.TraitToReplace=option.TraitToReplace
     local definition=api.TraitData[option.ItemName]
     assert(definition and data,'Invalid eligible trait')
     api.SetTraitTextData(data)
     result[#result+1]={ItemName=option.ItemName,Rarity=option.Rarity or 'Common',
      Title=api.GetTraitTooltipTitle(definition),Description=api.GetTraitTooltip and api.GetTraitTooltip(data,{Default=definition.Title})or option.ItemName,
      Icon=data.Icon,Frame=api.GetTraitFrame(data),Data=data,Raw=option,
      Owner=player,StackOnly=source.StackOnly,StackNum=source.StackNum,
      Blocked=data.LocalDuoUnsupported==true or nil,UnsupportedReason=data.LocalDuoUnsupportedReason}
     end
    end
   end
   return result
  end,
  apply=function(hero,source,choice,request)
   assert(choice.Owner==request.Player,'Choice belongs to another panel')
   -- Adapter leaves swaps, poms, costs, double boons, bans, codex and cleanup
   -- to the host's complete purchase implementation, not a partial AddTrait.
   return host.commitChoice(hero,source,choice,request)
  end,
  valid=host.valid,
  onComplete=host.onComplete,
 }
end
return Adapter
