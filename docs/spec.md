# Registro de Compras — Especificação Técnica e Funcional

## 1. Visão geral

App pessoal (uso único, protegido por login) para organizar notas fiscais de compras (mercado, farmácia etc.), categorizar os itens com apoio de IA, e visualizar quanto se gasta por categoria e por produto — incluindo mínimo, médio e máximo de preço pago em cada produto ao longo do tempo.

Evolução de um protótipo funcional (HTML único, dados salvos localmente) para um app real: **Next.js + Supabase (Postgres + Auth) + deploy na Vercel**.

### 1.1 Por que essa stack
- **Postgres (via Supabase)**: os dados são naturalmente relacionais (nota → itens → produto genérico) e as consultas centrais são agregações (`GROUP BY`, `MIN`, `AVG`, `MAX`, `SUM`) — SQL resolve isso nativamente, sem precisar recalcular tudo em JavaScript a cada carregamento.
- **Supabase Auth**: login simples (e-mail + senha) para proteger o app, sem precisar implementar autenticação do zero.
- **Vercel**: hospedagem do Next.js, com variáveis de ambiente para as chaves sensíveis (Supabase service role, Anthropic API key).

### 1.2 Fora de escopo (v1)
- Múltiplos usuários / compartilhamento entre contas (o modelo de dados já prevê `user_id`, mas a v1 é uso individual).
- Edição/reprocessamento retroativo de notas já importadas (uma nota importada é imutável; só os itens dela podem ganhar/alterar mapeamento).
- Notificações, alertas de variação de preço, ou comparação automática entre mercados (podem virar v2).

---

## 2. Modelo de dados (Postgres / Supabase)

```sql
-- Extensão necessária para uuid
create extension if not exists "pgcrypto";

-- Notas fiscais importadas (imutáveis após criação)
create table notas (
  chave_acesso text primary key,
  user_id uuid not null references auth.users(id) default auth.uid(),
  numero text,
  serie text,
  emissao timestamptz,
  cnpj_emitente text,
  razao_social_emitente text,
  valor_pago numeric(12,2) not null default 0,
  criado_em timestamptz not null default now()
);

-- Itens de cada nota (já deduplicados por código dentro da mesma nota na importação)
create table itens (
  id bigint generated always as identity primary key,
  nota_chave_acesso text not null references notas(chave_acesso) on delete cascade,
  descricao text not null,
  codigo text,
  quantidade numeric(12,4) not null default 0,
  valor_unitario numeric(12,4) not null default 0,
  valor_total numeric(12,2) not null default 0
);
create index idx_itens_nota on itens(nota_chave_acesso);
create index idx_itens_descricao on itens(descricao);

-- Produto genérico: o "rótulo canônico" (ex: "Sabão em pó"), dono da categoria
create table produtos_genericos (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users(id) default auth.uid(),
  nome text not null,
  categoria text not null,
  criado_em timestamptz not null default now(),
  unique (user_id, nome)
);

-- Mapeamento: cada descrição literal de nota aponta para um produto genérico.
-- Mudar a categoria de um produto genérico reflete em todas as descrições mapeadas a ele.
create table descricoes_mapeadas (
  descricao text primary key,
  user_id uuid not null references auth.users(id) default auth.uid(),
  produto_generico_id uuid not null references produtos_genericos(id) on delete cascade,
  criado_em timestamptz not null default now()
);
create index idx_mapa_produto on descricoes_mapeadas(produto_generico_id);
```

### 2.1 Row Level Security

```sql
alter table notas enable row level security;
alter table itens enable row level security;
alter table produtos_genericos enable row level security;
alter table descricoes_mapeadas enable row level security;

create policy "notas: só o dono" on notas
  for all using (auth.uid() = user_id) with check (auth.uid() = user_id);

create policy "produtos_genericos: só o dono" on produtos_genericos
  for all using (auth.uid() = user_id) with check (auth.uid() = user_id);

create policy "descricoes_mapeadas: só o dono" on descricoes_mapeadas
  for all using (auth.uid() = user_id) with check (auth.uid() = user_id);

-- itens não tem user_id direto: a policy passa pela nota
create policy "itens: só o dono via nota" on itens
  for all using (
    exists (select 1 from notas n where n.chave_acesso = itens.nota_chave_acesso and n.user_id = auth.uid())
  );
```

### 2.2 Views de agregação

