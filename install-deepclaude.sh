#!/usr/bin/env bash
# shellcheck disable=SC2059,SC2088
#━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
# install-deepclaude.sh — Instalador cross-platform do deepclaude
# ────────────────────────────────────────────────────────────────────────────
# Instala e configura o binário OFICIAL do Claude Code com o backend trocado
# para o DeepSeek V4 Pro via endpoint Anthropic-compatível. Cria uma segunda
# instalação ISOLADA (sem quebrar a original) e expõe o comando `deepclaude`.
#
# Compatível com: Linux, macOS, Windows (Git Bash / WSL)
# Contraparte Windows nativa: install-deepclaude.ps1
#
# Uso:
#   chmod +x install-deepclaude.sh
#   ./install-deepclaude.sh              # instalação interativa
#   ./install-deepclaude.sh --key=sk-... # fornece a chave na linha de comando
#   ./install-deepclaude.sh --no-key     # pula validação da chave (instala depois)
#   DEEPSEEK_CLAUDE_API_KEY=sk-... ./install-deepclaude.sh  # chave via env
#
# O que ele faz:
#   1. Detecta o SO (Linux / macOS / Windows-GitBash)
#   2. Verifica/instala o binário `claude` (oficial + fallback npm)
#   3. Localiza/valida a chave da API DeepSeek
#   4. Cria o dir de config isolado (~/.claude-deepseek/)
#   5. Espelha skills/commands globais da instalação original
#   6. Gera o launcher `deepclaude` em ~/.local/bin/ (ou %USERPROFILE% no Win)
#   7. Verifica PATH e testa a instalação
#━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
set -uo pipefail

# ── Cores ───────────────────────────────────────────────────────────────────
RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'
BLUE='\033[0;34m'; CYAN='\033[0;36m'; BOLD='\033[1m'; NC='\033[0m'

# 🔴 TODO log vai para STDERR — não é estilo, é correção de bug.
# Funções como `resolve_deepseek_key` devolvem valor por stdout e são chamadas em
# `$( )`. Enquanto info/ok/header escreviam em stdout, a substituição capturava
# a MENSAGEM junto com o valor: a chave virava "\033[0;32m✓\033[0m Chave via
# env\nsk-..." e ia inteira no header Authorization → 401 em todos os caminhos.
# Pior, `save_deepseek_key` gravava isso no arquivo e o launcher lê `head -n1`,
# ou seja pegava a linha da MENSAGEM. E no modo interativo o próprio prompt era
# capturado, então a pergunta não aparecia e o script parecia travado.
# Regra: se a função devolve valor por stdout, nada mais pode escrever lá.
info()    { printf "${BLUE}ℹ${NC} %s\n" "$*" >&2; }
ok()      { printf "${GREEN}✓${NC} %s\n" "$*" >&2; }
warn()    { printf "${YELLOW}⚠${NC} %s\n" "$*" >&2; }
err()     { printf "${RED}✗${NC} %s\n" "$*" >&2; }
header()  { printf "\n${BOLD}${CYAN}═══ %s ═══${NC}\n" "$*" >&2; }
say()     { printf "%b\n" "$*" >&2; }   # texto livre (resumo final)

# ── Detecção de SO ──────────────────────────────────────────────────────────
detect_os() {
  local os
  case "$(uname -s)" in
    Linux)  os='linux' ;;
    Darwin) os='macos' ;;
    MINGW*|MSYS*|CYGWIN*) os='windows-gitbash' ;;
    *)
      if [[ "$(uname -s)" == *"_NT"* ]]; then
        os='windows-gitbash'
      else
        err "Sistema operacional não reconhecido: $(uname -s)"
        err "Este script suporta Linux, macOS e Windows (Git Bash / WSL)."
        err "Para Windows nativo (PowerShell), use: install-deepclaude.ps1"
        exit 1
      fi
      ;;
  esac
  printf '%s' "$os"
}

# ── Helpers de caminho ──────────────────────────────────────────────────────
config_dir() {
  # Diretório de config isolado da conta deepclaude
  case "$OS" in
    windows-gitbash) printf '%s/.claude-deepseek' "$HOME" ;;
    *)               printf '%s/.claude-deepseek' "$HOME" ;;
  esac
}

