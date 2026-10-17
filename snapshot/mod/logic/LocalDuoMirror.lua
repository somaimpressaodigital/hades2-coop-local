-- Persistent Zagreus-only upgrades, implemented with Hades II combat APIs.
local Mirror={}
Mirror.Entries={
    {Key="Vitality",Name="Vitalidade ctônica",Description="+5 de vida máxima por nível",Max=10,Cost=10},
    {Key="Shadow",Name="Presença sombria",Description="+10% de dano pelas costas por nível",Max=5,Cost=10},
    {Key="Blood",Name="Força da noite",Description="+5% de dano de armas por nível (adaptação coop)",Max=5,Cost=15},
    {Key="Regeneration",Name="Regeneração ctônica",Description="Recupera 1 de vida por nível ao entrar em uma nova sala",Max=3,Cost=20},
    {Key="Purse",Name="Bolso profundo",Description="+20 moedas no começo de cada corrida por nível",Max=5,Cost=15},
}
function Mirror.Levels()
    GameState.LocalDuoZagreusMirror=GameState.LocalDuoZagreusMirror or {}
    return GameState.LocalDuoZagreusMirror
end
function Mirror.Buy(index)
    local entry=Mirror.Entries[index]
    if not entry then return false,"Melhoria inválida" end
    local levels=Mirror.Levels();local level=levels[entry.Key] or 0
    if level>=entry.Max then return false,"Nível máximo" end
    local cost=entry.Cost*(level+1)
    if (GameState.Resources.MetaCurrency or 0)<cost then return false,"Cinzas insuficientes" end
    SpendResource("MetaCurrency",cost,"LocalDuoZagreusMirror",{SkipResourceSpendPresentation=true})
    levels[entry.Key]=level+1
    return true,"Melhoria adquirida"
end
function Mirror.Apply(hero)
    local zag=hero.LocalDuoCharacter=="Zagreus"
    local levels=Mirror.Levels()
    local bonus=zag and (levels.Vitality or 0)*5 or 0
    local delta=bonus-(hero.LocalDuoMirrorHealth or 0)
    if delta~=0 then
        AddMaxHealth(delta,"LocalDuoMirror",{Silent=true,NoHealing=delta<0})
        hero.LocalDuoMirrorHealth=bonus
        hero.Health=math.min(hero.Health,hero.MaxHealth)
    end
    hero.OutgoingDamageModifiers=hero.OutgoingDamageModifiers or {}
    for i=#hero.OutgoingDamageModifiers,1,-1 do
        if hero.OutgoingDamageModifiers[i].Name=="LocalDuoMirror" then table.remove(hero.OutgoingDamageModifiers,i) end
    end
    if zag then
        AddOutgoingDamageModifier(hero,{Name="LocalDuoMirror",
            HitVulnerabilityMultiplier=1+0.1*(levels.Shadow or 0),
            ValidWeaponMultiplier=1+0.05*(levels.Blood or 0)})
        if not CurrentHubRoom and not CurrentRun.LocalDuoMirrorPurseApplied then
            CurrentRun.LocalDuoMirrorPurseApplied=true
            AddResource("Money",20*(levels.Purse or 0),"LocalDuoMirror")
        end
    end
end
function Mirror.EnterRoom(hero,room)
    if hero.LocalDuoCharacter~="Zagreus" or hero.IsDead or CurrentHubRoom then return end
    room.LocalDuoMirrorHealed=room.LocalDuoMirrorHealed or {}
    if room.LocalDuoMirrorHealed[hero.LocalDuoCharacter] then return end
    room.LocalDuoMirrorHealed[hero.LocalDuoCharacter]=true
    local amount=Mirror.Levels().Regeneration or 0
    if amount>0 then Heal(hero,{HealAmount=amount,Silent=true,SourceName="LocalDuoMirror"}) end
end
function Mirror.Render(screen)
    local levels=Mirror.Levels()
    for i,entry in ipairs(Mirror.Entries) do
        local level=levels[entry.Key] or 0
        local selected=screen.MirrorFocus==i
        local shade=selected and {224,205,161,255} or {195,185,209,255}
        ModifyTextBox({Id=screen.Components["Name"..i].Id,Text=entry.Name,Color=shade})
        ModifyTextBox({Id=screen.Components["Level"..i].Id,Text=level.." / "..entry.Max,Color=shade})
        ModifyTextBox({Id=screen.Components["Cost"..i].Id,
            Text=level==entry.Max and "COMPLETO" or (entry.Cost*(level+1)).." Cinzas",Color=shade})
        SetColor({Id=screen.Components["Row"..i].Id,Color=selected and {190,145,235,255} or {90,75,115,255}})
        SetAlpha({Id=screen.Components["Row"..i].Id,Fraction=selected and 1 or 0.65})
    end
    ModifyTextBox({Id=screen.Components.Balance.Id,Text="CINZAS: "..(GameState.Resources.MetaCurrency or 0).."     JOGADOR "..screen.MirrorPlayer})
    ModifyTextBox({Id=screen.Components.Message.Id,Text=screen.Message or "Escolha uma melhoria para Zagreus"})
