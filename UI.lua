local _,_,resx, resy = strfind(({GetScreenResolutions()})[GetCurrentResolution()],"^(%d+)x(%d+)$")
EFrame.frameRecycler = {}
EFrame.objectRecycler = {}
local root = CreateFrame("frame","EFrame.root.frame")
function EFrame:recycle(f)
    if not f.owned then return end
    f:SetParent(nil)
    f:ClearAllPoints()
    local t = strlower(f:GetFrameType())
    self.frameRecycler[t] = self.frameRecycler[t] or {}
    tinsert(self.frameRecycler[t],f)
end
function EFrame:recycleObject(f)
 --   f:SetParent(nil)
    f:ClearAllPoints()
    local t = strlower(f:GetObjectType())
    self.objectRecycler[t] = self.objectRecycler[t] or {}
    tinsert(self.objectRecycler[t],f)
end

function EFrame:newFrame(t,parent)
    t = strlower(t)
    local f = tremove(self.frameRecycler[t] or {}) or CreateFrame(t)
    f:SetParent(parent)
    return f
end

function EFrame:newObject(t,p,m)
    t = strlower(t)
    local r = tremove(self.objectRecycler[t] or {})
    if not r then
        return p[m](p)
    end
    r:SetParent(p)
    return r
end

Item = {type = "Item"}
Item_MT = Object.IndexWrapper(Object_MT, {__index=Item})
Item_MT.__newindex = Object_MT.__newindex

local function colorComp(c1,c2)
    return not (c1 or c2) or c1 and c2 and c1[1] == c2[1] and c1[2] == c2[2] and c1[3] == c2[3] and c1[4] == c2[4]
end

function Item:new(parent, wrap, mode)
    parent = parent or EFrame.root
    assert(wrap == root or parent)
    local f = Object{properties={"_bottom","_right","_vcentre","_hcentre","marginLeft","marginTop","marginRight","marginBottom", "rotation", "implicitWidth", "implicitHeight"}}
    f.frame = wrap or EFrame:newFrame("frame")
    f.frame.owned = mode == nil or mode
    f:attach("width","getWidth","setWidth")
    f:attach("height","getHeight","setHeight")
    f:attach("visible", nil, "setVisible")
    f:attach("y","getY","setY")
    f:attach("x","getX","setX")
    f:attach("z","getZ","setZ")
    f.left = {frame = f, point = "x"}
    f.right = {frame = f, point = "_right"}
    f.top = {frame = f, point = "y"}
    f.bottom = {frame = f, point = "_bottom"}
    f.hcentre = {frame = f, point = "_hcentre"}
    f.vcentre = {frame = f, point = "_vcentre"}
    f:attach("anchorTop", nil, "setTopPoint")
    f:attach("anchorBottom", nil, "setBottomPoint")
    f:attach("anchorVCentre", nil, "setVCentrePoint")
    f:attach("anchorLeft", nil, "setLeftPoint")
    f:attach("anchorRight", nil, "setRightPoint")
    f:attach("anchorHCentre", nil, "setHCentrePoint")
    f:attach("anchorFill", nil, "setAllPoints")
    f:attach("margins", nil, "setAllMargins")
    f.update = EFrame.update
    setmetatable(f, Item_MT)
    f.parentChanged:connect(function (parent)
        if not parent then return end
        f.frame:SetParent(parent and parent.frame)
        f:updateVisible()
    end)
    f.parent = parent
    f.x = 0
    f.y = 0
    f.implicitWidth = 0
    f.implicitHeight = 0
    f.width = f._implicitWidth
    f.height = f._implicitHeight
    f._bottom = EFrame.bind("self.y + self.height")
    f._right = EFrame.bind("self.x + self.width")
    f._vcentre = EFrame.bind("self.y + self.height/2")
    f._hcentre = EFrame.bind("self.x + self.width/2")
    f.margins = 0
    f.visible = true
    return f
end
setmetatable(Item, {__call = Item.new})


function Item:destroy()
    self.frame:Hide()
    EFrame:recycle(self.frame)
    Object.destroy(self)
end

local function getLeft(f)
    return f:GetLeft() or 0
end
local function getTop(f)
    return f:GetTop() or 0
end

function Item:getX()
    local left = getLeft(self.frame)
    if not self.parent then return 0 end
    local p = self.parent.frame
    return p and left - getLeft(p) or left
end

function Item:setX(x)
    self.frame:SetPoint("LEFT", self.parent and self.parent.frame or self.frame ~= root and root or nil, "LEFT", x, 0)
    self.xChanged(x)
end

function Item:getY()
    local top = getTop(self.frame)
    if not self.parent then return 0 end
    local p = self.parent.frame
    return - (p and top - getTop(p) or top)
end

function Item:setY(y)
    self.frame:SetPoint("TOP", self.parent and self.parent.frame or self.frame ~= root and root or nil, "TOP", 0, -y)
    self.yChanged(y)
end

function Item:setZ(z)
    if self:getZ() == z then return end
    
    self.frame:SetFrameLevel(z)
    self.zChanged(z)
end

function Item:getZ()
    return self.frame:GetFrameLevel()
end

function Item:getWidth()
    return self.frame:GetWidth()
end

function Item:setWidth(w)
    if self:getWidth() == w then return end
    
    self.frame:SetWidth(w)
    self.widthChanged(w)
