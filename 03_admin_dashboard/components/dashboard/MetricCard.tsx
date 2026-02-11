import React from 'react'
import { Card, CardContent, CardHeader, CardTitle } from '@/components/ui/card'
import { Badge } from '@/components/ui/badge'
import { getTrendIcon } from '@/lib/utils'
import { TrendDirection } from '@/types'
import { LucideIcon } from 'lucide-react'

interface MetricCardProps {
  title: string
  value: string | number
  change?: number
  trend?: TrendDirection
  icon?: LucideIcon
  description?: string
  badge?: {
    text: string
    variant?: 'success' | 'warning' | 'error' | 'default'
  }
}

export function MetricCard({
  title,
  value,
  change,
  trend,
  icon: Icon,
  description,
  badge,
}: MetricCardProps) {
  return (
    <Card>
      <CardHeader className="flex flex-row items-center justify-between space-y-0 pb-2">
        <CardTitle className="text-sm font-medium">{title}</CardTitle>
        {Icon && <Icon className="h-4 w-4 text-muted-foreground" />}
      </CardHeader>
      <CardContent>
        <div className="text-2xl font-bold">{value}</div>
        {(change !== undefined || description || badge) && (
          <div className="flex items-center gap-2 mt-1">
            {change !== undefined && trend && (
              <p className="text-xs text-muted-foreground">
                <span
                  className={
                    trend === 'up'
                      ? 'text-green-600'
                      : trend === 'down'
                      ? 'text-red-600'
                      : 'text-gray-600'
                  }
                >
                  {getTrendIcon(trend)} {Math.abs(change)}%
                </span>
                {' from last week'}
              </p>
            )}
            {description && !change && (
              <p className="text-xs text-muted-foreground">{description}</p>
            )}
            {badge && (
              <Badge variant={badge.variant || 'default'}>{badge.text}</Badge>
            )}
          </div>
        )}
      </CardContent>
    </Card>
  )
}
