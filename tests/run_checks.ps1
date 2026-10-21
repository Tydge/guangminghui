param(
    [string]$GodotPath = 'godot',
    [string]$PythonPath = 'python'
)
$ErrorActionPreference = 'Stop'
$projectPath = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot '..')).Path
foreach ($script in @('test_resources.gd', 'test_resources_ui.gd', 'test_rules.gd', 'test_effects.gd', 'test_expansion.gd', 'test_synergy.gd', 'test_renewal.gd', 'test_housing_clone.gd', 'test_covenant.gd', 'test_covenant_ui.gd', 'test_renewal_ui.gd', 'test_opening_balance.gd', 'test_ui.gd', 'test_battle_clarity.gd', 'test_modern_mechanics.gd', 'test_modern_ui.gd', 'test_presentation.gd', 'test_dice_sequence.gd', 'test_flow_order.gd', 'test_expansion_ui.gd', 'test_synergy_ui.gd', 'test_interaction_polish.gd', 'test_support_modes_ui.gd', 'test_table_tuning.gd', 'test_table_tuning_ui.gd', 'test_match.gd')) {
    $testOutput = & $GodotPath --headless --path $projectPath --script ('res://tests/' + $script) 2>&1
    $testCode = $LASTEXITCODE
    $testOutput | Write-Output
    if ($testCode -ne 0 -or ($testOutput -match 'SCRIPT ERROR:|ERROR:|Parse Error')) { throw ('Failed: ' + $script) }
}
& $PythonPath (Join-Path $PSScriptRoot 'test_card_sync.py')
if ($LASTEXITCODE -ne 0) { throw 'Failed: card table synchronization tests' }
& $PythonPath (Join-Path $projectPath 'tools/card_table.py') check
if ($LASTEXITCODE -ne 0) { throw 'Card table and game data are not synchronized' }