end
function Mirror.HandleInput(screen,player,input)
    if player~=screen.MirrorPlayer then return end
    local previous=screen.PreviousInput[player] or {}
    if input.Down and not previous.Down then screen.MirrorFocus=screen.MirrorFocus%#Mirror.Entries+1 end
    if input.Up and not previous.Up then screen.MirrorFocus=(screen.MirrorFocus-2)%#Mirror.Entries+1 end
    if input.Confirm and not previous.Confirm then
        local ok,message=Mirror.Buy(screen.MirrorFocus);screen.Message=message
        if ok then screen.Apply();RequestSave({}) end
    end
    if (input.Cancel and not previous.Cancel) or (input.Start and not previous.Start) then
        CloseScreenButton(screen);notifyExistingWaiters("ScreenInput"..screen.Name)
    end
    screen.PreviousInput[player]=input
    Mirror.Render(screen)
end
function Mirror.Open(player,lobby,apply)
    local screen={Name="LocalDuoMirror",Components={},MirrorPlayer=player,MirrorFocus=1,Apply=apply,
        PreviousInput={{},{}},InputInitialized={},DeviceText={},Ready={},IgnoreOtherScreenInput=true,
        SkipQuestStatusCheck=true,FreezePlayerArgs={DisableTray=true}}
    OnScreenOpened(screen);HideCombatUI(screen.Name)
    local group="Combat_Menu_TraitTray"
    local bg=CreateScreenComponent({Name="rectangle01",Group="Combat_Menu_TraitTray_Backing",X=ScreenCenterX,Y=ScreenCenterY,Scale=10})
    screen.Components.Background=bg;SetColor({Id=bg.Id,Color={12,8,20,255}})
    local cx,cy=ScreenCenterX,ScreenCenterY
    local frame=CreateScreenComponent({Name="BlankObstacle",Group="Combat_Menu_TraitTray_Backing",X=cx,Y=cy,Scale=1})
    screen.Components.Frame=frame
    SetAnimation({DestinationId=frame.Id,Name="MythmakerBoxDefault"})
    SetScaleX({Id=frame.Id,Fraction=1.2});SetScaleY({Id=frame.Id,Fraction=1.05})
    SetColor({Id=frame.Id,Color={180,130,215,255}})
    local function text(key,value,x,y,size,width,justify)
        local c=CreateScreenComponent({Name="BlankObstacle",Group=group,X=x,Y=y})
        screen.Components[key]=c
        CreateTextBox({Id=c.Id,Text=value,Font="LatoMedium",FontSize=size,Width=width,
            Color={220,210,230,255},Justification=justify or "Left"})
    end
    text("Title","ESPELHO DA NOITE",cx,cy-330,34,1100,"Center")
    text("Balance","",cx,cy-275,21,900,"Center")
    local icons={"ShrineIcon_EnemyHealth","ShrineIcon_EnemyDamage","ShrineIcon_EnemySpeed","ShrineIcon_HealingReduction","ShrineIcon_ShopPrices"}
    for i,entry in ipairs(Mirror.Entries)do
        local y=cy-190+(i-1)*100
        local row=CreateScreenComponent({Name="ButtonDefault",Group=group,X=cx,Y=y+12,Scale=1})
        screen.Components["Row"..i]=row
        SetScaleX({Id=row.Id,Fraction=4.4});SetScaleY({Id=row.Id,Fraction=1.65})
        UseableOff({Id=row.Id})
        local icon=CreateScreenComponent({Name="BlankObstacle",Group=group,X=cx-480,Y=y+10,Scale=0.7})
        screen.Components["Icon"..i]=icon;SetAnimation({DestinationId=icon.Id,Name=icons[i]})
        text("Name"..i,"",cx-420,y-13,23,650)
        text("Description"..i,entry.Description,cx-420,y+24,17,690)
        text("Level"..i,"",cx+400,y-15,24,150,"Center")
        text("Cost"..i,"",cx+400,y+24,18,180,"Center")
    end
    text("Message","",cx,cy+285,20,1050,"Center")
    text("Help","DIRECIONAL: ESCOLHER     A / X: MELHORAR     B / CIRCULO: VOLTAR",cx,cy+335,17,1250,"Center")
    DisableGamepadCursor(screen.Name);Mirror.Render(screen);lobby.ActiveScreen=screen
    HandleScreenInput(screen)
    if lobby.ActiveScreen==screen then lobby.ActiveScreen=nil end
    ShowCombatUI(screen.Name)
end
return Mirror
