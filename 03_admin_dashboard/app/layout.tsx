import type { Metadata } from 'next'
import './globals.css'

export const metadata: Metadata = {
  title: 'StudyAI Admin Dashboard',
  description: 'Admin dashboard for managing StudyAI platform',
}

export default function RootLayout({
  children,
}: {
  children: React.ReactNode
}) {
  return (
    <html lang="en">
      <body className="font-sans">{children}</body>
    </html>
  )
}
