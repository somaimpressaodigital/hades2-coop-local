-- H2 cards and progression; only equipped loadouts are personal.
local Players=ModRequire "CoopPlayers.lua"
local Context=ModRequire "HeroContext.lua"
local Control=ModRequire "CoopControl.lua"
local PersonalRerolls=ModRequire "LocalDuoPersonalRerolls.lua"
local A={}
local Group="Combat_Menu_TraitTray"
local editing=false
local function capture()
    local out={Equipped={},Adjacency={}}
    for name,data in pairs(GameState.MetaUpgradeState)do
        out.Equipped[name]=data.Equipped==true
        out.Adjacency[name]=DeepCopyTable(data.AdjacencyBonuses or {})
    end
    out.Layouts=DeepCopyTable(GameState.SavedMetaUpgradeLayouts or {})
    out.Layout=GameState.CurrentMetaUpgradeLayout
    return out
end
function A.Ensure()
    InitializeMetaUpgradeState()
    GameState.LocalDuoArcanaLayouts=GameState.LocalDuoArcanaLayouts or {}
    for p=1,2 do
        if not GameState.LocalDuoArcanaLayouts[p]then GameState.LocalDuoArcanaLayouts[p]=capture()end
    end
end
-- Never hold this projection across a wait/UI coroutine. Shared level/unlock/resource
-- progression is deliberately not copied into personal loadouts.
function A.Edit(player,fn)
    assert(player==1 or player==2,"Unknown Arcana owner")
    assert(not editing,"Nested Arcana edit is not supported")
    A.Ensure()
    local shared=GameState.MetaUpgradeState
    local layout=GameState.SavedMetaUpgradeLayouts
    local selected=GameState.CurrentMetaUpgradeLayout
    local personal=GameState.LocalDuoArcanaLayouts[player]
    GameState.MetaUpgradeState=DeepCopyTable(shared)
    for name,data in pairs(GameState.MetaUpgradeState)do
        data.Equipped=personal.Equipped[name]or nil
        data.AdjacencyBonuses=DeepCopyTable(personal.Adjacency and personal.Adjacency[name]or {})
    end
    GameState.SavedMetaUpgradeLayouts=DeepCopyTable(personal.Layouts or {})
    GameState.CurrentMetaUpgradeLayout=personal.Layout
    editing=true
    local result=table.pack(pcall(fn))
    local after=capture()
    if result[1]then
        for name,data in pairs(GameState.MetaUpgradeState)do
            -- Actual H2 account progression, not a second purchase per player.
            shared[name].Unlocked=data.Unlocked
            shared[name].Level=data.Level
        end
        GameState.LocalDuoArcanaLayouts[player]=after
        if player==1 then
            for name,data in pairs(shared)do
                data.Equipped=after.Equipped[name]or nil
                data.AdjacencyBonuses=after.Adjacency[name]
            end
        end
    end
    GameState.MetaUpgradeState=shared
    GameState.SavedMetaUpgradeLayouts=layout
    GameState.CurrentMetaUpgradeLayout=selected
    -- Account comprehension may have advanced; rebuild caches for the base J1
    -- loadout rather than restoring stale values from before the real purchase.
    GetCurrentMetaUpgradeCost();GetMaxMetaUpgradeCost()
    editing=false
    if not result[1]then error(result[2],0)end
    return table.unpack(result,2,result.n)
end
local function recompute()
    CheckAutoEquipCards(nil);CheckAutoEquipCards(nil)
    UpdateMetaUpgradeCardAdjacencyBonuses()
end
local function pay(cost,source)
    if not cost or not HasResources(cost)then return false end
    -- Stock resource API, real shared wallet. No yield or screen-global callbacks.
    for name,amount in pairs(cost)do
        if amount>0 then assert(SpendResource(name,amount,source,
            {SkipQuestStatusCheck=true,SkipResourceSpendPresentation=true})~=false,"Arcana payment failed")end
    end
    return true
