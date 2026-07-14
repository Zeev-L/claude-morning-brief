-- jump.applescript — the actual AX logic, run via `osascript jump.applescript <url>`
-- by the thin ClaudeJump.app shim. Kept external so it can be tuned WITHOUT
-- rebuilding/re-signing the app (which would reset its Accessibility grant).
--
--   osascript jump.applescript "claudejump://open?title=<urlencoded>"
--   osascript jump.applescript "claudejump://dump"     (writes /tmp/claude-ax-dump.txt)

on run argv
	set u to ""
	if (count of argv) > 0 then set u to item 1 of argv
	if u contains "dump" then
		doDump()
	else if u contains "://brief" then
		openBrief()
	else
		openByTitle(extractTitle(u))
	end if
end run

-- claudejump://brief — open the newest Morning Brief on the Desktop. Lets the
-- bridge (or any https page) open the LOCAL brief in one click; a direct file://
-- link is blocked by browsers from an https origin, a custom scheme is not.
on openBrief()
	set p to (POSIX path of (path to home folder)) & "Desktop/Claude Morning Brief/latest.html"
	try
		do shell script "open " & quoted form of p
	end try
end openBrief

on extractTitle(u)
	set AppleScript's text item delimiters to "title="
	set raw to last text item of u
	set AppleScript's text item delimiters to ""
	return do shell script "/usr/bin/python3 -c 'import sys,urllib.parse;print(urllib.parse.unquote(sys.argv[1]))' " & quoted form of raw
end extractTitle

-- force Electron/Chromium to expose its accessibility tree
on forceA11y(p)
	tell application "System Events"
		try
			set value of attribute "AXManualAccessibility" of p to true
		end try
	end tell
end forceA11y

-- depth-first search returning the first AXButton whose name contains theTitle
on findBtn(el, theTitle, depth)
	if depth > 26 then return missing value
	tell application "System Events"
		try
			if (role of el is "AXButton") then
				if ((name of el as string) contains theTitle) then return el
			end if
		end try
		try
			repeat with k in (UI elements of el)
				set r to my findBtn(k, theTitle, depth + 1)
				if r is not missing value then return r
			end repeat
		end try
	end tell
	return missing value
end findBtn

on openByTitle(theTitle)
	tell application "System Events"
		set procs to (processes whose name is "Claude")
		repeat with p in procs
			my forceA11y(p)
		end repeat
		delay 0.7
		-- setup A (per-session windows, e.g. Claude-RTL): raise the window whose
		-- name contains the title. Most reliable when each session is its own window.
		repeat with p in procs
			try
				set w to (first window of p whose name contains theTitle)
				set frontmost of p to true
				delay 0.15
				perform action "AXRaise" of w
				return
			end try
		end repeat
		-- setup B (single window + Recents sidebar): press the matching sidebar button.
		repeat with p in procs
			try
				set b to my findBtn(window 1 of p, theTitle, 0)
				if b is not missing value then
					set frontmost of p to true
					delay 0.15
					perform action "AXPress" of b
					return
				end if
			end try
		end repeat
		-- fallback: the session's window is closed (common in the per-window setup)
		-- and no sidebar button matched. We can't reliably click a Recents row from
		-- Electron's sparse a11y tree, so just bring the Claude app to the front — the
		-- user lands on Recents and picks the session (its name = the card title).
		-- Belt-and-suspenders: System Events frontmost + `open -a` on the app bundle.
		repeat with p in procs
			try
				set frontmost of p to true
				try
					set appPath to POSIX path of (application file of p)
					do shell script "open -a " & quoted form of appPath
				end try
				return
			end try
		end repeat
	end tell
	-- no Claude process at all → launch/focus the app via its own scheme
	try
		do shell script "open claude://"
	end try
end openByTitle

-- diagnostic dump of the sidebar tree
global gOut, gCount
on doDump()
	set gOut to ""
	set gCount to 0
	tell application "System Events"
		set procs to (processes whose name is "Claude")
		repeat with p in procs
			my forceA11y(p)
		end repeat
		delay 1.0
		repeat with p in procs
			set gOut to gOut & "=== PROC " & (unix id of p) & " ===" & linefeed
			try
				my walk(window 1 of p, 0)
			end try
		end repeat
	end tell
	do shell script "cat > /tmp/claude-ax-dump.txt <<'XEOF'
" & gOut & "
XEOF"
end doDump

on walk(el, depth)
	if gCount > 6000 then return
	if depth > 24 then return
	tell application "System Events"
		set nm to ""
		set rl to ""
		try
			set rl to (role of el as string)
		end try
		try
			set nm to (name of el as string)
		end try
		if nm is not "" and nm is not "missing value" then
			set gOut to gOut & rl & " | " & nm & linefeed
			set gCount to gCount + 1
		end if
		try
			repeat with k in (UI elements of el)
				my walk(k, depth + 1)
			end repeat
		end try
	end tell
end walk
