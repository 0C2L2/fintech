'use client';

import { useEffect, useState } from 'react';
import { useRouter } from 'next/navigation';
import { useAuth } from '@/lib/auth-context';
import { api } from '@/lib/api';
import { DashboardLayout } from '@/components/DashboardLayout';
import { Card } from '@/components/ui/card';
import {
  AlertCircle, TrendingUp, Users, DollarSign, FileText,
  Brain, ShieldAlert, Lightbulb, BarChart2, Activity,
  Target, Zap, Info, ChevronRight, AlertTriangle
} from 'lucide-react';
import {
  PieChart, Pie, Cell, ResponsiveContainer,
  BarChart, Bar, XAxis, YAxis, CartesianGrid, Tooltip, Legend,
} from 'recharts';
import { User, AdminOverview } from '@/types';

const SEGMENT_COLORS = ['#3b82f6', '#10b981', '#f59e0b', '#ef4444', '#8b5cf6'];

// Thresholds that match rules.R
const FINANCIAL_RULES = [
  { category: 'Rent', limit: 40, description: 'Housing costs above 40% strain all other spending' },
  { category: 'Food', limit: 30, description: 'Food over 30% often signals lack of meal planning' },
  { category: 'Transport', limit: 25, description: 'Transport over 25% suggests commute or vehicle costs are excessive' },
  { category: 'Entertainment', limit: 20, description: 'Entertainment above 20% is flagged as discretionary overspend' },
  { category: 'Education', limit: 15, description: 'Education reference — not usually flagged as overspend' },
  { category: 'Discretionary (total)', limit: 40, description: 'All non-essential spending combined must stay under 40%' },
];

const SEGMENTS = [
  {
    label: 'Balanced Budgeter',
    color: '#3b82f6',
    icon: '⚖️',
    description: 'Default segment. User has moderate savings rate and no dominant spending category.',
    conditions: 'Savings rate ≤ 25%, Rent ≤ 40%, Entertainment ≤ 20%',
  },
  {
    label: 'High Saver',
    color: '#10b981',
    icon: '💰',
    description: 'User consistently saves more than 25% of income. Gets "invest your savings" advice.',
    conditions: 'Savings rate > 25% of income',
  },
  {
    label: 'Rent-Burdened User',
    color: '#f59e0b',
    icon: '🏠',
    description: 'Housing costs dominate the budget. Receives advice to explore shared housing.',
    conditions: 'Rent > 40% of total expenses',
  },
  {
    label: 'Entertainment-Heavy Spender',
    color: '#ef4444',
    icon: '🎬',
    description: 'Leisure and entertainment dominate non-essential spending. Gets budgeting advice.',
    conditions: 'Entertainment > 20% of total expenses',
  },
];

const SCORE_RULES = [
  { label: 'Start score', points: 100, color: '#10b981', type: 'base' },
  { label: '−25 per critical flag', points: -25, color: '#ef4444', type: 'deduct', example: 'Spending exceeds income' },
  { label: '−15 per high flag', points: -15, color: '#f87171', type: 'deduct', example: 'Low savings rate, High rent burden' },
  { label: '−10 per medium flag', points: -10, color: '#fbbf24', type: 'deduct', example: 'High entertainment/food/discretionary' },
  { label: '−5 per low flag', points: -5, color: '#d1d5db', type: 'deduct', example: 'High transport costs' },
  { label: '+10 bonus if savings > 20%', points: 10, color: '#34d399', type: 'bonus', example: '' },
  { label: '+5 bonus if savings > 30%', points: 5, color: '#6ee7b7', type: 'bonus', example: '' },
];

interface OverspendingIssue { issue: string; count: number; }
interface Segment { segment: string; count: number; }

