local Engine = CreateFrame("frame", "EFrame")

local function weakTable()
    local t = {}
    setmetatable(t, {__call = 'v'})
    return t
end

Engine:SetScript("OnUpdate", function ()
    this:update()
end)

function Engine:atomic(f, ...)
    local ret
    if not self.lock then
        self.lock = true
        ret = f(unpack(arg))
        self:process()
        self.lock = nil
    else
        ret = f(unpack(arg))
    end
    return ret
end

function Engine:process()
    local n = tremove(self.procced,1)
    Engine:disposeGarbage()
    while n do
        n()
        Engine:disposeGarbage()
        n = tremove(self.procced,1)
    end
end

Engine.collector = {}
Engine.garbage = weakTable()
Engine.objects = weakTable()

function Engine:stats()
    local t = {total = 0, garbage = 0}
    for _,o in self.objects do
        if not o.type then
            t.garbage = t.garbage +1
        else
            t[o.type] = (t[o.type] or 0) +1
            t.total = t.total +1
        end
    end
    return t
end

function Engine:addObject(o)
    tinsert(Engine.objects,o)
end

function Engine:addGarbage(o)
    tinsert(Engine.collector, o)
end

function Engine:disposeGarbage()
    local o = tremove(Engine.collector,1)
    while o do
        o:destroy()
        tinsert(Engine.garbage,o)
        o = tremove(Engine.collector,1)
    end
end

function Engine:makeAtomic(f)
    return function (...)
        return self:atomic(f, unpack(arg))
    end
end

function Engine.bind(f)
    return Bind:new(f)
end

function Engine:execute()
    if self.lock then return end
   Engine:process()
end

function Engine:enqueue(f)
    tinsert(self.procced, f)
end

Object = {type = "Object"}

Connection = {type = "Connection"}

Signal = {type = "Signal"}

Property = {type = "Property"}

Bind = {type = "Bind"}

local Connection_MT = {}
Connection_MT.__index = Connection

function Connection:new(o)
    setmetatable(o,Connection_MT)
    Engine:addObject(o)
    return o
end

function Connection:disconnect()
    self.signal:disconnect(self.id)
end

local Signal_MT = {}

function Signal_MT.__call(self, ...)
    local auto = self.parent and self.autoslot and self.parent[self.autoslot]
    if auto then
        auto(self.parent, unpack(arg))
    end
    if not self.n then return end
    for n=1,self.n do
        local c = self[n]
        if c then
            if type(c.target) == "function" then
                c.target(unpack(arg))
            else
                assert(type(c.target[c.slot]) == "function", format("Slot '%s' has invalid type '%s'. ",c.slot , type(c.target[c.slot])))
                if c.ququed then
                    Engine:enqueue(function() Engine:atomic(c.target[c.slot],c.target, unpack(arg)) end)
                else
                    c.target[c.slot](c.target, unpack(arg))
                end
            end
        end
    end
    Engine:execute()
end

Signal_MT.__index = Signal

function Signal:new(parent, name)
    local s = {n=0,parent = parent, autoslot = format("on%s%s",strupper(strsub(name,1,1)),strsub(name,2)or"")}
    Engine:addObject(s)
    setmetatable(s, Signal_MT)
    return s
end

function Signal:destroy()
    setmetatable(self,nil)
    for k in self do
        self[k] = nil
    end
end

function Signal:connect(target, slot)
    local t1, t2 = type(target), type(slot)
    assert(t1 == "table" and t2 == "string" or t1 == "function" and not slot, format("Cannot connect to types (<%s,%s>)",t1,t2))
    self.n = self.n +1
    local c = Connection:new{signal = self, target = target, slot = slot, id = self.n}
    self[self.n] = c
    if t1 == "table" then
        tinsert(target._connections,c)
    end
    return c
end

function Signal:disconnect(target, slot)
    if type(target) == "number" then
        self[target] = nil
    else
        for n=1,self.n do
            if self[n] and self[n].target == target and self[n].slot == slot then
                self[n] = nil
            end
        end
    end
end

function Signal:disconnectAll()
    for k in self do
        self[k] = nil
    end
end

Property_MT = {__index = Property}

function Property:new(parent, name, meta)
    local p = {}
    Engine:addObject(p)
    meta = meta or {}
    if meta.getter then
        p.get = meta.getter
    end
    if meta.setter then
        p.set = meta.setter
    end
    p.parent = parent
    p.signal = name.."Changed"
    setmetatable(p, Property_MT)
    return p
end

function Property:get()
    return self.value
end

local binding
function Property:_get(o, sn)
    if binding then
        local s = rawget(o or self.parent, sn or self.signal)
        if s then
            binding:bind(s)
        end
    end
    return self:get()
end

function Property:set(v)
    if v ~= self.value then
        self.value = v
        self.parent[self.signal](v)
    end
end

function Property:destroy()
    for k, v in self do
        self[k] = nil
    end
end

Object_MT = {}

local Bind_MT = {}

local function isBind(t)
    return getmetatable(t) == Bind_MT
end

Object_MT.__index = function (self, k)
    local p = rawget(self, '_'..k)
    local mt = getmetatable(p)
    if mt == Property_MT then
        return p:_get(self, k.."Changed")
    end
    return Object[k]
