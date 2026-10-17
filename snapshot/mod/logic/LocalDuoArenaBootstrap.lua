-- Duel mode removed at the user's request. No imports, hooks, portal or runtime.
local M={}
function M.Register()return false end
function M.ReadStatus()return {Registered=false,Enabled=false,Removed=true}end
return M
