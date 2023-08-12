local Network={}

function Network:new(o)
  o=o or {}
  setmetatable(o,self)
  self.__index=self
  o:init()
  return o
end

function Network:init_dots()
  math.randomseed(params:get("seed"))
  local divs=self.divs or {1/4,1/4,1/8,1/8,1/8,1/16,1/16,1/16}
  local dens=self.dens or {0.5,0.75,0.25,0.5,0.75,0.25,0.5,0.75}
  self.nw={}
  for i=1,64 do
    local row=8-((i-1)%8)
    local col=math.floor((i-0.01)/8)+1
    -- generate random notework lattice
    self.rowcol_to_i[row][col]=i
    self.nw[i]={
      id=i,
      armed=false,
      er=er.random(math.random(8,32),dens[col]),
      pos=0,
      pan=math.random(-100,100)/200,
      amp=math.random(25,75)/100,
      -- div=global_divisions[math.random(#global_divisions)],
      div=divs[col],
      emitted=false,
      iterated=false,
      row=row,
      col=col,
    }
  end
end
function Network:init()
  self.playing=false
  self.emitted=false
  self.pos=1
  self.amp=0.5
  self.pos_hold=nil
  self.conn={}
  self.rowcol_to_i={}
  for i=1,8 do
    self.rowcol_to_i[i]={}
    for j=1,8 do
      self.rowcol_to_i[i][j]=1
    end
  end
  self:init_dots()
end

function Network:set_action(fn)
  self.fn=fn
end

function Network:change_amp(d)
  self.amp=util.clamp(self.amp+d,0,1)
end

function Network:emit(step,div)
  local to_emit={}
  for j,nw in ipairs(self.nw) do
    if nw.div*util.clamp(global_div_scales[params:get(instrument_list[self.id].."div_scale")],1/16,1)==div then
      self.nw[j].pos=(step%#nw.er)+1
      self.nw[j].iterated=nw.er[self.nw[j].pos]
      if not self.playing then
        goto continue
      end
      -- emit if either...
      -- ...it is connected TO something
      -- ...it is armed
      if nw.er[self.nw[j].pos] then
        local to=self:to(j)
        local into=self:into(j)
        -- only play if nothing connnected is armed
        local web=self:networked(j)
        local none_armed=true
        for _,k in ipairs(web) do
          if self.nw[k].armed then
            none_armed=false
          end
        end
        if ((none_armed and #into==0 and #to>0) or nw.armed) then
          table.insert(to_emit,j)
        else
          self.nw[j].emitted=false
        end
      else
        self.nw[j].emitted=false
      end
    end
    ::continue::
  end
  if #to_emit>0 then
    -- select one randomly to emit
    local j=to_emit[math.random(1,#to_emit)]
    -- emit the ones to emit
    for _,i in ipairs(to_emit) do
      if i==j then
        self.nw[j].emitted=true

        -- emit note
        if self.fn~=nil then
          self.fn(self.nw[j])
        end

        -- arm connected
        local to=self:to(j)
        for _,j2 in ipairs(to) do
          if not self.nw[j2].armed then
            self.nw[j2].armed=true
          end
        end

        -- disarm current
        self.nw[j].armed=false
      else
        self.nw[j].emitted=false
      end
    end
  end
end

function Network:toggle_play(playing)
  if playing~=nil then
    self.playing=playing
  else
    self.playing=(not self.playing)
  end
  if not self.playing then
    -- disarm everything
    for i,nw in ipairs(self.nw) do
      if nw.armed then
        self.nw[i].armed=false
      end
    end
  end
end

-- web generates the unique list of all connected nodes
function Network:networked(i)
  local r={}
  local rhave={}
  for _,v in ipairs(self.conn) do
    if (v[1]==i or v[2]==i) then
      for j=1,2 do
        if rhave[v[j]]==nil then
          table.insert(r,v[j])
          rhave[v[j]]=true
        end
      end
    end
  end
  for ii=1,7 do
    for _,k in ipairs(r) do
      for _,v in ipairs(self.conn) do
        if (v[1]==k or v[2]==k) then
          for j=1,2 do
            if rhave[v[j]]==nil then
              table.insert(r,v[j])
              rhave[v[j]]=true
            end
          end
        end
      end
    end
  end
  return r
end

function Network:current_nw()
  return self.nw[self.pos]
end

function Network:randomize(d)
  if d>0 then
    -- add random connection
    local i=math.random(1,64)
    local j=math.random(1,64)
    local k=0
    while (not self:is_connected_to(i,j)) and i==j do
      i=math.random(1,64)
      j=math.random(1,64)
      k=k+1
      if k>30 then
        print("error randomizing")
        do return end
      end
    end
    table.insert(self.conn,{i,j})
  elseif d<0 then
    -- remove last connection
    if #self.conn>0 then
      table.remove(self.conn,#self.conn)
    end
  end
end

function Network:connect(i,j)
  if i==nil and j==nil then
    if self.pos_hold==nil then
      self.pos_hold=self.pos
      do return end
    end
    i=self.pos_hold
    j=self.pos
  end
  if i==j then
    do return end
  end
  -- connect the first key to the second key
  -- if it isn't already connected
  if not self:is_connected_to(i,j) then
    table.insert(self.conn,{i,j})
  end
  self.pos_hold=nil
end

function Network:is_connected_to(i,j)
  for k,v in ipairs(self.conn) do
    if i==v[1] and j==v[2] then
      do return k end
    end
  end
end

function Network:clear()
  self.conn={}
end

function Network:disconnect(i,j)
  if i==nil then
    -- cancel
    if self.pos_hold~=nil then
      self.pos_hold=nil
      do return end
    end
    -- remove current connections
    print("disconnect from current pos: "..self.pos)
    local conn={}
    for i,v in ipairs(self.conn) do
      if v[1]~=self.pos and v[2]~=self.pos then
        table.insert(conn,v)
      end
    end
    self.conn=conn
    do return end
  end
  local ind=self:is_connected_to(i,j)
  if ind then
    table.remove(self.conn,ind)
  end
end

-- connections returns the indicies for self.conn
-- of any connection to/from node
function Network:connections(i)
  local conns={}
  for k,v in ipairs(self.conn) do
    if i==v[1] or i==v[2] then
      table.insert(conns,k)
    end
  end
  return conns
end

-- to lists all the nodes that come from node
function Network:to(i)
  local to={}
  for _,v in ipairs(self.conn) do
    if v[1]==i then
      table.insert(to,v[2])
    end
  end
  return to
end

function Network:into(i)
  local into={}
  for _,v in ipairs(self.conn) do
    if v[2]==i then
      table.insert(into,v[1])
    end
  end
  return into
end

function Network:change_pos(d)
  local pos=self.pos
  pos=pos+d
  if pos>=1 and pos<=64 then
    self.pos=pos
  end
end

function Network:change_row(d)
  local pos=self.pos
  pos=pos+d
  if math.floor((pos-0.01)/8)==math.floor((self.pos-0.01)/8) then
    self.pos=pos
  end
end

function Network:change_col(d)
  local pos=self.pos
  pos=pos+d*8
  if pos>=1 and pos<=64 then
    self.pos=pos
  end
end

function Network:coord(i)
  local spacing=7
  local tr={35,1}
  local x=self.nw[i].col*spacing+tr[1]
  local y=self.nw[i].row*spacing+tr[2]
  return x,y
end

function Network:draw_connection(i,j,lw)
  local x1,y1=self:coord(i)
  local x2,y2=self:coord(j)
  local d=distance_points(x1,y1,x2,y2)
  -- TODO: add a little lfo to the the point so they sway
  local p=perpendicular_points({x1,y1},{x2,y2},math.sqrt(d)*8)
  if lw==nil then
    lw=self.nw[j].armed and 2 or 1
  end
  screen.line_width(lw)
  screen.level(self.nw[j].armed and 15 or 7)
  screen.move(x1,y1)
  screen.curve((p[1]+x1)/2,(p[2]+y1)/2,(p[1]+x2)/2,(p[2]+y2)/2,x2,y2)
  screen.stroke()
end

function Network:draw()
  -- show the network topology
  -- using bezier curves
  -- where curving UP connects left to right
  -- and curving DOWN connects right to left
  local connected={}
  for i,nw in ipairs(self.nw) do
    local to=self:to(i)
    if to then
      for _,j in ipairs(to) do
        connected[i]=true
        connected[j]=true
        self:draw_connection(i,j)
      end
    end
  end
  if self.pos_hold~=nil then
    if self.pos_hold~=self.pos then
      self:draw_connection(self.pos_hold,self.pos,2)
    end
  end

  -- show the notework dots
  for i,nw in ipairs(self.nw) do
    local x,y=self:coord(i)
    -- erase the network topology directly around
    screen.level(0)
    screen.circle(x,y,self.pos==i and 5 or 2)
    screen.fill()

    -- draw a different sized dot
    screen.level(nw.iterated and 3 or 1)
    screen.circle(x,y,1.5)
    screen.stroke()
    if connected[i] then
      screen.circle(x,y,1.5)
      screen.fill()
    end
    screen.line_width(1)
    if nw.emitted then
      screen.level(15)
      screen.circle(x,y,2)
      screen.fill()
    end
    if self.pos==i then
      screen.level(self.pos_hold and 15 or 4)
      screen.circle(x,y,4)
      screen.stroke()
    end
  end

  if keydown[1] then
    local bank_id=params:get(instrument_list[global_page].."bank")
    local help={{"k3","link"},{"k2","unlink"},{"k1+e2","bank "..math.floor(bank_id)},{"k1+k2","load"}}
    local y=7
    for _,h in ipairs(help) do
      screen.level(15)
      screen.move(1,y)
      screen.text(h[1])
      y=y+7
      if h[1]=="k1+e2" then
        screen.level(bank[global_page][bank_id].saved and 15 or 2)
      else
        screen.level(15)
      end
      screen.move(5,y)
      screen.text(h[2])
      y=y+8
    end

    screen.move(128,15)
    screen.text_right("k1+e1:")
    screen.move(128,25)
    local db=params:get(instrument_list[self.id].."db")
    screen.text_right((db>0 and "+" or "")..db.." dB")

    screen.move(128,40)
    screen.text_right("k1+e3:")
    screen.move(128,50)
    screen.text_right("(cw) rand")
    screen.move(128,60)
    screen.text_right("(ccw) clear")
    screen.move(118,5)
    screen.text_right("k1+k3 (saves to bank):")
  end

  -- show if playing
  screen.level(15)
  screen.move(128,5)
  screen.text_right(self.playing and ">" or "||")
end

return Network
