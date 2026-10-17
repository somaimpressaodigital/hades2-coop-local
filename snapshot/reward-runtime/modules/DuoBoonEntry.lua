-- Single public integration entry: Entry.Open(host,args).
-- A host table identifies one run/runtime; retain it between openings.
local Entry={}
local runtimes=setmetatable({}, {__mode='k'})
local Handle={};Handle.__index=Handle
local function notifyHud(host,phase,scope)
 local hud=host.Game and host.Game.LocalDuoHudRuntime
 if hud and hud.Enabled and type(hud.Notify)=='function'then
  -- HUD failures must never replay a choice or prevent reward/session cleanup.
  pcall(hud.Notify,hud,phase,scope)
 end
end
function Handle:Sync()
 if not self.Choices or not self.Model then return end
 for p=1,2 do
  local source,target=self.Choices.Panels[p],self.Model.Panels[p]
  local revision=source.RerollRevision or 0
  if target.RerollRevision~=nil and target.RerollRevision~=revision then
   target.Source=self.Host.Modules.Model.Clone(source.Source)
   target.Offers=self.Host.Modules.Model.Clone(source.Offers);target.Selected=nil;target.Focus=1
   for index,offer in ipairs(target.Offers)do if not offer.Blocked then target.Focus=index;break end end
   target.Revision=target.Revision+1;target.Armed=false;target.Previous={}
   self.PanelRefresh=self.PanelRefresh or {};self.PanelRefresh[p]=true
  end
  target.RerollRevision=revision
  self.RerollInfo=self.RerollInfo or {}
  local stamp=tostring(revision)..':'..tostring(source.RerollAttemptSerial or 0)
  if not self.RerollInfo[p]or self.RerollInfo[p].Stamp~=stamp then
   local info=self.Host.readOwnRerollInfo and self.Host.readOwnRerollInfo(self.Args.key,p)or {Available=false}
   self.RerollInfo[p]={Stamp=stamp,Info=info}
  end
  target.Reroll=self.RerollInfo[p].Info
  target.Status=source.Status;target.Selected=source.Receipt and source.Receipt.Index
  if target.Focus>#target.Offers and not target.Reroll.Available then target.Focus=#target.Offers end
  target.RerollError=source.RerollError
 end
end
function Handle:Refresh()
 self:Sync()
 if self.View and not self.View.Closed then
  for p=1,2 do if self.PanelRefresh and self.PanelRefresh[p]then self.View:RefreshPanel(p);self.PanelRefresh[p]=nil end end
  self.View:Render()
 end
