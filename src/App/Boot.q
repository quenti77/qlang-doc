import Config from "./Config.q"

--" The configuration and the database, or the program stops saying why: `main.q` and `migrate.q` start the same way. --"
struct Boot
    public config: Config
    public db: Db
end

impl Boot
    public fun start() -> Boot
        let config = Config.from_env()
        if config.is_err() then
            panic(config.unwrap_err().message)
        end
        let db = Db.connect(config.unwrap().database_url)
        if db.is_err() then
            panic(db.unwrap_err().message)
        end
        Boot { config: config.unwrap(), db: db.unwrap() }
    end
end

export Boot
