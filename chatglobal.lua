-- ╔══════════════════════════════════════════════════════╗
-- ║    GLOBAL CHAT HUB v4  •  Mobile First  💜           ║
-- ║    • Menu lateral esquerdo                           ║
-- ║    • Minimizar → bolinha flutuante arrastrável       ║
-- ║    • Sistema de faixa etária com avisos              ║
-- ╚══════════════════════════════════════════════════════╝
local FIREBASE_URL = "https://scriptroblox-adede-default-rtdb.firebaseio.com"
local POLL_INT     = 3
local MAX_MSGS     = 50
local PRES_EXPIRE  = 45

local Players = game:GetService("Players")
local UIS     = game:GetService("UserInputService")
local Tween   = game:GetService("TweenService")
local Http    = game:GetService("HttpService")

local ME     = Players.LocalPlayer
local MYNAME = ME.Name
local MYUID  = ME.UserId

-- Faixa etária: "child"(<13) | "teen"(13-17) | "adult"(18+)
local MY_AGE_GROUP = ""
local MY_AGE_NUM = 0  -- idade real em número

local function isMinorGroup(g) return g=="child" or g=="teen" end
local function isAdultGroup(g) return g=="adult" end

-- ── HTTP Detection ────────────────────────────────────────
local httpFn, httpName = nil, "none"
local useHttpSvc = false

-- Delta usa 'request' como global -- testa cada candidata com pcall
do
    local TEST = FIREBASE_URL.."/ping.json"
    local function probe(fn, nm)
        if type(fn)~="function" then return false end
        local ok,res=pcall(fn,{Url=TEST,Method="GET"})
        if ok and res then
            local sc=tonumber(res.StatusCode or res.status_code or 0) or 0
            local body=tostring(res.Body or res.body or "")
            if sc>0 or #body>0 then httpFn=fn; httpName=nm; return true end
        end
        return false
    end
    -- Testa em ordem (request = padrão do Delta)
    local fns = {
        function() return request end,
        function() return syn and syn.request end,
        function() return http_request end,
        function() return http and http.request end,
        function() return fluxus and fluxus.request end,
    }
    local names = {"request","syn.request","http_request","http.request","fluxus.request"}
    for i,getter in ipairs(fns) do
        local ok,fn = pcall(getter)
        if ok and fn and probe(fn, names[i]) then break end
    end
    -- Fallback HttpService
    if not httpFn then
        if pcall(function() Http:GetAsync(TEST) end) then
            useHttpSvc=true; httpName="HttpService"
        end
    end
end

local function doRequest(opts)
    if httpFn then
        local ok,r = pcall(httpFn, opts)
        if ok and r then
            local sc = tonumber(r.StatusCode or r.status_code) or 200
            return {Success=(sc>=200 and sc<300), StatusCode=sc, Body=tostring(r.Body or r.body or "")}
        end
    end
    local ok2,r2 = pcall(function()
        if opts.Method=="GET" then return Http:GetAsync(opts.Url)
        else return Http:PostAsync(opts.Url,opts.Body or "",Enum.HttpContentType.ApplicationJson) end
    end)
    if ok2 and r2 then useHttpSvc=true; httpName="HttpService"; return {Success=true,StatusCode=200,Body=tostring(r2)} end
    return nil
end

-- ── Firebase ──────────────────────────────────────────────
local function fbRaw(method,path,data)
    local opts={Url=FIREBASE_URL..path,Method=method,Headers={["Content-Type"]="application/json"}}
    if data then opts.Body=Http:JSONEncode(data) end
    local res=doRequest(opts); if not res then return nil,"no_response" end
    local body=tostring(res.Body or ""); local code=tonumber(res.StatusCode) or 0
    if body=="" or body=="null" or code==404 then return {},nil end
    if code==200 or res.Success then
        local ok,d=pcall(Http.JSONDecode,Http,body)
        return ok and d or {},nil
    end
    return nil,"http_"..tostring(code)..": "..body:sub(1,50)
end
local function fbGet(p)    return fbRaw("GET",p) end
local function fbPost(p,d) return fbRaw("POST",p,d) end
local function fbPut(p,d)  return fbRaw("PUT",p,d) end
local function fbDel(p)    return fbRaw("DELETE",p) end
local function fbList(ch)  return fbRaw("GET","/"..ch..'.json?orderBy="$key"&limitToLast='..MAX_MSGS) end

