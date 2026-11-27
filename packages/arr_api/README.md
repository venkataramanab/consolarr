# arr_api

Hand-written, tolerant clients for Sonarr (and shared Radarr types).

Endpoints used (Sonarr v3 API, tolerant of v4; from Sonarr's public API docs):

- `GET api/v3/system/status`, `qualityprofile`, `rootfolder`, `tag`, `POST tag`
- `GET api/v3/series`, `GET/PUT series/{id}` (`moveFiles=false`), `POST series`,
  `GET series/lookup?term=`, `GET languageprofile` (v3 only; absent in v4)
- `GET api/v3/episode?seriesId=&includeEpisodeFile=true`, `PUT episode/monitor`
- `GET api/v3/calendar`, `GET wanted/missing`, `GET wanted/cutoff`
- `GET api/v3/queue`, `DELETE queue/{id}` (`removeFromClient`, `blocklist` and
  `blacklist`, `skipRedownload`)
- `POST api/v3/command`, `GET command/{id}`
- `GET api/v3/release`, `POST release`

The API key travels only in the `X-Api-Key` header, never in a URL.
