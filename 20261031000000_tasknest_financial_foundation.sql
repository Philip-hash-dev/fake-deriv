create table public.profiles (
  id uuid primary key references auth.users (id) on delete cascade,
  display_name text,
  is_owner boolean not null default false,
  created_at timestamptz not null default now()
);

create function public.create_profile_for_new_user()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  insert into public.profiles (id)
  values (new.id)
  on conflict (id) do nothing;
  return new;
end;
$$;

revoke all on function public.create_profile_for_new_user() from public, anon, authenticated;

create trigger create_profile_after_signup
after insert on auth.users
for each row execute function public.create_profile_for_new_user();

create table public.reward_campaigns (
  id uuid primary key default gen_random_uuid(),
  name text not null,
  funding_status text not null default 'unfunded'
    check (funding_status in ('unfunded', 'funded', 'paused', 'closed')),
  secured_budget_kes bigint not null default 0 check (secured_budget_kes >= 0),
  reserved_budget_kes bigint not null default 0 check (
    reserved_budget_kes >= 0 and reserved_budget_kes <= secured_budget_kes
  ),
  funding_reference text unique,
  funded_at timestamptz,
  created_at timestamptz not null default now(),
  check (funding_status <> 'funded' or secured_budget_kes > 0)
);

create table public.tasks (
  id uuid primary key default gen_random_uuid(),
  campaign_id uuid not null references public.reward_campaigns (id),
  title text not null,
  description text not null,
  reward_kes bigint not null check (reward_kes > 0),
  slots_total integer not null check (slots_total > 0),
  slots_remaining integer not null check (slots_remaining >= 0 and slots_remaining <= slots_total),
  status text not null default 'draft'
    check (status in ('draft', 'published', 'paused', 'closed')),
  created_at timestamptz not null default now()
);

create table public.task_submissions (
  id uuid primary key default gen_random_uuid(),
  task_id uuid not null references public.tasks (id),
  user_id uuid not null references auth.users (id),
  submission text not null,
  status text not null default 'pending'
    check (status in ('pending', 'approved', 'rejected')),
  reviewer_id uuid references public.profiles (id),
  review_reason text,
  created_at timestamptz not null default now(),
  reviewed_at timestamptz,
  unique (task_id, user_id),
  check (status = 'pending' or (reviewer_id is not null and review_reason is not null and reviewed_at is not null))
);

create table public.payment_transactions (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users (id),
  provider text not null check (provider in ('stripe', 'mpesa')),
  provider_reference text unique,
  amount_kes integer not null check (amount_kes between 50 and 200),
  status text not null default 'pending'
    check (status in ('pending', 'succeeded', 'failed', 'refunded')),
  created_at timestamptz not null default now(),
  settled_at timestamptz
);

create table public.wallet_ledger (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users (id),
  amount_kes bigint not null check (amount_kes <> 0),
  entry_type text not null check (
    entry_type in ('topup', 'refund', 'task_reward', 'withdrawal_hold', 'withdrawal_release', 'withdrawal_paid')
  ),
  idempotency_key text not null unique,
  payment_id uuid references public.payment_transactions (id),
  created_at timestamptz not null default now()
);

create table public.withdrawal_requests (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users (id),
  amount_kes bigint not null check (amount_kes > 0),
  status text not null default 'pending'
    check (status in ('pending', 'approved', 'rejected', 'paid', 'appealed')),
  requested_at timestamptz not null default now(),
  review_due_at timestamptz not null default (now() + interval '7 days'),
  decision_reason text,
  decided_by uuid references public.profiles (id),
  decided_at timestamptz,
  appeal_reason text,
  appealed_at timestamptz,
  payout_reference text unique,
  paid_at timestamptz,
  check (
    status in ('pending', 'appealed')
    or (decision_reason is not null and decided_by is not null and decided_at is not null)
  ),
  check (status <> 'paid' or (payout_reference is not null and paid_at is not null)),
  check (status <> 'appealed' or (appeal_reason is not null and appealed_at is not null))
);

create table public.withdrawal_audit_log (
  id uuid primary key default gen_random_uuid(),
  withdrawal_id uuid not null references public.withdrawal_requests (id),
  actor_id uuid not null references public.profiles (id),
  action text not null check (action in ('approved', 'rejected', 'paid', 'appealed')),
  reason text not null,
  created_at timestamptz not null default now()
);

create function public.reject_financial_record_mutation()
returns trigger
language plpgsql
set search_path = ''
as $$
begin
  raise exception 'Financial and audit records are append-only';
end;
$$;

revoke all on function public.reject_financial_record_mutation() from public, anon, authenticated;

create trigger wallet_ledger_is_append_only
before update or delete on public.wallet_ledger
for each row execute function public.reject_financial_record_mutation();

create trigger withdrawal_audit_log_is_append_only
before update or delete on public.withdrawal_audit_log
for each row execute function public.reject_financial_record_mutation();

alter table public.profiles enable row level security;
alter table public.reward_campaigns enable row level security;
alter table public.tasks enable row level security;
alter table public.task_submissions enable row level security;
alter table public.payment_transactions enable row level security;
alter table public.wallet_ledger enable row level security;
alter table public.withdrawal_requests enable row level security;
alter table public.withdrawal_audit_log enable row level security;

create policy "Users can read funded campaigns"
on public.reward_campaigns for select to authenticated
using (funding_status = 'funded');

create policy "Users can read their own profile"
on public.profiles for select to authenticated
using ((select auth.uid()) = id);

create policy "Users can read funded published tasks"
on public.tasks for select to authenticated
using (
  status = 'published'
  and slots_remaining > 0
  and exists (
    select 1
    from public.reward_campaigns campaign
    where campaign.id = tasks.campaign_id
      and campaign.funding_status = 'funded'
      and campaign.secured_budget_kes >= campaign.reserved_budget_kes
      and campaign.reserved_budget_kes >= tasks.reward_kes * tasks.slots_total
  )
);

create policy "Users can read their own submissions"
on public.task_submissions for select to authenticated
using ((select auth.uid()) = user_id);

create policy "Users can read their own payments"
on public.payment_transactions for select to authenticated
using ((select auth.uid()) = user_id);

create policy "Users can read their own wallet entries"
on public.wallet_ledger for select to authenticated
using ((select auth.uid()) = user_id);

create policy "Users can read their own withdrawal requests"
on public.withdrawal_requests for select to authenticated
using ((select auth.uid()) = user_id);

create policy "Users can read their own withdrawal decisions"
on public.withdrawal_audit_log for select to authenticated
using (
  exists (
    select 1
    from public.withdrawal_requests request
    where request.id = withdrawal_id
      and request.user_id = (select auth.uid())
  )
);

revoke all on public.profiles, public.reward_campaigns, public.tasks,
  public.task_submissions, public.payment_transactions, public.wallet_ledger,
  public.withdrawal_requests, public.withdrawal_audit_log
from public, anon, authenticated;

grant select on public.profiles, public.reward_campaigns, public.tasks, public.task_submissions,
  public.payment_transactions, public.wallet_ledger, public.withdrawal_requests,
  public.withdrawal_audit_log to authenticated;
