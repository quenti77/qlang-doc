--" What the program reads from its environment. Nothing is written here: a secret never lives in the code. --"
struct Config
    public database_url: string
    public session_secret: string
    public secure_cookies: bool
    public submissions_open: bool
    public views_dir: string
end

impl Config
    --" Reads the environment, or says what is missing. --"
    public fun from_env() -> Result<Config, Error>
        let url = env.get("DOC_DATABASE_URL")
        if url == none then
            return Err(Error { message: "DOC_DATABASE_URL is not set (postgres://user:password@host/database)" })
        end
        let secret = env.get("DOC_SESSION_SECRET")
        if secret == none or secret.len() < 32 then
            return Err(Error { message: "DOC_SESSION_SECRET must be set, with at least 32 characters" })
        end
        Ok(Config {
            database_url: url,
            session_secret: secret,
            secure_cookies: env.get("DOC_SECURE_COOKIES") == "1",
            submissions_open: env.get("DOC_SUBMISSIONS") == "open",
            views_dir: env.get("DOC_VIEWS_DIR") ?? "views",
        })
    end
end

export Config
