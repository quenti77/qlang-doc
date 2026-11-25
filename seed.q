import Boot from "./src/App/Boot.q"
import Store from "./src/Docs/Store.q"
import Docs from "./src/Docs/Docs.q"

--" `qlang run seed.q`: makes the first administrator from DOC_ADMIN_LOGIN and DOC_ADMIN_PASSWORD, when there is no account yet. Safe to run again. --"
let boot = Boot.start()
let docs = Docs.new(Store.new(boot.db))
if docs.store.count_accounts() > 0 then
    print("there is already an account: nothing to do")
else
    let login = env.get("DOC_ADMIN_LOGIN") ?? "admin"
    let password = env.get("DOC_ADMIN_PASSWORD")
    if password == none then
        panic("DOC_ADMIN_PASSWORD is not set (at least 12 characters)")
    end
    let made = docs.create_account(login, password, "admin", none)
    if made.is_err() then
        panic(made.unwrap_err())
    end
    print("administrator {login} created")
end
