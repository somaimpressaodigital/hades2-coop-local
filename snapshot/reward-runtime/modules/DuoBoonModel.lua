-- No engine globals: independent offers, input and exactly-once commit queue.
local Model={};Model.__index=Model
local function clone(value,seen)
 if type(value)~='table'then return value end
 seen=seen or {};if seen[value]then return seen[value]end
 local out={};seen[value]=out;for k,v in pairs(value)do out[clone(k,seen)]=clone(v,seen)end
 return out
end
Model.Clone=clone
function Model.New(args)
 assert(args.id and args.runAs and args.generate and args.apply,'Missing session/callback contract')
 assert(args.players[1] and args.players[2] and args.players[1]~=args.players[2],'Two distinct heroes required')
 assert(args.players[1].ObjectId and args.players[2].ObjectId and args.players[1].ObjectId~=args.players[2].ObjectId,'Distinct native actors required')
 assert(not args.players[1].IsDead and not args.players[2].IsDead,'Use vanilla single-player reward flow for a fallen partner')
 assert(args.devices[1]~=nil and args.devices[2]~=nil and args.devices[1]~=args.devices[2],'Distinct controllers required')
 local self=setmetatable({Id=args.id,Args=args,Panels={},Queue={},Receipts={},Closed=false,Draining=false},Model)
 for player=1,2 do
  local source=assert(args.sources[player],'Missing personal loot')
  assert(not source.LocalDuoOwner or source.LocalDuoOwner==player,'Loot belongs to another player')
  local private=clone(source)
  -- Preserve already rolled personal offers; reopening must not grant a reroll.
  -- Unowned/shared precomputed offers cannot be borrowed by the other hero.
  if source.LocalDuoOwner~=player then private.UpgradeOptions=nil end
  local offers=args.runAs(args.players[player],args.generate,args.players[player],private,player)
  assert(type(offers)=='table' and #offers>0,'No eligible choices; preserve vanilla fallback')
  assert(#offers<=3,'Prototype supports three visible choices per panel')
  local focus=1
  for i,offer in ipairs(offers)do if not offer.Blocked then focus=i;break end end
  self.Panels[player]={Hero=args.players[player],Source=private,Offers=clone(offers),
   Focus=focus,Status='choosing',Previous={},Armed=false,Connected=false,Revision=1}
 end
 return self
end
function Model:Request(player,index)
 local panel=assert(self.Panels[player],'Unknown player')
 if self.Closed or panel.Status~='choosing'then return false end
 local choice=panel.Offers[index]
 if not choice or choice.Blocked then return false end
 panel.Status='queued'
 self.Queue[#self.Queue+1]={Player=player,Index=index,Revision=panel.Revision,
  Token=tostring(self.Id)..':'..player..':'..panel.Revision,Choice=clone(choice)}
 return true
end
function Model:Poll(player,input,now)
 local panel=assert(self.Panels[player]);local previous=panel.Previous
 if self.Closed or(panel.Status~='choosing'and panel.Status~='queued')then return end
 if not input.Connected or input.Focused==false then
  panel.Connected=false;panel.Armed=false;panel.Previous={};return
 end
 panel.Connected=true
 if panel.Instance~=input.Instance then panel.Instance=input.Instance;panel.Armed=false;previous={}end
 if not panel.Armed then
  panel.Previous=clone(input)
  if not(input.Cancel or input.Confirm or input.Up or input.Down or input.Left or input.Right)then panel.Armed=true end
  return
 end
 if input.Cancel and not previous.Cancel then
  if self.Cancel then self:Cancel(player)end
  panel.Previous=clone(input);return -- Cancel wins over simultaneous Confirm.
 end
 if panel.Status~='choosing'then panel.Previous=clone(input);return end
 local direction=(input.Down or input.Right)and 1 or(input.Up or input.Left)and -1 or 0
 if direction~=0 and(direction~=panel.Direction or now>=(panel.NextRepeat or 0))then
  local candidate=panel.Focus
  local count=#panel.Offers+(panel.Reroll and panel.Reroll.Available and 1 or 0)
  for _=1,count do
   candidate=((candidate-1+direction)%count)+1
   if candidate>#panel.Offers or not panel.Offers[candidate].Blocked then panel.Focus=candidate;break end
  end
  panel.NextRepeat=now+(direction~=panel.Direction and 0.35 or 0.12)
 end
 panel.Direction=direction
 if input.Confirm and not previous.Confirm then self:Request(player,panel.Focus)end
 panel.Previous=clone(input)
end
function Model:Drain()
 if self.Draining or self.Closed then return end
 self.Draining=true
 while #self.Queue>0 and not self.Closed do
  local request=table.remove(self.Queue,1);local panel=self.Panels[request.Player]
  if not self.Receipts[request.Token]then
   panel.Status='applying'
   local ok,result=pcall(function()
    assert(not self.Args.valid or self.Args.valid(panel.Hero,panel.Source,request),'Session/hero is no longer valid')
    return self.Args.runAs(panel.Hero,self.Args.apply,panel.Hero,panel.Source,clone(request.Choice),request)
   end)
   if ok and result~=false then
    self.Receipts[request.Token]={Player=request.Player,Index=request.Index,Result=result,Token=request.Token}
    panel.Status='committed';panel.Selected=request.Index
   else
    -- The engine callback may have changed traits before raising an error.
    -- Never automatically retry an uncertain application or duplicate rewards.
    panel.Status='uncertain';panel.Error=tostring(result)
   end
  end
 end
 self.Draining=false
 if self.Panels[1].Status=='committed' and self.Panels[2].Status=='committed'then
  self.Closed=true
  if self.Args.onComplete then self.Args.onComplete(self.Receipts)end
 end
end
function Model:Abort(reason)
 self.Closed=true;self.Queue={};self.AbortReason=reason
 -- Applied receipts are intentionally retained; do not promise native rollback.
end
return Model
