-- One collection/same god; raw native draws and processed traits are personal.
local M={}
function M.Normalize(g,args)
 local a,b=args.sources[1],args.sources[2]
 if not a.LocalDuoCommonRoot then return end
 assert(b.LocalDuoCommonCarrier and b.LocalDuoCommonRootId==a.ObjectId and a.Name==b.Name,'Common source identity mismatch')
 assert(a.UpgradeOptions and b.UpgradeOptions and a.UpgradeOptions~=b.UpgradeOptions,'Common pools must be separate tables')
 -- Already generated under each owner. Validation only: never copy or reroll here.
end
function M.PersonalRaw(g,hero,raw,source)
 local out=g.DeepCopyTable(raw)
 if not(source.LocalDuoCommonRoot or source.LocalDuoCommonCarrier)or source.StackOnly then return out end
 local def=g.TraitData[out.ItemName]
 if not def or not def.Slot then return out end
 -- GetReplacementTraits occupant/rank rule, without its random selector.
 local occupied
 for _,trait in ipairs(hero.Traits or{})do
  if trait.Slot==def.Slot then
   if not occupied then occupied={TraitName=trait.Name,Rarity='Common'}end
   if trait.Rarity and g.GetRarityValue(trait.Rarity)>g.GetRarityValue(occupied.Rarity)then occupied.Rarity=trait.Rarity end
  end
 end
 out.TraitToReplace=nil;out.OldRarity=nil
 if not occupied then return out end
 -- Personal pool is already rolled. Preserve its rarity; no reroll/requalification.
 out.TraitToReplace=occupied.TraitName;out.OldRarity=occupied.Rarity
 return out
end
function M.Reason(g,hero,raw,source)
 if not(source.LocalDuoCommonRoot or source.LocalDuoCommonCarrier)then return end
 local def=g.TraitData[raw.ItemName]
 if not def then return 'Dados da opção indisponíveis.' end
 if raw.Type=='TransformingTrait' or raw.ItemName=='FallbackGold'then return 'Esta opção exige outro fluxo de recompensa.' end
 if source.StackOnly then
  local eligible=g.GetAllUpgradeableGodTraits(source.StackNum)
  if not eligible[raw.ItemName]then return 'Este jogador não possui esta bênção para melhorar.' end
  return
 end
 -- Native personal draws are authoritative; do not add another eligibility filter.
end
function M.Blocked(g,hero,raw,p,source,reason)
 local data=g.GetProcessedTraitData({Unit=hero,TraitName=raw.ItemName,Rarity=raw.Rarity})
 local def=assert(g.TraitData[raw.ItemName]);g.SetTraitTextData(data)
 data.LocalDuoUnsupported=true;data.LocalDuoUnsupportedReason=reason
 return {ItemName=raw.ItemName,Rarity=raw.Rarity or 'Common',Owner=p,Data=data,Icon=data.Icon,
  Title=g.GetTraitTooltipTitle(def),Description=g.GetTraitTooltip and g.GetTraitTooltip(data,{Default=def.Title})or raw.ItemName,
  Frame=g.GetTraitFrame(data),StackOnly=source.StackOnly,StackNum=source.StackNum,Raw=raw,Blocked=true,UnsupportedReason=reason}
end
return M
