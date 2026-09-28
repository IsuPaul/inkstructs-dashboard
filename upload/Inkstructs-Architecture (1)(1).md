---
title: "Inkstructs — Learning Platform Architecture"
subtitle: "Technical architecture and build plan (v1.2 — decisions confirmed)"
---

# 1. Product overview

**Inkstructs** is an instructor-led online training platform offering courses such as Website Development, AI & Automation, and Python Programming. It has three experiences in one application:

| Portal | Who | Purpose |
|---|---|---|
| **Admin portal** | Owner / staff | Review applications, accept students, take payments, build courses, manage cohorts and instructors, issue certificates |
| **Instructor portal** | Teachers | Manage their assigned cohorts, upload materials, post announcements, schedule live classes, grade assignments, track their students |
| **Student dashboard** | Accepted, paid students | See only enrolled courses, follow a week-by-week roadmap, watch lessons, mark modules complete, download certificates |

**Key design decision: courses vs. cohorts.** A *course* is reusable content (e.g. "Python Programming"). A *cohort* is one live run of it (e.g. "Python — Nov 2026 Batch") with its own start date, instructor(s), price and students. Content is written once and delivered many times.

# 2. Tech stack

| Layer | Choice | Reason |
|---|---|---|
| Framework | Next.js 15 (App Router) + TypeScript | Server Components, Server Actions, middleware |
| UI | Tailwind CSS + shadcn/ui | Professional, consistent, fast to build |
| Auth | Supabase Auth (invite-only) | `inviteUserByEmail`, password reset, sessions |
| Database | Supabase Postgres + Row Level Security | Security enforced at data layer |
| File storage | Supabase Storage (private buckets) | PDFs, images, documents, certificates via signed URLs |
| Video | **Mux** (recommended) | Direct uploads, adaptive streaming, signed playback, view analytics, built for many hours of video |
| Payments | **Paystack (NGN)** | Nigerian cards, bank transfer, USSD; full payment; webhook-driven (see section 9) |
| Email | Resend + React Email | Branded invites, receipts, reminders |
| Certificates | `@react-pdf/renderer` (server-side PDF) | Branded PDF with QR code and verification ID |
| Hosting / CI | Vercel + GitHub | Preview deploys per pull request |
| Forms / validation | React Hook Form + Zod | Type-safe forms and server validation |
| Background jobs | Supabase Edge Functions / Vercel Cron | Reminders, drip unlocks, certificate generation |

# 3. High-level flow

```
Applicant -> Public site -> Application form -> applications (pending)
                                      |
                        Admin reviews -> Accept + assigns cohort
                                      |
                     Paystack checkout link (NGN, full payment)
                                      |
                     Payment webhook confirms (server-side)
                                      |
        enrollment set to active + auth.admin.inviteUserByEmail()
                                      |
       Student sets password -> /dashboard (only their courses)
                                      |
     Course -> Weeks -> Modules -> Lessons (video, docs, images, text)
                                      |
   Lesson complete -> Module COMPLETE -> Week complete -> Course 100%
                                      |
                    Certificate auto-generated + emailed
```

# 4. Roles and permissions

| Capability | Admin | Instructor | Student |
|---|:-:|:-:|:-:|
| Manage applications, payments, refunds | Yes | No | No |
| Create / edit courses and cohorts | Yes | No | No |
| Assign instructors to cohorts | Yes | No | No |
| Upload materials and videos to assigned courses | Yes | Yes | No |
| View students and progress | All | Own cohorts only | Self only |
| Post announcements | Yes | Own cohorts | No |
| Grade assignments, leave feedback | Yes | Own cohorts | No |
| Schedule live classes | Yes | Own cohorts | No |
| Issue / revoke certificates | Yes | Recommend only | Download own |
| View course content | Yes | Assigned | Enrolled and paid |

Roles are stored in `profiles.role` (`admin`, `instructor`, `student`). Next.js middleware gates routes for UX; **Postgres RLS is the true security boundary**.

# 5. Content hierarchy

This structure gives you full control over the number of weeks and days:

```
Course        (duration_weeks, days_per_week - set by admin)
 |- Cohort    (start_date, instructors, price, capacity)
 |- Week 1..N
     |- Module (assigned to Day 1..D)
         |- Lesson (video | document | image | text | link | assignment | live class)
```

