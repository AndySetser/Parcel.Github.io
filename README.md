# Parcel — Alamosa County Data Pipeline

A small R pipeline for pulling real property data into the Parcel project,
starting with RentCast's API. Same shape as the `kansas_lema_econ` project:
raw pulls cached locally, cleaned into a flat analysis-ready file.

## One-time setup

1. **Get a RentCast API key** at https://www.rentcast.io/api (free tier, no
   card required, 50 calls/month).

2. **Store the key locally — never in this repo.** Open `~/.Renviron`:
   ```bash
   nano ~/.Renviron
   ```
   Add this line, save, then restart R/RStudio:
   ```
   RENTCAST_API_KEY=your_actual_key_here
   ```

3. **Protect the repo** so the key can never get committed by accident:
   ```bash
   echo ".Renviron" >> .gitignore
   ```

4. **Install R packages** (one time):
   ```r
   install.packages(c("httr", "jsonlite", "dplyr", "purrr", "tibble"))
   ```

## Workflow

```
R/01_fetch_rentcast.R   # calls the API, caches raw JSON per address
R/02_clean_rentcast.R   # combines cached JSON into one clean CSV
```

Run in that order. `01_fetch_rentcast.R` is cache-aware — it will never
re-call the API for an address it's already pulled, so you can add new
addresses to the list and re-run safely without burning quota on old ones.

Every call made (successful or not) is logged to
`data/raw/rentcast/_cache_log.csv` so you always know exactly how much of
your monthly quota has been used and on what.

## Adding addresses

Edit the `addresses` tibble near the top of `01_fetch_rentcast.R`. Given the
50-call/month free-tier ceiling, add addresses in small deliberate batches
rather than all at once — e.g. 10–15 at a time.

## Output

`data/processed/alamosa_properties.csv` — one row per property, columns for
address, beds/baths, sqft, lot size, year built, last sale price/date, and
property type. This is the file that eventually feeds both:
- the R-side market analysis, and
- the Parcel site's listing data (as JSON once you're ready to wire it in).

## What's NOT in this pipeline

Current for-sale inventory (live listings) isn't pulled here — RentCast's
`/properties` endpoint returns property *records*, not active MLS listings.
The plan for actual listings is owner-submission (sellers post their own
home, verified against this same property-record data) rather than scraping
a third-party listing site, which would violate those sites' terms of use.
