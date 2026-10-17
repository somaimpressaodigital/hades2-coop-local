local Ally={}
function Ally.Apply(hero)
    if not hero or not hero.ObjectId then return end
    -- AutoLockable is the native unit property used by NPC/enemy definitions.
    -- Do not change Targetable, HomingEligible, immunity or enemy target choice.
    SetUnitProperty({DestinationId=hero.ObjectId,Property='AutoLockable',Value=false})
    SetUnitProperty({DestinationId=hero.ObjectId,Property='FriendlyToPlayer',Value=true})
    -- Scripted targeting often enumerates EnemyTeam rather than AutoLockable.
    -- Extra controlled actors must not remain in any enemy search group.
    AddToGroup({Id=hero.ObjectId,Name='HeroTeam'})
    RemoveFromGroup({Id=hero.ObjectId,Names={'EnemyTeam','GroundEnemies','FlyingEnemies'}})
end
return Ally
