
create table public.auctions (
 id uuid primary key default gen_random_uuid(),
 seller_id uuid not null references auth.users(id),
 seller_name text not null check(length(seller_name) between 1 and 80),
 name text not null check(length(name) between 1 and 140),
 category text not null,
 city text not null check(length(city) between 1 and 80),
 description text not null default '' check(length(description)<=4000),
 image_url text not null default '',
 price numeric(12,2) not null check(price>0),
 buy_now numeric(12,2) check(buy_now>0),
 end_time timestamptz not null,
 sold boolean not null default false,
 winner_id uuid references auth.users(id),
 created_at timestamptz not null default now()
);
create table public.bids (
 id uuid primary key default gen_random_uuid(),
 auction_id uuid not null references public.auctions(id),
 bidder_id uuid not null references auth.users(id),
 amount numeric(12,2) not null check(amount>0),
 created_at timestamptz not null default now()
);
alter table public.auctions enable row level security;
alter table public.bids enable row level security;
create policy "Read listings" on public.auctions for select to anon, authenticated using(true);
create policy "Create own listing" on public.auctions for insert to authenticated
 with check(seller_id=auth.uid() and winner_id is null and sold=false and end_time>now()
 and end_time<=now()+interval '30 days' and (buy_now is null or buy_now>=price));
create policy "Read own bids" on public.bids for select to authenticated using(bidder_id=auth.uid());
grant select on public.auctions to anon,authenticated;
grant insert on public.auctions to authenticated;
grant select on public.bids to authenticated;
revoke update,delete on public.auctions from anon,authenticated;
revoke insert,update,delete on public.bids from anon,authenticated;
create function public.place_bid(p_auction_id uuid,p_amount numeric) returns void
 language plpgsql security definer set search_path='' as $$
 declare a public.auctions;
 begin
 if auth.uid() is null then raise exception 'Please sign in first.'; end if;
 select * into a from public.auctions where id=p_auction_id for update;
 if not found then raise exception 'Listing not found.'; end if;
 if a.seller_id=auth.uid() then raise exception 'You cannot bid on your own item.'; end if;
 if a.sold or a.end_time<=now() then raise exception 'This auction has ended.'; end if;
 if p_amount is null or p_amount::text in ('NaN','Infinity','-Infinity') or p_amount<=a.price or p_amount>9999999999.99 or p_amount<>round(p_amount,2) then
 raise exception 'Enter a higher bid with at most two decimal places.'; end if;
 insert into public.bids(auction_id,bidder_id,amount) values(a.id,auth.uid(),p_amount);
 update public.auctions set price=p_amount,winner_id=auth.uid() where id=a.id;
 end $$;
create function public.reserve_item(p_auction_id uuid) returns void
 language plpgsql security definer set search_path='' as $$
 declare a public.auctions;
 begin
 if auth.uid() is null then raise exception 'Please sign in first.'; end if;
 select * into a from public.auctions where id=p_auction_id for update;
 if not found then raise exception 'Listing not found.'; end if;
 if a.seller_id=auth.uid() then raise exception 'You cannot reserve your own item.'; end if;
 if a.sold or a.end_time<=now() or a.buy_now is null then raise exception 'This item is unavailable.'; end if;
 insert into public.bids(auction_id,bidder_id,amount) values(a.id,auth.uid(),a.buy_now);
 update public.auctions set sold=true,price=a.buy_now,winner_id=auth.uid() where id=a.id;
 end $$;
revoke all on function public.place_bid(uuid,numeric) from public,anon;
revoke all on function public.reserve_item(uuid) from public,anon;
grant execute on function public.place_bid(uuid,numeric) to authenticated;
grant execute on function public.reserve_item(uuid) to authenticated;


alter table public.auctions add constraint finite_price check(price::text not in ('NaN','Infinity','-Infinity')), add constraint finite_buy_now check(buy_now is null or buy_now::text not in ('NaN','Infinity','-Infinity'));
create index auctions_created_at_idx on public.auctions(created_at desc);
create index bids_auction_idx on public.bids(auction_id);
create index bids_bidder_idx on public.bids(bidder_id);
create index auctions_seller_idx on public.auctions(seller_id);
create index auctions_winner_idx on public.auctions(winner_id);
