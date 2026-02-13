'use client'

import { useEffect } from 'react'
import { useRouter } from 'next/navigation'

export function useAuth() {
  const router = useRouter()

  useEffect(() => {
    const token = localStorage.getItem('admin_token')
    if (!token) {
      router.push('/login')
    }
  }, [router])

  const logout = () => {
    localStorage.removeItem('admin_token')
    router.push('/login')
  }

  return { logout }
}
