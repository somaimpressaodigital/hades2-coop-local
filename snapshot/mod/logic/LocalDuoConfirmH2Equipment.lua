-- Confirmation of actual stock EquipPlayerWeapon bookkeeping in the current owner context.
-- Does not claim C++ instance/generation proof; native gameplay remains Main's check.
local M={}
function M.New(d)
 assert(d and d.Game and d.Players and d.Context)
 return function(hero,root,owner)
  local ok,confirmed=pcall(function()
   local api,p,ctx=d.Game,d.Players,d.Context
   if(owner~=1 and owner~=2)or p.GetHero(owner)~=hero or p.GetPlayerByHero(hero)~=owner
    or hero.IsDead or not hero.ObjectId or ctx.GetCurrentHeroContext()~=hero then return false end
   local actor=hero.ObjectId
   local data=api.WeaponData and api.WeaponData[root]
   if type(data)~='table'or data.Name~=root or type(api.GetWeaponData)~='function'then return false end
   local roots=api.WeaponSets and api.WeaponSets.HeroPrimaryWeapons;local native=false
   for _,name in ipairs(roots or {})do if name==root then native=true end end
   if not native or type(hero.Weapons)~='table'or hero.Weapons[root]~=true then return false end
   local map=api.MapState;local equipped=map and map.EquippedWeapons
   if type(equipped)~='table'or equipped[root]~=true then return false end
   for _,name in ipairs(roots)do if name~=root and (hero.Weapons[name]or equipped[name])then return false end end
   if data.SecondaryWeapon and hero.Weapons[data.SecondaryWeapon]~=true then return false end
   for _,name in ipairs(api.WeaponSets.HeroWeaponSets[root]or {})do if equipped[name]~=true then return false end end
   local personal=api.GetWeaponData(hero,root)
   if type(personal)~='table'or personal.Name~=root then return false end
   return p.GetHero(owner)==hero and p.GetPlayerByHero(hero)==owner and hero.ObjectId==actor
    and ctx.GetCurrentHeroContext()==hero and api.MapState==map and map.EquippedWeapons==equipped
    and hero.Weapons[root]==true and equipped[root]==true
  end)
  return ok and confirmed==true
 end
end
return M
