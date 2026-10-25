BBReady=false
BBLocks={}
function BBInt(n,a,b) return type(n)=='number' and n%1==0 and n>=a and n<=b end
function BBNear(src,target,radius)
    local a,b=GetPlayerPed(src),GetPlayerPed(target)
    return a~=0 and b~=0 and GetPlayerRoutingBucket(src)==GetPlayerRoutingBucket(target)
        and #(GetEntityCoords(a)-GetEntityCoords(b))<=(radius or 5)
end
function BBAt(src,locations,radius)
    local p=GetPlayerPed(src)
    if p==0 then return false end
    for _,v in ipairs(locations) do if #(GetEntityCoords(p)-v.coords)<=(radius or 10) then return true end end
    return false
end
function BBEntity(info)
    if not info then return end
    return info.source and GetPlayerPed(info.source) or (info.netId and NetworkGetEntityFromNetworkId(info.netId))
end
function BBValidData(src,data,bail)
    return type(data)=='table' and BBInt(data.source,1,65535) and BBNear(src,data.source,5)
        and BBInt(bail and data.penalty or data.reward,0,Config.BailOfficers.maximumBailAmount)
        and (not bail or BBInt(data.length,1,Config.BailOfficers.maximumBailLength))
        and BBInt(data.sentence or 0,0,Config.BailOfficers.maximumSentence or 1440)
        and (data.description==nil or type(data.description)=='string' and #data.description<=2000)
        and (data.image==nil or type(data.image)=='string' and #data.image<=255)
end
function BBView(src,event,identifier)
    local p=GetPlayerPermissions(src)
    if p.bailManage or p.bailPlacement then return true end
    if identifier and GetIdentifier(src)==identifier then return true end
    local action=event:match('([^:]+)$') or event
    return not action:lower():find('bail') and BountyHunters and BountyHunters[src]~=nil
end
function BBBroadcast(event,identifier,...)
    for _,id in ipairs(GetPlayers()) do
        local src=tonumber(id)
        if BBView(src,event,identifier) then TriggerClientEvent(event,src,identifier,...) end
    end
end
function BBPay(identifier,amount,key)
    local receipt='payment:'..key
    local raw=GetResourceKvpString(receipt)
    if raw=='done' or raw=='paying' then return raw=='done' end
    local src=GetSourceFromIdentifier(identifier)
    if not src then SetResourceKvp(receipt,json.encode({identifier=identifier,amount=amount})); return false end
    SetResourceKvp(receipt,'paying')
    local ok,result=pcall(AddMoney,src,amount)
    if ok and result==true then SetResourceKvp(receipt,'done'); return true end
    SetResourceKvp(receipt,json.encode({identifier=identifier,amount=amount}))
    return false
end
-- Pending records can be retried; ambiguous 'paying' receipts require operator reconciliation.
function BBRecover(src)
    local identifier=GetIdentifier(src)
    local issuedRaw=GetResourceKvpString('issued:'..identifier)
    if issuedRaw then
        local ok,issued=pcall(json.decode,issuedRaw)
        if ok and type(issued)=='table' then
            local remaining={}
            for _,item in ipairs(issued) do
                local remove=item.kind=='weapon' and Inventory.RemoveWeapon or Inventory.RemoveItem
                if remove(src,item.name,item.count)~=true then remaining[#remaining+1]=item end
            end
            if #remaining==0 then DeleteResourceKvp('issued:'..identifier)
            else SetResourceKvp('issued:'..identifier,json.encode(remaining)) end
        end
    end
    local iterator=StartFindKvp('payment:')
    while true do
        local key=FindKvp(iterator)
        if not key then break end
        local ok,data=pcall(json.decode,GetResourceKvpString(key) or '')
        if ok and type(data)=='table' and data.identifier==identifier then BBPay(identifier,data.amount,key:sub(9)) end
    end
    EndFindKvp(iterator)
end
function BBClearSession(src)
    for id,b in pairs(BountyRegistry or {}) do
        if b.bountyHunter==src then CancelBounty(id) end
        if b.source==src then b.source=nil end
    end
    if BountyHunters then BountyHunters[src]=nil end
    BBParole[src]=nil
end
AddEventHandler('esx:playerLogout',function(src) BBClearSession(src or source) end)
AddEventHandler('QBCore:Server:OnPlayerUnload',function(src) BBClearSession(src or source) end)
local register=RegisterNetEvent
local rates={}
RegisterNetEvent=function(name,handler)
    if type(handler)~='function' then return register(name,handler) end
    register(name,function(...)
        local src=source
        if not BBReady or not GetPlayerName(src) then return end
        local key=src..':'..name; local now=GetGameTimer()
        if rates[key] and now-rates[key]<250 then return end
        rates[key]=now
        local duty=BountyHunters and BountyHunters[src]
        if duty and duty.identifier~=GetIdentifier(src) then BountyHunters[src]=nil; return end
        handler(...)
    end)
end
AddEventHandler('playerDropped',function()
    local prefix=source..':'
    for key in pairs(rates) do if key:sub(1,#prefix)==prefix then rates[key]=nil end end
end)

function BBExecute(query,params,callback)
    local rows=MySQL.Sync.execute(query,params)
    if type(rows)~='number' or rows<1 then error('Bail/bounty persistence failed') end
    if callback then callback(rows) end
    return rows
end
function BBConvertBail(id)
    local b=BailRegistry[id]
    if not b or BBLocks[id] then return false end
    BBLocks[id]=true
    local ok=MySQL.Sync.transaction({
        'INSERT INTO pickle_bailbounty_bounties (target,targetname,image,issuer,reward,description,sentence) SELECT identifier,name,image,issuer,reward,description,sentence FROM pickle_bailbounty_bail WHERE identifier=@id',
        'DELETE FROM pickle_bailbounty_bail WHERE identifier=@id',
    },{['@id']=id})
    if ok then
        BailRegistry[id]=nil
        BBBroadcast('pickle_bailbounty:removebail',id,GetSourceFromIdentifier(id))
        AddBountyToRegistry({target=id,targetname=b.name,image=b.image,issuer=b.issuer,reward=b.reward,description=b.description,sentence=b.sentence},false,false)
    end
    BBLocks[id]=nil
    return ok
end
BBParole={}
RegisterCallback('pickle_bailbounty:beginParole',function(src,cb)
    local id=GetIdentifier(src); local bail=BailRegistry[id]
    if not bail or os.time()>bail.nextcompliance or not DoesBailRequireCheckIn(bail)
        or not BBAt(src,Config.Bail.paroleOfficers,10) then cb(false); return end
    local index=math.random(1,#Config.Bail.paroleMissions)
    local cfg=Config.Bail.paroleMissions[index]
    BBParole[src]={identity=id,period=bail.nextcompliance,index=index,progress=0,points={},required=math.min(cfg.pointsRequired,#cfg.points),last=GetGameTimer()}
    cb(index)
end)
RegisterNetEvent('pickle_bailbounty:parolePoint',function(point)
    local src=source; local mission=BBParole[src]
    if not mission or mission.identity~=GetIdentifier(src) or os.time()>mission.period then return end
    local cfg=Config.Bail.paroleMissions[mission.index]
    if not BBInt(point,1,#cfg.points) or mission.points[point] or GetGameTimer()-mission.last<600 then return end
    if #(GetEntityCoords(GetPlayerPed(src))-cfg.points[point].coords)>3 then return end
    mission.points[point]=true; mission.progress=mission.progress+1; mission.last=GetGameTimer()
end)
