.PHONY: help init-submodules sync-submodules update-submodules submodule-status

help:
	@echo "Submodule management targets:"
	@echo ""
	@echo "  make init-submodules    Initial clone helper (init + recursive update)"
	@echo "  make sync-submodules    Sync submodules to the commits pinned by this repo"
	@echo "  make update-submodules  Bump submodules to latest upstream main (use intentionally)"
	@echo "  make submodule-status   Show current submodule commits and status"
	@echo ""

# First-time setup after cloning without --recurse-submodules.
init-submodules:
	git submodule update --init --recursive

# Bring working tree submodule contents in line with the commits this superproject pins.
# Safe to run any time; this is what 'update.sh' already does at deploy time.
sync-submodules:
	git submodule sync --recursive
	git submodule update --init --recursive

# Advance each submodule to the latest commit on its tracked branch (main, per .gitmodules)
# and stage the new pointer commits. Review with 'git diff --staged' before committing.
update-submodules:
	git submodule sync --recursive
	git submodule update --init --remote --merge --recursive
	git add services/announcements services/swole services/yt-dlp
	@echo ""
	@echo "Submodules advanced to latest upstream main. Staged pointer changes:"
	@git diff --staged --submodule=log -- services/announcements services/swole services/yt-dlp || true
	@echo ""
	@echo "Next: review above, then commit with e.g.:"
	@echo "    git commit -m 'Bump submodules to latest main'"
	@echo "    git push"

submodule-status:
	@git submodule status --recursive
