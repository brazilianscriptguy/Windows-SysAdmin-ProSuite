
#!/usr/bin/env python3
from __future__ import annotations

import datetime as dt
import json
import os
import sys
import urllib.request
from dataclasses import dataclass
from typing import Dict, List, Tuple


# ----------------------------
# Config (Tokyonight-ish)
# ----------------------------
BG = "#1a1b26"
CARD = "#24283b"
BORDER = "#414868"
TEXT = "#c0caf5"
MUTED = "#a9b1d6"
ACCENT = "#7aa2f7"
GOOD = "#9ece6a"

WIDTH = 495
HEIGHT = 195
PADDING = 18

OUT_DIR = "assets/readme-cards"
STATS_SVG = os.path.join(OUT_DIR, "github-stats.svg")
LANG_SVG = os.path.join(OUT_DIR, "top-languages.svg")
STREAK_SVG = os.path.join(OUT_DIR, "streak.svg")


@dataclass
class RepoLang:
  name: str
  bytes: int


def die(msg: str) -> None:
  print(f"ERROR: {msg}", file=sys.stderr)
  sys.exit(1)


def gh_graphql(token: str, query: str, variables: dict) -> dict:
  url = "https://api.github.com/graphql"
  body = json.dumps({"query": query, "variables": variables}).encode("utf-8")
  req = urllib.request.Request(url, data=body, method="POST")
  req.add_header("Authorization", f"Bearer {token}")
  req.add_header("Content-Type", "application/json")
  req.add_header("User-Agent", "readme-cards-generator")

  with urllib.request.urlopen(req, timeout=30) as resp:
    payload = json.loads(resp.read().decode("utf-8"))

  if "errors" in payload:
    die(json.dumps(payload["errors"], indent=2))
  return payload["data"]


def svg_escape(s: str) -> str:
  return (s.replace("&", "&amp;")
           .replace("<", "&lt;")
           .replace(">", "&gt;")
           .replace('"', "&quot;")
           .replace("'", "&#39;"))


def svg_card(title: str, lines: List[Tuple[str, str]], footer: str | None = None) -> str:
  """
  lines: [(label, value)]
  """
  title = svg_escape(title)
  now = dt.datetime.utcnow().strftime("%Y-%m-%d %H:%M UTC")

  # layout
  y = PADDING + 28
  line_h = 22

  # Build text nodes
  text_nodes = []
  text_nodes.append(f'<text x="{PADDING}" y="{PADDING+20}" fill="{TEXT}" font-size="18" font-family="ui-sans-serif, system-ui, -apple-system, Segoe UI">{title}</text>')
  text_nodes.append(f'<text x="{WIDTH-PADDING}" y="{PADDING+20}" text-anchor="end" fill="{MUTED}" font-size="11" font-family="ui-sans-serif, system-ui, -apple-system, Segoe UI">{now}</text>')

  for (label, value) in lines:
    label_e = svg_escape(label)
    value_e = svg_escape(value)
    text_nodes.append(
      f'<text x="{PADDING}" y="{y}" fill="{MUTED}" font-size="13" font-family="ui-sans-serif, system-ui, -apple-system, Segoe UI">{label_e}</text>'
      f'<text x="{WIDTH-PADDING}" y="{y}" text-anchor="end" fill="{TEXT}" font-size="13" font-family="ui-sans-serif, system-ui, -apple-system, Segoe UI">{value_e}</text>'
    )
    y += line_h

  if footer:
    footer_e = svg_escape(footer)
    text_nodes.append(
      f'<text x="{PADDING}" y="{HEIGHT-PADDING}" fill="{ACCENT}" font-size="12" font-family="ui-sans-serif, system-ui, -apple-system, Segoe UI">{footer_e}</text>'
    )

  return f"""<svg xmlns="http://www.w3.org/2000/svg" width="{WIDTH}" height="{HEIGHT}" viewBox="0 0 {WIDTH} {HEIGHT}">
  <rect x="0" y="0" width="{WIDTH}" height="{HEIGHT}" rx="16" fill="{BG}"/>
  <rect x="10" y="10" width="{WIDTH-20}" height="{HEIGHT-20}" rx="14" fill="{CARD}" stroke="{BORDER}" stroke-width="1"/>
  {''.join(text_nodes)}
</svg>
"""


