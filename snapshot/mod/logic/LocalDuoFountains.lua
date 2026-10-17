-- Apply actor-specific benefits while the fountain itself is consumed once.
local Fountains={}
function Fountains.Apply(used,user)
    local hero=CurrentRun.Hero
    local delay=0
    for _,trait in ipairs(hero.Traits or {})do
        if trait.FountainDamageBonus then
            trait.AccumulatedFountainDamageBonus=(trait.AccumulatedFountainDamageBonus or 0)+trait.FountainDamageBonus-1
            ExtractValues(hero,trait,trait)
        end
        if trait.FountainRarity and (trait.Uses or 0)>0 and HasRarifiableTraits(trait.FountainRarity)then
            ReduceTraitUses(trait)
            local args=ShallowCopyTable(trait.FountainRarity);args.Delay=delay
            thread(AddRarityToTraits,trait,args);delay=delay+1
        end
        if trait.FountainRefreshUses then
            thread(SpellPotionRefillPresentation,used,user,trait,0.2,delay)
            local bonus=GetTotalHeroTraitValue("BonusSpellUses")
            trait.RemainingUses=(HasHeroTraitValue("RolloverSpellUses") and trait.RemainingUses or 0)+trait.MaxUses+bonus
            SetWeaponProperty({WeaponName=trait.PreEquipWeapons[1],DestinationId=hero.ObjectId,Property="Enabled",Value=true})
            UpdateTraitNumber(trait);TraitUIDeactivateTrait(trait);delay=delay+1
        end
    end
    local fraction=(used.HealFraction or 0)+GetTotalHeroTraitValue("FountainHealFractionBonus")
    local override=GetTotalHeroTraitValue("FountainHealFractionOverride")
    if override>0 then fraction=override end
    Heal(hero,{HealFraction=fraction*CalculateHealingMultiplier(),SourceName="HealthFountain"})
    UpdateHealthUI()
end
return Fountains
