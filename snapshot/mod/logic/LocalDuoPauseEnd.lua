-- The native Pause button calls these Lua functions. No input polling or extra menu.
local Players=ModRequire 'CoopPlayers.lua'
local Campaign=ModRequire 'LocalDuoCampaignEnd.lua'
local Diagnostics=ModRequire 'LocalDuoDiagnostics.lua'
local M={};local frame,last;local lastCanReason,lastCanAllowed,lastCanTrace
local function same(r)
 if not r then return false,'Pause frame not captured'end
 if LocalDuoCoopModeActive~=true then return false,'Coop mode is not active'end
 if Players.GetPlayersCount()~=2 then return false,'Current player count is not two'end
 if CurrentRun~=r.Run then return false,'Pause run reference changed'end
 if GameState~=r.State then return false,'Pause GameState reference changed'end
 if MapState~=r.Map then return false,'Pause MapState reference changed'end
 if SessionMapState~=r.Session then return false,'Pause SessionMapState reference changed'end
 for p=1,2 do local h=Players.GetHero(p)
  if h~=r.Heroes[p]or not h or h.ObjectId~=r.Ids[p]then return false,'Pause actor reference or ID changed: J'..p end
 end
 return true
end
local function provider()
 local arena=LocalDuoArenaRuntime
 if arena~=nil then
  if type(arena)~='table' or type(arena.IsDuelSceneOwned)~='function' then return nil end
  local ok,owned=pcall(arena.IsDuelSceneOwned,arena)
  if not ok or owned~=false then
   -- RequestExit alone does not kill the private actors and cannot implement this button.
   if owned~=true or type(arena.CanEndRun)~='function' or type(arena.RequestEndRun)~='function' then return nil end
   return arena,arena.CanEndRun,arena.RequestEndRun
  end
 end
 return Campaign,Campaign.CanRequest,Campaign.Request
end
local function can(r,paused)
 local current,why=same(r)
 if not current then return false,nil,nil,nil,why end
 if r.Requested then return false,nil,nil,nil,'Pause end already requested'end
 if paused and r.Session.IsPaused~=true then return false,nil,nil,nil,'Pause flag is not active'end
 local owner,check,request=provider()
 if not owner or type(check)~='function'or type(request)~='function'then return false,nil,nil,nil,'Campaign end provider unavailable'end
 local ok,value,reason
 if owner==Campaign then ok,value,reason=pcall(check)else ok,value,reason=pcall(check,owner)end
 if not ok then return false,owner,check,request,'Campaign end check failed: '..tostring(value)end
 if value~=true then return false,owner,check,request,tostring(reason or 'Campaign end check returned false')end
 return true,owner,check,request
end
function M.Opened()
 lastCanTrace=nil
 if LocalDuoCoopModeActive~=true or Players.GetPlayersCount()~=2 then frame=nil;return end
 if frame and same(frame) then return end
 local a,b=Players.GetHero(1),Players.GetHero(2)
 if type(a)~='table' or type(b)~='table' or a==b or type(SessionMapState)~='table' then frame=nil;return end
 frame={Run=CurrentRun,State=GameState,Map=MapState,Session=SessionMapState,
  Heroes={a,b},Ids={a.ObjectId,b.ObjectId}}
end
function M.CanRequest()
 local allowed,_,_,_,why=can(frame,true)
 -- The guarded native Pause bridge owns Resume; Lua never fabricates a native close API.
 lastCanAllowed=allowed==true;lastCanReason=not lastCanAllowed and why or nil
 local room=type(CurrentRun)=='table'and CurrentRun.CurrentRoom
 local trace=tostring(lastCanAllowed)..' reason='..tostring(lastCanReason)..' room='..tostring(type(room)=='table'and room.Name)
  ..' hub='..tostring(type(CurrentHubRoom)=='table'and CurrentHubRoom.Name or CurrentHubRoom)..' paused='..tostring(type(SessionMapState)=='table'and SessionMapState.IsPaused)
  ..' frame='..tostring(frame~=nil)
 if trace~=lastCanTrace then
  lastCanTrace=trace
  if type(Diagnostics.Write)=='function'then pcall(Diagnostics.Write,'pauseEndCan',trace)end
 end
 return lastCanAllowed
end
function M.Request()
 local allowed,owner,check,request=can(frame,true)
 if not allowed then return false end
 local r=frame
 r.Requested=true;r.Provider=owner;r.Check=check;r.Dispatch=request;last=r
 return true -- intent armed only; actual native Resume must close/unpause before Closed dispatches death
end
function M.CanResume()
 local r=frame
 if not r or not r.Requested or not same(r)or r.Session.IsPaused~=true then return false end
 local owner,check,request=provider()
 if owner~=r.Provider or check~=r.Check or request~=r.Dispatch then return false end
 local ok,value
 if owner==Campaign then ok,value=pcall(check)else ok,value=pcall(check,owner)end
 return ok and value==true
end
function M.Closed()
 local r=frame;frame=nil -- native close invalidates this exact menu lifetime once
 if not r or not r.Requested then return false end
 if not same(r) or r.Session.IsPaused==true then r.Error='Pause/world not actually released';return false end
 local owner,check,request=provider()
 if owner~=r.Provider or check~=r.Check or request~=r.Dispatch then r.Error='End-run provider changed';return false end
 local ok,accepted,why
 if owner==Campaign then ok,accepted,why=pcall(request) else ok,accepted,why=pcall(request,owner) end
 if not ok or accepted~=true then r.Error=tostring(ok and why or accepted);return false end
 r.Accepted=true;return true -- provider must defer the actual lifecycle until this callback returns
end
function M.ReadStatus()
 local r=frame or last
 return {PauseOpen=frame~=nil,Requested=r and r.Requested==true or false,
  Accepted=r and r.Accepted==true or false,Error=r and r.Error,
  CanAllowed=lastCanAllowed,CanReason=lastCanReason,NativeGameplayValidated=false}
end
LocalDuoPauseCanEndRun=function()return M.CanRequest()end
LocalDuoPauseRequestEndRun=function()return M.Request()end
LocalDuoPauseCanResumeEndRun=function()return M.CanResume()end
return M
