param()
$fileArg = $args | Where-Object { $_ -like "*.html" } | Select-Object -First 1
if ($fileArg -and (Test-Path -LiteralPath $fileArg)) {
  Remove-Item -LiteralPath $fileArg -Force
}
exit 0
