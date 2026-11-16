local app = require("impl/app")

function PluginShutdown()
    app.Stop()
end

app.Start()