end
function Handle:Update()
 if not self.Session then return end
 self.Session:Update()
 if self.Session.State~='active'then return end
 local ok,errorText=pcall(function()
  self.DetailInput=self.DetailInput or {}
  local inputs={}
  for p=1,2 do inputs[p]=self.Host.read(self.Args.devices[p]);self.Model:Poll(p,inputs[p],self.Host.now())end
  self:Refresh()
  self.Session:Update() -- Owner Cancel reaches supervisor before queued applications.
  if self.Session.State~='active'then return end
  for p=1,2 do
   local input=inputs[p];local previous=self.DetailInput[p]
   if not previous or previous.Instance~=input.Instance or not input.Connected or input.Focused==false then
    previous={Instance=input.Instance,Armed=false};self.DetailInput[p]=previous
   end
   if previous.Armed then
    if input.PageNext and not previous.Next then self.View:TurnPage(p,1)end
    if input.PagePrevious and not previous.Previous then self.View:TurnPage(p,-1)end
   elseif not input.PageNext and not input.PagePrevious and input.Connected and input.Focused~=false then previous.Armed=true end
   previous.Next=input.PageNext;previous.Previous=input.PagePrevious
  end
  if #self.Choices.Queue>0 and not self.Running then
   self.Running=true
   local scheduled,scheduleError=pcall(self.Host.thread,function()
    -- Inputs may have been queued before disconnect, death or room transition.
    self.Session:Update()
    local beforeCommit={}
    for p=1,2 do local panel=self.Choices.Panels[p];local hero=panel.Hero
     beforeCommit[p]={Panel=panel,Hero=hero,Key=panel.Key,Status=panel.Status,Receipt=panel.Receipt,
      Build=hero.LocalDuoBuildReceipts and hero.LocalDuoBuildReceipts[panel.Key],
      Applied=hero.LocalDuoBoonReceipts and hero.LocalDuoBoonReceipts[panel.Key]}
    end
    local success,result=pcall(function()
     if self.Session.State=='active'then self.Choices:Drain()end
    end)
    self.Running=false
    self.CommitFeedback=self.CommitFeedback or {}
    self.HudCommitted=self.HudCommitted or {}
    for p=1,2 do
     if self.Choices.Panels[p].Status=='committed' and not self.HudCommitted[p]then
      self.HudCommitted[p]=true
      notifyHud(self.Host,'commit',self.Session.Scope)
     end
     local prior=beforeCommit[p];local panel=self.Choices.Panels[p];local hero=panel.Hero
     local receipt=panel.Receipt;local applied=hero.LocalDuoBoonReceipts and hero.LocalDuoBoonReceipts[panel.Key]
     if prior.Panel==panel and prior.Hero==hero and prior.Key==panel.Key and prior.Status=='queued'
      and prior.Receipt==nil and prior.Build==nil and prior.Applied==nil and not self.CommitFeedback[p]
      and panel.Status=='committed'and type(receipt)=='table'and receipt.Status=='committed'
      and receipt.Player==p and receipt.Key==panel.Key and hero.LocalDuoBuildReceipts
      and hero.LocalDuoBuildReceipts[panel.Key]==receipt and type(applied)=='table'
      and applied.Status=='committed'and applied.Token==panel.Key and applied.Player==p
      and self.Session.State=='active'and self.View and not self.View.Closed
      and type(self.View.ConfirmFeedback)=='function'then
      self.CommitFeedback[p]=receipt -- consume feedback only; never modify application receipts
      local valid,live=pcall(self.Host.roomValid,self.Session.Scope)
      if valid and live==true then
       local shown,why=pcall(self.View.ConfirmFeedback,self.View,p,receipt)
       if not shown then self.FeedbackError=tostring(why)end
      end
     end
    end
    if not success then self.Error=tostring(result);self.Session:Finish('worker-error')end
    self.Session:Update()
    if self.Session.State=='active'then
     local rendered,renderError=pcall(self.Refresh,self)
     if not rendered then self.Error=tostring(renderError);self.Session:Finish('render-error')end
    end
   end)
   if not scheduled then self.Running=false;error(scheduleError)end
  end
 end)
 if not ok then self.Error=tostring(errorText);self.Session:Finish('input-error')end
end
function Handle:Close(reason)if self.Session then self.Session:Finish(reason or 'cancelled')end end
function Handle:PanelClosed(p)self.Session:PanelClosed(p)end
function Handle:Report()
 return {Session=self.Session:Report(),Choices=self.Choices and self.Choices:Result(),Error=self.Error}
