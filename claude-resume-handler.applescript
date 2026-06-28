on open location this_URL
	set rs to (POSIX path of (path to home folder)) & ".claude/morning-brief/resume.sh"
	try
		do shell script "/bin/zsh " & quoted form of rs & " " & quoted form of this_URL
	end try
end open location
