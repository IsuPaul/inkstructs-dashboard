import { type NextRequest, NextResponse } from 'next/server'
import { createServerClient } from '@supabase/ssr'

export async function middleware(request: NextRequest) {
  let response = NextResponse.next({ request })
  const supabaseUrl = process.env.NEXT_PUBLIC_SUPABASE_URL
  const supabaseKey = process.env.NEXT_PUBLIC_SUPABASE_ANON_KEY
  if (!supabaseUrl || !supabaseKey) {
    if (request.nextUrl.pathname === '/') return NextResponse.redirect(new URL('/login', request.url))
    return response
  }
  try {
    const supabase = createServerClient(supabaseUrl, supabaseKey, {
      cookies: { getAll: () => request.cookies.getAll(), setAll: cookiesToSet => cookiesToSet.forEach(({ name, value, options }) => { request.cookies.set(name, value); response.cookies.set(name, value, options) }) },
    })
    const { data: { user } } = await supabase.auth.getUser()
    if (!user && request.nextUrl.pathname === '/') return NextResponse.redirect(new URL('/login', request.url))
    if (user && request.nextUrl.pathname === '/login') return NextResponse.redirect(new URL('/', request.url))
  } catch {
    if (request.nextUrl.pathname === '/') return NextResponse.redirect(new URL('/login', request.url))
    return response
  }
  return response
}

export const config = { matcher: ['/', '/login'] }