```sql
-- Gasto por categoria (só itens já categorizados)
create view v_gasto_por_categoria as
select
  pg.user_id,
  pg.categoria,
  sum(i.valor_total) as total,
  count(*) as qtd_itens
from itens i
join descricoes_mapeadas dm on dm.descricao = i.descricao
join produtos_genericos pg on pg.id = dm.produto_generico_id
group by pg.user_id, pg.categoria;

-- Estatísticas por produto genérico
create view v_estatisticas_produto as
select
  pg.id as produto_generico_id,
  pg.user_id,
  pg.nome as produto,
  pg.categoria,
  count(*) as qtd_compras,
  min(i.valor_unitario) as preco_min,
  avg(i.valor_unitario) as preco_medio,
  max(i.valor_unitario) as preco_max,
  sum(i.valor_total) as total_gasto
from itens i
join descricoes_mapeadas dm on dm.descricao = i.descricao
join produtos_genericos pg on pg.id = dm.produto_generico_id
group by pg.id, pg.user_id, pg.nome, pg.categoria;
```

> Views herdam RLS das tabelas base — como `itens` já filtra por dono via join, e `produtos_genericos`/`descricoes_mapeadas` também são protegidas, as views ficam seguras automaticamente ao consultar como o usuário logado (usando a `anon key` + sessão do usuário, não a service role key).

---

## 3. Autenticação

- Supabase Auth, e-mail + senha. Um único usuário cadastrado manualmente (você) — não expor tela de cadastro público.
- Next.js middleware protege todas as rotas exceto `/login`: sem sessão válida, redireciona para `/login`.
- Cliente Supabase:
  - **Browser**: `@supabase/ssr` com a `anon key` (respeita RLS, autenticado pela sessão do usuário).
  - **Server (API routes de importação/categorização)**: também usar o cliente autenticado por sessão sempre que possível, para manter RLS ativo. A `service role key` (que ignora RLS) só deve ser usada se for estritamente necessário rodar algo fora do contexto de um usuário logado — não é o caso aqui, então evite guardá-la no projeto se não for usar.

---

## 4. Arquitetura de pastas (Next.js App Router)

```
/app
  /login/page.tsx
  /(protegido)/
    layout.tsx                 # checa sessão, aplica navegação/abas
    dashboard/page.tsx
    notas/page.tsx
    notas/[chave]/page.tsx      # ou modal client-side reaproveitando a lista
    pendencias/page.tsx
    importar/page.tsx
  /api/
    importar/route.ts           # POST: recebe JSON do coletor, faz upsert
    categorizar/route.ts         # POST: chama Anthropic API, retorna sugestões
    mapeamento/route.ts          # POST: confirma produto genérico + categoria
/lib
  supabase/client.ts             # cliente browser
  supabase/server.ts             # cliente server (route handlers)
  parse.ts                       # parsing de valores BRL, datas, agrupamento de itens por nota
  types.ts
/middleware.ts                   # proteção de rotas
```

---

## 5. Funcionalidades por tela

### 5.1 Login (`/login`)
- Formulário simples e-mail + senha (Supabase Auth `signInWithPassword`).
- Sem opção de cadastro visível.

### 5.2 Importar (`/importar`)
- Upload de arquivo `.json` (mesmo formato gerado pelo `coletor-notas-fiscais`).
- Parsing no client (ou enviado cru pro backend, ver §6.1) → `POST /api/importar`.
- Backend faz upsert em `notas` (ignora `chave_acesso` já existente) e insere `itens` das notas novas, já com itens de mesmo código somados dentro da nota.
- Mostrar resultado: X notas novas, Y ignoradas (já existiam).
- Aceitar também o export de backup do protótipo antigo (`{ notas_raw, mapeamento_produtos }`) como caminho de migração única (ver §8).

### 5.3 Pendências (`/pendencias`)
- Lista descrições de itens (`itens.descricao`) que não têm entrada em `descricoes_mapeadas`, agrupadas (uma linha por descrição única, com contagem de ocorrências).
- Botão **"Categorizar tudo com IA"**: envia lote de descrições pendentes para `POST /api/categorizar`, que chama a API da Anthropic no servidor (usando `ANTHROPIC_API_KEY`, nunca exposta no browser) e retorna sugestões `{ descricao, produtoGenerico, categoria }`. A IA recebe como contexto os produtos genéricos e categorias já existentes (`select nome, categoria from produtos_genericos`), para reaproveitar padrões já estabelecidos.
- Cada item pendente mostra a sugestão pré-preenchida, editável, com autocomplete puxando de `produtos_genericos` existentes.
- Botão **"Aceitar todas as sugestões"**: para cada item com sugestão, `POST /api/mapeamento` — cria o `produtos_genericos` se o nome ainda não existir (case-insensitive), senão reaproveita o existente, e insere a linha em `descricoes_mapeadas`.
- Confirmação individual por item continua disponível.