bin_dir() {
  # Diretório onde o launcher será instalado
  case "$OS" in
    windows-gitbash) printf '%s' "$HOME" ;;  # %USERPROFILE% é o HOME do Git Bash
    macos)           printf '%s/.local/bin' "$HOME" ;;
    *)               printf '%s/.local/bin' "$HOME" ;;
  esac
}

launcher_path() {
  case "$OS" in
    windows-gitbash) printf '%s/deepclaude' "$(bin_dir)" ;;
    *)               printf '%s/deepclaude' "$(bin_dir)" ;;
  esac
}

main_claude_config() {
  # Config dir da instalação principal do Claude (a original)
  case "$OS" in
    windows-gitbash) printf '%s/.claude' "$HOME" ;;
    macos)           printf '%s/.claude' "$HOME" ;;
    *)               printf '%s/.claude' "$HOME" ;;
  esac
}

# ── Verificação de pré-requisitos ───────────────────────────────────────────
check_prereqs() {
  header 'Verificando pré-requisitos'

  local missing=()

  if ! command -v curl &>/dev/null; then
    missing+=('curl')
  fi

  if [[ ${#missing[@]} -gt 0 ]]; then
    err "Pré-requisitos faltando: ${missing[*]}"
    case "$OS" in
      linux)
        info "Instale com: sudo apt install ${missing[*]}  (Debian/Ubuntu/Pop)"
        info "         ou: sudo dnf install ${missing[*]}  (Fedora)"
        info "         ou: sudo pacman -S ${missing[*]}     (Arch)"
        ;;
      macos)
        info "Instale com: brew install ${missing[*]}"
        ;;
      windows-gitbash)
        info "Instale o Git for Windows (inclui curl): https://git-scm.com/download/win"
        ;;
    esac
    exit 1
  fi

  ok "Pré-requisitos OK (curl)"
}

# ── Instalação do binário Claude Code ───────────────────────────────────────
find_or_install_claude() {
  header 'Binário Claude Code'

  # Já existe? Então NÃO mexemos: nada de reinstalar, atualizar ou trocar de
  # canal. O deepclaude compartilha o MESMO binário e se isola por env var —
  # instalar por cima só arriscaria quebrar a instalação que já funciona.
  if command -v claude &>/dev/null; then
    local claude_path
    claude_path="$(command -v claude)"
    local claude_version
    claude_version="$(claude --version 2>/dev/null || echo 'desconhecida')"
    ok "Claude Code encontrado: ${claude_path} (${claude_version})"
    info "Mantido como está — o deepclaude reusa este binário e se isola por CLAUDE_CONFIG_DIR."
    printf '%s' "$claude_path"
    return 0
  fi

  info "Claude Code não encontrado. Instalando..."

  # ⚠️ A saída dos instaladores vai para STDERR: esta função devolve o caminho
  # do binário por stdout e é chamada em $( ). Sem o redirecionamento, o log do
  # curl/npm entraria no valor capturado.
  # Opção 1: Instalador oficial (Linux/macOS)
  if [[ "$OS" == 'linux' || "$OS" == 'macos' ]]; then
    info "Tentando instalador oficial (claude.ai/install.sh)..."
    if curl -fsSL https://claude.ai/install.sh | bash >&2; then
      if command -v claude &>/dev/null; then
        ok "Claude Code instalado via instalador oficial"
        printf '%s' "$(command -v claude)"
        return 0
      fi
    fi
    warn "Instalador oficial falhou, tentando via npm..."
  fi

  # Opção 2: npm (cross-platform, sempre funciona)
  if ! command -v npm &>/dev/null && ! command -v node &>/dev/null; then
    err "Node.js/npm não encontrado — necessário para instalar o Claude Code."
    err "Instale o Node.js 18+: https://nodejs.org"
    case "$OS" in
      linux)
        info "  ou: curl -fsSL https://deb.nodesource.com/setup_lts.x | sudo -E bash - && sudo apt install -y nodejs"
        ;;
      macos)
        info "  ou: brew install node"
        ;;
    esac
    exit 1
  fi

  info "Instalando @anthropic-ai/claude-code via npm..."
  if npm i -g @anthropic-ai/claude-code >&2; then
    if command -v claude &>/dev/null; then
      ok "Claude Code instalado via npm"
      printf '%s' "$(command -v claude)"
      return 0
    fi
  fi

  err "Falha ao instalar o Claude Code."
  err "Tente manualmente: curl -fsSL https://claude.ai/install.sh | bash"
  err "              ou: npm i -g @anthropic-ai/claude-code"
  exit 1
}

