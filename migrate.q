import "@std/web/migrate.q" as migrate
import Boot from "./src/App/Boot.q"
import all_migrations from "./src/App/Schema.q"

--" `qlang run migrate.q`: makes the tables that are missing. Safe to run again. --"
let boot = Boot.start()
let applied = migrate.Migrator.new(boot.db).run(all_migrations())
if applied.is_err() then
    panic("the migration failed: {applied.unwrap_err().message}")
end
for id in applied.unwrap() do
    print("applied {id}")
end
print("the database is up to date")
