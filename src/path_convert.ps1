# Shared path conversion interfaces. No filesystem access or shell initialization.
function winpath {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory, Position = 0, ValueFromPipeline, ValueFromRemainingArguments)]
        [AllowEmptyString()][string[]]$Path
    )
    process {
        foreach ($item in $Path) {
            if ($item -match '^~(?:[/\\]|$)') {
                $HOME.TrimEnd('\', '/').Replace('\', '/') + $item.Substring(1).Replace('\', '/')
            } elseif ($item -match '^/([A-Za-z]):(?=[/\\]|$)') {
                $Matches[1].ToUpperInvariant() + ':' + $item.Substring(3)
            } elseif ($item -match '^/([A-Za-z])(?:/|$)') {
                # C: is drive-relative; /c must become the drive root C:/.
                $Matches[1].ToUpperInvariant() + ':/' + $item.Substring([Math]::Min(3, $item.Length))
            } else {
                $item
            }
        }
    }
}

function unixpath {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory, Position = 0, ValueFromPipeline, ValueFromRemainingArguments)]
        [AllowEmptyString()][string[]]$Path
    )
    process {
        foreach ($item in $Path) {
            $unix = [regex]::Replace(
                $item,
                '^/?([A-Za-z]):[\\/]+',
                { param($match) '/' + $match.Groups[1].Value.ToLowerInvariant() + '/' }
            )
            $unix.Replace('\', '/')
        }
    }
}
