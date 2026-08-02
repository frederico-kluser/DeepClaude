# DeepClaude

Claude Code oficial com backend **DeepSeek V4 Pro** — instalação cross-platform em um comando.

```bash
./install-deepclaude.sh
```

Depois: `deepclaude` no terminal.

## O que é

O binário **oficial** do [Claude Code](https://code.claude.com) (zero patch), apontado para o endpoint Anthropic-compatível do DeepSeek (`https://api.deepseek.com/anthropic`), que traduz o Messages API e serve o `deepseek-v4-pro` no lugar de qualquer `claude-*`.

**Isolamento por env vars, não por binário** — o `claude` original continua funcionando normalmente. A conta DeepClaude usa `CLAUDE_CONFIG_DIR=~/.claude-deepseek/` com chave e histórico próprios.

## Instalação

### Linux / macOS / Windows (Git Bash / WSL)

```bash
chmod +x install-deepclaude.sh
./install-deepclaude.sh
```

Flags:
- `--key=sk-...` — fornece a chave DeepSeek (senão pergunta)
- `--no-key` — pula validação (configure depois)

### Windows (PowerShell)

```powershell
.\install-deepclaude.ps1
```

Se a política de execução bloquear:

```powershell
powershell -ExecutionPolicy Bypass -File install-deepclaude.ps1
```

## O que o instalador faz

1. Detecta o SO (Linux / macOS / Windows)
2. Encontra ou instala o binário `claude` (oficial → fallback npm)
3. Localiza/valida a chave da API DeepSeek (`curl` no `/user/balance`)
4. Cria dir de config isolado `~/.claude-deepseek/`
5. Espelha skills/commands globais da instalação original (se existir)
6. Gera o launcher `deepclaude` em `~/.local/bin/`
7. Verifica PATH

## Uso

```bash
deepclaude                       # sessão interativa
deepclaude -p "Explique este código"  # one-shot
deepclaude --version             # versão
```

## Chave da API

Obtenha em: https://platform.deepseek.com/api_keys

A chave pode ser fornecida de 3 formas (ordem de prioridade):
1. Env var: `DEEPSEEK_CLAUDE_API_KEY=sk-... deepclaude`
2. Flag: `./install-deepclaude.sh --key=sk-...`
3. Arquivo: `~/.claude-deepseek/deepseek.key` (criado pelo instalador)

## Limitações (DeepSeek V4 Pro vs Claude oficial)

| Funcionalidade | Status |
|---|---|
| Edição de código | ✓ |
| Tool calls (bash, edit, write) | ✓ |
| Thinking/extended reasoning | ✓ |
| Subagentes (haiku → flash em vez de haiku) | ⚠️ |
| Cache de contexto (automático da DeepSeek) | ✓ |
| MCP local/stdio | ✓ |
| MCP remoto (server-side) | ✗ |
| Visão (imagens/PDFs) | ✗ degradação silenciosa |
| Zero Data Retention (ZDR) | ✗ |

**Custo:** ~34× mais barato que Claude Opus (pré-pago: entrada US$ 0,435/M, saída US$ 0,87/M).

**Segurança:** sem ZDR — nunca use com código sensível/corporativo.

## Arquitetura

```
deepclaude (wrapper bash/.cmd)
  └─ env vars prefixadas:
       CLAUDE_CONFIG_DIR=~/.claude-deepseek/    # config isolada
       ANTHROPIC_BASE_URL=api.deepseek.com/anthropic  # endpoint DeepSeek
       ANTHROPIC_AUTH_TOKEN=<chave>             # autenticação
       ANTHROPIC_MODEL=deepseek-v4-pro           # modelo pinado
       ANTHROPIC_DEFAULT_*_MODEL=deepseek-v4-pro # subagentes também V4 Pro
  └─ claude --dangerously-skip-permissions --effort max
```

O binário `claude` é compartilhado com a instalação original — o isolamento é 100% por variáveis de ambiente.

## Desinstalar

```bash
rm -rf ~/.claude-deepseek ~/.local/bin/deepclaude
```

A instalação original do Claude Code não é afetada.
