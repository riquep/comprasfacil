# Registro de Compras

App pessoal para organizar notas fiscais de compras: importa o JSON gerado pelo [coletor-notas-fiscais](../coletor-notas-fiscais), categoriza os itens (com apoio de IA), e mostra quanto se gasta por categoria e por produto — incluindo preço mínimo, médio e máximo pago em cada produto ao longo do tempo.

> Status: em desenvolvimento inicial. Evolução de um protótipo funcional (HTML único) validado antes de virar app de verdade.

## Especificação

A especificação técnica e funcional completa está em [`docs/spec-registro-compras.md`](docs/spec-registro-compras.md) — modelo de dados, autenticação, arquitetura de pastas, funcionalidades por tela e API routes. Comece por ali antes de mexer no código.

## Stack

- [Next.js](https://nextjs.org) (App Router)
- [Supabase](https://supabase.com) — Postgres + Auth
- Deploy na [Vercel](https://vercel.com)
- API da Anthropic (Claude) para sugestão automática de categorização, chamada só no servidor

## Como rodar localmente

```bash
git clone <repo>
cd registro-compras
npm install
cp .env.example .env.local   # preencher com as chaves do Supabase e da Anthropic
npm run dev
```

Variáveis necessárias em `.env.local` (ver detalhes em `docs/spec-registro-compras.md` §7):

```
NEXT_PUBLIC_SUPABASE_URL=
NEXT_PUBLIC_SUPABASE_ANON_KEY=
ANTHROPIC_API_KEY=
```

## Migração do protótipo

Se você já tem um export do protótipo (`{ notas_raw, mapeamento_produtos }`), suba esse arquivo pela tela de Importar — o app reconhece o formato de backup e migra notas + categorizações já feitas num passo só (ver §8 da spec).

## Escopo

Uso individual (login único, protegido). Fora de escopo por enquanto: múltiplos usuários, comparação automática de preço entre mercados, filtro por período no dashboard — ver "Próximos passos" na spec.
