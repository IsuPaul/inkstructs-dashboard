import Link from 'next/link'

export default function PortalPage({ title, description }: { title: string; description: string }) {
  return <main className="portal-page"><div className="portal-top"><Link href="/" className="brand"><div className="brand-mark">i</div><span>inkstructs</span></Link><Link href="/" className="back-link">← Back to dashboard</Link></div><section className="portal-card"><p className="eyebrow">STUDENT PORTAL</p><h1>{title}</h1><p className="muted">{description}</p><div className="coming-card">This area is connected and ready for its live Supabase data. The next implementation will populate it with your records.</div></section></main>
}
