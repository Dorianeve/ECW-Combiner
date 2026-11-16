# Configuration loading ----

#' Load and validate the pipeline configuration
#'
#' Reads a YAML file and injects secrets from environment variables, so
#' credentials never live in the config file.
#'
#' @param path Path to the YAML config. Defaults to `$COMBINER_CONFIG` or
#'   `config/config.yml`.
#' @param check_source_dir If TRUE, fail when `paths$source_dir` does not exist.
#' @return A named list.
load_config <- function(path = Sys.getenv("COMBINER_CONFIG", "config/config.yml"),
                        check_source_dir = TRUE) {
  if (!file.exists(path)) {
    stop("Config file not found: ", path,
         "\nCopy config/config.example.yml to config/config.yml and edit it.",
         call. = FALSE)
  }
  cfg <- yaml::read_yaml(path)

  required <- list(
    c("paths", "source_dir"), c("paths", "cache_dir"), c("paths", "output_dir"),
    c("source", "file_patterns"), c("tables")
  )
  for (key in required) {
    if (is.null(purrr::pluck(cfg, !!!as.list(key)))) {
      stop("Missing config entry: ", paste(key, collapse = "$"), call. = FALSE)
    }
  }

  if (check_source_dir && !dir.exists(cfg$paths$source_dir)) {
    stop("paths$source_dir does not exist: ", cfg$paths$source_dir,
         "\nIf this is Google Drive for Desktop, check the drive is mounted and ",
         "folders are set to 'Mirror files'.", call. = FALSE)
  }

  assert_config_paths_safe(cfg)   # never write below the source folder

  # GMS_USER/GMS_PASSWORD env vars take priority; fall back to gms$user/gms$password
  # in config.yml (also git-ignored) if set there instead.
  env_user     <- Sys.getenv("GMS_USER", unset = NA_character_)
  env_password <- Sys.getenv("GMS_PASSWORD", unset = NA_character_)
  cfg$gms$user     <- if (!is.na(env_user)) env_user else cfg$gms$user %||% NA_character_
  cfg$gms$password <- if (!is.na(env_password)) env_password else cfg$gms$password %||% NA_character_
  cfg
}

#' Resolve the number of parallel workers from config
resolve_workers <- function(cfg) {
  par <- cfg$parallel
  if (is.null(par) || isFALSE(par$enabled)) return(1L)
  w <- par$workers
  if (is.null(w) || identical(w, "auto")) {
    return(as.integer(max(1, min(future::availableCores() - 1, 6))))
  }
  as.integer(max(1, w))
}
