-- Minimal candidate; no globals/engine/setup hooks. NOT installed.
local M={}
local function filtered(list,name)
 if list==nil then return nil end
 assert(type(list)=='table','Modifier array required')
 local keys={}
 for key,entry in pairs(list)do
   assert(type(key)=='number' and key>=1 and key%1==0 and type(entry)=='table','Expected numeric modifier entries')
   keys[#keys+1]=key
 end
 table.sort(keys)
 local out={}
 for _,key in ipairs(keys)do
   local entry=list[key]
   if entry.Name~=name then out[#out+1]=entry end
 end
 return out
end
local function entryEqual(a,b)
 if a==b then return true end
 if not a or not b then return false end
 for k,v in pairs(a)do if b[k]~=v then return false end end
 for k,v in pairs(b)do if a[k]~=v then return false end end
 return true
end
local function arrayEqual(a,b)
 if a==b then return true end
 if not a or not b or #a~=#b then return false end
 for i=1,#a do if not entryEqual(a[i],b[i])then return false end end
 local total=0;for _ in pairs(a)do total=total+1 end
 return total==#a
end
local function finitePositive(v)
 return type(v)=='number' and v>0 and v==v and v<math.huge
end
function M.Reconcile(unit,registeredCount,config)
 assert(type(unit)=='table' and type(config)=='table','Unit/config required')
 assert(type(registeredCount)=='number' and registeredCount>=0 and registeredCount%1==0,'Explicit registered player count required')
 local eligible=registeredCount>=2 and unit.RequiredKill and not unit.Charmed and not unit.AlwaysTraitor and unit.MaxHealth
 local incoming=filtered(unit.IncomingDamageModifiers,'LocalDuoResistance')
 local outgoing=filtered(unit.OutgoingDamageModifiers,'LocalDuoDamage')
 if eligible then
   local resistance=unit.IsBoss and config.BossResistance or config.EnemyResistance
   assert(finitePositive(resistance)and finitePositive(config.EnemyDamage),'Valid finite configured factors required')
   incoming=incoming or {};outgoing=outgoing or {}
   incoming[#incoming+1]={Name='LocalDuoResistance',GlobalMultiplier=1/resistance}
   outgoing[#outgoing+1]={Name='LocalDuoDamage',GlobalMultiplier=config.EnemyDamage}
 end
 local changed=not arrayEqual(unit.IncomingDamageModifiers,incoming)or not arrayEqual(unit.OutgoingDamageModifiers,outgoing)
 if changed then unit.IncomingDamageModifiers=incoming;unit.OutgoingDamageModifiers=outgoing end
 return changed,eligible and 'scaled' or 'local-factors-removed'
end
return M