end

function Item:getHeight()
    return self.frame:GetHeight()
end

function Item:setHeight(h)
    if self:getHeight() == h then return end
    self.frame:SetHeight(h)
    self.heightChanged(h)
end

function Item:mapFrom(item, x, y)
    local p = self.parent.frame
    local ip = item.parent
    if not ip then
        return x - getLeft(p) + getLeft(item.frame), y - getTop(item.frame) + getTop(p)
    end
    return x - getLeft(p) + getLeft(ip.frame), y - getTop(ip.frame) + getTop(p)
end

local function anchorX(frame, anchor)
    return ({frame:mapFrom(anchor.frame, anchor.frame[anchor.point], 0)})[1]
end

local function anchorY(frame, anchor)
    return ({frame:mapFrom(anchor.frame, 0, anchor.frame[anchor.point])})[2]
end

function Item:setLeftPoint(anchor)
    self._anchorLeft.value = anchor
    if self.anchorFill then
        return
    end
    local right,hc = self.anchorRight, self.anchorHCentre
    if anchor then
        self.x = EFrame.bind(function() return anchorX(self, anchor) + self.marginLeft end)
        if right then
            self.width = EFrame.bind(function() return anchorX(self, right)  - self.marginRight - self.x end)
        elseif hc then
            self.width = EFrame.bind(function() return (anchorX(self,hc) - self.x)*2 end)
        end
    else
        self.x = self.x
        self.width = self.width
        if hc then
            self:setHCentrePoint(hc)
        elseif right then
            self:setRightPoint(right)
        end
    end
end

function Item:setRightPoint(anchor)
    self._anchorRight.value = anchor
    if self.anchorFill then
        return
    end
    local left,hc = self.anchorLeft, self.anchorHCentre
    if anchor then
        if left then
            self:setLeftPoint(left)
        elseif hc then
            self:setHCentrePoint(hc)
        else
            self.x = EFrame.bind(function() return anchorX(self, anchor) - self.marginRight - self.width end)
        end
    else
        self.x = self.x
        self.width = self.width
        if left then
            self:setLeftPoint(left)
        elseif hc then
            self:setHCentrePoint(hc)
        end
    end
end

function Item:setHCentrePoint(anchor)
    self._anchorHCentre.value = anchor
    if self.anchorFill then
        return
    end
    local left,right = self.anchorLeft, self.anchorRight
    if anchor then
        if left then
            self:setTopPoint(left)
        end
        self.x = EFrame.bind(function() return anchorX(self, anchor) - self.width/2 end)
        if right then
            self.width = EFrame.bind(function() return (anchorX(self, right) - self.marginRight - anchorX(self, anchor))*2 end)
        end
    else
        self.x = self.x
        self.width = self.width
        if left then
            self:setLeftPoint(left)
        elseif right then
            self:setBottomPoint(right)
        end
    end
end

function Item:setTopPoint(anchor)
    self._anchorTop.value = anchor
    if self.anchorFill then
        return
    end
    local bot,vc = self.anchorBottom, self.anchorVCentre
    if anchor then
        self.y = EFrame.bind(function() return anchorY(self, anchor) + self.marginTop end)
        if bot then
            self.height = EFrame.bind(function() return anchorY(self, bot) - self.y - self.marginBottom end)
        elseif vc then
            self.height = EFrame.bind(function() return (anchorY(self,vc) - self.y)*2 end)
        end
    else
        self.y = self.y
        self.height = self.height
        if vc then
            self:setVCentrePoint(vc)
        elseif bot then
            self:setBottomPoint(bot)
        end
    end
end

function Item:setBottomPoint(anchor)
    self._anchorBottom.value = anchor
    if self.anchorFill then
        return
    end
    local top,vc = self.anchorTop, self.anchorVCentre
    if anchor then
        if top then
            self:setTopPoint(top)
        elseif vc then
            self:setVCentrePoint(vc)
        else
            self.y = EFrame.bind(function() return anchorY(self, anchor) - self.marginBottom - self.height end)
        end
    else
        self.y = self.y
        self.height = self.height
        if top then
            self:setTopPoint(top)
        elseif vc then
            self:setVCentrePoint(vc)
        end
    end
end

function Item:setVCentrePoint(anchor)
    self._anchorVCentre.value = anchor
    if self.anchorFill then
        return
    end
    local top,bot = self.anchorTop, self.anchorBottom
    if anchor then
        if top then
            self:setTopPoint(top)
        end
        self.y = EFrame.bind(function() return anchorY(self, anchor) - self.marginBottom - self.height/2 end)
        if bot then
            self.height = EFrame.bind(function() return (anchorY(self, bot) - self.marginBottom - anchorY(self, anchor))*2 end)
        end
    else
        self.y = self.y
        self.height = self.height
        if top then
            self:setTopPoint(top)
        elseif bot then
            self:setBottomPoint(bot)
        end
    end
end

