-- Visual-only native binding candidate. Disposable Profile3, once per map.
-- Never hides the old actor until BOTH native ownership directions are verified.
local HeadLabel=(ModRequire "../config.lua").TextAbovePlayersParams or{}
local Players=ModRequire "CoopPlayers.lua"
local Context=ModRequire "HeroContext.lua"
local Native=ModRequire "HeroContextNative.lua"
local HeroEx=ModRequire "HeroEx.lua"
local HookUtils=ModRequire "../utils/HookUtils.lua"
local Events=ModRequire "Events.lua"
local Gate=ModRequire "LocalDuoRenderProbe.lua"
local Character=ModRequire "LocalDuoCharacter.lua"
local Sword=ModRequire "LocalDuoOriginalSword.lua"
local Test={}
local function verified(player,id)
    local a,b=Players.GetHero(1),Players.GetHero(2)
    local r=LocalDuoNativeBindingProbe(player==1 and id or a.ObjectId,player==2 and id or b.ObjectId)
    return r and r.Validated==true
end
function Test.Update(write)
    -- Never infer an original actor owner from "not J1": both may be Melinoe.
    local player
    for owner=1,2 do
        if Character.Name(owner)=="Zagreus" then player=owner;break end
    end
    if not player then return end
    if not CurrentRun or not SessionMapState or LocalDuoPreparationPending
        or next(ActiveScreens or {}) or not LocalDuoNativeBindActor then return end
    local a,b=Players.GetHero(1),Players.GetHero(2)
    if not a or not b or a.IsDead or b.IsDead or SessionMapState.OriginalBindingAttempted then return end
    if not Gate.IsTestProfile() then SessionMapState.OriginalBindingAttempted=true;return end
    local baseline=LocalDuoNativeBindingProbe(a.ObjectId,b.ObjectId)
    if not baseline or not baseline.Validated then return end
    SessionMapState.OriginalBindingAttempted=true
    thread(function()
    if Character.Name(player)~="Zagreus" then return end
    local hero=Players.GetHero(player)
    local old=hero.ObjectId
    local entryScope={Run=CurrentRun,Room=CurrentHubRoom or CurrentRun.CurrentRoom,Map=MapState}
    if hero.LocalDuoOriginalActor==old then return end
    local inventory=DeepCopyTable(hero.Weapons)
    local new,bound
    local health,maxHealth,mana,maxMana=hero.Health,hero.MaxHealth,hero.Mana,hero.MaxMana
    local ok,problem=pcall(function()
        assert(LocalDuoNativeCreateOriginalActor,"Native factory symbol unavailable")
        local nativeType
        new,nativeType=LocalDuoNativeCreateOriginalActor(old)
        write("originalNativeCreation","J"..player.." old="..old.." new="..tostring(new).." type="..tostring(nativeType))
        assert(new and new~=0 and new~=old,"Original actor creation failed")
        local accepted,reason=LocalDuoNativeBindActor(player,old,new)
        assert(accepted==true,"Engine rejected native binding: "..tostring(reason))
        bound=true
        assert(verified(player,new),"Ownership verification failed before initialization")
        hero.LocalDuoOriginalActor=new
        for from,to in pairs(LocalDuoOriginalVisual.Mapping)do CoopSetAnimationSwap(player,from,to)end
        HookUtils.wrapOnce("GetIdsByType",function()return {new}end)
        hero.ObjectId=nil
        Context.RunWithHeroContextAwait(hero,HeroEx.SetupHeroObject,CurrentRun.CurrentRoom,false)
        assert(hero.ObjectId==new,"Initialization selected a different actor")
        assert(verified(player,new),"Ownership verification failed after initialization")
        Players.PlayerUnitIdToHero[old]=nil;Players.PlayerUnitIdToHero[new]=hero
        hero.Health=health;hero.MaxHealth=maxHealth;hero.Mana=mana;hero.MaxMana=maxMana
        if hero.LocalDuoUsesLegacySwordMechanics==true and LocalDuoOriginalSwordReady then
            Context.RunWithHeroContextAwait(hero,Sword.Equip,hero)
            write("originalSword","J"..player.." sword combo/special/dash equipped; native combat validation pending")
        end
        SetAnimation({DestinationId=new,Name=hero.LocalDuoOriginalSword and "LocalDuoH1_ZagreusSwordUpdateIdleLoop" or LocalDuoOriginalVisual.Idle})
        SetColor({Id=new,Color={255,255,255,255}})
        SetScale({Id=new,Fraction=LocalDuoOriginalVisual.BodyScale or 0.8})
        RemoveOutline({Id=new})
        CreateTextBox({Id=new,Text="J"..player,Font="LatoMedium",FontSize=HeadLabel.FontSize or 24,Width=HeadLabel.Width or 96,VerticalJustification="Bottom",
            Color={255,255,255,255},OffsetY=(LocalDuoOriginalVisual.LabelOffsetY or HeadLabel.OffsetY or -180),Justification="Center"})
        SetUnitProperty({DestinationId=new,Property="AutoLockable",Value=false})
        SetUnitProperty({DestinationId=new,Property="FriendlyToPlayer",Value=true})
        -- Retain the old actor for rollback; it is no longer owned by a player.
        SetUntargetable({Id=old});SetAlpha({Id=old,Fraction=0});DestroyTextBox({Id=old})
        SetThingProperty({DestinationId=old,Property="StopsUnits",Value=false})
        hero.LocalDuoOriginalPrevious=old
        write("originalNativeBinding","J"..player.." old="..old.." new="..new.." ownership verified before/after setup; visual confirmation pending")
    end)
    if not ok then
        local restored=verified(player,old)
        if not restored and new then restored=LocalDuoNativeBindActor(player,new,old) and verified(player,old) end
        if restored then
            hero.ObjectId=old;hero.LocalDuoOriginalActor=nil;hero.Weapons=inventory;hero.LocalDuoOriginalSword=nil
            Players.PlayerUnitIdToHero[old]=hero
            if new then Players.PlayerUnitIdToHero[new]=nil;Destroy({Id=new})end
            for from in pairs(LocalDuoOriginalVisual.Mapping)do CoopRemoveAnimationSwap(player,from)end
            SetTargetable({Id=old});SetAlpha({Id=old,Fraction=1})
        end
        hero.Health=health;hero.MaxHealth=maxHealth;hero.Mana=mana;hero.MaxMana=maxMana
        write("originalNativeBindingError",tostring(problem).." rollback="..tostring(restored).." old="..old.." new="..tostring(new))
    end
    if ok then Events.run:trigger("playerActorRebound",player,old,new,entryScope) end
    end)
end
return Test
