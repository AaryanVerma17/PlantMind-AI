import { useEffect, useState } from "react";
import Navbar from "../components/Navbar";
import { getComplianceDashboard, getEquipmentCompliance } from "../services/api";
import { Search, CheckCircle2, XCircle, AlertCircle } from "lucide-react";

const statusIcon = {
  met: <CheckCircle2 size={16} className="text-emerald-500" />,
  missing: <XCircle size={16} className="text-red-500" />,
  expired: <AlertCircle size={16} className="text-amber-500" />,
};

export default function Compliance() {
  const [summary, setSummary] = useState(null);
  const [tag, setTag] = useState("");
  const [category, setCategory] = useState("");
  const [result, setResult] = useState(null);
  const [searching, setSearching] = useState(false);

  useEffect(() => {
    getComplianceDashboard().then((r) => setSummary(r.data));
  }, []);

  const handleSearch = async () => {
    if (!tag.trim() || !category.trim()) return;
    setSearching(true);
    try {
      const { data } = await getEquipmentCompliance(tag, category);
      setResult(data);
    } finally {
      setSearching(false);
    }
  };

  return (
    <div>
      <Navbar title="Compliance Intelligence" />
      <div className="p-8 space-y-6">
        <div className="grid grid-cols-4 gap-5">
          {[
            { label: "Total Requirements", value: summary?.total ?? 0, color: "slate" },
            { label: "Met", value: summary?.met ?? 0, color: "emerald" },
            { label: "Missing", value: summary?.missing ?? 0, color: "red" },
            { label: "Expired", value: summary?.expired ?? 0, color: "amber" },
          ].map((s, i) => (
            <div key={i} className="bg-white border border-slate-200 rounded-2xl p-5 shadow-sm">
              <p className="text-xs text-slate-400 font-medium">{s.label}</p>
              <p className={`text-2xl font-semibold mt-1 text-${s.color}-600`}>{s.value}</p>
            </div>
          ))}
        </div>

        <div className="bg-white border border-slate-200 rounded-2xl shadow-sm p-6">
          <h3 className="font-semibold text-slate-800 mb-4">Check Equipment Compliance</h3>
          <div className="flex gap-3 mb-5">
            <input
              value={tag}
              onChange={(e) => setTag(e.target.value)}
              placeholder="Equipment tag, e.g. P-102"
              className="flex-1 border border-slate-300 rounded-lg px-4 py-2.5 text-sm"
            />
            <input
              value={category}
              onChange={(e) => setCategory(e.target.value)}
              placeholder="Category, e.g. Pressure Vessel"
              className="flex-1 border border-slate-300 rounded-lg px-4 py-2.5 text-sm"
            />
            <button
              onClick={handleSearch}
              disabled={searching}
              className="bg-emerald-600 hover:bg-emerald-700 disabled:opacity-50 text-white rounded-lg px-5 flex items-center gap-2 text-sm font-medium"
            >
              <Search size={16} /> Check
            </button>
          </div>

          {result && (
            <div>
              <p className="text-sm text-slate-500 mb-3">
                {result.equipment_tag} · {result.equipment_category} · {result.gaps.length} gap(s) found
              </p>
              <div className="divide-y divide-slate-100 border border-slate-100 rounded-xl">
                {result.all_requirements.map((r, i) => (
                  <div key={i} className="flex items-center justify-between px-4 py-3">
                    <div className="flex items-center gap-2">
                      {statusIcon[r.status] || statusIcon.missing}
                      <span className="text-sm text-slate-700">{r.requirement}</span>
                    </div>
                    <span className="text-xs text-slate-400 capitalize">{r.status}</span>
                  </div>
                ))}
              </div>
            </div>
          )}
        </div>
      </div>
    </div>
  );
}
