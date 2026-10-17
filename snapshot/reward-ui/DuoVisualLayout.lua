-- Approximate text budget. No words/numbers are discarded; markup stays atomic.
local Layout={}
function Layout.Count(s)
 local n=0;for _ in tostring(s):gmatch('[%z\1-\127\194-\244][\128-\191]*')do n=n+1 end;return n
end
function Layout.Short(text,limit)
 local chars={};for c in tostring(text):gmatch('[%z\1-\127\194-\244][\128-\191]*')do chars[#chars+1]=c end
 if #chars<=limit then return text end
 local out={};for i=1,math.max(0,limit-3)do out[#out+1]=chars[i]end;return table.concat(out)..'...'
end
local function estimate(word,data)
 word=word:gsub('{%$TooltipData%.([%w_]+)}',function(k)
  local v=data and data[k];return(type(v)=='string' or type(v)=='number')and tostring(v)or string.rep('W',20)
 end):gsub('{#[^}]+}',''):gsub('{!Icons%.[^}]+}','WW'):gsub('{%$Keywords%.[^}]+}','')
 word=word:gsub('{%$[^}]+}',string.rep('W',20)):gsub('[%[%]]','')
 return Layout.Count(word)
end
function Layout.Pages(template,data,columns,lines)
 assert(type(template)=='string','Localized description template required')
 columns=columns or 44;lines=lines or 6
 local words={};local i=1;template=template:gsub('\\n','\n')
 while i<=#template do
  local c=template:sub(i,i)
  if c=='\n' then words[#words+1]='\n';i=i+1
  elseif c:match('%s')then i=i+1
  else
   local start=i
   while i<=#template and not template:sub(i,i):match('%s')do
    local ch=template:sub(i,i)
    if ch=='{'then i=(template:find('}',i,true)or #template)+1
    elseif ch=='['then i=(template:find(']',i,true)or #template)+1
    else i=i+1 end
   end
   words[#words+1]=template:sub(start,i-1)
  end
 end
 local pages,page,line,width,active={},{},'',0,{}
 local function flush()
  page[#page+1]=line;line='';width=0
  if #page>=lines then pages[#pages+1]=table.concat(page,' \\n ');page={};line=table.concat(active)end
 end
 for _,word in ipairs(words)do
  if word=='\n' then flush()
  else
   local w=estimate(word,data);if width>0 and width+1+w>columns then flush()end
   line=line..(width>0 and ' 'or '')..word;width=width+(width>0 and 1 or 0)+w
   for tag in word:gmatch('{#[^}]+}')do if tag=='{#Prev}'then table.remove(active)else active[#active+1]=tag end end
  end
 end
 if width>0 or #page>0 then page[#page+1]=line;pages[#pages+1]=table.concat(page,' \\n ')end
 if #pages==0 then pages[1]=''end;return pages
end
function Layout.Metadata(offer,source)
 local d=offer.Data or {};local n=d.StackNum or offer.Raw and offer.Raw.StackNum or 1
 if source.StackOnly then return 'nv. '..(d.OldLevel or math.max(1,n-(source.StackNum or 1)))..' / '..(d.NewLevel or n)end
 return(offer.Raw and offer.Raw.TraitToReplace and 'Troca - 'or '')..'nv. '..n
end
return Layout
