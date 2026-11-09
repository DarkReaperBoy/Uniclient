#!/bin/sh
# GIT_ASKPASS credential helper — answers git's credential prompts from .env
# (AGENTS.md §0.2). Usage: GIT_ASKPASS=scripts/git-askpass.sh git push origin main
d=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
[ -f "$d/.env" ] && . "$d/.env"
case "$*" in
  *Username*) echo "${GH_USER:-x-access-token}" ;;
  *) echo "${GH_TOKEN:-}" ;;
esac
