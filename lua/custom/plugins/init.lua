local M = {}

vim.keymap.set('v', '<', '<gv', { noremap = true, silent = true })
vim.keymap.set('v', '>', '>gv', { noremap = true, silent = true })

-- NOTE: begin latek
local vim = vim

local function counttable(t)
  --returns number of elements in table
  local count=0
  for _ in pairs(t) do
    count=count+1
  end
  return count
end

local random = math.random
math.randomseed(os.time())
local function uuid()
    local template ='xxxxxxxx-xxxx-4xxx-yxxx-xxxxxxxxxxxx'
    return string.gsub(template, '[xy]', function (c)
        local v = (c == 'x') and random(0, 0xf) or random(8, 0xb)
        return string.format('%x', v)
    end)
end


local function find_equations()
  --returns a list , every element of list is table {lno,cno} pair 
  local lines = vim.api.nvim_buf_get_lines(0,0,-1,false)
  local positions = {}
  -- read through all of them 
  for lno,line in pairs(lines) do
    local st = 1
    while true do
      local x,y=string.find(line,"$$",st,true)
      if x==nil then break end
      table.insert(positions,{lno,x})
      st=y+1
    end
  end
  if (counttable(positions)%2)~=0 then
    print("unmatched $$")
  end
  return positions
end

local function latex_topng(fnames,size)
  --renders the latex as png's  in /tmp
  local latexjobids = {}
  local dvijobids = {}
  for _,fname in pairs(fnames) do
    local jobid = vim.fn.jobstart("latex  --interaction=nonstopmode --output-dir=/tmp --output-format=dvi LATEXFILE" .. fname, {cwd="/tmp",on_stdout = function (_,_,_) print() end,on_stderr=function (_,_,_) print() end})
    table.insert(latexjobids,jobid)
  end
  vim.fn.jobwait(latexjobids)
  for _,fname in pairs(fnames) do
    local jobid = vim.fn.jobstart("dvipng -D "..tonumber(size).. " -T tight  -bg Transparent -fg 'cmyk 0.00 0.00 0.02 0.03'  -o /tmp/LATEXFILE"..fname..".png".." ".."/tmp/LATEXFILE"..fname..".dvi",{cwd="/tmp",on_stdout = function () print() end})
    table.insert(dvijobids,jobid)
  end
  vim.fn.jobwait(dvijobids)
end

local function get_lstrings(positions)
  --gets list os strings between positions 
  --positions is a list of pairs of lno,cno  (lineno , columno)
  local lstrings = {}
  for i=1,counttable(positions),2 do
    local lstring = ""
    local start = positions[i]
    local stop = positions[i+1]
    for _,v in pairs(vim.api.nvim_buf_get_text(0,start[1]-1,start[2]+1,stop[1]-1,stop[2]-1,{nil})) do
      lstring = lstring .. v
    end
    table.insert(lstrings,lstring)
  end
  return lstrings
end
local pre = "\\documentclass[12pt]{standalone}\n \\usepackage{amsmath}\n \\usepackage{amssymb} \n \\begin{document}\n \\begin{align} "
local post = "\\end{align} \n \\end{document}"

local function write_texfiles(lstrings)
  local fnames = {}
  for _,v in pairs(lstrings) do
    local fname = uuid()
    local filehandle = io.open("/tmp/LATEXFILE"..fname, "w")
    if filehandle then
        filehandle:write(pre..v.."\n"..post)
        filehandle:close()
        table.insert(fnames, fname)
    else
        print("Error: Unable to open file for writing")
    end
  end
  return fnames
end


local imgs = {}
local api = require("image")

