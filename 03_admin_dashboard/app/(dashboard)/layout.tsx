'use client'

import { Sidebar } from '@/components/dashboard/Sidebar'
import { useAuth } from '@/hooks/useAuth'

export default function DashboardLayout({
  children,
}: {
  children: React.ReactNode
}) {
  // Protect all dashboard routes - redirect to login if not authenticated
  useAuth()

  return (
    <div className="flex h-screen overflow-hidden">
      <Sidebar />
      <main className="flex-1 overflow-y-auto bg-gray-50">
        <div className="container mx-auto p-8">{children}</div>
      </main>
    </div>
  )
}
