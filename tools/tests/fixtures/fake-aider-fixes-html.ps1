param()
$fileArg = $args | Where-Object { $_ -like "*.html" } | Select-Object -First 1
if ($fileArg -and (Test-Path -LiteralPath $fileArg)) {
  Set-Content -LiteralPath $fileArg -Value '<html><body><div id="app"></div><script src="app.js"></script></body></html>'
}
exit 0
