#!/usr/bin/env pwsh
<#
.SYNOPSIS
  Instalador cross-platform do deepclaude — Windows nativo (PowerShell)
.DESCRIPTION
  Instala e configura o binário OFICIAL do Claude Code com o backend trocado
  para o DeepSeek V4 Pro via endpoint Anthropic-compatível. Cria uma segunda
  instalação ISOLADA (sem quebrar a original) e expõe o comando `deepclaude`.

  Contraparte Linux/macOS: install-deepclaude.sh

  Uso:
    .\install-deepclaude.ps1                    # instalação interativa
    .\install-deepclaude.ps1 -Key "sk-..."      # fornece a chave na linha de comando
    .\install-deepclaude.ps1 -NoKey             # pula validação da chave
    $env:DEEPSEEK_CLAUDE_API_KEY="sk-..."; .\install-deepclaude.ps1

  Se o script não executar por política de execução:
    powershell -ExecutionPolicy Bypass -File install-deepclaude.ps1
    Set-ExecutionPolicy -Scope CurrentUser RemoteSigned
#>

param(
  [string]$Key = '',
  [switch]$NoKey = $false,
  [switch]$Help = $false
)

$ErrorActionPreference = 'Stop'
# PowerShell 5.1+ (Windows 10+) ou PowerShell 7+ (recomendado)

