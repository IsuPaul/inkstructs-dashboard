import type { Metadata } from 'next'
import './globals.css'

export const metadata: Metadata = { title: 'Inkstructs — Student Dashboard', description: 'Learn practical skills with Inkstructs.' }
export default function RootLayout({ children }: Readonly<{ children: React.ReactNode }>) { return <html lang="en"><body>{children}</body></html> }
