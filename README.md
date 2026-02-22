# n8n-storage

Render free instance for n8n with Telegram-only database backups.

## What this setup does
- Restores `database.sqlite` from the pinned Telegram manifest on cold start.
- Creates compressed chunked DB backups and uploads them to your Telegram channel.
- Keeps only a small local manifest history to avoid disk growth.
- Runs n8n with aggressive execution-pruning defaults in `render.yaml`.

## Important reality check
No setup can provide truly "unlimited" lifetime storage/performance on Render free.
This repo minimizes storage usage and recovers state reliably, but platform limits still apply.