function Item:setAllPoints(frame)
    self._anchorFill.value = frame
    if frame then
        self.x = EFrame.bind(function() return anchorX(self, frame.left) + self.marginLeft end)
        self.y = EFrame.bind(function() return anchorY(self, frame.top) + self.marginTop end)
        self.width = EFrame.bind(function() return frame.width - self.marginRight - self.marginLeft end)
        self.height = EFrame.bind(function() return frame.height - self.marginTop - self.marginBottom end)
    else
        local top, vc, bot, left, hc, right = self.anchorTop, self.anchorVCentre, self.anchorBottom, self.anchorLeft, self.anchorHCentre, self.anchorRight
        if top then
            self:setTopPoint(top)
        elseif vc then
            self:setVCentrePoint(vc)
        elseif bot then
            self:setBottomPoint(bot)
        end
        if left then
            self:setLeftPoint(left)
        elseif hc then
            self:setHCentrePoint(hc)
        elseif right then
            self:setRightPoint(right)
        end
    end
end

function Item:setAllMargins(v)
    self.marginTop = v
    self.marginBottom = v
    self.marginLeft = v
    self.marginRight = v
end

function Item:setVisible(t)
    if t then
        self.frame:Show()
        self:_setVisible(self.frame:IsVisible() and true or false)
    else
        self.frame:Hide()
        self:_setVisible(false)
    end
end

function Item:_setVisible(v)
    if self._visible.value ~= v then
        self._visible.value = v
        for _,c in self.children do
            if c.updateVisible then
                c:updateVisible()
            end
        end
        self.visibleChanged(self._visible.value)
    end
end

function Item:updateVisible()
    local old = self._visible.value
    if self.parent and self.parent.visible then
        self:_setVisible(self.frame:IsShown() and true or false)
    else
        self:_setVisible(false)
    end
end

Rectangle = {type = "Rectangle"}
Rectangle_MT = Object.IndexWrapper(Item_MT, {__index=Rectangle})
Rectangle_MT.__newindex = Item_MT.__newindex

function Rectangle:new(parent)
    local o = Item(parent)
    o._texture = EFrame:newObject("texture",o.frame,"CreateTexture")
    o._texture:SetAllPoints()
    setmetatable(o, Rectangle_MT)
    o:attach("color", nil,"setColor")
    o:attach("borderColor", nil, "setBorderColor")
    o:attach("borderWidth", "getBorderWidth", "setBorderWidth")
    o:attach("layer", "getLayer", "setLayer")
    o.layer = "ARTWORK"
    o.color = {1,1,1}
    return o
end
setmetatable(Rectangle, {__call = Rectangle.new})

function Rectangle:destroy()
    EFrame:recycleObject(self._texture)
    if self._borderTop then
        EFrame:recycleObject(self._borderTop)
        EFrame:recycleObject(self._borderBottom)
        EFrame:recycleObject(self._borderRight)
        EFrame:recycleObject(self._borderLeft)
    end
    Item.destroy(self)
end

function Rectangle:_borderSetup()
    if not self._borderTop then
        self._borderTop = EFrame:newObject("texture", self.frame, "CreateTexture", self.layer)
        self._borderBottom = EFrame:newObject("texture", self.frame, "CreateTexture", self.layer)
        self._borderRight = EFrame:newObject("texture", self.frame, "CreateTexture", self.layer)
        self._borderLeft = EFrame:newObject("texture", self.frame, "CreateTexture", self.layer)
        
        self._borderTop:SetPoint("TOP", self.frame,"TOP")
        self._borderTop:SetPoint("LEFT", self.frame,"LEFT")
        self._borderTop:SetPoint("RIGHT", self.frame,"RIGHT")
        
        self._borderRight:SetPoint("RIGHT", self.frame,"RIGHT")
        self._borderRight:SetPoint("TOP", self._borderTop,"BOTTOM")
        self._borderRight:SetPoint("BOTTOM", self._borderBottom,"TOP")
        
        self._borderBottom:SetPoint("BOTTOM", self.frame,"BOTTOM")
        self._borderBottom:SetPoint("LEFT", self.frame,"LEFT")
        self._borderBottom:SetPoint("RIGHT", self.frame,"RIGHT")
        
        self._borderLeft:SetPoint("LEFT", self.frame,"LEFT")
        self._borderLeft:SetPoint("TOP", self._borderTop,"BOTTOM")
        self._borderLeft:SetPoint("BOTTOM", self._borderBottom,"TOP")
    end
end

function Rectangle:setColor(color)
    if colorComp(self._color.value, color) then
        return
    end
    self._color.value = color
    self._texture:SetTexture(unpack(color))
    self.colorChanged(color)
end

function Rectangle:setBorderColor(color)
    if colorComp(self._borderColor.value, color) then
        return
    end
    self:_borderSetup()
    self._borderColor.value = color
    self._borderTop:SetTexture(unpack(color))
    self._borderRight:SetTexture(unpack(color))
    self._borderBottom:SetTexture(unpack(color))
    self._borderLeft:SetTexture(unpack(color))
    self.borderColorChanged(color)
end

function Rectangle:getBorderWidth()
    return self._borderTop:IsVisible() and self._borderTop:GetHeight() or 0
end

