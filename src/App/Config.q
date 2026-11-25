--" What the program reads from its environment. Nothing is written here: a secret never lives in the code. --"
struct Config
    public database_url: string
    public session_secret: string
    public secure_cookies: bool
    public submissions_open: bool
    public views_dir: string
    public git_hosts: array<string>
    public hook_secret: string
    public base_url: string
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
            git_hosts: (env.get("DOC_GIT_HOSTS") ?? "github.com,gitlab.com,codeberg.org").split(",").map(fun(h: string) -> string h.trim().lower() end).filter(fun(h: string) -> bool h != "" end),
            hook_secret: env.get("DOC_HOOK_SECRET") ?? "",
            base_url: (env.get("DOC_BASE_URL") ?? "http://127.0.0.1:8082").trim(),
        })
    end
end

export Config
