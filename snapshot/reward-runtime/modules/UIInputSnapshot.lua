-- Passive read of existing Runtime/Input/Model data, never Poll/confirm/apply.
local fields={'Connected','Focused','Reason','Device','ControllerId','NativeInstance','Up','Down','Left','Right',
 'Confirm','Cancel','PageNext','PagePrevious','X','Y','Index','Name'}
local function inputRecord(source)
 if type(source)~='table'then return {Available=false}end
 local out={Available=true}
 for _,key in ipairs(fields)do
  local value=source[key];local kind=type(value)
  if kind=='string'or kind=='number'or kind=='boolean'then out[key]=value end
 end
 if source.Instance~=nil then out.InstanceReference=tostring(source.Instance)end
 return out
end
return function(runtime)
 local report={Enabled=runtime.Enabled,Subscribed=runtime.Subscribed,Scheduled=runtime.Scheduled,
  Updating=runtime.Updating,TickCount=runtime.TickCount,UpdateCount=runtime.UpdateCount,
  Error=runtime.Error and tostring(runtime.Error)or nil,Players={},Sessions={}}
 local input=runtime.Input
 if input then
  report.PollCount=input.PollCount;report.LastPollTime=input.LastPollTime
  for p=1,2 do
   local binding=input.Bindings and input.Bindings[p]
   report.Players[p]={Raw=inputRecord(input.LastRaw and input.LastRaw[p]),
    Cache=inputRecord(input.Cache and input.Cache[p]),BrokerArmed=binding and binding.Armed,
    BindingIdentity=binding and binding.Identity}
   local counts={}
   for key,count in pairs(input.RawSignalCounts and input.RawSignalCounts[p]or{})do
    counts[key]={PressedSamples=count.PressedSamples,RisingEdges=count.RisingEdges,
     LastSampleAt=count.LastSampleAt,LastPressedAt=count.LastPressedAt,LastRiseAt=count.LastRiseAt}
   end
   report.Players[p].RawSignalCounts=counts
  end
 end
 report.BridgeError=runtime.Bridge and runtime.Bridge.Error and tostring(runtime.Bridge.Error)or nil
 for key,record in pairs(runtime.Bridge and runtime.Bridge.Records or{})do
  local h=record.Handle;local s=h and h.Session
  local entry={Key=key,Phase=record.Phase,Error=record.Error and tostring(record.Error)or nil,
   HandleError=h and h.Error,SessionState=s and s.State,SessionReason=s and s.Reason,
   SessionLastError=s and s.Errors and s.Errors[#s.Errors],ModelClosed=h and h.Model and h.Model.Closed,
   ViewClosed=h and h.View and h.View.Closed,Running=h and h.Running,Panels={}}
  for p=1,2 do
   local panel=h and h.Model and h.Model.Panels[p]
   if panel then entry.Panels[p]={Focus=panel.Focus,Status=panel.Status,Armed=panel.Armed,
    Connected=panel.Connected,Direction=panel.Direction,NextRepeat=panel.NextRepeat,
    InstanceReference=panel.Instance and tostring(panel.Instance),Previous=inputRecord(panel.Previous)}end
  end
  report.Sessions[#report.Sessions+1]=entry
 end
 return report
end
