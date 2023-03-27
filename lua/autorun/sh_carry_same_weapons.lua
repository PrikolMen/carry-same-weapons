local addonName = 'Carry Same Weapons!'

local weapons = weapons
local table = table
local hook = hook
local net = net

local timer_Simple = timer.Simple
local ents_Create = ents.Create
local IsValid = IsValid

module( 'carry_same_weapons', package.seeall )

local ENTITY = FindMetaTable( 'Entity' )

-- I tried to do it differently, but the meta-call dominates the object's meta-table.
ENTITY.__GetClass = ENTITY.__GetClass or ENTITY.GetClass
function ENTITY:GetClass()
    if self[ addonName ] then
        local className = self.__ClassName
        if ( className ~= nil ) then
            return className
        end
    end

    return self:__GetClass()
end

function CopySWEP( newClassName, className )
    local data = weapons.GetStored( className )
    if not data then return false end

    local swep = {
        [ 'Base' ] = className,
        [ addonName ] = true
    }

    for key, value in pairs( data ) do
        swep[ key ] = value
    end

    swep.__RealClassName = newClassName
    swep.__ClassName = className

    swep.DisableDuplicator = true
    swep.Spawnable = false

    weapons.Register( swep, newClassName )

    return true
end

if SERVER then

    ExperimentalMode = false
    BlackList = {
        ['gmod_tool'] = true
    }

    function WriteConfig()
        file.Write( 'carry_same_weapons.json', util.TableToJSON( {
            ['ExperimentalMode'] = ExperimentalMode,
            ['BlackList'] = BlackList
        }, true ) )
    end

    function ReadConfig()
        if file.Exists( 'carry_same_weapons.json', 'DATA' ) then
            local json = file.Read( 'carry_same_weapons.json', 'DATA' )
            if ( json ~= nil ) then
                local tbl = util.JSONToTable( json )
                if ( tbl ~= nil ) then
                    return tbl
                end
            end
        end

        WriteConfig()
    end

    local config = ReadConfig()
    if ( config ~= nil ) then
        ExperimentalMode = tobool( config.ExperimentalMode )
        local blackList = config.BlackList
        if ( blackList ~= nil ) then
            table.Merge( BlackList, blackList )
        end
    end

    util.AddNetworkString( addonName )

    local playerGive = {}
    Itrations = {}
    Weapons = {}

    local function copyDataTable( destination, source )
        for key, value in pairs( source ) do
            if ( value == NULL ) then continue end
            if ( IsEntity( value ) or ispanel( value ) ) and not IsValid( value ) then continue end
            if isfunction( value ) then continue end

            local dValue = destination[ key ]
            if ( dValue ~= nil ) and istable( value ) and istable( dValue ) then
                copyDataTable( dValue, value )
                continue
            end
        end
    end

    hook.Add( 'OnEntityCreated', addonName, function( ent )
        if not ent:IsWeapon() then return end
        if not ent:IsScripted() then return end
        if ent[ addonName ] then return end

        local className = ent:GetClass()
        if BlackList[ className ] then return end

        timer_Simple( 0, function()
            if not IsValid( ent ) then return end

            local itration = Itrations[ className ] or 0
            Itrations[ className ] = itration + 1

            local newClassName = className .. '_iter' .. itration
            if not CopySWEP( newClassName, className ) then return end
            Weapons[ newClassName ] = className

            net.Start( addonName )
                net.WriteString( newClassName )
                net.WriteString( className )
            net.Broadcast()

            local pos = ent:GetPos()
            local ang = ent:GetAngles()
            local color = ent:GetColor()
            local index = ent:EntIndex()
            local model = ent:GetModel()
            local skinNumber = ent:GetSkin()
            local velocity = ent:GetVelocity()
            local material = ent:GetMaterial()
            local flexScale = ent:GetFlexScale()

            local flexes = {}
            for flex = 1, ent:GetFlexNum() do
                flexes[ flex ] = ent:GetFlexWeight( flex )
            end

            local bodygroups = {}
            for _, bodygroup in ipairs( ent:GetBodyGroups() ) do
                bodygroups[ #bodygroups + 1 ] = { bodygroup.id, ent:GetBodygroup( bodygroup.id ) }
            end

            local dataTable = nil
            if ExperimentalMode then
                dataTable = ent:GetTable()
            end

            ent:Remove()

            timer_Simple( 0.25, function()
                ent = ents_Create( newClassName )
                if not IsValid( ent ) then return end

                ent:SetPos( pos )
                ent:SetAngles( ang )
                ent:SetColor( color )
                ent:SetModel( model )
                ent:SetSkin( skinNumber )
                ent:SetVelocity( velocity )
                ent:SetMaterial( material )
                ent:SetFlexScale( flexScale )

                for flex = 1, ent:GetFlexNum() do
                    local flexWeight = flexes[ flex ]
                    if not flexWeight then continue end
                    ent:SetFlexWeight( flexWeight )
                end

                for _, bodygroup in ipairs( bodygroups ) do
                    ent:SetBodygroup( bodygroup[ 1 ], bodygroup[ 2 ] )
                end

                if ExperimentalMode then
                    copyDataTable( ent:GetTable(), dataTable )
                end

                ent:Spawn()
                ent:Activate()

                local ply = playerGive[ index ]
                if IsValid( ply ) then
                    ply:PickupWeapon( ent )

                    timer_Simple( 0.25, function()
                        if not IsValid( ply ) then return end
                        if not IsValid( ent ) then return end
                        ply:SelectWeapon( ent )
                    end )
                end

                playerGive[ index ] = nil
            end )
        end )
    end )

    hook.Add( 'PlayerCanPickupWeapon', addonName, function( ply, wep, lock )
        if wep[ addonName ] then return end
        if lock then return end

        local canPickup = hook.Run( 'PlayerCanPickupWeapon', ply, wep, true )
        if not canPickup then return end

        playerGive[ wep:EntIndex() ] = ply
    end )

    local queue = {}
    hook.Add( 'PlayerInitialSpawn', addonName, function( ply )
        queue[ ply ] = true
    end)

    hook.Add( 'SetupMove', addonName, function( ply, _, cmd )
        if queue[ ply ] and not cmd:IsForced() then
            queue[ ply ] = nil

            for newClassName, className in pairs( Weapons ) do
                net.Start( addonName )
                    net.WriteString( newClassName )
                    net.WriteString( className )
                net.Broadcast()
            end
        end
    end)

end

if CLIENT then

    net.Receive( addonName, function()
        CopySWEP( net.ReadString(), net.ReadString() )
    end )

end

hook.Add( 'EntityRemoved', addonName, function( ent )
    if not ent:IsWeapon() then return end
    if not ent[ addonName ] then return end

    local realClassName = ent.__RealClassName
    local className = ent:GetClass()

    timer_Simple( 0, function()
        if IsValid( ent ) then return end

        local swep = weapons.GetStored( realClassName )
        if not swep then return end
        table.Empty( swep )

        if CLIENT then return end
        Weapons[ realClassName ] = nil

        local itration = Itrations[ className ]
        if not itration then return end
        itration = itration - 1

        if ( itration < 0 ) then
            itration = 0
        end

        Itrations[ className ] = itration
    end )
end )