on open location this_URL
	try
		set py to "python3 -c 'import sys,urllib.parse as u; q=u.parse_qs(u.urlparse(sys.argv[1]).query); print(q.get(\"cwd\",[\"\"])[0]); print(q.get(\"id\",[\"\"])[0])' " & quoted form of this_URL
		set parsed to do shell script py
		set cwdPath to paragraph 1 of parsed
		set sid to paragraph 2 of parsed
		if sid is "" then return
		tell application "Terminal"
			activate
			if cwdPath is not "" then
				do script "cd " & quoted form of cwdPath & " && claude --resume " & quoted form of sid
			else
				do script "claude --resume " & quoted form of sid
			end if
		end tell
	end try
end open location
