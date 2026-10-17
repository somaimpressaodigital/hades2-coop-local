-- Cosmetic color only; use the currently registered J2 actor, never CurrentRun.Hero.
local M={}
local crimsonPackageLoaded=false
-- Identification outline is independent of the actor's tint/texture.
function M.ApplyOutline(hero)
    if not hero or hero.IsDead or not hero.ObjectId or hero.LocalDuoCharacter~="Melinoe"
        or hero.PolymorphType~=nil or hero.PolymorphModelOverride~=nil
        or (MapState and (MapState.HostilePolymorph or MapState.BabyPolymorph)) then return false end
    local players=ModRequire "CoopPlayers.lua"
    local first=players.GetHero(1)
    if players.GetPlayersCount()~=2 or players.GetHero(2)~=hero
        or players.GetPlayerByHero(hero)~=2 or not first or first==hero
        or first.ObjectId==hero.ObjectId then return false end
    -- Let native Darkside temporarily own its outline; existing Undarkside hook
    -- restores the configured purple marker after native RemoveOutline.
    local darkside=SessionMapState and SessionMapState.DarkSide
    if type(darkside)=="table" and next(darkside)~=nil then return false end
    AddOutline({Id=hero.ObjectId,R=180,G=70,B=240,Opacity=0.6,Thickness=2,Threshold=0.6})
    return true
end
function M.Apply(hero)
    M.ApplyOutline(hero)
    if not hero or hero.IsDead or not hero.ObjectId or hero.LocalDuoCharacter~="Melinoe" then return false end
    -- Lazy require avoids the existing HeroEx -> CoopPlayers load cycle.
    local players=ModRequire "CoopPlayers.lua"
    local first=players.GetHero(1)
    if players.GetPlayersCount()~=2 or players.GetHero(2)~=hero
        or players.GetPlayerByHero(hero)~=2 or not first or first==hero
        or first.ObjectId==hero.ObjectId then return false end
    -- Presentation-only: native per-actor texture override, never a shared replacement.
    -- Native temporary forms retain their own texture and color until costume restoration.
    local darkside=SessionMapState and SessionMapState.DarkSide
    if hero.PolymorphType~=nil or hero.PolymorphModelOverride~=nil
        or (MapState and (MapState.HostilePolymorph or MapState.BabyPolymorph))
        or (type(darkside)=="table" and next(darkside)~=nil) then return false end
    if false and LocalDuoCoopModeActive==true then -- Disabled after native magenta texture failure.
        if not crimsonPackageLoaded then
            local ok,result=pcall(LoadPackages,{Name="LocalDuoCrimsonRecolor"})
            crimsonPackageLoaded=ok and result~=false
        end
        if crimsonPackageLoaded then
            SetThingProperty({DestinationId=hero.ObjectId,Property="GrannyTexture",
                Value="GR2/LocalDuoCrimsonMelinoe_Color512"})
            -- Original texture colors; identification remains the separate purple outline.
            SetColor({Id=hero.ObjectId,Color={255,255,255,255}})
            return true
        end
    end
    local tint=(ModRequire "../config.lua").LocalDuo.Player2Tint
    if type(tint)~="table" then return false end
    local color={}
    for i=1,4 do
        local value=tint[i]
        if type(value)~="number" or value~=value or value<0 or value>255 then return false end
        color[i]=value
    end
    SetColor({Id=hero.ObjectId,Color=color})
    return true
end
return M
