-- 회원 탈퇴: 현재 로그인(auth.uid()) 사용자 데이터 정리 + auth 계정 삭제
-- SECURITY DEFINER 함수이므로 search_path를 고정해 SQL 주입/오염을 방지합니다.

create or replace function public.delete_my_account()
returns void
language plpgsql
security definer
set search_path = public, auth
as $$
declare
  v_uid uuid;
begin
  v_uid := auth.uid();
  if v_uid is null then
    raise exception 'not authenticated';
  end if;

  -- 내가 만든 이벤트의 가시성 연결 제거
  delete from public.event_visibility ev
  using public.events e
  where ev.event_id = e.id
    and e.creator_id = v_uid;

  -- 내가 만든 이벤트 삭제
  delete from public.events
  where creator_id = v_uid;

  -- 내가 만든 그룹의 연결 데이터 정리
  delete from public.event_visibility ev
  using public.groups g
  where ev.group_id = g.id
    and g.created_by = v_uid;

  delete from public.group_members gm
  using public.groups g
  where gm.group_id = g.id
    and g.created_by = v_uid;

  -- 내가 만든 그룹 삭제
  delete from public.groups
  where created_by = v_uid;

  -- 내가 속한 그룹 멤버십 삭제
  delete from public.group_members
  where user_id = v_uid;

  -- 프로필 삭제
  delete from public.profiles
  where id = v_uid;

  -- auth 사용자 삭제
  delete from auth.users
  where id = v_uid;
end;
$$;

grant execute on function public.delete_my_account() to authenticated;

