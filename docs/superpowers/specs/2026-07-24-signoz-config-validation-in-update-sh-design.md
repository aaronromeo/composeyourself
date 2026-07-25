# SigNoz Compose Config Validation in update.sh

**Date:** 2026-07-24

## Problem

The OTEL deployment plan (Task 4) included a `docker compose config` pre-flight check to catch bad YAML or missing env vars before the expensive `build --no-cache` step. This was run manually during initial deploy but was never integrated into `update.sh`. Without it, a broken compose config or missing `.env` var would only surface after the full rebuild cycle.

## Decision

Add a `docker compose $COMPOSE_FILES config` validation step to `update.sh`, placed between `generate_config.sh` and `docker compose down`.

## Design

### What

Insert 3 lines into `update.sh` after `./generate_config.sh` (line 77) and before the "Rebuild and restart" block (line 80):

```bash
# Validate compose config (catches bad YAML / missing env vars before the expensive build)
echo -e "${YELLOW}⚙️ Validating compose configuration...${NC}"
docker compose $COMPOSE_FILES config > /dev/null && echo -e "${GREEN}✅ Config OK${NC}" || { echo -e "${RED}❌ Config validation failed${NC}"; exit 1; }
```

### Why here

- After `generate_config.sh` — the config generation may create files the compose config references
- Before `docker compose down` — fail fast before the expensive rebuild cycle
- Only runs when git changes exist (early-exit on line 64 prevents this from running on no-change updates)

### Behavior

- **Success**: prints `✅ Config OK`, proceeds to rebuild
- **Failure**: prints `❌ Config validation failed`, exits with code 1 (set -e would catch this anyway, but the explicit message is clearer)
- **Output**: rendered config goes to `/dev/null` — no need to persist the rendered file for recurring updates
- **Host-agnostic**: runs for both rocketman and sweetpaintedlady (validation is harmless for both)

## Trade-offs

| Option | Pros | Cons |
|--------|------|------|
| A. Always validate (this design) | Catches errors early, cheap operation | Extra 2-3 seconds on updates |
| B. Validate only on rocketman | No overhead for sweetpaintedlady | sweetpaintedlady gets no protection |
| C. No validation | Zero overhead | Errors surface late in the build |

Chose A: `docker compose config` is fast (~1-2s) and the validation is universally useful.

## Files Modified

- `update.sh` — insert 3 lines after line 77
