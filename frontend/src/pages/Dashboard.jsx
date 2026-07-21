import { useEffect, useState } from "react";
import Navbar from "../components/Navbar";
import StatsCard from "../components/StatsCard";
import { listDocuments, getHealthOverview, getPredictiveAlerts, getComplianceDashboard } from "../services/api";
import { FileText, AlertTriangle, ShieldCheck, Activity } from "lucide-react";
import { BarChart, Bar, XAxis, YAxis, Tooltip, ResponsiveContainer, CartesianGrid } from "recharts";

export default function Dashboard() {
  const [docs, setDocs] = useState([]);
  const [health, setHealth] = useState([]);
  const [alerts, setAlerts] = useState([]);
  const [compliance, setCompliance] = useState(null);
  const [loading, setLoading] = useState(true);

  useEffect(() => {
    (async () => {
      try {
        const [d, h, a, c] = await Promise.all([
          listDocuments(),
          getHealthOverview(),
          getPredictiveAlerts(),
          getComplianceDashboard(),
        ]);
        setDocs(d.data);
        setHealth(h.data);
        setAlerts(a.data);
        setCompliance(c.data);
      } finally {
        setLoading(false);
      }
    })();
  }, []);

  const readyDocs = docs.filter((d) => d.status === "ready").length;
  const highRiskEquipment = health.filter((h) => h.risk_level === "high").length;
  const chartData = health.slice(0, 8).map((h) => ({ name: h.equipment_tag, breakdowns: h.breakdowns, events: h.total_events }));

  return (
    <div>
      <Navbar title="Analytics Dashboard" />
      <div className="p-8 space-y-6">
        <div className="grid grid-cols-4 gap-5">
          <StatsCard label="Documents Indexed" value={readyDocs} icon={FileText} accent="slate" />
          <StatsCard label="High-Risk Equipment" value={highRiskEquipment} icon={AlertTriangle} accent="red" />
          <StatsCard label="Predictive Alerts" value={alerts.length} icon={Activity} accent="amber" />
          <StatsCard
            label="Compliance Rate"
            value={compliance?.compliance_rate ?? 0}
            suffix="%"
            icon={ShieldCheck}
            accent="emerald"
          />
        </div>

        <div className="grid grid-cols-3 gap-6">
          <div className="col-span-2 bg-white border border-slate-200 rounded-2xl p-6 shadow-sm">
            <h3 className="font-semibold text-slate-800 mb-4">Equipment Breakdown Frequency</h3>
            {chartData.length === 0 ? (
              <p className="text-sm text-slate-400 py-10 text-center">No maintenance data yet. Upload maintenance logs to populate this chart.</p>
            ) : (
              <ResponsiveContainer width="100%" height={280}>
                <BarChart data={chartData}>
                  <CartesianGrid strokeDasharray="3 3" stroke="#f1f5f9" />
                  <XAxis dataKey="name" tick={{ fontSize: 12 }} />
                  <YAxis tick={{ fontSize: 12 }} />
                  <Tooltip />
                  <Bar dataKey="events" fill="#cbd5e1" name="Total Events" radius={[4, 4, 0, 0]} />
                  <Bar dataKey="breakdowns" fill="#ef4444" name="Breakdowns" radius={[4, 4, 0, 0]} />
                </BarChart>
              </ResponsiveContainer>
            )}
          </div>

          <div className="bg-white border border-slate-200 rounded-2xl p-6 shadow-sm">
            <h3 className="font-semibold text-slate-800 mb-4">Upcoming / Overdue Maintenance</h3>
            <div className="space-y-3 max-h-[280px] overflow-y-auto">
              {alerts.length === 0 && <p className="text-sm text-slate-400 text-center py-10">No predictive alerts.</p>}
              {alerts.map((a, i) => (
                <div key={i} className="flex items-center justify-between bg-slate-50 rounded-lg px-3 py-2.5">
                  <div>
                    <p className="text-sm font-medium text-slate-700">{a.equipment_tag}</p>
                    <p className="text-xs text-slate-400">Avg interval: {a.avg_failure_interval_days}d</p>
                  </div>
                  <span className={`text-xs px-2 py-1 rounded-full font-medium ${
                    a.urgency === "overdue" ? "bg-red-50 text-red-600" : "bg-amber-50 text-amber-600"
                  }`}>
                    {a.urgency === "overdue" ? "Overdue" : `${a.predicted_days_until_next_failure}d`}
                  </span>
                </div>
              ))}
            </div>
          </div>
        </div>
      </div>
    </div>
  );
}
