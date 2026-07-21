import { useEffect, useState } from "react";
import Navbar from "../components/Navbar";
import { getHealthOverview, getPredictiveAlerts, runRootCauseAnalysis } from "../services/api";
import { Loader2, Search } from "lucide-react";

const riskColors = {
  high: "bg-red-50 text-red-600",
  medium: "bg-amber-50 text-amber-600",
  low: "bg-emerald-50 text-emerald-600",
  unknown: "bg-slate-100 text-slate-500",
};

export default function Maintenance() {
  const [health, setHealth] = useState([]);
  const [alerts, setAlerts] = useState([]);
  const [incident, setIncident] = useState("");
  const [rcaResult, setRcaResult] = useState(null);
  const [analyzing, setAnalyzing] = useState(false);

  useEffect(() => {
    (async () => {
      const [h, a] = await Promise.all([getHealthOverview(), getPredictiveAlerts()]);
      setHealth(h.data);
      setAlerts(a.data);
    })();
  }, []);

  const handleAnalyze = async () => {
    if (!incident.trim()) return;
    setAnalyzing(true);
    setRcaResult(null);
    try {
      const { data } = await runRootCauseAnalysis(incident);
      setRcaResult(data);
    } catch {
      setRcaResult({ likely_causes: ["Analysis failed - please try again."], corrective_actions: [], preventive_recommendations: [], confidence: 0 });
    } finally {
      setAnalyzing(false);
    }
  };

  return (
    <div>
      <Navbar title="Maintenance Intelligence" />
      <div className="p-8 space-y-6">
        <div className="grid grid-cols-2 gap-6">
          <div className="bg-white border border-slate-200 rounded-2xl shadow-sm">
            <div className="px-6 py-4 border-b border-slate-100">
              <h3 className="font-semibold text-slate-800">Equipment Health Overview</h3>
            </div>
            <div className="max-h-[380px] overflow-y-auto divide-y divide-slate-100">
              {health.length === 0 && <p className="text-sm text-slate-400 text-center py-10">No equipment data yet.</p>}
              {health.map((h, i) => (
                <div key={i} className="flex items-center justify-between px-6 py-3">
                  <div>
                    <p className="text-sm font-medium text-slate-700">{h.equipment_tag}</p>
                    <p className="text-xs text-slate-400">{h.total_events} events · {h.total_downtime_hours}h downtime</p>
                  </div>
                  <span className={`text-xs px-2.5 py-1 rounded-full font-medium capitalize ${riskColors[h.risk_level]}`}>
                    {h.risk_level}
                  </span>
                </div>
              ))}
            </div>
          </div>

          <div className="bg-white border border-slate-200 rounded-2xl shadow-sm">
            <div className="px-6 py-4 border-b border-slate-100">
              <h3 className="font-semibold text-slate-800">Predictive Maintenance Alerts</h3>
            </div>
            <div className="max-h-[380px] overflow-y-auto divide-y divide-slate-100">
              {alerts.length === 0 && <p className="text-sm text-slate-400 text-center py-10">No alerts. Need 2+ breakdown records per equipment tag.</p>}
              {alerts.map((a, i) => (
                <div key={i} className="px-6 py-3">
                  <div className="flex items-center justify-between">
                    <p className="text-sm font-medium text-slate-700">{a.equipment_tag}</p>
                    <span className={`text-xs px-2 py-1 rounded-full font-medium ${a.urgency === "overdue" ? "bg-red-50 text-red-600" : "bg-amber-50 text-amber-600"}`}>
                      {a.urgency}
                    </span>
                  </div>
                  <p className="text-xs text-slate-400 mt-0.5">
                    Predicted in {a.predicted_days_until_next_failure}d · avg cycle {a.avg_failure_interval_days}d
                  </p>
                </div>
              ))}
            </div>
          </div>
        </div>

        <div className="bg-white border border-slate-200 rounded-2xl shadow-sm p-6">
          <h3 className="font-semibold text-slate-800 mb-1">Root Cause Analysis</h3>
          <p className="text-sm text-slate-400 mb-4">Describe an incident and get AI-driven cause analysis grounded in your plant records.</p>
          <div className="flex gap-3">
            <textarea
              value={incident}
              onChange={(e) => setIncident(e.target.value)}
              rows={2}
              placeholder="e.g. Compressor C-204 tripped on high vibration during startup at 03:15..."
              className="flex-1 border border-slate-300 rounded-lg px-4 py-2.5 text-sm resize-none focus:outline-none focus:ring-2 focus:ring-emerald-500/40"
            />
            <button
              onClick={handleAnalyze}
              disabled={analyzing}
              className="bg-emerald-600 hover:bg-emerald-700 disabled:opacity-50 text-white rounded-lg px-5 flex items-center gap-2 text-sm font-medium"
            >
              {analyzing ? <Loader2 size={16} className="animate-spin" /> : <Search size={16} />}
              Analyze
            </button>
          </div>

          {rcaResult && (
            <div className="grid grid-cols-3 gap-4 mt-6">
              <div>
                <p className="text-xs font-medium text-slate-500 mb-2">Likely Causes</p>
                <ul className="text-sm text-slate-700 space-y-1 list-disc list-inside">
                  {rcaResult.likely_causes?.map((c, i) => <li key={i}>{c}</li>)}
                </ul>
              </div>
              <div>
                <p className="text-xs font-medium text-slate-500 mb-2">Corrective Actions</p>
                <ul className="text-sm text-slate-700 space-y-1 list-disc list-inside">
                  {rcaResult.corrective_actions?.map((c, i) => <li key={i}>{c}</li>)}
                </ul>
              </div>
              <div>
                <p className="text-xs font-medium text-slate-500 mb-2">Preventive Recommendations</p>
                <ul className="text-sm text-slate-700 space-y-1 list-disc list-inside">
                  {rcaResult.preventive_recommendations?.map((c, i) => <li key={i}>{c}</li>)}
                </ul>
              </div>
            </div>
          )}
        </div>
      </div>
    </div>
  );
}