end
function Entry.Open(host,args)
 local modules=assert(host.Modules,'Provide explicit module dependencies')
 for _,name in ipairs({'Model','Adapter','Apply','Choices','View','Session'})do assert(modules[name],'Missing module: '..name)end
 for _,name in ipairs({'read','now','thread','roomValid','connected','alive','choiceValid','acquire','release','secureRewards'})do
  assert(type(host[name])=='function','Missing host callback: '..name)
 end
 local runtime=runtimes[host]
 if not runtime then
  runtime={Handles={}};runtimes[host]=runtime
  local function handle(scope)return assert(runtime.Handles[scope.Key],'Missing registered handle')end
  runtime.Manager=modules.Session.New({
   acquire=host.acquire,release=host.release,roomValid=host.roomValid,connected=host.connected,alive=host.alive,
   openUI=function(scope,owner)
    local h=handle(scope);h.Owner=owner
    local native=modules.Apply.New(host.ApplyApi)
    local adapter=modules.Adapter.New({Context=host.Context,Game=host.Game,
     commitChoice=native.commit,selectVisibleOptions=host.selectVisibleOptions})
    h.Model=modules.Model.New({id=scope.Key,players=scope.Heroes,sources=scope.Sources,
     devices=h.Args.devices,runAs=adapter.runAs,generate=adapter.generate,
     apply=function()error('Use only DuoBuildChoices.Drain')end})
    local offers={h.Model.Panels[1].Offers,h.Model.Panels[2].Offers}
    h.Choices=modules.Choices.New({rewardKey=scope.Key,Context=host.Context,Apply=native,
     LootIndividual=host.LootIndividual,clone=modules.Model.Clone,heroes=scope.Heroes,
     sources=scope.Sources,offers=offers,valid=host.choiceValid,
     reroll=host.requestOwnReroll and function(p,request)return host.requestOwnReroll(scope.Key,p,request)end})
    -- Reuse input arming/repeat logic; do not start Model's application queue.
    h.Model.Request=function(_,p,index)
     if index==#h.Model.Panels[p].Offers+1 then
      if not h.Model.Panels[p].Reroll or not h.Model.Panels[p].Reroll.Available then return false end
      local accepted=h.Choices:RequestReroll(p);h:Sync();return accepted
     end
     local accepted=h.Choices:Confirm(p,index);if accepted then h.Model.Panels[p].CancelReason=nil end;h:Sync();return accepted
    end
    h.Model.Cancel=function(_,p)
     local a,b=scope.Sources[1],scope.Sources[2]
     if a.LocalDuoCommonRoot or a.LocalDuoCommonCarrier or b.LocalDuoCommonRoot or b.LocalDuoCommonCarrier then
      h.Model.Panels[p].CancelReason='Escolha uma bênção para continuar'
      return false -- Stock common choice remains mandatory; no forfeit/closed cache.
     end
     local accepted=h.Choices:Cancel(p);h:Sync();return accepted
    end
    h:Sync()
    modules.View.New(host.Game,h.Model,{names=h.Args.names,onAllocated=function(view)h.View=view end})
    notifyHud(host,'open',scope)
    return true
   end,
   closeUI=function(scope)
    local h=handle(scope);if h.View then h.View:Destroy()end
    if not h.HudCloseNotified then h.HudCloseNotified=true;notifyHud(host,'close',scope)end
    return true
   end,
      stopChoices=function(scope,owner,reason)
    local h=handle(scope);if h.Choices then h.Choices:Abort(reason)end;return true
   end,
   isApplying=function(scope)
    local h=handle(scope);return h.Running==true or (h.Choices and h.Choices.Draining==true)or false
   end,
   choiceStatus=function(scope,owner,p)return handle(scope).Choices.Panels[p].Status end,
   secureRewards=function(scope,owner,report)
    local h=handle(scope);h:Sync()
    return host.secureRewards(scope,owner,report,h.Choices and h.Choices:Result())
   end})
 end
 local existing=runtime.Handles[args.key]
 if existing then return existing,false end
 local h=setmetatable({Host=host,Args=args,Running=false},Handle)
 runtime.Handles[args.key]=h -- Before open/failure callbacks can run.
 local ok,session,created,reason=pcall(runtime.Manager.Open,runtime.Manager,args)
 if not ok then runtime.Handles[args.key]=nil;error(session)end
 if not session then runtime.Handles[args.key]=nil;return nil,false,reason end
 h.Session=session
 return h,created
end
function Entry.CanRetireClosed(host,key,expected)
 local runtime=runtimes[host];local h=runtime and runtime.Handles[key]
 if not h or h~=expected or not h.Session or h.Session.State~='closed' or h.Running
  or(h.Choices and h.Choices.Draining)or(h.View and not h.View.Closed)then return false end
 local s=h.Session;local manager=runtime.Manager
 if manager.Active~=nil or manager.Sessions[key]~=s or s.Manager~=manager then return false end
 for _,lease in ipairs(s.Leases or{})do if not lease.Released then return false end end
 return s.RewardsSecured==true and s.UIClosed==true and s.Stopped==true
end
function Entry.RetireClosed(host,key,expected)
 if not Entry.CanRetireClosed(host,key,expected)then return false end
 local runtime=runtimes[host]
 runtime.Manager.Sessions[key]=nil;runtime.Handles[key]=nil
 return true -- Previous session is already naturally closed; new Open creates another session.
end
return Entry
