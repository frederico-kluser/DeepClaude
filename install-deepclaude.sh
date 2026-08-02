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

info()    { printf "${BLUE}ℹ${NC} %s\n" "$*"; }
ok()      { printf "${GREEN}✓${NC} %s\n" "$*"; }
warn()    { printf "${YELLOW}⚠${NC} %s\n" "$*" >&2; }
err()     { printf "${RED}✗${NC} %s\n" "$*" >&2; }
header()  { printf "\n${BOLD}${CYAN}═══ %s ═══${NC}\n" "$*"; }

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

  # Já existe?
  if command -v claude &>/dev/null; then
    local claude_path
    claude_path="$(command -v claude)"
    local claude_version
    claude_version="$(claude --version 2>/dev/null || echo 'desconhecida')"
    ok "Claude Code encontrado: ${claude_path} (${claude_version})"
    printf '%s' "$claude_path"
    return 0
  fi

  info "Claude Code não encontrado. Instalando..."

  # Opção 1: Instalador oficial (Linux/macOS)
  if [[ "$OS" == 'linux' || "$OS" == 'macos' ]]; then
    info "Tentando instalador oficial (claude.ai/install.sh)..."
    if curl -fsSL https://claude.ai/install.sh | bash; then
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
  if npm i -g @anthropic-ai/claude-code; then
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
    printf '\n'
    info "Chave da API DeepSeek necessária."
    info "Obtenha uma em: https://platform.deepseek.com/api_keys"
    printf "${BOLD}Chave (sk-...):${NC} "
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
      local is_active currency balance
      is_active="$(printf '%s' "$body" | grep -o '"is_active"[[:space:]]*:[[:space:]]*true' || true)"
      currency="$(printf '%s' "$body" | grep -o '"currency"[[:space:]]*:[[:space:]]*"[^"]*"' | head -1 || true)"
      balance="$(printf '%s' "$body" | grep -o '"total_balance"[[:space:]]*:[[:space:]]*[0-9.]*' || true)"

      if [[ -n "$is_active" ]]; then
        ok "Chave válida ✓"
        if [[ -n "$balance" ]]; then
          local bal_num; bal_num="$(printf '%s' "$balance" | grep -o '[0-9.]*$')"
          local cur_str; cur_str="$(printf '%s' "$currency" | grep -o '"[^"]*"$' | tr -d '"')"
          info "Saldo: ${cur_str:-USD} ${bal_num:-?}"
        fi
        return 0
      fi
      warn "Resposta 200 mas campo is_active ausente — prosseguindo..."
      return 0
      ;;
    401)
      err "Chave INVÁLIDA (401 Unauthorized)."
      err "Verifique se a chave está correta e não expirou."
      err "Obtenha uma nova em: https://platform.deepseek.com/api_keys"
      return 1
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

save_deepseek_key() {
  local dir="$1" key="$2"

  mkdir -p "$dir"
  printf '%s\n' "$key" > "$dir/deepseek.key"
  chmod 600 "$dir/deepseek.key"
  ok "Chave salva em $dir/deepseek.key (chmod 600)"
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

  case "$OS" in
    windows-gitbash)
      # Windows Git Bash: script bash simples
      cat > "$launcher" << 'DEEPCLAUDE_EOF'
#!/usr/bin/env bash
# deepclaude — Claude Code com backend DeepSeek V4 Pro
# Gerado por install-deepclaude.sh — não edite manualmente.
set -euo pipefail

CONFIG_DIR="${HOME}/.claude-deepseek"
DSKEY="${DEEPSEEK_CLAUDE_API_KEY:-}"

if [ -z "$DSKEY" ] && [ -r "$CONFIG_DIR/deepseek.key" ]; then
  DSKEY="$(head -n1 "$CONFIG_DIR/deepseek.key")"
fi

if [ -z "$DSKEY" ]; then
  echo "deepclaude: sem chave da API DeepSeek." >&2
  echo "Grave a chave em ${CONFIG_DIR}/deepseek.key (chmod 600)" >&2
  echo "ou exporte DEEPSEEK_CLAUDE_API_KEY" >&2
  exit 1
fi

exec env \
  CLAUDE_CONFIG_DIR="$CONFIG_DIR" \
  ANTHROPIC_BASE_URL='https://api.deepseek.com/anthropic' \
  ANTHROPIC_AUTH_TOKEN="$DSKEY" \
  ANTHROPIC_MODEL='deepseek-v4-pro' \
  ANTHROPIC_DEFAULT_OPUS_MODEL='deepseek-v4-pro' \
  ANTHROPIC_DEFAULT_SONNET_MODEL='deepseek-v4-pro' \
  ANTHROPIC_DEFAULT_HAIKU_MODEL='deepseek-v4-pro' \
  claude --dangerously-skip-permissions --effort max "$@"
DEEPCLAUDE_EOF
      chmod +x "$launcher"
      ok "Launcher criado: $launcher"
      ;;

    *)
      # Linux/macOS: script bash com env prefixada (nada vaza pro shell)
      cat > "$launcher" << 'DEEPCLAUDE_EOF'