export default function AdminDashboardPage() {
  const { user } = useAuth();
  const router = useRouter();
  const [overview, setOverview] = useState<AdminOverview | null>(null);
  const [segments, setSegments] = useState<Segment[]>([]);
  const [overspending, setOverspending] = useState<OverspendingIssue[]>([]);
  const [users, setUsers] = useState<User[]>([]);
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState<string | null>(null);
  const [mounted, setMounted] = useState(false);

  useEffect(() => { setMounted(true); }, []);

  useEffect(() => {
    if (!user) return;
    if (user.role !== 'admin') { router.push('/dashboard'); return; }

    const load = async () => {
      try {
        const [ov, seg, over, us] = await Promise.all([
          api.admin.overview(),
          api.admin.segments(),
          api.admin.overspending(),
          api.admin.users(),
        ]);
        if (ov.success) setOverview(ov.data);
        if (seg.success) setSegments(seg.data);
        if (over.success) setOverspending(over.data);
        if (us.success) setUsers(us.data);
      } catch (e: any) {
        setError(e.message || 'Failed to load dashboard data');
      } finally {
        setLoading(false);
      }
    };
    load();
  }, [user, router]);

  if (loading) {
    return (
      <DashboardLayout>
        <div className="flex flex-col items-center justify-center min-h-[60vh] gap-4">
          <div className="w-12 h-12 border-4 border-blue-500 border-t-transparent rounded-full animate-spin" />
          <p className="text-slate-500 font-medium">Loading admin dashboard…</p>
        </div>
      </DashboardLayout>
    );
  }

  const totalSegmented = segments.reduce((s, x) => s + x.count, 0);
  const avgSpend = users.length > 0 ? (overview?.total_expense_amount || 0) / users.length : 0;

  return (
    <DashboardLayout>
      <div className="space-y-10 pb-12">

        {/* ===== HEADER ===== */}
        <div className="flex items-start justify-between">
          <div>
            <h1 className="text-3xl font-bold text-slate-900 tracking-tight">Admin Dashboard</h1>
            <p className="text-slate-500 mt-1">System-wide analytics · How each algorithm works · Live data</p>
          </div>
          <span className="inline-flex items-center gap-1.5 px-3 py-1.5 bg-blue-100 text-blue-700 rounded-full text-xs font-semibold">
            <Brain className="h-3.5 w-3.5" /> ML-Powered
          </span>
        </div>

        {error && (
          <Card className="bg-red-50 border-red-200 p-4 flex items-start gap-3">
            <AlertCircle className="text-red-600 mt-0.5 shrink-0" size={18} />
            <p className="text-red-700 text-sm">{error}</p>
          </Card>
        )}

        {/* ===== SECTION 1: LIVE METRICS ===== */}
        <section>
          <SectionHeader icon={<Activity className="h-5 w-5" />} title="Platform Metrics" subtitle="Live totals from the database" />
          <div className="grid grid-cols-2 lg:grid-cols-4 gap-4 mt-4">
            <MetricCard
              icon={<Users className="h-5 w-5 text-blue-600" />}
              label="Registered Users"
              value={overview?.total_users?.toLocaleString() || '0'}
              bg="bg-blue-50"
              note="Excludes admin accounts"
            />
            <MetricCard
              icon={<BarChart2 className="h-5 w-5 text-emerald-600" />}
              label="Expense Entries"
              value={overview?.total_expenses?.toLocaleString() || '0'}
              bg="bg-emerald-50"
              note="All user expense records"
            />
            <MetricCard
              icon={<DollarSign className="h-5 w-5 text-amber-600" />}
              label="Total Tracked Spending"
              value={`$${(overview?.total_expense_amount || 0).toLocaleString('en-US', { maximumFractionDigits: 0 })}`}
              bg="bg-amber-50"
              note={`Avg $${avgSpend.toLocaleString('en-US', { maximumFractionDigits: 0 })} / user`}
            />
            <MetricCard
              icon={<FileText className="h-5 w-5 text-purple-600" />}
              label="Reports Generated"
              value={overview?.total_reports?.toLocaleString() || '0'}
              bg="bg-purple-50"
              note="Excel downloads by users"
            />
          </div>
          {overview?.latest_activity && (
            <div className="mt-3 flex items-center gap-2 text-sm text-slate-500 bg-slate-50 border border-slate-200 rounded-lg px-4 py-2.5">
              <Zap className="h-4 w-4 text-amber-500 shrink-0" />
              <span>Latest active month: <strong className="text-slate-700">{overview.latest_activity.expense_month}</strong> — {overview.latest_activity.count.toLocaleString()} expenses totalling <strong className="text-slate-700">${overview.latest_activity.total.toLocaleString('en-US', { maximumFractionDigits: 0 })}</strong></span>
            </div>
          )}
        </section>

        {/* ===== SECTION 2: USER SEGMENTATION ===== */}
        <section>
          <SectionHeader
            icon={<Brain className="h-5 w-5" />}
            title="User Segmentation — How it works"
            subtitle="K-Means clustering + rule-based fallback assigns every user to one of 4 financial segments"
          />

          <div className="mt-4 grid grid-cols-1 lg:grid-cols-2 gap-6">
            {/* Algorithm explanation */}
            <Card className="p-6 space-y-5">
              <h3 className="font-semibold text-slate-800 flex items-center gap-2">
                <span className="w-6 h-6 rounded-full bg-blue-100 text-blue-700 text-xs font-bold flex items-center justify-center">1</span>
                Feature Extraction (features.R)
              </h3>
              <p className="text-sm text-slate-600 leading-relaxed">
                For each user-month, the system builds a <strong>feature vector</strong> from their expense records. It extracts the share of spending going to each category (Rent, Food, Transport, Entertainment, Education), calculates actual savings rate, expense growth vs. last month, and 3-month rolling averages.
              </p>
              <div className="bg-slate-50 rounded-lg p-3 text-xs font-mono text-slate-600 space-y-1">
                <div>savings_rate = (income − total_expense) / income</div>
                <div>rent_share = rent_spending / total_expenses</div>
                <div>entertainment_share = entertainment / total_expenses</div>
                <div>expense_growth = (this_month − last_month) / last_month</div>
              </div>

              <h3 className="font-semibold text-slate-800 flex items-center gap-2 pt-2">
                <span className="w-6 h-6 rounded-full bg-blue-100 text-blue-700 text-xs font-bold flex items-center justify-center">2</span>
                K-Means Model (clustering.R)
              </h3>
              <p className="text-sm text-slate-600 leading-relaxed">
                If a trained K-Means model (<code className="bg-slate-100 px-1 rounded">kmeans_model.rds</code>) exists, the feature vector is scaled using saved scaler parameters, then the nearest cluster centroid is found using Euclidean distance. The cluster ID maps to one of the 4 labels below.
              </p>

              <h3 className="font-semibold text-slate-800 flex items-center gap-2 pt-2">
                <span className="w-6 h-6 rounded-full bg-purple-100 text-purple-700 text-xs font-bold flex items-center justify-center">↩</span>
                Rule-Based Fallback
              </h3>
              <p className="text-sm text-slate-600 leading-relaxed">
                When no trained model exists, the system uses deterministic rules in priority order: High Saver → Rent-Burdened → Entertainment-Heavy → Balanced Budgeter.
              </p>
            </Card>

            {/* Live pie chart + segment distribution */}
            <Card className="p-6">
              <div className="flex items-center justify-between mb-4">
                <h3 className="font-semibold text-slate-800">Live Segment Distribution</h3>
                <span className="text-xs text-slate-400">{totalSegmented} cases analysed</span>
              </div>
              {segments.length > 0 && mounted ? (
                <ResponsiveContainer width="100%" height={220}>
                  <PieChart>
                    <Pie data={segments} dataKey="count" nameKey="segment" cx="50%" cy="50%" outerRadius={85} label={({ name, value }) => `${name}: ${value}`}>
                      {segments.map((_, i) => <Cell key={i} fill={SEGMENT_COLORS[i % SEGMENT_COLORS.length]} />)}
                    </Pie>
                    <Tooltip formatter={(v, n) => [v, n]} />
                    <Legend formatter={(value) => <span className="text-xs">{value}</span>} />
                  </PieChart>
                </ResponsiveContainer>
              ) : (
                <div className="h-[220px] flex items-center justify-center text-slate-400 text-sm">
                  {mounted ? 'No segment data yet — run analysis first.' : <div className="h-[220px] animate-pulse bg-gray-100 rounded-lg w-full" />}
                </div>
              )}
            </Card>
          </div>

          {/* 4 segment cards */}
          <div className="grid grid-cols-1 sm:grid-cols-2 lg:grid-cols-4 gap-4 mt-4">
            {SEGMENTS.map((seg) => {
              const live = segments.find(s => s.segment === seg.label);
              const pct = totalSegmented > 0 && live ? Math.round(live.count / totalSegmented * 100) : 0;
              return (
                <Card key={seg.label} className="p-4 border-l-4" style={{ borderLeftColor: seg.color }}>
                  <div className="flex items-center gap-2 mb-2">
                    <span className="text-xl">{seg.icon}</span>
                    <span className="font-semibold text-slate-800 text-sm">{seg.label}</span>
                  </div>
                  <p className="text-xs text-slate-500 leading-relaxed mb-3">{seg.description}</p>
                  <div className="bg-slate-50 rounded p-2 text-xs text-slate-600 font-mono mb-3">
                    {seg.conditions}
                  </div>
                  <div className="flex items-center justify-between">
                    <span className="text-xs text-slate-400">Current cases</span>
                    <span className="font-bold text-base" style={{ color: seg.color }}>
                      {live?.count ?? 0} <span className="text-xs font-normal text-slate-400">({pct}%)</span>
                    </span>
                  </div>
                  {live && (
                    <div className="mt-2 h-1.5 bg-slate-100 rounded-full overflow-hidden">
                      <div className="h-full rounded-full" style={{ width: `${pct}%`, backgroundColor: seg.color }} />
                    </div>
                  )}
                </Card>
              );
            })}
          </div>
        </section>

        {/* ===== SECTION 3: OVERSPENDING WARNINGS ===== */}
        <section>
          <SectionHeader
            icon={<ShieldAlert className="h-5 w-5" />}
            title="Overspending Warnings — How they work"
            subtitle="9 rule-based checks run on every analysis. Each produces a flag with severity: critical / high / medium / low"
          />

          <div className="mt-4 grid grid-cols-1 lg:grid-cols-2 gap-6">
            {/* Rules table */}
            <Card className="p-6">
              <h3 className="font-semibold text-slate-800 mb-4 flex items-center gap-2">
                <Target className="h-4 w-4 text-slate-500" />
                Category Spending Rules (rules.R)
              </h3>
              <div className="space-y-2">
                {FINANCIAL_RULES.map((rule) => (
                  <div key={rule.category} className="flex items-start gap-3 p-3 bg-slate-50 rounded-lg">
                    <div className="flex-1">
                      <div className="flex items-center justify-between">
                        <span className="text-sm font-semibold text-slate-800">{rule.category}</span>
                        <span className="text-sm font-bold text-red-500">max {rule.limit}%</span>
                      </div>
                      <p className="text-xs text-slate-500 mt-0.5">{rule.description}</p>
                    </div>
                  </div>
                ))}
              </div>
              <div className="mt-4 space-y-2">
                <div className="p-3 bg-red-50 border border-red-100 rounded-lg">
                  <p className="text-xs font-semibold text-red-700">Rule: Spending exceeds income</p>
                  <p className="text-xs text-red-600 mt-0.5">When total_expense {'>'} income → <strong>critical</strong> severity. Most severe flag possible.</p>
                </div>
                <div className="p-3 bg-amber-50 border border-amber-100 rounded-lg">
                  <p className="text-xs font-semibold text-amber-700">Rule: Rapid expense growth</p>
                  <p className="text-xs text-amber-600 mt-0.5">If expenses grew {'>'} 20% from last month → <strong>medium</strong> severity.</p>
                </div>
                <div className="p-3 bg-blue-50 border border-blue-100 rounded-lg">
                  <p className="text-xs font-semibold text-blue-700">Rule: Custom budget exceeded</p>
                  <p className="text-xs text-blue-600 mt-0.5">If user set a budget threshold for a category and exceeded it → <strong>high</strong> severity.</p>
                </div>
              </div>
            </Card>

            {/* Live overspending chart */}
            <Card className="p-6">
              <h3 className="font-semibold text-slate-800 mb-1">Most Common Issues Across All Users</h3>
              <p className="text-xs text-slate-400 mb-4">Counted from the last 100 analysis results in the database</p>
              {overspending.length > 0 && mounted ? (
                <ResponsiveContainer width="100%" height={280}>
                  <BarChart data={overspending.slice(0, 7)} layout="vertical" margin={{ left: 10, right: 20 }}>
                    <CartesianGrid strokeDasharray="3 3" horizontal={false} />
                    <XAxis type="number" tick={{ fontSize: 11 }} />
                    <YAxis type="category" dataKey="issue" width={170} tick={{ fontSize: 11 }} />
                    <Tooltip />
                    <Bar dataKey="count" name="Occurrences" fill="#ef4444" radius={[0, 4, 4, 0]} />
                  </BarChart>
                </ResponsiveContainer>
              ) : (
                <div className="h-[280px] flex items-center justify-center text-slate-400 text-sm">
                  {mounted ? 'No overspending data yet.' : <div className="animate-pulse bg-gray-100 rounded-lg w-full h-full" />}
                </div>
              )}
            </Card>
          </div>
        </section>

        {/* ===== SECTION 4: FINANCIAL SCORE ===== */}
        <section>
          <SectionHeader
            icon={<Target className="h-5 w-5" />}
            title="Financial Score — How it's calculated"
            subtitle="A single 0–100 score built from flag severity. Shown on every user's dashboard and analysis page."
          />
          <div className="mt-4 grid grid-cols-1 lg:grid-cols-2 gap-6">
            <Card className="p-6">
              <h3 className="font-semibold text-slate-800 mb-4">Scoring Formula (overspending.R)</h3>
              <div className="space-y-2">
                {SCORE_RULES.map((rule, i) => (
                  <div key={i} className="flex items-center gap-3 p-3 rounded-lg bg-slate-50">
                    <span
                      className="text-sm font-bold w-12 text-center shrink-0 rounded px-1.5 py-0.5"
                      style={{ color: rule.color, backgroundColor: `${rule.color}20` }}
                    >
                      {rule.points > 0 ? `+${rule.points}` : rule.points}
                    </span>
                    <div className="flex-1">
                      <p className="text-sm font-medium text-slate-800">{rule.label}</p>
                      {rule.example && <p className="text-xs text-slate-400 mt-0.5">e.g. {rule.example}</p>}
                    </div>
                  </div>
                ))}
              </div>
              <div className="mt-4 p-3 bg-slate-800 text-slate-100 rounded-lg text-xs font-mono leading-relaxed">
                score = 100 − (flags × deductions) + bonuses<br />
                score = max(0, min(100, score))
              </div>
            </Card>
            <Card className="p-6">
              <h3 className="font-semibold text-slate-800 mb-4">Score Interpretation</h3>
              <div className="space-y-3">
                {[
                  { range: '80–100', label: 'Excellent', color: '#10b981', bg: '#f0fdf4', desc: 'No or minor issues. Green on UI. High Savers typically score here.' },
                  { range: '50–79', label: 'Moderate', color: '#f59e0b', bg: '#fffbeb', desc: 'Some flags detected. Amber on UI. Balanced Budgeters tend to land here.' },
                  { range: '0–49', label: 'Needs attention', color: '#ef4444', bg: '#fef2f2', desc: 'Multiple high/critical flags. Red on UI. Urgent advice is triggered.' },
                ].map(band => (
                  <div key={band.range} className="flex items-start gap-3 p-4 rounded-lg border" style={{ backgroundColor: band.bg, borderColor: `${band.color}40` }}>
                    <span className="text-2xl font-black shrink-0" style={{ color: band.color }}>{band.range}</span>
                    <div>
                      <p className="font-semibold text-slate-800">{band.label}</p>
                      <p className="text-xs text-slate-600 mt-0.5">{band.desc}</p>
                    </div>
                  </div>
                ))}
              </div>
            </Card>
          </div>
        </section>

        {/* ===== SECTION 5: SAVINGS PREDICTION ===== */}
        <section>
          <SectionHeader
            icon={<TrendingUp className="h-5 w-5" />}
            title="Savings Prediction — How it works"
            subtitle="Predicts what the user is likely to save next month using machine learning or linear regression"
          />
          <div className="mt-4 grid grid-cols-1 lg:grid-cols-2 gap-6">
            <Card className="p-6 space-y-5">
              <div>
                <h3 className="font-semibold text-slate-800 mb-2 flex items-center gap-2">
                  <span className="w-6 h-6 rounded-full bg-emerald-100 text-emerald-700 text-xs font-bold flex items-center justify-center">1</span>
                  Random Forest Model (prediction.R)
                </h3>
                <p className="text-sm text-slate-600 leading-relaxed">
                  If <code className="bg-slate-100 px-1 rounded text-xs">rf_savings_model.rds</code> exists, the system feeds 10 features into a trained Random Forest to predict next month's savings. Features include income, total expense, all category shares, savings rate, expense growth, and 3-month rolling average savings.
                </p>
                <div className="mt-3 bg-slate-50 rounded-lg p-3 text-xs font-mono text-slate-600 space-y-1">
                  <div className="text-slate-400">// Input features to RF model:</div>
                  <div>income, total_expense, rent_share, food_share,</div>
                  <div>transport_share, education_share,</div>
                  <div>entertainment_share, savings_rate,</div>
                  <div>expense_growth, avg_savings_last_3m</div>
                </div>
              </div>
              <div>
                <h3 className="font-semibold text-slate-800 mb-2 flex items-center gap-2">
                  <span className="w-6 h-6 rounded-full bg-purple-100 text-purple-700 text-xs font-bold flex items-center justify-center">↩</span>
                  Linear Regression Fallback
                </h3>
                <p className="text-sm text-slate-600 leading-relaxed">
                  When no RF model exists (or it errors), a simple <strong>linear regression on time</strong> is used against the last 6 months of savings. If fewer than 2 months of history exist, the fallback is <code className="bg-slate-100 px-1 rounded text-xs">income − total_expense</code>.
                </p>
                <div className="mt-3 bg-slate-50 rounded-lg p-3 text-xs font-mono text-slate-600 space-y-1">
                  <div className="text-slate-400">// Simple fallback:</div>
                  <div>history$t = seq(1..n)  # time index</div>
                  <div>model = lm(savings ~ t, data=history)</div>
                  <div>predicted = predict(model, t = n+1)</div>
                </div>
              </div>
            </Card>
            <Card className="p-6">
              <h3 className="font-semibold text-slate-800 mb-4">What the prediction drives</h3>
              <div className="space-y-3">
                {[
                  { icon: '📉', title: 'Predicted negative savings', trigger: 'predicted_savings < 0', action: 'Triggers a critical-severity recommendation: "Impose strict caps on discretionary expenses immediately"', color: '#fef2f2', border: '#fecaca' },
                  { icon: '💡', title: 'Shown on dashboard', trigger: 'Always displayed', action: 'The predicted amount appears in the dashboard summary card and analysis page as a forward-looking indicator.', color: '#f0f9ff', border: '#bae6fd' },
                  { icon: '📊', title: 'Excel report sheet', trigger: 'On every report download', action: 'The predicted savings figure is included in the "Summary" sheet of every Excel report as "Predicted Next Savings".', color: '#f0fdf4', border: '#bbf7d0' },
                ].map(item => (
                  <div key={item.title} className="p-4 rounded-lg border" style={{ backgroundColor: item.color, borderColor: item.border }}>
                    <div className="flex items-center gap-2 mb-1">
                      <span className="text-lg">{item.icon}</span>
                      <span className="font-semibold text-slate-800 text-sm">{item.title}</span>
                    </div>
                    <p className="text-xs text-slate-500 mb-1">Trigger: <code className="bg-white px-1 rounded">{item.trigger}</code></p>
                    <p className="text-xs text-slate-600">{item.action}</p>
                  </div>
                ))}
              </div>
            </Card>
          </div>
        </section>

        {/* ===== SECTION 6: RECOMMENDATIONS ===== */}
        <section>
          <SectionHeader
            icon={<Lightbulb className="h-5 w-5" />}
            title="Recommendation Engine — How it works"
            subtitle="Generates 3 types of personalized advice: flag-based, segment-based, and prediction-based"
          />
          <div className="mt-4 grid grid-cols-1 lg:grid-cols-3 gap-4">
            <Card className="p-5 border-t-4 border-t-red-400">
              <h3 className="font-semibold text-slate-800 mb-2 flex items-center gap-2">
                <AlertTriangle className="h-4 w-4 text-red-500" />
                1 · Flag-Based (highest priority)
              </h3>
              <p className="text-xs text-slate-500 leading-relaxed mb-3">
                Each overspending flag maps to a specific recommendation. The engine iterates over all active flags and generates an action + estimated dollar impact.
              </p>
              <div className="space-y-1.5">
                {[
                  { flag: 'High entertainment', action: 'Cut 10–15% this month' },
                  { flag: 'High rent burden', action: 'Consider shared housing' },
                  { flag: 'Low savings rate', action: 'Auto-save 10% of income' },
                  { flag: 'High food spending', action: 'Set weekly food budget' },
                  { flag: 'Spend > income', action: 'Cap all discretionary now' },
                  { flag: 'Rapid growth', action: 'Review recent increases' },
                  { flag: 'High transport', action: 'Use public transit' },
                  { flag: 'High discretionary', action: 'Set strict monthly cap' },
                ].map(r => (
                  <div key={r.flag} className="flex gap-2 text-xs">
                    <ChevronRight className="h-3.5 w-3.5 text-red-400 shrink-0 mt-0.5" />
                    <span><strong>{r.flag}</strong> → {r.action}</span>
                  </div>
                ))}
              </div>
            </Card>

            <Card className="p-5 border-t-4 border-t-blue-400">
              <h3 className="font-semibold text-slate-800 mb-2 flex items-center gap-2">
                <Brain className="h-4 w-4 text-blue-500" />
                2 · Segment-Based
              </h3>
              <p className="text-xs text-slate-500 leading-relaxed mb-3">
                Added on top of flag-based ones based on the user's cluster label. Only fires if no matching advice was already generated from flags.
              </p>
              <div className="space-y-3">
                {[
                  { segment: '🎬 Entertainment-Heavy', rec: '"Set a fixed monthly entertainment budget and stick to it"', severity: 'medium' },
                  { segment: '💰 High Saver', rec: '"Consider investing a portion of savings for long-term growth"', severity: 'info' },
                ].map(r => (
                  <div key={r.segment} className="bg-blue-50 rounded-lg p-3">
                    <p className="text-xs font-semibold text-blue-800">{r.segment}</p>
                    <p className="text-xs text-blue-600 mt-1 italic">{r.rec}</p>
                    <span className="inline-block mt-1 text-[10px] bg-blue-100 text-blue-700 px-1.5 py-0.5 rounded">severity: {r.severity}</span>
                  </div>
                ))}
                <p className="text-xs text-slate-400 italic">Balanced Budgeter and Rent-Burdened get no extra segment advice (flag-based advice is sufficient).</p>
              </div>
            </Card>

            <Card className="p-5 border-t-4 border-t-purple-400">
              <h3 className="font-semibold text-slate-800 mb-2 flex items-center gap-2">
                <TrendingUp className="h-4 w-4 text-purple-500" />
                3 · Prediction-Based
              </h3>
              <p className="text-xs text-slate-500 leading-relaxed mb-3">
                Checks the savings prediction output. If the forecast is negative, an urgent critical-severity recommendation is added regardless of flags.
              </p>
              <div className="bg-red-50 border border-red-100 rounded-lg p-3 mb-3">
                <p className="text-xs font-semibold text-red-700">If predicted_savings &lt; 0</p>
                <p className="text-xs text-red-600 mt-1">"Impose strict caps on discretionary expenses immediately"</p>
                <p className="text-xs text-red-500 mt-1">Severity: <strong>critical</strong></p>
              </div>
              <div className="bg-emerald-50 border border-emerald-100 rounded-lg p-3">
                <p className="text-xs font-semibold text-emerald-700">If no recommendations generated</p>
                <p className="text-xs text-emerald-600 mt-1">"You're doing well! Continue your current spending habits."</p>
                <p className="text-xs text-emerald-500 mt-1">Severity: <strong>info</strong></p>
              </div>
            </Card>
          </div>
        </section>

        {/* ===== SECTION 7: TOP USERS ===== */}
        <section>
          <SectionHeader
            icon={<Users className="h-5 w-5" />}
            title="User Table"
            subtitle="All registered users sorted by total spending"
          />
          <Card className="mt-4 overflow-hidden">
            <div className="overflow-x-auto">
              <table className="w-full text-sm">
                <thead className="bg-slate-50 border-b border-slate-200">
                  <tr>
                    {['User', 'Email', 'Role', 'Expenses', 'Total Spent', 'Avg / Expense', 'Joined'].map(h => (
                      <th key={h} className="px-4 py-3 text-left text-xs font-semibold text-slate-500 uppercase tracking-wider">{h}</th>
                    ))}
                  </tr>
                </thead>
                <tbody className="divide-y divide-slate-100">
                  {users
                    .sort((a, b) => (b.total_spent || 0) - (a.total_spent || 0))
                    .slice(0, 15)
                    .map((u, i) => (
                      <tr key={u.id} className="hover:bg-slate-50 transition-colors">
                        <td className="px-4 py-3 font-medium text-slate-900">
                          <span className="inline-flex items-center gap-2">
                            <span className="w-6 h-6 rounded-full bg-blue-100 text-blue-700 text-xs font-bold flex items-center justify-center">{i + 1}</span>
                            {u.full_name}
                          </span>
                        </td>
                        <td className="px-4 py-3 text-slate-500">{u.email}</td>
                        <td className="px-4 py-3">
                          <span className={`text-xs px-2 py-0.5 rounded-full font-medium ${u.role === 'admin' ? 'bg-purple-100 text-purple-700' : 'bg-slate-100 text-slate-600'}`}>
                            {u.role}
                          </span>
                        </td>
                        <td className="px-4 py-3 text-slate-700">{(u.expense_count || 0).toLocaleString()}</td>
                        <td className="px-4 py-3 font-semibold text-slate-900">
                          ${(u.total_spent || 0).toLocaleString('en-US', { maximumFractionDigits: 2 })}
                        </td>
                        <td className="px-4 py-3 text-slate-500">
                          ${u.expense_count ? ((u.total_spent || 0) / u.expense_count).toFixed(2) : '—'}
                        </td>
                        <td className="px-4 py-3 text-slate-400 text-xs">
                          {u.created_at ? new Date(u.created_at).toLocaleDateString() : '—'}
                        </td>
                      </tr>
                    ))}
                </tbody>
              </table>
              {users.length > 15 && (
                <div className="px-4 py-2 bg-slate-50 border-t border-slate-200 text-xs text-slate-400 text-center">
                  Showing top 15 of {users.length} users
                </div>
              )}
            </div>
          </Card>
        </section>

      </div>
    </DashboardLayout>
  );
}

function SectionHeader({ icon, title, subtitle }: { icon: React.ReactNode; title: string; subtitle: string }) {
  return (
    <div className="flex items-start gap-3">
      <div className="w-9 h-9 rounded-lg bg-slate-100 text-slate-600 flex items-center justify-center shrink-0 mt-0.5">
        {icon}
      </div>
      <div>
        <h2 className="text-xl font-bold text-slate-900">{title}</h2>
        <p className="text-slate-500 text-sm mt-0.5">{subtitle}</p>
      </div>
    </div>
  );
}

function MetricCard({ icon, label, value, bg, note }: { icon: React.ReactNode; label: string; value: string; bg: string; note: string }) {
  return (
    <Card className={`p-5 ${bg} border-0`}>
      <div className="flex items-start justify-between mb-3">
        <p className="text-sm font-medium text-slate-600">{label}</p>
        {icon}
      </div>
      <p className="text-2xl font-bold text-slate-900">{value}</p>
      <p className="text-xs text-slate-400 mt-1">{note}</p>
    </Card>
  );
}
