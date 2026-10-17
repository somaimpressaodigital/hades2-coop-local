-- Phase-one renderer scene. Original sprites are constructed from birth;
-- the actual coop player is never rebound or replaced by this diagnostic.
local Scene={}
function Scene.Start(hero)
    local data=LocalDuoOriginalVisual
    if not data or not SessionMapState or SessionMapState.LocalDuoOriginalScene then return false end
    if not hero or not hero.ObjectId or hero.IsDead then return false end
    local id=SpawnUnit({Name=data.VisualDefinition,Group='Standing',DestinationId=hero.ObjectId,
        OffsetX=-200,OffsetY=100})
    assert(id and id~=0,'Original sprite actor creation failed')
    SessionMapState.LocalDuoOriginalScene={Id=id,Anchor=hero.ObjectId,Phase=0,Elapsed=0}
    SetUntargetable({Id=id})
    UseableOff({Id=id})
    SetAnimation({DestinationId=id,Name=data.Idle})
    CreateTextBox({Id=id,Text='HADES I ORIGINAL',Font='LatoMedium',FontSize=16,
        Color={255,235,190,255},OffsetY=-150,Justification='Center'})
    -- The game-specific Steam screenshot bridge only queues a local capture;
    -- it does not upload/share or use desktop capture. Verify output separately.
    if type(LocalDuoSteamCapture)=='function' then
        thread(function()
            wait(1)
            if SessionMapState and SessionMapState.LocalDuoOriginalScene
                and SessionMapState.LocalDuoOriginalScene.Id==id then
                pcall(LocalDuoSteamCapture)
            end
        end)
    end
    return true,id
end
function Scene.Update(delta)
    local state=SessionMapState and SessionMapState.LocalDuoOriginalScene
    if not state then return end
    state.Elapsed=state.Elapsed+delta
    if state.Elapsed<3 then return end
    state.Elapsed=0;state.Phase=(state.Phase+1)%4
    if state.Phase==1 then
        SetUnitProperty({DestinationId=state.Id,Property='Speed',Value=300})
        Move({Id=state.Id,DestinationId=state.Anchor,OffsetX=220,OffsetY=100})
    elseif state.Phase==2 then
        Stop({Id=state.Id})
        SetAnimation({DestinationId=state.Id,Name=LocalDuoOriginalVisual.Idle})
    elseif state.Phase==3 then
        -- Animation test only: actual dodge invulnerability/input comes later.
        SetAnimation({DestinationId=state.Id,Name=LocalDuoOriginalVisual.Dash})
    else
        SetUnitProperty({DestinationId=state.Id,Property='Speed',Value=300})
        Move({Id=state.Id,DestinationId=state.Anchor,OffsetX=-220,OffsetY=100})
    end
end
return Scene
