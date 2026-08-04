$instances = @(
    'SQL01',
    'SQL02',
    'SQL03'
)

$result = & "$PSScriptRoot/../src/Compare-DatabaseSchema.ps1" \
    -SqlInstance $instances \
    -Database 'AppDb'

$result.VariantSummary | Format-Table -AutoSize
$result.DatabaseSummary | Format-Table -AutoSize

# Detailed component comparison between variant representatives will be added
# after the structural SQL collector is complete.
