local Input = { Error = nil }
Input.Native=LocalDuoPhysicalInput
if type(Input.Native)~="table" then Input.Error="Extensão de controles indisponível" end

function Input.Read(index)
    if not Input.Native then return {Connected=false,Error=Input.Error} end
    local raw=Input.Native.read(index)
    raw.Right=raw.Right or (raw.X or 0)>18000
    raw.Left=raw.Left or (raw.X or 0)<-18000
    raw.Down=raw.Down or (raw.Y or 0)>18000
    raw.Up=raw.Up or (raw.Y or 0)<-18000
    raw.Next=raw.Right or raw.Down or (raw.X or 0)>18000 or (raw.Y or 0)>18000
    raw.Previous=raw.Left or raw.Up or (raw.X or 0)<-18000 or (raw.Y or 0)<-18000
    return raw
end

return Input
