-- Native Hades UI components; fixed 1920x1080 logical canvas like the lobby.
local View={};View.__index=View
local palette={{100,160,255,255},{205,135,255,255}}
local gold={224,205,161,255};local white={235,235,242,255}
local rarity={Rare='BoonSlotRare',Epic='BoonSlotEpic',Heroic='BoonSlotHeroic',Legendary='BoonSlotLegendary',Duo='BoonSlotDuo'}
function View.WithTemplates(layout,templates)
 return {New=function(api,model,args)
  args=args or {};args.layout=layout;args.templates=templates;return View.New(api,model,args)
 end}
end
function View.New(api,model,args)
 args=args or {};assert(args.layout and args.templates,'Use WithTemplates(layout,templates)')
 local self=setmetatable({Api=api,Model=model,Components={},Rows={},PlayerInterfaces={},Args=args,Closed=false,
  Pages={},Stats={},Replacements={},Page={1,1},Focused={},ActiveDetails={},PanelComponents={},
  FeedbackDone={model.Panels[1].Status=='committed',model.Panels[2].Status=='committed'},
  FeedbackWorld={Run=api.CurrentRun,Room=api.CurrentRun and api.CurrentRun.CurrentRoom,Map=api.MapState,Session=api.SessionMapState}},View)
 if args and args.onAllocated then args.onAllocated(self)end
 local function build()
 local cx,cy=api.ScreenCenterX,api.ScreenCenterY
 local function title(value)
  return api.GetDisplayName and api.GetDisplayName({Text=value})or args.templates[value] and args.templates[value].DisplayName or value
 end
 local function blockedReason(offer)
  local curse=offer.Raw and offer.Raw.Type=='TransformingTrait'and offer.Data and offer.Data.Name
  if curse=='ChaosCommonCurse'then return 'Esta maldição ainda não tem duração pessoal.'end
  if curse=='ChaosRestrictBoonCurse'then return 'Esta maldição ainda não tem duração pessoal.'end
  return curse and 'Esta combinação ainda não está adaptada ao coop.'
   or 'Esta melhoria ainda não é compatível com o coop.'
 end
 local function replacementInfo(offer,panel,player)
  local raw=offer.Raw
  if type(raw)~='table'or type(raw.TraitToReplace)~='string'or raw.TraitToReplace==''
   or (offer.Owner~=nil and offer.Owner~=player)then return nil end
  -- Native personal offer metadata is authoritative. Never infer a replacement from slot/build.
  local old=raw.TraitToReplace;local definition=api.TraitData and api.TraitData[old]
  local owned
  for _,trait in ipairs(panel.Hero and panel.Hero.Traits or{})do
   if trait.Name==old and(not raw.OldRarity or trait.Rarity==raw.OldRarity)then owned=trait;break end
  end
  local oldData=owned or definition
  local oldKey=old
  if oldData and api.GetTraitTooltipTitle then oldKey=api.GetTraitTooltipTitle(oldData)or old end
  return {OldName=title(oldKey),NewName=title(offer.Title),OldRarity=raw.OldRarity,
   OldIcon=oldData and oldData.Icon,OldTrait=old,NewTrait=offer.ItemName}
 end
 local buildingPlayer
 local function component(key,name,x,y,scale,group)
  local c=api.CreateScreenComponent({Name=name,Group=group or 'Combat_Menu',X=x,Y=y,Scale=scale or 1})
  self.Components[key]=c;if buildingPlayer then self.PanelComponents[buildingPlayer][key]=c end;return c
 end
 local function text(key,value,x,y,size,color,width,left,tooltip,description)
  local c=component(key,'BlankObstacle',x,y,1,'Combat_Menu_Overlay')
  api.CreateTextBox({Id=c.Id,Text=value,Font=(key:match('^Details%d')or key:match('^DetailsOneStat')or key:match('^DetailsTwoStats')or key:match('^StatLabel')or key:match('^StatValue')or key:match('^Status')or key:match('^Page')or key=='Help')and 'LatoMedium'or(size>=25 and 'P22UndergroundSCMedium'or 'LatoMedium'),
   FontSize=size,Color=color or white,Width=width or 700,Justification=left and 'Left' or 'Center',LineSpacingBottom=2,
   VerticalJustification='Top',LuaKey='TooltipData',LuaValue=tooltip or {},UseDescription=description or false,
   Format=description and 'BaseFormat' or nil,VariableAutoFormat='BoldFormatGraft',TextSymbolScale=0.7})
  return c
 end
 local background=component('Background','rectangle01',cx,cy,10,'Combat_Menu')
 api.SetColor({Id=background.Id,Color={6,8,17,255}});api.SetAlpha({Id=background.Id,Fraction=0.97})
