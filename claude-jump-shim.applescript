on open location u
	set jp to (POSIX path of (path to home folder)) & ".claude/morning-brief/jump.applescript"
	try
		do shell script "/usr/bin/osascript " & quoted form of jp & " " & quoted form of (u as string)
	end try
end open location
