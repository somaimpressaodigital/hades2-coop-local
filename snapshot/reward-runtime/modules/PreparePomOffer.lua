-- Native H2 pom preview only. Application remains existing Host/Apply responsibility.
local M={}
function M.Prepare(api,process,hero,raw,owner,source)
 assert(source.StackOnly==true,'Pom source required')
 assert(raw.ItemName~='FallbackGold','Pom without owned traits needs native gold fallback')
 local owned=assert(api.GetHeroTrait(raw.ItemName),'Missing owned boon for pom')
 assert(hero.TraitDictionary and hero.TraitDictionary[raw.ItemName]
  and hero.TraitDictionary[raw.ItemName][1]==owned,'Owned boon context mismatch')
 local levels=source.StackNum or 1
 assert(type(levels)=='number'and levels>0 and levels%1==0,'Invalid pom level count')
 local old=owned.StackNum or 1
 local replacement=process{Unit=hero,TraitName=raw.ItemName,StackNum=old+levels,
  RarityMultiplier=owned.RarityMultiplier}
 local tooltip=api.DeepCopyTable(owned) -- SetTraitTextData must never mutate the owned build.
 tooltip.OldLevel=old;tooltip.NewLevel=old+levels
 tooltip.LocalDuoUnsupported=replacement.LocalDuoUnsupported
 tooltip.LocalDuoUnsupportedReason=replacement.LocalDuoUnsupportedReason
 api.SetTraitTextData(tooltip,{ReplacementTraitData=replacement})
 local definition=assert(api.TraitData[raw.ItemName],'Unknown native boon')
 local title=api.GetTraitTooltipTitle(definition)
 return {ItemName=raw.ItemName,Owner=owner,Rarity=owned.Rarity or 'Common',Data=tooltip,
  Icon=tooltip.Icon,Title=title,Description=api.GetTraitTooltip and api.GetTraitTooltip(tooltip,{Default=title})or raw.ItemName,
  Frame=api.GetTraitFrame(tooltip),StackOnly=true,StackNum=levels,
  Blocked=tooltip.LocalDuoUnsupported==true,UnsupportedReason=tooltip.LocalDuoUnsupportedReason}
end
return M
