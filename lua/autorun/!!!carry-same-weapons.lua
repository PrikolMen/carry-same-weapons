local addonName = "Carry Same Weapons"
module( addonName, package.seeall )
local classNameBase = "csww"

local getClassNameAlias
do

    local pattern = "^" .. classNameBase .. "_%d+_(.+)$"
    local string_match = string.match

    function getClassNameAlias( className )
        return string_match( className, pattern )
    end

end

local isCustomClass
do

    local pattern2 = "^" .. classNameBase .. "_%d+_.+$"
    local string_find = string.find

    function isCustomClass( className )
        return string_find( className, pattern2 ) ~= nil
    end

end

local WEAPON = FindMetaTable( "Weapon" )
local ENTITY = FindMetaTable( "Entity" )
local PLAYER = FindMetaTable( "Player" )
local NPC = FindMetaTable( "NPC" )
local NULL = NULL

local ENTITY_GetClass = ENTITY.GetClass

local function getClass( entity )
    local className = ENTITY_GetClass( entity )

    local alias = getClassNameAlias( className )
    if alias ~= nil then
        return alias
    end

    return className
end

WEAPON.GetClass = getClass

do

    local ipairs = ipairs

    local function getWeapon( ply, requiredClassName )
        for _, weapon in ipairs( ply:GetWeapons() ) do
            local className = ENTITY_GetClass( weapon )
            if className == requiredClassName then
                return weapon
            end

            if not isCustomClass( className ) then continue end

            local alias = getClassNameAlias( className )
            if alias and alias == requiredClassName then
                return weapon
            end
        end

        return NULL
    end

    PLAYER.GetWeapon = getWeapon

    function PLAYER:HasWeapon( className )
        return getWeapon( self, className ):IsValid()
    end

    if SERVER then
        NPC.GetWeapon = getWeapon

        local selectWeapon = PLAYER_SelectWeapon
        if not selectWeapon then
            selectWeapon = PLAYER.SelectWeapon
            PLAYER_SelectWeapon = selectWeapon
        end

        function PLAYER:SelectWeapon( className )
            local weapon = getWeapon( self, className )
            if not weapon:IsValid() then return end
            return selectWeapon( self, ENTITY_GetClass( weapon ) )
        end

        function PLAYER:DropNamedWeapon( className, ... )
            local weapon = getWeapon( self, className )
            if not weapon:IsValid() then return end
            return self:DropWeapon( weapon, ... )
        end
    end

end

do
    local entIndex = ENTITY.EntIndex
    function WEAPON:__tostring()
        return "Weapon [" .. entIndex( self ) .. "][" .. getClass( self ) .. "]"
    end
end

local weapons_GetStored = weapons.GetStored
local weapons_Register = weapons.Register
local list_Set = list.Set
local hook_Add = hook.Add