#!/usr/bin/env bash
# deepclaude — Claude Code com backend DeepSeek V4 Pro
# Gerado por install-deepclaude.sh — não edite manualmente.
# Para atualizar a config, rode install-deepclaude.sh novamente.
set -euo pipefail

CONFIG_DIR="${HOME}/.claude-deepseek"
DSKEY="${DEEPSEEK_CLAUDE_API_KEY:-}"

if [ -z "$DSKEY" ] && [ -r "$CONFIG_DIR/deepseek.key" ]; then
  DSKEY="$(head -n1 "$CONFIG_DIR/deepseek.key")"
fi

if [ -z "$DSKEY" ]; then
  echo "deepclaude: sem chave da API DeepSeek." >&2
  echo "Grave a chave em ${CONFIG_DIR}/deepseek.key (chmod 600)" >&2
  echo "ou exporte DEEPSEEK_CLAUDE_API_KEY" >&2
  exit 1
fi

exec env \
  CLAUDE_CONFIG_DIR="$CONFIG_DIR" \
  ANTHROPIC_BASE_URL='https://api.deepseek.com/anthropic' \
  ANTHROPIC_AUTH_TOKEN="$DSKEY" \
  ANTHROPIC_MODEL='deepseek-v4-pro' \
  ANTHROPIC_DEFAULT_OPUS_MODEL='deepseek-v4-pro' \
  ANTHROPIC_DEFAULT_SONNET_MODEL='deepseek-v4-pro' \
  ANTHROPIC_DEFAULT_HAIKU_MODEL='deepseek-v4-pro' \
  claude --dangerously-skip-permissions --effort max "$@"
DEEPCLAUDE_EOF
      chmod +x "$launcher"
      ok "Launcher criado: $launcher"
      ;;
  esac
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
  local cfg="$1" key="$2"

  header 'Instalação concluída!'

  printf '\n'
  printf "${BOLD}Resumo:${NC}\n"
  printf '  Comando:         ${CYAN}deepclaude${NC}\n'
  printf '  Config dir:      ${CYAN}%s${NC}\n' "$cfg"
  printf '  Chave:           ${CYAN}%s/deepseek.key${NC}\n' "$cfg"
  printf '  Backend:         DeepSeek V4 Pro\n'
  printf '  Endpoint:        https://api.deepseek.com/anthropic\n'
  printf '\n'
  printf "${BOLD}Próximos passos:${NC}\n"
  printf '  1. Reinicie o terminal ou ajuste o PATH (veja acima)\n'
  printf '  2. Rode: ${CYAN}deepclaude${NC}\n'
  printf '  3. Na primeira execução, responda às perguntas de tema e trust\n'
  printf '  4. Para adicionar skills globais, copie/links para %s/skills/\n' "$cfg"
  printf '\n'
  printf "${BOLD}Limitações (DeepSeek V4 Pro vs Claude oficial):${NC}\n"
  printf '  - Sem visão (imagens/PDFs são degradados silenciosamente)\n'
  printf '  - Sem MCP remoto (server-side); MCP local/stdio funciona\n'
  printf '  - Sem ZDR (Zero Data Retention) — ${RED}nunca use com código sensível${NC}\n'
  printf '  - Propenso a alucinações (~94%% no benchmark AA-Omniscience)\n'
  printf '  - Custo: ~34× mais barato que Opus (pré-pago)\n'
  printf '\n'
  printf "${BOLD}Se o Claude original parar de funcionar:${NC}\n"
  printf '  As instalações são isoladas por env vars — a original não foi alterada.\n'
  printf '  Se precisar reverter: apague %s e o launcher em %s\n' "$cfg" "$(launcher_path)"
  printf '\n'
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

  printf '\n'
  printf "${BOLD}${CYAN}"
  printf '╔══════════════════════════════════════════════════════╗\n'
  printf '║  install-deepclaude.sh                              ║\n'
  printf '║  Claude Code + DeepSeek V4 Pro — Cross-Platform     ║\n'
  printf '╚══════════════════════════════════════════════════════╝'
  printf "${NC}\n"

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
    DSKEY="$(resolve_deepseek_key "$CFG")"
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
