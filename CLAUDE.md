# CLAUDE.md — Compras Fácil

Contexto de projeto para o Claude Code. Leia isso antes de começar a implementar.

## O que é este projeto

App pessoal (uso individual, protegido por login) que importa notas fiscais de compras, categoriza os itens (com apoio de IA) e mostra gastos por categoria e por produto, com preço mínimo/médio/máximo por produto ao longo do tempo.

**A especificação completa está em `docs/spec-compras-facil.md`.** Ela cobre: modelo de dados (SQL + RLS), autenticação, arquitetura de pastas, funcionalidades de cada tela, API routes e variáveis de ambiente. Este arquivo não repete o que já está lá — só traz contexto operacional e lógica pronta que vale reaproveitar.

## Stack

Next.js (App Router) + Supabase (Postgres + Auth) + deploy na Vercel. API da Anthropic chamada só em API routes do servidor (nunca no client).

## Origem: veio de um protótipo validado

Este projeto é a reimplementação "de verdade" de um protótipo em HTML único (React/JS puro, sem framework) que já rodou com dados reais e validou: o formato de entrada do JSON do coletor de notas, a lógica de parsing, o fluxo de categorização por IA, e o visual do dashboard. Reaproveite o que segue em vez de redescobrir do zero.

### Parsing (JS puro — porte para TypeScript, mesma lógica)

O JSON do coletor traz cada nota com `detalhe.itens[]`. Valores monetários vêm em formato brasileiro (`"1.234,56"`), quantidade em formato decimal padrão (`"1.0000"`), e data como `"07/01/2026 10:53:40"`. Itens repetidos (mesmo `codigo`) dentro da **mesma nota** devem ser somados (quantidade e valor total), mantendo o valor unitário.

```js
function parseBRL(str){
  if(str === null || str === undefined) return 0;
  const s = String(str).trim().replace(/\./g,'').replace(',', '.');
  const n = parseFloat(s);
  return isNaN(n) ? 0 : n;
}
function parseQtd(str){
  const n = parseFloat(str);
  return isNaN(n) ? 0 : n;
}
function parseEmissao(str){
  if(!str) return null;
  const [datePart, timePart] = str.split(' ');
  if(!datePart) return null;
  const [dd,mm,yyyy] = datePart.split('/').map(Number);
  let hh=0,mi=0,ss=0;
  if(timePart){ [hh,mi,ss] = timePart.split(':').map(Number); }
  return new Date(yyyy, (mm||1)-1, dd||1, hh||0, mi||0, ss||0);
}

// Agrupa itens repetidos (mesmo código) dentro da mesma nota antes de persistir
function processRawNota(raw){
  const det = raw.detalhe;
  if(!det) return null;
  const grouped = {};
  for(const it of (det.itens || [])){
    const key = it.codigo || it.descricao;
    if(!grouped[key]){
      grouped[key] = {
        descricao: (it.descricao || '').trim(),
        codigo: it.codigo,
        quantidade: 0,
        valorUnitario: parseBRL(it.valorUnitario),
        valorTotal: 0,
      };
    }
    grouped[key].quantidade += parseQtd(it.quantidade);
    grouped[key].valorTotal += parseBRL(it.valorTotal);
  }
  return {
    chaveAcesso: det.chaveAcesso,
    numero: det.numero,
    emissao: parseEmissao(det.emissao),
    emitente: {
      razaoSocial: det.emitente?.razaoSocial || 'Desconhecido',
      cnpj: det.emitente?.cnpj || '',
    },
    valorPago: parseBRL(det.valorPago),
    itens: Object.values(grouped),
  };
}
```

Ao persistir: `notas` faz upsert por `chave_acesso` (ignora se já existe); `itens` só é inserido para notas novas.

### Prompt de categorização por IA (já testado, reaproveitar tal como está)

Chamado em `POST /api/categorizar`, com `model: claude-sonnet-4-6`. Recebe a lista de descrições pendentes como conteúdo da mensagem do usuário (`JSON.stringify(descricoes)`), e no system prompt injeta os produtos genéricos e categorias já cadastrados do usuário, para a IA reaproveitar o que já existe em vez de criar duplicatas.

```js
const systemPrompt = `Você categoriza itens de notas fiscais de supermercado brasileiro.
Para cada descrição de item (como aparece literalmente na nota fiscal, geralmente abreviada), retorne:
- "produtoGenerico": um nome de produto genérico, canônico, em português, sem marca (ex: "LAVA ROUPAS ARIEL CONC 50LAV 2L" -> "Sabão líquido"; "TOALHA UMED PERSONAL SOFT" -> "Toalha umedecida"). Reutilize um produtoGenerico já existente da lista fornecida sempre que o item for o mesmo tipo de produto, mesmo que marca ou tamanho sejam diferentes.
- "categoria": uma categoria ampla. Reutilize uma categoria da lista fornecida quando fizer sentido; só crie uma nova se nenhuma existente se aplicar.

Produtos genéricos já em uso: ${JSON.stringify(produtosConhecidos)}
Categorias já em uso: ${JSON.stringify(catList)}

Responda APENAS com um array JSON, sem markdown, sem texto adicional, no formato:
[{"descricao":"...","produtoGenerico":"...","categoria":"..."}]
A ordem e o número de itens no array de saída deve corresponder exatamente à lista de entrada.`;
```

Ao processar a resposta: tirar eventuais cercas de markdown (` ```json ... ``` `) antes de fazer `JSON.parse`. Chamar em lotes de ~40 descrições por vez quando a fila de pendências for grande.

## Identidade visual a manter

Tema "ledger/recibo" já validado — manter ao construir os componentes:

- **Paleta**: fundo escuro verde-ink (`#17211C`), superfícies (`#1F2B24` / `#28362D`), âmbar como cor de destaque (`#E0A458`), rust para valores máximos/alerta (`#C1543F`), texto em off-white quente (`#EDE6D6`).
- **Tipografia**: títulos em slab serif (Zilla Slab), corpo em Inter, valores monetários e de quantidade em monoespaçada (IBM Plex Mono) — reforça a metáfora de "recibo impresso".
- **Lista de produtos como cartões, não tabela** — em mobile, tabela com muitas colunas quebra. Cada cartão mostra nome + categoria, uma barrinha de faixa mín–média–máx (ponto âmbar marcando a média), e total gasto em destaque.
- **Modais navegáveis**: abrir o detalhe de um produto lista as ocorrências (nota, data, quantidade, valores); clicar numa ocorrência abre o modal da nota, com botão "← voltar" pro modal do produto.

## Convenções

- Interface inteiramente em português (pt-BR), incluindo mensagens de erro e rótulos.
- Datas exibidas no formato `dd/mm/aaaa`; valores monetários formatados via `toLocaleString('pt-BR', { style: 'currency', currency: 'BRL' })`.
- Evitar usar a `service role key` do Supabase — as queries devem rodar autenticadas pela sessão do usuário, respeitando RLS. Só introduzir a service role key se surgir uma necessidade real e explícita.