function Rectangle:setBorderWidth(width)
    self:_borderSetup()
    self._texture:ClearAllPoints()
    if width == 0 then
        self._borderTop:Hide()
        self._borderBottom:Hide()
        self._borderRight:Hide()
        self._borderLeft:Hide()
        self._texture:SetAllPoints()
    else
        self._borderTop:SetHeight(width)
        self._borderBottom:SetHeight(width)
        self._borderRight:SetWidth(width)
        self._borderLeft:SetWidth(width)
        self._borderTop:Show()
        self._borderBottom:Show()
        self._borderRight:Show()
        self._borderLeft:Show()
        self._texture:SetPoint("TOP", self._borderTop, "BOTTOM")
        self._texture:SetPoint("RIGHT", self._borderRight, "LEFT")
        self._texture:SetPoint("BOTTOM", self._borderBottom, "TOP")
        self._texture:SetPoint("LEFT", self._borderLeft, "RIGHT")
    end
end


function Rectangle:getLayer()
    return self._texture:GetDrawLayer()
end

function Rectangle:setLayer(l)
    if self.layer == strupper(l) then
        return
    end
    self._texture:SetDrawLayer(l)
    if self._borderTop then
        self._borderTop:SetDrawLayer(self.layer)
        self._borderBottom:SetDrawLayer(self.layer)
        self._borderRight:SetDrawLayer(self.layer)
        self._borderLeft:SetDrawLayer(self.layer)
    end
    self.layerChanged(l)
end

Image = {type = "Image"}
Image_MT = Object.IndexWrapper(Item_MT, {__index=Image})
Image_MT.__newindex = Item_MT.__newindex

function Image:new(parent)
    local o = Item(parent)
    o._texture = EFrame:newObject("texture",o.frame,"CreateTexture")
    o._texture:SetAllPoints()
    setmetatable(o, Image_MT)
    o:attach("source", "getSource","setSource")
    o:attach("color", nil, "setColor")
    o:attach("layer", "getLayer", "setLayer")
    o.layer = "ARTWORK"
    return o
end
setmetatable(Image, {__call = Image.new})

function Image:destroy()
    self._texture:SetTexture(nil)
    self._texture:SetVertexColor(1,1,1)
    EFrame:recycleObject(self._texture)
    Item.destroy(self)
end

function Image:getSource()
    return self._texture:GetTexture()
end

function Image:setSource(src)
    if src == self.source then
        return
    end
    
    self._texture:SetTexture(src)
    self.sourceChanged(src)
end

function Image:setColor(color)
    if colorComp(self._color.value, color) then
        return
    end
    self._color.value = color
    self._texture:SetVertexColor(unpack(color))
    self.colorChanged(color)
end

function Image:getLayer()
    return self._texture:GetDrawLayer()
end

function Image:setLayer(l)
    if self.layer == strupper(l) then
        return
    end
    self._texture:SetDrawLayer(l)
    self.layerChanged(l)
end

Label = {type = "Label"}
Label_MT = Object.IndexWrapper(Item_MT, {__index=Label})
Label_MT.__newindex = Item_MT.__newindex

function Label:new(parent)
    local o = Item(parent)
    o.n_text = EFrame:newObject("fontstring",o.frame,"CreateFontString")
    o.n_text:SetFontObject("GameFontNormal")
    o.n_text:SetAllPoints()
    setmetatable(o, Label_MT)
    
    o:attach("text","getText","setText")
    o:attach("color",nil,"setColor")
    o:attach("shadowColor","getShadowColor","setShadowColor")
    o:attach("shadowOffset","getShadowOffset","setShadowOffset")
    o:attach("outline","getOutline","setOutline")
    o:attach("justifyH","getJustifyH","setJustifyH")
    o:attach("justifyV","getJustifyV","setJustifyV")
    o:attach("contentWidth","getContentWidth",Property.ReadOnly)
    o:attach("contentHeight","getContentHeight",Property.ReadOnly)
    o.implicitWidth = o._contentWidth
    o.implicitHeight = o._contentHeight
    o.text = ""
    o.visibleChanged:connect(o, "refreshContentSize")
    return o
end
setmetatable(Label, {__call = Label.new})

function Label:destroy()
    EFrame:recycleObject(self.n_text)
    Item.destroy(self)
end

function Label:getText()
    return self.n_text:GetText()
end

function Label:setText(t)
    if self:getText() == t then return end
    
    self.n_text:SetText(t)
    self.textChanged(t)
    self.contentWidthChanged(self.contentWidth)
    self.contentHeightChanged(self.contentHeight)
end

function Label:setColor(color)
    if colorComp(self._color.value, color) then
        return
    end
    self._color.value = color
    self.n_text:SetTextColor(unpack(color))
    self.colorChanged(color)
end

function Label:getShadowColor()
    return {self.n_text:GetShadowColor()}
end
    
function Label:setShadowColor(c)
    c = c or {}
    local old = self:getShadowColor()
    if colorComp(old, c) then return end
    self.n_text:SetShadowColor(unpack(c))
    self.shadowColorChanged(c)
end

function Label:getContentWidth()
    local v = self.n_text:GetWidth()
    if v ~= self._contentWidth.value then
        self._contentWidth.value = v
        self.contentWidthChanged(v)
    end
    return v
end

function Label:getContentHeight()
    local v = self.n_text:GetHeight()
    if v ~= self._contentHeight.value then
        self._contentHeight.value = v
        self.contentHeightChanged(v)
    end
    return v
end

function Label:refreshContentSize()
    self:getContentWidth() self:getContentHeight()
end

MouseArea = {type = "MouseArea"}

