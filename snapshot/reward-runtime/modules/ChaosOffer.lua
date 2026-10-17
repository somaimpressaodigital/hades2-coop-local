-- Exact free Chaos pair preparation. No RNG, payment, hooks or new expiration loop.
local M={}
local curses={ChaosHealthCurse=true,ChaosDamageCurse=true,ChaosPrimaryAttackCurse=true,
 ChaosSecondaryAttackCurse=true,ChaosSpeedCurse=true,ChaosExAttackCurse=true,ChaosCastCurse=true,
 ChaosDashCurse=true,ChaosManaFocusCurse=true}
local blessings={ChaosWeaponBlessing=true,ChaosSpecialBlessing=true,ChaosCastBlessing=true,
 ChaosHealthBlessing=true,ChaosManaBlessing=true,ChaosManaOverTimeBlessing=true,
 ChaosExSpeedBlessing=true,ChaosManaCostBlessing=true,ChaosSpeedBlessing=true,
 ChaosDoorHealBlessing=true,ChaosOmegaDamageBlessing=true}
function M.SourceAllowed(s)
 return type(s)=='table'and(s.Name=='TrialUpgrade'or s.Name=='ChaosUpgrade')and s.TransformingTraits==true
  and s.GodLoot==false and s.OnUsedFunctionName=='UseLoot'and not s.StackOnly and not s.UpgradeOnPick
  and not s.Cost and not s.AltCost and s.ResourceCosts==nil and not s.BoughtFromShop and not s.LocalDuoShopOwner
end
local function contains(t,name)for _,v in ipairs(t or{})do if v==name then return true end end;return false end
local function poolHas(s,r)
 for _,v in ipairs(s.UpgradeOptions or{})do
  if v.Type==r.Type and v.ItemName==r.ItemName and v.SecondaryItemName==r.SecondaryItemName
   and v.Rarity==r.Rarity and not v.Blocked then return true end
 end
 return false
end
local function rawAllowed(g,s,r)
 return M.SourceAllowed(s)and type(r)=='table'and r.Type=='TransformingTrait'and not r.Blocked
  and not r.TraitToReplace and not r.StackNum and type(r.ItemName)=='string'and type(r.SecondaryItemName)=='string'
  and g.TraitData[r.ItemName]~=nil and g.TraitData[r.SecondaryItemName]~=nil
  and contains(s.PermanentTraits,r.ItemName)and contains(s.TemporaryTraits,r.SecondaryItemName)and poolHas(s,r)
end
function M.ChoiceAllowed(g,hero,s,c)
 if not c or c.Blocked or c.ChaosPair~=true or not rawAllowed(g,s,c.Raw)then return false end
 local d,b=c.Data,c.BlessingData
 return type(d)=='table'and type(b)=='table'and c.ItemName==c.Raw.ItemName
  and d.Name==c.Raw.SecondaryItemName and b.Name==c.Raw.ItemName
  and c.Owner==s.LocalDuoOwner and (c.Owner==1 or c.Owner==2)
  and curses[d.Name]==true and blessings[b.Name]==true and not d.LocalDuoUnsupported and not b.LocalDuoUnsupported
  and d.UsesAsEncounters==true and not d.UsesAsRooms and type(d.RemainingUses)=='number'and d.RemainingUses>0
  and not d.HiddenRoomReward and not d.AddEnemyOnDeathProjectile and not d.DisableMetaUpgrades
  and type(d.OnExpire)=='table'and d.OnExpire.TraitData==b and (function()for k in pairs(d.OnExpire)do if k~='TraitData'then return false end end;return true end)()
end
function M.Prepare(g,processor,hero,raw,p,source)
 assert(rawAllowed(g,source,raw),'Exact current native Chaos pair required')
 assert(source.LocalDuoOwner==p and(p==1 or p==2),'Chaos pair owner mismatch')
 local blessing=assert(processor({Unit=hero,TraitName=raw.ItemName,Rarity=raw.Rarity},source))
 local curse=assert(processor({Unit=hero,TraitName=raw.SecondaryItemName,Rarity=raw.Rarity},source))
 assert(blessing.Name==raw.ItemName and curse.Name==raw.SecondaryItemName,'Chaos processing changed pair')
 local extraExpire=curse.OnExpire and next(curse.OnExpire)~=nil
 curse.OnExpire=curse.OnExpire or{};curse.OnExpire.TraitData=blessing
 curse.TraitTitle='ChaosCombo_'..curse.Name..'_'..blessing.Name
 g.SetTraitTextData(blessing);g.SetTraitTextData(curse)
 local tooltip=g.DeepCopyTable(blessing)
 for k,v in pairs(curse)do tooltip[k]=v end
 tooltip.Blessing=raw.ItemName;tooltip.Curse=raw.SecondaryItemName
 curse.ExtractData=curse.ExtractData or{}
 for _,v in pairs(g.GetExtractData(blessing)or{})do if v.ExtractAs then curse.ExtractData[v.ExtractAs]=blessing[v.ExtractAs]end end
 local choice={ItemName=raw.ItemName,Data=curse,BlessingData=blessing,TooltipData=tooltip,
  Raw=g.DeepCopyTable(raw),Owner=p,Rarity=raw.Rarity or'Common',Icon=blessing.Icon,
  Title=curse.TraitTitle,Description=curse.Name,Description2=blessing.Name,Frame=g.GetTraitFrame(curse),ChaosPair=true}
 if extraExpire or not M.ChoiceAllowed(g,hero,source,choice)then
  choice.Blocked=true;choice.UnsupportedReason=curse.LocalDuoUnsupportedReason or blessing.LocalDuoUnsupportedReason
   or'Esta combinação de Chaos ainda exige um efeito ou uma expiração não isolados por jogador.'
 end
 return choice
end
return M
