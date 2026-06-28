#!/bin/zsh
# Invoked by ClaudeResume.app for claudemb://resume?id=..&cwd=.. links.
# Builds a .command file and opens it so Terminal runs `claude --resume`.
U="$1"
CWD=$(/usr/bin/python3 -c 'import sys,urllib.parse as u;print(u.parse_qs(u.urlparse(sys.argv[1]).query).get("cwd",[""])[0])' "$U" 2>/dev/null)
ID=$(/usr/bin/python3 -c 'import sys,urllib.parse as u;print(u.parse_qs(u.urlparse(sys.argv[1]).query).get("id",[""])[0])' "$U" 2>/dev/null)
[ -z "$ID" ] && exit 0
BIN="$HOME/.local/bin/claude"; [ -x "$BIN" ] || BIN=claude
F=$(mktemp /tmp/claude-resume-XXXXXX).command
{ echo '#!/bin/zsh'; [ -n "$CWD" ] && printf 'cd %q\n' "$CWD"; printf 'exec %q --resume %q\n' "$BIN" "$ID"; } > "$F"
chmod +x "$F"
open "$F"
