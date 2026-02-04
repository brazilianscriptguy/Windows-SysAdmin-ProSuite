#!/usr/bin/env python3
from __future__ import annotations

import datetime as dt
import json
import os
import re
import sys
import urllib.request
from dataclasses import dataclass
from typing import Dict, List, Tuple, Optional


# ----------------------------
# Config (Tokyonight-ish)
# ----------------------------
BG = "#1a1b26"
CARD = "#24283b"
BORDER = "#414868"
TEXT = "#c0caf5"
MUTED = "#a9b1d6"
ACCENT = "#7aa2f7"

WIDTH = 495
HEIGHT = 195
PADDING = 18

OUT_DIR = "assets/readme-cards"
STATS_SVG = os.path.join(OUT_DIR, "github-stats.svg")
LANG_SVG = os.path.join(OUT_DIR, "top-languages.svg")
STREAK_SVG = os.path.join(OUT_DIR, "streak.svg")

PER_REPO_JSON = os.path.join(OUT_DIR, "per-repo-languages.json")
PER_REPO_MD = os.path.join(OUT_DIR, "per-repo-languages.md")
RELEASE_JSON = os.path.join(OUT_DIR, "release-info.json")

# If you want to exclude repos from aggregation (comma-separated names)
EXCLUDE_REPOS = {r.strip() for r in os.environ.get("EXCLUDE_REPOS", "").split(",") if r.strip()}

# Optional local scan mode for *this repo checkout* (binary normalization)
# - OFF by default (because you aggregate across all repos via GitHub Linguist)
LOCAL_SCAN = os.environ.get("LOCAL_SCAN", "false").lower() == "true"
LOCAL_SCAN_ROOT = os.environ.get("LOCAL_SCAN_ROOT", ".")
LOCAL_SCAN_MAX_MB = int(os.environ.get("LOCAL_SCAN_MAX_MB", "250"))  # safety guard

# File/path excludes for local scan
EXCLUDE_DIRS = {
    ".git", ".github", ".venv", "venv", "node_modules", "dist", "build", "bin", "obj",
    ".idea", ".vscode", "__pycache__", ".ruff_cache", ".mypy_cache"
}
# “Binary / media / archives” excluded from local scan sizes
EXCLUDE_EXTS = {
    ".png", ".jpg", ".jpeg", ".gif", ".webp", ".ico", ".svg",
    ".mp4", ".mov", ".avi", ".mkv", ".mp3", ".wav",
    ".zip", ".7z", ".rar", ".tar", ".gz",
    ".exe", ".dll", ".msi", ".iso", ".img", ".bin",
    ".pdf", ".doc", ".docx", ".ppt", ".pptx", ".xls", ".xlsx",
    ".nupkg", ".snupkg"
}


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

    if "data" not in payload or payload["data"] is None:
        die("GraphQL returned no data.")

    return payload["data"]


def svg_escape(s: str) -> str:
    return (s.replace("&", "&amp;")
            .replace("<", "&lt;")
            .replace(">", "&gt;")
            .replace('"', "&quot;")
            .replace("'", "&#39;"))