end
local function visible(row,column,name)
    return GameState.MetaUpgradeState[name].Unlocked or(row==1 and column==1)or HasNeighboringUnlockedCards(row,column)
end
function A.Mutate(player,card,action)
    return A.Edit(player,function()
        local data=MetaUpgradeCardData[card.Name]
        local state=GameState.MetaUpgradeState[card.Name]
        if not data or not state or not visible(card.Row,card.Column,card.Name)then return false,"Carta oculta"end
        if action=="Upgrade"then
            if not state.Unlocked or not CanUpgradeCards()then return false,"Evolução bloqueada"end
            local cost=CanUpgradeMetaUpgrade(card.Name)
            if not cost or not pay(cost,card.Name)then return false,"Recursos insuficientes / nível máximo"end
            RemoveStoreItemPin(card.Name..GetMetaUpgradeLevel(card.Name),{Purchase=true})
            state.Level=GetMetaUpgradeLevel(card.Name)+1
            GameState.Flags.HasUpgradedCards=true
        elseif not state.Unlocked then
            if not pay(data.ResourceCost,card.Name)then return false,"Recursos insuficientes"end
            state.Unlocked=true
            RemoveStoreItemPin(card.Name,{Purchase=true})
            if not data.AutoEquipRequirements and GetCurrentMetaUpgradeCost()+(data.Cost or 0)<=GetMaxMetaUpgradeCost()then state.Equipped=true end
        elseif data.AutoEquipRequirements then
            return false,"Despertar automático: requisitos da carta"
        elseif state.Equipped then state.Equipped=nil
        elseif GetCurrentMetaUpgradeCost()+(data.Cost or 0)>GetMaxMetaUpgradeCost()then return false,"Limite de compreensão"
        else state.Equipped=true end
        recompute();UpdateMetaUpgradeUnlockedCountCache()
        return true
    end)
end
function A.IncreaseLimit(player)
    return A.Edit(player,function()
        local nextData=MetaUpgradeCostData.MetaUpgradeLevelData[GetCurrentMetaUpgradeLimitLevel()+1]
        if not nextData or not pay(nextData.ResourceCost,"IncreaseCardLimit")then return false,"Recursos insuficientes / limite máximo"end
        RemoveStoreItemPin("MetaUpgradeLevelData"..(GetCurrentMetaUpgradeLimitLevel()+1),{Purchase=true})
        IncrementTableValue(GameState,"MetaUpgradeLimitLevel",1)
        return true
    end)
end
local function text(screen,key,value,x,y,size,color,width,top,font)
    local c=CreateScreenComponent({Name="BlankObstacle",Group=Group,X=x,Y=y})
    screen.Components[key]=c
    CreateTextBox({Id=c.Id,Text=value,Font=font or "LatoMedium",FontSize=size or 22,Color=color or Color.White,
        Justification="Center",VerticalJustification=top and "Top" or "Center",Width=width or 720,
        TextSymbolScale=0.7,LineSpacingBottom=3})
    return c
end
local function button(screen,key,label,x,y,player,index,card)
    -- The stock card is its own art destination. Do not put card art on a tiny
    -- BlankObstacle above a horizontal ButtonDefault.
    local c=CreateScreenComponent({Name=card and "ButtonMetaUpgradeCard" or "ButtonDefault",
        Group=Group,X=x,Y=y,Scale=card and 1 or 0.78})
    screen.Components[key]=c;c.LocalDuoPlayer=player;c.ArcanaIndex=index
    c.OnPressedFunctionName="LocalDuoArcanaClick"
    if not card then
        CreateTextBox({Id=c.Id,Text=label,Font="LatoMedium",FontSize=20,Width=238,
            Color=Color.White,Justification="Center",VerticalJustification="Center"})
    end
    return c
