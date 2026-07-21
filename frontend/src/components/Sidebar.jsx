import { NavLink } from "react-router-dom";
import {
  LayoutDashboard, MessageSquare, FileText, Wrench, ShieldCheck, FileBarChart2,
} from "lucide-react";

const navItems = [
  { to: "/", label: "Dashboard", icon: LayoutDashboard },
  { to: "/chat", label: "AI Copilot", icon: MessageSquare },
  { to: "/documents", label: "Documents", icon: FileText },
  { to: "/maintenance", label: "Maintenance", icon: Wrench },
  { to: "/compliance", label: "Compliance", icon: ShieldCheck },
  { to: "/reports", label: "Reports", icon: FileBarChart2 },
];

export default function Sidebar() {
  return (
    <aside className="w-60 h-screen bg-slate-900 text-slate-200 flex flex-col fixed left-0 top-0">
      <div className="px-6 py-5 border-b border-slate-800">
        <h1 className="text-lg font-semibold tracking-tight text-white">PlantMind <span className="text-emerald-400">AI</span></h1>
        <p className="text-xs text-slate-500 mt-0.5">Industrial Knowledge Intelligence</p>
      </div>
      <nav className="flex-1 px-3 py-4 space-y-1">
        {navItems.map(({ to, label, icon: Icon }) => (
          <NavLink
            key={to}
            to={to}
            end={to === "/"}
            className={({ isActive }) =>
              `flex items-center gap-3 px-3 py-2.5 rounded-lg text-sm transition-colors ${
                isActive
                  ? "bg-emerald-500/10 text-emerald-400 font-medium"
                  : "text-slate-400 hover:bg-slate-800 hover:text-slate-200"
              }`
            }
          >
            <Icon size={18} />
            {label}
          </NavLink>
        ))}
      </nav>
      <div className="px-6 py-4 border-t border-slate-800 text-xs text-slate-500">
        v1.0.0 · ET GenAI Hackathon
      </div>
    </aside>
  );
}
