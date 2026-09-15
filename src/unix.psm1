# Unix 短选项解析。未知选项报错，-- 之后全部视为操作数。

# 用途：严格解析 unix 短选项与操作数；未知选项直接报错，-- 之后全部视为操作数。
# 示例：ConvertFrom-UnixArguments -Arguments @('-rf', '--', '-demo') -AllowedOptions @('r', 'f')
function ConvertFrom-UnixArguments {
    [CmdletBinding()]
    param(
        [object[]]$Arguments,
        [string[]]$AllowedOptions = @()
    )

    $allowed = [Collections.Generic.HashSet[string]]::new(
        [StringComparer]::Ordinal
    )
    foreach ($option in $AllowedOptions) {
        $null = $allowed.Add($option)
    }

    $options = [Collections.Generic.HashSet[string]]::new(
        [StringComparer]::Ordinal
    )
    $operands = [Collections.Generic.List[object]]::new()
    $parseOptions = $true

    foreach ($argument in $Arguments) {
        if ($parseOptions -and $argument -is [string]) {
            if ($argument -eq '--') {
                $parseOptions = $false
                continue
            }

            if ($argument -match '^-(?!-)(.+)$') {
                foreach ($optionCharacter in $Matches[1].ToCharArray()) {
                    $option = [string]$optionCharacter
                    if (-not $allowed.Contains($option)) {
                        throw "Unsupported option: -$option"
                    }
                    $null = $options.Add($option)
                }
                continue
            }

            if ($argument.StartsWith('--')) {
                throw "Unsupported option: $argument"
            }
        }

        $operands.Add($argument)
    }

    [pscustomobject]@{
        Options  = $options
        Operands = $operands.ToArray()
    }
}

Export-ModuleMember -Function ConvertFrom-UnixArguments