local function mkCode()
    local c="ABCDEFGHJKLMNPQRSTUVWXYZ23456789"; local r=""
    for _=1,6 do local i=math.random(1,#c); r=r..c:sub(i,i) end
    return r
end
local function sfen(s) return (tostring(s):gsub("[^%w%-_]","_")) end

-- Avatar com fallback silencioso
local avCache = {}
local function fetchAvatar(uid, lbl)
    if not uid or uid == 0 or not lbl then return end
    if avCache[uid] then
        pcall(function() lbl.Image = avCache[uid] end); return
    end
    task.spawn(function()
        -- tenta GetUserThumbnailAsync; silencia CrossExperience error
        local ok, url = pcall(function()
            return Players:GetUserThumbnailAsync(uid,
                Enum.ThumbnailType.HeadShot, Enum.ThumbnailSize.Size48x48)
        end)
        if ok and url and url ~= "" then
            avCache[uid] = url
            pcall(function() if lbl and lbl.Parent then lbl.Image = url end end)
        end
    end)
end

-- ── Destroy old ───────────────────────────────────────────
pcall(function()
    local cg=game:GetService("CoreGui"); local o=cg:FindFirstChild("GlobalChatHub"); if o then o:Destroy() end
    local pg=ME:FindFirstChild("PlayerGui"); if pg then local o2=pg:FindFirstChild("GlobalChatHub"); if o2 then o2:Destroy() end end
end)

-- ── ScreenGui ─────────────────────────────────────────────
local SG=Instance.new("ScreenGui")
SG.Name="GlobalChatHub"; SG.ResetOnSpawn=false; SG.IgnoreGuiInset=true
SG.ZIndexBehavior=Enum.ZIndexBehavior.Sibling; SG.DisplayOrder=999
pcall(function() if syn and syn.protect_gui then syn.protect_gui(SG) end end)
if not pcall(function() SG.Parent=game:GetService("CoreGui") end) then
    SG.Parent=ME:WaitForChild("PlayerGui")
end

local mob=UIS.TouchEnabled and not UIS.KeyboardEnabled
local vp=workspace.CurrentCamera.ViewportSize
local WIN_W   = mob and math.min(math.floor(vp.X*0.90),400) or 520
local WIN_H   = mob and math.min(math.floor(vp.Y*0.72),480) or 470
local TITLE_H = mob and 52  or 44
local TAB_W   = mob and 56  or 50
local IN_H    = mob and 44  or 34
local FSZ     = mob and 13  or 12
local AV_SZ   = mob and 26  or 22
local BTN_SZ  = mob and 28  or 23

local C_BG      = Color3.fromRGB(8,6,20)
local C_TITLE   = Color3.fromRGB(12,8,30)
local C_TABS_BG = Color3.fromRGB(10,7,24)
local C_TAB_ON  = Color3.fromRGB(85,50,205)
local C_TAB_OFF = Color3.fromRGB(17,13,36)
local C_SEND    = Color3.fromRGB(82,50,195)
local C_ACCENT  = Color3.fromRGB(72,42,180)
local C_INPUT   = Color3.fromRGB(13,10,32)

-- ── DECLARAR Main cedo (fix do nil no closure da Bubble) ──
local Main  -- será atribuído mais abaixo

-- Estado minimizar (declarado antes do closure)
local minimized = false
-- ══════════════════════════════════════════════════════════
-- BUBBLE (estado minimizado)
-- ══════════════════════════════════════════════════════════
local Bubble=Instance.new("ImageButton",SG)
Bubble.Name="MiniBubble"; Bubble.Size=UDim2.new(0,54,0,54)
Bubble.Position=UDim2.new(0,14,0.5,-27)
Bubble.BackgroundColor3=C_ACCENT; Bubble.BorderSizePixel=0
Bubble.Visible=false; Bubble.ZIndex=100; Bubble.AutoButtonColor=false
Instance.new("UICorner",Bubble).CornerRadius=UDim.new(1,0)
local bSt=Instance.new("UIStroke",Bubble); bSt.Color=Color3.fromRGB(145,105,255); bSt.Thickness=2
local bIco=Instance.new("TextLabel",Bubble)
bIco.Size=UDim2.new(1,0,1,0); bIco.BackgroundTransparency=1
bIco.Text="💬"; bIco.TextSize=24; bIco.Font=Enum.Font.GothamBold; bIco.TextColor3=Color3.new(1,1,1)
local bBadge=Instance.new("TextLabel",Bubble)
bBadge.Size=UDim2.new(0,18,0,18); bBadge.Position=UDim2.new(1,-14,0,-4)
bBadge.BackgroundColor3=Color3.fromRGB(220,45,45); bBadge.TextColor3=Color3.new(1,1,1)
bBadge.TextSize=9; bBadge.Font=Enum.Font.GothamBold; bBadge.Text=""
bBadge.BorderSizePixel=0; bBadge.Visible=false
Instance.new("UICorner",bBadge).CornerRadius=UDim.new(1,0)

-- Pulso da bolinha
task.spawn(function()
    while SG.Parent do
        if Bubble.Visible then
            Tween:Create(Bubble,TweenInfo.new(0.9,Enum.EasingStyle.Sine,Enum.EasingDirection.InOut),{BackgroundColor3=Color3.fromRGB(108,65,240)}):Play()
            task.wait(0.9)
            Tween:Create(Bubble,TweenInfo.new(0.9,Enum.EasingStyle.Sine,Enum.EasingDirection.InOut),{BackgroundColor3=Color3.fromRGB(58,32,145)}):Play()
        end
        task.wait(0.9)
    end
end)

-- Drag da bolinha
do
    local bd,bs,bp,bmoved=false,nil,nil,false
    Bubble.InputBegan:Connect(function(i)
        if i.UserInputType==Enum.UserInputType.MouseButton1 or i.UserInputType==Enum.UserInputType.Touch then
            bd=true; bs=i.Position; bp=Bubble.Position; bmoved=false
        end
    end)
    Bubble.InputEnded:Connect(function(i)
        if i.UserInputType==Enum.UserInputType.MouseButton1 or i.UserInputType==Enum.UserInputType.Touch then bd=false end
    end)
    UIS.InputChanged:Connect(function(i)
        if bd and (i.UserInputType==Enum.UserInputType.MouseMovement or i.UserInputType==Enum.UserInputType.Touch) then
            local d=i.Position-bs
            if (math.abs(d.X)+math.abs(d.Y))>8 then bmoved=true end
            Bubble.Position=UDim2.new(bp.X.Scale,bp.X.Offset+d.X,bp.Y.Scale,bp.Y.Offset+d.Y)
        end
    end)
    Bubble.MouseButton1Click:Connect(function()
        if bmoved then return end
        if not Main then return end
        minimized = false  -- reset estado
        Bubble.Visible=false; Main.Visible=true
        Main.Size=UDim2.new(0,0,0,0)
        Tween:Create(Main,TweenInfo.new(0.35,Enum.EasingStyle.Back,Enum.EasingDirection.Out),{Size=UDim2.new(0,WIN_W,0,WIN_H)}):Play()
        bBadge.Text=""; bBadge.Visible=false
    end)
end

-- ══════════════════════════════════════════════════════════
-- JANELA PRINCIPAL  (agora Main recebe o valor)
-- ══════════════════════════════════════════════════════════
Main=Instance.new("Frame",SG)
Main.Name="MainWin"; Main.AnchorPoint=Vector2.new(0.5,0.5)
Main.Position=UDim2.new(0.5,0,0.5,0)
Main.Size=UDim2.new(0,0,0,0)
Main.BackgroundColor3=C_BG; Main.BorderSizePixel=0; Main.ClipsDescendants=true
Main.Visible=false
Instance.new("UICorner",Main).CornerRadius=UDim.new(0,14)
local mSt=Instance.new("UIStroke",Main); mSt.Color=C_ACCENT; mSt.Thickness=1.5

-- ── BARRA DE TÍTULO ───────────────────────────────────────
local TBar=Instance.new("Frame",Main)
TBar.Size=UDim2.new(1,0,0,TITLE_H); TBar.BackgroundColor3=C_TITLE; TBar.BorderSizePixel=0
Instance.new("UICorner",TBar).CornerRadius=UDim.new(0,14)
local tfix=Instance.new("Frame",TBar); tfix.Size=UDim2.new(1,0,0.5,0); tfix.Position=UDim2.new(0,0,0.5,0)
tfix.BackgroundColor3=C_TITLE; tfix.BorderSizePixel=0
local tGrad=Instance.new("UIGradient",TBar)
tGrad.Color=ColorSequence.new({ColorSequenceKeypoint.new(0,Color3.fromRGB(68,40,175)),ColorSequenceKeypoint.new(1,Color3.fromRGB(12,8,30))}); tGrad.Rotation=90

local avSzT=TITLE_H-14
local avOut=Instance.new("Frame",TBar)
avOut.Size=UDim2.new(0,avSzT,0,avSzT); avOut.Position=UDim2.new(0,9,0.5,-avSzT/2)
avOut.BackgroundColor3=Color3.fromRGB(38,26,80); avOut.BorderSizePixel=0
Instance.new("UICorner",avOut).CornerRadius=UDim.new(1,0)
Instance.new("UIStroke",avOut).Color=Color3.fromRGB(110,70,210)
local avI=Instance.new("ImageLabel",avOut); avI.Size=UDim2.new(1,0,1,0); avI.BackgroundTransparency=1; avI.ScaleType=Enum.ScaleType.Fit
Instance.new("UICorner",avI).CornerRadius=UDim.new(1,0)
fetchAvatar(MYUID,avI)

local ax=avSzT+16
local nLbl=Instance.new("TextLabel",TBar)
nLbl.Text=MYNAME; nLbl.Position=UDim2.new(0,ax,0,5); nLbl.Size=UDim2.new(1,-(ax+BTN_SZ*2+22),0,TITLE_H/2-3)
nLbl.BackgroundTransparency=1; nLbl.TextColor3=Color3.fromRGB(228,218,255)
nLbl.TextSize=mob and 14 or 13; nLbl.Font=Enum.Font.GothamBold
nLbl.TextXAlignment=Enum.TextXAlignment.Left; nLbl.TextTruncate=Enum.TextTruncate.AtEnd

local gLbl=Instance.new("TextLabel",TBar)
gLbl.Text="🎮 "..game.Name; gLbl.Position=UDim2.new(0,ax,0,TITLE_H/2+2); gLbl.Size=UDim2.new(1,-(ax+BTN_SZ*2+22),0,TITLE_H/2-8)
gLbl.BackgroundTransparency=1; gLbl.TextColor3=Color3.fromRGB(95,80,158)
gLbl.TextSize=mob and 10 or 9; gLbl.Font=Enum.Font.Gotham
gLbl.TextXAlignment=Enum.TextXAlignment.Left; gLbl.TextTruncate=Enum.TextTruncate.AtEnd

local function mkTBtn(txt,bg,x)
    local b=Instance.new("TextButton",TBar)
    b.Text=txt; b.Size=UDim2.new(0,BTN_SZ,0,BTN_SZ); b.Position=UDim2.new(1,x,0.5,-BTN_SZ/2)
    b.BackgroundColor3=bg; b.TextColor3=Color3.new(1,1,1)
    b.TextSize=mob and 15 or 12; b.Font=Enum.Font.GothamBold; b.BorderSizePixel=0; b.AutoButtonColor=false
    Instance.new("UICorner",b).CornerRadius=UDim.new(0,7)
    b.MouseEnter:Connect(function() Tween:Create(b,TweenInfo.new(0.12),{BackgroundTransparency=0.25}):Play() end)
    b.MouseLeave:Connect(function() Tween:Create(b,TweenInfo.new(0.12),{BackgroundTransparency=0}):Play() end)
    return b
end
local MinBtn   = mkTBtn("−",Color3.fromRGB(200,145,0),-(BTN_SZ*2+13))
local CloseBtn = mkTBtn("X",Color3.fromRGB(195,38,38),-(BTN_SZ+7))

-- ── CORPO ─────────────────────────────────────────────────
local Body=Instance.new("Frame",Main)
Body.Size=UDim2.new(1,0,1,-TITLE_H); Body.Position=UDim2.new(0,0,0,TITLE_H)
Body.BackgroundTransparency=1; Body.ClipsDescendants=true

local LeftPanel=Instance.new("ScrollingFrame",Body)
LeftPanel.Size=UDim2.new(0,TAB_W,1,0)
LeftPanel.BackgroundColor3=C_TABS_BG; LeftPanel.BorderSizePixel=0
LeftPanel.ScrollBarThickness=0; LeftPanel.AutomaticCanvasSize=Enum.AutomaticSize.Y
LeftPanel.ScrollingDirection=Enum.ScrollingDirection.Y
local ltl=Instance.new("UIListLayout",LeftPanel)
ltl.FillDirection=Enum.FillDirection.Vertical; ltl.HorizontalAlignment=Enum.HorizontalAlignment.Center; ltl.Padding=UDim.new(0,5)
local ltp=Instance.new("UIPadding",LeftPanel); ltp.PaddingTop=UDim.new(0,8); ltp.PaddingBottom=UDim.new(0,8)

local vDiv=Instance.new("Frame",Body)
vDiv.Size=UDim2.new(0,1,1,0); vDiv.Position=UDim2.new(0,TAB_W,0,0)
vDiv.BackgroundColor3=Color3.fromRGB(50,34,122); vDiv.BorderSizePixel=0

local Content=Instance.new("Frame",Body)
Content.Size=UDim2.new(1,-TAB_W-1,1,0); Content.Position=UDim2.new(0,TAB_W+1,0,0)
Content.BackgroundTransparency=1; Content.ClipsDescendants=true

-- ══════════════════════════════════════════════════════════
-- ABAS
-- ══════════════════════════════════════════════════════════
local TABS={
    {key="local",   ico="💬",lbl="Local",   fb=nil},
    {key="global",  ico="🌍",lbl="Global",  fb="global"},
    {key="brasil",  ico="🇧🇷",lbl="Brasil",  fb="brasil"},
    {key="usa",     ico="🇺🇸",lbl="USA",     fb="usa"},
    {key="privado", ico="🔒",lbl="Privado", fb=nil},
    {key="debug",   ico="🔧",lbl="Debug",   fb=nil},
}
local tabBtns={}; local panels={}; local msgCount={}; local activeKey=nil
local unreadCount=0; local reportedUsers={}

local function switchTab(key)
    if activeKey==key then return end; activeKey=key
    for k,t in pairs(tabBtns) do
        local on=(k==key)
        Tween:Create(t.btn,TweenInfo.new(0.15),{BackgroundColor3=on and C_TAB_ON or C_TAB_OFF}):Play()
        t.ico.TextColor3=on and Color3.fromRGB(255,248,255) or Color3.fromRGB(118,105,185)
        t.lbl.TextColor3=on and Color3.fromRGB(215,208,255) or Color3.fromRGB(80,68,135)
        t.ind.BackgroundTransparency=on and 0 or 1
    end
    for k,p in pairs(panels) do
        if k==key then
            p.frame.Visible=true
            p.frame.Position=UDim2.new(0.04,0,0,0)
            Tween:Create(p.frame,TweenInfo.new(0.18,Enum.EasingStyle.Quad),{Position=UDim2.new(0,0,0,0)}):Play()
        else
            p.frame.Visible=false
        end
    end
end

local function mkTabBtn(tab)
    local btn=Instance.new("TextButton",LeftPanel)
    btn.Name=tab.key
    local BH=mob and 62 or 54
    btn.Size=UDim2.new(1,-6,0,BH); btn.BackgroundColor3=C_TAB_OFF; btn.BorderSizePixel=0
    btn.Text=""; btn.AutoButtonColor=false
    Instance.new("UICorner",btn).CornerRadius=UDim.new(0,9)
    local ind=Instance.new("Frame",btn)
    ind.Size=UDim2.new(0,3,0.6,0); ind.Position=UDim2.new(0,0,0.2,0)
    ind.BackgroundColor3=Color3.fromRGB(165,120,255); ind.BorderSizePixel=0; ind.BackgroundTransparency=1
    Instance.new("UICorner",ind).CornerRadius=UDim.new(0,2)
    local ico=Instance.new("TextLabel",btn)
    ico.Size=UDim2.new(1,0,0,mob and 28 or 22); ico.Position=UDim2.new(0,0,0,mob and 6 or 4)
    ico.BackgroundTransparency=1; ico.TextSize=mob and 18 or 15; ico.Font=Enum.Font.GothamBold
    ico.Text=tab.ico; ico.TextColor3=Color3.fromRGB(118,105,185)
    local lbl=Instance.new("TextLabel",btn)
    lbl.Size=UDim2.new(1,0,0,mob and 14 or 12); lbl.Position=UDim2.new(0,0,1,mob and -20 or -16)
    lbl.BackgroundTransparency=1; lbl.TextSize=mob and 8 or 7; lbl.Font=Enum.Font.Gotham
    lbl.Text=tab.lbl; lbl.TextColor3=Color3.fromRGB(80,68,135)
    tabBtns[tab.key]={btn=btn,ico=ico,lbl=lbl,ind=ind}
    btn.MouseButton1Click:Connect(function() switchTab(tab.key) end)
end

local function buildPanel(key,noInput)
    msgCount[key]=0
    local frame=Instance.new("Frame",Content)
    frame.Name=key; frame.Size=UDim2.new(1,0,1,0)
    frame.BackgroundTransparency=1; frame.Visible=false; frame.ClipsDescendants=true
    local iH=noInput and 0 or (IN_H+10)
    local scroll=Instance.new("ScrollingFrame",frame)
    scroll.Name="Scroll"; scroll.Size=UDim2.new(1,-8,1,-(iH+14)); scroll.Position=UDim2.new(0,4,0,3)
    scroll.BackgroundColor3=Color3.fromRGB(9,7,20); scroll.BorderSizePixel=0
    scroll.ScrollBarThickness=3; scroll.ScrollBarImageColor3=C_ACCENT
    scroll.CanvasSize=UDim2.new(0,0,0,0); scroll.AutomaticCanvasSize=Enum.AutomaticSize.None
    Instance.new("UICorner",scroll).CornerRadius=UDim.new(0,8)
    local ll=Instance.new("UIListLayout",scroll); ll.SortOrder=Enum.SortOrder.LayoutOrder; ll.Padding=UDim.new(0,2)
    local sp=Instance.new("UIPadding",scroll)
    sp.PaddingLeft=UDim.new(0,5); sp.PaddingRight=UDim.new(0,5); sp.PaddingTop=UDim.new(0,4); sp.PaddingBottom=UDim.new(0,4)
    -- Atualiza CanvasSize manualmente e rola para o fim
    ll:GetPropertyChangedSignal("AbsoluteContentSize"):Connect(function()
        local h = ll.AbsoluteContentSize.Y + 16
        scroll.CanvasSize = UDim2.new(0,0,0,h)
        scroll.CanvasPosition = Vector2.new(0, math.max(0, h - scroll.AbsoluteSize.Y))
    end)
    local inputBox,sendBtn
    if not noInput then
        local iF=Instance.new("Frame",frame)
        iF.Size=UDim2.new(1,-8,0,IN_H); iF.Position=UDim2.new(0,4,1,-(IN_H+5))
        iF.BackgroundColor3=C_INPUT; iF.BorderSizePixel=0
        Instance.new("UICorner",iF).CornerRadius=UDim.new(0,10)
        Instance.new("UIStroke",iF).Color=Color3.fromRGB(58,38,148)
        inputBox=Instance.new("TextBox",iF); inputBox.PlaceholderText="Escreva aqui..."; inputBox.Text=""
        inputBox.Size=UDim2.new(1,-(IN_H+12),1,0); inputBox.Position=UDim2.new(0,10,0,0)
        inputBox.BackgroundTransparency=1; inputBox.TextColor3=Color3.fromRGB(215,205,255)
        inputBox.PlaceholderColor3=Color3.fromRGB(62,52,112); inputBox.TextSize=FSZ
        inputBox.Font=Enum.Font.Gotham; inputBox.TextXAlignment=Enum.TextXAlignment.Left
        inputBox.ClearTextOnFocus=false; inputBox.MultiLine=false
        sendBtn=Instance.new("TextButton",iF)
        sendBtn.Text=">>>"; sendBtn.Size=UDim2.new(0,IN_H-4,0,IN_H-8); sendBtn.Position=UDim2.new(1,-(IN_H+2),0.5,-(IN_H-8)/2)
        sendBtn.BackgroundColor3=C_SEND; sendBtn.TextColor3=Color3.new(1,1,1)
        sendBtn.TextSize=mob and 18 or 16; sendBtn.Font=Enum.Font.GothamBold; sendBtn.BorderSizePixel=0; sendBtn.AutoButtonColor=false
        Instance.new("UICorner",sendBtn).CornerRadius=UDim.new(0,8)
        sendBtn.MouseEnter:Connect(function() Tween:Create(sendBtn,TweenInfo.new(0.12),{BackgroundColor3=Color3.fromRGB(105,70,225)}):Play() end)
        sendBtn.MouseLeave:Connect(function() Tween:Create(sendBtn,TweenInfo.new(0.12),{BackgroundColor3=C_SEND}):Play() end)
    end
    panels[key]={frame=frame,scroll=scroll,input=inputBox,send=sendBtn}
    return panels[key]
end

-- ── addMsg ────────────────────────────────────────────────
local function addMsg(key,user,text,uid,senderAgeGroup,isSys)
    local p=panels[key]; if not p or not p.scroll then return end
    msgCount[key]=(msgCount[key] or 0)+1
    if msgCount[key]>MAX_MSGS then
        local f=p.scroll:FindFirstChildWhichIsA("Frame"); if f then f:Destroy(); msgCount[key]=msgCount[key]-1 end
    end
    -- Badge na bolinha + som/vibração
    if not isSys and user~=MYNAME then
        pcall(playNotif)
        if Bubble.Visible then
            unreadCount=unreadCount+1; bBadge.Text=unreadCount>9 and "9+" or tostring(unreadCount); bBadge.Visible=true
        end
    end
    local row=Instance.new("Frame",p.scroll)
    row.Name="msg"; row.LayoutOrder=msgCount[key]; row.BackgroundTransparency=1; row.BorderSizePixel=0
    if isSys then
        row.Size=UDim2.new(1,0,0,20); row.AutomaticSize=Enum.AutomaticSize.Y
        local lb=Instance.new("TextLabel",row)
        lb.Size=UDim2.new(1,-4,0,0); lb.AutomaticSize=Enum.AutomaticSize.Y; lb.Position=UDim2.new(0,2,0,2)
        lb.BackgroundTransparency=1; lb.TextColor3=Color3.fromRGB(112,102,175); lb.TextSize=FSZ-1
        lb.Font=Enum.Font.Gotham; lb.TextWrapped=true; lb.TextXAlignment=Enum.TextXAlignment.Center; lb.RichText=true
        lb.Text=tostring(text)
    else
        -- verificar aviso de idade
        local showWarn=false; local warnTxt=""
        local sAge = tonumber(senderAgeGroup) or 0
        if user~=MYNAME and MY_AGE_NUM>0 and sAge>0 then
            if MY_AGE_NUM < 18 and sAge >= 18 then
                showWarn=true; warnTxt="⚠️ Este usuário é adulto ("..sAge.." anos). Tome cuidado!"
            elseif MY_AGE_NUM >= 18 and sAge < 18 then
                showWarn=true; warnTxt="⚠️ Este usuário é menor de idade ("..sAge.." anos)."
            end
        end

        row.Size=UDim2.new(1,0,0,AV_SZ+14); row.AutomaticSize=Enum.AutomaticSize.Y
        row.BackgroundColor3=Color3.fromRGB(22,16,48)
        row.BackgroundTransparency= showWarn and 0.4 or 0.6
        Instance.new("UICorner",row).CornerRadius=UDim.new(0,7)
        if showWarn then
            local warnSt=Instance.new("UIStroke",row); warnSt.Color=Color3.fromRGB(220,120,0); warnSt.Thickness=1
        end
        Tween:Create(row,TweenInfo.new(0.2),{BackgroundTransparency= showWarn and 0.55 or 0.72}):Play()

        -- Aviso banner
        if showWarn then
            local wb=Instance.new("Frame",row)
            wb.Size=UDim2.new(1,-10,0,0); wb.AutomaticSize=Enum.AutomaticSize.Y; wb.Position=UDim2.new(0,5,0,4)
            wb.BackgroundColor3=Color3.fromRGB(160,72,10); wb.BackgroundTransparency=0.25; wb.BorderSizePixel=0
            Instance.new("UICorner",wb).CornerRadius=UDim.new(0,6)
            local wt=Instance.new("TextLabel",wb)
            wt.Size=UDim2.new(1,-8,0,0); wt.AutomaticSize=Enum.AutomaticSize.Y; wt.Position=UDim2.new(0,4,0,3)
            wt.BackgroundTransparency=1; wt.TextColor3=Color3.fromRGB(255,215,95)
            wt.TextSize=FSZ-2; wt.Font=Enum.Font.GothamBold; wt.TextWrapped=true; wt.TextXAlignment=Enum.TextXAlignment.Left
            wt.Text=warnTxt
            local wsp=Instance.new("Frame",wb); wsp.Size=UDim2.new(1,0,0,4); wsp.Position=UDim2.new(0,0,1,0); wsp.BackgroundTransparency=1
        end

        local yOff = showWarn and (FSZ+12) or 0

        -- Avatar
        local avF=Instance.new("Frame",row)
        avF.Size=UDim2.new(0,AV_SZ,0,AV_SZ); avF.Position=UDim2.new(0,5,0,yOff+6)
        avF.BackgroundColor3=Color3.fromRGB(36,24,72); avF.BorderSizePixel=0
        Instance.new("UICorner",avF).CornerRadius=UDim.new(1,0)
        local avImg2=Instance.new("ImageLabel",avF); avImg2.Size=UDim2.new(1,0,1,0); avImg2.BackgroundTransparency=1; avImg2.ScaleType=Enum.ScaleType.Fit
        Instance.new("UICorner",avImg2).CornerRadius=UDim.new(1,0)
        if uid and uid~=0 then fetchAvatar(uid,avImg2) end

        local lx=AV_SZ+11
        local txF=Instance.new("Frame",row)
        txF.Size=UDim2.new(1,-(lx+5),0,0); txF.AutomaticSize=Enum.AutomaticSize.Y
        txF.Position=UDim2.new(0,lx,0,yOff+5); txF.BackgroundTransparency=1

        local nc=(user==MYNAME) and "#FFD700" or "#AE9DFF"
        -- pegar idade numérica do campo "an" se disponível
        local ageTag=""
        local ageNum = tonumber(senderAgeGroup) or 0
        if ageNum > 0 then
            local ageColor = ageNum < 13 and "#6699FF" or (ageNum < 18 and "#AAAAFF" or "#AAFFAA")
            ageTag = (' (%d)'):format(ageNum)
        end

        local nL=Instance.new("TextLabel",txF)
        nL.Size=UDim2.new(1,0,0,14); nL.BackgroundTransparency=1; nL.TextSize=FSZ-1; nL.Font=Enum.Font.GothamBold
        nL.TextXAlignment=Enum.TextXAlignment.Left; nL.RichText=true
        nL.Text=('<font color="%s">%s</font>%s'):format(nc,tostring(user),ageTag)

        local mL=Instance.new("TextLabel",txF)
        mL.Size=UDim2.new(1,0,0,0); mL.AutomaticSize=Enum.AutomaticSize.Y; mL.Position=UDim2.new(0,0,0,15)
        mL.BackgroundTransparency=1; mL.TextColor3=Color3.fromRGB(202,192,242); mL.TextSize=FSZ
        mL.Font=Enum.Font.Gotham; mL.TextWrapped=true; mL.TextXAlignment=Enum.TextXAlignment.Left; mL.Text=tostring(text)

        -- Botão Reportar (destacado se showWarn)
        if user~=MYNAME then
            local rBtn=Instance.new("TextButton",txF)
            rBtn.Text="🚨 Reportar"; rBtn.Size=UDim2.new(0,82,0,18); rBtn.Position=UDim2.new(0,0,1,4)
            rBtn.BackgroundColor3= showWarn and Color3.fromRGB(180,40,40) or Color3.fromRGB(80,55,130)
            rBtn.BackgroundTransparency= showWarn and 0.2 or 0.65
            rBtn.TextColor3= showWarn and Color3.fromRGB(255,210,210) or Color3.fromRGB(180,160,220)
            rBtn.TextSize=FSZ-2; rBtn.Font=Enum.Font.GothamBold; rBtn.BorderSizePixel=0; rBtn.AutoButtonColor=false
            Instance.new("UICorner",rBtn).CornerRadius=UDim.new(0,5)
            rBtn.MouseButton1Click:Connect(function()
                if reportedUsers[user] then rBtn.Text="✔ Reportado"; return end
                reportedUsers[user]=true; rBtn.Text="✔ Reportado"
                rBtn.BackgroundColor3=Color3.fromRGB(35,110,35); rBtn.BackgroundTransparency=0.2
                task.spawn(function()
                    fbPost("/reports.json",{reporter=MYNAME,reported=user,uid=uid or 0,ts=os.time(),g=game.Name})
                end)
            end)
            -- Botão Convidar pra Sala
            local invBtn=Instance.new("TextButton",txF)
            invBtn.Text="+ Sala Priv"; invBtn.Size=UDim2.new(0,78,0,18)
            invBtn.Position=UDim2.new(0,88,1,4)
            invBtn.BackgroundColor3=Color3.fromRGB(30,90,160); invBtn.BackgroundTransparency=0.4
            invBtn.TextColor3=Color3.fromRGB(180,220,255)
            invBtn.TextSize=FSZ-2; invBtn.Font=Enum.Font.GothamBold; invBtn.BorderSizePixel=0; invBtn.AutoButtonColor=false
            Instance.new("UICorner",invBtn).CornerRadius=UDim.new(0,5)
            invBtn.MouseButton1Click:Connect(function()
                if not privCode then
                    invBtn.Text="Crie sala 1o!"; task.delay(2,function() invBtn.Text="+ Sala Priv" end); return
                end
                invBtn.Text="Enviando..."; invBtn.BackgroundTransparency=0.6
                task.spawn(function()
                    local invKey = sfen(user)
                    fbPut("/invites/"..invKey..".json",{
                        from=MYNAME, fromUid=MYUID, code=privCode,
                        ts=os.time(), to=user
                    })
                    invBtn.Text="✔ Convidado!"
                    invBtn.BackgroundColor3=Color3.fromRGB(30,130,60)
                    invBtn.BackgroundTransparency=0.2
                end)
            end)
            local rsp=Instance.new("Frame",txF); rsp.Size=UDim2.new(1,0,0,26); rsp.Position=UDim2.new(0,0,1,0); rsp.BackgroundTransparency=1
        end

        local bp=Instance.new("Frame",row); bp.Size=UDim2.new(1,0,0,8); bp.Position=UDim2.new(0,0,1,0); bp.BackgroundTransparency=1
    end

end

local function sysMsg(key,txt) addMsg(key,"",txt,0,nil,true) end

-- Montar abas e painéis
for _,tab in ipairs(TABS) do
    mkTabBtn(tab)
    local noIn=(tab.key=="local" or tab.key=="debug" or tab.key=="privado")
    buildPanel(tab.key,noIn)
end

-- ══════════════════════════════════════════════════════════
-- CHAT LOCAL
-- ══════════════════════════════════════════════════════════
sysMsg("local","✅ Chat local conectado!")
local function hookLocalChat()
    local ok=pcall(function()
        local tcs=game:GetService("TextChatService")
        if tcs.ChatVersion~=Enum.ChatVersion.TextChatService then error() end
        tcs.MessageReceived:Connect(function(msg)
            local nm=(msg.TextSource and msg.TextSource.Name) or "?"
            local uid2=0; pcall(function() local pp=Players:FindFirstChild(nm); if pp then uid2=pp.UserId end end)
            addMsg("local",nm,msg.Text,uid2,nil,false)
        end)
    end)
    if ok then return end
    local function hk(pl) pl.Chatted:Connect(function(m) addMsg("local",pl.Name,m,pl.UserId,nil,false) end) end
    for _,pl in ipairs(Players:GetPlayers()) do hk(pl) end
    Players.PlayerAdded:Connect(hk)
end
task.spawn(hookLocalChat)

-- ══════════════════════════════════════════════════════════
-- CANAIS FIREBASE
-- ══════════════════════════════════════════════════════════
local function setupChannel(key,fb)
    local p=panels[key]; if not p then return end
    sysMsg(key,"🔗 Canal ["..fb.."] conectando...")
    local lastSent=0; local spamCount=0
    local function enviar(txt)
        txt=txt and txt:match("^%s*(.-)%s*$") or ""; if txt=="" then return end
        local now=os.time()
        if (now-lastSent) < 2 then
            spamCount=spamCount+1
            if spamCount >= 4 then
                sysMsg(key,"⛔ Spam detectado! Aguarde 8s.")
                if p.input then p.input.Text="" end
                task.delay(8,function() spamCount=0; lastSent=0 end)
                return
            end
            sysMsg(key,"⏳ Espere "..tostring(2-(now-lastSent)).."s")
            return
        end
        spamCount=math.max(0,spamCount-1); lastSent=now
        task.spawn(function()
            fbPost("/"..fb..".json",{u=MYNAME,uid=MYUID,t=txt,ts=os.time(),g=game.Name,ag=MY_AGE_GROUP,an=MY_AGE_NUM})
        end)
        pcall(playSend)
        if p.input then p.input.Text="" end
    end
    if p.send  then p.send.MouseButton1Click:Connect(function() enviar(p.input and p.input.Text or "") end) end
    if p.input then p.input.FocusLost:Connect(function(enter) if enter then enviar(p.input.Text) end end) end
    task.spawn(function()
        local known={}; local first=true
        while Main.Parent do
            task.wait(first and 0.5 or POLL_INT)
            local data,err=fbList(fb)
            if data and type(data)=="table" then
                local list={}
                for k,v in pairs(data) do
                    if type(v)=="table" and not known[k] then
                        known[k]=true; table.insert(list,{ts=v.ts or 0,u=v.u or "?",t=v.t or "",uid=v.uid or 0,ag=v.ag or ""})
                    end
                end
                table.sort(list,function(a,b) return a.ts<b.ts end)
                if first then first=false; if #list==0 then sysMsg(key,"📭 Vazio. Seja o primeiro!") else sysMsg(key,"✅ Conectado!") end end
                for _,m in ipairs(list) do addMsg(key,m.u,m.t,m.uid,m.an or 0,false) end
            else
                if first then first=false; sysMsg(key,"⚠️ Erro: "..(err or "?").." | 🔧 Debug") end
            end
        end
    end)
end
setupChannel("global","global"); setupChannel("brasil","brasil"); setupChannel("usa","usa")

-- ══════════════════════════════════════════════════════════
-- PRESENÇA
-- ══════════════════════════════════════════════════════════
local myKey=sfen(MYNAME); local knownUsers={}
local function pushPresence() task.spawn(function() fbPut("/presence/"..myKey..".json",{n=MYNAME,uid=MYUID,ts=os.time(),g=game.Name,ag=MY_AGE_GROUP}) end) end
local function pollPresence()
    task.spawn(function()
        local data=fbGet("/presence.json"); if not data or type(data)~="table" then return end
        local now=os.time()
        for sk,info in pairs(data) do
            if sk~=myKey and type(info)=="table" then
                local fresh=(now-(info.ts or 0))<PRES_EXPIRE
                if knownUsers[sk]==nil and fresh then knownUsers[sk]={n=info.n or sk,alive=true}
                elseif knownUsers[sk] and knownUsers[sk].alive and not fresh then
                    knownUsers[sk].alive=false; local nm=info.n or sk
                    for _,ch in ipairs({"global","brasil","usa"}) do sysMsg(ch,"👋 "..nm.." saiu") end
                    task.delay(30,function() fbDel("/presence/"..sk..".json") end)
                end
            end
        end
    end)
end
pushPresence()
task.spawn(function() while Main.Parent do task.wait(12); pushPresence(); pollPresence() end end)


-- ══════════════════════════════════════════════════════════
-- SOM E VIBRAÇÃO DE NOTIFICAÇÃO
-- ══════════════════════════════════════════════════════════
local HapticSvc = pcall(function() return game:GetService("HapticService") end) and game:GetService("HapticService") or nil
local SoundSvc  = game:GetService("SoundService")

-- Som de notificação (beep curto)
local notifSound = Instance.new("Sound")
notifSound.SoundId = "rbxassetid://4590662766"  -- beep curto do Roblox
notifSound.Volume = 0.4
notifSound.RollOffMaxDistance = 0
pcall(function() notifSound.Parent = SoundSvc end)

-- Som de envio (clique)
local sendSound = Instance.new("Sound")
sendSound.SoundId = "rbxassetid://608537390"  -- click
sendSound.Volume = 0.25
sendSound.RollOffMaxDistance = 0
pcall(function() sendSound.Parent = SoundSvc end)

local function playNotif()
    pcall(function() notifSound:Play() end)
    -- Vibração no mobile
    pcall(function()
        if HapticSvc then
            HapticSvc:SetMotor(Enum.UserInputType.Gamepad1, Enum.VibrationMotor.Small, 0.5)
            task.delay(0.1, function()
                pcall(function() HapticSvc:SetMotor(Enum.UserInputType.Gamepad1, Enum.VibrationMotor.Small, 0) end)
            end)
        end
    end)
    -- Piscar borda da janela (feedback visual)
    pcall(function()
        if Main and Main.Visible then
            Tween:Create(mSt, TweenInfo.new(0.12), {Color=Color3.fromRGB(255,200,50), Thickness=2.5}):Play()
            task.delay(0.25, function()
                pcall(function() Tween:Create(mSt, TweenInfo.new(0.3), {Color=C_ACCENT, Thickness=1.5}):Play() end)
            end)
        end
    end)
end

local function playSend()
    pcall(function() sendSound:Play() end)
end

-- ══════════════════════════════════════════════════════════
-- SISTEMA DE CONVITES
-- ══════════════════════════════════════════════════════════
local myInvKey = sfen(MYNAME)

local function showInvitePopup(fromName, roomCode)
    -- Overlay escuro
    local ov=Instance.new("Frame",SG)
    ov.Size=UDim2.new(1,0,1,0); ov.BackgroundColor3=Color3.fromRGB(0,0,0)
    ov.BackgroundTransparency=0.5; ov.ZIndex=200; ov.BorderSizePixel=0

    -- Card do convite
    local pop=Instance.new("Frame",SG)
    pop.AnchorPoint=Vector2.new(0.5,0.5); pop.Position=UDim2.new(0.5,0,0.5,0)
    pop.Size=UDim2.new(0,0,0,0); pop.ZIndex=201
    pop.BackgroundColor3=Color3.fromRGB(10,8,28); pop.BorderSizePixel=0
    pop.ClipsDescendants=true
    Instance.new("UICorner",pop).CornerRadius=UDim.new(0,16)
    local pSt=Instance.new("UIStroke",pop); pSt.Color=Color3.fromRGB(80,160,255); pSt.Thickness=1.8

    local PW = mob and math.min(math.floor(vp.X*0.82),340) or 340
    local PH = mob and 200 or 185
    Tween:Create(pop,TweenInfo.new(0.35,Enum.EasingStyle.Back,Enum.EasingDirection.Out),
        {Size=UDim2.new(0,PW,0,PH)}):Play()

    local ico2=Instance.new("TextLabel",pop); ico2.Text="🔒"
    ico2.Size=UDim2.new(1,0,0,mob and 44 or 38); ico2.Position=UDim2.new(0,0,0,mob and 12 or 10)
    ico2.BackgroundTransparency=1; ico2.TextSize=mob and 30 or 26
    ico2.Font=Enum.Font.GothamBold; ico2.ZIndex=202

    local t1=Instance.new("TextLabel",pop)
    t1.Size=UDim2.new(1,-20,0,mob and 26 or 22); t1.Position=UDim2.new(0,10,0,mob and 58 or 50)
    t1.BackgroundTransparency=1; t1.TextColor3=Color3.fromRGB(230,220,255)
    t1.TextSize=mob and 15 or 14; t1.Font=Enum.Font.GothamBold; t1.ZIndex=202
    t1.Text=fromName.." te convidou!"

    local t2=Instance.new("TextLabel",pop)
    t2.Size=UDim2.new(1,-20,0,mob and 20 or 18); t2.Position=UDim2.new(0,10,0,mob and 86 or 76)
    t2.BackgroundTransparency=1; t2.TextColor3=Color3.fromRGB(120,160,220)
    t2.TextSize=mob and 12 or 11; t2.Font=Enum.Font.Gotham; t2.ZIndex=202
    t2.Text="Sala privada: "..roomCode

    local BW=(PW-36)/2
    local BY=mob and 122 or 110
    local BH=mob and 42 or 36

    local accBtn=Instance.new("TextButton",pop)
    accBtn.Size=UDim2.new(0,BW,0,BH); accBtn.Position=UDim2.new(0,10,0,BY)
    accBtn.BackgroundColor3=Color3.fromRGB(30,130,55); accBtn.TextColor3=Color3.new(1,1,1)
    accBtn.Text="✔ Entrar"; accBtn.TextSize=mob and 14 or 13; accBtn.Font=Enum.Font.GothamBold
    accBtn.BorderSizePixel=0; accBtn.AutoButtonColor=false; accBtn.ZIndex=202
    Instance.new("UICorner",accBtn).CornerRadius=UDim.new(0,10)

    local decBtn=Instance.new("TextButton",pop)
    decBtn.Size=UDim2.new(0,BW,0,BH); decBtn.Position=UDim2.new(0,BW+26,0,BY)
    decBtn.BackgroundColor3=Color3.fromRGB(150,30,30); decBtn.TextColor3=Color3.new(1,1,1)
    decBtn.Text="✕ Recusar"; decBtn.TextSize=mob and 14 or 13; decBtn.Font=Enum.Font.GothamBold
    decBtn.BorderSizePixel=0; decBtn.AutoButtonColor=false; decBtn.ZIndex=202
    Instance.new("UICorner",decBtn).CornerRadius=UDim.new(0,10)

    local function closePopup()
        Tween:Create(pop,TweenInfo.new(0.2,Enum.EasingStyle.Quart,Enum.EasingDirection.In),{Size=UDim2.new(0,0,0,0)}):Play()
        Tween:Create(ov,TweenInfo.new(0.2),{BackgroundTransparency=1}):Play()
        task.delay(0.25,function() pop:Destroy(); ov:Destroy() end)
        -- Limpar convite do Firebase
        task.spawn(function() fbDel("/invites/"..myInvKey..".json") end)
    end

    accBtn.MouseButton1Click:Connect(function()
        closePopup()
        task.spawn(function()
            local info=fbGet("/rooms/"..roomCode.."/info.json")
            if info and type(info)=="table" and info.c then
                startPrivateRoom(roomCode,false)
            else
                sysMsg("global","❌ Sala não encontrada ou expirou.")
            end
        end)
    end)
    decBtn.MouseButton1Click:Connect(function() closePopup() end)

    -- Auto-fechar em 30s
    task.delay(30,function()
        if pop and pop.Parent then closePopup() end
    end)
end

-- Poll de convites (checa a cada 4s)
task.spawn(function()
    task.wait(3)
    local lastInviteTs = 0
    while Main.Parent do
        task.wait(4)
        local inv = fbGet("/invites/"..myInvKey..".json")
        if inv and type(inv)=="table" and inv.code and inv.ts and tonumber(inv.ts) > lastInviteTs then
            lastInviteTs = tonumber(inv.ts)
            local fromN = inv.from or "Alguém"
            local code2 = inv.code
            -- Mostrar popup na thread principal
            showInvitePopup(fromN, code2)
        end
    end
end)


-- ══════════════════════════════════════════════════════════
-- SALA PRIVADA
-- ══════════════════════════════════════════════════════════
local privCode=nil; local privKnown={}

local function startPrivateRoom(code,isCreator)
    privCode=code; privKnown={}
    local p=panels["privado"]; if not p then return end
    for _,c in ipairs(p.frame:GetChildren()) do c:Destroy() end
    local scroll2=Instance.new("ScrollingFrame",p.frame)
    scroll2.Size=UDim2.new(1,-8,1,-(IN_H+36)); scroll2.Position=UDim2.new(0,4,0,30)
    scroll2.BackgroundColor3=Color3.fromRGB(9,7,20); scroll2.BorderSizePixel=0
    scroll2.ScrollBarThickness=3; scroll2.ScrollBarImageColor3=Color3.fromRGB(138,42,205)
    scroll2.CanvasSize=UDim2.new(0,0,0,0); scroll2.AutomaticCanvasSize=Enum.AutomaticSize.None
    Instance.new("UICorner",scroll2).CornerRadius=UDim.new(0,8)
    local ll2=Instance.new("UIListLayout",scroll2); ll2.SortOrder=Enum.SortOrder.LayoutOrder; ll2.Padding=UDim.new(0,2)
    local sp2=Instance.new("UIPadding",scroll2)
    sp2.PaddingLeft=UDim.new(0,5); sp2.PaddingRight=UDim.new(0,5); sp2.PaddingTop=UDim.new(0,4); sp2.PaddingBottom=UDim.new(0,4)
    ll2:GetPropertyChangedSignal("AbsoluteContentSize"):Connect(function()
        local h2 = ll2.AbsoluteContentSize.Y + 16
        scroll2.CanvasSize = UDim2.new(0,0,0,h2)
        scroll2.CanvasPosition = Vector2.new(0, math.max(0, h2 - scroll2.AbsoluteSize.Y))
    end)

    p.scroll=scroll2; msgCount["privado"]=0
    local cLbl=Instance.new("TextLabel",p.frame)
    cLbl.Size=UDim2.new(1,-8,0,24); cLbl.Position=UDim2.new(0,4,0,3)
    cLbl.BackgroundTransparency=1; cLbl.TextXAlignment=Enum.TextXAlignment.Left
    cLbl.TextColor3=Color3.fromRGB(185,162,240); cLbl.TextSize=FSZ-1; cLbl.Font=Enum.Font.Gotham; cLbl.RichText=true
    cLbl.Text='🔒 <font color="#FFD700"><b>'..code.."</b></font> "..(isCreator and "· você criou" or "· você entrou")
    local iF2=Instance.new("Frame",p.frame)
    iF2.Size=UDim2.new(1,-8,0,IN_H); iF2.Position=UDim2.new(0,4,1,-(IN_H+5))
    iF2.BackgroundColor3=Color3.fromRGB(13,10,32); iF2.BorderSizePixel=0
    Instance.new("UICorner",iF2).CornerRadius=UDim.new(0,10); Instance.new("UIStroke",iF2).Color=Color3.fromRGB(112,36,170)
    local inBox=Instance.new("TextBox",iF2); inBox.PlaceholderText="Mensagem privada..."; inBox.Text=""
    inBox.Size=UDim2.new(1,-(IN_H+12),1,0); inBox.Position=UDim2.new(0,10,0,0)
    inBox.BackgroundTransparency=1; inBox.TextColor3=Color3.fromRGB(215,205,255)
    inBox.PlaceholderColor3=Color3.fromRGB(78,58,128); inBox.TextSize=FSZ; inBox.Font=Enum.Font.Gotham
    inBox.TextXAlignment=Enum.TextXAlignment.Left; inBox.ClearTextOnFocus=false
    local sBtn2=Instance.new("TextButton",iF2); sBtn2.Text=">>>"; sBtn2.Size=UDim2.new(0,IN_H-4,0,IN_H-8)
    sBtn2.Position=UDim2.new(1,-(IN_H+2),0.5,-(IN_H-8)/2)
    sBtn2.BackgroundColor3=Color3.fromRGB(138,36,195); sBtn2.TextColor3=Color3.new(1,1,1)
    sBtn2.TextSize=mob and 18 or 16; sBtn2.Font=Enum.Font.GothamBold; sBtn2.BorderSizePixel=0; sBtn2.AutoButtonColor=false
    Instance.new("UICorner",sBtn2).CornerRadius=UDim.new(0,8)
    p.input=inBox; p.send=sBtn2
    local function addPS(txt)
        if not p.scroll then return end
        msgCount["privado"]=(msgCount["privado"] or 0)+1
        local row=Instance.new("Frame",p.scroll); row.LayoutOrder=msgCount["privado"]; row.BackgroundTransparency=1
        row.Size=UDim2.new(1,0,0,20); row.AutomaticSize=Enum.AutomaticSize.Y
        local lb=Instance.new("TextLabel",row); lb.Size=UDim2.new(1,-4,0,0); lb.AutomaticSize=Enum.AutomaticSize.Y
        lb.Position=UDim2.new(0,2,0,2); lb.BackgroundTransparency=1
        lb.TextColor3=Color3.fromRGB(162,78,220); lb.TextSize=FSZ-1; lb.Font=Enum.Font.Gotham
        lb.TextWrapped=true; lb.TextXAlignment=Enum.TextXAlignment.Center; lb.Text=tostring(txt)
    end
    local function addPM(user,txt,uid2,ag2)
        addMsg("privado",user,txt,uid2,ag2,false)
    end
    local function sendP(txt)
        txt=txt and txt:match("^%s*(.-)%s*$") or ""; if txt=="" then return end
        task.spawn(function() fbPost("/rooms/"..code.."/msgs.json",{u=MYNAME,uid=MYUID,t=txt,ts=os.time(),ag=MY_AGE_GROUP,an=MY_AGE_NUM}) end)
        inBox.Text=""
    end
    sBtn2.MouseButton1Click:Connect(function() sendP(inBox.Text) end)
    inBox.FocusLost:Connect(function(enter) if enter then sendP(inBox.Text) end end)
    addPS("🔒 Sala: "..code..(isCreator and " — aguarde amigo..." or " — você entrou!"))
    task.spawn(function()
        local first=true
        while Main.Parent and privCode==code do
            task.wait(first and 0.5 or POLL_INT)
            local data2,err2=fbList("rooms/"..code.."/msgs")
            if data2 and type(data2)=="table" then
                local list2={}
                for k,v in pairs(data2) do
                    if type(v)=="table" and not privKnown[k] then
                        privKnown[k]=true; table.insert(list2,{ts=v.ts or 0,u=v.u or "?",t=v.t or "",uid=v.uid or 0,ag=v.ag or "",an=v.an or 0})
                    end
                end
                table.sort(list2,function(a,b) return a.ts<b.ts end)
                if first then first=false; if #list2==0 then addPS("📭 Sala vazia. Manda o código!") else addPS("✅ Sala ativa!") end end
                for _,m in ipairs(list2) do
                    addPM(m.u,m.t,m.uid,m.an or 0)
                    -- Notificação na bolinha se minimizado
                    if Bubble.Visible and m.u ~= MYNAME then
                        unreadCount = unreadCount + 1
                        bBadge.Text = unreadCount > 9 and "9+" or tostring(unreadCount)
                        bBadge.Visible = true
                    end
                end
            else
                if first then first=false; addPS("⚠️ Erro: "..(err2 or "?")) end
            end
        end
    end)
    switchTab("privado")
end

task.defer(function()
    task.wait(0.5)
    local p=panels["privado"]; if not p then return end
    sysMsg("privado","🔒 Sala Privada Global"); sysMsg("privado","Crie ou entre com código")
    local ctrl=Instance.new("Frame",p.frame)
    ctrl.Name="PrivCtrl"; ctrl.AnchorPoint=Vector2.new(0.5,0.5)
    ctrl.Size=UDim2.new(0.90,0,0,0); ctrl.AutomaticSize=Enum.AutomaticSize.Y
    ctrl.Position=UDim2.new(0.5,0,0.46,0); ctrl.BackgroundTransparency=1
    local cll=Instance.new("UIListLayout",ctrl)
    cll.FillDirection=Enum.FillDirection.Vertical; cll.Padding=UDim.new(0,10); cll.HorizontalAlignment=Enum.HorizontalAlignment.Center
    local cBtn=Instance.new("TextButton",ctrl)
    cBtn.Text="✨ Criar Sala Privada"; cBtn.Size=UDim2.new(1,0,0,IN_H+4)
    cBtn.BackgroundColor3=Color3.fromRGB(88,36,182); cBtn.TextColor3=Color3.new(1,1,1)
    cBtn.TextSize=mob and 13 or 12; cBtn.Font=Enum.Font.GothamBold; cBtn.BorderSizePixel=0; cBtn.AutoButtonColor=false
    Instance.new("UICorner",cBtn).CornerRadius=UDim.new(0,10)
    local joinF=Instance.new("Frame",ctrl)
    joinF.Size=UDim2.new(1,0,0,IN_H+4); joinF.BackgroundColor3=Color3.fromRGB(13,10,32); joinF.BorderSizePixel=0
    Instance.new("UICorner",joinF).CornerRadius=UDim.new(0,10); Instance.new("UIStroke",joinF).Color=Color3.fromRGB(78,46,162)
    local codeBox2=Instance.new("TextBox",joinF); codeBox2.PlaceholderText="Código da sala..."; codeBox2.Text=""
    codeBox2.Size=UDim2.new(1,-(IN_H+16),1,0); codeBox2.Position=UDim2.new(0,10,0,0)
    codeBox2.BackgroundTransparency=1; codeBox2.TextColor3=Color3.fromRGB(220,210,255)
    codeBox2.PlaceholderColor3=Color3.fromRGB(78,64,128); codeBox2.TextSize=FSZ
    codeBox2.Font=Enum.Font.Gotham; codeBox2.TextXAlignment=Enum.TextXAlignment.Left; codeBox2.ClearTextOnFocus=false
    local jBtn=Instance.new("TextButton",joinF)
    jBtn.Text=">>>"; jBtn.Size=UDim2.new(0,IN_H-2,0,IN_H-4); jBtn.Position=UDim2.new(1,-(IN_H+4),0.5,-(IN_H-4)/2)
    jBtn.BackgroundColor3=Color3.fromRGB(26,112,52); jBtn.TextColor3=Color3.new(1,1,1)
    jBtn.TextSize=mob and 18 or 16; jBtn.Font=Enum.Font.GothamBold; jBtn.BorderSizePixel=0; jBtn.AutoButtonColor=false
    Instance.new("UICorner",jBtn).CornerRadius=UDim.new(0,8)
    cBtn.MouseButton1Click:Connect(function()
        cBtn.Text="⏳ Criando..."; cBtn.Active=false
        task.spawn(function()
            local code=mkCode(); fbPut("/rooms/"..code.."/info.json",{c=MYNAME,uid=MYUID,ts=os.time()})
            ctrl:Destroy(); startPrivateRoom(code,true)
        end)
    end)
    local function doJoin()
        local code=codeBox2.Text:upper():gsub("%s",""); if #code<4 then sysMsg("privado","⚠️ Código inválido!"); return end
        jBtn.Text="⏳"; jBtn.Active=false
        task.spawn(function()
            local info=fbGet("/rooms/"..code.."/info.json")
            if info and type(info)=="table" and info.c then ctrl:Destroy(); startPrivateRoom(code,false)
            else jBtn.Text=">>>"; jBtn.Active=true; sysMsg("privado","❌ Sala não encontrada!") end
        end)
    end
    jBtn.MouseButton1Click:Connect(doJoin)
    codeBox2.FocusLost:Connect(function(e) if e then doJoin() end end)
end)

-- ══════════════════════════════════════════════════════════
-- DEBUG
-- ══════════════════════════════════════════════════════════
local function runDiag()
    sysMsg("debug","🔍 Iniciando diagnóstico..."); task.wait(0.1)
    addMsg("debug","HTTP","Função: "..httpName,0,nil,false)
    if not httpFn and not useHttpSvc then sysMsg("debug","❌ Sem HTTP! Ative rede no executor."); return end
    sysMsg("debug","📡 Testando Firebase...")
    local res=doRequest({Url=FIREBASE_URL.."/ping.json",Method="GET"})
    if not res then sysMsg("debug","❌ Sem resposta do Firebase!"); return end
    local code2=tostring(res.StatusCode or "?"); local body2=tostring(res.Body or "")
    if body2:find("Permission denied") or code2=="401" then
        sysMsg("debug","❌ Firebase bloqueado! Vá em Regras → read/write: true"); return
    end
    if code2=="200" or res.Success then sysMsg("debug","✅ Firebase OK!")
    else sysMsg("debug","⚠️ HTTP "..code2.." | "..body2:sub(1,50)) end
end
task.defer(function()
    task.wait(0.5)
    sysMsg("debug","Executor: "..httpName); sysMsg("debug","Pressione o botão para testar.")
    local p=panels["debug"]; if not p then return end
    local db=Instance.new("TextButton",p.frame)
    db.Text="🔍 Testar Conexão"; db.Size=UDim2.new(1,-8,0,40); db.Position=UDim2.new(0,4,1,-45)
    db.BackgroundColor3=Color3.fromRGB(30,115,50); db.TextColor3=Color3.new(1,1,1)
    db.TextSize=mob and 13 or 12; db.Font=Enum.Font.GothamBold; db.BorderSizePixel=0; db.AutoButtonColor=false
    Instance.new("UICorner",db).CornerRadius=UDim.new(0,10)
    db.MouseButton1Click:Connect(function()
        db.Text="Testando..."; db.BackgroundColor3=Color3.fromRGB(18,78,35)
        task.spawn(function() runDiag(); task.wait(2.5); db.Text="🔍 Testar Conexão"; db.BackgroundColor3=Color3.fromRGB(30,115,50) end)
    end)
end)

-- ══════════════════════════════════════════════════════════
-- ARRASTAR JANELA
-- ══════════════════════════════════════════════════════════
do
    local drag,ds,dp=false,nil,nil
    TBar.InputBegan:Connect(function(i)
        if i.UserInputType==Enum.UserInputType.MouseButton1 or i.UserInputType==Enum.UserInputType.Touch then
            drag=true; ds=i.Position; dp=Main.Position
        end
    end)
    TBar.InputEnded:Connect(function(i)
        if i.UserInputType==Enum.UserInputType.MouseButton1 or i.UserInputType==Enum.UserInputType.Touch then drag=false end
    end)
    UIS.InputChanged:Connect(function(i)
        if drag and (i.UserInputType==Enum.UserInputType.MouseMovement or i.UserInputType==Enum.UserInputType.Touch) then
            local d=i.Position-ds; Main.Position=UDim2.new(dp.X.Scale,dp.X.Offset+d.X,dp.Y.Scale,dp.Y.Offset+d.Y)
        end
    end)
end

-- ══════════════════════════════════════════════════════════
-- MINIMIZAR / FECHAR
-- ══════════════════════════════════════════════════════════
local savedPos=Main.Position
MinBtn.MouseButton1Click:Connect(function()
    minimized=not minimized
    if minimized then
        savedPos=Main.Position
        Tween:Create(Main,TweenInfo.new(0.28,Enum.EasingStyle.Quart,Enum.EasingDirection.In),{Size=UDim2.new(0,0,0,0)}):Play()
        task.delay(0.28,function()
            Main.Visible=false; unreadCount=0; Bubble.Visible=true
            Bubble.Size=UDim2.new(0,0,0,0)
            Tween:Create(Bubble,TweenInfo.new(0.32,Enum.EasingStyle.Back,Enum.EasingDirection.Out),{Size=UDim2.new(0,54,0,54)}):Play()
        end)
    else
        Bubble.Visible=false; Main.Visible=true; Main.Position=savedPos; Main.Size=UDim2.new(0,0,0,0)
        MinBtn.Text="−"
        Tween:Create(Main,TweenInfo.new(0.35,Enum.EasingStyle.Back,Enum.EasingDirection.Out),{Size=UDim2.new(0,WIN_W,0,WIN_H)}):Play()
    end
    MinBtn.Text=minimized and "□" or "−"
end)
CloseBtn.MouseButton1Click:Connect(function()
    task.spawn(function() fbDel("/presence/"..myKey..".json") end)
    Tween:Create(Main,TweenInfo.new(0.22,Enum.EasingStyle.Back,Enum.EasingDirection.In),{Size=UDim2.new(0,0,0,0)}):Play()
    Bubble.Visible=false; task.delay(0.25,function() SG:Destroy() end)
end)

-- ══════════════════════════════════════════════════════════
-- AGE GATE (com botões de faixa etária)
-- ══════════════════════════════════════════════════════════
local function openMainChat()
    Main.Visible=true; Main.Size=UDim2.new(0,0,0,0)
    task.delay(0.05,function()
        Tween:Create(Main,TweenInfo.new(0.42,Enum.EasingStyle.Back,Enum.EasingDirection.Out),{Size=UDim2.new(0,WIN_W,0,WIN_H)}):Play()
    end)
    switchTab("local")
end

do
    local overlay=Instance.new("Frame",SG)
    overlay.Size=UDim2.new(1,0,1,0); overlay.BackgroundColor3=Color3.fromRGB(0,0,0)
    overlay.BackgroundTransparency=0.35; overlay.BorderSizePixel=0; overlay.ZIndex=50

    local CARD_W=mob and math.min(math.floor(vp.X*0.86),360) or 360
    local CARD_H=mob and 310 or 290
    local card=Instance.new("Frame",SG)
    card.AnchorPoint=Vector2.new(0.5,0.5); card.Position=UDim2.new(0.5,0,0.5,0)
    card.Size=UDim2.new(0,0,0,0); card.BackgroundColor3=Color3.fromRGB(9,7,22)
    card.BorderSizePixel=0; card.ZIndex=51; card.ClipsDescendants=true
    Instance.new("UICorner",card).CornerRadius=UDim.new(0,16)
    local cSt=Instance.new("UIStroke",card); cSt.Color=Color3.fromRGB(88,52,205); cSt.Thickness=1.8
    Instance.new("UIGradient",card).Color=ColorSequence.new({
        ColorSequenceKeypoint.new(0,Color3.fromRGB(16,11,38)),
        ColorSequenceKeypoint.new(1,Color3.fromRGB(8,6,20))
    })
    task.delay(0.1,function()
        Tween:Create(card,TweenInfo.new(0.45,Enum.EasingStyle.Back,Enum.EasingDirection.Out),{Size=UDim2.new(0,CARD_W,0,CARD_H)}):Play()
    end)

    local ico=Instance.new("TextLabel",card); ico.Size=UDim2.new(1,0,0,mob and 52 or 46)
    ico.Position=UDim2.new(0,0,0,mob and 18 or 14); ico.BackgroundTransparency=1
    ico.Text="🔞"; ico.TextSize=mob and 36 or 30; ico.Font=Enum.Font.GothamBold; ico.ZIndex=52

    local ttl=Instance.new("TextLabel",card); ttl.Size=UDim2.new(1,-24,0,mob and 28 or 24)
    ttl.Position=UDim2.new(0,12,0,mob and 68 or 58); ttl.BackgroundTransparency=1
    ttl.Text="Qual é a sua idade?"; ttl.TextColor3=Color3.fromRGB(228,218,255)
    ttl.TextSize=mob and 18 or 16; ttl.Font=Enum.Font.GothamBold; ttl.ZIndex=52

    local sub=Instance.new("TextLabel",card); sub.Size=UDim2.new(1,-28,0,0); sub.AutomaticSize=Enum.AutomaticSize.Y
    sub.Position=UDim2.new(0,14,0,mob and 100 or 88); sub.BackgroundTransparency=1
    sub.Text="ℹ️  Isso não afetará seu chat.\nVocê poderá conversar com quem quiser."
    sub.TextColor3=Color3.fromRGB(120,108,185); sub.TextSize=mob and 12 or 11; sub.Font=Enum.Font.Gotham
    sub.TextWrapped=true; sub.TextXAlignment=Enum.TextXAlignment.Center; sub.ZIndex=52

    -- Input de idade numérica
    local inputF = Instance.new("Frame", card)
    inputF.Size = UDim2.new(0, CARD_W-32, 0, mob and 46 or 42)
    inputF.Position = UDim2.new(0, 16, 0, mob and 158 or 142)
    inputF.BackgroundColor3 = Color3.fromRGB(18,14,42); inputF.BorderSizePixel = 0; inputF.ZIndex = 53
    Instance.new("UICorner", inputF).CornerRadius = UDim.new(0, 10)
    local iSt2 = Instance.new("UIStroke", inputF); iSt2.Color = Color3.fromRGB(88,52,205); iSt2.Thickness = 1.5

    local ageBox = Instance.new("TextBox", inputF)
    ageBox.PlaceholderText = "Digite sua idade (ex: 16)"
    ageBox.Text = ""; ageBox.Size = UDim2.new(1, -(mob and 58 or 52), 1, 0)
    ageBox.Position = UDim2.new(0, 12, 0, 0)
    ageBox.BackgroundTransparency = 1; ageBox.TextColor3 = Color3.fromRGB(225,215,255)
    ageBox.PlaceholderColor3 = Color3.fromRGB(90,78,148)
    ageBox.TextSize = mob and 17 or 15; ageBox.Font = Enum.Font.GothamBold
    ageBox.TextXAlignment = Enum.TextXAlignment.Left; ageBox.ClearTextOnFocus = false
    ageBox.ZIndex = 54
    ageBox.TextEditable = true

    local confirmBtn = Instance.new("TextButton", inputF)
    confirmBtn.Text = "OK"; confirmBtn.Size = UDim2.new(0, mob and 48 or 42, 0, (mob and 46 or 42)-10)
    confirmBtn.Position = UDim2.new(1, -(mob and 54 or 48), 0.5, -((mob and 46 or 42)-10)/2)
    confirmBtn.BackgroundColor3 = Color3.fromRGB(85,50,205); confirmBtn.TextColor3 = Color3.new(1,1,1)
    confirmBtn.TextSize = mob and 14 or 13; confirmBtn.Font = Enum.Font.GothamBold
    confirmBtn.BorderSizePixel = 0; confirmBtn.AutoButtonColor = false; confirmBtn.ZIndex = 54
    Instance.new("UICorner", confirmBtn).CornerRadius = UDim.new(0, 8)

    local errLbl = Instance.new("TextLabel", card)
    errLbl.Size = UDim2.new(0, CARD_W-32, 0, 20); errLbl.Position = UDim2.new(0, 16, 0, mob and 208 or 190)
    errLbl.BackgroundTransparency = 1; errLbl.TextColor3 = Color3.fromRGB(255,100,100)
    errLbl.TextSize = mob and 12 or 11; errLbl.Font = Enum.Font.Gotham
    errLbl.TextXAlignment = Enum.TextXAlignment.Center; errLbl.Name = "ErrLbl"; errLbl.Text = ""; errLbl.ZIndex = 53

    local function confirm()
        local v = tonumber(ageBox.Text)
        if not v or v < 1 or v > 120 then
            errLbl.Text = "Digite um numero valido (ex: 16)"
            Tween:Create(inputF, TweenInfo.new(0.05), {Position=UDim2.new(0,20,0,mob and 158 or 142)}):Play()
            task.wait(0.05)
            Tween:Create(inputF, TweenInfo.new(0.05), {Position=UDim2.new(0,12,0,mob and 158 or 142)}):Play()
            task.wait(0.05)
            Tween:Create(inputF, TweenInfo.new(0.05), {Position=UDim2.new(0,16,0,mob and 158 or 142)}):Play()
            return
        end
        -- determina grupo
        MY_AGE_NUM = v
        if v < 13 then MY_AGE_GROUP = "child"
        elseif v < 18 then MY_AGE_GROUP = "teen"
        else MY_AGE_GROUP = "adult" end

        Tween:Create(card,TweenInfo.new(0.28,Enum.EasingStyle.Quart,Enum.EasingDirection.In),{Size=UDim2.new(0,0,0,0)}):Play()
        Tween:Create(overlay,TweenInfo.new(0.28),{BackgroundTransparency=1}):Play()
        task.delay(0.32, function() card:Destroy(); overlay:Destroy(); openMainChat() end)
    end

    confirmBtn.MouseButton1Click:Connect(confirm)
    ageBox.FocusLost:Connect(function(enter) if enter then confirm() end end)
    task.delay(0.5, function() pcall(function() ageBox:CaptureFocus() end) end)
end

print("[GlobalChatHub v4] ✅ | "..MYNAME.." | HTTP: "..httpName)
