-- Native rendering comparison, restricted to the disposable Profile3 copy.
-- Never changes the player actor, controller, weapons, HP, or animation swaps.
local Probe={}
function Probe.IsTestProfile()
    local f=io.open("<USERPROFILE>/Saved Games/Hades II/activeProfile","rb")
    if not f then return false end
    local data=f:read("*a");f:close()
    return data:find("Profile3",1,true)~=nil
end
function Probe.Create(hero)
    if not Probe.IsTestProfile() then return false,"reference probe refused outside Profile3" end
    if not hero or hero.IsDead or not hero.ObjectId or not SessionMapState then
        return false,"living test hero required"
    end
    if SessionMapState.LocalDuoRenderReference then return true,"reference already exists" end
    -- Use the exact vanilla NPC definition and idle animation. In particular,
    -- do not SetThingProperty(GrannyModel/GrannyTexture) on this reference.
    local id=SpawnUnit({Name="NPC_Zagreus_Past_01",Group="Standing",
        DestinationId=hero.ObjectId,OffsetX=180,OffsetY=0})
    if not id or id==0 then return false,"native reference spawn failed" end
    SessionMapState.LocalDuoRenderReference=id
    SetThingProperty({DestinationId=id,Property="StopsUnits",Value=false})
    SetThingProperty({DestinationId=id,Property="StopsProjectiles",Value=false})
    UseableOff({Id=id})
    SetAnimation({DestinationId=id,Name="Zagreus_Idle"})
    CreateTextBox({Id=id,Text="REFERENCIA ORIGINAL",Font="LatoMedium",FontSize=16,
        Color={255,255,255,255},OffsetY=-150,Justification="Center"})
    return true,"native reference id="..id.." player id="..hero.ObjectId
end
return Probe