end


Object_MT.__newindex = function (self, k, v)
    local p = rawget(self, '_'..k)
    local mt = getmetatable(p)
    local old
    if mt ~= Property_MT then
        rawset(self, k, v)
        return
    end
    local oldbind = p.bind
    if oldbind and oldbind == v then
        return
    end
    if olbind then
        old = p:get()
        if not olbind and old == v then
            return
        end
    end
    if p.reset then
        p.reset:disconnect()
        p.reset = nil
    end
    local s = rawget(self,k.."Changed")
    if type(v) == "table" and v.type == "Property" then
        local bp = v
        v = Engine.bind(function() return bp:_get() end)
    end
    if isBind(v) then
        v.parent = p.parent
        v:update()
        v.valueChanged:connect(function(val) p:set(val) end)
        p.bind = v
        v = v.value
    else
        if type(v) == "table" and v.destroyed and v.destroyed.type == "Signal" then
  --          p.reset = v.destroyed:connect(function() p._value = nil s(nil) end)
        end
        p.bind = nil
    end
    p:set(v)
    if oldbind then
        oldbind:drop()
        oldbind:destroy()
    end
end

local function query(self, f, k)
    if type(f) == "table" then
        return f[k]
    else
        return f(self, k)
    end
end

local function IndexWrapper(b, s)
    local n = {}
    function n.__index(self, k)
        return query(self,s.__index,k) or query(self,b.__index,k)
    end
    return n
end

Object.IndexWrapper = IndexWrapper

function Object:new(meta, parent)
    local o = meta.object or {}
    Engine:addObject(o)
    o._connections = {}
    o._signals = weakTable()
    local oMT = getmetatable(o)
    if oMT and oMT.__index then
        oMT = IndexWrapper(oMT, Object_MT)
        oMT.__newindex = Object_MT.__newindex
    else
        oMT = Object_MT
    end
    setmetatable(o, oMT)
    for _,s in meta.signals or {} do
        o:attachSignal(s)
    end
    for _,s in meta.properties or {} do
        o['_'..s] = Property:new(o, s)
        o:attachSignal(s.."Changed")
    end
    o:attachSignal("destroyed")
    o:attach("children",nil, Property.ReadOnly)
    o:attach("parent", nil, "setParent")
    o.parent = parent
    o._children.value = {}
    return o
end
setmetatable(Object, {__call = Object.new})

function Object:deleteLater()
    Engine:addGarbage(self)
end


function Object:destroy()
    local t = self.type
    assert(not self._destroyed, "Attempt to destroy object twice.")
    self.destroyed(self)
    self.destroyed:disconnectAll()
    local c = tremove(self.children)
    while c do
        c:destroy()
        c = tremove(self.children)
    end
    self.parent:removeChild(self)
    for k,c in self._connections do
        c:disconnect()
        self._connections[k] = nil
    end
    for k, v in self._signals do
        v:disconnectAll()
    end
    self.parent = nil
    setmetatable(self, nil)
    for k, v in self do
        self[k] = nil
    end
    self._destroyed = true
    self._type = t
end

Property.ReadOnly = "READONLY"

function Object:attach(name, getter, setter)
    if setter == Property.ReadOnly then
        setter = function() error(format("cannot make assignment to readonly property %s."),name) end
    end
    local meta = {
        getter = getter and function ()
            return self[getter](self)
        end,
        setter = setter and function (_, v)
            self[setter](self,v)
        end
    }
    rawset(self, '_'..name, Property:new(self, name, meta))
    local s = Signal:new(self, name.."Changed")
    rawset(self, name.."Changed", s)
    self:registerSignal(s)
end

function Object:registerSignal(s)
    self._signals[tostring(s)] = s
end

function Object:attachSignal(n)
    local s = Signal:new(self, n)
    self:registerSignal(s)
    rawset(self, n, s)
end

function Object:setParent(parent)
    local oldparent = self.parent
    if oldparent then
        oldparent:removeChild(self)
    end
    self._parent.value = parent
    if parent then
        parent:addChild(self)
    end
    self.parentChanged(parent)
end

function Object:addChild(f)
    tinsert(self._children.value, f)
    self:childrenChanged(self.children)
end

function Object:removeChild(f)
    for k,c in self._children.value do
        if c == f then
            tremove(self._children.value, k)
            self:childrenChanged(self.children)
            return
        end
    end
end

Bind_MT = IndexWrapper(Object_MT, {__index=Bind})
Bind_MT.__newindex = Object_MT.__newindex

function Bind:new(f)
    local o = Object:new{properties={"value"}}
    local t = type(f)
    if t == "string" then
        f = loadstring(format("return function(self)return %s end", f))()
    end
    o._f = f
    o._cs = weakTable()
    setmetatable(o, Bind_MT)
    return o
end

function Bind:update()
    self:drop()
    local old = binding
    binding = self
    self.value = self._f(self.parent)
    binding = old
    return self.value
end

function Bind:bind(s)
    s:connect(self,"update")
end

function Bind:drop()
    for k,c in self._connections do
        c:disconnect()
        self._connections[k] = nil
    end
end

function Bind:destroy()
    self:drop()
    Object.destroy(self)
end

Engine.update = Signal:new(Engine, "update")
Engine.procced = {}
