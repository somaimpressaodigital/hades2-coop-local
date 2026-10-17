local Audio=ModRequire 'LocalDuoOriginalAudio.lua'
local Sword={Names={'LocalDuoH1_SwordWeapon','LocalDuoH1_SwordWeapon2','LocalDuoH1_SwordWeapon3','LocalDuoH1_SwordWeaponDash','LocalDuoH1_SwordParry'}}
local function add(set,name)
    WeaponSets[set]=WeaponSets[set]or{}
    local found=false
    for _,v in ipairs(WeaponSets[set])do if v==name then found=true end end
    if not found then table.insert(WeaponSets[set],name)end
    WeaponSetLookups[set]=WeaponSetLookups[set]or{};WeaponSetLookups[set][name]=true
end
function Sword.Register()
    if Sword.Registered or not WeaponData or not WeaponSets or not WeaponSetLookups then return end
    for i,name in ipairs(Sword.Names)do
        WeaponData[name]={Name=name,UpgradeChoiceText=i==5 and 'UpgradeChoiceMenu_Secondary' or 'UpgradeChoiceMenu_Melee',
            SkipAttackNotReadySounds=true,CauseImpactReaction=true,DefaultKnockbackForce=800,
            DefaultKnockbackScale=1.0,MinWeaponChargeTime=0.1,
            SpeedPropertyChanges=DeepCopyTable(WeaponData.DefaultWeaponValues.DefaultSpeedPropertyChanges),
            SelfMultiplier=0,StartingWeapon=true}
        GameData.MissingPackages[name]=true
        add('HeroAllWeapons',name);add('HeroPhysicalWeapons',name);add('HeroNonExWeapons',name)
        if i<5 then add('HeroMeleeRangeWeapons',name);add('HeroPrimaryPhysicalWeapons',name)end
    end
    local primary=WeaponData[Sword.Names[1]]
    primary.DashWeapon=Sword.Names[4];primary.SecondaryWeapon=Sword.Names[5]
    primary.ExpireDashWeaponOnDash=true
    primary.DashSwaps={Sword.Names[1],Sword.Names[2],Sword.Names[3]}
    add('HeroPrimaryWeapons',Sword.Names[1]);add('HeroPrimarySecondaryWeapons',Sword.Names[1]);add('HeroPrimarySecondaryWeapons',Sword.Names[5])
    add('HeroDashWeapons',Sword.Names[4]);add('HeroSecondaryWeapons',Sword.Names[5])
    WeaponSets.HeroWeaponSets[Sword.Names[1]]={Sword.Names[2],Sword.Names[3],Sword.Names[4]}
    WeaponSets.HeroWeaponSets[Sword.Names[5]]={}
    Audio.RegisterSword()
    Sword.Registered=true
end
function Sword.Equip(hero)
    assert(hero.LocalDuoUsesLegacySwordMechanics==true,'Legacy H1 mechanics require explicit opt-in')
    assert(hero.LocalDuoOriginalActor==hero.ObjectId,'Independent original actor required')
    Sword.Register();assert(Sword.Registered,'Original sword metadata unavailable')
    LoadPackages({Names={'Fx','WeaponDagger','WeaponAxe'}})
    local remove={};local seen={}
    local function collect(name)
        if seen[name]or name:sub(1,11)=='LocalDuoH1_'then return end
        seen[name]=true;remove[#remove+1]=name
        for _,child in ipairs(WeaponSets.HeroWeaponSets[name]or{})do collect(child)end
    end
    for name in pairs(hero.Weapons)do
        if WeaponSetLookups.HeroPrimaryWeapons[name] or WeaponSetLookups.HeroSecondaryWeapons[name]
            or WeaponSetLookups.HeroMeleeRangeWeapons[name] or WeaponSetLookups.HeroDashWeapons[name] then
            collect(name)
        end
    end
    for _,name in ipairs(remove)do
        UnequipWeapon({DestinationId=hero.ObjectId,Name=name,UnloadPackages=false});hero.Weapons[name]=nil
    end
    for _,name in ipairs(Sword.Names)do EquipWeapon({DestinationId=hero.ObjectId,Name=name,LoadPackages=false})end
    hero.Weapons[Sword.Names[1]]=true;hero.Weapons[Sword.Names[5]]=true
    hero.LocalDuoOriginalSword=true
    Audio.Apply(hero)
end
Sword.Register()
return Sword