end
local function createFocusBorder(screen,player)
    -- Native rectangle01 has a 480x270 source canvas in both Fx package
    -- resolutions. Scale native geometry into four solid screen-unit strips.
    local width,height,thickness=88,128,7.5
    local sides={
        {"Top",0,-height/2,width+thickness,thickness},
        {"Bottom",0,height/2,width+thickness,thickness},
        {"Left",-width/2,0,thickness,height+thickness},
        {"Right",width/2,0,thickness,height+thickness},
    }
    for _,side in ipairs(sides)do
        local c=CreateScreenComponent({Name="rectangle01",Group="Combat_Menu_TraitTray_Overlay",X=0,Y=0})
        c.FocusOffsetX=side[2];c.FocusOffsetY=side[3]
        screen.Components["Focus"..player..side[1]]=c
        SetScaleX({Id=c.Id,Fraction=side[4]/480})
        SetScaleY({Id=c.Id,Fraction=side[5]/270})
        SetColor({Id=c.Id,Color={255,55,185,255}})
        SetAlpha({Id=c.Id,Fraction=0})
    end
end
local function renderFocusBorder(screen,player,opacity)
    local index=screen.Focus[player]
    local card=index and index<=#screen.Cards and screen.Components["Card"..player.."_"..index]
    for _,side in ipairs({"Top","Bottom","Left","Right"})do
        local c=screen.Components["Focus"..player..side]
        if card then Teleport({Id=c.Id,DestinationId=card.Id,OffsetX=c.FocusOffsetX,OffsetY=c.FocusOffsetY})end
        SetAlpha({Id=c.Id,Fraction=card and opacity or 0})
    end
end
local function valid(screen)
    return not screen.Closing and CurrentRun==screen.Run and CurrentRun.CurrentRoom==screen.Room and MapState==screen.Map
        and CurrentHubRoom==screen.HubRoom
        and Players.GetHero(1)==screen.Heroes[1]and Players.GetHero(2)==screen.Heroes[2]
        and not screen.Heroes[1].IsDead and not screen.Heroes[2].IsDead
        and screen.Heroes[1].ObjectId==screen.Actors[1]and screen.Heroes[2].ObjectId==screen.Actors[2]