# ── Help ─────────────────────────────────────────────────────────────────────
if ($Help) {
  Write-Host @"
Uso: .\install-deepclaude.ps1 [-Key sk-...] [-NoKey]

  -Key sk-...    Fornece a chave da API DeepSeek
  -NoKey         Pula a validacao da chave (configure depois)
  -Help          Mostra esta ajuda

A chave tambem pode ser fornecida via env var:
  `$env:DEEPSEEK_CLAUDE_API_KEY = "sk-..." ; .\install-deepclaude.ps1

Para burlar a politica de execucao:
  powershell -ExecutionPolicy Bypass -File install-deepclaude.ps1
"@
  exit 0
}

# ── Cores ────────────────────────────────────────────────────────────────────
function Write-Info    { Write-Host "i $args" -ForegroundColor Cyan }
function Write-Ok      { Write-Host "√ $args" -ForegroundColor Green }
function Write-Warning2 { Write-Host "⚠ $args" -ForegroundColor Yellow }
function Write-Err     { Write-Host "× $args" -ForegroundColor Red }
function Write-Header  { Write-Host "`n═══ $args ═══" -ForegroundColor Blue }

# ── Helpers de caminho ──────────────────────────────────────────────────────
$Script:ConfigDir   = Join-Path $env:USERPROFILE '.claude-deepseek'
$Script:BinDir      = Join-Path $env:USERPROFILE '.local\bin'
$Script:LauncherPath = Join-Path $BinDir 'deepclaude.cmd'
$Script:MainClaudeCfg = Join-Path $env:USERPROFILE '.claude'

# ── Verificacao de pre-requisitos ────────────────────────────────────────────
function Check-Prereqs {
  Write-Header 'Verificando pre-requisitos'

  # Node.js / npm (necessario para instalar Claude Code se nao existir)
  $nodeOk = Get-Command node -ErrorAction SilentlyContinue
  $npmOk  = Get-Command npm -ErrorAction SilentlyContinue

  if (-not $nodeOk) {
    Write-Err 'Node.js nao encontrado — necessario para instalar o Claude Code.'
    Write-Info 'Instale de: https://nodejs.org (LTS recomendado)'
    Write-Info '  ou: winget install OpenJS.NodeJS.LTS'
    exit 1
  }

  if (-not $npmOk) {
    Write-Err 'npm nao encontrado (deveria vir com o Node.js).'
    exit 1
  }

  Write-Ok "Node.js: $(node --version)"
  Write-Ok "npm:     $(npm --version)"
}

# ── Instalacao do binario Claude Code ────────────────────────────────────────
function Find-OrInstallClaude {
  Write-Header 'Binario Claude Code'

  $claude = Get-Command claude -ErrorAction SilentlyContinue
  if ($claude) {
    $ver = & claude --version 2>$null
    Write-Ok "Claude Code encontrado: $($claude.Source) ($ver)"
    return $claude.Source
  }

  Write-Info 'Claude Code nao encontrado. Instalando via npm...'
  npm install -g @anthropic-ai/claude-code

  $claude = Get-Command claude -ErrorAction SilentlyContinue
  if ($claude) {
    Write-Ok "Claude Code instalado via npm: $($claude.Source)"
    return $claude.Source
  }

  Write-Err 'Falha ao instalar o Claude Code.'
  Write-Info 'Tente manualmente: npm install -g @anthropic-ai/claude-code'
  Write-Info 'Ou baixe o instalador de: https://claude.ai/install'
  exit 1
}

# ── DeepSeek API Key ─────────────────────────────────────────────────────────
function Resolve-DeepSeekKey {
  # Ordem: flag -Key → env var → arquivo existente → prompt

  # 1. Flag -Key
  if ($Key) {
    Write-Ok 'Chave DeepSeek via parametro -Key'
    return $Key
  }

  # 2. Env var
  $envKey = $env:DEEPSEEK_CLAUDE_API_KEY
  if ($envKey) {
    Write-Ok 'Chave DeepSeek via DEEPSEEK_CLAUDE_API_KEY (env)'
    return $envKey
  }

  # 3. Arquivo existente
  $keyFile = Join-Path $ConfigDir 'deepseek.key'
  if (Test-Path $keyFile) {
    $fileKey = (Get-Content $keyFile -First 1).Trim()
    if ($fileKey) {
      Write-Ok 'Chave DeepSeek encontrada em deepseek.key'
      return $fileKey
    }
  }

  # 4. Prompt interativo
  Write-Host ''
  Write-Info 'Chave da API DeepSeek necessaria.'
  Write-Info 'Obtenha uma em: https://platform.deepseek.com/api_keys'
  $promptKey = Read-Host -Prompt 'Chave (sk-...)'
  if (-not $promptKey) {
    Write-Err 'Nenhuma chave fornecida. Abortando.'
    exit 1
  }
  return $promptKey
}

function Test-DeepSeekKey {
  param([string]$KeyToTest)

  Write-Info 'Validando chave DeepSeek...'

  try {
    $response = Invoke-RestMethod -Uri 'https://api.deepseek.com/user/balance' `
      -Headers @{ Authorization = "Bearer $KeyToTest" } `
      -StatusCodeVariable 'httpCode' `
      -SkipHttpErrorCheck `
      -TimeoutSec 15

    if ($httpCode -eq 200) {
      if ($response.is_active) {
        Write-Ok 'Chave valida √'
        if ($response.total_balance) {
          Write-Info "Saldo: $($response.total_balance)"
        }
        return $true
      }
      Write-Warning2 'Resposta 200 mas campo is_active ausente — prosseguindo...'
      return $true
    }
  }
  catch {
    if ($_.Exception.Response.StatusCode -eq 401) {
      Write-Err 'Chave INVALIDA (401 Unauthorized).'
      Write-Err 'Verifique se a chave esta correta e nao expirou.'
      Write-Info 'Obtenha uma nova em: https://platform.deepseek.com/api_keys'
      return $false
    }
    if ($_.Exception.Response.StatusCode -eq 403) {
      Write-Err 'Acesso negado (403). A conta pode estar suspensa ou sem saldo.'
      return $false
    }
    if ($_.Exception.Response.StatusCode -eq 429) {
      Write-Warning2 'Rate-limited (429) — nao foi possivel validar agora. Prosseguindo...'
      return $true
    }
    Write-Warning2 "Erro na validacao: $_"
    Write-Warning2 'A chave pode funcionar mesmo assim — prosseguindo.'
    return $true
  }

  Write-Warning2 'Resposta inesperada — prosseguindo...'
  return $true
}

function Save-DeepSeekKey {
  param([string]$KeyToSave)

  New-Item -ItemType Directory -Path $ConfigDir -Force | Out-Null
  Set-Content -Path (Join-Path $ConfigDir 'deepseek.key') -Value $KeyToSave -NoNewline

  # Ajusta permissões (equivalente a chmod 600: só o owner lê/escreve)
  try {
    $acl = Get-Acl (Join-Path $ConfigDir 'deepseek.key')
    $acl.SetAccessRuleProtection($true, $false)
    $rule = New-Object System.Security.AccessControl.FileSystemAccessRule(
      $env:USERNAME, 'FullControl', 'Allow'
    )
    $acl.SetAccessRule($rule)
    Set-Acl (Join-Path $ConfigDir 'deepseek.key') $acl
    Write-Ok 'Chave salva e permissões ajustadas'
  }
  catch {
    Write-Warning2 "Nao foi possivel ajustar permissoes ACL: $_"
    Write-Warning2 'A chave esta salva mas pode estar legivel por outros usuarios.'
    Write-Info "Execute manualmente: icacls `"$ConfigDir\deepseek.key`" /inheritance:r /grant:r `"$env:USERNAME:R`""
    Write-Ok "Chave salva em $ConfigDir\deepseek.key"
  }
}

# ── Configuracao do diretorio isolado ────────────────────────────────────────
function New-ConfigDir {
  Write-Header 'Configuracao isolada'

  if (Test-Path $ConfigDir) {
    Write-Ok "Diretorio de config ja existe: $ConfigDir"
  }
  else {
    New-Item -ItemType Directory -Path $ConfigDir -Force | Out-Null
    Write-Ok "Diretorio de config criado: $ConfigDir"
  }

  # Subdiretorios
  New-Item -ItemType Directory -Path (Join-Path $ConfigDir 'skills')   -Force | Out-Null
  New-Item -ItemType Directory -Path (Join-Path $ConfigDir 'commands') -Force | Out-Null
  New-Item -ItemType Directory -Path (Join-Path $ConfigDir 'plugins')  -Force | Out-Null
}

# ── Espelhamento de skills e commands ────────────────────────────────────────
function Copy-SkillsAndCommands {
  Write-Header 'Skills e commands globais'

  $srcSkills   = Join-Path $MainClaudeCfg 'skills'
  $dstSkills   = Join-Path $ConfigDir 'skills'
  $srcCommands = Join-Path $MainClaudeCfg 'commands'
  $dstCommands = Join-Path $ConfigDir 'commands'

  # Skills
  if ((Test-Path $srcSkills) -and (Get-ChildItem $srcSkills -ErrorAction SilentlyContinue)) {
    Write-Info "Copiando skills de $srcSkills → $dstSkills"
    $count = 0
    Get-ChildItem $srcSkills -Directory | ForEach-Object {
      $target = Join-Path $dstSkills $_.Name
      if (-not (Test-Path $target)) {
        Copy-Item $_.FullName $target -Recurse
        $count++
      }
    }
    Write-Ok "$count skill(s) copiada(s)"
  }
  else {
    Write-Info "Nenhuma skill global encontrada em $srcSkills"
    Write-Info "Adicione skills em $dstSkills ou instale plugins."
  }

  # Commands
  if ((Test-Path $srcCommands) -and (Get-ChildItem $srcCommands -ErrorAction SilentlyContinue)) {
    Write-Info "Copiando commands de $srcCommands → $dstCommands"
    $count = 0
    Get-ChildItem $srcCommands -File | ForEach-Object {
      $target = Join-Path $dstCommands $_.Name
      if (-not (Test-Path $target)) {
        Copy-Item $_.FullName $target
        $count++
      }
    }
    Write-Ok "$count command(s) copiado(s)"
  }
  else {
    Write-Info "Nenhum command global encontrado em $srcCommands"
  }
}

# ── Criacao do launcher (.cmd) ──────────────────────────────────────────────
function New-Launcher {
  Write-Header 'Criando launcher deepclaude'

  New-Item -ItemType Directory -Path $BinDir -Force | Out-Null

  # .cmd para Windows (batch) — compatível com cmd.exe, PowerShell e Git Bash
  $launcherContent = @'
@echo off
REM deepclaude — Claude Code com backend DeepSeek V4 Pro
REM Gerado por install-deepclaude.ps1 — nao edite manualmente.
REM Para atualizar a config, rode install-deepclaude.ps1 novamente.

set CONFIG_DIR=%USERPROFILE%\.claude-deepseek

REM Resolver chave: env var → arquivo
if defined DEEPSEEK_CLAUDE_API_KEY (
    set DSKEY=%DEEPSEEK_CLAUDE_API_KEY%
    goto :key_found
)
if exist "%CONFIG_DIR%\deepseek.key" (
    set /p DSKEY=<"%CONFIG_DIR%\deepseek.key"
    goto :key_found
)

echo deepclaude: sem chave da API DeepSeek.
echo Grave a chave em %CONFIG_DIR%\deepseek.key
echo ou defina a variavel DEEPSEEK_CLAUDE_API_KEY
exit /b 1

:key_found
set CLAUDE_CONFIG_DIR=%CONFIG_DIR%
set ANTHROPIC_BASE_URL=https://api.deepseek.com/anthropic
set ANTHROPIC_AUTH_TOKEN=%DSKEY%
set ANTHROPIC_MODEL=deepseek-v4-pro
set ANTHROPIC_DEFAULT_OPUS_MODEL=deepseek-v4-pro
set ANTHROPIC_DEFAULT_SONNET_MODEL=deepseek-v4-pro
set ANTHROPIC_DEFAULT_HAIKU_MODEL=deepseek-v4-pro

claude --dangerously-skip-permissions --effort max %*
'@

  Set-Content -Path $LauncherPath -Value $launcherContent
  Write-Ok "Launcher criado: $LauncherPath"
}

# ── Verificacao de PATH ──────────────────────────────────────────────────────
function Test-PathEnv {
  Write-Header 'Verificando PATH'

  $userPath = [Environment]::GetEnvironmentVariable('PATH', 'User')
  if ($userPath -like "*$BinDir*") {
    Write-Ok "$BinDir esta no PATH do usuario"
    return
  }

  $machinePath = [Environment]::GetEnvironmentVariable('PATH', 'Machine')
  if ($machinePath -like "*$BinDir*") {
    Write-Ok "$BinDir esta no PATH do sistema"
    return
  }

  Write-Warning2 "$BinDir NAO esta no PATH!"
  Write-Info 'Adicione ao PATH do usuario para usar o comando deepclaude:'
  Write-Host ''
  Write-Host "  [System.Environment]::SetEnvironmentVariable('PATH'," -ForegroundColor Cyan
  Write-Host "    `$env:PATH + ';$BinDir', 'User')" -ForegroundColor Cyan
  Write-Host ''
  Write-Info 'Depois reinicie o terminal ou abra uma nova janela.'

  # Oferecer para adicionar automaticamente
  $add = Read-Host -Prompt 'Deseja adicionar ao PATH agora? [S/n]'
  if ($add -eq '' -or $add -eq 'S' -or $add -eq 's' -or $add -eq 'Sim') {
    try {
      [Environment]::SetEnvironmentVariable('PATH',
        [Environment]::GetEnvironmentVariable('PATH', 'User') + ";$BinDir",
        'User')
      $env:PATH += ";$BinDir"
      Write-Ok 'Adicionado ao PATH do usuario. Funcionara em novos terminais.'
    }
    catch {
      Write-Err "Nao foi possivel adicionar ao PATH: $_"
      Write-Info 'Adicione manualmente via: Configuracoes → Sistema → Sobre → Configuracoes avancadas → Variaveis de ambiente'
    }
  }
}

# ── Teste pos-instalacao ─────────────────────────────────────────────────────
function Test-Installation {
  Write-Header 'Teste de instalacao'

  if (Test-Path $LauncherPath) {
    Write-Info 'Testando deepclaude --version...'
    try {
      $result = & cmd.exe /c "$LauncherPath --version" 2>&1
      if ($LASTEXITCODE -eq 0) {
        Write-Ok 'deepclaude respondeu OK'
        Write-Host $result
      }
      else {
        Write-Warning2 'deepclaude --version reportou erro'
        Write-Warning2 'Mas pode funcionar em modo interativo — tente rodar diretamente.'
      }
    }
    catch {
      Write-Warning2 "deepclaude --version falhou: $_"
      Write-Warning2 'Isso e esperado se a chave ainda nao foi configurada.'
    }
  }
  else {
    Write-Warning2 'Launcher nao encontrado — pulando teste.'
  }
}

# ── Resumo final ─────────────────────────────────────────────────────────────
function Write-Summary {
  Write-Header 'Instalacao concluida!'

  Write-Host ''
  Write-Host 'Resumo:' -ForegroundColor White
  Write-Host "  Comando:         deepclaude" -ForegroundColor Cyan
  Write-Host "  Config dir:      $ConfigDir" -ForegroundColor Cyan
  Write-Host "  Chave:           $ConfigDir\deepseek.key" -ForegroundColor Cyan
  Write-Host '  Backend:         DeepSeek V4 Pro'
  Write-Host '  Endpoint:        https://api.deepseek.com/anthropic'
  Write-Host ''
  Write-Host 'Proximos passos:' -ForegroundColor White
  Write-Host '  1. Reinicie o terminal ou abra uma nova janela'
  Write-Host '  2. Rode: deepclaude' -ForegroundColor Cyan
  Write-Host '  3. Na primeira execucao, responda as perguntas de tema e trust'
  Write-Host "  4. Para adicionar skills globais, copie para $ConfigDir\skills\"
  Write-Host ''
  Write-Host 'Limitacoes (DeepSeek V4 Pro vs Claude oficial):' -ForegroundColor White
  Write-Host '  - Sem visao (imagens/PDFs sao degradados silenciosamente)'
  Write-Host '  - Sem MCP remoto (server-side); MCP local/stdio funciona'
  Write-Host '  - Sem ZDR (Zero Data Retention) — NUNCA use com codigo sensivel' -ForegroundColor Red
  Write-Host '  - Propenso a alucinacoes (~94% no benchmark AA-Omniscience)'
  Write-Host '  - Custo: ~34× mais barato que Opus (pre-pago)'
  Write-Host ''
  Write-Host 'Se o Claude original parar de funcionar:' -ForegroundColor White
  Write-Host '  As instalacoes sao isoladas por env vars — a original nao foi alterada.'
  Write-Host "  Se precisar reverter: apague $ConfigDir e $LauncherPath"
  Write-Host ''
}

# ══════════════════════════════════════════════════════════════════════════════
# main
# ══════════════════════════════════════════════════════════════════════════════

Write-Host ''
Write-Host '╔══════════════════════════════════════════════════════╗' -ForegroundColor Cyan
Write-Host '║  install-deepclaude.ps1                             ║' -ForegroundColor Cyan
Write-Host '║  Claude Code + DeepSeek V4 Pro — Windows Native     ║' -ForegroundColor Cyan
Write-Host '╚══════════════════════════════════════════════════════╝' -ForegroundColor Cyan
Write-Host ''

Write-Ok 'Sistema: Windows (PowerShell)'

# 1. Pre-requisitos
Check-Prereqs

# 2. Claude Code
$null = Find-OrInstallClaude

# 3. DeepSeek API key
if ($NoKey) {
  Write-Warning2 'Modo -NoKey: pulando configuracao da chave.'
}
else {
  $DSKEY = Resolve-DeepSeekKey
  if (Test-DeepSeekKey $DSKEY) {
    Save-DeepSeekKey $DSKEY
  }
  else {
    $proceed = Read-Host -Prompt 'Validacao falhou. Salvar chave mesmo assim? [s/N]'
    if ($proceed -eq 's' -or $proceed -eq 'S' -or $proceed -eq 'sim') {
      Save-DeepSeekKey $DSKEY
    }
    else {
      Write-Err 'Abortando. Corrija a chave e rode novamente.'
      exit 1
    }
  }
}

# 4. Config dir
New-ConfigDir

# 5. Mirror skills/commands
Copy-SkillsAndCommands

# 6. Create launcher
New-Launcher

# 7. PATH check
Test-PathEnv

# 8. Test
Test-Installation

# 9. Summary
Write-Summary
