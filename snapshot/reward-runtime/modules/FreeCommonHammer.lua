-- Eligibility only; existing native trait processing/application remains authoritative.
local M={}
function M.New(d)
 local api,ctx=assert(d.Game),assert(d.Context)
 local self={}
 function self:Check(hero,source)
  if api.LocalDuoCoopModeActive~=true or d.Gate.IsTestProfile()~=true or ctx.GetCurrentHeroContext()~=hero
   or not hero or hero.IsDead or source.Name~='WeaponUpgrade' or source.GodLoot~=false
   or source.StackOnly or source.ResourceCosts or source.BoughtFromShop or source.UpgradeOnPick
   or source.Cost or source.AltCost or source.TransformingTrait then return false,'Only ordinary free H2 hammer supported' end
  if type(api.IsTraitEligible)~='function' then return false,'Native trait eligibility unavailable'end
  local root,count=nil,0
  for _,name in ipairs(api.WeaponSets.HeroPrimaryWeapons or{})do if hero.Weapons and hero.Weapons[name]then root=name;count=count+1 end end
  if count~=1 then return false,'Current H2 weapon root ambiguous'end
  local loot=api.LootData and api.LootData.WeaponUpgrade
  local pool=source.UpgradeOptions
  if not loot or type(loot.Traits)~='table'or type(pool)~='table'or #pool==0 then return false,'Actual hammer pool required'end
  local index={};for _,name in ipairs(loot.Traits)do index[name]=true end
  for _,raw in ipairs(pool)do
   local definition=api.TraitData[raw.ItemName]
   if raw.Type~='Trait'or raw.TraitToReplace or raw.ItemName=='FallbackGold'
    or(raw.Rarity and raw.Rarity~='Common')or not index[raw.ItemName]or not definition
    or definition.IsHammerTrait~=true or definition.CodexWeapon~=root
    or api.IsTraitEligible(definition)~=true then return false,'Hammer option is not eligible for this owner weapon'end
  end
  return true
 end
 return self
end
return M
