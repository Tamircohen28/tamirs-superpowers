#!/usr/bin/env bash

input=$(cat)

model=$(echo "$input" | jq -r '.model.display_name // empty')
current_dir=$(echo "$input" | jq -r '.workspace.current_dir // .cwd // empty')
branch=$(echo "$input" | jq -r '.worktree.branch // empty')
effort=$(echo "$input" | jq -r '.effort.level // empty')
ctx_pct=$(echo "$input" | jq -r '.context_window.used_percentage // empty')
five_pct=$(echo "$input" | jq -r '.rate_limits.five_hour.used_percentage // empty')
five_resets=$(echo "$input" | jq -r '.rate_limits.five_hour.resets_at // empty')
seven_pct=$(echo "$input" | jq -r '.rate_limits.seven_day.used_percentage // empty')
seven_resets=$(echo "$input" | jq -r '.rate_limits.seven_day.resets_at // empty')
duration_ms=$(echo "$input" | jq -r '.cost.total_duration_ms // empty')
total_cost=$(echo "$input" | jq -r '.cost.total_cost_usd // empty')

fmt_model() {
  local name="$1"
  local lower=""
  name="${name//1M context/1M}"
  lower=$(printf '%s' "$name" | tr '[:upper:]' '[:lower:]')

  case "$lower" in
    *haiku*) printf '\033[33m%s\033[0m\n' "$name" ;;
    *sonnet*) printf '\033[32m%s\033[0m\n' "$name" ;;
    *opus*) printf '\033[34m%s\033[0m\n' "$name" ;;
    *) echo "$name" ;;
  esac
}

fmt_effort() {
  case "$1" in
    low) printf '\033[33m○ Low\033[0m\n' ;;
    medium) printf '\033[32m◐ Medium\033[0m\n' ;;
    high) printf '\033[38;5;208m● High\033[0m\n' ;;
    xhigh) printf '\033[34m◉ xHigh\033[0m\n' ;;
    max) printf '\033[31m◈ Max\033[0m\n' ;;
    *) echo "" ;;
  esac
}

fmt_pct() {
  local pct="$1"
  if [ -z "$pct" ] || [ "$pct" = "null" ]; then
    echo "--"
    return
  fi
  printf "%.0f" "$pct"
}

fmt_resets() {
  local epoch="$1"
  if [ -z "$epoch" ] || [ "$epoch" = "null" ]; then
    echo "resets --"
    return
  fi

  local now
  now=$(date +%s)
  local diff=$(( epoch - now ))

  if [ "$diff" -le 0 ]; then
    echo "resets now"
    return
  fi

  local h=$(( diff / 3600 ))
  local m=$(( (diff % 3600) / 60 ))

  if [ "$h" -gt 0 ]; then
    echo "resets in ${h}h ${m}m"
  else
    echo "resets in ${m}m"
  fi
}

fmt_duration() {
  local ms="$1"
  if [ -z "$ms" ] || [ "$ms" = "null" ]; then
    echo "--"
    return
  fi

  local total_sec=$(( ms / 1000 ))
  local d=$(( total_sec / 86400 ))
  local h=$(( (total_sec % 86400) / 3600 ))
  local m=$(( (total_sec % 3600) / 60 ))
  local s=$(( total_sec % 60 ))

  if [ "$d" -gt 0 ]; then
    echo "${d}d${h}H${m}m"
  elif [ "$h" -gt 0 ]; then
    echo "${h}H${m}m"
  elif [ "$m" -gt 0 ]; then
    echo "${m}m${s}s"
  else
    echo "${s}s"
  fi
}

fmt_cost() {
  local cost="$1"
  if [ -z "$cost" ] || [ "$cost" = "null" ]; then
    echo '$--'
    return
  fi

  printf '$%.2f' "$cost"
}

build_bar() {
  local pct="$1"
  local bar_width=10
  local filled=0

  if [ -n "$pct" ] && [ "$pct" != "null" ]; then
    local rounded
    rounded=$(fmt_pct "$pct")
    filled=$(( rounded * bar_width / 100 ))
    [ "$filled" -lt 0 ] && filled=0
    [ "$filled" -gt "$bar_width" ] && filled=$bar_width
  fi

  local empty=$(( bar_width - filled ))
  local bar=""
  local fill=""
  local pad=""

  [ "$filled" -gt 0 ] && printf -v fill "%${filled}s" && bar="${fill// /█}"
  [ "$empty" -gt 0 ] && printf -v pad "%${empty}s" && bar="${bar}${pad// /░}"

  echo "$bar"
}

