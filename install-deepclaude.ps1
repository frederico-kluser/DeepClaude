#!/usr/bin/env pwsh
<#
.SYNOPSIS
  Instalador cross-platform do deepclaude — Windows nativo (PowerShell)
.DESCRIPTION
  Instala e configura o binário OFICIAL do Claude Code com o backend trocado
  para o DeepSeek via endpoint Anthropic-compatível. Cria uma segunda
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
  [string]$Name = 'deepseek',
  [string]$Dir = '',
  [string]$Command = '',
  [string]$SkillsFrom = '',
  [switch]$NoSkills = $false,
  [switch]$NoKey = $false,
  [switch]$Help = $false
)

$ErrorActionPreference = 'Stop'
# PowerShell 5.1+ (Windows 10+) ou PowerShell 7+ (recomendado)

# ── Help ─────────────────────────────────────────────────────────────────────
if ($Help) {
  Write-Host @"
Uso: .\install-deepclaude.ps1 [opcoes]

Cria uma AREA NOVA do Claude Code apontada para o DeepSeek. A area default
(~\.claude) nunca e tocada e o `claude` existente nao e substituido.

  -Name <nome>       Nome da area. Define dir e comando:
                       (padrao)      -> ~\.claude-deepseek       + deepclaude
                       -Name x       -> ~\.claude-deepseek-x     + deepclaude-x
  -Dir <caminho>     Dir da area explicito (precede -Name)
  -Command <nome>    Nome do comando gerado
  -Key sk-...        Fornece a chave da API DeepSeek
  -NoKey             Pula a validacao da chave (configure depois)
  -SkillsFrom <dir>  Area de onde copiar skills (default: ~\.claude)
  -NoSkills          Nao copia skills/commands
  -Help              Mostra esta ajuda

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

# ── Areas de instalacao ─────────────────────────────────────────────────────
# Uma "area" e um CLAUDE_CONFIG_DIR proprio. O binario `claude` e COMPARTILHADO
# entre todas; o isolamento e por variavel de ambiente, nunca por reinstalar.
#
# 🔴 A area default (~\.claude) e INTOCAVEL: e onde o `claude` sem env var
# guarda login e historico. Escrever ali seria o "replace" que este projeto
# existe para evitar. Cada -Name cria uma area NOVA.
$Script:DefaultArea = 'deepseek'

if ($Name -notmatch '^[A-Za-z0-9._-]+$') {
  Write-Host "Nome de area invalido: '$Name' - use so letras, numeros, . _ -" -ForegroundColor Red
  exit 1
}

if ($Dir) {
  $Script:ConfigDir = $Dir.Replace('~', $env:USERPROFILE)
}
elseif ($Name -eq $Script:DefaultArea) {
  $Script:ConfigDir = Join-Path $env:USERPROFILE '.claude-deepseek'   # compat
}
else {
  $Script:ConfigDir = Join-Path $env:USERPROFILE ".claude-deepseek-$Name"
}

if ($Command)                        { $Script:LauncherName = "$Command.cmd" }
elseif ($Name -eq $Script:DefaultArea) { $Script:LauncherName = 'deepclaude.cmd' }
else                                 { $Script:LauncherName = "deepclaude-$Name.cmd" }

$Script:BinDir       = Join-Path $env:USERPROFILE '.local\bin'
$Script:LauncherPath = Join-Path $BinDir $Script:LauncherName
# Area de ORIGEM das skills — somente leitura, nada e escrito nela.
if ($SkillsFrom) { $Script:MainClaudeCfg = $SkillsFrom.Replace('~', $env:USERPROFILE) }
else             { $Script:MainClaudeCfg = Join-Path $env:USERPROFILE '.claude' }

# ── Gate: nunca a area default ──────────────────────────────────────────────
function Assert-AreaIsSafe {
  $defaultArea = Join-Path $env:USERPROFILE '.claude'
  $a = $Script:ConfigDir.TrimEnd('\', '/')
  $b = $defaultArea.TrimEnd('\', '/')
  if ($a -ieq $b) {
    Write-Err "Recusado: '$Script:ConfigDir' e a area DEFAULT do Claude Code."
    Write-Err 'Este instalador cria uma area NOVA e nunca substitui a default.'
    Write-Err 'Use -Name <nome> ou -Dir <caminho> para escolher outra.'
    exit 1
  }

  # Anti-mistura: dir que ja tem login de outra conta.
  if (Test-Path $Script:ConfigDir) {
    $hasClaudeLogin = Test-Path (Join-Path $Script:ConfigDir '.credentials.json')
    $hasDsKey       = Test-Path (Join-Path $Script:ConfigDir 'deepseek.key')
    if ($hasClaudeLogin -and -not $hasDsKey) {
      Write-Err "Recusado: '$Script:ConfigDir' ja contem login de outra conta."
      Write-Err 'Reaproveitar esse dir misturaria dois cadastros. Escolha outro -Dir.'
      exit 1
    }
  }
}

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

  $uri     = 'https://api.deepseek.com/user/balance'
  $headers = @{ Authorization = "Bearer $KeyToTest" }
  $code    = 0
  $body    = $null

  # 🔴 -StatusCodeVariable e -SkipHttpErrorCheck só existem no PowerShell 7+.
  # No 5.1 — que é o padrão do Windows 10/11 e o mínimo que este script promete
  # suportar — eles dão erro de binding de parâmetro, o erro caía no catch
  # genérico com $_.Exception.Response nulo e a função devolvia $true.
  # Resultado: no Windows "de fábrica" a chave NUNCA era validada de verdade.
  if ($PSVersionTable.PSVersion.Major -ge 7) {
    try {
      $body = Invoke-RestMethod -Uri $uri -Headers $headers `
        -StatusCodeVariable 'code' -SkipHttpErrorCheck -TimeoutSec 15
    }
    catch {
      Write-Warning2 "Erro de rede ao validar: $_"
      Write-Warning2 'A chave pode funcionar mesmo assim - prosseguindo.'
      return $true
    }
  }
  else {
    try {
      $resp = Invoke-WebRequest -Uri $uri -Headers $headers -TimeoutSec 15 -UseBasicParsing
      $code = [int]$resp.StatusCode
      $body = $resp.Content | ConvertFrom-Json
    }
    catch {
      if ($_.Exception.Response) {
        $code = [int]$_.Exception.Response.StatusCode
      }
      else {
        Write-Warning2 "Erro de rede ao validar: $_"
        Write-Warning2 'A chave pode funcionar mesmo assim - prosseguindo.'
        return $true
      }
    }
  }

  switch ($code) {
    200 {
      if ($body -and $body.is_active) {
        Write-Ok 'Chave valida'
        $bal = $null
        if ($body.balance_infos -and $body.balance_infos.Count -gt 0) {
          $bal = "$($body.balance_infos[0].currency) $($body.balance_infos[0].total_balance)"
        }
        if ($bal) { Write-Info "Saldo: $bal" }
        return $true
      }
      Write-Warning2 'Resposta 200 mas is_active ausente - prosseguindo...'
      return $true
    }
    401 {
      Write-Err 'Chave INVALIDA (401 Unauthorized).'
      Write-Err 'Verifique se a chave esta correta e nao expirou.'
      Write-Info 'Obtenha uma nova em: https://platform.deepseek.com/api_keys'
      return $false
    }
    402 {
      # 402 != 401: a chave foi ACEITA, o que falta e saldo.
      Write-Warning2 '402 Insufficient Balance - a chave e VALIDA, falta saldo.'
      Write-Info 'Recarregue em: https://platform.deepseek.com/top_up'
      return $true
    }
    403 {
      Write-Err 'Acesso negado (403). A conta pode estar suspensa.'
      return $false
    }
    429 {
      Write-Warning2 'Rate-limited (429) - nao deu para validar agora. Prosseguindo...'
      return $true
    }
    default {
      Write-Warning2 "Resposta inesperada (HTTP $code) - prosseguindo..."
      return $true
    }
  }
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
REM deepclaude - Claude Code oficial com o cerebro do DeepSeek.
REM Gerado por install-deepclaude.ps1 - rode o instalador de novo para atualizar.
REM
REM Padrao: deepseek-v4-flash[1m]  |  slot fable: deepseek-v4-pro[1m]
REM O alias `deepseek-v4-flash` serve o build 0731 (uso de ferramenta) e o
REM `deepseek-v4-pro` serve o 0813. Para agente de terminal o flash ganha nos
REM sub-indices independentes (agentic 48,4 x 37,8) e custa 1/3.
REM Trocar: `/model fable` dentro da sessao, ou `deepclaude --pro`.
REM
REM Nomes que NAO existem nesta API (HTTP 400): deepseek-v4-flash-0731,
REM deepseek-v4-pro-0813, deepseek/deepseek-*. Os dois ultimos sao do OpenRouter.

REM 🔴 setlocal e OBRIGATORIO: sem ele as variaveis abaixo VAZAM para a sessao
REM do cmd e o `claude` original passaria a falar com a DeepSeek na mesma
REM janela. O isolamento desta instalacao depende desta linha.
setlocal

if not defined DEEPCLAUDE_DIR       set "DEEPCLAUDE_DIR=__DEEPCLAUDE_AREA_DIR__"
if not defined DEEPCLAUDE_MODEL     set "DEEPCLAUDE_MODEL=deepseek-v4-flash[1m]"
if not defined DEEPCLAUDE_FABLE_MODEL set "DEEPCLAUDE_FABLE_MODEL=deepseek-v4-pro[1m]"
if not defined DEEPCLAUDE_BASE_URL  set "DEEPCLAUDE_BASE_URL=https://api.deepseek.com/anthropic"
if not defined DEEPCLAUDE_MAX_CONTEXT_TOKENS set "DEEPCLAUDE_MAX_CONTEXT_TOKENS=1048576"

set "CONFIG_DIR=%DEEPCLAUDE_DIR%"
set "MODEL=%DEEPCLAUDE_MODEL%"

REM Parse de --pro. O `shift` do batch NAO altera %*, entao a lista de
REM argumentos precisa ser reconstruida a mao. Usa-se %1 (com aspas) e nao %~1
REM para preservar argumentos com espaco.
set "ARGS="
:dc_parse
if "%~1"=="" goto dc_parsed
if /i "%~1"=="--pro" goto dc_setpro
set "ARGS=%ARGS% %1"
shift
goto dc_parse
:dc_setpro
set "MODEL=deepseek-v4-pro[1m]"
echo deepclaude: sessao no deepseek-v4-pro 1>&2
shift
goto dc_parse
:dc_parsed

if not defined DEEPCLAUDE_HAIKU_MODEL set "DEEPCLAUDE_HAIKU_MODEL=%MODEL%"

REM Chave: env explicita vence o arquivo. DEEPSEEK_CLAUDE_API_KEY fica por
REM compatibilidade com instalacoes anteriores a 2026-08-13.
set "DSKEY="
if defined DEEPCLAUDE_API_KEY      set "DSKEY=%DEEPCLAUDE_API_KEY%"
if not defined DSKEY if defined DEEPSEEK_CLAUDE_API_KEY set "DSKEY=%DEEPSEEK_CLAUDE_API_KEY%"
if not defined DSKEY if exist "%CONFIG_DIR%\deepseek.key" set /p DSKEY=<"%CONFIG_DIR%\deepseek.key"

if not defined DSKEY (
    echo deepclaude: sem chave da API DeepSeek. 1>&2
    echo Grave a chave em %CONFIG_DIR%\deepseek.key 1>&2
    echo ou defina a variavel DEEPCLAUDE_API_KEY 1>&2
    exit /b 1
)

set "CLAUDE_CONFIG_DIR=%CONFIG_DIR%"
set "ANTHROPIC_BASE_URL=%DEEPCLAUDE_BASE_URL%"
set "ANTHROPIC_AUTH_TOKEN=%DSKEY%"
set "ANTHROPIC_MODEL=%MODEL%"
set "ANTHROPIC_DEFAULT_OPUS_MODEL=%MODEL%"
set "ANTHROPIC_DEFAULT_SONNET_MODEL=%MODEL%"
set "ANTHROPIC_DEFAULT_HAIKU_MODEL=%DEEPCLAUDE_HAIKU_MODEL%"
set "ANTHROPIC_DEFAULT_FABLE_MODEL=%DEEPCLAUDE_FABLE_MODEL%"
set "CLAUDE_CODE_SUBAGENT_MODEL=%MODEL%"
set "CLAUDE_CODE_MAX_CONTEXT_TOKENS=%DEEPCLAUDE_MAX_CONTEXT_TOKENS%"
REM Em batch, `set VAR=` REMOVE a variavel (equivalente ao `env -u` do Unix).
REM O ANTHROPIC_AUTH_TOKEN ja vence na precedencia, mas remover elimina a
REM ambiguidade se o usuario tiver uma ANTHROPIC_API_KEY no ambiente.
set "ANTHROPIC_API_KEY="

claude --dangerously-skip-permissions --effort max%ARGS%
exit /b %ERRORLEVEL%
'@

  # O here-string e literal (@'...'@) de proposito: o .cmd esta cheio de %VAR% e
  # nao pode sofrer interpolacao do PowerShell. O unico valor dinamico entra por
  # substituicao de placeholder, para a area escolhida em -Name/-Dir valer.
  $launcherContent = $launcherContent.Replace('__DEEPCLAUDE_AREA_DIR__', $Script:ConfigDir)

  # Nao sobrescrever cegamente um launcher existente.
  if (Test-Path $LauncherPath) {
    $bak = "$LauncherPath.bak-$(Get-Date -Format 'yyyyMMddHHmmss')"
    Copy-Item $LauncherPath $bak -Force
    Write-Warning2 "Launcher existente salvo em $bak"
  }

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
  Write-Host '  Endpoint:        https://api.deepseek.com/anthropic'
  Write-Host '  Modelo:          deepseek-v4-flash[1m]   (slot fable: deepseek-v4-pro[1m])' -ForegroundColor Cyan
  Write-Host ''
  Write-Host 'Proximos passos:' -ForegroundColor White
  Write-Host '  1. Reinicie o terminal ou abra uma nova janela'
  Write-Host '  2. Rode: deepclaude' -ForegroundColor Cyan
  Write-Host '  3. Na primeira execucao responda tema e trust (nao ha /login)'
  Write-Host "  4. Para adicionar skills globais, copie para $ConfigDir\skills\"
  Write-Host ''
  Write-Host 'Trocar de modelo:' -ForegroundColor White
  Write-Host '  /model fable       dentro da sessao -> V4 Pro   (/model sonnet volta)' -ForegroundColor Cyan
  Write-Host '  deepclaude --pro   sessao inteira no V4 Pro' -ForegroundColor Cyan
  Write-Host ''
  Write-Host '  O padrao e o flash de proposito: o alias serve o build 0731, focado em'
  Write-Host '  uso de ferramenta, e os sub-indices independentes da OpenRouter dao'
  Write-Host '  agentic 48,4 (flash) x 37,8 (pro) - por 1/3 do preco.'
  Write-Host ''
  Write-Host 'Limitacoes (vs Claude oficial):' -ForegroundColor White
  Write-Host '  - Sem visao - imagem/PDF NAO dao erro, voltam como placeholder' -ForegroundColor Yellow
  Write-Host '    (HTTP 200 com resposta errada e pior que falha)'
  Write-Host '  - Sem MCP remoto (server-side); MCP local/stdio funciona'
  Write-Host '  - Sem ZDR - NUNCA use com codigo sensivel/corporativo' -ForegroundColor Red
  Write-Host '  - Alucina mais que o Claude (~94% no AA-Omniscience), inclusive sobre a'
  Write-Host '    propria identidade: nao pergunte a ele qual modelo ele e'
  Write-Host ''
  Write-Host 'Custo:' -ForegroundColor White
  Write-Host '  flash US$ 0,14 entrada / US$ 0,28 saida por M  |  pro US$ 0,435 / 0,87'
  Write-Host '  ATENCAO: a DeepSeek passa a cobrar por horario em 2026-08-16 16:00 UTC' -ForegroundColor Yellow
  Write-Host '    (peak 01:00-04:00 e 06:00-10:00 UTC; cache hit fica 6-12x mais caro)'
  Write-Host '  O total_cost_usd que o Claude Code reporta e inutil aqui (usa a tabela da'
  Write-Host '  Anthropic e erra ~12x). Custo real e o saldo em /user/balance.'
  Write-Host ''
  Write-Host 'Isolamento:' -ForegroundColor White
  Write-Host '  O binario `claude` e compartilhado; o desvio e so por env var DENTRO do'
  Write-Host '  launcher (que usa setlocal, entao nada vaza para a sua sessao do cmd).'
  Write-Host '  A instalacao original do Claude Code nao foi alterada.'
  Write-Host "  Reverter: apague $ConfigDir e $LauncherPath"
  Write-Host ''
}

# ══════════════════════════════════════════════════════════════════════════════
# main
# ══════════════════════════════════════════════════════════════════════════════

Write-Host ''
Write-Host '╔══════════════════════════════════════════════════════╗' -ForegroundColor Cyan
Write-Host '║  install-deepclaude.ps1                             ║' -ForegroundColor Cyan
Write-Host '║  Claude Code + DeepSeek — Windows Native            ║' -ForegroundColor Cyan
Write-Host '╚══════════════════════════════════════════════════════╝' -ForegroundColor Cyan
Write-Host ''

Write-Ok 'Sistema: Windows (PowerShell)'

# 0. Area — resolve e valida ANTES de escrever qualquer coisa
Write-Header 'Area de instalacao'
Write-Info "Area:     $Script:ConfigDir"
Write-Info "Comando:  $Script:LauncherName"
Write-Info 'Default do Claude Code (~\.claude): intocada'
Assert-AreaIsSafe

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
