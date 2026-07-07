# ==============================================================================
# 01_fetch_rentcast.R
# Pulls property records from the RentCast API for a list of Alamosa County
# addresses and writes the raw JSON responses + a combined CSV to disk.
#
# SETUP (one-time, do this before running):
#   1. Add your key to ~/.Renviron (NOT to this script, NOT to the repo):
#        RENTCAST_API_KEY=your_actual_key_here
#   2. Restart R / RStudio so the environment variable loads.
#   3. Add ".Renviron" to your .gitignore if it isn't already.
#
# FREE TIER NOTE:
#   RentCast's free plan = 50 calls/month. This script is written to burn
#   calls deliberately and cautiously: it checks a local cache before hitting
#   the API, so re-running the script never re-charges you for an address
#   you've already pulled.
# ==============================================================================

library(httr)
library(jsonlite)
library(dplyr)
library(purrr)

# ---- Config ------------------------------------------------------------------

RENTCAST_API_KEY <- Sys.getenv("RENTCAST_API_KEY")

if (identical(RENTCAST_API_KEY, "")) {
  stop(
    "RENTCAST_API_KEY not found. Add it to ~/.Renviron as:\n",
    "  RENTCAST_API_KEY=your_key_here\n",
    "then restart R."
  )
}

BASE_URL   <- "https://api.rentcast.io/v1/properties"
RAW_DIR    <- "data/raw/rentcast"
CACHE_FILE <- file.path(RAW_DIR, "_cache_log.csv")

dir.create(RAW_DIR, recursive = TRUE, showWarnings = FALSE)

# ---- Address list --------------------------------------------------------
# Start small and deliberate given the 50-call/month ceiling.
# Fill this in with real Alamosa County addresses as you're ready to spend
# calls on them. One row = one API call (on first pull; cached after that).

addresses <- tibble::tibble(
  address = c(
    "123 Example St, Alamosa, CO 81101"
    # add more addresses here, one per line
  )
)

# ---- Helpers ---------------------------------------------------------------

# Turn an address into a safe filename for local caching
address_to_filename <- function(addr) {
  clean <- gsub("[^A-Za-z0-9]+", "_", addr)
  paste0(clean, ".json")
}

# Has this address already been pulled? (avoids burning free-tier calls twice)
already_cached <- function(addr) {
  file.exists(file.path(RAW_DIR, address_to_filename(addr)))
}

# Single API call for one address, with basic error handling
fetch_property <- function(addr) {

  if (already_cached(addr)) {
    message("Cached, skipping API call: ", addr)
    return(invisible(NULL))
  }

  message("Fetching from RentCast: ", addr)

  resp <- GET(
    url = BASE_URL,
    query = list(address = addr),
    add_headers(
      "X-Api-Key" = RENTCAST_API_KEY,
      "Accept"    = "application/json"
    )
  )

  status <- status_code(resp)

  if (status == 200) {
    content_raw <- content(resp, as = "text", encoding = "UTF-8")
    writeLines(content_raw, file.path(RAW_DIR, address_to_filename(addr)))
    log_call(addr, status, "ok")
  } else if (status == 401) {
    stop("401 Unauthorized — check that RENTCAST_API_KEY is correct and active.")
  } else if (status == 429) {
    warning("429 Rate limited / quota exceeded for: ", addr,
            " — stopping here so we don't waste further calls this month.")
    log_call(addr, status, "quota_exceeded")
    return(invisible("STOP"))
  } else {
    warning("Unexpected status ", status, " for: ", addr)
    log_call(addr, status, "error")
  }

  Sys.sleep(1)  # be polite, avoid hammering the API
  invisible(NULL)
}

# Keep a running log of every call made, so you always know exactly how much
# of your monthly quota has been spent and on what.
log_call <- function(addr, status, result) {
  entry <- tibble::tibble(
    timestamp = as.character(Sys.time()),
    address   = addr,
    status    = status,
    result    = result
  )
  if (file.exists(CACHE_FILE)) {
    write.table(entry, CACHE_FILE, sep = ",", append = TRUE,
                row.names = FALSE, col.names = FALSE)
  } else {
    write.csv(entry, CACHE_FILE, row.names = FALSE)
  }
}

# ---- Run ---------------------------------------------------------------------
# Uses a for-loop (not purrr::map) on purpose, so it's easy to eyeball
# progress and stop early if you see quota warnings.

for (addr in addresses$address) {
  result <- fetch_property(addr)
  if (identical(result, "STOP")) break
}

message("Done. Check ", CACHE_FILE, " to see exactly how many calls were used.")