# ── DeepSeek API Key ────────────────────────────────────────────────────────
resolve_deepseek_key() {
  # Resolve a chave na ordem: env var → arquivo → prompt
  local dir="$1"
  local key="${DEEPSEEK_CLAUDE_API_KEY:-}"

  # 1. Env var
  if [[ -n "$key" ]]; then
    ok "Chave DeepSeek via DEEPSEEK_CLAUDE_API_KEY (env)"
    printf '%s' "$key"
    return 0
  fi

  # 2. Flag --key=... no args (setado pelo caller)
  if [[ -n "${ARG_KEY:-}" ]]; then
    ok "Chave DeepSeek via --key"
    printf '%s' "$ARG_KEY"
    return 0
  fi

  # 3. Arquivo existente
  if [[ -r "$dir/deepseek.key" ]]; then
    key="$(head -n1 "$dir/deepseek.key")"
    if [[ -n "$key" ]]; then
      ok "Chave DeepSeek encontrada em $dir/deepseek.key"
      printf '%s' "$key"
      return 0
    fi
  fi

  # 4. Prompt interativo
  if [[ -t 0 ]]; then
    printf '\n' >&2
    info "Chave da API DeepSeek necessária."
    info "Obtenha uma em: https://platform.deepseek.com/api_keys"
    # Prompt em stderr: em stdout ele seria capturado pelo $( ) e ficaria invisível.
    printf "${BOLD}Chave (sk-...):${NC} " >&2
    IFS= read -r key
    if [[ -z "$key" ]]; then
      err "Nenhuma chave fornecida. Abortando."
      exit 1
    fi
    printf '%s' "$key"
    return 0
  fi

  err "Sem chave da API DeepSeek e sem terminal interativo."
  err "Forneça a chave com: DEEPSEEK_CLAUDE_API_KEY=sk-... $0"
  err "               ou: $0 --key=sk-..."
  exit 1
}

validate_deepseek_key() {
  local key="$1"
  local balance_url='https://api.deepseek.com/user/balance'

  info "Validando chave DeepSeek..."

  local response http_code
  response="$(curl -s -w '\n%{http_code}' \
    -H "Authorization: Bearer ${key}" \
    "$balance_url" 2>/dev/null)" || true

  http_code="$(printf '%s' "$response" | tail -n1)"
  local body
  body="$(printf '%s' "$response" | sed '$d')"

  case "$http_code" in
    200)
      # O campo é `is_available` (não `is_active`) e `total_balance` vem como
      # STRING entre aspas — as duas coisas foram conferidas contra a resposta
      # real: {"is_available":true,"balance_infos":[{"currency":"USD",
      #        "total_balance":"3.80","granted_balance":"0.00",...}]}
      local available currency balance
      available="$(printf '%s' "$body" | grep -o '"is_available"[[:space:]]*:[[:space:]]*\(true\|false\)' | grep -o '\(true\|false\)$' || true)"
      currency="$(printf '%s' "$body" | grep -o '"currency"[[:space:]]*:[[:space:]]*"[^"]*"' | head -1 | grep -o '"[^"]*"$' | tr -d '"' || true)"
      balance="$(printf '%s' "$body" | grep -o '"total_balance"[[:space:]]*:[[:space:]]*"[^"]*"' | head -1 | grep -o '"[^"]*"$' | tr -d '"' || true)"

      ok "Chave válida — autenticou no endpoint de saldo"
      [[ -n "$balance" ]] && info "Saldo: ${currency:-USD} ${balance}"

      # Chave boa + carteira vazia é um estado REAL e confuso: o install passa,
      # mas toda chamada ao modelo devolve 402 Insufficient Balance. Vale avisar
      # aqui, senão o usuário culpa a instalação.
      if [[ "$available" == 'false' ]]; then
        warn "A chave funciona, mas a carteira está SEM SALDO (is_available: false)."
        warn "O deepclaude vai subir e devolver 'API Error: 402 Insufficient Balance'"
        warn "em toda chamada até você recarregar em https://platform.deepseek.com"
      fi
      return 0
      ;;
    401)
      err "Chave INVÁLIDA (401 Unauthorized)."
      err "Verifique se a chave está correta e não expirou."
      err "Obtenha uma nova em: https://platform.deepseek.com/api_keys"
      return 1
      ;;
    402)
      # 402 != 401 e a diferença importa: a chave foi ACEITA, falta é saldo.
      warn "402 Insufficient Balance — a chave é VÁLIDA, o que falta é saldo."
      info "Recarregue em: https://platform.deepseek.com/top_up"
      info "A instalação continua; o deepclaude só vai responder após a recarga."
      return 0
      ;;
    403)
      err "Acesso negado (403). A conta pode estar suspensa ou sem saldo."
      return 1
      ;;
    429)
      warn "Rate-limited (429) — não foi possível validar agora. Prosseguindo..."
      return 0
      ;;
    *)
      warn "Resposta inesperada do endpoint de validação (HTTP ${http_code})."
      warn "A chave pode funcionar mesmo assim — prosseguindo."
      info "Resposta: $(printf '%s' "$body" | head -c 200)"
      return 0
      ;;
  esac
}

