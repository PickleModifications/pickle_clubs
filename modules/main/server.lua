Clubs = {}

function RegisterClub(data, skipSync)
    Clubs[data.id] = {
        label = data.label,
        description = data.description,
        coords = data.coords,
        entities = data.entities,
    }
    if not skipSync then
        TriggerClientEvent("pickle_clubs:syncClubs", -1, Clubs)
    end
end

RegisterNetEvent("pickle_clubs:initializePlayer", function()
    local src = source
    TriggerClientEvent("pickle_clubs:syncClubs", src, Clubs)
end)

CreateThread(function()
    -- Simulated Club pre-database setup
    RegisterClub({
        id = 67,
        label = "Vanilla Unicorn",
        description = "The Vanilla Unicorn is a club that serves alcohol and music.",
        coords = vector3(119.1173, -1289.0688, 28.2532),
        entities = {
            ["abc-123456"] = {
                type = "club_entry",
                doors = {
                    {coords = vector3(119.1173, -1289.0688, 28.2532), heading = 211.4423, model = `prop_strip_door_01`},
                },
                bouncer = {
                    ped = "bouncer_1",
                    coords = vector3(127.9870, -1299.3616, 28.2327), 
                    heading = 210.3588
                },
                line = {
                    coords = vector3(129.5437, -1299.7993, 28.2327),
                    heading = 29.7786
                }
            }
        }
    }, true)
end)