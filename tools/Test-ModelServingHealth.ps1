param(
  [string]$ModelName = "ornith:9b",
  [string]$OllamaHost = "http://localhost:11434",
  [int]$TimeoutSeconds = 60
)

$ErrorActionPreference = "Stop"

function Test-RepetitionLoop {
  param([string]$Text)
  if ([string]::IsNullOrWhiteSpace($Text)) { return $false }
  $chunkLength = 15
  if ($Text.Length -lt $chunkLength) { return $false }
  for ($i = 0; $i -le ($Text.Length - $chunkLength); $i++) {
    $chunk = $Text.Substring($i, $chunkLength)
    $occurrences = ([regex]::Matches($Text, [regex]::Escape($chunk))).Count
    if ($occurrences -ge 3) { return $true }
  }
  return $false
}

$body = @{
  model = $ModelName
  messages = @(
    @{ role = "system"; content = "Tu es un assistant de code concis." },
    @{ role = "user"; content = "Ecris juste une fonction Python add(a, b) qui retourne a + b, sans explication." }
  )
  stream = $false
} | ConvertTo-Json -Depth 6

$result = [ordered]@{
  checked_at = (Get-Date).ToString("o")
  model = $ModelName
  status = "unknown"
  message = ""
}

try {
  $response = Invoke-RestMethod -Uri ($OllamaHost + "/api/chat") -Method Post -Body $body -ContentType "application/json; charset=utf-8" -TimeoutSec $TimeoutSeconds
  $content = [string]$response.message.content
  $doneReason = [string]$response.done_reason
  $looping = Test-RepetitionLoop -Text $content
  if ($looping) {
    $result.status = "failed"
    $result.message = "Reponse du modele '" + $ModelName + "' detectee en boucle de repetition."
  } elseif ($doneReason -ne "stop") {
    $result.status = "failed"
    $result.message = "Le modele '" + $ModelName + "' n'a pas termine proprement (done_reason=" + $doneReason + "), signe possible de derive."
  } elseif ([string]::IsNullOrWhiteSpace($content)) {
    $result.status = "failed"
    $result.message = "Le modele '" + $ModelName + "' a renvoye une reponse vide."
  } else {
    $result.status = "ok"
    $result.message = "Modele '" + $ModelName + "' repond correctement, sans boucle de repetition."
  }
} catch {
  $result.status = "failed"
  $result.message = "Echec de l'appel au modele '" + $ModelName + "': " + $_.Exception.Message
}

$result | ConvertTo-Json -Depth 6
if ($result.status -ne "ok") { exit 1 }
exit 0
