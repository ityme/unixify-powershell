# 文本过滤。

# 用途：把字符串或 PowerShell 对象转换为可供 grep 匹配的文本。
# 示例：ps -ef | grep pwsh 会同时搜索进程对象的各个字段
function ConvertTo-SearchText {
    param([object]$Value)

    if ($null -eq $Value) {
        return ''
    }

    if ($Value -is [string]) {
        return $Value
    }

    if ($Value -is [System.Diagnostics.Process]) {
        return "$($Value.Id) $($Value.ProcessName) $($Value.Name)"
    }

    return (
        $Value.PSObject.Properties |
            ForEach-Object {
                if ($null -ne $_.Value) {
                    [string]$_.Value
                }
            }
    ) -join ' '
}

# 用途：使用正则表达式判断一个值是否匹配，并支持 -v 反选。
# 示例：grep -v error -> 只输出不包含 error 的内容
function Test-SearchMatch {
    param(
        [regex]$Matcher,
        [object]$Value,
        [switch]$InvertMatch
    )

    $matched = $Matcher.IsMatch((ConvertTo-SearchText $Value))
    if ($InvertMatch) {
        return -not $matched
    }

    return $matched
}

# 用途：过滤管道对象或文件内容，支持 -i 忽略大小写和 -v 反选。
# 示例：ps -ef | grep -i pwsh
function global:grep {
    [CmdletBinding()]
    param(
        [Alias('i')]
        [switch]$IgnoreCase,

        [Alias('v')]
        [switch]$InvertMatch,

        [Parameter(Mandatory, Position = 0)]
        [string]$Pattern,

        [Parameter(Position = 1, ValueFromRemainingArguments)]
        [string[]]$Path,

        [Parameter(ValueFromPipeline)]
        [object]$InputObject
    )

    begin {
        $global:LASTEXITCODE = 2
        $state = [pscustomobject]@{
            Matched = $false
            Error   = $false
        }
        $options = if ($IgnoreCase) {
            [Text.RegularExpressions.RegexOptions]::IgnoreCase
        } else {
            [Text.RegularExpressions.RegexOptions]::None
        }
        $matcher = [regex]::new($Pattern, $options)
    }

    process {
        if (
            $PSBoundParameters.ContainsKey('InputObject') -and
            (Test-SearchMatch $matcher $InputObject -InvertMatch:$InvertMatch)
        ) {
            $state.Matched = $true
            $InputObject
        }
    }

    end {
        foreach ($item in @(ConvertTo-WindowsPathOperands $Path)) {
            try {
                Get-Content -LiteralPath ($item) -ErrorAction Stop |
                    Where-Object {
                        $matched = Test-SearchMatch $matcher $_ -InvertMatch:$InvertMatch
                        if ($matched) {
                            $state.Matched = $true
                        }
                        $matched
                    }
            } catch {
                $state.Error = $true
                Write-Error $_
            }
        }

        $global:LASTEXITCODE = if ($state.Error) {
            2
        } elseif ($state.Matched) {
            0
        } else {
            1
        }
    }
}

Export-ModuleMember -Function @()
