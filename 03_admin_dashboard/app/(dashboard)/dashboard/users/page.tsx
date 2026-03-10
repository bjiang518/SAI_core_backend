'use client'

import React, { useEffect, useState, useCallback, useRef } from 'react'
import { Card, CardContent, CardDescription, CardHeader, CardTitle } from '@/components/ui/card'
import { Badge } from '@/components/ui/badge'
import { AlertCircle, Search, X } from 'lucide-react'
import { formatDate } from '@/lib/utils'

interface User {
  id: string
  name: string
  email: string
  join_date: string
  last_active: string | null
  subscriptionStatus: string
  total_sessions: number
}

interface Pagination {
  page: number
  limit: number
  total: number
  totalPages: number
}

export default function UsersPage() {
  const [users, setUsers] = useState<User[]>([])
  const [pagination, setPagination] = useState<Pagination>({ page: 1, total: 0, totalPages: 0, limit: 50 })
  const [loading, setLoading] = useState(true)
  const [error, setError] = useState<string | null>(null)
  const [search, setSearch] = useState('')
  const [debouncedSearch, setDebouncedSearch] = useState('')
  const debounceTimer = useRef<ReturnType<typeof setTimeout> | null>(null)

  const fetchUsers = useCallback(async (page = 1, searchQuery = debouncedSearch) => {
    setLoading(true)
    try {
      const apiUrl = process.env.NEXT_PUBLIC_API_URL || 'https://sai-backend-production.up.railway.app'
      const token = localStorage.getItem('admin_token')
      const params = new URLSearchParams({
        page: String(page),
        limit: '50',
        ...(searchQuery ? { search: searchQuery } : {}),
      })

      const response = await fetch(`${apiUrl}/api/admin/users/list?${params}`, {
        headers: { Authorization: `Bearer ${token}` },
      })

      const data = await response.json().catch(() => null)

      if (!response.ok) {
        const msg = data?.error || data?.message || `HTTP ${response.status} ${response.statusText}`
        setError(`API error: ${msg}`)
        return
      }

      if (data?.success) {
        setUsers(data.data)
        setPagination(data.pagination)
        setError(null)
      } else {
        setError(data?.error || 'Unexpected response from backend')
      }
    } catch (err: unknown) {
      const msg = err instanceof Error ? err.message : String(err)
      setError(`Network error: ${msg}`)
    } finally {
      setLoading(false)
    }
  }, [debouncedSearch])

  // Initial load
  useEffect(() => {
    fetchUsers(1, '')
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [])

  // Re-fetch when debounced search changes
  useEffect(() => {
    fetchUsers(1, debouncedSearch)
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [debouncedSearch])

  const handleSearchChange = (value: string) => {
    setSearch(value)
    if (debounceTimer.current) clearTimeout(debounceTimer.current)
    debounceTimer.current = setTimeout(() => setDebouncedSearch(value), 400)
  }

  const clearSearch = () => {
    setSearch('')
    setDebouncedSearch('')
  }

  const getStatusBadge = (status: string) => {
    switch (status.toLowerCase()) {
      case 'active': return <Badge variant="success">Active</Badge>
      case 'trial': return <Badge variant="warning">Trial</Badge>
      case 'inactive': return <Badge variant="error">Inactive</Badge>
      default: return <Badge>{status}</Badge>
    }
  }

  return (
    <div className="space-y-6">
      {/* Header */}
      <div>
        <h1 className="text-3xl font-bold tracking-tight">Users</h1>
        <p className="text-muted-foreground mt-1">Manage and view all registered users</p>
      </div>

      {/* Stats + Search row */}
      <div className="flex flex-col sm:flex-row sm:items-center justify-between gap-4">
        <div className="flex gap-4 text-sm">
          <span className="font-semibold text-2xl">{pagination.total.toLocaleString()}</span>
          <span className="text-muted-foreground self-end pb-0.5">total users</span>
        </div>
        {/* Search input */}
        <div className="relative w-full sm:w-72">
          <Search className="absolute left-3 top-1/2 -translate-y-1/2 h-4 w-4 text-muted-foreground pointer-events-none" />
          <input
            type="text"
            placeholder="Search by name or email…"
            value={search}
            onChange={(e) => handleSearchChange(e.target.value)}
            className="w-full pl-9 pr-8 py-2 text-sm rounded-lg border border-input bg-background focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-ring"
          />
          {search && (
            <button
              onClick={clearSearch}
              className="absolute right-2 top-1/2 -translate-y-1/2 text-muted-foreground hover:text-foreground"
            >
              <X className="h-4 w-4" />
            </button>
          )}
        </div>
      </div>

      {error && (
        <div className="flex items-center gap-2 rounded-lg border border-red-200 bg-red-50 p-4 text-sm text-red-800">
          <AlertCircle className="h-4 w-4 shrink-0" />
          {error}
        </div>
      )}

      {/* Users Table */}
      <Card>
        <CardHeader>
          <CardTitle>All Users</CardTitle>
          <CardDescription>
            {debouncedSearch
              ? `${pagination.total} result${pagination.total !== 1 ? 's' : ''} for "${debouncedSearch}"`
              : `${pagination.total.toLocaleString()} registered users`}
          </CardDescription>
        </CardHeader>
        <CardContent>
          {loading ? (
            <div className="flex items-center justify-center py-12">
              <div className="animate-spin rounded-full h-8 w-8 border-b-2 border-primary" />
            </div>
          ) : users.length === 0 ? (
            <div className="text-center py-10 text-muted-foreground">
              {debouncedSearch ? `No users match "${debouncedSearch}"` : 'No users found'}
            </div>
          ) : (
            <>
              <div className="overflow-x-auto">
                <table className="w-full text-sm">
                  <thead>
                    <tr className="border-b text-left text-xs font-medium text-muted-foreground">
                      <th className="pb-2 pr-4">Name</th>
                      <th className="pb-2 pr-4">Email</th>
                      <th className="pb-2 pr-4">Status</th>
                      <th className="pb-2 pr-4">Joined</th>
                      <th className="pb-2 pr-4">Last Active</th>
                      <th className="pb-2">Sessions</th>
                    </tr>
                  </thead>
                  <tbody>
                    {users.map((user) => (
                      <tr key={user.id} className="border-b last:border-0 hover:bg-gray-50">
                        <td className="py-3 pr-4 font-medium">{user.name || '—'}</td>
                        <td className="py-3 pr-4 text-muted-foreground">{user.email}</td>
                        <td className="py-3 pr-4">{getStatusBadge(user.subscriptionStatus)}</td>
                        <td className="py-3 pr-4">{formatDate(user.join_date)}</td>
                        <td className="py-3 pr-4">
                          {user.last_active ? formatDate(user.last_active) : 'Never'}
                        </td>
                        <td className="py-3">{user.total_sessions}</td>
                      </tr>
                    ))}
                  </tbody>
                </table>
              </div>

              {/* Pagination */}
              <div className="mt-4 flex items-center justify-between text-sm text-muted-foreground">
                <div>
                  Showing {users.length} of {pagination.total.toLocaleString()} users
                </div>
                <div className="flex items-center gap-2">
                  <button
                    onClick={() => fetchUsers(pagination.page - 1)}
                    disabled={pagination.page === 1}
                    className="px-3 py-1 border rounded disabled:opacity-40 disabled:cursor-not-allowed hover:bg-gray-50"
                  >
                    Previous
                  </button>
                  <span className="text-xs">
                    {pagination.page} / {pagination.totalPages}
                  </span>
                  <button
                    onClick={() => fetchUsers(pagination.page + 1)}
                    disabled={pagination.page >= pagination.totalPages}
                    className="px-3 py-1 border rounded disabled:opacity-40 disabled:cursor-not-allowed hover:bg-gray-50"
                  >
                    Next
                  </button>
                </div>
              </div>
            </>
          )}
        </CardContent>
      </Card>
    </div>
  )
}
