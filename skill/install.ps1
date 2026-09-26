# Install the exam-to-qb skill from this repo into the AI tools' skill folders.
#
#   ~/.claude/skills/exam-to-qb   Claude Code
#   ~/.agents/skills/exam-to-qb   OpenAI Codex, Gemini CLI (shared interop path)
#
# Default is Copy mode (safe, works everywhere). Use -Link to create directory
# junctions pointing back at this repo instead, so `git pull` updates the skill
# in place with no re-install. Junctions need no administrator rights.
#
#   .\install.ps1            # copy
#   .\install.ps1 -Link      # junction to the repo copy
#   .\install.ps1 -WhatIf    # show what would happen
param(
  [switch]$Link,
  [switch]$WhatIf
)
$ErrorActionPreference = "Stop"

$repoSkill = Join-Path (Split-Path -Parent $MyInvocation.MyCommand.Path) "exam-to-qb"
if (-not (Test-Path (Join-Path $repoSkill "SKILL.md"))) {
  throw "找不到 $repoSkill\SKILL.md — 請在 repo 的 skill\ 目錄下執行此腳本"
}

$targets = @(
  @{ Name = "Claude Code";        Path = Join-Path $env:USERPROFILE ".claude\skills\exam-to-qb" },
  @{ Name = "Codex / Gemini CLI"; Path = Join-Path $env:USERPROFILE ".agents\skills\exam-to-qb" }
)

foreach ($t in $targets) {
  $dest = $t.Path
  $parent = Split-Path -Parent $dest
  Write-Output ("--- {0}`n    {1}" -f $t.Name, $dest)

  if ($WhatIf) {
    $mode = if ($Link) { "建立目錄連結指向 $repoSkill" } else { "複製檔案" }
    Write-Output ("    [WhatIf] 會{0}" -f $mode)
    continue
  }

  if (-not (Test-Path $parent)) { New-Item -ItemType Directory $parent -Force | Out-Null }

  if (Test-Path $dest) {
    $item = Get-Item $dest -Force
    if ($item.LinkType) {
      # existing junction/symlink: remove the link itself, never its target
      cmd /c rmdir "`"$dest`"" | Out-Null
    } else {
      Remove-Item $dest -Recurse -Force -Confirm:$false
    }
  }

  if ($Link) {
    cmd /c mklink /J "`"$dest`"" "`"$repoSkill`"" | Out-Null
    Write-Output "    OK - 已建立目錄連結（git pull 後即自動更新）"
  } else {
    Copy-Item $repoSkill $dest -Recurse -Force
    Write-Output "    OK - 已複製"
  }
}

Write-Output ""
Write-Output "驗證：python `"$repoSkill\build.py`" --help"
if (-not $Link -and -not $WhatIf) {
  Write-Output "提醒：這是複製模式，日後改了 repo 裡的技能要重跑本腳本；改用 .\install.ps1 -Link 可免同步。"
}
