export default function StatsCard({ label, value, icon: Icon, accent = "emerald", suffix = "" }) {
  const accents = {
    emerald: "bg-emerald-50 text-emerald-600",
    amber: "bg-amber-50 text-amber-600",
    red: "bg-red-50 text-red-600",
    slate: "bg-slate-100 text-slate-600",
  };

  return (
    <div className="bg-white border border-slate-200 rounded-2xl p-5 shadow-sm flex items-center justify-between">
      <div>
        <p className="text-xs text-slate-400 font-medium">{label}</p>
        <p className="text-2xl font-semibold text-slate-800 mt-1">
          {value}
          {suffix}
        </p>
      </div>
      <div className={`w-11 h-11 rounded-xl flex items-center justify-center ${accents[accent]}`}>
        <Icon size={20} />
      </div>
    </div>
  );
}
