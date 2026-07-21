export default function Navbar({ title }) {
  return (
    <header className="h-16 border-b border-slate-200 bg-white flex items-center justify-between px-8 sticky top-0 z-10">
      <h2 className="text-xl font-semibold text-slate-800">{title}</h2>
      <div className="flex items-center gap-3">
        <span className="text-sm text-slate-500">Plant Engineer</span>
        <div className="w-9 h-9 rounded-full bg-emerald-500 text-white flex items-center justify-center text-sm font-medium">
          PE
        </div>
      </div>
    </header>
  );
}
