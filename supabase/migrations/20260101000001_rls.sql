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
