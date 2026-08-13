# DeepClaude

Claude Code oficial com o cérebro do **DeepSeek** — instalação isolada, em um comando.

```bash
./install-deepclaude.sh
```

Depois: `deepclaude` no terminal.

## O que é

O binário **oficial** do [Claude Code](https://code.claude.com) — zero patch — apontado para o endpoint Anthropic-compatível da DeepSeek (`https://api.deepseek.com/anthropic`), que traduz o Messages API e serve os modelos `deepseek-v4-*` no lugar de qualquer `claude-*`.

**Não substitui a sua instalação do Claude Code.** Se o `claude` já existe na máquina, o instalador o deixa exatamente como está e apenas o reusa: o desvio é 100% por variável de ambiente, prefixada ao comando dentro do launcher. A conta DeepClaude vive em `CLAUDE_CONFIG_DIR=~/.claude-deepseek/`, com chave, histórico e settings próprios.

## Instalação

### Linux / macOS / Windows (Git Bash / WSL)

```bash
chmod +x install-deepclaude.sh
./install-deepclaude.sh
```

Flags:

| Flag | Efeito |
|---|---|
| `--name=<nome>` | Nome da **área** — define o dir e o comando |
| `--dir=<caminho>` | Dir da área explícito (precede `--name`) |
| `--command=<nome>` | Nome do comando gerado |
| `--key=sk-...` | Fornece a chave DeepSeek (senão pergunta) |
| `--no-key` | Pula a chave — configure depois |
| `--skills-from=<dir>` | Área de onde copiar skills (default: `~/.claude`) |
| `--no-skills` | Não copia skills/commands |
| `-h`, `--help` | Ajuda |

A chave também sai de `DEEPSEEK_CLAUDE_API_KEY` no ambiente.

## Áreas — várias instalações lado a lado

Uma **área** é um `CLAUDE_CONFIG_DIR` próprio: chave, histórico, settings e skills separados. O binário `claude` é **compartilhado** por todas — o isolamento é por variável de ambiente, nunca por reinstalar nada.

```bash
./install-deepclaude.sh                      # ~/.claude-deepseek            → deepclaude
./install-deepclaude.sh --name=trabalho      # ~/.claude-deepseek-trabalho   → deepclaude-trabalho
./install-deepclaude.sh --name=pessoal       # ~/.claude-deepseek-pessoal    → deepclaude-pessoal
```

Cada execução com um `--name` novo cria uma área **nova**, com chave e histórico próprios, e um comando próprio. Nenhuma delas interfere nas outras.

### O que o instalador se recusa a fazer

| Situação | Comportamento |
|---|---|
| Área alvo é `~/.claude` (a default do Claude Code) | **Aborta.** Essa é a área onde o `claude` sem env var guarda seu login — o instalador nunca escreve nela |
| Dir alvo já tem login de outra conta (`.credentials.json`, Kimi, `auth.json`) | **Aborta.** Misturar dois cadastros no mesmo dir é o erro que mais dói |
| O comando alvo já existe e é um **symlink** | **Aborta** e mostra o alvo. `cat >` através de symlink sobrescreve o arquivo apontado, não o link — isso já destruiria um script versionado em outro repo |
| O comando alvo existe como arquivo comum | Faz **backup** `.bak-<timestamp>` antes de gerar |

O `claude` que já estiver instalado **não é substituído nem atualizado** — é apenas reusado.

### Integração com seletores de conta

Se a máquina tiver o CLI `claude-contas` (o seletor por trás de funções como `asd`), a área nova é registrada automaticamente com tipo `dsclaude`, e passa a aparecer no menu:

```bash
asd -a deepseek-trabalho
```

Sem esse CLI, nada muda — a instalação funciona pelo comando direto.

### Skills

As skills da área de origem são espelhadas por symlink resolvendo o **alvo canônico**, não o caminho dentro da origem. Se `~/.claude/skills/foo` já é um link para `~/Projects/foo`, a área nova aponta direto para `~/Projects/foo` — sem criar uma cadeia que quebraria se a origem sumisse. A área de origem é **somente lida**.

### Windows (PowerShell)

```powershell
.\install-deepclaude.ps1
```

Se a política de execução bloquear:

```powershell
powershell -ExecutionPolicy Bypass -File install-deepclaude.ps1
```

## O que o instalador faz

1. Detecta o SO
2. **Encontra ou instala** o binário `claude` — se já existir, não toca nele
3. Pede e **valida** a chave DeepSeek (`GET /user/balance`)
4. Cria o dir isolado `~/.claude-deepseek/` e grava a chave em `600`
5. Espelha skills/commands globais da instalação original (symlink no Unix, cópia no Windows)
6. Gera o launcher `deepclaude` em `~/.local/bin/`
7. Verifica o PATH e testa

## Modelos

| Slot | Modelo | Quando |
|---|---|---|
| padrão (opus/sonnet/haiku/subagentes) | `deepseek-v4-flash[1m]` | dia a dia, tool calling, refactor linear |
| `fable` | `deepseek-v4-pro[1m]` | codegen pesado, refatoração nuclear |

```bash
deepclaude            # V4 Flash
/model fable          # dentro da sessão → V4 Pro   (/model sonnet volta)
deepclaude --pro      # sessão inteira no V4 Pro
```

**O flash ser o padrão não é economia burra.** Nesta API o nome não versiona — o *alias* rola. O `deepseek-v4-flash` serve o build **0731** (31/07/2026), um re-pós-treino focado em uso de ferramenta; o `deepseek-v4-pro` serve o **0813** (GA de 12/08/2026). Para trabalho de agente de terminal os sub-índices independentes da OpenRouter dão **agentic 48,4 (flash) × 37,8 (pro)** e **coding 69,1 × 59,4**, com o flash custando **1/3**. O pro ganha em geração de código pura (LiveCodeBench 93,5 × 91,6) — daí ele ficar a um comando, não no caminho crítico.

> ⚠️ **Nomes de modelo não são portáveis entre gateways.** Aqui só existem `deepseek-v4-flash` e `deepseek-v4-pro` (com `[1m]` opcional). `deepseek-v4-flash-0731`, `deepseek-v4-pro-0813` e qualquer `deepseek/...` dão **HTTP 400** — são strings do **OpenRouter**, onde por sua vez o alias simples entrega a versão de **abril**. Guias da comunidade misturam os dois o tempo todo.

## Variáveis de ambiente do launcher

| Variável | Default |
|---|---|
| `DEEPCLAUDE_DIR` | `~/.claude-deepseek` |
| `DEEPCLAUDE_API_KEY` | lê `<dir>/deepseek.key` |
| `DEEPCLAUDE_MODEL` | `deepseek-v4-flash[1m]` |
| `DEEPCLAUDE_FABLE_MODEL` | `deepseek-v4-pro[1m]` |
| `DEEPCLAUDE_HAIKU_MODEL` | igual ao principal |
| `DEEPCLAUDE_BASE_URL` | `https://api.deepseek.com/anthropic` |
| `DEEPCLAUDE_MAX_CONTEXT_TOKENS` | `1048576` |

## Chave da API

Obtenha em: https://platform.deepseek.com/api_keys

Ordem de resolução: `DEEPCLAUDE_API_KEY` → `DEEPSEEK_CLAUDE_API_KEY` → `~/.claude-deepseek/deepseek.key`.

Para rotacionar, basta reescrever o arquivo — o launcher relê a cada subida.

> **401 ≠ 402.** `401` é chave inválida; `402 Insufficient Balance` significa que a chave foi **aceita** e só falta saldo. O instalador distingue os dois.

## Limitações (vs Claude oficial)

| Funcionalidade | Status |
|---|---|
| Edição de código, tool calls (bash/edit/write) | ✅ |
| Thinking / extended reasoning (`--effort max`) | ✅ |
| Cache de contexto (automático, server-side) | ✅ |
| Janela de 1M tokens | ✅ |
| MCP local / stdio | ✅ |
| MCP remoto (server-side) | ❌ |
| Visão (imagens / PDFs) | ❌ **falha silenciosa** |
| Zero Data Retention | ❌ |

🔴 **A falha de visão é silenciosa e é a pegadinha mais cara aqui.** A doc da DeepSeek é explícita: *"`input_image` parts do not cause an error, but are replaced with a placeholder text"*. Ou seja, **HTTP 200 com uma resposta errada** — o modelo comenta uma imagem que nunca viu, e `try/catch` não pega. Para qualquer trabalho visual, use uma conta Claude de verdade.

**Sem ZDR:** o prompt vai para o servidor público da DeepSeek. Nunca use com código sensível ou corporativo.

**Alucinação:** a família V4 pontua ~94% de propensão no AA-Omniscience. Isso vale inclusive para a autodescrição — **nunca pergunte ao modelo qual modelo ele é**; ele responde com confiança e erra. Para verificar roteamento use metadado:

```bash
deepclaude -p "ok" --output-format json | grep -o '"modelUsage":{[^}]*}'
```

## Custo

| por 1M tokens | Flash | Pro |
|---|---|---|
| entrada (cache miss) | US$ 0,14 | US$ 0,435 |
| entrada (cache hit) | US$ 0,0028 | US$ 0,003625 |
| saída | US$ 0,28 | US$ 0,87 |

🔴 **A DeepSeek passa a cobrar por horário em 2026-08-16, 16:00 UTC** (peak = 01:00–04:00 e 06:00–10:00 UTC). O **cache hit fica 6–12× mais caro** — e é justamente o cache que segura o custo de um agente que relê o mesmo repositório o tempo todo.

⚠️ **Ignore o `total_cost_usd` que o Claude Code reporta.** Ele calcula com a tabela de preço da Anthropic, que não tem modelo DeepSeek: numa medição real superestimou **~12×** e chegou a marcar o flash mais caro que o pro. Custo verdadeiro é o saldo:

```bash
curl -s https://api.deepseek.com/user/balance \
  -H "Authorization: Bearer $(head -n1 ~/.claude-deepseek/deepseek.key)"
```

## Arquitetura

```
deepclaude (wrapper bash / .cmd)
  └─ env prefixada ao comando — existe só neste processo:
       CLAUDE_CONFIG_DIR=~/.claude-deepseek/      # config isolada
       ANTHROPIC_BASE_URL=api.deepseek.com/anthropic
       ANTHROPIC_AUTH_TOKEN=<chave>               # dispensa /login
       ANTHROPIC_MODEL / _OPUS_ / _SONNET_ / _HAIKU_ / _FABLE_
       CLAUDE_CODE_SUBAGENT_MODEL                 # os SEIS pins
       CLAUDE_CODE_MAX_CONTEXT_TOKENS=1048576
       (env -u ANTHROPIC_API_KEY)
  └─ claude --dangerously-skip-permissions --effort max
```

**Por que seis pins e não três:** um pin faltando **não dá erro**. O endpoint mapeia `claude-*` por prefixo, e só `claude-opus-*` vira o pro — `claude-sonnet-*` e `claude-haiku-*` caem no flash. Sem pinar todos, parte da sessão roda num modelo que você não escolheu, em silêncio.

**Por que `CLAUDE_CODE_MAX_CONTEXT_TOKENS`:** o CLI não reconhece `deepseek-*` como modelo Claude e assume 200k de janela, disparando auto-compact a 1/5 do que o modelo aguenta.

**Por que `env -u ANTHROPIC_API_KEY`:** remover é melhor que esvaziar. O `ANTHROPIC_AUTH_TOKEN` já vence na precedência, mas se o usuário tiver uma `ANTHROPIC_API_KEY` exportada, removê-la elimina a ambiguidade.

No Windows o launcher `.cmd` usa **`setlocal`** — sem isso as variáveis vazariam para a sessão do `cmd` e o `claude` original passaria a falar com a DeepSeek na mesma janela.

## Desinstalar

```bash
rm -rf ~/.claude-deepseek ~/.local/bin/deepclaude
```

A instalação original do Claude Code não é afetada.
