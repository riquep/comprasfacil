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