- When creating a course you enter **weeks** and **days per week**. The builder generates the empty week/day grid, which can be extended or trimmed later.
- **Drip release** is configurable per course: `none`, `by_date` (Week 2 opens on cohort start + 7 days), or `by_completion` (Week 2 opens after Week 1 is complete).
- Modules can be marked required or optional. Only required lessons count toward completion.

# 6. Database schema

```sql
-- Identity
profiles (id uuid PK -> auth.users, full_name, email, role, avatar_url, bio, created_at)

-- Admissions
applications (id, full_name, email, phone, course_id, cohort_id, message,
              status ['pending','accepted','rejected','enrolled'],
              reviewed_by, reviewed_at, created_at)

-- Content (reusable)
courses  (id, title, slug, description, thumbnail_url, level,
          duration_weeks, days_per_week,
          drip_mode ['none','by_date','by_completion'],
          price_kobo bigint, currency default 'NGN', is_published, created_at)
weeks    (id, course_id, week_number, title, summary)
modules  (id, week_id, day_number, position, title, description, is_required)
lessons  (id, module_id, position, title,
          type ['video','document','image','text','link','assignment','live'],
          content_text, external_url, duration_min, is_required)
assets   (id, lesson_id, storage_path, mime_type, size_bytes,
          video_source ['mux','external_link'],  -- swappable video host
          mux_asset_id, mux_playback_id, created_at)

-- Delivery
cohorts            (id, course_id, name, start_date, end_date,
                    capacity, price_kobo bigint, currency default 'NGN',
                    status ['draft','open','running','completed'])
cohort_instructors (cohort_id, instructor_id, role ['lead','assistant'])
enrollments        (id, student_id, cohort_id,
                    status ['pending_payment','invited','active','completed','paused','refunded'],
                    invited_at, joined_at, unique(student_id, cohort_id))
live_sessions      (id, cohort_id, title, starts_at, duration_min, meeting_url, recording_url)

-- Progress
lesson_progress (id, student_id, lesson_id, completed_at, unique(student_id, lesson_id))
module_progress (id, student_id, module_id,
                 status ['not_started','in_progress','complete'], completed_at)

-- Assessment
submissions (id, student_id, lesson_id, file_url, text_answer,
             status ['submitted','graded','resubmit'],
             grade, feedback, graded_by, graded_at)

-- Payments (full payment, NGN)
payments (id, enrollment_id, provider default 'paystack', provider_ref unique,
          amount_kobo bigint, currency default 'NGN',
          status ['pending','paid','failed','refunded'],
          paid_at, raw_event jsonb)
coupons (id, code, percent_off, amount_off, max_uses, expires_at)

-- Certificates
certificates (id, enrollment_id, student_id, course_id, cohort_id,
              verification_code unique, pdf_path, issued_at,
              revoked_at, issued_by)

-- Communication
announcements (id, cohort_id, author_id, title, body, created_at)
```

**Progress logic**

1. A student marks a lesson complete, which writes to `lesson_progress`.
2. A trigger (or Server Action) checks whether all *required* lessons in the module are done; if so the module becomes **COMPLETE**.
3. A week is complete when all its required modules are complete.
4. Course percentage is computed in a SQL view (never stored), so it can never drift.

# 7. Security model (RLS)

- **Students** can read course content only when they hold an `active` enrollment in a cohort of that course. They can write only their own progress and submissions.
- **Instructors** can read and write content and student data only for cohorts listed in `cohort_instructors`.
- **Admins** have full access.
- **Payments and certificates**: students read only their own rows; writes happen only through server code using the service-role key.
- Storage buckets are private; files are served through short-lived signed URLs. Mux playback uses **signed playback tokens**, so video links cannot be shared or hot-linked.
- The service-role key and payment secrets live only in server environment variables.
- Payment webhooks verify provider signatures and are idempotent.

# 8. Video pipeline (Mux)

1. The admin or instructor picks a video in the builder.
2. The server requests a **Mux direct upload URL**; the browser uploads straight to Mux (never through Vercel, which has a ~4.5 MB request limit).
3. Mux processes the file and calls a webhook; we store `mux_asset_id` and `mux_playback_id` on the asset.
4. Students watch through the Mux player with signed tokens, adaptive bitrate and resume-from-last-position.
5. Mux Data provides watch-time analytics that can feed instructor dashboards.

