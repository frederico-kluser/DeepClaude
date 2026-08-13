# DeepClaude

Roda o **Claude Code oficial** com o cérebro do **DeepSeek** — por ~1/100 do custo do Opus.

Não substitui nada: se você já tem o `claude` instalado, ele é reusado como está. O DeepClaude cria uma **área separada** (config, chave e histórico próprios) e um comando novo. Sua instalação atual continua intacta.

## Instalar

```bash
git clone https://github.com/frederico-kluser/DeepClaude.git && cd DeepClaude
chmod +x install-deepclaude.sh
./install-deepclaude.sh
```

Ele pede a chave da DeepSeek ([pegue aqui](https://platform.deepseek.com/api_keys)), valida, cria a área e gera o comando. Windows nativo: `.\install-deepclaude.ps1`.

## Usar

```bash
deepclaude                    # sessão interativa
deepclaude -p "corrija o bug do parser"   # one-shot
```

Trocar de modelo:

```bash
/model fable                  # dentro da sessão → V4 Pro   (/model sonnet volta)
deepclaude --pro              # a sessão inteira no V4 Pro
```

## Várias áreas

Cada `--name` cria uma instalação independente, com chave, histórico e comando próprios:

```bash
./install-deepclaude.sh --name=trabalho    # → comando deepclaude-trabalho
./install-deepclaude.sh --name=pessoal     # → comando deepclaude-pessoal
```

| Flag | |
|---|---|
| `--name=<nome>` | nome da área (define dir e comando) |
| `--dir=<caminho>` | dir da área explícito |
| `--command=<nome>` | nome do comando gerado |
| `--key=sk-...` | chave da API (senão pergunta) |
| `--no-key` | configura a chave depois |
| `--skills-from=<dir>` | de onde copiar skills (default `~/.claude`) |
| `--no-skills` | não copiar skills |

Se a máquina tiver o CLI `claude-contas`, a área é registrada e aparece no seletor (`asd -a deepseek-<nome>`).

**O instalador aborta** se a área alvo for a default `~/.claude`, se o dir já tiver login de outra conta, ou se o comando alvo for um symlink (sobrescrever seguiria o link e destruiria o arquivo apontado).

## Modelos

| Slot | Modelo | Para |
|---|---|---|
| padrão | `deepseek-v4-flash[1m]` | dia a dia, tool calling, refactor |
| `fable` | `deepseek-v4-pro[1m]` | codegen pesado, refatoração grande |

O flash é padrão de propósito: o alias serve o build **0731**, focado em uso de ferramenta, e nos sub-índices independentes da OpenRouter faz **agentic 48,4** contra 37,8 do pro — por 1/3 do preço. O pro ganha em geração de código pura, daí ficar a um comando de distância.

> ⚠️ Nomes de modelo não são portáveis entre gateways. Aqui só existem `deepseek-v4-flash` e `deepseek-v4-pro`. `deepseek-v4-flash-0731`, `deepseek-v4-pro-0813` e `deepseek/...` dão **HTTP 400** — são strings do OpenRouter, onde por sua vez o alias simples entrega a versão de abril.

## Limitações

| | |
|---|---|
| Edição, tool calls, thinking, cache, 1M de contexto | ✅ |
| MCP local / stdio | ✅ |
| MCP remoto (server-side) | ❌ |
| Visão (imagens, PDFs) | ❌ **falha silenciosa** |
| Zero Data Retention | ❌ |

🔴 **A falha de visão é a pegadinha cara.** A doc da DeepSeek é explícita: `input_image` *"does not cause an error, but is replaced with a placeholder text"*. HTTP 200 com resposta errada — o modelo comenta uma imagem que nunca viu, e `try/catch` não pega.

**Sem ZDR:** o prompt vai para o servidor público da DeepSeek. Nunca use com código sensível.

**Alucinação:** a família V4 pontua ~94% de propensão no AA-Omniscience — inclusive sobre a própria identidade. Nunca pergunte ao modelo qual modelo ele é; verifique por metadado:

```bash
deepclaude -p "ok" --output-format json | grep -o '"modelUsage":{[^}]*}'
```

## Custo

| por 1M tokens | Flash | Pro |
|---|---|---|
| entrada | US$ 0,14 | US$ 0,435 |
| entrada em cache | US$ 0,0028 | US$ 0,003625 |
| saída | US$ 0,28 | US$ 0,87 |

🔴 **A DeepSeek passa a cobrar por horário em 2026-08-16, 16:00 UTC** (pico: 01:00–04:00 e 06:00–10:00 UTC). O **cache hit fica 6–12× mais caro** — e é o cache que segura o custo de um agente que relê o mesmo repositório.

⚠️ **Ignore o `total_cost_usd` do Claude Code.** Ele usa a tabela de preço da Anthropic, que não tem modelo DeepSeek: numa medição real superestimou **~12×**. Custo verdadeiro é o saldo:

```bash
curl -s https://api.deepseek.com/user/balance \
  -H "Authorization: Bearer $(head -n1 ~/.claude-deepseek/deepseek.key)"
```

## Como funciona

O launcher prefixa variáveis de ambiente ao `claude` — nada é patcheado, nada vaza para o shell:

```
CLAUDE_CONFIG_DIR=~/.claude-deepseek        # área isolada
ANTHROPIC_BASE_URL=api.deepseek.com/anthropic
ANTHROPIC_AUTH_TOKEN=<chave>                # dispensa /login
ANTHROPIC_MODEL + _OPUS_ + _SONNET_ + _HAIKU_ + _FABLE_ + SUBAGENT   # os 6 pins
CLAUDE_CODE_MAX_CONTEXT_TOKENS=1048576
```

**Por que seis pins:** um pin faltando não dá erro. O endpoint mapeia `claude-*` por prefixo e só `claude-opus-*` vira o pro — sonnet e haiku caem no flash, em silêncio.

**Por que declarar a janela:** o CLI não reconhece `deepseek-*` como modelo Claude, assume 200k e auto-compacta a 1/5 do que o modelo aguenta.

No Windows o `.cmd` usa `setlocal` — sem isso as variáveis vazariam para a sessão do `cmd` e o `claude` original passaria a falar com a DeepSeek na mesma janela.

## Desinstalar

```bash
rm -rf ~/.claude-deepseek ~/.local/bin/deepclaude
```

A instalação original do Claude Code não é afetada.