def svg_lang_bars(title: str, langs: List[RepoLang]) -> str:
  title = svg_escape(title)
  now = dt.datetime.utcnow().strftime("%Y-%m-%d %H:%M UTC")

  total = sum(l.bytes for l in langs) or 1
  # layout
  x0 = PADDING
  y0 = PADDING + 46
  bar_w = WIDTH - (PADDING * 2)
  bar_h = 10

  # simple palette (fixed)
  palette = ["#7aa2f7", "#bb9af7", "#2ac3de", "#9ece6a", "#f7768e", "#e0af68", "#7dcfff", "#c0caf5"]

  # stacked bar segments
  segs = []
  x = x0
  for i, l in enumerate(langs):
    w = max(2, int(bar_w * (l.bytes / total)))
    color = palette[i % len(palette)]
    segs.append(f'<rect x="{x}" y="{y0}" width="{w}" height="{bar_h}" rx="4" fill="{color}"/>')
    x += w

  # legend lines
  legend = []
  y = y0 + 30
  line_h = 20
  for i, l in enumerate(langs[:8]):
    pct = (l.bytes / total) * 100
    color = palette[i % len(palette)]
    legend.append(
      f'<circle cx="{x0+6}" cy="{y-5}" r="5" fill="{color}"/>'
      f'<text x="{x0+18}" y="{y}" fill="{MUTED}" font-size="13" font-family="ui-sans-serif, system-ui, -apple-system, Segoe UI">{svg_escape(l.name)}</text>'
      f'<text x="{WIDTH-PADDING}" y="{y}" text-anchor="end" fill="{TEXT}" font-size="13" font-family="ui-sans-serif, system-ui, -apple-system, Segoe UI">{pct:.1f}%</text>'
    )
    y += line_h

  return f"""<svg xmlns="http://www.w3.org/2000/svg" width="{WIDTH}" height="{HEIGHT}" viewBox="0 0 {WIDTH} {HEIGHT}">
  <rect x="0" y="0" width="{WIDTH}" height="{HEIGHT}" rx="16" fill="{BG}"/>
  <rect x="10" y="10" width="{WIDTH-20}" height="{HEIGHT-20}" rx="14" fill="{CARD}" stroke="{BORDER}" stroke-width="1"/>
  <text x="{PADDING}" y="{PADDING+20}" fill="{TEXT}" font-size="18" font-family="ui-sans-serif, system-ui, -apple-system, Segoe UI">{title}</text>
  <text x="{WIDTH-PADDING}" y="{PADDING+20}" text-anchor="end" fill="{MUTED}" font-size="11" font-family="ui-sans-serif, system-ui, -apple-system, Segoe UI">{now}</text>

  <text x="{PADDING}" y="{PADDING+40}" fill="{MUTED}" font-size="13" font-family="ui-sans-serif, system-ui, -apple-system, Segoe UI">Top languages by bytes (non-fork repos)</text>

  <rect x="{x0}" y="{y0}" width="{bar_w}" height="{bar_h}" rx="4" fill="#1f2335" stroke="{BORDER}" stroke-width="1"/>
  {''.join(segs)}

  {''.join(legend)}
</svg>
"""


def compute_streak(days: List[Tuple[str, int]]) -> Tuple[int, int, int]:
  """
  days: list of (YYYY-MM-DD, count) sorted ascending.
  returns: (current_streak, longest_streak, total_contribs)
  """
  total = sum(c for _, c in days)
  longest = 0
  current = 0

  # longest streak
  streak = 0
  prev_date = None
  for ds, c in days:
    d = dt.date.fromisoformat(ds)
    if prev_date and (d - prev_date).days != 1:
      streak = 0
    if c > 0:
      streak += 1
      longest = max(longest, streak)
    else:
      streak = 0
    prev_date = d

  # current streak (walk backwards from today)
  today = dt.date.today()
  day_map = {dt.date.fromisoformat(ds): c for ds, c in days}
  d = today
  while True:
    c = day_map.get(d, 0)
    if c > 0:
      current += 1
      d = d - dt.timedelta(days=1)
      continue
    # allow today to be 0 early in the day; if today is 0, try yesterday as start
    if d == today and current == 0:
      d = d - dt.timedelta(days=1)
      today = d  # shift anchor once
      continue
    break

  return current, longest, total