bar_color() {
  local pct="$1"
  if [ -z "$pct" ] || [ "$pct" = "null" ]; then
    echo ""
    return
  fi

  local rounded
  rounded=$(fmt_pct "$pct")

  if [ "$rounded" -ge 90 ] 2>/dev/null; then
    printf '\033[31m'
  elif [ "$rounded" -ge 70 ] 2>/dev/null; then
    printf '\033[33m'
  else
    printf '\033[32m'
  fi
}

github_repo_url() {
  local remote_name=""
  local remote=""
  local repo_path=""

  if [ -z "$current_dir" ]; then
    return
  fi

  if [ -n "$branch" ]; then
    remote_name=$(git -C "$current_dir" config --get "branch.${branch}.remote" 2>/dev/null || true)
  fi

  [ -z "$remote_name" ] && remote_name="origin"
  remote=$(git -C "$current_dir" remote get-url "$remote_name" 2>/dev/null || true)

  if [ -z "$remote" ]; then
    remote_name=$(git -C "$current_dir" remote 2>/dev/null | sed -n '1p')
    [ -n "$remote_name" ] && remote=$(git -C "$current_dir" remote get-url "$remote_name" 2>/dev/null || true)
  fi

  case "$remote" in
    git@github.com:*)
      repo_path="${remote#git@github.com:}"
      repo_path="${repo_path%.git}"
      echo "https://github.com/${repo_path}"
      ;;
    https://github.com/*)
      repo_path="${remote#https://github.com/}"
      repo_path="${repo_path%.git}"
      echo "https://github.com/${repo_path}"
      ;;
  esac
}

fmt_repo() {
  local label="$1"
  local green='\033[32m'
  local bold='\033[1m'
  local reset='\033[0m'
  local display="📁 ${label}"

  printf '%b' "${green}${bold}${display}${reset}"
}

fmt_branch() {
  local branch_name="$1"
  local repo_url="$2"
  local yellow='\033[33m'
  local reset='\033[0m'
  local label="⎇ ${branch_name}"

  if [ -n "$repo_url" ]; then
    printf '%b' "${yellow}\e]8;;${repo_url}/tree/${branch_name}\a${label}\e]8;;\a${reset}"
    return
  fi

  printf '%b' "${yellow}${label}${reset}"
}

if [ -z "$branch" ] && [ -n "$current_dir" ]; then
  branch=$(git -C "$current_dir" branch --show-current 2>/dev/null || true)
fi

dir_name="${current_dir##*/}"
[ -z "$dir_name" ] && dir_name="$current_dir"

ctx_fmt=$(fmt_pct "$ctx_pct")
model_fmt=$(fmt_model "${model:-unknown}")
effort_fmt=$(fmt_effort "$effort")
repo_url=$(github_repo_url)
first_line="[${model_fmt:-unknown}"
[ -n "$effort_fmt" ] && first_line="$first_line $effort_fmt"
first_line="$first_line]"
[ -n "$dir_name" ] && first_line="$first_line $(fmt_repo "$dir_name")"
[ -n "$branch" ] && first_line="$first_line $(fmt_branch "$branch" "$repo_url")"
first_line="$first_line ctx:${ctx_fmt}"
[ "$ctx_fmt" != "--" ] && first_line="${first_line}%"

reset='\033[0m'
duration_fmt=$(fmt_duration "$duration_ms")
cost_fmt=$(fmt_cost "$total_cost")

format_limit_line() {
  local label="$1"
  local pct="$2"
  local resets="$3"
  local bar color fmt

  bar=$(build_bar "$pct")
  color=$(bar_color "$pct")
  fmt=$(fmt_pct "$pct")

  if [ "$fmt" = "--" ]; then
    printf '%s: -- %s | %s' "$label" "$bar" "$(fmt_resets "$resets")"
  else
    printf '%s: %b%s%b %s%% | %s' "$label" "$color" "$bar" "$reset" "$fmt" "$(fmt_resets "$resets")"
  fi
}

second_line="$(format_limit_line "5h" "$five_pct" "$five_resets") | ${duration_fmt} | ${cost_fmt}"

printf "%b\n" "$first_line"
printf "%b\n" "$second_line"
if [ -n "$seven_pct" ] && [ "$seven_pct" != "null" ]; then
  printf "%b\n" "$(format_limit_line "7d" "$seven_pct" "$seven_resets")"
fi
