vault {
  address = "https://knox.io.nrs.gov.bc.ca"
  renew_token = true
  vault_agent_token_file = "/config/token/.vault-token"
  unwrap_token = true
  retry {
    enabled = true
    attempts = 12
    backoff = "250ms"
    max_backoff = "1m"
  }
}

secret {
    no_prefix = true
    path = "apps/dev/nodejs-sample/nodejs-sample/proxy-account-ready-only"
}

exec {
  splay = "0s"
  env {
    pristine = false
  }
  kill_timeout = "5s"
}