**Your workflow:** record the class on Zoom, save the MP4, then drag it into the lesson in the admin panel. The platform uploads it to Mux in the background and shows an upload/processing status until the video is ready to publish.

The video host is kept behind a small interface (`video_source` on each asset). Lessons can also accept a YouTube/Vimeo link for free or preview content, and another host such as Bunny Stream could be added later without changing the rest of the app.

Documents and images use signed direct uploads to Supabase Storage.

# 9. Payments

**Recommended flow (payment before access):**

1. Admin accepts an application and the student receives a **secure checkout link**.
2. The student pays the **full course fee in naira** by card, bank transfer or USSD through Paystack.
3. The provider calls our **webhook**; after signature verification the payment is marked `paid`.
4. The webhook sets the enrollment to `active` and triggers the **account invite email**.
5. A receipt email is sent; admins see the payment in the finance view.

Notes:

- Never trust the browser redirect for payment confirmation; only the verified webhook can activate access.
- Support coupons, scholarships (admin-set 100% discount), refunds (which pause or revoke access), and reminders for unpaid checkout links.
- Amounts are stored in **kobo** (integers) to avoid rounding errors.
- Paystack is used because students are in Nigeria. The payment code sits behind a small interface so another provider (e.g. Stripe for international students) can be added later without rewriting the app.
- Bank transfer and USSD payments confirm more slowly than cards, so access is granted only when the webhook arrives, never from the browser redirect.

# 10. Certificates

- **Eligibility rule** (configurable per course): 100% of required modules complete, plus optional minimum assignment grade and payment in full.
- On eligibility, a background job generates a branded **PDF certificate** containing student name, course, cohort dates, issue date, instructor/director signature, a **QR code** and a unique **verification code**. The signatory is **Paul Inya Isu (Admin / Director)**; the signature image is stored once in settings and applied to every certificate.
- The PDF is stored in a private bucket and emailed; students can re-download from `/certificates`.
- A public page `/verify/[code]` confirms authenticity (name, course, date), which employers can check.
- Admins can revoke a certificate; the verify page then shows it as revoked.

# 11. Page map

**Student**

- `/dashboard` — greeting, enrolled course cards with progress rings, "Continue learning", upcoming live classes, announcements
- `/courses/[slug]` — week roadmap with status badges (Locked, In progress, Complete)
- `/courses/[slug]/modules/[id]` — lesson player, materials, **Mark as complete**, next/previous
- `/assignments`, `/certificates`, `/payments`, `/profile`

**Instructor**

- `/teach` — my cohorts, upcoming sessions, submissions awaiting grading
- `/teach/cohorts/[id]` — student list with progress, announcements, live sessions
- `/teach/courses/[id]/builder` — upload and edit materials for assigned courses
- `/teach/submissions` — grading queue with feedback

**Admin**

- `/admin` — KPIs: applications, revenue, active students, completion rates
- `/admin/applications` — review, accept, reject, send payment link
- `/admin/courses` and `/builder` — set weeks/days, drag-and-drop modules, uploads
- `/admin/cohorts` — batches, pricing, instructors, capacity
- `/admin/students`, `/admin/instructors`
- `/admin/payments` — transactions, refunds, coupons
- `/admin/certificates` — issued list, revoke, reissue
- `/admin/announcements`, `/admin/settings`

**Public**

- `/` landing, `/courses` catalogue, `/apply`, `/login`, `/verify/[code]`

# 12. Look and feel

- Working brand direction until real assets exist: ink-inspired palette (deep navy/indigo with a bright accent), clean type (Inter or Geist), generous whitespace. Brand tokens live in one Tailwind theme file so a future logo/colour change is a single edit.
- Left sidebar on desktop, bottom navigation on mobile; fully responsive since many learners study on phones.
- Light and dark mode.
- Vertical week timeline with green check badges for completed modules; progress rings on course cards.
- Celebration micro-interaction when a module or course is completed.

# 13. Project structure