MouseArea_MT = Object.IndexWrapper(Item_MT, {__index=MouseArea})
MouseArea_MT.__newindex = Item_MT.__newindex

function MouseArea:new(parent)
    local o = Item(parent, EFrame:newFrame("Button"))
    o:attach("pressed")
    o:attach("dragTarget", nil, "setDragTarget")
    o:attach("dragActive")
    o:attach("enabled", "getEnabled", "setEnabled")
    o:attach("containsMouse")
    o:attach("hoover")
    o:attach("containsPress")
    o:attachSignal("clicked")
    o.frame:RegisterForClicks("LeftButtonDown","LeftButtonUp")
    o.frame:SetScript("OnMouseUp", function ()
        if not o.containsPress then
            o.pressed = false
        end
    end)
    o.frame:SetScript("OnClick", function ()
        if o.frame:GetButtonState() == "NORMAL" then
            o.pressed = true
        else
            if o.containsPress then
                o.clicked(arg1)
            end
            o.pressed = false
        end
    end)
    local ox, oy
    o.frame:SetScript("OnDragStart", function ()
        local x, y = GetCursorPosition()
        ox = x / o.frame:GetEffectiveScale()
        oy = - y / o.frame:GetEffectiveScale()
        o.dragActive = true
    end)
    o.frame:SetScript("OnDragStop", function ()
        ox = nil
        oy = nil
        o.dragActive = false
    end)
    o.frame:SetScript("OnUpdate", function ()
        if o.dragActive then
            local x, y = GetCursorPosition()
            x = x / o.frame:GetEffectiveScale()
            y = - y / o.frame:GetEffectiveScale()
            o.dragTarget.x = o.dragTarget.x + x - ox
            o.dragTarget.y = o.dragTarget.y + y - oy
            ox = x
            oy = y
        end
        if o.pressed or o.hoover then
            o.containsMouse = MouseIsOver(o.frame) and true or false
        end
    end)
    setmetatable(o, MouseArea_MT)
    o.enabled = true
    o.hoover = false
    o.dragActive = false
    o.pressed = false
    o.containsPress = EFrame.bind(function() return o.pressed and o.containsMouse end)
    return o
end
setmetatable(MouseArea, {__call = MouseArea.new})

function MouseArea:destroy()
    self.frame:SetScript("OnClick",nil)
    self.frame:SetScript("OnMouseUp",nil)
    self.frame:SetScript("OnUpdate",nil)
    self.frame:SetScript("OnDragStart",nil)
    self.frame:SetScript("OnDragStop",nil)
    self.frame:Disable()
    self.frame:RegisterForDrag()
    Item.destroy(self)
end

function MouseArea:setDragTarget(target)
    if self.dragTarget == target then return end
    
    if not self.dragTarget then
        self.frame:RegisterForDrag("LeftButton")
    elseif not target then
        self.frame:RegisterForDrag()
    end
    self._dragTarget.value = target
    self.dragTargetChanged(target)
end

function MouseArea:getEnabled()
    return self.frame:IsEnabled() == 1
end

function MouseArea:setEnabled(e)
    if e == self.enabled then return end
    if e then
        self.frame:Enable()
    else
        self.frame:Disable()
    end
    self.enabledChanged(e)
end

Button = {type = "Button"}

Button_MT = Object.IndexWrapper(MouseArea_MT, {__index=Button})
Button_MT.__newindex = MouseArea_MT.__newindex

function Button:new(parent)
    local o = MouseArea(parent)
    o:attach("background",nil, "setBackground")
    o:attach("checkable")
    o:attach("checked")
    o:attach("exclusiveGroup")
    o:attach("flat")
    o.flat = false
    o.textLabel = Label(o)
    o._text = o.textLabel._text
    setmetatable(o, Button_MT)
    o.background = Rectangle(o)
    o.background.layer = "background"
    o.image = Image(o)
    o.image.layer = "artwork"
    o.background.color = EFrame.bind(function () return not o.enabled and ((o.containsPress or o.checkedChanged) and {0.5,0.75,0.5} or {.1,.25,.1}) or o.flat and {0,0,0,0} or (o.containsPress or o.checked) and {0,.25,0} or {0,0.75,0} end)
    o.textLabel.anchorFill = o
    o.textLabel.marginLeft = 2
    o.textLabel.marginRight = 2
    o.textLabel.marginBottom = 3
    o.implicitWidth = EFrame.bind(function() return o.textLabel.contentWidth + o.textLabel.marginLeft + o.textLabel.marginRight end)
    o.implicitHeight = EFrame.bind(function() return o.textLabel.contentHeight + o.textLabel.marginBottom + o.textLabel.marginTop end)
    o.image.anchorFill = o
    o.image.color = EFrame.bind(function () return o.flat and (o.checked or o.containsPress) and {0,.25,0} or {0,1,0} end)
    o._icon = o.image._source
    o.clicked:connect(function ()
        if o.checkable then
            o.checked = not o.checked
        end
    end)
    o.checkableChanged:connect(function (c)
        if not c then
            o.checked = false
        end
    end)
    o.exclusiveGroupChanged:connect(function (ex)
        if ex then
            ex:bind(o)
        end
    end)
    o.checkedChanged:connect(function (c)
        local ex = o.exclusiveGroup
        if c and ex then
            ex.current = o
        end
    end)
    return o
