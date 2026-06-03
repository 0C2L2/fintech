"use client";

import { useEffect, useState } from "react";
import { DashboardLayout } from "@/components/DashboardLayout";
import { api } from "@/lib/api";
import { AdminOverview } from "@/types";
import { Card, CardContent, CardHeader, CardTitle } from "@/components/ui/card";
import { Users, Receipt, PieChart, ShieldAlert } from "lucide-react";
import { toast } from "sonner";
import { useAuth } from "@/lib/auth-context";
import { useRouter } from "next/navigation";

export default function AdminPage() {
  const [overview, setOverview] = useState<AdminOverview | null>(null);
  const [segments, setSegments] = useState<{segment: string, count: number}[]>([]);
  const [isLoading, setIsLoading] = useState(true);
  const { user } = useAuth();
  const router = useRouter();

  useEffect(() => {
    if (user && user.role !== 'admin') {
      router.push('/dashboard');
      return;
    }

    const fetchAdminData = async () => {
      setIsLoading(true);
      try {
        const [overviewRes, segmentsRes] = await Promise.all([
          api.admin.overview(),
          api.admin.segments()
        ]);

        if (overviewRes.success) setOverview(overviewRes.data);
        if (segmentsRes.success) setSegments(segmentsRes.data);
      } catch (err: any) {
        toast.error("Failed to load admin data");
      } finally {
        setIsLoading(false);
      }
    };

    if (user?.role === 'admin') {
      fetchAdminData();
    }
  }, [user, router]);

  if (!user || user.role !== 'admin') return null;

  return (
    <DashboardLayout>
      <div className="space-y-6">
        <div>
          <h1 className="text-3xl font-bold tracking-tight text-slate-900 flex items-center">
            <ShieldAlert className="mr-3 h-8 w-8 text-red-600" />
            Admin Panel
          </h1>
          <p className="text-slate-500">System overview and aggregates.</p>
        </div>

        {isLoading ? (
          <div className="flex justify-center p-12">
            <div className="animate-spin rounded-full h-8 w-8 border-b-2 border-blue-600"></div>
          </div>
        ) : (
          <>
            <div className="grid grid-cols-1 md:grid-cols-3 gap-6">
              <Card className="shadow-sm border-slate-200">
                <CardHeader className="flex flex-row items-center justify-between pb-2 space-y-0">
                  <CardTitle className="text-sm font-medium text-slate-500">Total Users</CardTitle>
                  <Users className="h-4 w-4 text-blue-600" />
                </CardHeader>
                <CardContent>
                  <div className="text-3xl font-bold text-slate-900">{overview?.total_users || 0}</div>
                </CardContent>
              </Card>
              
              <Card className="shadow-sm border-slate-200">
                <CardHeader className="flex flex-row items-center justify-between pb-2 space-y-0">
                  <CardTitle className="text-sm font-medium text-slate-500">Total Expenses Logged</CardTitle>
                  <Receipt className="h-4 w-4 text-blue-600" />
                </CardHeader>
                <CardContent>
                  <div className="text-3xl font-bold text-slate-900">{overview?.total_expenses || 0}</div>
                  <p className="text-xs text-slate-500 mt-1">
                    Vol: ${overview?.total_expense_amount?.toFixed(2) || '0.00'}
                  </p>
                </CardContent>
              </Card>

              <Card className="shadow-sm border-slate-200">
                <CardHeader className="flex flex-row items-center justify-between pb-2 space-y-0">
                  <CardTitle className="text-sm font-medium text-slate-500">User Segments</CardTitle>
                  <PieChart className="h-4 w-4 text-blue-600" />
                </CardHeader>
                <CardContent>
                  <div className="text-3xl font-bold text-slate-900">{segments.length}</div>
                  <p className="text-xs text-slate-500 mt-1">distinct profiles</p>
                </CardContent>
              </Card>
            </div>

            <div className="grid grid-cols-1 gap-6">
              <Card className="shadow-sm border-slate-200">
                <CardHeader>
                  <CardTitle>System Segmentation Distribution</CardTitle>
                </CardHeader>
                <CardContent>
                   {segments.length > 0 ? (
                     <div className="space-y-4">
                       {segments.map((seg, i) => {
                         const total = segments.reduce((acc, curr) => acc + curr.count, 0);
                         const percent = Math.round((seg.count / total) * 100);
                         return (
                           <div key={i} className="flex items-center justify-between">
                             <div className="space-y-1 w-full">
                               <div className="flex items-center justify-between">
                                  <span className="font-medium text-sm text-slate-900">{seg.segment}</span>
                                  <span className="text-sm text-slate-500">{seg.count} cases ({percent}%)</span>
                               </div>
                               <div className="w-full bg-slate-100 rounded-full h-2">
                                 <div className="bg-blue-600 h-2 rounded-full" style={{ width: `${percent}%` }}></div>
                               </div>
                             </div>
                           </div>
                         );
                       })}
                     </div>
                   ) : (
                     <div className="text-slate-500 text-center py-4">No segment data available yet.</div>
                   )}
                </CardContent>
              </Card>
            </div>
          </>
        )}
      </div>
    </DashboardLayout>
  );
}
