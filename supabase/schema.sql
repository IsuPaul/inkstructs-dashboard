-- Inkstructs v1 foundation schema
create extension if not exists "pgcrypto";

create type public.app_role as enum ('admin','instructor','student');
create type public.enrollment_status as enum ('pending_payment','invited','active','completed','paused','refunded');
create type public.course_level as enum ('beginner','intermediate','advanced');

create table public.profiles (
  id uuid primary key references auth.users(id) on delete cascade,
  full_name text not null,
  email text not null,
  role public.app_role not null default 'student',
  avatar_url text,
  bio text,
  created_at timestamptz not null default now()
);

create table public.courses (
  id uuid primary key default gen_random_uuid(),
  title text not null,
  slug text not null unique,
  description text not null default '',
  thumbnail_url text,
  level public.course_level not null default 'beginner',
  duration_weeks integer not null check (duration_weeks > 0),
  days_per_week integer not null check (days_per_week between 1 and 7),
  price_kobo bigint not null default 0 check (price_kobo >= 0),
  currency text not null default 'NGN',
  is_published boolean not null default false,
  created_at timestamptz not null default now()
);

create table public.cohorts (
  id uuid primary key default gen_random_uuid(),
  course_id uuid not null references public.courses(id) on delete cascade,
  name text not null,
  start_date date not null,
  end_date date,
  capacity integer not null default 30 check (capacity > 0),
  price_kobo bigint not null default 0 check (price_kobo >= 0),
  status text not null default 'draft' check (status in ('draft','open','running','completed')),
  created_at timestamptz not null default now()
);

create table public.enrollments (
  id uuid primary key default gen_random_uuid(),
  student_id uuid not null references public.profiles(id) on delete cascade,
  cohort_id uuid not null references public.cohorts(id) on delete cascade,
  status public.enrollment_status not null default 'pending_payment',
  invited_at timestamptz,
  joined_at timestamptz,
  created_at timestamptz not null default now(),
  unique(student_id, cohort_id)
);

create table public.weeks (
  id uuid primary key default gen_random_uuid(),
  course_id uuid not null references public.courses(id) on delete cascade,
  week_number integer not null check (week_number > 0),
  title text not null,
  summary text not null default '',
  unique(course_id, week_number)
);

create table public.modules (
  id uuid primary key default gen_random_uuid(),
  week_id uuid not null references public.weeks(id) on delete cascade,
  day_number integer not null check (day_number > 0),
  position integer not null default 1,
  title text not null,
  description text not null default '',
  is_required boolean not null default true
);

create table public.lessons (
  id uuid primary key default gen_random_uuid(),
  module_id uuid not null references public.modules(id) on delete cascade,
  position integer not null default 1,
  title text not null,
  type text not null default 'text' check (type in ('video','document','image','text','link','assignment','live')),
  content_text text not null default '',
  external_url text,
  duration_min integer not null default 0 check (duration_min >= 0),
  is_required boolean not null default true
);

create table public.lesson_progress (
  id uuid primary key default gen_random_uuid(),
  student_id uuid not null references public.profiles(id) on delete cascade,
  lesson_id uuid not null references public.lessons(id) on delete cascade,
  completed_at timestamptz not null default now(),
  unique(student_id, lesson_id)
);

create table public.announcements (
  id uuid primary key default gen_random_uuid(),
  cohort_id uuid not null references public.cohorts(id) on delete cascade,
  author_id uuid not null references public.profiles(id),
  title text not null,
  body text not null,
  created_at timestamptz not null default now()
);

create index enrollments_student_idx on public.enrollments(student_id);
create index enrollments_cohort_idx on public.enrollments(cohort_id);
create index lesson_progress_student_idx on public.lesson_progress(student_id);
create index lesson_progress_lesson_idx on public.lesson_progress(lesson_id);

create or replace function public.is_admin() returns boolean language sql stable security definer set search_path = public as $$
  select exists(select 1 from public.profiles where id = auth.uid() and role = 'admin');
$$;

create or replace function public.handle_new_user() returns trigger language plpgsql security definer set search_path = public as $$
begin
  insert into public.profiles(id, full_name, email) values (new.id, coalesce(new.raw_user_meta_data->>'full_name','New student'), new.email);
  return new;
end;
$$;

create trigger on_auth_user_created after insert on auth.users for each row execute procedure public.handle_new_user();

alter table public.profiles enable row level security;
alter table public.courses enable row level security;
alter table public.cohorts enable row level security;
alter table public.enrollments enable row level security;
alter table public.weeks enable row level security;
alter table public.modules enable row level security;
alter table public.lessons enable row level security;
alter table public.lesson_progress enable row level security;
alter table public.announcements enable row level security;

create policy "profiles self or admin" on public.profiles for select using (id = auth.uid() or public.is_admin());
create policy "profiles self update" on public.profiles for update using (id = auth.uid());
create policy "published courses visible" on public.courses for select using (is_published or public.is_admin());
create policy "admin manages courses" on public.courses for all using (public.is_admin()) with check (public.is_admin());
create policy "enrolled cohorts visible" on public.cohorts for select using (public.is_admin() or exists (select 1 from public.enrollments e where e.cohort_id = cohorts.id and e.student_id = auth.uid() and e.status = 'active'));
create policy "student sees own enrollments" on public.enrollments for select using (student_id = auth.uid() or public.is_admin());
create policy "content for active students" on public.weeks for select using (public.is_admin() or exists (select 1 from public.enrollments e join public.cohorts c on c.id = e.cohort_id where c.course_id = weeks.course_id and e.student_id = auth.uid() and e.status = 'active'));
create policy "modules follow course access" on public.modules for select using (public.is_admin() or exists (select 1 from public.weeks w join public.enrollments e on e.student_id = auth.uid() join public.cohorts c on c.id = e.cohort_id where w.id = modules.week_id and c.course_id = w.course_id and e.status = 'active'));
create policy "lessons follow module access" on public.lessons for select using (public.is_admin() or exists (select 1 from public.modules m join public.weeks w on w.id = m.week_id join public.enrollments e on e.student_id = auth.uid() join public.cohorts c on c.id = e.cohort_id where m.id = lessons.module_id and c.course_id = w.course_id and e.status = 'active'));
create policy "students manage own progress" on public.lesson_progress for all using (student_id = auth.uid() or public.is_admin()) with check (student_id = auth.uid() or public.is_admin());
create policy "active students see announcements" on public.announcements for select using (public.is_admin() or exists (select 1 from public.enrollments e where e.cohort_id = announcements.cohort_id and e.student_id = auth.uid() and e.status = 'active'));
