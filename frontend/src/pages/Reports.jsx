import { useState } from "react";
import Navbar from "../components/Navbar";
import { generateReport } from "../services/api";
import { FileBarChart2, Loader2, Download } from "lucide-react";

const REPORT_TYPES = [
  { value: "maintenance", label: "Maintenance Report" },
  { value: "incident", label: "Incident Report" },
  { value: "audit_summary", label: "Audit Summary" },
  { value: "equipment_summary", label: "Equipment Summary" },
  { value: "executive", label: "Executive Report" },
];

export default function Reports() {
  const [reportType, setReportType] = useState("maintenance");
  const [equipmentTag, setEquipmentTag] = useState("");
  const [incidentDescription, setIncidentDescription] = useState("");
  const [format, setFormat] = useState("pdf");
  const [generating, setGenerating] = useState(false);
  const [result, setResult] = useState(null);

  const apiBase = import.meta.env.VITE_API_URL || "http://localhost:8000";

  const handleGenerate = async () => {
    setGenerating(true);
    setResult(null);
    try {
      const { data } = await generateReport({
        report_type: reportType,
        equipment_tag: reportType === "equipment_summary" ? equipmentTag : undefined,
        incident_description: reportType === "incident" ? incidentDescription : undefined,
        export_format: format,
      });
      setResult(data);
    } catch (err) {
      alert(err.response?.data?.detail || "Report generation failed.");
    } finally {
      setGenerating(false);
    }
  };

  return (
    <div>
      <Navbar title="AI Report Generator" />
      <div className="p-8 max-w-2xl">
        <div className="bg-white border border-slate-200 rounded-2xl shadow-sm p-6">
          <h3 className="font-semibold text-slate-800 mb-4">Generate Report</h3>

          <label className="text-xs font-medium text-slate-500">Report Type</label>
          <select
            value={reportType}
            onChange={(e) => setReportType(e.target.value)}
            className="w-full border border-slate-300 rounded-lg px-4 py-2.5 text-sm mt-1 mb-4"
          >
            {REPORT_TYPES.map((r) => <option key={r.value} value={r.value}>{r.label}</option>)}
          </select>

          {reportType === "equipment_summary" && (
            <>
              <label className="text-xs font-medium text-slate-500">Equipment Tag</label>
              <input
                value={equipmentTag}
                onChange={(e) => setEquipmentTag(e.target.value)}
                placeholder="e.g. P-102"
                className="w-full border border-slate-300 rounded-lg px-4 py-2.5 text-sm mt-1 mb-4"
              />
            </>
          )}

          {reportType === "incident" && (
            <>
              <label className="text-xs font-medium text-slate-500">Incident Description</label>
              <textarea
                value={incidentDescription}
                onChange={(e) => setIncidentDescription(e.target.value)}
                rows={3}
                placeholder="Describe what happened..."
                className="w-full border border-slate-300 rounded-lg px-4 py-2.5 text-sm mt-1 mb-4 resize-none"
              />
            </>
          )}

          <label className="text-xs font-medium text-slate-500">Export Format</label>
          <div className="flex gap-3 mt-1 mb-5">
            {["pdf", "docx"].map((f) => (
              <button
                key={f}
                onClick={() => setFormat(f)}
                className={`px-4 py-2 rounded-lg text-sm font-medium border ${
                  format === f ? "bg-emerald-600 text-white border-emerald-600" : "border-slate-300 text-slate-600"
                }`}
              >
                {f.toUpperCase()}
              </button>
            ))}
          </div>

          <button
            onClick={handleGenerate}
            disabled={generating}
            className="w-full bg-emerald-600 hover:bg-emerald-700 disabled:opacity-50 text-white rounded-lg py-3 flex items-center justify-center gap-2 text-sm font-medium"
          >
            {generating ? <Loader2 size={16} className="animate-spin" /> : <FileBarChart2 size={16} />}
            Generate Report
          </button>

          {result && (
            <a 
              href={`${apiBase}${result.download_url}`}
              target="_blank"
              rel="noreferrer"
              className="mt-4 flex items-center justify-between bg-emerald-50 text-emerald-700 rounded-lg px-4 py-3 text-sm font-medium"
            >
              {result.title}
              <Download size={16} />
            </a>
          )}
        </div>
      </div>
    </div>
  );
}
