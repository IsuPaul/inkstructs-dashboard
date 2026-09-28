# Inkstructs Dashboard

## Version 1.3.0

Updated real-dashboard foundation based on the Inkstructs architecture document.

Included:

- Next.js 15 App Router structure
- TypeScript configuration
- Tailwind CSS setup
- Responsive student dashboard
- Reusable dashboard component
- Typed mock course data
- Interactive dashboard actions
- Next.js 16.3.6-compatible package configuration
- JavaScript Next.js config for Node.js 24 compatibility
- Removed deprecated `next lint` script
- Refined visual direction to a spacious green-and-white learning portal
- Increased dashboard scale and course-card prominence
- Reduced accent colours for a calmer interface
- Removed deprecated TypeScript `baseUrl` option for Next.js 16 builds
- Fixed typed Lucide navigation items for production TypeScript builds
- Added Supabase schema, RLS policies, auth profile trigger, and typed client helpers
- Added Supabase email/password login
- Added secure session middleware and auth callback route
- Protected the dashboard for authenticated users
- Hardened Supabase middleware against missing or invalid production configuration
- Enforced login redirect when visiting the protected dashboard without a valid session
- Added login error handling so failed Supabase requests do not leave the form stuck
- Added real routes for courses, assignments, calendar, certificates, payments, settings, and help
- Replaced placeholder navigation links with working page links
- Original architecture reference document

Future updates should increment the version and preserve the architecture document in the archive.
