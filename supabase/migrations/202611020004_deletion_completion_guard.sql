-- Persist verification across the crash window between Auth removal and the
-- completion receipt. An unrelated administrative Auth deletion is not proof
-- that storage cleanup succeeded.
alter table manna_private.deletion_receipts add column cleanup_verified_at timestamptz;
create function public.verify_account_deletion_cleanup(p_user uuid) returns boolean language plpgsql security definer set search_path='' as $$
begin
 if not public.account_deletion_ready(p_user) then return false; end if;
 update manna_private.deletion_receipts set cleanup_verified_at=now() where user_id=p_user;
 return true;
end $$;
create or replace function public.finish_account_deletion_receipt(p_user uuid) returns void
language plpgsql security definer set search_path='' as $$ begin
 if exists(select 1 from auth.users where id=p_user) then raise exception 'Account still exists'; end if;
 if exists(select 1 from manna_private.deletion_receipts where user_id=p_user and cleanup_verified_at is null) then raise exception 'Storage cleanup was not verified'; end if;
 update manna_private.deletion_receipts set user_id=null,completed_at=now() where user_id=p_user;
end $$;
revoke all on function public.verify_account_deletion_cleanup(uuid),public.finish_account_deletion_receipt(uuid) from public,anon,authenticated;
grant execute on function public.verify_account_deletion_cleanup(uuid),public.finish_account_deletion_receipt(uuid) to service_role;
notify pgrst,'reload schema';