sanitize_key() {
  # Remove CR (arquivo salvo no Windows), espaços nas pontas e qualquer coisa
  # após a primeira linha. O launcher lê com `head -n1`, então uma chave com
  # lixo na frente falharia com 401 sem explicar o porquê.
  printf '%s' "$1" | head -n1 | tr -d '\r' | sed 's/^[[:space:]]*//; s/[[:space:]]*$//'
}

save_deepseek_key() {
  local dir="$1" key="$2"

  mkdir -p "$dir"
  chmod 700 "$dir" 2>/dev/null || true
  printf '%s\n' "$key" > "$dir/deepseek.key"
  chmod 600 "$dir/deepseek.key"
  ok "Chave salva em $dir/deepseek.key (chmod 600)"

  # Sanity check: o launcher vai ler exatamente isto.
  local readback; readback="$(head -n1 "$dir/deepseek.key")"
  if [[ "$readback" != "$key" ]]; then
    err "O que foi gravado não bate com a chave fornecida — abortando para não deixar instalação quebrada."
    exit 1
  fi
}

# ── Configuração do diretório isolado ───────────────────────────────────────
setup_config_dir() {
  local cfg="$1"

  header 'Configuração isolada'

  if [[ -d "$cfg" ]]; then
    ok "Diretório de config já existe: $cfg"
  else
    mkdir -p "$cfg"
    ok "Diretório de config criado: $cfg"
  fi

  # Subdiretórios obrigatórios
  mkdir -p "$cfg/skills" "$cfg/commands" "$cfg/plugins"
}