end
setmetatable(Button, {__call = Button.new})

function Button:setBackground(f)
    if self.background == f then
        return
    end
    self._background.value = f
    if f then
        f.anchorFill = self
    end
    self.backgroundChanged(f)
end

ExclusiveGroup = {type = "ExclusiveGroup"}

ExclusiveGroup_MT = Object.IndexWrapper(Object_MT, {__index=ExclusiveGroup})
ExclusiveGroup_MT.__newindex = Object_MT.__newindex

function ExclusiveGroup:new(parent)
    local o = Object({properties = {"current"}}, parent)
    o.currentChanged:connect(function (o)
        if o then
            o.checked = true
        end
    end)
    setmetatable(o, ExclusiveGroup_MT)
    return o
end
setmetatable(ExclusiveGroup, {__call = ExclusiveGroup.new})

function ExclusiveGroup:bind(o)
    o.checkedChanged:connect(function (c)
        if c then self.current = o end
    end)
end

function ExclusiveGroup:destroy()
    Object.destroy(self)
end

CheckButton = {type = "CheckButton"}

CheckButton_MT = Object.IndexWrapper(MouseArea_MT, {__index=CheckButton})
CheckButton_MT.__newindex = MouseArea_MT.__newindex

function CheckButton:new(parent)
    local o = MouseArea(parent)
    o:attach("checked")
    o:attach("exclusiveGroup")
    o.square = Rectangle(o)
    o.square.color = {0,1,0,0.25}
    o.square.borderWidth = 2
    o.square.borderColor = {0,1,0}
    o.square.anchorVCentre = o.vcentre
    o.tick = Rectangle(o.square)
    o.tick.anchorFill = o.square
    o.tick.margins = 4
    setmetatable(o, CheckButton_MT)
    o.label = Label(o)
    o.label.anchorLeft = o.square.right
    o.label.anchorVCentre = o.vcentre
    o.label.marginLeft = 2
    o._text = o.label._text
    o.checked = false
    o.square.implicitHeight = o.label._height
    o.square.implicitWidth = o.square._height
    o.implicitWidth = EFrame.bind(function() return o.square.width + o.label.width + o.label.marginLeft end)
    o.implicitHeight = EFrame.bind(function() return max(o.square.height, o.label.height) end)
    o.tick.color = EFrame.bind(function() return o.containsPress and {0.25,.75,0.25} or o.checked and {0,1,0} or {0,0,0,0} end)
    o.clicked:connect(function ()
        o.checked = not o.checked
    end)
    local a =EFrame.bind(function ()
        local ex = o.exclusiveGroup
        if ex then
            o.checked = ex.current == o
        end
    end)
    a.parent = o
    a:update()
    o.checkedChanged:connect(function (c)
        local ex = o.exclusiveGroup
        if c and ex then
            ex.current = o
        end
    end)
    return o
end
setmetatable(CheckButton, {__call = CheckButton.new})

RadioButton = {type = "RadioButton"}

RadioButton_MT = Object.IndexWrapper(MouseArea_MT, {__index=RadioButton})
RadioButton_MT.__newindex = MouseArea_MT.__newindex

function RadioButton:new(parent)
    local o = MouseArea(parent)
    o:attach("checked")
    o:attach("exclusiveGroup")
    o.square = Rectangle(o)
    o.square.color = {0,1,0,0.25}
    o.square.borderWidth = 2
    o.square.borderColor = {0,1,0}
    o.square.anchorVCentre = o.vcentre
    o.tick = Rectangle(o.square)
    o.tick.anchorFill = o.square
    o.tick.margins = 4
    setmetatable(o, RadioButton_MT)
    o.label = Label(o)
    o.label.anchorLeft = o.square.right
    o.label.anchorVCentre = o.vcentre
    o.label.marginLeft = 2
    o._text = o.label._text
    o.checked = false
    o.square.implicitHeight = EFrame.bind(function() return o.label.height end)
    o.square.implicitWidth = EFrame.bind(function() return o.square.height end)
    o.implicitWidth = EFrame.bind(function() return o.square.width + o.label.width + o.label.marginLeft end)
    o.implicitHeight = EFrame.bind(function() return max(o.square.height, o.label.height) end)
    o.tick.color = EFrame.bind(function() return o.containsPress and {0.25,.75,0.25} or o.checked and {0,1,0} or {0,0,0,0} end)
    o.clicked:connect(function ()
        o.checked = true
    end)
    local a = EFrame.bind(function ()
        local ex = o.exclusiveGroup
        if ex then
            o.checked = ex.current == o
        end
    end)
    a.parent = o
    a:update()
    o.checkedChanged:connect(function (c)
        local ex = o.exclusiveGroup
        if c and ex then
            ex.current = o
        end
    end)
    return o
end
setmetatable(RadioButton, {__call = RadioButton.new})

TextArea = {type = "TextArea"}

TextArea_MT = Object.IndexWrapper(Item_MT, {__index=TextArea})
TextArea_MT.__newindex = Item_MT.__newindex

