#!/usr/bin/env bash
# 下载 unixify-powershell 并挂钩当前用户的 pwsh。
#   curl -fsSL https://raw.githubusercontent.com/ityme/unixify-powershell/main/src/scripts/bootstrap.sh | bash

set -euo pipefail

REPO="${UNIXIFY_REPO:-ityme/unixify-powershell}"
REF="${UNIXIFY_REF:-main}"

if ! command -v pwsh >/dev/null 2>&1; then
  echo "unixify-powershell: pwsh not found" >&2
  exit 1
fi

bootstrap=""
src="${BASH_SOURCE[0]:-}"
if [[ -n "$src" && -f "$src" ]]; then
  dir="$(cd "$(dirname "$src")" && pwd)"
  if [[ -f "$dir/bootstrap.ps1" ]]; then
    bootstrap="$dir/bootstrap.ps1"
  fi
fi

cleanup() {
  if [[ -n "${tmp:-}" && -f "$tmp" ]]; then
    rm -f "$tmp"
  fi
}
trap cleanup EXIT

if [[ -z "$bootstrap" ]]; then
  tmp="$(mktemp)"
  url="https://raw.githubusercontent.com/${REPO}/${REF}/src/scripts/bootstrap.ps1"
  if command -v curl >/dev/null 2>&1; then
    curl -fsSL "$url" -o "$tmp"
  elif command -v wget >/dev/null 2>&1; then
    wget -qO "$tmp" "$url"
  else
    echo "unixify-powershell: need curl or wget" >&2
    exit 1
  fi
  bootstrap="$tmp"
fi

pwsh -NoLogo -NoProfile -File "$bootstrap" "$@"