# ── Espelhamento de skills e commands globais ────────────────────────────────
mirror_skills_and_commands() {
  local src="$1" dst="$2"

  header 'Skills e commands globais'

  local mirrored_skills=0 mirrored_commands=0

  # Skills
  if [[ -d "$src/skills" ]] && [[ -n "$(ls -A "$src/skills" 2>/dev/null)" ]]; then
    info "Espelhando skills de $src/skills/ → $dst/skills/"
    for skill_dir in "$src/skills"/*/; do
      [[ -d "$skill_dir" ]] || continue
      local skill_name; skill_name="$(basename "$skill_dir")"
      local target="$dst/skills/$skill_name"

      if [[ -e "$target" ]]; then
        continue  # já existe
      fi

      case "$OS" in
        windows-gitbash)
          # Git Bash no Windows: symlinks às vezes funcionam, mas cópia é mais seguro
          cp -r "$skill_dir" "$target"
          ;;
        *)
          # Linux/macOS: symlink para que updates na fonte propaguem
          ln -s "$skill_dir" "$target"
          ;;
      esac
      ((mirrored_skills++))
    done
    ok "${mirrored_skills} skill(s) espelhada(s)"
  else
    info "Nenhuma skill global encontrada em $src/skills/ — diretório skills/ criado vazio."
    info "Adicione skills em $dst/skills/ ou instale via plugins."
  fi

  # Commands
  if [[ -d "$src/commands" ]] && [[ -n "$(ls -A "$src/commands" 2>/dev/null)" ]]; then
    info "Espelhando commands de $src/commands/ → $dst/commands/"
    for cmd_file in "$src/commands"/*; do
      [[ -f "$cmd_file" ]] || continue
      local cmd_name; cmd_name="$(basename "$cmd_file")"
      local target="$dst/commands/$cmd_name"

      if [[ -e "$target" ]]; then
        continue
      fi

      case "$OS" in
        windows-gitbash) cp "$cmd_file" "$target" ;;
        *)               ln -s "$cmd_file" "$target" ;;
      esac
      ((mirrored_commands++))
    done
    ok "${mirrored_commands} command(s) espelhado(s)"
  else
    info "Nenhum command global encontrado em $src/commands/ — diretório commands/ criado vazio."
  fi

  # Aviso sobre skills quebradas (comum)
  local broken=0
  for symlink in "$dst/skills"/*/ "$dst/commands"/*; do
    if [[ -L "$symlink" ]] && [[ ! -e "$symlink" ]]; then
      ((broken++))
    fi
  done
  if [[ $broken -gt 0 ]]; then
    warn "${broken} symlink(s) quebrado(s) detectado(s) — skills/commands que apontam para destinos inexistentes."
    info "Isso é normal se a instalação original tem symlinks quebrados (inofensivo: o Claude Code ignora skills quebradas silenciosamente)."
  fi
}

# ── Criação do launcher ─────────────────────────────────────────────────────
create_launcher() {
  local cfg="$1" bin="$2"

  header 'Criando launcher deepclaude'

  mkdir -p "$bin"

  local launcher; launcher="$(launcher_path)"

  # Um launcher só para todos os SOs — as duas versões anteriores eram idênticas
  # exceto por um comentário, e duas cópias da lista de pins é justamente como
  # nasce um pin faltando.
  cat > "$launcher" << 'DEEPCLAUDE_EOF'
#!/usr/bin/env bash
# deepclaude — Claude Code oficial com o cérebro do DeepSeek.
# Gerado por install-deepclaude.sh — rode o instalador de novo para atualizar.
#
# ── Política de modelo ──────────────────────────────────────────────────────
# Padrão: deepseek-v4-flash[1m]  ·  slot `fable`: deepseek-v4-pro[1m]
#
# Parece invertido e não é: nesta API o NOME não versiona, o ALIAS rola. O
# `deepseek-v4-flash` serve hoje o build 0731 (31/07/2026, re-pós-treino para
# uso de ferramenta) e o `deepseek-v4-pro` serve o 0813 (GA de 12/08/2026).
# Para trabalho de agente de terminal o flash é a escolha melhor E mais barata:
#   Terminal Bench 2.1 . 82,7 (flash) — e os sub-índices independentes da
#   OpenRouter dão agentic 48,4 (flash) x 37,8 (pro), coding 69,1 x 59,4.
#   Preço . flash US$ 0,14/0,28 por M   x   pro US$ 0,435/0,87 por M.
# O pro fica a um comando: `/model fable` DENTRO da sessão (volta com
# `/model sonnet`), ou `deepclaude --pro` para a sessão inteira.
#
# 🔴 Nomes que NÃO existem nesta API (dão HTTP 400): `deepseek-v4-flash-0731`,
# `deepseek-v4-pro-0813`, `deepseek/deepseek-*`. Os dois últimos são strings do
# OpenRouter — lá o alias simples entrega a versão de ABRIL. Só valem
# `deepseek-v4-flash` e `deepseek-v4-pro`, com `[1m]` opcional.
set -euo pipefail

CONFIG_DIR="${DEEPCLAUDE_DIR:-$HOME/.claude-deepseek}"
MODEL="${DEEPCLAUDE_MODEL:-deepseek-v4-flash[1m]}"
FABLE="${DEEPCLAUDE_FABLE_MODEL:-deepseek-v4-pro[1m]}"
BASE_URL="${DEEPCLAUDE_BASE_URL:-https://api.deepseek.com/anthropic}"
# O CLI não reconhece `deepseek-*` como modelo Claude e assumiria 200k de
# janela, disparando auto-compact a 1/5 do que o modelo aguenta. A doc oficial
# (code.claude.com/docs/en/context-window) manda declarar a janela real aqui.
CTX="${DEEPCLAUDE_MAX_CONTEXT_TOKENS:-1048576}"

# --pro: sobe a sessão inteira no V4 Pro. Consumido antes do --help para não
# vazar como argumento do `claude`.
if [ "${1:-}" = "--pro" ]; then
  shift
  MODEL="deepseek-v4-pro[1m]"
  echo "deepclaude: sessão no deepseek-v4-pro" >&2
fi
HAIKU="${DEEPCLAUDE_HAIKU_MODEL:-$MODEL}"

case "${1:-}" in
  -h|--help)
    cat <<EOF
deepclaude — Claude Code com o cérebro do DeepSeek

  deepclaude [args do claude]
  deepclaude --pro [args]        sessão inteira no V4 Pro

Dentro da sessão:
  /model fable                   troca para o V4 Pro
  /model sonnet                  volta para o V4 Flash

Ambiente (todos opcionais):
  DEEPCLAUDE_DIR                 dir de config  (default: ~/.claude-deepseek)
  DEEPCLAUDE_API_KEY             chave DeepSeek (default: <dir>/deepseek.key)
  DEEPCLAUDE_MODEL               modelo principal
  DEEPCLAUDE_FABLE_MODEL         modelo do slot fable
  DEEPCLAUDE_BASE_URL            endpoint

Saldo:  curl -s https://api.deepseek.com/user/balance \\
          -H "Authorization: Bearer \$(head -n1 \$DEEPCLAUDE_DIR/deepseek.key)"
EOF
    exit 0 ;;
esac

# Chave: env explícita vence o arquivo. DEEPSEEK_CLAUDE_API_KEY é mantida por
# compatibilidade com instalações anteriores a 2026-08-13.
DSKEY="${DEEPCLAUDE_API_KEY:-${DEEPSEEK_CLAUDE_API_KEY:-}}"
if [ -z "$DSKEY" ] && [ -r "$CONFIG_DIR/deepseek.key" ]; then
  DSKEY="$(head -n1 "$CONFIG_DIR/deepseek.key")"
fi

if [ -z "$DSKEY" ]; then
  echo "deepclaude: sem chave da API DeepSeek." >&2
  echo "Grave a chave em ${CONFIG_DIR}/deepseek.key (chmod 600)" >&2
  echo "ou exporte DEEPCLAUDE_API_KEY" >&2
  exit 1
fi

# `env -u ANTHROPIC_API_KEY`: REMOVE a variável em vez de esvaziá-la. O
# ANTHROPIC_AUTH_TOKEN já vence a API_KEY na precedência oficial, mas se o
# usuário tiver uma ANTHROPIC_API_KEY exportada no shell, removê-la elimina a
# ambiguidade de "chave vazia" de vez.
# A env é prefixada ao comando: existe só neste processo, nada vaza pro shell.
exec env -u ANTHROPIC_API_KEY \
  CLAUDE_CONFIG_DIR="$CONFIG_DIR" \
  ANTHROPIC_BASE_URL="$BASE_URL" \
  ANTHROPIC_AUTH_TOKEN="$DSKEY" \
  ANTHROPIC_MODEL="$MODEL" \
  ANTHROPIC_DEFAULT_OPUS_MODEL="$MODEL" \
  ANTHROPIC_DEFAULT_SONNET_MODEL="$MODEL" \
  ANTHROPIC_DEFAULT_HAIKU_MODEL="$HAIKU" \
  ANTHROPIC_DEFAULT_FABLE_MODEL="$FABLE" \
  CLAUDE_CODE_SUBAGENT_MODEL="$MODEL" \
  CLAUDE_CODE_MAX_CONTEXT_TOKENS="$CTX" \
  claude --dangerously-skip-permissions --effort max "$@"
DEEPCLAUDE_EOF

  chmod +x "$launcher"
  ok "Launcher criado: $launcher"
}

# ── Verificação de PATH ─────────────────────────────────────────────────────
check_path() {
  local bin="$1"

  header 'Verificando PATH'

  if [[ ":$PATH:" == *":$bin:"* ]]; then
    ok "$bin está no PATH"
    return 0
  fi

  warn "$bin NÃO está no PATH!"
  info "Adicione ao seu shell rc para usar o comando 'deepclaude':"

  case "$OS" in
    macos|linux)
      info ""
      printf "${CYAN}  echo 'export PATH=\"%s:\$PATH\"' >> ~/.bashrc${NC}\n" "$bin"
      printf "${CYAN}  echo 'export PATH=\"%s:\$PATH\"' >> ~/.zshrc${NC}\n" "$bin"
      info ""
      info "Depois reinicie o terminal ou rode: export PATH=\"$bin:\$PATH\""
      ;;
    windows-gitbash)
      info ""
      printf "${CYAN}  echo 'export PATH=\"%s:\$PATH\"' >> ~/.bashrc${NC}\n" "$bin"
      info ""
      ;;
  esac
}

# ── Teste pós-instalação ────────────────────────────────────────────────────
test_installation() {
  header 'Teste de instalação'

  local launcher; launcher="$(launcher_path)"

  if [[ -x "$launcher" ]]; then
    info "Testando deepclaude --version..."
    if "$launcher" --version &>/dev/null; then
      ok "deepclaude respondeu OK"
      "$launcher" --version 2>/dev/null || true
    else
      warn "deepclaude --version falhou — mas o binário pode funcionar em modo interativo."
      warn "Tente rodar 'deepclaude' diretamente após ajustar o PATH."
    fi
  else
    warn "Launcher não encontrado em $launcher — pulando teste."
  fi
}

# ── Resumo final ────────────────────────────────────────────────────────────
print_summary() {
  local cfg="$1"

  header 'Instalação concluída!'

  say ""
  say "${BOLD}Resumo:${NC}"
  say "  Comando:      ${CYAN}deepclaude${NC}"
  say "  Config dir:   ${CYAN}${cfg}${NC}   ${BOLD}(isolado — a instalação original do Claude não foi tocada)${NC}"
  say "  Chave:        ${CYAN}${cfg}/deepseek.key${NC}"
  say "  Endpoint:     https://api.deepseek.com/anthropic"
  say "  Modelo:       ${CYAN}deepseek-v4-flash[1m]${NC}  (slot fable: ${CYAN}deepseek-v4-pro[1m]${NC})"
  say ""
  say "${BOLD}Próximos passos:${NC}"
  say "  1. Reinicie o terminal ou ajuste o PATH (veja acima)"
  say "  2. Rode: ${CYAN}deepclaude${NC}"
  say "  3. Na primeira execução responda tema e trust (não há /login — o token dispensa)"
  say ""
  say "${BOLD}Trocar de modelo:${NC}"
  say "  ${CYAN}/model fable${NC}     dentro da sessão → V4 Pro   (${CYAN}/model sonnet${NC} volta)"
  say "  ${CYAN}deepclaude --pro${NC} sessão inteira no V4 Pro"
  say ""
  say "  O padrão é o ${BOLD}flash${NC} de propósito: o alias serve o build 0731, focado em uso"
  say "  de ferramenta, e os sub-índices independentes da OpenRouter dão agentic"
  say "  48,4 (flash) × 37,8 (pro) — por 1/3 do preço. O pro brilha em codegen puro."
  say ""
  say "${BOLD}Limitações (vs Claude oficial):${NC}"
  say "  - ${YELLOW}Sem visão${NC} — imagem/PDF NÃO dão erro, voltam como placeholder (HTTP 200"
  say "    com resposta errada é pior que falha; não confie em try/catch)"
  say "  - Sem MCP remoto (server-side); MCP local/stdio funciona normalmente"
  say "  - ${RED}Sem ZDR — nunca use com código sensível/corporativo${NC}"
  say "  - Alucina mais que o Claude (~94% de propensão no AA-Omniscience), inclusive"
  say "    sobre a própria identidade: não pergunte a ele qual modelo ele é"
  say ""
  say "${BOLD}Custo:${NC}"
  say "  flash US\$ 0,14 entrada / US\$ 0,28 saída por M  ·  pro US\$ 0,435 / 0,87"
  say "  ${YELLOW}⚠ A DeepSeek passa a cobrar por horário em 2026-08-16 16:00 UTC${NC}"
  say "    (peak 01:00-04:00 e 06:00-10:00 UTC; cache hit fica 6-12× mais caro)"
  say "  O ${BOLD}total_cost_usd${NC} que o Claude Code reporta é inútil aqui — ele usa a tabela"
  say "  de preço da Anthropic e chega a errar ~12×. Custo real é o saldo:"
  say "    ${CYAN}curl -s https://api.deepseek.com/user/balance -H \"Authorization: Bearer \\\$(head -n1 ${cfg}/deepseek.key)\"${NC}"
  say ""
  say "${BOLD}Desinstalar:${NC}  rm -rf ${cfg} $(launcher_path)"
  say ""
}

# ══════════════════════════════════════════════════════════════════════════════
# main
# ══════════════════════════════════════════════════════════════════════════════
main() {
  local ARG_KEY='' ARG_NO_KEY=false

  # Parse args
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --key=*)   ARG_KEY="${1#*=}"; shift ;;
      --key)     ARG_KEY="$2"; shift 2 ;;
      --no-key)  ARG_NO_KEY=true; shift ;;
      -h|--help)
        printf 'Uso: %s [--key=sk-...] [--no-key]\n' "$0"
        printf '\n'
        printf '  --key=sk-...   Fornece a chave da API DeepSeek\n'
        printf '  --no-key       Pula a validação da chave (configure depois)\n'
        printf '  -h, --help     Mostra esta ajuda\n'
        printf '\n'
        printf 'A chave também pode ser fornecida via env var:\n'
        printf '  DEEPSEEK_CLAUDE_API_KEY=sk-... %s\n' "$0"
        exit 0
        ;;
      *)
        err "Argumento desconhecido: $1"
        printf 'Use --help para ver as opções.\n'
        exit 1
        ;;
    esac
  done

  say ""
  say "${BOLD}${CYAN}╔══════════════════════════════════════════════════════╗"
  say "║  install-deepclaude.sh                               ║"
  say "║  Claude Code + DeepSeek — instalação isolada         ║"
  say "╚══════════════════════════════════════════════════════╝${NC}"

  # 1. Detect OS
  OS="$(detect_os)"
  ok "Sistema detectado: ${OS}"

  # 2. Prerequisites
  check_prereqs

  # 3. Ensure Claude Code binary exists
  CLAUDE_BIN="$(find_or_install_claude)"
  # claude binary path stored in CLAUDE_BIN but we use PATH resolution at runtime

  # 4. Config dir
  CFG="$(config_dir)"

  # 5. DeepSeek API key
  if [[ "$ARG_NO_KEY" == true ]]; then
    warn "Modo --no-key: pulando configuração da chave."
    info "Você precisará configurar a chave manualmente para usar o deepclaude."
  else
    DSKEY="$(sanitize_key "$(resolve_deepseek_key "$CFG")")"
    if [[ -z "$DSKEY" ]]; then
      err "Chave vazia após sanitização. Abortando."
      exit 1
    fi
    if validate_deepseek_key "$DSKEY"; then
      save_deepseek_key "$CFG" "$DSKEY"
    else
      if [[ -t 0 ]]; then
        warn "Validação falhou. Deseja salvar a chave mesmo assim?"
        printf "${BOLD}[s/N]:${NC} "
        IFS= read -r yn
        case "$yn" in
          [Ss]|[Ss][Ii][Mm]) save_deepseek_key "$CFG" "$DSKEY" ;;
          *) err "Abortando. Corrija a chave e rode novamente."; exit 1 ;;
        esac
      else
        err "Validação da chave falhou e não há terminal para confirmar. Abortando."
        exit 1
      fi
    fi
  fi

  # 6. Config dir + subdirs
  setup_config_dir "$CFG"

  # 7. Mirror skills/commands from main installation
  MAIN_CFG="$(main_claude_config)"
  mirror_skills_and_commands "$MAIN_CFG" "$CFG"

  # 8. Create launcher
  BIN="$(bin_dir)"
  create_launcher "$CFG" "$BIN"

  # 9. PATH check
  check_path "$BIN"

  # 10. Test
  test_installation

  # 11. Summary
  print_summary "$CFG"
}

main "$@"
