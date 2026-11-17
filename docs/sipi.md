# SIPI (IIIF image server)

Both stacks run the same pinned tag: **`daschswiss/sipi:v10.0.0`**.

- `compose.yaml` (`image_server`) is beta/production and mounts `sipi-config/`.
- `backend/compose.yaml` is local dev + CI and uses the image's stock config,
  with a dev-only `SIPI_JWTKEY` so v10 agrees to start (see below).

Bump both files in the same change. Dev and CI should never test a different
major than production serves.

## Upgrading

1. Read the `BREAKING CHANGES` sections of
   [the upstream changelog](https://github.com/dasch-swiss/sipi/blob/main/CHANGELOG.md)
   for every release you skip. Check them against `sipi-config/*.lua`.
2. Smoke-test the production config under the production user before you
   deploy. Run the new tag with `--user 14:50`, mount `sipi-config/` as
   `compose.yaml` does, and request `info.json`, a region/size tile and a
   `full/max` render of a `.jp2`, `.jpg` and `.tif` through the `/sipi` prefix.
   `info.json` alone proves nothing, because it returns 200 on files whose
   pixels SIPI cannot decode.
3. Check the startup log. It should show no deprecated-key warnings and no
   `caching disabled`, and it should log `Created cache directory: /tmp/sipi-cache`.
4. Also start it once *without* `SIPI_JWT_SECRET`: the startup guards of new
   majors are where upgrades break, and a smoke test that always passes a
   secret will not see them.
5. Bump the backend dev compose first. Run the backend tests and `tests_e2e`,
   then bump production and open a few manuscripts on beta.

To roll back, revert the tag. `sipi.config.lua` loads and serves images on
v5.0.1 through v10.0.0, but v5 does not recognise the renamed `cache_dir` /
`cache_size` keys, so it runs uncached again (as it always did).

## Config notes

- **JWT secret (v10+).** SIPI v10 refuses to start if `jwt_secret` is empty,
  shorter than 32 bytes, or the stock demo value (`refusing startup — jwt_secret
  ...; set SIPI_JWTKEY`). Set `SIPI_JWT_SECRET` (42 characters) in `env_file`.
  If it is unset, `sipi.config.lua` falls back to a random per-boot secret
  rather than the public demo one, so SIPI still starts. Nothing uses SIPI JWTs
  (no Lua routes), so a changing secret is harmless. The `SIPI_JWTKEY`
  environment variable, if set, overrides the config value.

- **Cache.** `cache_dir` is `/tmp/sipi-cache`. The image's `/sipi/cache` is
  root-owned, so the `14:50` user cannot write there. Before this was fixed,
  production SIPI silently ran with caching disabled. Restart the container
  to clear the cache: the v10 image no longer has an `/api/cache` endpoint.
- **Routes.** The config defines no Lua routes (`routes = {}`). nginx still
  denies `/sipi/api/*` as defence in depth.
- **Lua sandbox (v10+).** Lua scripts may use only `os.getenv`, `os.clock` and
  `os.date`, plus a whitelisted stdlib (no `io`/`debug`). `config.adminuser`
  and `config.password` are gone. `env_or()` in the config uses only
  `os.getenv`. The `admin` table is now inert.
- **Admission control (v10+).** The default is the "advanced" tier, which can
  answer 503/413 to very large requests. A 12000×9000 `full/max` JP2 render
  passed in testing. If real manuscripts trip it, set
  `SIPI_ADMISSION_MODE=basic` on `image_server`.

## Licensing

SIPI is AGPL-3.0, the same licence as this repository, `backend` and
`frontend`. It was AGPL-3.0 at every tag from v5.0.1 to v10.0.0, so upgrading
does not change our obligations. We run the unmodified upstream image. The
only SIPI-derived files we ship are `sipi-config/*.lua`, which are AGPL-3.0 and
keep their upstream copyright headers. The image links Kakadu (JPEG 2000) under
DaSCH's licence, and SIPI's AGPL §7 additional permission covers that. We pull
the image and do not redistribute it, so that permission is not needed here.
v8 and later added Rust dependencies (`jsonwebtoken`, `opentelemetry`, …).
These are MIT/Apache-2.0, which are compatible with AGPL-3.0.
