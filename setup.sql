-- I-paste sa Supabase > SQL Editor > Run
create table activities(
 id uuid primary key default gen_random_uuid(),
 code text unique not null, title text not null,
 kind text not null default 'Seatwork', section text,
 start_at timestamptz not null default now(),
 deadline_at timestamptz not null,
 closed boolean not null default false,
 created_at timestamptz not null default now());
create table submissions(
 id uuid primary key default gen_random_uuid(),
 activity_id uuid not null references activities(id) on delete cascade,
 student_name text not null, section text, device text, ip text,
 files text[] not null, created_at timestamptz not null default now());
alter table activities enable row level security;
alter table submissions enable row level security;
create policy admin_all on activities for all to authenticated using(true) with check(true);
create policy admin_all on submissions for all to authenticated using(true) with check(true);

create function is_open(c text) returns boolean language sql stable security definer set search_path=public as
$$ select exists(select 1 from activities where code=c and not closed and now() between start_at and deadline_at) $$;

create function get_activity(c text) returns json language sql stable security definer set search_path=public as
$$ select json_build_object('title',title,'kind',kind,
 'open',(not closed and now() between start_at and deadline_at),
 'state',case when closed or now()>deadline_at then 'closed' when now()<start_at then 'scheduled' else 'open' end)
 from activities where code=c $$;

create function submit(c text, nm text, sec text, dev text, f text[]) returns json language plpgsql security definer set search_path=public as $$
declare aid uuid; h json;
begin
 select id into aid from activities where code=c and not closed and now() between start_at and deadline_at;
 if aid is null then raise exception 'CLOSED'; end if;
 begin h:=current_setting('request.headers',true)::json; exception when others then h:='{}'::json; end;
 insert into submissions(activity_id,student_name,section,device,ip,files)
 values(aid,left(nm,100),left(sec,50),left(dev,60),trim(split_part(coalesce(h->>'x-forwarded-for',''),',',1)),f);
 return json_build_object('ok',true);
end $$;
grant execute on function is_open(text),get_activity(text),submit(text,text,text,text,text[]) to anon,authenticated;

insert into storage.buckets(id,name,public) values('uploads','uploads',false) on conflict do nothing;
create policy up_insert on storage.objects for insert to anon,authenticated
 with check(bucket_id='uploads' and public.is_open(split_part(name,'/',1)));
create policy up_admin on storage.objects for all to authenticated
 using(bucket_id='uploads') with check(bucket_id='uploads');
