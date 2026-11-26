import Boot from "../src/App/Boot.q"
import Store from "../src/Docs/Store.q"
import Registry, Options from "../src/Registry/Registry.q"

--" `qlang run tools/import-index.q -- ../qlang/packages.json`: puts the packages of an index file (the `packages.json` of the qlang repository) in the
registry, as listed, waiting for the worker to read them. A repository that is already there is left alone; the name comes from its `qlang.toml` once read. Safe to run again. --"
let args = env.args()
if args.len() < 1 then
    panic("usage: qlang run tools/import-index.q -- <packages.json>")
end
let boot = Boot.start()
let registry = Registry.new(Store.new(boot.db), Options { submissions_open: false, hosts: [] })
let index = Json.to<map<string, Json>>(Json.parse(fs.read(args[0]).unwrap()).unwrap()).unwrap()
let added = 0
for name in index.keys() do
    let entry = index[name].unwrap()
    let made = registry.add(entry.get("git").unwrap().as_string(), none)
    if made.is_err() then
        print("skipped {name}: {made.unwrap_err()}")
    else
        added = added + 1
    end
end
print("imported {added} package(s)")
