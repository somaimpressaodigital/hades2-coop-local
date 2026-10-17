-- Optional legacy Host callbacks only. No generation, application, Native context, hooks or timers.
local M={}
local swordNames={AphroditeWeaponBoon=true,AphroditeSpecialBoon=true,HighHealthCritBoon=true,CritBonusBoon=true}
local function copy(t,seen)
 if type(t)~='table'then return t end;seen=seen or{};if seen[t]then return seen[t]end
 local out={};seen[t]=out;for k,v in pairs(t)do out[k]=copy(v,seen)end;return out
end
local function equal(a,b,seen)
 if type(a)~=type(b)then return false end;if type(a)~='table'then return a==b end
 seen=seen or{};if seen[a]==b then return true end;seen[a]=b
 for k,v in pairs(a)do if not equal(v,b[k],seen)then return false end end
 for k in pairs(b)do if a[k]==nil then return false end end;return true
end
function M.New(d)
 for _,key in ipairs({'isOriginalSword','GetOwner','GetHero'})do assert(type(d[key])=='function','actual dependency required: '..key)end
 assert(type(d.NativeMap)=='table'and type(d.SwordAdapter)=='table'and type(d.SwordAdapter.Prepare)=='function')
 local self={}
 local function scope(h)
  if type(h)~='table'or h.IsDead or not h.ObjectId then return nil,'Jogador indisponível.'end
  local actor=h.ObjectId;local owner=d.GetOwner(h)
  if(owner~=1 and owner~=2)or d.GetHero(owner)~=h or d.NativeMap[actor]~=h then return nil,'Referência do jogador mudou.'end
  local sword=d.isOriginalSword(h)
  if sword~=true and sword~=false then return nil,'Arma do jogador ainda não confirmada.'end
  if h.ObjectId~=actor or d.GetHero(owner)~=h or d.GetOwner(h)~=owner or d.NativeMap[actor]~=h then return nil,'Referência do jogador mudou.'end
  return owner,sword,actor
 end
 local function current(h,o,actor)return d.GetHero(o)==h and d.GetOwner(h)==o and h.ObjectId==actor and not h.IsDead and d.NativeMap[actor]==h end
 function self.prepareTrait(h,data)
  local owner,sword,actor=scope(h);if not owner then return nil,sword end
  if type(data)~='table'or type(data.Name)~='string'then return nil,'Dados da bênção indisponíveis.'end
  if not sword then return data end -- Native P1/Melinoe data retained exactly, no sword transformation.
  local prepared,why
  if swordNames[data.Name]then
   local ok,value=pcall(d.SwordAdapter.Prepare,data,owner)
   if ok then prepared=value else why='Esta versão da bênção precisa de adaptação para a espada.'end
  elseif data.Name=='ApolloManaBoon'then
   if type(d.NativeMana)=='table'and type(d.NativeMana.prepareTrait)=='function'and type(d.NativeMana.acceptTrait)=='function'then
    local ok,value,reason=pcall(d.NativeMana.prepareTrait,h,copy(data),owner)
    if ok then prepared,why=value,reason else why='Backend pessoal de mana indisponível.'end
   else why='Backend pessoal de mana ainda não conectado.'end
  else why='Bênção ainda não compatível com Zagreus.'end
  if not current(h,owner,actor)then return nil,'Referência do jogador mudou durante a preparação.'end
  return prepared,why
 end
 function self.acceptTrait(h,data)
  local owner,sword,actor=scope(h);if not owner then return false,sword end
  if type(data)~='table'or type(data.Name)~='string'then return false,'Dados da bênção indisponíveis.'end
  if data.LocalDuoUnsupported==true then return false,data.LocalDuoUnsupportedReason or'Opção indisponível.'end
  if not sword then return true end
  if swordNames[data.Name]then
   local ok,expected=pcall(d.SwordAdapter.Prepare,data,owner)
   local ready=ok and equal(expected,data)and current(h,owner,actor)
   return ready,ready and nil or'Bênção precisa da cópia pessoal preparada para a espada.'
  end
  if data.Name=='ApolloManaBoon'and type(d.NativeMana)=='table'and type(d.NativeMana.acceptTrait)=='function'then
   local ok,accepted,reason=pcall(d.NativeMana.acceptTrait,h,data,owner)
   return ok and accepted==true and current(h,owner,actor),reason or'Backend pessoal de mana não confirmou esta opção.'
  end
  return false,'Bênção ainda não compatível com Zagreus.'
 end
 function self.markChoiceUnsupported(h,choice,reason)
  local out={};for k,v in pairs(choice)do out[k]=v end -- keep Raw exact identity; never rewrite the source pool.
  out.Data=copy(choice.Data or{});out.Blocked=true;out.UnsupportedReason=reason or'Opção indisponível.'
  out.Data.LocalDuoUnsupported=true;out.Data.LocalDuoUnsupportedReason=out.UnsupportedReason
  return out
 end
 return self
end
return M
