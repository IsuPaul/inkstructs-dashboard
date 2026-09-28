'use client'

import { FormEvent, useState } from 'react'
import { createClient } from '@/lib/supabase/client'

export default function LoginPage() {
  const [email, setEmail] = useState('')
  const [password, setPassword] = useState('')
  const [error, setError] = useState('')
  const [loading, setLoading] = useState(false)

  async function submit(event: FormEvent<HTMLFormElement>) {
    event.preventDefault()
    setLoading(true)
    setError('')
    try {
      const supabase = createClient()
      const { error: signInError } = await supabase.auth.signInWithPassword({ email, password })
      if (signInError) { setError(signInError.message); return }
      window.location.assign('/')
    } catch (caught) {
      setError(caught instanceof Error ? caught.message : 'Unable to connect to Supabase. Check your Vercel environment variables.')
    } finally {
      setLoading(false)
    }
  }

  return <main className="auth-page"><div className="auth-card"><div className="brand auth-brand"><div className="brand-mark">i</div><span>inkstructs</span></div><p className="eyebrow">STUDENT PORTAL</p><h1>Welcome back</h1><p className="muted">Sign in to continue your learning journey.</p><form onSubmit={submit}><label>Email address<input type="email" value={email} onChange={event=>setEmail(event.target.value)} placeholder="you@example.com" required /></label><label>Password<input type="password" value={password} onChange={event=>setPassword(event.target.value)} placeholder="Enter your password" required /></label>{error && <p className="auth-error">{error}</p>}<button className="primary-button auth-submit" disabled={loading}>{loading ? 'Signing in…' : 'Sign in'} <span>→</span></button></form><p className="auth-note">Accounts are created by the Inkstructs admin team.</p></div></main>
}
