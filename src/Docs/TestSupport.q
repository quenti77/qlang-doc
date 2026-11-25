import "@std/web/migrate.q" as migrate
import all_migrations from "../App/Schema.q"
import Store from "./Store.q"
import Docs from "./Docs.q"

--" A documentation over an empty test database (`make test-db` makes it): the tables are dropped and made again. --"
fun fresh_db() -> Db
    let url = env.get("DOC_TEST_DATABASE_URL")
    if url == none then
        panic("DOC_TEST_DATABASE_URL is not set: run the tests with `make test`")
    end
    let db = Db.connect(url).unwrap()
    db.execute("DROP SCHEMA public CASCADE", []).unwrap()
    db.execute("CREATE SCHEMA public", []).unwrap()
    migrate.Migrator.new(db).run(all_migrations()).unwrap()
    db
end

fun fresh_docs() -> Docs
    Docs.new(Store.new(fresh_db()))
end

export fresh_db, fresh_docs
