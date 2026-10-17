-- Original Hades I event names verified against both installed GUID lists.
-- Hades II retains these events. Never changes the shared Melinoe definitions.
local Audio={}
local function sounds(...)
    local list={};for _,name in ipairs({...})do list[#list+1]={Name=name}end;return list
end
local attack1=sounds('/VO/ZagreusEmotes/EmoteAttacking_Sword','/SFX/Player Sounds/ZagreusSwordSwipe')
local attack2=sounds('/VO/ZagreusEmotes/EmoteAttacking','/SFX/Player Sounds/ZagreusSwordOverhead')
local attack3=sounds('/VO/ZagreusEmotes/EmotePowerAttacking_Sword')
function Audio.RegisterSword()
    for name,list in pairs({LocalDuoH1_SwordWeapon=attack1,LocalDuoH1_SwordWeapon2=attack2,
        LocalDuoH1_SwordWeapon3=attack3,LocalDuoH1_SwordWeaponDash=attack1,
        LocalDuoH1_SwordParry=sounds('/VO/ZagreusEmotes/EmoteParry_Sword')})do
        if WeaponData[name]then WeaponData[name].Sounds={FireSounds=DeepCopyTable(list)}end
    end
end
function Audio.Apply(hero)
    if not hero or hero.LocalDuoOriginalActor~=hero.ObjectId then return end
    Audio.RegisterSword()
    if LocalDuoLoadOriginalBank then LocalDuoLoadOriginalBank()end
    hero.WeaponDataOverride=hero.WeaponDataOverride or {}
    for name,list in pairs({WeaponBlink=sounds('/VO/ZagreusEmotes/EmoteEvading','/SFX/Player Sounds/ZagreusDash'),
        WeaponCast=sounds('/SFX/Player Sounds/ZagreusBloodshotFire')})do
        local personal=hero.WeaponDataOverride[name] or DeepCopyTable(WeaponData[name])
        personal.Sounds=DeepCopyTable(personal.Sounds or {})
        personal.Sounds.FireSounds=DeepCopyTable(list)
        personal.Sounds.ChargeSounds={{Name='/Leftovers/SFX/AuraCharge',
            StoppedBy={'ChargeCancel','Fired'},StoppedByLookup={ChargeCancel=true,Fired=true}}}
        hero.WeaponDataOverride[name]=personal
    end
end
function Audio.Probe(hero)
    local results={}
    for _,cue in ipairs({'/SFX/Player Sounds/ZagreusSwordSwipe','/SFX/Player Sounds/ZagreusSwordOverhead',
        '/SFX/Player Sounds/ZagreusSwordParry','/VO/ZagreusEmotes/EmoteAttacking_Sword',
        '/VO/ZagreusEmotes/EmoteParry_Sword','/VO/ZagreusEmotes/EmoteEvading'})do
        local id=PlaySound({Name=cue,Id=hero.ObjectId})
        results[#results+1]=cue..'='..tostring(id)
        wait(0.25)
    end
    return table.concat(results,';')
end
return Audio
