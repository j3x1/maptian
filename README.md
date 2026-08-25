# Blog Theme and Deployment Scripts

The Ghost theme and deployment scripts behind [chaijiaxun.com](https://chaijiaxun.com).

## Deployment

The blog runs in a Docker container named **`ghost-blog`** on `ghost:5`, listening on
port **3711**. Content (the SQLite database and uploaded images) lives in a Docker
volume called **`ghost_content`**.

Ghost's config is **not** in the volume — it is bind-mounted from
`/root/ghost-config/config.production.json` on the host. That file is what sets the
port to 3711 and holds the SMTP credentials, so it must be mounted or Ghost falls
back to port 2368 and the port mapping stops working. It is deliberately not in this
repo because it contains secrets.

### Deploying a theme change

From the repo root, on your laptop:

```bash
./deployment/deploy-theme.sh
```

This validates the theme with `gscan`, rsyncs it into the volume, fixes ownership,
restarts Ghost and waits for the site to come back. A restart is required — Ghost
compiles `.hbs` templates at boot, and the `?v=` asset hash only changes on restart.

### Scripts

- `deployment/deploy-theme.sh` — validate, sync and restart (the one you'll use)
- `deployment/run-prod.sh` — create the container from scratch
- `deployment/backup-volume.sh` — back up the `ghost_content` volume
- `deployment/restore-volume.sh` — restore it

### Backups

There is currently **no automated backup**. `backup-volume.sh` has to be run by
hand, and nothing is scheduled on the server. The blog's SQLite database and all
uploaded images live in a single Docker volume, so this is the biggest outstanding
risk on the box — worth revisiting.

## Theme

Structure is based on the [ghostium](https://github.com/oswaldoacauan/ghostium) theme.

### Routing

Set in Ghost's `routes.yaml`, not in this repo:

- `/` → the `home` page, rendered with `index.hbs`
- `/blog/` → the post collection, rendered with `page-blog.hbs`
- `/blog/topic/{slug}/` → tags
- `/blog/author/{slug}/` → authors
- RSS lives at `/blog/rss/`

### Colours

The palette is a set of CSS custom properties at the top of
`maptian/assets/css/theme-code.css`. Change those variables rather than the rules
underneath them — everything else reads from them.

`--rail-x` is shared by the nav rail and the author rail so the vertical line down
the left gutter stays aligned; don't hardcode either offset.

### Features

- [Twenty Twenty](https://zurb.com/playground/twentytwenty) for comparison images
- Reading-time estimate and a scroll progress bar
- Disqus comments

### Gotchas

- **Don't run Prettier over `.hbs` files.** It reflows inline `<script>` blocks and
  turns `// ...` comment tails into executable code. This silently broke Disqus for
  a long time. `.prettierignore` covers `*.hbs` — keep it that way.
- **`ghost:5` is pinned on purpose.** Ghost runs irreversible database migrations on
  the first boot of a new major version. Back up before upgrading to Ghost 6.
- jQuery is self-hosted at `assets/js/jquery-3.7.1.min.js`. `jquery.event.move.js`
  is patched for jQuery 3 (it used `jQuery.event.props`, removed in 3.0).

## Branches

### master

Custom blog theme for Jia Xun's personal blog. Ported to Ghost 5.

### Maptian Design

Custom theme for Jia Jin's personal blog. No longer used; its assets were removed
from `master` (they included licensed retail fonts that shouldn't have been served
publicly). See the `jiajin` branch if you need the history.

## Copyright & License

Copyright (c) 2026 Pixel Rife — Released under the [MIT license](LICENSE).
