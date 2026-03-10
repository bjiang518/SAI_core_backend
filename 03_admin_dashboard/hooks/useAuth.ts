'use client'

import { useEffect } from 'react'
import { useRouter } from 'next/navigation'

export function useAuth() {
  const router = useRouter()

  useEffect(() => {
    const token = localStorage.getItem('admin_token')
    if (!token) {
      router.push('/login')
      return
    }
    // Check expiry from JWT payload (client-side, no signature verification)
    try {
      const payload = JSON.parse(atob(token.split('.')[1]))
      if (payload.exp && payload.exp * 1000 < Date.now()) {
        localStorage.removeItem('admin_token')
        router.push('/login')
      }
    } catch {
      localStorage.removeItem('admin_token')
      router.push('/login')
    }
  }, [router])

  const logout = () => {
    localStorage.removeItem('admin_token')
    router.push('/login')
  }

  return { logout }
}
