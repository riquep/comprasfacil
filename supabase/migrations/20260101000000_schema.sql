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
