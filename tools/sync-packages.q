import Boot from "../src/App/Boot.q"
import Store from "../src/Docs/Store.q"
import Registry, Options from "../src/Registry/Registry.q"
import GitSource from "../src/Registry/GitSource.q"

--" `qlang run --allow-process tools/sync-packages.q`: reads the git repositories of the listed packages that asked for it (a webhook, the panel,
a new approval) or that were not read for six hours. Run it every few minutes (a systemd timer, cron): it is the only part of the site that
runs `git`, so that the web server never has to. Gives one line per package. --"
let boot = Boot.start()
let registry = Registry.new(Store.new(boot.db), Options { submissions_open: false, hosts: [] })
let six_hours = 6 * 3600 * 1000
let lines = registry.sync_due(GitSource.https().source(), six_hours, 20)
for line in lines do
    print(line)
end
if lines.is_empty() then
    print("nothing to read")
end
