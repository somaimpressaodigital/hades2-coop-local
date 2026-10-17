local HeadLabel=(ModRequire "../config.lua").TextAbovePlayersParams or{}
local Players=ModRequire 'CoopPlayers.lua'
local Context=ModRequire 'HeroContext.lua'
local Native=ModRequire 'HeroContextNative.lua'
local HeroEx=ModRequire 'HeroEx.lua'
local Gate=ModRequire 'LocalDuoRenderProbe.lua'
local Core=ModRequire 'OriginalAvatarPrototype.lua'
local Character=ModRequire 'LocalDuoCharacter.lua'
local Player={}
local function native(player,fun,args)return Native.RunWithNativeHeroContext(player,fun,args)end
function Player.Try(player,hero)
    if not Gate.IsTestProfile() or not LocalDuoOriginalVisual or not hero then return false end
    if Character.Name(player)~='Zagreus' or hero.IsDead then return false end
    local adapter={IsTestProfile=Gate.IsTestProfile}
    adapter.Protect=function(h)
        h.InvulnerableFlags=h.InvulnerableFlags or {};h.InvulnerableFlags.LocalDuoOriginalSwap=true
        SetInvulnerable({Id=h.ObjectId})
    end
    adapter.Release=function(h)
        h.InvulnerableFlags.LocalDuoOriginalSwap=nil
        if next(h.InvulnerableFlags)==nil then SetVulnerable({Id=h.ObjectId})end
    end
    adapter.CreateFor=function(p,name,old)
        return native(p,SpawnUnit,{Name=name,Group='Standing',DestinationId=old})
    end
    adapter.BindFor=function(p,id)return native(p,SwitchActiveUnit,{Id=id})end
    adapter.Initialize=function(p,id,h)
        -- Replace the old 3D animation swaps before any vanilla setup animation.
        for from,to in pairs(LocalDuoOriginalVisual.Mapping)do CoopSetAnimationSwap(p,from,to)end
        -- Do not hold native global player selection around yielding Lua setup.
        Context.RunWithHeroContext(h,HeroEx.SetupAdditional,CurrentRun.CurrentRoom,nil,h,id)
        for from,to in pairs(LocalDuoOriginalVisual.Mapping)do CoopSetAnimationSwap(p,from,to)end
        SetInvulnerable({Id=id})
        SetAnimation({DestinationId=id,Name=LocalDuoOriginalVisual.Idle})
    end
    adapter.Commit=function(p,h,old,id)
        h.ObjectId=id;Players.PlayerUnitIdToHero[id]=h;Players.PlayerUnitIdToHero[old]=nil
        SetUnitProperty({DestinationId=id,Property='FriendlyToPlayer',Value=true})
        SetTargetable({Id=id})
        SetScale({Id=id,Fraction=LocalDuoOriginalVisual.BodyScale or 0.8})
        CreateTextBox({Id=id,Text='J'..p,Font='LatoMedium',FontSize=HeadLabel.FontSize or 24,Width=HeadLabel.Width or 96,VerticalJustification="Bottom",
            Color={255,255,255,255},OffsetY=(LocalDuoOriginalVisual.LabelOffsetY or HeadLabel.OffsetY or -180),Justification='Center'})
    end
    adapter.Rollback=function(p,h,old,id)
        h.ObjectId=old;Players.PlayerUnitIdToHero[old]=h
        if id then Players.PlayerUnitIdToHero[id]=nil end
        for from in pairs(LocalDuoOriginalVisual.Mapping)do CoopRemoveAnimationSwap(p,from)end
        for from,to in pairs(LocalDuoZagreus.Mapping)do CoopSetAnimationSwap(p,from,to)end
    end
    adapter.Park=function(old)
        SetUntargetable({Id=old});SetAlpha({Id=old,Fraction=0})
        DestroyTextBox({Id=old})
        SetThingProperty({DestinationId=old,Property='StopsUnits',Value=false})
    end
    adapter.Show=function(old)SetTargetable({Id=old});SetAlpha({Id=old,Fraction=1})end
    adapter.Destroy=function(id)Destroy({Id=id})end
    adapter.FailProtected=function(p,old,id,message)
        DebugPrint({Text='Original avatar rollback failed: '..tostring(message)})
    end
    local id,problem=Core.Replace(adapter,player,hero,LocalDuoOriginalVisual.PlayerDefinition)
    if id then GameState.LocalDuoOriginalPrototype=true end
    return id,problem
end
function Player.ObserveInput(hero,id)return Core.ObserveInput(hero,id)end
return Player
