"use client";

import {
  LineChart,
  Line,
  XAxis,
  YAxis,
  CartesianGrid,
  Tooltip,
  ReferenceLine,
  ResponsiveContainer,
  Legend,
} from "recharts";
import { formatDateShort } from "@/lib/utils";

interface TrendChartProps {
  data: Array<Record<string, unknown>>;
  dataKey: string;
  label: string;
  color: string;
  baselineValue?: number | null;
}

export function TrendChart({
  data,
  dataKey,
  label,
  color,
  baselineValue,
}: TrendChartProps) {
  if (data.length === 0) {
    return (
      <div className="flex h-48 items-center justify-center text-sm text-gray-400">
        No data to display yet
      </div>
    );
  }

  const chartData = data.map((d) => ({
    ...d,
    dateLabel: formatDateShort(d.date as string),
  }));

  return (
    <div className="h-48 w-full">
      <ResponsiveContainer width="100%" height="100%">
        <LineChart data={chartData} margin={{ top: 5, right: 5, left: -10, bottom: 5 }}>
          <CartesianGrid strokeDasharray="3 3" stroke="#E2E8F0" />
          <XAxis
            dataKey="dateLabel"
            tick={{ fontSize: 11, fill: "#94A3B8" }}
            tickLine={false}
          />
          <YAxis
            tick={{ fontSize: 11, fill: "#94A3B8" }}
            tickLine={false}
            axisLine={false}
          />
          <Tooltip
            contentStyle={{
              fontSize: 12,
              borderRadius: 8,
              border: "1px solid #E2E8F0",
            }}
          />
          {baselineValue !== null && baselineValue !== undefined && (
            <ReferenceLine
              y={baselineValue}
              stroke="#94A3B8"
              strokeDasharray="5 5"
              label={{
                value: "Baseline",
                position: "right",
                fill: "#94A3B8",
                fontSize: 10,
              }}
            />
          )}
          <Line
            type="monotone"
            dataKey={dataKey}
            stroke={color}
            strokeWidth={2}
            dot={{ fill: color, r: 3 }}
            activeDot={{ r: 5 }}
            name={label}
            connectNulls
          />
        </LineChart>
      </ResponsiveContainer>
    </div>
  );
}