function TextArea:new(parent)
    local o = Item(parent, EFrame:newFrame("ScrollFrame"))
    o.n_text = EFrame:newFrame("EditBox",o.frame)
    o.frame:SetScrollChild(o.n_text)
    o.n_text:SetAllPoints(o.frame)
    o.n_text:SetFontObject("ChatFontNormal")
    o.n_text:SetMultiLine(1)
    o.n_text:SetAutoFocus(false)
    setmetatable(o, TextArea_MT)
    o:attach("text","getText","setText")
    o:attach("focus", nil, "setFocus")
    o:attach("color",nil,"setColor")
    o:attach("shadowColor","getShadowColor","setShadowColor")
    o:attach("shadowOffset","getShadowOffset","setShadowOffset")
    o:attach("outline","getOutline","setOutline")
    o:attach("justifyH","getJustifyH","setJustifyH")
    o:attach("justifyV","getJustifyV","setJustifyV")
    o.text = ""
    o._focus.value = true
    o.n_text:SetScript("OnTextChanged", function() o.textChanged(o.text) end)
    o.n_text:SetScript("OnEditFocusGained", function() o.focus = true end)
    o.n_text:SetScript("OnEditFocusLost", function() o.focus = false end)
    return o
end
setmetatable(TextArea, {__call = TextArea.new})

function TextArea:getText()
    return self.n_text:GetText()
end

function TextArea:setText(t)
    if t == self.text then return end
    self.n_text:SetText(t)
    self.textChanged(t)
end

function TextArea:setFocus(f)
    if self.focus == f then return end
    self._focus.value = f
    if f then
        self.n_text:SetFocus()
    else
        self.n_text:ClearFocus()
    end
    self.focusChanged(f)
end

function TextArea:setColor(color)
    if colorComp(self._color.value, color) then
        return
    end
    self._color.value = color
    self.n_text:SetTextColor(unpack(color))
    self.colorChanged(color)
end

function TextArea:getShadowColor()
    return {self.n_text:GetShadowColor()}
end
    
function TextArea:setShadowColor(c)
    c = c or {}
    local old = self:getShadowColor()
    if colorComp(old, c) then return end
    self.n_text:SetShadowColor(unpack(c))
    self.shadowColorChanged(c)
end

function TextArea:getContentWidth()
    local v = self.n_text:GetWidth()
    if v ~= self._contentWidth.value then
        self._contentWidth.value = v
        self.contentWidthChanged(v)
    end
    return v
end

function TextArea:selectText(p0, p1)
    self.n_text:HighlightText(p0,p1)
end

Window = {type = "Window"}

Window_MT = Object.IndexWrapper(MouseArea_MT, {__index=Window})
Window_MT.__newindex = MouseArea_MT.__newindex

function Window:new(parent)
    local o = MouseArea(parent)
    o.dragTarget = o
    setmetatable(o, Window_MT)
    o.decoration = Rectangle(o)
    o.titleLabel = Label(o.decoration)
    o.decoration.anchorTop = o.top
    o.decoration.anchorLeft = o.left
    o.decoration.anchorRight = o.right
    o.decoration.color = {0,1,0,0.5}
    o.closeButton = Button(o.decoration)
    o.closeButton.flat = true
    o.closeButton.anchorTop = o.decoration.top
    o.closeButton.anchorBottom = o.decoration.bottom
    o.closeButton.anchorRight = o.decoration.right
    o.closeButton.width = EFrame.bind(function() return o.closeButton.height end)
    o.closeButton.margins = 2
    o.closeButton.icon = "Interface\\Addons\\EmeraldFramework\\Textures\\CloseButton"
    o.closeButton.clicked:connect(function() o.visible = false end)
    o.minimizeButton = Button(o.decoration)
    o.minimizeButton.flat = true
    o.minimizeButton.anchorTop = o.decoration.top
    o.minimizeButton.anchorBottom = o.decoration.bottom
    o.minimizeButton.anchorRight = o.closeButton.left
    o.minimizeButton.width = EFrame.bind(function() return o.closeButton.height end)
    o.minimizeButton.margins = 2
    o.minimizeButton.checkable = true
    o.minimizeButton.icon = "Interface\\Addons\\EmeraldFramework\\Textures\\MinimizeButton"
    o.minimizeButton.checkedChanged:connect(function(c) o.centralItem.visible = not c end)
    o.decoration.height = EFrame.bind(function() return max(20, o.titleLabel.contentHeight) end)
    o.decoration.implicitWidth = EFrame.bind(function() return o.titleLabel.contentWidth + o.decoration.height * 2 + 6 end)
    o.titleLabel.anchorFill = o.decoration
    o.titleLabel.margins = 3
    o.titleLabel.marginRight = EFrame.bind(function() return o.decoration.height*2 +3 end)
    o:attach("background",nil, "setBackground")
    o.background = Rectangle(o)
    o._title = o.titleLabel._text
    o.textChanged = o.titleLabel._textChanged
    o:attach("centralItem", nil, "setCentralItem")
    o.visibleChanged:connect(function (v)
        if v then
            o.minimizeButton.checked = false
            o.x = o.parent.width/2 - o.width/2
            o.y = o.parent.height/2 - o.height/2
        end
    end)
    
    o.background.borderColor = {0,1,0,0.5}
    o.background.color = {0,1,0,0.25}
    o.background.borderWidth = 2
    o.background.visible = EFrame.bind(function() return o.centralItem and o.centralItem.visible or false end)
    
    return o
