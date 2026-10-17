-- Passive checks. These inspect Lua state, never simulate input or mutate actors.
local Monitor={}
function Monitor.New() return {Previous=nil,Findings={},Seen={}} end
local function finding(state,code,message)
    if state.Seen[code] then return end
    state.Seen[code]=true
    state.Findings[#state.Findings+1]={Code=code,Message=message}
end
function Monitor.Observe(state,sample)
    local a,b=sample.Players[1],sample.Players[2]
    if a and b then
        if a.Id and a.Id==b.Id then finding(state,'same_actor','J1 e J2 ligados ao mesmo ator') end
        if a.Character and a.Character==b.Character and a.Character~='Melinoe' then finding(state,'same_character','Personagem exclusivo atribuido aos dois jogadores') end
        if not sample.Menu and a.Controller~=nil and a.Controller==b.Controller then
            finding(state,'same_controller','Mesmo controle configurado para os dois jogadores fora do menu')
        end
    end
    if (sample.RescuesUsed or 0)>2 then finding(state,'rescue_limit','Mais de dois resgates na corrida') end
    local old=state.Previous
    if old and old.Room==sample.Room and old.Protected and sample.Protected then
        for p=1,2 do
            local before,after=old.Players[p],sample.Players[p]
            if before and after and before.Id==after.Id and before.Health and after.Health
                and after.Health<before.Health then
                finding(state,'menu_damage_'..p,'J'..p..' perdeu vida durante preparacao protegida')
            end
        end
    end
    -- Copy observed primitives: references to live heroes would hide HP changes.
    local copy={Room=sample.Room,Protected=sample.Protected,Players={}}
    for p=1,2 do
        local hero=sample.Players[p]
        if hero then copy.Players[p]={Id=hero.Id,Health=hero.Health} end
    end
    state.Previous=copy
    return state.Findings
end
return Monitor
