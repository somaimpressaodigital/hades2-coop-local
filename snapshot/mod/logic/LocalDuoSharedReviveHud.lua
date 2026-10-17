-- One shared campaign pool, supplied by Rescue.ReadState; no personal DD inference.
local Hud={}
local key='LocalDuoSharedReviveIcon'
local owned
local function current()
    return owned and CurrentRun==owned.Run and MapState==owned.Map
        and SessionMapState==owned.Session and HUDScreen==owned.Hud
        and HUDScreen.Components==owned.Components
        and owned.Components[key]==owned.Component and owned.Component.Id==owned.Id
end
function Hud.Destroy()
    if not owned then return true end
    if not current()then
        -- Another native HUD/world generation owns its cleanup; never touch stale IDs.
        owned=nil
        return true
    end
    local record=owned
    local ok,result=pcall(Destroy,{Id=record.Id})
    if not ok or result==false then return false end
    if owned==record and current()then record.Components[key]=nil;owned=nil end
    return true
end
local function known(state)
    if type(state)~='table'or state.Known~=true or state.Run~=CurrentRun
        or not CurrentRun or not MapState or not SessionMapState or not HUDScreen
        or type(HUDScreen.Components)~='table'then return false end
    if state.Ending==true then return false end
    return (state.Available==true and state.Remaining==1 and state.Spent==false)
        or(state.Available==false and state.Remaining==0 and state.Spent==true)
end
function Hud.Update(state)
    if owned and not current()then owned=nil end
    if not known(state)then return Hud.Destroy()end
    local hidden=SessionMapState.IsPaused==true or AreScreensActive()
        or next(MapState.CombatUIHide or {})~=nil
    if not owned then
        -- Do not adopt or overwrite a component from any other producer/generation.
        if hidden or HUDScreen.Components[key]~=nil then return false end
        local width,height=ScreenWidth,ScreenHeight
        if type(width)~='number'or type(height)~='number'then return false end
        local component=CreateScreenComponent({Name='BlankObstacle',Group='HUD_Main',
            X=width/2,Y=height-92,Scale=0.8})
        if type(component)~='table'or type(component.Id)~='number'or component.Id<=0
            or component.Id>=math.huge or component.Id%1~=0 then return false end
        HUDScreen.Components[key]=component
        owned={Component=component,Id=component.Id,Run=CurrentRun,Map=MapState,
            Session=SessionMapState,Hud=HUDScreen,Components=HUDScreen.Components}
    end
    local animation=state.Available and 'ExtraLifeMel'or 'ExtraLifeEmpty'
    if owned.Animation~=animation then
        SetAnimation({DestinationId=owned.Id,Name=animation});owned.Animation=animation
    end
    local opacity=ConfigOptionCache and ConfigOptionCache.HUDOpacity or 1
    if type(opacity)~='number'or opacity~=opacity then opacity=1 end
    opacity=math.max(0,math.min(1,opacity))
    local alpha=hidden and 0 or opacity
    if owned.Alpha~=alpha then SetAlpha({Id=owned.Id,Fraction=alpha,Duration=0});owned.Alpha=alpha end
    return true
end
return Hud