local function insertpngs(eqpos, fnames, _)
  local findex = 1
  for i = 1, counttable(eqpos), 2 do
    local source = "/tmp/LATEXFILE" .. fnames[findex] .. ".png"
    local buf = vim.api.nvim_get_current_buf()
    local image = api.from_file(source, {
      id = "latex_image_" .. findex,
      window = vim.api.nvim_get_current_win(),
      buffer = buf,
      with_virtual_padding = true,
      -- inline = true,
      x = 0,
      y = eqpos[i+1][1],
      --width = 100,  -- adjust as needed
      height = 100  -- adjust as needed
    })
    table.insert(imgs, image)
    image:render()
    findex = findex + 1
  end
end

function RenderLatex(opts)
  RemoveLatex()
  local eqpos = find_equations()
  local lstrings = get_lstrings(eqpos)
  local fnames = write_texfiles(lstrings)
  latex_topng(fnames,opts.fargs[1])
  insertpngs(eqpos,fnames)
end

local function inbetween(curpos,pos1,pos2)
  --checks if curpos is b/w pos1 and pos2
  --assumes pos2 isafter pos1
  if pos1[1]==pos2[1] then
    --is pos1 and pos2 on same line, check column
    if curpos[1]==pos1[1] and pos1[2]<curpos[2] and curpos[2]<pos2[2]  then
      return true
    end
  elseif pos1[1]==curpos[1] and pos1[2] < curpos[2] then
    -- now that we established pos1 and pos2 are on diff lines
    -- if cur on line of pos1, check if cursor column after pos1 column
    return true
  elseif curpos[1]==pos2[1] and curpos[2] < pos2[2]  then
    -- if cur on line of pos2 check if pos2 is after cursor
    return true
  elseif pos1[1]<curpos[1] and curpos[1]<pos2[1] then
    --if curpos ,pos1 and pos2 on different lines, just check for lines
    return true
  end
  return false
end

local function findenclosing_eq(curpos,positions)
  --returns {pos1,pos2} if cursor is between some equation
  --else returns nil
  for i=1,counttable(positions),2 do
    if inbetween(curpos,positions[i],positions[i+1]) then
      return {positions[i],positions[i+1]}
    end
  end
  return nil
end

local function RenderLatexAtCursor(opts)
  -- RemoveLatex()
  local eqpos = find_equations()
  local curpos = vim.fn.getpos('.')
  curpos = {curpos[2],curpos[3]}
  local cureqpos = findenclosing_eq(curpos,eqpos)
  if cureqpos ~= nil then
    local lstrings = get_lstrings(cureqpos)
    local fnames = write_texfiles(lstrings)
    latex_topng(fnames,opts.fargs[1])
    insertpngs(cureqpos,fnames)
  else
    print("cursor not in equation")
  end
end

--function RenderLatex(opts)
--  local timer = vim.loop.new_timer()
--  timer:start(0,0,vim.schedule_wrap(renderlatex))
--end

function RemoveLatex()
  for _,img in pairs(imgs) do
    img:clear()
  end
  for k,_ in pairs(imgs) do
    imgs[k] = nil
  end
end

vim.api.nvim_create_user_command('RenderLatex', RenderLatex , {nargs=1, complete = function()
return {"200","300"} end })

vim.api.nvim_create_user_command('RenderLatexAtCursor', RenderLatexAtCursor , {nargs=1, complete = function(_,_,_)
return {"200","300"} end })

vim.api.nvim_create_user_command('RemoveLatex', RemoveLatex , {nargs=0})

-- NOTE: end latek
-- instructions: add a hotkey here for RenderLatexAsCursor which is leader and r
vim.keymap.set('n', '<leader>r', ':RenderLatexAtCursor 300<CR>', { noremap = true, silent = true })
vim.keymap.set('n', '<leader>R', ':RenderLatex 300<CR>', { noremap = true, silent = true })

local current_line = -1

vim.api.nvim_create_autocmd({"CursorMoved", "CursorMovedI"}, {
  callback = function()
    local new_line = vim.fn.line('.')
    if new_line ~= current_line then
      if current_line ~= -1 then
        -- RemoveLatex()
      end
      current_line = new_line
    end
  end
})


return M