def svg_card(title: str, lines: List[Tuple[str, str]], footer: Optional[str] = None) -> str:
    title = svg_escape(title)
    now = dt.datetime.utcnow().strftime("%Y-%m-%d %H:%M UTC")

    y = PADDING + 28
    line_h = 22

    text_nodes = []
    text_nodes.append(
        f'<text x="{PADDING}" y="{PADDING+20}" fill="{TEXT}" font-size="18" '
        f'font-family="ui-sans-serif, system-ui, -apple-system, Segoe UI">{title}</text>'
    )
    text_nodes.append(
        f'<text x="{WIDTH-PADDING}" y="{PADDING+20}" text-anchor="end" fill="{MUTED}" font-size="11" '
        f'font-family="ui-sans-serif, system-ui, -apple-system, Segoe UI">{now}</text>'
    )

    for (label, value) in lines:
        label_e = svg_escape(label)
        value_e = svg_escape(value)
        text_nodes.append(
            f'<text x="{PADDING}" y="{y}" fill="{MUTED}" font-size="13" '
            f'font-family="ui-sans-serif, system-ui, -apple-system, Segoe UI">{label_e}</text>'
            f'<text x="{WIDTH-PADDING}" y="{y}" text-anchor="end" fill="{TEXT}" font-size="13" '
            f'font-family="ui-sans-serif, system-ui, -apple-system, Segoe UI">{value_e}</text>'
        )
        y += line_h

    if footer:
        footer_e = svg_escape(footer)
        text_nodes.append(
            f'<text x="{PADDING}" y="{HEIGHT-PADDING}" fill="{ACCENT}" font-size="12" '
            f'font-family="ui-sans-serif, system-ui, -apple-system, Segoe UI">{footer_e}</text>'
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
    x0 = PADDING
    y0 = PADDING + 46
    bar_w = WIDTH - (PADDING * 2)
    bar_h = 10

    palette = ["#7aa2f7", "#bb9af7", "#2ac3de", "#9ece6a", "#f7768e", "#e0af68", "#7dcfff", "#c0caf5"]

    segs = []
    x = x0
    for i, l in enumerate(langs):
        w = max(2, int(bar_w * (l.bytes / total)))
        color = palette[i % len(palette)]
        segs.append(f'<rect x="{x}" y="{y0}" width="{w}" height="{bar_h}" rx="4" fill="{color}"/>')
        x += w

    legend = []
    y = y0 + 30
    line_h = 20
    for i, l in enumerate(langs[:8]):
        pct = (l.bytes / total) * 100
        color = palette[i % len(palette)]
        legend.append(
            f'<circle cx="{x0+6}" cy="{y-5}" r="5" fill="{color}"/>'
            f'<text x="{x0+18}" y="{y}" fill="{MUTED}" font-size="13" '
            f'font-family="ui-sans-serif, system-ui, -apple-system, Segoe UI">{svg_escape(l.name)}</text>'
            f'<text x="{WIDTH-PADDING}" y="{y}" text-anchor="end" fill="{TEXT}" font-size="13" '
            f'font-family="ui-sans-serif, system-ui, -apple-system, Segoe UI">{pct:.1f}%</text>'
        )
        y += line_h

    return f"""<svg xmlns="http://www.w3.org/2000/svg" width="{WIDTH}" height="{HEIGHT}" viewBox="0 0 {WIDTH} {HEIGHT}">
  <rect x="0" y="0" width="{WIDTH}" height="{HEIGHT}" rx="16" fill="{BG}"/>
  <rect x="10" y="10" width="{WIDTH-20}" height="{HEIGHT-20}" rx="14" fill="{CARD}" stroke="{BORDER}" stroke-width="1"/>
  <text x="{PADDING}" y="{PADDING+20}" fill="{TEXT}" font-size="18" font-family="ui-sans-serif, system-ui, -apple-system, Segoe UI">{title}</text>
  <text x="{WIDTH-PADDING}" y="{PADDING+20}" text-anchor="end" fill="{MUTED}" font-size="11" font-family="ui-sans-serif, system-ui, -apple-system, Segoe UI">{now}</text>
  <text x="{PADDING}" y="{PADDING+40}" fill="{MUTED}" font-size="13" font-family="ui-sans-serif, system-ui, -apple-system, Segoe UI">Top languages by GitHub Linguist bytes (non-fork repos)</text>
  <rect x="{x0}" y="{y0}" width="{bar_w}" height="{bar_h}" rx="4" fill="#1f2335" stroke="{BORDER}" stroke-width="1"/>
  {''.join(segs)}
  {''.join(legend)}
</svg>
"""


def compute_streak_utc(days: List[Tuple[str, int]]) -> Tuple[int, int, int]:
    """
    days: list of (YYYY-MM-DD, count) sorted ascending.
    returns: (current_streak, longest_streak, total_contribs)
    Uses UTC anchoring to match GitHub contribution calendar dates.
    """
    total = sum(c for _, c in days)
    longest = 0

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

    # current streak: allow “today is 0” once (common early UTC)
    day_map = {dt.date.fromisoformat(ds): c for ds, c in days}

    anchor = dt.datetime.utcnow().date()
    if day_map.get(anchor, 0) == 0:
        anchor = anchor - dt.timedelta(days=1)

    current = 0
    d = anchor
    while day_map.get(d, 0) > 0:
        current += 1
        d = d - dt.timedelta(days=1)

    return current, longest, total


def read_nuspec_version(nuspec_path: str) -> Optional[str]:
    """
    Lightweight extraction of <version> from nuspec (no XML deps).
    """
    if not os.path.isfile(nuspec_path):
        return None
    try:
        raw = open(nuspec_path, "r", encoding="utf-8", errors="ignore").read()
        m = re.search(r"<version>\s*([^<]+)\s*</version>", raw, re.IGNORECASE)
        return m.group(1).strip() if m else None
    except Exception:
        return None


def local_scan_language_bytes(root: str) -> Dict[str, int]:
    """
    Optional: estimate language composition by scanning files in checkout.
    Excludes binary/media/archives and common build directories.
    NOTE: This is *repo-local*, not cross-repo.
    """
    ext_map = {
        ".ps1": "PowerShell",
        ".psm1": "PowerShell",
        ".psd1": "PowerShell",
        ".vbs": "VBScript",
        ".hta": "HTML/VBScript",
        ".py": "Python",
        ".js": "JavaScript",
        ".ts": "TypeScript",
        ".json": "JSON",
        ".md": "Markdown",
        ".yml": "YAML",
        ".yaml": "YAML",
        ".xml": "XML",
        ".nuspec": "XML",
        ".cs": "C#",
        ".cpp": "C++",
        ".c": "C",
        ".h": "C/C++ Header",
        ".html": "HTML",
        ".css": "CSS",
        ".sh": "Shell",
        ".bat": "Batchfile",
        ".cmd": "Batchfile",
    }

    total_bytes = 0
    limit = LOCAL_SCAN_MAX_MB * 1024 * 1024
    out: Dict[str, int] = {}

    for base, dirs, files in os.walk(root):
        # prune excluded dirs
        dirs[:] = [d for d in dirs if d not in EXCLUDE_DIRS and not d.startswith(".git")]

        for fn in files:
            path = os.path.join(base, fn)
            _, ext = os.path.splitext(fn.lower())

            if ext in EXCLUDE_EXTS:
                continue

            try:
                sz = os.path.getsize(path)
            except OSError:
                continue

            total_bytes += sz
            if total_bytes > limit:
                # safety guard: stop scanning
                out["(scan-truncated)"] = out.get("(scan-truncated)", 0) + 1
                return out

            lang = ext_map.get(ext, "Other")
            out[lang] = out.get(lang, 0) + sz

    return out


def main() -> None:
    token = os.environ.get("GITHUB_TOKEN")
    user = os.environ.get("GITHUB_USERNAME")
    if not token:
        die("GITHUB_TOKEN is missing.")
    if not user:
        die("GITHUB_USERNAME is missing.")

    os.makedirs(OUT_DIR, exist_ok=True)

    # Repository context (for release + nuspec alignment)
    gh_repo = os.environ.get("GITHUB_REPOSITORY", "").strip()  # owner/name
    owner, repo_name = (gh_repo.split("/", 1) + [""])[:2] if "/" in gh_repo else (user, "")

    # ---------
    # Query user + contribution calendar (UTC)
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
              contributionDays { date contributionCount }
            }
          }
        }
      }
    }
    """
    data = gh_graphql(token, q_user, {"login": user})
    u = data["user"]
    cal_days = []
    for w in u["contributionsCollection"]["contributionCalendar"]["weeks"]:
        for d in w["contributionDays"]:
            cal_days.append((d["date"], int(d["contributionCount"])))
    cal_days.sort(key=lambda x: x[0])

    current_streak, longest_streak, total_contribs = compute_streak_utc(cal_days)

    # ---------
    # Latest release (align to NuGet/release cadence)
    # ---------
    latest_release = {"tag": None, "publishedAt": None, "url": None}
    if repo_name:
        q_release = """
        query($owner: String!, $name: String!) {
          repository(owner: $owner, name: $name) {
            releases(first: 1, orderBy: {field: CREATED_AT, direction: DESC}) {
              nodes { tagName publishedAt url }
            }
          }
        }
        """
        try:
            rd = gh_graphql(token, q_release, {"owner": owner, "name": repo_name})
            nodes = rd["repository"]["releases"]["nodes"]
            if nodes:
                latest_release = {
                    "tag": nodes[0].get("tagName"),
                    "publishedAt": nodes[0].get("publishedAt"),
                    "url": nodes[0].get("url"),
                }
        except Exception:
            # don’t fail cards generation if release query fails
            pass

    with open(RELEASE_JSON, "w", encoding="utf-8") as f:
        json.dump(latest_release, f, indent=2)

    # If nuspec exists, extract version for display
    nuspec_version = read_nuspec_version("sysadmin-prosuite.nuspec")

    # ---------
    # Repos pagination: per-repo + aggregate (GitHub Linguist sizes)
    # ---------
    q_repos = """
    query($login: String!, $cursor: String) {
      user(login: $login) {
        repositories(
          first: 100,
          after: $cursor,
          ownerAffiliations: OWNER,
          isFork: false,
          orderBy: {field: UPDATED_AT, direction: DESC}
        ) {
          pageInfo { hasNextPage endCursor }
          nodes {
            name
            stargazerCount
            isArchived
            languages(first: 12, orderBy: {field: SIZE, direction: DESC}) {
              edges { size node { name } }
            }
          }
        }
      }
    }
    """

    stars = 0
    lang_bytes: Dict[str, int] = {}
    per_repo: Dict[str, Dict[str, int]] = {}
    cursor = None

    while True:
        data_r = gh_graphql(token, q_repos, {"login": user, "cursor": cursor})
        repos = data_r["user"]["repositories"]

        for repo in repos["nodes"]:
            rname = repo["name"]
            if rname in EXCLUDE_REPOS:
                continue
            if repo.get("isArchived"):
                continue

            stars += int(repo["stargazerCount"])
            rlangs: Dict[str, int] = {}

            for e in repo["languages"]["edges"]:
                lname = e["node"]["name"]
                size = int(e["size"])
                rlangs[lname] = rlangs.get(lname, 0) + size
                lang_bytes[lname] = lang_bytes.get(lname, 0) + size

            per_repo[rname] = dict(sorted(rlangs.items(), key=lambda kv: kv[1], reverse=True))

        if not repos["pageInfo"]["hasNextPage"]:
            break
        cursor = repos["pageInfo"]["endCursor"]

    # write per-repo JSON
    out_payload = {
        "generatedAtUtc": dt.datetime.utcnow().strftime("%Y-%m-%dT%H:%M:%SZ"),
        "user": u["login"],
        "method": "github-linguist-bytes",
        "excludedRepos": sorted(EXCLUDE_REPOS),
        "repos": per_repo,
    }
    with open(PER_REPO_JSON, "w", encoding="utf-8") as f:
        json.dump(out_payload, f, indent=2)

    # optional per-repo markdown summary (top 10 repos, top 5 langs each)
    try:
        rows = []
        rows.append("# Per-repo Language Breakdown (GitHub Linguist)\n")
        rows.append(f"- Generated (UTC): {out_payload['generatedAtUtc']}")
        rows.append(f"- User: {out_payload['user']}")
        rows.append("")
        top_repos = sorted(per_repo.items(), key=lambda kv: sum(kv[1].values()), reverse=True)[:10]
        for rn, langs in top_repos:
            total = sum(langs.values()) or 1
            top5 = list(langs.items())[:5]
            rows.append(f"## {rn}")
            for lname, b in top5:
                rows.append(f"- {lname}: {b} bytes ({(b/total)*100:.1f}%)")
            rows.append("")
        with open(PER_REPO_MD, "w", encoding="utf-8") as f:
            f.write("\n".join(rows))
    except Exception:
        pass

    top_langs = sorted(
        [RepoLang(k, v) for k, v in lang_bytes.items()],
        key=lambda x: x.bytes,
        reverse=True
    )[:8]

    # ---------
    # Optional local scan mode (repo checkout only)
    # ---------
    local_scan_info = None
    if LOCAL_SCAN:
        scan = local_scan_language_bytes(LOCAL_SCAN_ROOT)
        local_scan_info = dict(sorted(scan.items(), key=lambda kv: kv[1], reverse=True))

    # ---------
    # Build SVGs
    # ---------
    display_name = u["name"] or u["login"]

    release_line = "n/a"
    if latest_release.get("tag"):
        release_line = f"{latest_release['tag']}"

    nuspec_line = nuspec_version or "n/a"

    lines_stats = [
        ("User", display_name),
        ("Followers", f'{u["followers"]["totalCount"]}'),
        ("Owned repos", f'{u["ownedRepos"]["totalCount"]}'),
        ("Total stars", f"{stars}"),
        ("Contributions (1y)", f"{total_contribs}"),
        ("Latest release", release_line),
        ("NuGet nuspec", nuspec_line),
    ]

    footer = "Generated by GitHub Actions • GitHub API only"
    stats_svg = svg_card("GitHub Stats", lines_stats, footer=footer)
    with open(STATS_SVG, "w", encoding="utf-8") as f:
        f.write(stats_svg)

    lang_svg = svg_lang_bars("Top Languages", top_langs)
    with open(LANG_SVG, "w", encoding="utf-8") as f:
        f.write(lang_svg)

    lines_streak = [
        ("Current streak", f"{current_streak} days"),
        ("Longest streak", f"{longest_streak} days"),
        ("Contributions (1y)", f"{total_contribs}"),
    ]
    streak_svg = svg_card("Contribution Streak", lines_streak, footer="Computed from GitHub contribution calendar (UTC, 1y)")
    with open(STREAK_SVG, "w", encoding="utf-8") as f:
        f.write(streak_svg)

    print(f"OK: wrote {STATS_SVG}, {LANG_SVG}, {STREAK_SVG}")
    print(f"OK: wrote {PER_REPO_JSON}, {RELEASE_JSON}")
    if os.path.isfile(PER_REPO_MD):
        print(f"OK: wrote {PER_REPO_MD}")
    if local_scan_info:
        print("INFO: LOCAL_SCAN enabled -> repo-local normalized sizes computed (not shown in SVG by default).")


if __name__ == "__main__":
    main()
