# ghost-blogs

Everything that isn't content for the two Ghost blogs on my DigitalOcean box:
the theme, the deployment scripts, and the server configs.

| | |
|---|---|
| [chaijiaxun.com](https://chaijiaxun.com) | `maptian` theme, port 3711, volume `ghost_content` |
| [travellingdevman.com](https://travellingdevman.com) | stock theme, port 1337, volume `travellingdevman_content` |

Both run `ghost:5` in Docker on the same host.

```
maptian/      the Ghost theme for chaijiaxun.com
deployment/   scripts that run against the server
config/       templates for the configs that live on the server
```

**No credentials are in this repo, and none ever should be** — it's public. The
`config/` directory holds templates with placeholder values; the filled-in
versions live at `/root/ghost-config/` on the server and are gitignored by
pattern. See [Configuration](#configuration).

## Theme

`maptian/` is the theme for chaijiaxun.com, based on
[ghostium](https://github.com/oswaldoacauan/ghostium). It stays named `maptian`
because that's its `package.json` name and the directory Ghost has it activated
from (`content/themes/maptian`) — renaming it would mean a redeploy and a
re-activation in Ghost admin.

### Deploying a theme change

```bash
./deployment/deploy-theme.sh
```

Validates with `gscan`, rsyncs into the volume, fixes ownership, restarts Ghost
and waits for the site to come back. The restart is required: Ghost compiles
`.hbs` at boot, and the `?v=` asset hash only changes on restart.

### Colours

The palette is a set of CSS custom properties at the top of
`maptian/assets/css/theme-code.css`. Change those variables, not the rules
underneath — everything else reads from them.

`--rail-x` is shared by the nav rail and the author rail so the vertical line
down the left gutter stays aligned. Don't hardcode either offset.

### Gotchas

- **Don't run Prettier over `.hbs` files.** It reflows inline `<script>` blocks
  and turns `// ...` comment tails into executable code. This silently broke
  Disqus on every post. `.prettierignore` covers `*.hbs` — keep it that way.
- **`ghost:5` is pinned on purpose.** Ghost runs irreversible database
  migrations on the first boot of a new major version. Back up before going to
  Ghost 6.
- jQuery is self-hosted at `maptian/assets/js/jquery-3.7.1.min.js`.
  `jquery.event.move.js` is patched for jQuery 3 (it used `jQuery.event.props`,
  removed in 3.0).

## Backups

Off-site to [Tigris](https://www.tigrisdata.com/). One script serves both blogs,
namespaced by site, so they share a bucket without colliding.

Scripts live at `/root/ghost-backup/` on the server — copies of the ones in
`deployment/`. Re-copy after changing anything here.

### Layout in the bucket

```
<site>/daily/YYYY-MM-DD.tar.gz     database + settings + themes + redirects
<site>/weekly/YYYY-MM-DD.tar.gz    one per ISO week, kept forever
<site>/images/...                  mirror of content/images, upload-only
```

**Why it's split in two.** For chaijiaxun the database is ~3 MB and changes
constantly, while the images are ~317 MB and are immutable — Ghost writes
`content/images/YYYY/MM/file.png` once and never touches it again. One combined
tarball would re-upload the same 317 MB every week forever (~16 GB/year of
near-identical copies). Split, each image is stored once and kept forever, while
the part that actually changes gets real point-in-time snapshots. A daily
tarball is ~2 MB for chaijiaxun and ~4 MB for travellingdevman.

The trade-off: a restore needs **both halves**. `restore-from-tigris.sh` does
that for you.

Logs are excluded — 126 MB of noise on chaijiaxun, and not content.

### Two rules worth not breaking

**Every object key is a pure function of (site, date).** Re-running a day is an
idempotent overwrite, never a duplicate, which is what makes "upload succeeded
but the script died before pruning" recoverable rather than a mess. Don't add a
timestamp, run id or random suffix.

**A weekly is the first success of its ISO week, not a fixed weekday.** With an
anchor day, one failed night — server down, credentials rotated, disk full —
means the week gets no weekly at all, and its daily is pruned days later.
Long-term retention would be lost silently and discovered months afterwards. The
bucket is the source of truth for "does this week have one yet", not any local
state file, so it survives a server rebuild.

Dailies are pruned past `BACKUP_RETENTION_DAYS`. Weeklies and images are never
deleted. Pruning refuses to run if the clock looks wrong, or if it would remove
more than 60% of the dailies at once, and it runs last so a prune failure can
never fail the backup.

### Usage

```bash
/root/ghost-backup/backup-to-tigris.sh chaijiaxun --check     # validate config
/root/ghost-backup/backup-to-tigris.sh chaijiaxun --dry-run   # no writes
/root/ghost-backup/backup-to-tigris.sh chaijiaxun             # for real

/root/ghost-backup/restore-from-tigris.sh chaijiaxun --list
/root/ghost-backup/restore-from-tigris.sh chaijiaxun weekly/2026-08-24
```

Backups take **no downtime** — `sqlite3 .backup` snapshots the live database.
Restores stop the container.

### Cron

Installed and running:

```
10 4 * * * /root/ghost-backup/backup-to-tigris.sh chaijiaxun        >> /var/log/ghost-backup/backup.log 2>&1
40 4 * * * /root/ghost-backup/backup-to-tigris.sh travellingdevman  >> /var/log/ghost-backup/backup.log 2>&1
```

Staggered so the two never contend; each also takes a per-site `flock`.

Logs go to `/var/log/ghost-backup/backup.log`, rotated weekly by
`/etc/logrotate.d/ghost-backup` (8 weeks, compressed). The dedicated directory
is deliberate — logrotate refuses to rotate anything directly in `/var/log` on
this box, because that directory is group-writable by `syslog`.

To stop the backups: `crontab -e` and delete the two lines.

## Configuration

Everything in `config/` is a **template**. The real files live on the server:

| Template | Server path |
|---|---|
| `config/backup.env.example` | `/root/ghost-config/backup.env` |
| `config/backup.chaijiaxun.env.example` | `/root/ghost-config/backup.chaijiaxun.env` |
| `config/backup.travellingdevman.env.example` | `/root/ghost-config/backup.travellingdevman.env` |
| `config/config.production.json.example` | `/root/ghost-config/config.production.json` |
| `config/routes/chaijiaxun.routes.yaml` | `ghost_content` volume → `settings/routes.yaml` |
| `config/routes/travellingdevman.routes.yaml` | `travellingdevman_content` volume → `settings/routes.yaml` |

The backup env files must be mode `600` — the scripts refuse to read a
world-readable credentials file. Credentials reach rclone through the
environment, so nothing is ever written to an `rclone.conf` on disk.

**Ghost's config is bind-mounted from outside the content volume.** It's what
sets the port and holds the SMTP credentials; without that mount Ghost falls
back to port 2368 and the port mapping silently stops working.

**`routes.yaml` is not part of the theme.** It lives in the content volume and
is what puts chaijiaxun's post collection under `/blog/` with a static homepage.
Editing routes in Ghost admin overwrites the volume's copy, so the versions here
have to be kept in sync by hand.

## Scripts

| | |
|---|---|
| `deployment/deploy-theme.sh` | validate, sync and restart — the one you'll use |
| `deployment/backup-to-tigris.sh` | off-site backup, one site per invocation |
| `deployment/restore-from-tigris.sh` | restore a snapshot plus the image mirror |
| `deployment/run-prod.sh` | create the chaijiaxun container from scratch |

## Server requirements

`rclone` and `sqlite3` on the host:

```bash
apt-get install -y rclone sqlite3
```

## History

This repo was `j3x1/maptian`, a theme repo named after the theme. It's now
`cjx3711/ghost-blogs` and covers both blogs. The `maptian` theme still lives here
under its original name.

The `jiajin` branch has the old "Maptian Design" theme for Jia Jin's blog, which
is no longer used. Its licensed retail fonts (Feijoa, Ideal Sans) were removed
from `master` — they shouldn't have been served publicly from a live site.

## Copyright & License

Copyright (c) 2026 Pixel Rife — Released under the [MIT license](maptian/LICENSE).
