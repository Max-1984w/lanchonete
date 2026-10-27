-- Cole este script inteiro em: Supabase > SQL Editor > New query > Run

create table itens (
  id bigint generated always as identity primary key,
  nome text not null,
  descricao text not null default '',
  preco numeric(10,2) not null check (preco >= 0),
  categoria text not null default 'Outros',
  disponivel boolean not null default true,
  criado_em timestamptz not null default now()
);

create table configuracao (
  id int primary key default 1 check (id = 1),
  nome_loja text not null default 'Minha Lanchonete',
  mensagem text not null default 'Escolha o que quiser, envie o pedido e acompanhe pelo número.',
  cor_principal text not null default '#15803d',
  cor_destaque text not null default '#dc2626'
);
insert into configuracao (id) values (1);

create table pedidos (
  numero bigint generated always as identity primary key,
  cliente text not null,
  telefone text not null,
  tipo text not null check (tipo in ('Retirada','Entrega')),
  endereco text not null default '',
  observacao text not null default '',
  itens jsonb not null,
  total numeric(10,2) not null,
  status text not null default 'novo' check (status in ('novo','preparo','pronto','entregue','cancelado')),
  criado_em timestamptz not null default now()
);

-- Segurança: ninguém lê ou altera nada sem uma regra
alter table itens enable row level security;
alter table configuracao enable row level security;
alter table pedidos enable row level security;

-- Cliente (visitante): vê só itens disponíveis e a configuração da loja
create policy "cliente ve itens disponiveis" on itens for select to anon using (disponivel);
create policy "cliente ve configuracao" on configuracao for select to anon using (true);

-- Loja (usuário logado): controla tudo
create policy "loja gerencia itens" on itens for all to authenticated using (true) with check (true);
create policy "loja gerencia configuracao" on configuracao for all to authenticated using (true) with check (true);
create policy "loja gerencia pedidos" on pedidos for all to authenticated using (true) with check (true);

-- Cliente envia pedido por esta função (o preço e o total são calculados aqui, não no navegador)
create or replace function criar_pedido(
  p_cliente text, p_telefone text, p_tipo text,
  p_endereco text, p_obs text, p_itens jsonb
) returns bigint
language plpgsql security definer set search_path = public as $$
declare
  v_itens jsonb;
  v_total numeric(10,2);
  v_num bigint;
begin
  if coalesce(trim(p_cliente),'') = '' or coalesce(trim(p_telefone),'') = '' then
    raise exception 'Informe nome e telefone.';
  end if;
  if p_tipo not in ('Retirada','Entrega') then
    raise exception 'Tipo de pedido inválido.';
  end if;
  if p_tipo = 'Entrega' and coalesce(trim(p_endereco),'') = '' then
    raise exception 'Informe o endereço de entrega.';
  end if;

  select jsonb_agg(jsonb_build_object('nome', i.nome, 'qtd', q.qtd, 'preco', i.preco)),
         sum(i.preco * q.qtd)
    into v_itens, v_total
    from jsonb_to_recordset(p_itens) as q(id bigint, qtd int)
    join itens i on i.id = q.id and i.disponivel
   where q.qtd > 0 and q.qtd <= 50;

  if v_itens is null then
    raise exception 'Os itens escolhidos não estão mais disponíveis.';
  end if;

  insert into pedidos (cliente, telefone, tipo, endereco, observacao, itens, total)
  values (trim(p_cliente), trim(p_telefone), p_tipo, coalesce(p_endereco,''), coalesce(p_obs,''), v_itens, v_total)
  returning numero into v_num;

  return v_num;
end $$;

grant execute on function criar_pedido(text,text,text,text,text,jsonb) to anon, authenticated;

-- Pedidos novos aparecem na hora no painel da loja
alter publication supabase_realtime add table pedidos;

-- Cardápio de exemplo (a loja pode apagar e criar os seus no painel)
insert into itens (nome, descricao, preco, categoria) values
  ('Pastel de carne', 'Massa crocante, recheio caseiro', 8, 'Salgados'),
  ('Pastel de queijo', 'Queijo derretido', 8, 'Salgados'),
  ('X-Salada', 'Hambúrguer, queijo, alface e tomate', 18, 'Lanches'),
  ('Suco de laranja', '500 ml, natural', 7, 'Bebidas'),
  ('Brigadeiro', 'Unidade', 4, 'Doces');