```
/app
  /(public)      landing, courses, apply, login, verify/[code]
  /(student)     dashboard, courses/[slug], assignments, certificates
  /(instructor)  teach/...
  /(admin)       admin/...
  /api           webhooks: payments, mux, email
/components      ui/, course/, admin/, instructor/
/lib             supabase/{client,server,admin}.ts, payments/, mux/, validators, utils
/actions         invite.ts, progress.ts, course-builder.ts, grading.ts, certificates.ts
/emails          invite, receipt, reminder, certificate templates
/supabase        migrations/, seed.sql
middleware.ts    auth + role gating
```

# 14. Build roadmap

| Phase | Scope | Outcome |
|---|---|---|
| **1. Foundation** | Next.js + Supabase setup, auth, roles (admin/instructor/student), schema and RLS, middleware, design tokens | Secure skeleton |
| **2. Course builder** | Courses, weeks/days, modules, lessons, Supabase uploads, Mux video uploads | Content can be created |
| **3. Admissions and payments** | Application form, review screen, checkout, webhooks, invite email | Students can apply, pay and get in |
| **4. Student dashboard** | Course cards, week roadmap, lesson player, progress and COMPLETE states | Learning experience live |
| **5. Instructor portal** | Cohort views, grading, announcements, live sessions | Teachers operational |
| **6. Certificates** | Eligibility engine, PDF generation, verification page | Credentials issued |
| **7. Polish and launch** | Analytics, reminders, drip release, QA, security review, production deploy | Go-live |
| **Later** | Quizzes, discussion forum, referral codes, mobile app, multi-language | Growth features |

# 15. Confirmed decisions

| Topic | Decision |
|---|---|
| Video | Hosted on **Mux** (confirmed over Loom and plain storage). Zoom MP4s uploaded through the admin panel. Loom and other hosts considered and not used for launch |
| Payments | Through the platform, **Paystack, NGN, full payment only** (no installments) |
| Delivery model | Instructor-led cohorts, with a Teacher (instructor) role |
| Live classes | Meeting links are stored and shown to students (no Zoom/Meet integration in v1) |
| Certificates | Issued on completion, signed by **Paul Inya Isu (Admin)** |
| Students | Nigeria; launch target of **1,000+ students** |
| Video volume | About 3 hours of video to start |
| Branding | Name is **Inkstructs**; logo and colours to come |

# 16. Scale and cost planning (1,000+ students)

**Video (Mux).** Mux bills per minute for storage and delivery, and its published pricing includes a monthly allowance of free delivery minutes. With about 3 hours (180 minutes) of video, storage is negligible. Delivery is the main cost:

| Scenario | Minutes delivered | Notes |
|---|---|---|
| 1,000 students watch everything once | about 180,000 | Roughly the first 100,000 minutes/month can fall inside the free allowance |
| Same students, average 2 views each | about 360,000 | Estimated at low tens to a few hundred US dollars in total |

These are planning estimates based on Mux's public pricing, not a quote. Confirm with the Mux pricing calculator before launch. To keep costs and student data usage low: use Mux **basic quality**, cap playback at 720p by default, and let the student choose a lower quality on weak connections.

**Nigerian network conditions.** Many students will be on mobile data, so the app is built mobile-first, with lightweight pages, adaptive video (which automatically drops quality on slow connections), and resume-from-last-position.

**Infrastructure sizing.** 1,000 students is comfortable for Supabase and Vercel on paid plans (Supabase Pro, Vercel Pro). Use database indexes on `student_id`, `cohort_id`, and `lesson_id`; keep progress writes small; and put the per-course progress view behind an index-friendly query.

**Payment fees.** Paystack charges a percentage per transaction (capped for local payments). Confirm the current rate in the Paystack dashboard and decide whether the course price absorbs it or passes it on.

**Safeguards at this scale.** Rate-limit login and application forms, verify every webhook signature, keep audit logs for payments and certificate issuance, and schedule daily database backups.

# 17. Phase 1 deliverables (next step)

1. Next.js 15 + TypeScript + Tailwind + shadcn/ui project, deployed to Vercel from GitHub
2. Supabase project with the full schema as versioned SQL migrations
3. Row Level Security policies for admin, instructor and student roles
4. Invite-only authentication, password set/reset, and role-based route protection
5. Base layouts: student shell, instructor shell, admin shell, with the Inkstructs placeholder theme
6. Seed script creating the first admin account (Paul Inya Isu)

**What you need ready:** a GitHub account, a Supabase account, a Vercel account, and (later, for Phase 3) a Paystack business account and a Mux account.