if SERVER then

    local classNames = ClassNames
    if not classNames then
        classNames = {}
        ClassNames = classNames
    end

    local string_format = string.format
    local pattern3 = "%s_%d_%s"

    local function newClass( className )
        local metatable = weapons_GetStored( className )
        if not metatable then return end

        local classes = classNames[ className ]
        if not classes then
            classes = {}
            classNames[ className ] = classes
        end

        local index = #classes + 1
        className = string_format( pattern3, classNameBase, index, className )
        classes[ index ] = className

        weapons_Register( metatable, className )
        list_Set( "Weapon", className, nil )
        return className
    end

    local create = ents_Create
    if not create then
        create = ents.Create
        ents_Create = create
    end

    function ents.Create( className )
        if not isCustomClass( className ) then
            local newClassName = newClass( className )
            if newClassName then
                className = newClassName
            end
        end

        return create( className )
    end

    local function createWeapon( className )
        local weapon = create( className )
        if weapon and weapon:IsValid() then
            weapon:Spawn()
            weapon:Activate()
            return weapon
        end

        return NULL
    end

    local function give( entity, className, noAmmo )
        if not isCustomClass( className ) then
            local newClassName = newClass( className )
            if newClassName then
                className = newClassName
            end
        end

        local weapon = createWeapon( className )
        if not weapon:IsValid() then
            return weapon
        end

        if noAmmo then
            weapon:SetClip1( 0 )
            weapon:SetClip2( 0 )
        end

        entity:PickupWeapon( weapon )
        return weapon
    end

    PLAYER.Give = give
    NPC.Give = give

    local timer_Simple = timer.Simple

    hook_Add( "OnEntityCreated", addonName, function( weapon )
        if not weapon:IsWeapon() or not weapon:IsScripted() then return end

        local className = ENTITY_GetClass( weapon )
        if isCustomClass( className ) then return end

        timer_Simple( 0, function()
            if not weapon:IsValid() then return end

            local owner = weapon:GetOwner()
            if owner:IsValid() then
                if not owner:Alive() then return end
                local entity = owner:Give( className, not owner:HasWeapon( className ) )
                if not entity:IsValid() then return end
            else

                local newClassName = newClass( className )
                if not newClassName then return end

                local entity = createWeapon( newClassName )
                if not entity:IsValid() then return end

                entity:SetAngles( weapon:GetAngles() )
                entity:SetPos( weapon:GetPos() )

                -- Properties Factory
                entity:SetCollisionGroup( weapon:GetCollisionGroup() )
                entity:SetMoveType( weapon:GetMoveType() )
                entity:SetNoDraw( weapon:GetNoDraw() )
                entity:SetColor( weapon:GetColor() )

                for physNum = 0, entity:GetPhysicsObjectCount() - 1 do
                    local newPhys = entity:GetPhysicsObjectNum( physNum )
                    if not newPhys or not newPhys:IsValid() then continue end

                    local oldPhys = weapon:GetPhysicsObjectNum( physNum )
                    if not oldPhys or not oldPhys:IsValid() then continue end

                    newPhys:EnableCollisions( oldPhys:IsCollisionEnabled() )
                    newPhys:EnableMotion( oldPhys:IsMotionEnabled() )
                    newPhys:EnableDrag( oldPhys:IsDragEnabled() )
                    newPhys:SetMass( oldPhys:GetMass() )

                    if oldPhys:IsAsleep() then
                        newPhys:Sleep()
                    else
                        newPhys:Wake()
                    end

                    newPhys:SetVelocity( oldPhys:GetVelocity() )
                end

            end

            weapon:Remove()
        end )
    end )

    local table_RemoveByValue = table.RemoveByValue
    local table_IsEmpty = table.IsEmpty

    hook_Add( "EntityRemoved", addonName, function( weapon, fullUpdate )
        if fullUpdate or not weapon:IsWeapon() or not weapon:IsScripted() then return end

        local className = ENTITY_GetClass( weapon )
        if not isCustomClass( className ) then return end

        local alias = getClassNameAlias( className )
        if not alias then return end

        local classes = classNames[ alias ]
        if not classes then return end
        table_RemoveByValue( classes, className )
        if table_IsEmpty( classes ) then
            classNames[ alias ] = nil
        end
    end )

    hook.Add( "PlayerGiveSWEP", addonName, function( ply, className, swep )
        if isCustomClass( className ) then return end
        className = newClass( className )
        if not className then return end
        swep.ClassName = className
    end )

    hook.Add( "PlayerSpawnSWEP", addonName, function( ply, className, swep )
        if isCustomClass( className ) then return end
        className = newClass( className )
        if not className then return end
        swep.ClassName = className
    end )

end

if CLIENT then

    hook_Add( "OnEntityCreated", addonName, function( weapon )
        if not weapon:IsWeapon() or not weapon:IsScripted() then return end

        local className = ENTITY_GetClass( weapon )
        if not isCustomClass( className ) then return end

        local alias = getClassNameAlias( className )
        if not alias then return end

        local metatable = weapons_GetStored( alias )
        if not metatable then return end

        weapons_Register( metatable, className )
        list_Set( "Weapon", className, nil )
    end )

end

hook_Add( "PreRegisterSWEP", addonName, function( metatable, className )
    if not isCustomClass( className ) then return end
    metatable.DisableDuplicator = true
    metatable.ClassNameOverride = nil
end )