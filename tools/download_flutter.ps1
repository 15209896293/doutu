$ErrorActionPreference = 'Continue'
$url = "https://storage.flutter-io.cn/flutter_infra_release/releases/stable/windows/flutter_windows_3.47.0-stable.zip"
$dir = "F:\flutter_parts"
$outZip = "F:\flutter_sdk.zip"
New-Item -ItemType Directory -Path $dir -Force | Out-Null

$segMB = 64
$segBytes = $segMB * 1MB
$count = 20

$jobs = @()
for ($i = 0; $i -lt $count; $i++) {
    $start = $i * $segBytes
    $end = $start + $segBytes - 1
    $out = "$dir\part_$($i.ToString('00')).bin"
    $jobs += Start-Job -ScriptBlock {
        param($u, $s, $e, $o)
        curl.exe -s --retry 8 --retry-delay 2 --retry-all-errors -r "$s-$e" -o $o $u
        $len = (Get-Item $o -ErrorAction SilentlyContinue).Length
        "$o -> $len bytes"
    } -ArgumentList $url, $start, $end, $out
}

"Waiting for $count segments..."
$jobs | Wait-Job -Timeout 3600 | Out-Null
$allOk = $true
foreach ($j in $jobs) {
    $state = $j.State
    if ($state -ne 'Completed') {
        "JOB NOT COMPLETED: $state"
        $allOk = $false
    }
    Receive-Job $j
}
$jobs | Remove-Job -Force

if ($allOk) {
    $parts = Get-ChildItem "$dir\part_*.bin" | Sort-Object Name
    $fs = [System.IO.File]::Open($outZip, [System.IO.FileMode]::Create)
    $bw = New-Object System.IO.BinaryWriter($fs)
    foreach ($p in $parts) {
        if ($p.Length -eq 0) { "skip empty $($p.Name)"; continue }
        $bytes = [System.IO.File]::ReadAllBytes($p.FullName)
        $bw.Write($bytes)
        "merged $($p.Name) ($($p.Length))"
    }
    $bw.Close()
    "FINAL SIZE: $((Get-Item $outZip).Length)"
} else {
    "DOWNLOAD INCOMPLETE - not merging"
}
