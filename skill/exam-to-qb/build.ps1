<#
build.ps1 - Convert a TSV of parsed exam questions into question-bank CSV format.

Pipeline contract:
  - You (Claude) parse the source document into questions and write a TSV file.
  - This script applies the 27-column question-bank template header + CSV escaping,
    and writes the final CSV as UTF-8 (no BOM).
  - This script is intentionally ASCII-only so its own encoding is never an issue;
    all CJK content lives in the TSV (read with explicit UTF-8) and header.csv.

TSV format (one question per line, fields separated by a literal TAB):
  [0] 題型  type: 1=是非 2=單選 3=複選 4=填充 5=問答
  [1] 題目  question text
  [2] 答案  answer:
              是非 -> 1(是) or 2(否)
              單選 -> option number (e.g. 2)
              複選 -> comma-joined numbers, e.g. 1,2,4  (commas are fine; script quotes them)
              填充 -> leave EMPTY; embed answers inline in 題目 as [*answer*]
              問答 -> reference answer text
  [3] 解說  explanation (optional)
  [4] 難易度 difficulty: 1=容易 2=適中 3=困難
  [5] 選項1  for 單選/複選: option 1 text; for 填充: 1=不分大小寫 2=區分大小寫
  [6] 選項2  for 單選/複選: option 2 text; for 填充: 1=不考慮順序 2=需考慮順序
  [7..] 選項3.. additional choice options

Encode newlines inside any field as the two-character token \n ; the script turns
them into real CRLF inside a quoted CSV field.

Params:
  -Tsv       path to the TSV file (required)
  -Out       path to the output CSV (required)
  -Header    path to a header file; default: header.csv next to this script
  -Category  optional category name to fill into column 2 (類別) for every row
  -AlsoBig5  also emit a Big5 (cp950) copy. Default path = <Out>_big5.csv
             (i.e. "_big5" inserted before the extension).
  -Big5Out   override the Big5 output path (implies -AlsoBig5).

Big5 note: cp950 has a smaller repertoire than UTF-8. A few symbols are
remapped to Big5 equivalents (>= -> U+2267, <= -> U+2266). Any character that
still cannot be encoded is written with a replacement char and reported as a
warning so the operator can decide whether the Big5 copy is acceptable.
#>
param(
  [Parameter(Mandatory=$true)][string]$Tsv,
  [Parameter(Mandatory=$true)][string]$Out,
  [string]$Header,
  [string]$Category = '',
  [switch]$AlsoBig5,
  [string]$Big5Out = ''
)
$ErrorActionPreference = 'Stop'
$utf8 = New-Object System.Text.UTF8Encoding($false)

if (-not $Header -or $Header -eq '') {
  $Header = Join-Path $PSScriptRoot 'header.csv'
}
$headerText = [System.IO.File]::ReadAllText($Header, $utf8).TrimEnd("`r","`n")

function Esc([string]$s) {
  if ($null -eq $s) { $s = '' }
  $s = $s -replace '\\n', "`r`n"
  if ($s -match '["\r\n,]') { '"' + ($s -replace '"','""') + '"' } else { $s }
}

$lines = [System.IO.File]::ReadAllLines($Tsv, $utf8)
$rows = @()
foreach ($line in $lines) {
  if ($line.Trim().Length -eq 0) { continue }
  $f = $line -split "`t"
  $cols = ,'' + ,$Category        # col1 題組 (empty), col2 類別
  $cols += $f                      # col3.. = 題型,題目,答案,解說,難易度,選項1..
  while ($cols.Count -lt 27) { $cols += '' }
  if ($cols.Count -gt 27) { $cols = $cols[0..26] }
  $rows += (($cols | ForEach-Object { Esc $_ }) -join ',')
}

$content = $headerText + "`r`n" + ($rows -join "`r`n") + "`r`n"
[System.IO.File]::WriteAllText($Out, $content, $utf8)

$bytes = [System.IO.File]::ReadAllBytes($Out)
$hasBom = ($bytes.Length -ge 3 -and $bytes[0] -eq 0xEF -and $bytes[1] -eq 0xBB -and $bytes[2] -eq 0xBF)
Write-Output ("OK -> {0}  rows={1}  category='{2}'  bytes={3}  BOM={4}" -f $Out, $rows.Count, $Category, $bytes.Length, $hasBom)

# --- optional Big5 (cp950) copy ---
if ($AlsoBig5 -or $Big5Out -ne '') {
  if ($Big5Out -eq '') {
    $dir  = [System.IO.Path]::GetDirectoryName($Out)
    $name = [System.IO.Path]::GetFileNameWithoutExtension($Out)
    $ext  = [System.IO.Path]::GetExtension($Out)
    $Big5Out = Join-Path $dir ($name + '_big5' + $ext)
  }
  # remap symbols that have Big5-friendly equivalents
  $b5content = $content.Replace([char]0x2265, [char]0x2267).Replace([char]0x2264, [char]0x2266)

  # detect any chars still unmappable in Big5
  $strict = [System.Text.Encoding]::GetEncoding(950, [System.Text.EncoderExceptionFallback]::new(), [System.Text.DecoderExceptionFallback]::new())
  $bad = [System.Collections.Generic.SortedSet[string]]::new()
  foreach ($ch in [char[]]$b5content) {
    if ([char]::IsControl($ch)) { continue }
    try { [void]$strict.GetBytes([string]$ch) } catch { [void]$bad.Add(("{0}(U+{1:X4})" -f $ch, [int]$ch)) }
  }

  $big5 = [System.Text.Encoding]::GetEncoding(950)   # replacement fallback -> '?'
  [System.IO.File]::WriteAllBytes($Big5Out, $big5.GetBytes($b5content))
  $b5size = (Get-Item $Big5Out).Length
  if ($bad.Count -eq 0) {
    Write-Output ("OK -> {0}  (Big5/cp950, lossless)  bytes={1}" -f $Big5Out, $b5size)
  } else {
    Write-Output ("WARN -> {0}  (Big5/cp950)  bytes={1}  UNMAPPABLE chars replaced with '?': {2}" -f $Big5Out, $b5size, ($bad -join ', '))
  }
}