end
local function costText(cost)
    local parts={}
    for name,n in pairs(cost or {})do
        local data=ResourceData and ResourceData[name]
        local label=GetDisplayName({Text=data and (data.CostTextId or data.TooltipId) or name})
        parts[#parts+1]=tostring(n).." "..label
    end
    table.sort(parts)
    return table.concat(parts," / ")
end
function A.Render(screen)
    for p=1,2 do Context.RunWithHeroContextAwait(screen.Heroes[p],function() A.Edit(p,function()
        recompute()
        local panelOpacity=screen.Ready[p] and 0.35 or 1
        for _,key in ipairs({"Frame","Heading","Status","Preview","Detail","CardState",
            "Description","Cost","Price","Shortcuts","Ready","Device"})do
            SetAlpha({Id=screen.Components[key..p].Id,Fraction=panelOpacity})
        end
        local accent=p==1 and {130,190,255,255} or {210,155,255,255}
        local used,maximum=GetCurrentMetaUpgradeCost(),GetMaxMetaUpgradeCost()
        ModifyTextBox({Id=screen.Components["Status"..p].Id,
            Text="Compreensão  "..used.." / "..maximum..(screen.Ready[p] and "   ·   PRONTO" or ""),
            Color=screen.Ready[p] and {150,240,190,255} or accent})
        for i,card in ipairs(screen.Cards)do
            local state=GameState.MetaUpgradeState[card.Name]
            local shown=visible(card.Row,card.Column,card.Name)
            local d=MetaUpgradeCardData[card.Name]
            local b=screen.Components["Card"..p.."_"..i]
            -- Use the same CardArt/Inactive/DevBacking path and explicit animation
            -- scale as stock UpdateMetaUpgradeCard, adapted to the five-row grid.
            local art=shown and (d.Image..(state.Equipped and "" or "_Inactive")) or "DevBacking"
            SetAnimation({DestinationId=b.Id,Name=art,Scale=screen.GridArtScale})
            SetHSV({Id=b.Id,HSV=shown and not state.Unlocked and {0,-1,-0.1} or {0,0,0},ValueChangeType="Absolute"})
            SetAlpha({Id=b.Id,Fraction=(shown and 1 or 0.3)*panelOpacity})
            SetColor({Id=b.Id,Color={255,255,255,255}})
            SetAlpha({Id=screen.Components["Equipped"..p.."_"..i].Id,
                Fraction=(shown and state.Equipped and 1 or 0)*panelOpacity})
            SetAlpha({Id=screen.Components["Number"..p.."_"..i].Id,Fraction=panelOpacity})
            ModifyTextBox({Id=screen.Components["Number"..p.."_"..i].Id,
                Text=not shown and "?" or (not state.Unlocked and "BLOQ." or (state.Equipped and "ATIVA" or tostring(d.Cost or 0))),
                Color=not state.Unlocked and {185,185,198,255} or (state.Equipped and {155,240,190,255} or {230,226,215,255})})
        end
        renderFocusBorder(screen,p,panelOpacity)
        SetColor({Id=screen.Components["Ready"..p].Id,
            Color=screen.Focus[p]==#screen.Cards+1 and {255,75,190,255} or
                (screen.Ready[p] and {150,240,190,255} or {225,220,210,255})})
        ModifyTextBox({Id=screen.Components["Ready"..p].Id,Text=screen.Ready[p] and "Pronto" or "Confirmar"})
        local card=screen.Cards[screen.SelectedCard[p]]
        if card then
            local d=MetaUpgradeCardData[card.Name];local s=GameState.MetaUpgradeState[card.Name]
            local shown=visible(card.Row,card.Column,card.Name)
            local title=card.Name
            if d.CustomTextWithShrineUpgrade and GetNumShrineUpgrades(d.CustomTextWithShrineUpgrade.ShrineUpgradeName)>0 then title=d.CustomTextWithShrineUpgrade.CardTitle end
            ModifyTextBox({Id=screen.Components["Detail"..p].Id,Text=shown and card.Name or "MetaUpgrade_Locked",
                Width=208,FontSize=20,AutoSetDataProperties=false})
            SetAnimation({DestinationId=screen.Components["Preview"..p].Id,
                Name=shown and d.Image or "DevBacking",Scale=screen.PreviewArtScale})
            SetHSV({Id=screen.Components["Preview"..p].Id,
                HSV=shown and not s.Unlocked and {0,-1,-0.1} or {0,0,0},ValueChangeType="Absolute"})
            local state=not shown and "OCULTA" or (not s.Unlocked and "BLOQUEADA" or
                (s.Equipped and "ATIVA" or (d.AutoEquipRequirements and "DESPERTAR AUTOMÁTICO" or "DISPONÍVEL")))
            ModifyTextBox({Id=screen.Components["CardState"..p].Id,Text=state,
                Color=s.Equipped and {150,240,190,255} or accent})
            local trait={}
            if shown and d.TraitName then
                trait=GetProcessedTraitData({Unit=screen.Heroes[p],TraitName=d.TraitName,
                    Rarity=TraitRarityData.RarityUpgradeOrder[GetMetaUpgradeLevel(card.Name)],
                    CustomMultiplier=1+(s.AdjacencyBonuses and s.AdjacencyBonuses.CustomMultiplier or 0)})
                SetTraitTextData(trait)
            end
            ModifyTextBox({Id=screen.Components["Description"..p].Id,Text=shown and title or "MetaUpgrade_Hidden",
                UseDescription=true,LuaKey="TooltipData",LuaValue=trait,Width=208,FontSize=18,AutoSetDataProperties=false})
            local cost=not s.Unlocked and d.ResourceCost or (CanUpgradeCards() and CanUpgradeMetaUpgrade(card.Name) or nil)
            local price=costText(cost)
            SetAlpha({Id=screen.Components["Cost"..p].Id,Fraction=shown and panelOpacity or 0})
            SetAlpha({Id=screen.Components["Price"..p].Id,Fraction=shown and price~="" and panelOpacity or 0})
            ModifyTextBox({Id=screen.Components["Cost"..p].Id,
                Text=shown and ("Nível "..GetMetaUpgradeLevel(card.Name).."\nCompreensão "..(d.Cost or 0)) or " "})
            ModifyTextBox({Id=screen.Components["Price"..p].Id,
                Text=shown and price~="" and ((s.Unlocked and "Evoluir:\n" or "Desbloquear:\n")..price) or " "})
        end
        -- This acknowledgement stays readable over the dimmed owner panel.
        SetAlpha({Id=screen.Components["Message"..p].Id,Fraction=1})
        ModifyTextBox({Id=screen.Components["Message"..p].Id,
            Text=screen.Ready[p] and "Aguardando outro jogador" or (screen.Messages[p] or ""),
            FontSize=screen.Ready[p] and 26 or 20,
            Color=screen.Ready[p] and {235,229,210,255} or {255,185,140,255}})
    end)end)end
end
local function apply(screen,p)
    assert(valid(screen),"Arcana owner/room changed before application")
    local hero=screen.Heroes[p]
    Context.RunWithHeroContextAwait(hero,function()
        A.Edit(p,function()
            recompute()
            -- Refresh only changed Arcana traits; avoid replenishing unchanged DDs.
            for name,d in pairs(MetaUpgradeCardData)do
                local before=screen.Applied[p][name]or{}
                local after=GameState.MetaUpgradeState[name]
                local oldBonus=before.AdjacencyBonuses and before.AdjacencyBonuses.CustomMultiplier
                local newBonus=after.AdjacencyBonuses and after.AdjacencyBonuses.CustomMultiplier
                if d.TraitName and HeroHasTrait(d.TraitName)and
                    (not after.Equipped or before.Level~=after.Level or oldBonus~=newBonus)then
                    RemoveWeaponTrait(d.TraitName,{Silent=true})
                end
            end
            -- Stock EquipPreRunMetaUpgrades body, excluding its RUN-global
            -- NumRerolls reset. Keep the existing real shared wallet, including
            -- spent/acquired uses. Personal reroll quantity is NOT implemented
            -- by this UI; it requires all stock acquisition/spend/reset paths.
            EquipMetaUpgrades(hero,{SkipTraitHighlight=true})
            ValidateMaxHealth()
            ValidateMaxMana()
            HandleWeaponAnimSwaps()
            PersonalRerolls.SetNativeBudget(CurrentRun,hero,GetTotalHeroTraitValue("RerollCount"))
        end)
    end)
    assert(valid(screen),"Arcana owner/room changed during application")
end
function A.Act(screen,p,index)
    if not valid(screen)or screen.Ready[p]then return end
    screen.Focus[p]=index
    local count=#screen.Cards
    local ok,why
    if index<=count then ok,why=A.Mutate(p,screen.Cards[index],"Equip")
    else
        screen.Ready[p]=true;ok=true
        if screen.Ready[1]and screen.Ready[2]then
            -- Apply after both finish: a shared level purchase made by the second
            -- player also refreshes the first player's equipped copy exactly once.
            apply(screen,1);apply(screen,2)
            RequestPreRunLoadoutChangeSave()
            CloseScreenButton(screen);notifyExistingWaiters("ScreenInput"..screen.Name)
            return
        end
    end
    if index<=count then screen.SelectedCard[p]=index end
    screen.Messages[p]=ok and ""or why
    A.Render(screen)
end
function A.HandleInput(screen,p,input)
    if(p~=1 and p~=2)or not valid(screen)or not screen.ArcanaInputSnapshots
        or screen.ArcanaInputSnapshots[p]~=input or input.Connected~=true or input.Focused~=true
        or not ActiveScreens or ActiveScreens[screen.Name]~=screen then return end
    local bindings=screen.ArcanaInputBindings;local current=Control.Schemas.Current;local schema=current and current[p]
    if not bindings or not bindings[p]or not schema or bindings.Current~=current or bindings[p].Schema~=schema
        or bindings[p].Device~=schema.Device or bindings[p].ControllerId~=schema.ControllerId
        or bindings[p].Instance~=input.Instance
        or(schema.Device=="Gamepad"and input.Index~=schema.ControllerId)
        or(schema.Device=="Keyboard"and p~=1)then return end
    local prev=screen.PreviousInput[p]or{}
    local move=(input.Right and not prev.Right and 1)or(input.Left and not prev.Left and -1)
        or(input.Down and not prev.Down and 5)or(input.Up and not prev.Up and -5)
        or(input.Next and not prev.Next and 1)or(input.Previous and not prev.Previous and -1)
    if input.Cancel then
        if not prev.Cancel then
            local wasReady=screen.Ready[p];screen.Ready[p]=false
            if wasReady then A.Render(screen)end
        end
        -- Cancel wins over every action, including held purchase shortcuts.
        screen.PreviousInput[p]=input
        return
    end
    if move and not screen.Ready[p]then
        screen.Focus[p]=math.max(1,math.min(#screen.Cards+1,screen.Focus[p]+move))
        if screen.Focus[p]<=#screen.Cards then screen.SelectedCard[p]=screen.Focus[p]end
        A.Render(screen)
    end
    if not screen.Ready[p] then
        local upgrade=input.Upgrade and not prev.Upgrade
        local limit=input.Limit and not prev.Limit
        if upgrade and limit then
            screen.Messages[p]="Use um atalho de cada vez";A.Render(screen)
        elseif upgrade or limit then
            local ok,why
            if upgrade then ok,why=A.Mutate(p,screen.Cards[screen.SelectedCard[p]],"Upgrade")
            else ok,why=A.IncreaseLimit(p)end
            screen.Messages[p]=ok and (upgrade and "Carta evoluída" or "Compreensão aumentada") or why
            A.Render(screen)
        elseif input.Confirm and not prev.Confirm then A.Act(screen,p,screen.Focus[p])end
    end
    screen.PreviousInput[p]=input
end
function LocalDuoArcanaClick(screen,b)
    -- Stock button activation carries no device identity (pad/keyboard/mouse share it).
    -- It must not apply a second action or route J2 through the left cursor.
    -- Keyboard and both pads use the validated independent readers above.
    return false
end
function A.IsAvailable()
    local room=CurrentHubRoom
    return LocalDuoCoopModeActive==true and room~=nil and
        (room.Name=="Hub_PreRun"or room.Name=="Hub_Main")
end
function A.Open(lobby,args)
    if IsScreenOpen("LocalDuoArcanaCoop")then return end
    if not A.IsAvailable()then return false,"Arcanos disponíveis no altar do hub"end
    A.Ensure();LoadPackages({Name="GUI"});LoadPackages({Name="BiomeHub"})
    local screen={Name="LocalDuoArcanaCoop",ArcanaCoop=true,Components={},Cards={},Focus={1,1},SelectedCard={1,1},
        Ready={false,false},Messages={},PreviousInput={{},{}},InputInitialized={},DeviceText={},Run=CurrentRun,
        Room=CurrentRun.CurrentRoom,HubRoom=CurrentHubRoom,Map=MapState,Heroes={Players.GetHero(1),Players.GetHero(2)},Actors={},Applied={},
        BlockPause=true,IgnoreOtherScreenInput=true,SkipQuestStatusCheck=true,FreezePlayerArgs={DisableTray=true}}
    for p=1,2 do assert(screen.Heroes[p]and not screen.Heroes[p].IsDead,"Both Arcana owners required");screen.Actors[p]=screen.Heroes[p].ObjectId end
    for p=1,2 do A.Edit(p,function()recompute();screen.Applied[p]=DeepCopyTable(GameState.MetaUpgradeState)end)end
    for row,data in ipairs(GameState.MetaUpgradeCardLayout)do for col,name in ipairs(data)do screen.Cards[#screen.Cards+1]={Row=row,Column=col,Name=name}end end
    HideCombatUI(screen.Name);OnScreenOpened(screen)
    local cx,cy=ScreenCenterX,ScreenCenterY
    screen.GridArtScale=(ScreenData.MetaUpgradeCardLayout.DefaultArtScale or 0.2775)*0.74
    screen.PreviewArtScale=0.34
    local bg=CreateScreenComponent({Name="rectangle01",Group=Group,X=cx,Y=cy,Scale=10});screen.Components.Background=bg
    SetColor({Id=bg.Id,Color={8,11,19,255}})
    text(screen,"Title","ARCANOS",cx,cy-477,36,{230,211,167,255},720,false,"P22UndergroundSCMedium")
    text(screen,"Help","Cartas equipadas individuais · Desbloqueios, níveis e recursos compartilhados",cx,cy+483,19,{190,194,206,255},1760)
    for p=1,2 do
        local x=cx+(p==1 and -470 or 470)
        local accent=p==1 and {130,190,255,255} or {210,155,255,255}
        local frame=CreateScreenComponent({Name="BlankObstacle",Group=Group,X=x,Y=cy+8,Scale=1});screen.Components["Frame"..p]=frame
        SetAnimation({DestinationId=frame.Id,Name="MythmakerBoxDefault"})
        SetScaleX({Id=frame.Id,Fraction=0.9});SetScaleY({Id=frame.Id,Fraction=1.34})
        text(screen,"Heading"..p,"MELÍNOE · JOGADOR "..p,x,cy-397,27,accent,780)
        text(screen,"Status"..p,"",x,cy-370,23,nil,780)
        -- Grid and selected-card detail occupy separate columns in each panel.
        local detailX=x+224
        for i,card in ipairs(screen.Cards)do
            local px=x-345+(card.Column-1)*100;local py=cy-270+(card.Row-1)*126
            local b=button(screen,"Card"..p.."_"..i,"",px,py,p,i,true)
            b.CardArtId=b.Id
            local glow=CreateScreenComponent({Name="Card_EquippedHighlight",Group=Group,X=px,Y=py,Scale=0.74})
            screen.Components["Equipped"..p.."_"..i]=glow
            text(screen,"Number"..p.."_"..i,"",px,py+44,14,nil,96)
        end
        createFocusBorder(screen,p)
        local preview=CreateScreenComponent({Name="BlankObstacle",Group=Group,X=detailX,Y=cy-233,Scale=1})
        screen.Components["Preview"..p]=preview
        -- Two title lines; narrower lower text stays inside the curved frame.
        text(screen,"Detail"..p,"",detailX,cy-90,20,nil,208,true)
        text(screen,"CardState"..p,"",detailX,cy-25,18,accent,208)
        text(screen,"Description"..p,"",detailX,cy+12,18,nil,208,true)
        text(screen,"Cost"..p,"",x+205,cy+190,17,{225,209,175,255},180,true)
        text(screen,"Price"..p,"",x+205,cy+246,17,{225,209,175,255},180,true)
        text(screen,"Message"..p,"",x,cy+337,20,{255,185,140,255},780)
        local keyboard=Control.Schemas.Current[p].Device=="Keyboard"
        text(screen,"Shortcuts"..p,keyboard and "F1 · Evoluir carta    F2 · Compreensão +" or "R1 · Evoluir carta    L1 · Compreensão +",x,cy+359,18,{225,209,175,255},780)
        button(screen,"Ready"..p,"Confirmar",x,cy+407,p,#screen.Cards+1)
        text(screen,"Device"..p,"",x,cy+443,18,{185,190,205,255},780)
    end
    local previous=lobby.ActiveScreen
    local result=table.pack(pcall(function()
        DisableGamepadCursor(screen.Name)
        lobby.StartPlayerInputListeners(screen);A.Render(screen);HandleScreenInput(screen)
    end))
    if lobby.ActiveScreen==screen then lobby.ActiveScreen=previous end
    if not screen.Closing then CloseScreenButton(screen)end
    ShowCombatUI(screen.Name)
    if not result[1]then error(result[2],0)end
end
return A