### 5.4 Dashboard (`/dashboard`)
- Card hero: total gasto (soma de `v_gasto_por_categoria.total`), nº de notas, itens categorizados vs. pendentes.
- Gasto por categoria: `select * from v_gasto_por_categoria order by total desc`. Clicável, filtra a lista de produtos abaixo.
- Lista de produtos (cartões, não tabela — ver §5.6): `select * from v_estatisticas_produto`, com busca por nome e ordenação (total gasto, nome, nº de compras, preço médio, preço máximo).
- Clicar num produto abre modal com as ocorrências (`itens` join `notas`, filtrando pelo `produto_generico_id`), cada uma clicável para abrir o modal da nota correspondente.

### 5.5 Notas (`/notas`)
- Lista todas as notas (`select * from notas order by emissao desc`): estabelecimento, data, nº de itens, valor pago.
- Clicar abre modal com o detalhe completo da nota (itens, valores, categoria/genérico de cada um, "pendente" se ainda não categorizado).

### 5.6 Padrão de UI a manter do protótipo
- Tema visual "ledger/recibo": paleta escuro-esverdeada + âmbar + tipografia slab serif (títulos) / monoespaçada (valores).
- Lista de produtos como cartões (não tabela), com a barra de faixa mín–média–máx — comprovadamente funciona bem em mobile.
- Modais de produto e nota com navegação entre si (abrir nota a partir de uma ocorrência de produto, com botão "voltar").

---

## 6. Fluxos e API routes

### 6.1 `POST /api/importar`
- Recebe o JSON bruto do coletor (array de notas com `detalhe.itens` etc.) **ou** o formato de backup do protótipo.
- Faz o parsing (reaproveitar a lógica já validada no protótipo: `parseBRL`, `parseQtd`, `parseEmissao`, agrupamento de itens por `codigo` dentro da mesma nota).
- Upsert em `notas` (on conflict `chave_acesso` do nothing) e insert em `itens` só para notas novas.
- Retorna `{ notasAdicionadas, notasIgnoradas }`.

### 6.2 `POST /api/categorizar`
- Recebe `{ descricoes: string[] }`.
- Busca produtos genéricos e categorias já existentes do usuário (via Supabase, respeitando RLS pela sessão).
- Chama a API da Anthropic (`model: claude-sonnet-4-6`) com o mesmo prompt de categorização do protótipo, usando `ANTHROPIC_API_KEY` do ambiente do servidor.
- Retorna `{ descricao, produtoGenerico, categoria }[]`.

### 6.3 `POST /api/mapeamento`
- Recebe `{ descricao, produtoGenerico, categoria }` (ou lote).
- `select id from produtos_genericos where user_id = ... and lower(nome) = lower(produtoGenerico)`. Se não existir, insere (com a `categoria` informada). Se existir, reaproveita o `id` (a `categoria` do produto genérico existente prevalece — evita duas categorias diferentes para o mesmo produto).
- Insere em `descricoes_mapeadas`.

---

## 7. Variáveis de ambiente

```
NEXT_PUBLIC_SUPABASE_URL=
NEXT_PUBLIC_SUPABASE_ANON_KEY=
ANTHROPIC_API_KEY=            # usada só nas API routes, nunca no client
```

Configuradas no `.env.local` (dev) e nas variáveis de ambiente do projeto na Vercel (prod). A `service role key` do Supabase só deve ser adicionada se, na implementação, surgir uma necessidade real de bypassar RLS — não é esperada na v1.

---

## 8. Migração dos dados do protótipo

Você já tem um export do artifact atual (`{ notas_raw, mapeamento_produtos }`). Passo único de migração:
1. Em `/importar`, subir esse arquivo de backup.
2. O backend reconhece o formato (`notas_raw` array + `mapeamento_produtos` objeto), e para cada entrada:
   - Insere a nota (já vem processada, sem precisar reagrupar itens).
   - Para cada `descricao → { produtoGenerico, categoria }` em `mapeamento_produtos`: cria o `produtos_genericos` (se não existir) e a linha em `descricoes_mapeadas`.
3. Depois desse passo único, o protótipo em HTML pode ser descontinuado.

---

## 9. Próximos passos sugeridos (pós-v1)
- Comparação de preço do mesmo produto entre mercados diferentes (já dá pra fazer com o schema atual, via `notas.cnpj_emitente` + `v_estatisticas_produto`).
- Filtro por período (mês/ano) no dashboard.
- Edição de `produtos_genericos` (renomear, mudar categoria, mesclar dois produtos genéricos em um).
