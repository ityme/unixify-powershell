# Personal shell settings. profile.ps1 dotsources this last.
# upwsh update leaves an existing copy in place. Uninstall keeps a changed copy and deletes an unchanged template with the runtime.

$script:CommandMap['w'] = 'cd /i/workspace'
$script:CommandMap['t'] = 'cd /i/tmp'
$script:CommandMap['i'] = 'cd /i/ispace'
$script:CommandMap['d'] = 'cd ~/Desktop'
$script:CommandMap['gs'] = 'git status'
Install-CommandMap
