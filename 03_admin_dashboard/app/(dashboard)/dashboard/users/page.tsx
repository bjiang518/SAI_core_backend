'use client'

import React from 'react'
import { Card, CardContent, CardDescription, CardHeader, CardTitle } from '@/components/ui/card'
import { Badge } from '@/components/ui/badge'
import { formatDate } from '@/lib/utils'

export default function UsersPage() {
  // TODO: Replace with real data from API
  const mockUsers = [
    {
      id: '1',
      name: 'Alice Johnson',
      email: 'alice@example.com',
      joinDate: '2026-01-15',
      lastActive: '2026-02-11',
      subscriptionStatus: 'active' as const,
      totalSessions: 45,
    },
    {
      id: '2',
      name: 'Bob Smith',
      email: 'bob@example.com',
      joinDate: '2026-01-20',
      lastActive: '2026-02-10',
      subscriptionStatus: 'trial' as const,
      totalSessions: 12,
    },
    {
      id: '3',
      name: 'Carol Williams',
      email: 'carol@example.com',
      joinDate: '2026-02-01',
      lastActive: '2026-02-09',
      subscriptionStatus: 'active' as const,
      totalSessions: 28,
    },
  ]

  const getStatusBadge = (status: string) => {
    switch (status) {
      case 'active':
        return <Badge variant="success">Active</Badge>
      case 'trial':
        return <Badge variant="warning">Trial</Badge>
      case 'inactive':
        return <Badge variant="error">Inactive</Badge>
      default:
        return <Badge>{status}</Badge>
    }
  }

  return (
    <div className="space-y-6">
      {/* Page Header */}
      <div>
        <h1 className="text-3xl font-bold tracking-tight">Users</h1>
        <p className="text-muted-foreground mt-2">
          Manage and view all registered users
        </p>
      </div>

      {/* Stats Cards */}
      <div className="grid gap-4 md:grid-cols-3">
        <Card>
          <CardHeader className="pb-3">
            <CardTitle className="text-sm font-medium">Total Users</CardTitle>
          </CardHeader>
          <CardContent>
            <div className="text-2xl font-bold">1,247</div>
            <p className="text-xs text-muted-foreground">+8.5% from last week</p>
          </CardContent>
        </Card>
        <Card>
          <CardHeader className="pb-3">
            <CardTitle className="text-sm font-medium">Active This Week</CardTitle>
          </CardHeader>
          <CardContent>
            <div className="text-2xl font-bold">892</div>
            <p className="text-xs text-muted-foreground">71.5% of total</p>
          </CardContent>
        </Card>
        <Card>
          <CardHeader className="pb-3">
            <CardTitle className="text-sm font-medium">New This Month</CardTitle>
          </CardHeader>
          <CardContent>
            <div className="text-2xl font-bold">156</div>
            <p className="text-xs text-muted-foreground">+12% growth</p>
          </CardContent>
        </Card>
      </div>

      {/* Users Table */}
      <Card>
        <CardHeader>
          <CardTitle>All Users</CardTitle>
          <CardDescription>
            A list of all registered users with their status and activity
          </CardDescription>
        </CardHeader>
        <CardContent>
          <div className="overflow-x-auto">
            <table className="w-full">
              <thead>
                <tr className="border-b text-left text-sm font-medium text-muted-foreground">
                  <th className="pb-3">Name</th>
                  <th className="pb-3">Email</th>
                  <th className="pb-3">Status</th>
                  <th className="pb-3">Joined</th>
                  <th className="pb-3">Last Active</th>
                  <th className="pb-3">Sessions</th>
                </tr>
              </thead>
              <tbody>
                {mockUsers.map((user) => (
                  <tr key={user.id} className="border-b last:border-0">
                    <td className="py-3 font-medium">{user.name}</td>
                    <td className="py-3 text-sm text-muted-foreground">{user.email}</td>
                    <td className="py-3">{getStatusBadge(user.subscriptionStatus)}</td>
                    <td className="py-3 text-sm">{formatDate(user.joinDate)}</td>
                    <td className="py-3 text-sm">{formatDate(user.lastActive)}</td>
                    <td className="py-3 text-sm">{user.totalSessions}</td>
                  </tr>
                ))}
              </tbody>
            </table>
          </div>
          <div className="mt-4 text-sm text-muted-foreground">
            Showing 3 of 1,247 users (mock data)
          </div>
        </CardContent>
      </Card>
    </div>
  )
}