text('Title','DÁDIVAS DA DUPLA',cx,cy-510,36,gold,1700)
 local function buildPanel(player)
  buildingPlayer=player;self.PanelComponents[player]={}
  local x=cx+(player==1 and -465 or 465);local panel=model.Panels[player]
  local name=(args and args.names and args.names[player])or('JOGADOR '..player)
  self.PlayerInterfaces[player]={Owner=player,Name='LocalDuoBoonPanel'..player,Rows=self.Rows[player]}
  text('Heading'..player,'J'..player..' - '..args.layout.Short(name,30),x,cy-452,32,palette[player],820)
  text('Source'..player,panel.Source.MenuTitle or panel.Source.Name or 'BÊNÇÃOS E MELHORIAS',x,cy-409,25,gold,820)
  text('Status'..player,'Escolha sua bênção',x,cy+358,24,palette[player],820)
  text('DetailsTitle'..player,'DETALHES',x-405,cy+30,27,gold,810,true)
  text('ReplacementCurrent'..player,'',x-405,cy+20,22,gold,810,true)
  text('ReplacementNew'..player,'',x-405,cy+49,22,palette[player],810,true)
  text('Details'..player,'',x-405,cy+76,27,white,810,true)
  text('DetailsOneStat'..player,'',x-405,cy+148,25,white,810,true)
  text('DetailsTwoStats'..player,'',x-405,cy+208,25,white,810,true)
  for line=1,2 do
   text('StatLabel'..player..'_'..line,'',x-405,cy+76+(line-1)*48,27,white,480,true)
   text('StatValue'..player..'_'..line,'',x+95,cy+76+(line-1)*48,24,gold,310,true)
  end
  text('Page'..player,'',x,cy+329,23,white,820)
  local action=component('Reroll'..player,'ContextualActionButton',x,cy+419,0.7,'Combat_Menu_Overlay')
  api.UseableOff({Id=action.Id}) -- Only this owner's normal Up/Down/Confirm selects this action.
  text('RerollLabel'..player,'',x,cy+400,22,gold,820)
  self.Pages[player]={};self.Stats[player]={};self.Replacements[player]={}
  self.Rows[player]={}
  self.PlayerInterfaces[player].Rows=self.Rows[player]
  for index,offer in ipairs(panel.Offers)do
   local y=cy-308+(index-1)*116;local key='P'..player..'C'..index
   local card=component(key,'BoonSlotBase',x,y,0.60)
   api.SetScaleY({Id=card.Id,Fraction=0.72})
   api.UseableOff({Id=card.Id}) -- Engine's shared cursor never confirms either panel.
   if rarity[offer.Rarity]then api.SetAnimation({DestinationId=card.Id,Name=rarity[offer.Rarity]})end
   local highlight=component(key..'Highlight','BlankObstacle',x,y,0.60,'Combat_Menu_Overlay')
   api.SetScaleY({Id=highlight.Id,Fraction=0.72})
   api.SetAnimation({DestinationId=highlight.Id,Name='BoonSlotHighlight'})
   api.SetColor({Id=highlight.Id,Color=palette[player]})
   local icon=component(key..'Icon','BlankObstacle',x-357,y,0.36,'Combat_Menu_Overlay')
   if offer.Icon then api.SetAnimation({DestinationId=icon.Id,Name=offer.Icon})end
   local frame=component(key..'Frame','BlankObstacle',x-357,y,0.36,'Combat_Menu_Overlay')
   if offer.Frame then api.SetAnimation({DestinationId=frame.Id,Name=offer.Frame})end
   -- Same native rarity colors/backings as UpgradeChoiceLogic; never infer or change rarity.
   local boonColor=offer.Data and offer.Data.CustomRarityColor
    or api.Color and api.Color['BoonPatch'..tostring(offer.Rarity)]or gold
   local emphasized=offer.Rarity=='Legendary'or offer.Rarity=='Duo'
   text(key..'Title',args.layout.Short(title(offer.Title),34),x-267,y-46,emphasized and 32 or 30,boonColor,570,true,offer.Data)
   local replacement=replacementInfo(offer,panel,player)
   -- A replacement gets three separate text bands inside its existing card.
   local metadataY=y+(replacement and -11 or -6)
   text(key..'Rarity',(offer.Data and offer.Data.CustomRarityName)or(offer.Rarity=='Common' and 'Comum'or 'Boon_'..offer.Rarity),x-267,metadataY,replacement and 19 or(emphasized and 28 or(rarity[offer.Rarity]and 26 or 25)),boonColor,280,true)
   text(key..'Level',offer.Blocked and 'Indisponível no coop'or args.layout.Metadata(offer,panel.Source),x+42,metadataY,replacement and 19 or(offer.Blocked and 21 or 25),offer.Blocked and {230,150,130,255}or gold,275,true)
   self.Replacements[player][index]=replacement or false
   if replacement or offer.Blocked then
    text(key..'Replacement',offer.Blocked and blockedReason(offer)or('SUBSTITUI: '..args.layout.Short(replacement.OldName,36)),x-267,y+(replacement and 16 or 30),replacement and 17 or 20,gold,570,true)
    if replacement and replacement.OldIcon then
     local oldIcon=component(key..'ReplacementIcon','BlankObstacle',x+360,y+22,0.13,'Combat_Menu_Overlay')
     api.SetAnimation({DestinationId=oldIcon.Id,Name=replacement.OldIcon})
     if replacement.OldRarity and replacement.OldRarity~=''then
      local oldFrame=component(key..'ReplacementFrame','BlankObstacle',x+360,y+22,0.13,'Combat_Menu_Overlay')
      api.SetAnimation({DestinationId=oldFrame.Id,Name='BoonIcon_Frame_'..replacement.OldRarity})
     end
    end
   end
   local template=api.DuoDescriptionTemplate and api.DuoDescriptionTemplate(offer.Description,offer.Data)
    or args.templates[offer.Description] and args.templates[offer.Description].Description or offer.DescriptionLiteral
   assert(template,'Missing verified description template: '..tostring(offer.Description))
   local chaos=offer.Raw and offer.Raw.Type=='TransformingTrait'
   if chaos then
    assert(type(offer.Data)=='table'and type(offer.BlessingData)=='table'
     and offer.Data.OnExpire and offer.Data.OnExpire.TraitData==offer.BlessingData,
     'Chaos description requires the actual paired personal curse and blessing')
    local blessing=api.DuoDescriptionTemplate and api.DuoDescriptionTemplate(offer.Description2,offer.BlessingData)
     or args.templates[offer.Description2]and args.templates[offer.Description2].Description
    assert(blessing,'Missing verified Chaos blessing template: '..tostring(offer.Description2))
    -- Namespace only presentation markup; never merge or mutate either processed trait.
    -- The stock curse already owns this exact future blessing under OnExpire.TraitData.
    blessing=blessing:gsub('%$TooltipData%.','$TooltipData.OnExpire.TraitData.')
    template='MALDIÇÃO\n'..template..'\nBÊNÇÃO\n'..blessing
   end
   local definition=not chaos and api.TraitData and api.TraitData[offer.ItemName]or offer.Data or {}
   local stats=not chaos and(offer.StatLines or definition.StatLines)or {}
   if not chaos and definition.CustomStatLinesWithShrineUpgrade and api.GetNumShrineUpgrades
    and api.GetNumShrineUpgrades(definition.CustomStatLinesWithShrineUpgrade.ShrineUpgradeName)>0 then
    stats=definition.CustomStatLinesWithShrineUpgrade.StatLines
   end
   if not chaos and definition.DreamRunStatLines and api.CurrentRun and api.CurrentRun.IsDreamRun then stats=definition.DreamRunStatLines end
   local statText={}
   for _,statKey in ipairs(stats)do if statKey~=''then
    local record=args.templates[statKey]
    assert(record and record.DisplayName and record.Description,'Missing native StatLine template: '..statKey)
    statText[#statText+1]={Label=record.DisplayName,Value=record.Description}
   end end
   -- Separate native label/value text boxes: NoWrap/style cannot absorb body text.
   self.Stats[player][index]=statText
   local rows=math.min(2,#statText)
   local pages=args.layout.Pages(template,chaos and(offer.TooltipData or offer.Data)or offer.Data,44,6-rows)
   local count=math.max(#pages,math.ceil(#statText/2))
   while #pages<count do pages[#pages+1]=pages[#pages]end
   self.Pages[player][index]=pages
   self.Rows[player][index]={Card=card,Highlight=highlight}
  end
 end
 self.BuildPanel=buildPanel
 for player=1,2 do buildPanel(player)end
 buildingPlayer=nil
 self:Render()
 end
 local ok,errorText=pcall(build)
 if not ok then pcall(self.Destroy,self);error(errorText)end
 return self
end
function View:Render(onlyPlayer)
 if self.Closed then return end
 for player=onlyPlayer or 1,onlyPlayer or 2 do
  local p=self.Model.Panels[player]
  local index=p.Selected or math.min(p.Focus,#p.Offers)
  if self.Focused[player]~=index then self.Focused[player]=index;self.Page[player]=1 end
  local label=p.Status=='committed' and 'Bênção recebida - aguardando parceiro'
   or p.Status=='uncertain' and 'Aplicação interrompida\nNão confirme novamente'
   or not p.Connected and 'Conecte seu controle'
   or p.Status~='choosing' and 'Recebendo bênção' or 'Escolha sua bênção'
  self.Api.ModifyTextBox({Id=self.Components['Status'..player].Id,Text=label})
  local info=p.Reroll or {};local focused=p.Focus>#p.Offers
  local actionText=info.Cost and ('Alterar opções · custo '..info.Cost..' · saldo '..info.Balance)or ''
  if p.Status~='choosing'then actionText=''elseif focused and actionText~=''then actionText='CONFIRMAR: '..actionText end
  self.Api.ModifyTextBox({Id=self.Components['RerollLabel'..player].Id,Text=actionText})
  self.Api.SetAlpha({Id=self.Components['Reroll'..player].Id,
   Fraction=(p.Status~='choosing'or not info.Cost)and 0 or(info.Available and(focused and 1 or 0.55)or 0.2)})
  if p.RerollError and p.Status=='choosing'then
   self.Api.ModifyTextBox({Id=self.Components['Status'..player].Id,Text=p.RerollError})
  end
  local offer=p.Offers[index];local pages=self.Pages[player][index];local page=self.Page[player]
  if offer.Blocked and p.Status=='choosing'then
   local any=false;for _,row in ipairs(p.Offers)do if not row.Blocked then any=true;break end end
   local reason=offer.UnsupportedReason or 'Opção indisponível.'
   self.Api.ModifyTextBox({Id=self.Components['Status'..player].Id,Text='J'..player..': '..(any and reason or('Sem melhorias compatíveis\n'..reason))})
  end
  if p.CancelReason and p.Status=='choosing'then
   self.Api.ModifyTextBox({Id=self.Components['Status'..player].Id,Text='J'..player..': '..p.CancelReason})
  end
  local stats=self.Stats[player][index]
  local statPage=math.min(page,math.max(1,math.ceil(#stats/2)))
  local start=(statPage-1)*2+1;local rows=math.min(2,math.max(0,#stats-start+1))
  for line=1,2 do
   local stat=stats[start+line-1]
   self.Api.ModifyTextBox({Id=self.Components['StatLabel'..player..'_'..line].Id,Text=stat and stat.Label or '',LuaKey='TooltipData',LuaValue=offer.Data or {}})
   self.Api.ModifyTextBox({Id=self.Components['StatValue'..player..'_'..line].Id,Text=stat and stat.Value or '',LuaKey='TooltipData',LuaValue=offer.Data or {}})
  end
  local fullTitle=self.Api.GetDisplayName and self.Api.GetDisplayName({Text=offer.Title})or self.Args.templates[offer.Title]and self.Args.templates[offer.Title].DisplayName or offer.Title
  self.Api.ModifyTextBox({Id=self.Components['DetailsTitle'..player].Id,Text=self.Args.layout.Short(fullTitle,50),LuaKey='TooltipData',LuaValue=offer.Data or {}})
  local replacement=self.Replacements[player][index]
  self.Api.SetAlpha({Id=self.Components['DetailsTitle'..player].Id,Fraction=replacement and 0 or 1})
  self.Api.SetAlpha({Id=self.Components['ReplacementCurrent'..player].Id,Fraction=replacement and 1 or 0})
  self.Api.SetAlpha({Id=self.Components['ReplacementNew'..player].Id,Fraction=replacement and 1 or 0})
  self.Api.ModifyTextBox({Id=self.Components['ReplacementCurrent'..player].Id,
   Text=replacement and('ATUAL: '..self.Args.layout.Short(replacement.OldName,49))or ''})
  self.Api.ModifyTextBox({Id=self.Components['ReplacementNew'..player].Id,
   Text=replacement and('NOVA: '..self.Args.layout.Short(replacement.NewName,49))or ''})
  local keys={'Details'..player,'DetailsOneStat'..player,'DetailsTwoStats'..player}
  for i,key in ipairs(keys)do
   local active=i==rows+1;local component=self.Components[key]
   self.Api.SetAlpha({Id=component.Id,Fraction=active and 1 or 0})
   self.Api.ModifyTextBox({Id=component.Id,Text=active and pages[page]or '',
    UseDescription=false,LuaKey='TooltipData',LuaValue=offer.Raw and offer.Raw.Type=='TransformingTrait'and(offer.TooltipData or offer.Data)or offer.Data or {}})
   if active then self.ActiveDetails[player]=component end
  end
  self.Api.ModifyTextBox({Id=self.Components['Page'..player].Id,Text=#pages>1 and('Detalhes '..page..' / '..#pages)or ''})
  for index,row in ipairs(self.Rows[player])do
   self.Api.SetAlpha({Id=row.Highlight.Id,Fraction=(p.Selected or p.Focus)==index and 1 or 0})
   local blocked=p.Offers[index].Blocked==true
   self.Api.SetAlpha({Id=row.Card.Id,Fraction=blocked and 0.35 or(p.Status=='committed' and p.Selected~=index and 0.35 or 1)})
  end
 end
end
-- Presentation only, called by Entry after observing a NEW committed receipt.
function View:ConfirmFeedback(player,receipt)
 if self.Closed or(player~=1 and player~=2)or self.FeedbackDone[player]then return false end
 local panel=self.Model.Panels[player];local hero=panel and panel.Hero
 if type(receipt)~='table'or receipt.Status~='committed'or receipt.Player~=player
  or receipt.Key~=self.Model.Id..':J'..player or not hero or not hero.LocalDuoBuildReceipts
  or hero.LocalDuoBuildReceipts[receipt.Key]~=receipt then return false end
 local offer=panel.Offers[receipt.Index]
 if not offer or offer.Owner~=player or offer.Blocked or offer.ItemName~=receipt.Name then return false end
 local key='P'..player..'C'..receipt.Index
 local component=self.Components[key];local record=self.FeedbackWorld;local api=self.Api
 local function current()
  if self.Closed or not record.Run or not record.Room or not record.Map or not record.Session
   or api.CurrentRun~=record.Run or api.CurrentRun.CurrentRoom~=record.Room or api.MapState~=record.Map or api.SessionMapState~=record.Session
   or self.Model.Panels[player]~=panel or panel.Hero~=hero or hero.LocalDuoBuildReceipts[receipt.Key]~=receipt
   or not component or self.Components[key]~=component or not self.PanelComponents[player]
   or self.PanelComponents[player][key]~=component or not self.Rows[player][receipt.Index]
   or self.Rows[player][receipt.Index].Card~=component or type(component.Id)~='number'
   or component.Id<=0 or component.Id>=math.huge or component.Id%1~=0
   or type(api.IsAlive)~='function'then return false end
  local ok,alive=pcall(api.IsAlive,{Id=component.Id});return ok and alive==true
 end
 if not current()or type(api.PlaySound)~='function'or type(api.CreateAnimation)~='function'then return false end
 self.FeedbackDone[player]=receipt -- before native calls; failures never replay a reward or effect
 local source=panel.Source or{}
 api.PlaySound({Name=source.UpgradeSelectedSound or '/SFX/HeatRewardDrop',Id=component.Id})
 if not current()then return false end
 api.CreateAnimation({Name='BoonGetBlack',DestinationId=component.Id,Scale=1.0,Group='Combat_Menu'})
 if not current()then return false end
 api.CreateAnimation({Name='BoonGet',DestinationId=component.Id,Scale=1.0,Group='Combat_Menu_Additive',Color=source.LootColor})
 return true -- native calls requested, not a pixel/audio playback proof
end
function View:RefreshPanel(player)
 assert(player==1 or player==2,'Unknown panel')
 if self.Closed then return end
 local owned=self.PanelComponents[player]or {};local ids={}
 for _,component in pairs(owned)do ids[#ids+1]=component.Id end
 if #ids>0 then self.Api.Destroy({Ids=ids})end
 for key,component in pairs(owned)do if self.Components[key]==component then self.Components[key]=nil end end
 self.Page[player]=1;self.Focused[player]=nil;self.ActiveDetails[player]=nil
 self.BuildPanel(player);self:Render(player)
end
function View:TurnPage(player,direction)
 assert(player==1 or player==2,'Unknown panel')
 if self.Closed then return end
 local panel=self.Model.Panels[player];local pages=self.Pages[player][panel.Selected or math.min(panel.Focus,#panel.Offers)]
 self.Page[player]=math.max(1,math.min(#pages,self.Page[player]+direction));self:Render()
end
function View:Destroy()
 if self.Closed then return end
 local ids={};for _,c in pairs(self.Components)do ids[#ids+1]=c.Id end
 self.Api.Destroy({Ids=ids});self.Components={};self.Closed=true
end
return View
