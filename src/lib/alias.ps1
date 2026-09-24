# 库存命令映射。个人设置放 user-settings.ps1。

$script:CommandMap = [ordered]@{
    ls   = 'eza --icons=auto --group-directories-first'
    ll   = 'eza --long --all --header --icons=auto --git --group-directories-first'
    la   = 'eza --all --icons=auto --group-directories-first'
    lt   = 'eza --tree'
    tree = 'eza --tree'
    vim  = 'nvim'
}

function Install-CommandMap {
    foreach ($name in $script:CommandMap.Keys) {
        $tokens = @($script:CommandMap[$name] -split '\s+')
        $head = $tokens[0]
        $rest = @()
        if ($tokens.Count -gt 1) {
            $rest = $tokens[1..($tokens.Count - 1)]
        }

        if ($head -eq 'eza') {
            $options = $rest
            Set-Item -Path "function:global:$name" -Value {
                Invoke-Eza $options $args
            }.GetNewClosure()
            continue
        }

        if ($head -eq 'cd' -and $rest.Count -eq 1) {
            $path = $rest[0]
            Set-Item -Path "function:global:$name" -Value {
                cd (winpath $path)
            }.GetNewClosure()
            continue
        }

        if ($rest.Count -eq 0) {
            Set-Alias -Name $name -Value $head -Scope Global -Force
            continue
        }

        $target = $head
        $arguments = $rest
        Set-Item -Path "function:global:$name" -Value {
            & $target @arguments @args
        }.GetNewClosure()
    }
}

Install-CommandMap
