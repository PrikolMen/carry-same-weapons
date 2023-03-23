local addonName = 'Carry Same Weapons!'

local weapons = weapons
local table = table
local hook = hook
local net = net

local timer_Simple = timer.Simple
local ents_Create = ents.Create
local IsValid = IsValid

module( 'carry_same_weapons', package.seeall )

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

    swep.__ClassName = newClassName
    function swep:GetClass()
        return className
    end

    swep.DisableDuplicator = true
    swep.Spawnable = false

    weapons.Register( swep, newClassName )

    return true
end

Weapons = {}
BlackList = {
    ['gmod_tool'] = true
}

if SERVER then

    util.AddNetworkString( addonName )

    local playerGive = {}
    Itrations = {}

    hook.Add( 'OnEntityCreated', addonName, function( ent )
        if not ent:IsWeapon() then return end
        if not ent:IsScripted() then return end
        if ent[ addonName ] then return end

        local className = ent:GetClass()
        if BlackList[ className ] then return end

        timer_Simple( 0, function()
            if not IsValid( ent ) then return end

            local count = Itrations[ className ] or 0
            Itrations[ className ] = count + 1

            local newClassName = className .. '_i' .. count
            if not CopySWEP( newClassName, className ) then return end
            Weapons[ newClassName ] = className

            net.Start( addonName )
                net.WriteString( newClassName )
                net.WriteString( className )
            net.Broadcast()

            local pos = ent:GetPos()
            local ang = ent:GetAngles()
            local color = ent:GetColor()
            local skinNumber = ent:GetSkin()
            local velocity = ent:GetVelocity()
            local material = ent:GetMaterial()

            local index = ent:EntIndex()

            ent:Remove()

            timer_Simple( 0.25, function()
                ent = ents_Create( newClassName )
                if not IsValid( ent ) then return end

                ent:SetPos( pos )
                ent:SetAngles( ang )
                ent:SetColor( color )
                ent:SetSkin( skinNumber )
                ent:SetVelocity( velocity )
                ent:SetMaterial( material )

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

    local realClassName = ent.__ClassName
    local className = ent:GetClass()

    timer_Simple( 0, function()
        if IsValid( ent ) then return end

        local swep = weapons.GetStored( realClassName )
        if not swep then return end
        table.Empty( swep )

        if CLIENT then return end
        Weapons[ realClassName ] = nil

        local count = Itrations[ className ]
        if not count then return end
        count = count - 1

        if ( count < 0 ) then
            count = 0
        end

        Itrations[ className ] = count
    end )
end )