import type { Metadata } from 'next'
import './globals.css'

export const metadata: Metadata = {
  title: 'StudyAgent Admin Dashboard',
  description: 'Admin dashboard for managing StudyAgent platform',
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
