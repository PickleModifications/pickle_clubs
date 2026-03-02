-- Society entity: server-side registration (minimal, no per-entity state)

CreateThread(function()
    RegisterEntityType("society", {
        label = "Society",
        description = "Society deposit/withdraw interaction point.",
        onStart = function(id, entityId)
            -- No per-entity server state needed
        end,
        onRender = function(id, entityId, source)
        end,
        onUnrender = function(id, entityId, source)
        end,
        onStop = function(id, entityId)
        end,
    })
end)