end
setmetatable(Window,{__call = Window.new})

function Window:setBackground(f)
    if self.background == f then
        return
    end
    self._background.value = f
    if f then
        f.anchorFill = self
        f.marginTop = EFrame.bind(function() return self.decoration.height end)
    end
    self.backgroundChanged(f)
end

function Window:setCentralItem(f)
    if f == self.centralItem then return end
    
    if f then
        self.implicitWidth = EFrame.bind(function() return max(self.decoration.implicitWidth, f.width + f.marginLeft + f.marginRight) end)
        self.implicitHeight = EFrame.bind(function() return f.height + f.marginTop + f.marginBottom + self.decoration.height end)
        f.anchorTop = self.decoration.bottom
        f.anchorLeft = self.left
        f.margins = 4
    end
    self._centralItem.value = f
    self.centralItemChanged(f)
end

Layout = {type = "Layout"}
Layout_MT = Object.IndexWrapper(Item_MT, {__index=Layout})
Layout_MT.__newindex = Item_MT.__newindex

function Layout:new(parent)
    local o = Item(parent)
    return o
end
setmetatable(Layout, {__call = Layout.new})


GridLayout = {type = "GridLayout"}
GridLayout_MT = Object.IndexWrapper(Item_MT, {__index=GridLayout})
GridLayout_MT.__newindex = Item_MT.__newindex

function GridLayout:new(nr, nc, parent)
    nr, nc = nr or 0, nc or 0
    local o = Layout(parent)
    o:attach("rows")
    o:attach("columns")
    o:attach("rowSpacing")
    o:attach("columnSpacing")
    setmetatable(o, GridLayout_MT)
    o.rows = nr
    o.columns = nc
    o.rowSpacing = 0
    o.columnSpacing = 0
    local a = EFrame.bind(function() o:refreshLayout() end)
    a.parent = o
    a:update()
    return o
end
setmetatable(GridLayout, {__call = GridLayout.new})

function GridLayout:refreshLayout()
--     local cc, r, c = self.children, self.rows, self.columns
--     local rs, cs = self.rowSpacing, self.columnSpacing
--     if getn(cc) == 0 then return end
--     local cy = 0
--     for i = 0, r-1 do
--         local max = 0
--         for j = 0, c-1 do
--             local f = cc[j + c*i +1]
--             if f then
--                 local ih = f.height
--                 if ih > max then
--                     max = ih
--                 end
--             end
--         end
--         for j = 0, c -1 do
--             local f = cc[j + c*i +1]
--             if f then
--                 f.y = cy
--             end
--         end
--         cy = cy + rs + max
--     end
--     local cx = 0
--     for i = 0, c -1 do
--         local max = 0
--         for j = 0, r -1 do
--             local f = cc[i + c*j +1]
--             if f then
--                 local iw = f.width
--                 if iw > max then
--                     max = iw
--                 end
--             end
--         end
--         for j = 0, r -1 do
--             local f = cc[i + c*j +1]
--             if f then
--                 f.x = cx
--             end
--         end
--         cx = cx + cs + max
--     end
--     self.implicitWidth = cx
--     self.implicitHeight = cy
end

RowLayout = {type = "RowLayout"}
RowLayout_MT = Object.IndexWrapper(Item_MT, {__index=RowLayout})
RowLayout_MT.__newindex = Item_MT.__newindex

function RowLayout:new(parent)
    local o = Layout(parent)
    o:attach("spacing")
    setmetatable(o, RowLayout_MT)
    o.spacing = 0
    local a = EFrame.bind(function() o:refreshLayout() end)
    a.parent = o
    a:update()
    return o
end
setmetatable(RowLayout, {__call = RowLayout.new})

function RowLayout:refreshLayout()
    local cc = self.children
    local spacing = self.spacing
    if getn(cc) == 0 then return end
    local cx, my = 0, 0
    for k,f in cc do
        if f.visible then
            my = max(f.height, my)
            f.x = cx
            cx = cx + f.width + spacing
        end
    end
    self.implicitWidth = cx
    self.implicitHeight = my
end

ColumnLayout = {type = "ColumnLayout"}
ColumnLayout_MT = Object.IndexWrapper(Layout_MT, {__index=ColumnLayout})
ColumnLayout_MT.__newindex = Layout_MT.__newindex

function ColumnLayout:new(parent)
    local o = Layout(parent)
    o:attach("spacing")
    setmetatable(o, ColumnLayout_MT)
    o.spacing = 0
    local a = EFrame.bind(function() o:refreshLayout() end)
    a.parent = o
    a:update()
    return o
end
setmetatable(ColumnLayout, {__call = ColumnLayout.new})

function ColumnLayout:refreshLayout()
    local cc = self.children
    local spacing = self.spacing
    if getn(cc) == 0 then return end
    local mx, cy = 0, 0
    for k,f in cc do
        if f.visible then
            mx = max(f.width, mx)
            f.y = cy
            cy = cy + f.height + spacing
        end
    end
    self.implicitWidth = mx
    self.implicitHeight = cy
end

root:SetScale(WorldFrame:GetHeight()/resy)
EFrame.root = Item(nil, root, false)
EFrame.root.name = "EFFrame.root"
EFrame.root.width = resx
EFrame.root.height = resy