def main() -> None:
  token = os.environ.get("GITHUB_TOKEN")
  user = os.environ.get("GITHUB_USERNAME")
  if not token:
    die("GITHUB_TOKEN is missing.")
  if not user:
    die("GITHUB_USERNAME is missing.")

  os.makedirs(OUT_DIR, exist_ok=True)

  # ---------
  # Query user + contribution calendar
  # ---------
  q_user = """
  query($login: String!) {
    user(login: $login) {
      login
      name
      followers { totalCount }
      publicRepos: repositories(privacy: PUBLIC) { totalCount }
      ownedRepos: repositories(ownerAffiliations: OWNER) { totalCount }
      contributionsCollection {
        contributionCalendar {
          weeks {
            contributionDays {
              date
              contributionCount
            }
          }
        }
        totalCommitContributions
        totalIssueContributions
        totalPullRequestContributions
        totalPullRequestReviewContributions
      }
    }
  }
  """
  data = gh_graphql(token, q_user, {"login": user})
  u = data["user"]
  cc = u["contributionsCollection"]
  cal_days = []
  for w in cc["contributionCalendar"]["weeks"]:
    for d in w["contributionDays"]:
      cal_days.append((d["date"], int(d["contributionCount"])))
  cal_days.sort(key=lambda x: x[0])

  current_streak, longest_streak, total_contribs = compute_streak(cal_days)

  # ---------
  # Repos pagination: stars + languages bytes
  # ---------
  q_repos = """
  query($login: String!, $cursor: String) {
    user(login: $login) {
      repositories(first: 100, after: $cursor, ownerAffiliations: OWNER, isFork: false, orderBy: {field: UPDATED_AT, direction: DESC}) {
        pageInfo { hasNextPage endCursor }
        nodes {
          stargazerCount
          languages(first: 10, orderBy: {field: SIZE, direction: DESC}) {
            edges { size node { name } }
          }
        }
      }
    }
  }
  """

  stars = 0
  lang_bytes: Dict[str, int] = {}
  cursor = None

  while True:
    data_r = gh_graphql(token, q_repos, {"login": user, "cursor": cursor})
    repos = data_r["user"]["repositories"]
    for repo in repos["nodes"]:
      stars += int(repo["stargazerCount"])
      for e in repo["languages"]["edges"]:
        name = e["node"]["name"]
        size = int(e["size"])
        lang_bytes[name] = lang_bytes.get(name, 0) + size

    if not repos["pageInfo"]["hasNextPage"]:
      break
    cursor = repos["pageInfo"]["endCursor"]

  top_langs = sorted([RepoLang(k, v) for k, v in lang_bytes.items()], key=lambda x: x.bytes, reverse=True)[:8]

  # ---------
  # Build SVGs
  # ---------
  display_name = u["name"] or u["login"]

  # Stats card
  lines_stats = [
    ("User", display_name),
    ("Followers", f'{u["followers"]["totalCount"]}'),
    ("Public repos", f'{u["publicRepos"]["totalCount"]}'),
    ("Owned repos", f'{u["ownedRepos"]["totalCount"]}'),
    ("Total stars", f"{stars}"),
    ("Contributions (1y)", f"{total_contribs}"),
  ]
  stats_svg = svg_card("GitHub Stats", lines_stats, footer="Generated by GitHub Actions • No external services")
  with open(STATS_SVG, "w", encoding="utf-8") as f:
    f.write(stats_svg)

  # Languages card
  lang_svg = svg_lang_bars("Top Languages", top_langs)
  with open(LANG_SVG, "w", encoding="utf-8") as f:
    f.write(lang_svg)

  # Streak card
  lines_streak = [
    ("Current streak", f"{current_streak} days"),
    ("Longest streak", f"{longest_streak} days"),
    ("Contributions (1y)", f"{total_contribs}"),
  ]
  streak_svg = svg_card("Contribution Streak", lines_streak, footer="Computed from GitHub contribution calendar (1y)")
  with open(STREAK_SVG, "w", encoding="utf-8") as f:
    f.write(streak_svg)

  print(f"OK: wrote {STATS_SVG}, {LANG_SVG}, {STREAK_SVG}")


if __name__ == "__main__":
  main()
