'use client'

import React, { useState, useEffect } from 'react'
import Link from 'next/link'
import { usePathname } from 'next/navigation'
import { cn } from '@/lib/utils'
import { useAuth } from '@/hooks/useAuth'
import {
  LayoutDashboard,
  Users,
  Activity,
  FileText,
  LogOut,
  BarChart2,
  Lightbulb,
  Tag,
  Menu,
  X,
  TrendingUp,
  Filter,
  AlertTriangle,
  ListChecks,
  Mail,
} from 'lucide-react'

const navigation = [
  { name: 'Overview',       href: '/dashboard',              icon: LayoutDashboard },
  { name: 'Users',          href: '/dashboard/users',        icon: Users },
  { name: 'User Actions',   href: '/dashboard/user-actions', icon: ListChecks },
  { name: 'Analytics',      href: '/dashboard/analytics',    icon: BarChart2 },
  { name: 'Retention',      href: '/dashboard/retention',    icon: TrendingUp },
  { name: 'Funnel',         href: '/dashboard/funnel',       icon: Filter },
  { name: 'Churn Risk',     href: '/dashboard/churn',        icon: AlertTriangle },
  { name: 'Insights',       href: '/dashboard/insights',     icon: Lightbulb },
  { name: 'System Health',  href: '/dashboard/system',       icon: Activity },
  { name: 'Reports',        href: '/dashboard/reports',      icon: FileText },
  { name: 'Promo Codes',    href: '/dashboard/promos',       icon: Tag },
  { name: 'Re-engagement',  href: '/dashboard/reengagement', icon: Mail },
]

export function Sidebar() {
  const pathname = usePathname()
  const { logout } = useAuth()
  const [mobileOpen, setMobileOpen] = useState(false)

  // Close mobile menu on route change
  useEffect(() => {
    setMobileOpen(false)
  }, [pathname])

  const sidebarContent = (
    <>
      {/* Logo */}
      <div className="flex h-16 items-center justify-between border-b border-gray-800 px-4">
        <div className="text-center flex-1">
          <h1 className="text-lg font-bold">StudyAgent Admin</h1>
          <p className="text-xs text-gray-400">Dashboard</p>
        </div>
        {/* Close button — mobile only */}
        <button
          className="lg:hidden text-gray-400 hover:text-white p-1"
          onClick={() => setMobileOpen(false)}
        >
          <X className="h-5 w-5" />
        </button>
      </div>

      {/* Navigation */}
      <nav className="flex-1 space-y-1 p-4">
        {navigation.map((item) => {
          const isActive = pathname === item.href
          return (
            <Link
              key={item.name}
              href={item.href}
              className={cn(
                'flex items-center gap-3 rounded-lg px-3 py-2 text-sm font-medium transition-colors',
                isActive
                  ? 'bg-gray-800 text-white'
                  : 'text-gray-400 hover:bg-gray-800 hover:text-white'
              )}
            >
              <item.icon className="h-4 w-4" />
              {item.name}
            </Link>
          )
        })}
      </nav>

      {/* Footer */}
      <div className="border-t border-gray-800 p-4">
        <button
          className="flex w-full items-center gap-3 rounded-lg px-3 py-2 text-sm font-medium text-gray-400 transition-colors hover:bg-gray-800 hover:text-white"
          onClick={logout}
        >
          <LogOut className="h-4 w-4" />
          Logout
        </button>
      </div>
    </>
  )

  return (
    <>
      {/* Mobile hamburger button — fixed top-left, visible only on small screens */}
      <button
        className="lg:hidden fixed top-3 left-3 z-50 rounded-lg bg-gray-900 p-2 text-white shadow-lg"
        onClick={() => setMobileOpen(true)}
      >
        <Menu className="h-5 w-5" />
      </button>

      {/* Mobile overlay */}
      {mobileOpen && (
        <div
          className="lg:hidden fixed inset-0 z-40 bg-black/50"
          onClick={() => setMobileOpen(false)}
        />
      )}

      {/* Mobile slide-in sidebar */}
      <div
        className={cn(
          'lg:hidden fixed inset-y-0 left-0 z-50 flex w-64 flex-col bg-gray-900 text-white transition-transform duration-200 ease-in-out',
          mobileOpen ? 'translate-x-0' : '-translate-x-full'
        )}
      >
        {sidebarContent}
      </div>

      {/* Desktop sidebar — always visible */}
      <div className="hidden lg:flex h-screen w-64 flex-col bg-gray-900 text-white shrink-0">
        {sidebarContent}
      </div>
    </>
  )
}
