import tkinter as tk
from tkinter import ttk, messagebox
import json
import os
import shutil
from pathlib import Path
import sv_ttk
import ctypes
import threading
import concurrent.futures

# ==========================================
# 0. 样式配置 (背景障眼法核心)
# ==========================================
class UIStyleConfig:
    WINDOW_SIZE = "1200x900"
    MIN_SIZE = (1100, 800)
    
    # [核心] 统一背景色，防止露底出现黑块
    # 只要这个颜色和上层控件一致，刷新时的"空隙"就看不见
    COLOR_BG_MAIN   = "#f3f3f3" 
    COLOR_BG_EDITOR = "#ffffff"
    COLOR_ACCENT    = "#0078d4"
    
    # 字体配置
    FONT_TITLE_L = ("Microsoft YaHei UI", 16, "bold")
    FONT_TITLE_M = ("Microsoft YaHei UI", 12, "bold")
    FONT_BODY    = ("Microsoft YaHei UI", 11)
    FONT_BOLD    = ("Microsoft YaHei UI", 11, "bold")
    FONT_CODE    = ("Consolas", 11)

    @staticmethod
    def apply_global_styles(root):
        try:
            # 仅开启 DPI 适配，不开启双缓冲
            ctypes.windll.shcore.SetProcessDpiAwareness(1)
            scale = ctypes.windll.shcore.GetScaleFactorForDevice(0) / 100
            root.tk.call('tk', 'scaling', scale)
        except: pass

        # [障眼法关键] 根窗口背景必须和 Frame 背景完全一致
        # 这样即使控件还没画出来，用户看到的也是一片灰白，而不是黑块
        root.configure(bg=UIStyleConfig.COLOR_BG_MAIN)

        try: sv_ttk.set_theme("light")
        except: pass

        style = ttk.Style()
        
        # 强制统一背景
        style.configure(".", font=UIStyleConfig.FONT_BODY, background=UIStyleConfig.COLOR_BG_MAIN)
        style.configure("TFrame", background=UIStyleConfig.COLOR_BG_MAIN)
        style.configure("TNotebook", background=UIStyleConfig.COLOR_BG_MAIN)
        style.configure("TNotebook.Tab", font=UIStyleConfig.FONT_TITLE_M, padding=(15, 3))
        
        style.configure("Treeview", font=UIStyleConfig.FONT_BODY, rowheight=30, background="white", fieldbackground="white")
        style.configure("Treeview.Heading", font=UIStyleConfig.FONT_BOLD, padding=(10, 8))
        
        style.configure("TButton", font=UIStyleConfig.FONT_BODY, padding=(10, 6))
        style.configure("Accent.TButton", font=UIStyleConfig.FONT_BOLD, padding=(10, 6))
        
        style.configure("TLabelframe", background=UIStyleConfig.COLOR_BG_MAIN)
        style.configure("TLabelframe.Label", font=UIStyleConfig.FONT_TITLE_M, foreground=UIStyleConfig.COLOR_ACCENT, background=UIStyleConfig.COLOR_BG_MAIN)

        root.option_add("*TEntry*Font", UIStyleConfig.FONT_BODY)
        root.option_add("*TCombobox*Font", UIStyleConfig.FONT_BODY)
        root.option_add("*Text*Font", UIStyleConfig.FONT_CODE)
        root.option_add("*Text*background", UIStyleConfig.COLOR_BG_EDITOR)

# ==========================================
# 1. 智能变量
# ==========================================
class SmartVar:
    @staticmethod
    def set(tk_var, new_value):
        s_val = str(new_value)
        if tk_var.get() != s_val:
            tk_var.set(s_val)

# ==========================================
# 2. 异步引擎
# ==========================================
class AsyncEngine:
    _executor = concurrent.futures.ThreadPoolExecutor(max_workers=4)
    _root = None

    @classmethod
    def set_root(cls, root):
        cls._root = root

    @staticmethod
    def run(task_func, ui_callback, *args):
        def _worker():
            try: return (True, task_func(*args))
            except Exception as e: return (False, str(e))
        def _done(future):
            if not AsyncEngine._root: return
            try:
                success, result = future.result()
                AsyncEngine._root.after(0, lambda: ui_callback(success, result) if ui_callback else None)
            except: pass
        future = AsyncEngine._executor.submit(_worker)
        future.add_done_callback(_done)

# ==========================================
# 3. 数据管理器 (副本模式)
# ==========================================
class OpenClawDataManager:
    def __init__(self):
        self.home = Path.home()
        self.config_path = self.home / ".openclaw" / "openclaw.json"
        self.config_data = {}
        self.agent_list = []
        self.files_meta = {}
        self.files_buffer = {}
        self.skills_cache = {}
        self.current_agent_id = None
        self._io_executor = concurrent.futures.ThreadPoolExecutor(max_workers=8)

    def _create_default_config(self):
        default_conf = {"agents": {"defaults": {"workspace": "~/.openclaw/workspace"}, "list": [{"id": "main", "default": True}]}}
        self.config_path.parent.mkdir(parents=True, exist_ok=True)
        with open(self.config_path, 'w', encoding='utf-8') as f: json.dump(default_conf, f, indent=2)

    def _read_file_safe(self, path_obj):
        try:
            if path_obj.exists() and path_obj.stat().st_size < 100000:
                return str(path_obj), path_obj.read_text(encoding='utf-8')
        except: pass
        return str(path_obj), None

    def preload_all_data(self):
        if not self.config_path.exists(): self._create_default_config()
        try:
            with open(self.config_path, 'r', encoding='utf-8') as f: self.config_data = json.load(f)
        except: self.config_data = {"agents": {"list": []}}
        
        self.agent_list = self.config_data.get("agents", {}).get("list", [{"id": "main", "name": "Default"}])
        
        files_to_read = []
        for agent in self.agent_list:
            aid = agent['id']
            ws = self.get_workspace_path_obj(aid)
            meta = []
            if ws.exists():
                for f in ["AGENTS.md", "SOUL.md", "USER.md", "IDENTITY.md", "TOOLS.md"]:
                    p = ws / f
                    exists = p.exists()
                    meta.append((f, str(p), exists))
                    if exists: files_to_read.append(p)
            self.files_meta[aid] = meta
            
            skills = {}
            for base in [self.home / ".openclaw" / "skills", ws / "skills"]:
                if base.exists():
                    for i in base.iterdir():
                        if i.is_dir() and (i/"SKILL.md").exists():
                            skills[i.name] = {"source": "Global" if "openclaw" in str(base) else "Workspace", "path": str(i)}
            self.skills_cache[aid] = skills

        if files_to_read:
            results = self._io_executor.map(self._read_file_safe, files_to_read)
            for path_str, content in results:
                if content is not None: self.files_buffer[path_str] = content
        return True

    def save_file_atomic(self, original_path_str, content):
        original_path = Path(original_path_str)
        shadow_path = original_path.with_suffix(original_path.suffix + ".tmp")
        try:
            original_path.parent.mkdir(parents=True, exist_ok=True)
            with open(shadow_path, 'w', encoding='utf-8') as f:
                f.write(content); f.flush(); os.fsync(f.fileno())
            os.replace(shadow_path, original_path)
            self.files_buffer[original_path_str] = content
            return True
        except Exception as e: return False

    def get_val(self, path, default=None):
        keys = path.split('.')
        curr = self.config_data
        try:
            for k in keys: curr = curr[k]
            return curr
        except: return default

    def set_val(self, path, value):
        keys = path.split('.')
        curr = self.config_data
        for k in keys[:-1]:
            if k not in curr: curr[k] = {}
            curr = curr[k]
        curr[keys[-1]] = value

    def save_config_sync(self):
        try:
            temp = self.config_path.with_suffix(".tmp")
            with open(temp, 'w', encoding='utf-8') as f: json.dump(self.config_data, f, indent=2)
            os.replace(temp, self.config_path)
            return True
        except: return False

    def get_file_content(self, path_str): return self.files_buffer.get(path_str, "")
    def update_file_buffer(self, path_str, content): self.files_buffer[path_str] = content
    def save_file_sync(self, path_str, content): return self.save_file_atomic(path_str, content)
    def get_workspace_path_obj(self, agent_id):
        agent = next((a for a in self.agent_list if a.get("id") == agent_id), {})
        ws = agent.get("workspace") or self.get_val("agents.defaults.workspace") or "~/.openclaw/workspace"
        return Path(os.path.expanduser(ws)).resolve()

# ==========================================
# 4. 静态面板基类
# ==========================================
class StaticPanel(ttk.Frame):
    def __init__(self, parent, manager):
        super().__init__(parent)
        self.manager = manager
        # 强制撑开，防止塌陷
        self.pack(fill="both", expand=True) 
        self._setup_static_ui() 
    def _setup_static_ui(self): pass
    def sync_data(self): pass

# ==========================================
# 5. 面板: 智能体
# ==========================================
class AgentSoulPanel(StaticPanel):
    def _setup_static_ui(self):
        paned = ttk.PanedWindow(self, orient="horizontal")
        paned.pack(fill="both", expand=True)

        self.tree = ttk.Treeview(paned, show="tree", selectmode="browse")
        self.tree.column("#0", width=280)
        paned.add(self.tree, weight=1)
        self.tree.bind("<<TreeviewSelect>>", self._on_select)
        self.tree.insert("", "end", iid="root", text="📂 工作区 (Workspace)", open=True)

        right_container = tk.Frame(paned, bg=UIStyleConfig.COLOR_BG_MAIN)
        paned.add(right_container, weight=4)
        
        self.v_path_lbl = tk.StringVar(value="请从左侧选择文件...")
        self.lbl_path = ttk.Label(right_container, textvariable=self.v_path_lbl, foreground="#666")
        self.lbl_path.pack(fill="x", pady=5, padx=10)
        
        txt_bg = tk.Frame(right_container, bg=UIStyleConfig.COLOR_BG_EDITOR)
        txt_bg.pack(fill="both", expand=True, padx=10)
        
        self.text = tk.Text(txt_bg, font=UIStyleConfig.FONT_CODE, 
                           bg=UIStyleConfig.COLOR_BG_EDITOR, fg="#333",
                           insertbackground="#333", undo=True, wrap="word", bd=0, padx=10, pady=10)
        self.text.pack(fill="both", expand=True)
        self.text.bind("<<Modified>>", self._on_modify)
        
        ttk.Button(right_container, text="💾 保存", style="Accent.TButton", command=self._save).pack(anchor="e", pady=5, padx=10)
        self.current_path_str = None
        self.loading_lock = False

    def sync_data(self):
        aid = self.manager.current_agent_id
        meta = self.manager.files_meta.get(aid, [])
        current_ids = set(self.tree.get_children("root"))
        target_ids = set()

        if meta:
            for fname, fpath, exists in meta:
                target_ids.add(fpath)
                is_in_buffer = fpath in self.manager.files_buffer
                icon = "📝" if is_in_buffer and not exists else ("📄" if exists else "⚪")
                txt = f" {icon} {fname}"
                # Diff Update: 只有文字不一样才刷新
                if self.tree.exists(fpath):
                    if self.tree.item(fpath, "text") != txt: self.tree.item(fpath, text=txt)
                else:
                    self.tree.insert("root", "end", iid=fpath, text=txt)
        else:
            target_ids.add("empty")
            if not self.tree.exists("empty"): self.tree.insert("root", "end", iid="empty", text="❌ (无数据)")

        for cid in current_ids:
            if cid not in target_ids: self.tree.delete(cid)

    def _on_select(self, e):
        sel = self.tree.selection()
        if not sel or "Workspace" in sel[0] or "root" in sel[0] or "empty" in sel[0]: return
        path_str = sel[0]
        
        if self.current_path_str and self.current_path_str != path_str:
             if self.text.edit_modified():
                self.manager.update_file_buffer(self.current_path_str, self.text.get("1.0", "end-1c"))
        
        self.current_path_str = path_str
        self.v_path_lbl.set(f"正在编辑: {Path(path_str).name}")
        content = self.manager.get_file_content(path_str)
        
        # Atomic Update: 文本框内容一致则不刷新
        if self.text.get("1.0", "end-1c") != content:
            self.loading_lock = True
            try: self.text.replace("1.0", "end", content)
            except: self.text.delete("1.0", "end"); self.text.insert("1.0", content)
            self.text.edit_modified(False)
            self.loading_lock = False

    def _on_modify(self, e):
        if not self.loading_lock and self.current_path_str:
            if self.text.edit_modified():
                self.manager.update_file_buffer(self.current_path_str, self.text.get("1.0", "end-1c"))
                self.text.edit_modified(False)

    def _save(self):
        if not self.current_path_str: return
        content = self.text.get("1.0", "end-1c")
        AsyncEngine.run(self.manager.save_file_sync, lambda s,r: messagebox.showinfo("结果", "已覆盖保存" if s else r), self.current_path_str, content)

# ==========================================
# 6. 面板: 技能
# ==========================================
class SkillsPanel(StaticPanel):
    def _setup_static_ui(self):
        self.tree = ttk.Treeview(self, columns=("n","s","st"), show="headings")
        self.tree.heading("n", text="技能名称"); self.tree.column("n", width=250)
        self.tree.heading("s", text="来源"); self.tree.column("s", width=100)
        self.tree.heading("st", text="状态"); self.tree.column("st", width=100)
        self.tree.pack(fill="both", expand=True, pady=(0, 10))
        self.tree.bind("<<TreeviewSelect>>", self._on_sel)

        f = ttk.LabelFrame(self, text="配置", padding=10)
        f.pack(fill="x")
        self.v_n = tk.StringVar(value="未选择")
        self.v_e = tk.BooleanVar()
        self.v_k = tk.StringVar()
        
        r1 = ttk.Frame(f); r1.pack(fill="x")
        ttk.Label(r1, textvariable=self.v_n, font=UIStyleConfig.FONT_BOLD).pack(side="left")
        ttk.Checkbutton(r1, text="启用", variable=self.v_e).pack(side="right")
        r2 = ttk.Frame(f); r2.pack(fill="x", pady=5)
        ttk.Label(r2, text="API Key:", font=UIStyleConfig.FONT_BODY).pack(side="left")
        ttk.Entry(r2, textvariable=self.v_k).pack(side="left", fill="x", expand=True, padx=10)
        ttk.Button(r2, text="💾 保存配置", style="Accent.TButton", command=self._save).pack(side="right")

    def sync_data(self):
        aid = self.manager.current_agent_id
        skills = self.manager.skills_cache.get(aid, {})
        entries = self.manager.get_val("skills.entries", {})
        current_items = set(self.tree.get_children())
        target_items = set()

        for name, info in skills.items():
            target_items.add(name)
            conf = entries.get(name, {})
            st = "✅ 已启用" if conf.get("enabled", True) else "⛔ 已禁用"
            if "apiKey" in conf: st += " 🔑"
            vals = (name, info['source'], st)
            if self.tree.exists(name):
                if self.tree.item(name, "values") != vals: self.tree.item(name, values=vals)
            else:
                self.tree.insert("", "end", iid=name, values=vals)
        for old in current_items:
            if old not in target_items: self.tree.delete(old)

    def _on_sel(self, e):
        sel = self.tree.selection()
        if not sel: return
        name = sel[0]
        self.v_n.set(name)
        conf = self.manager.get_val(f"skills.entries.{name}", {})
        self.v_e.set(conf.get("enabled", True))
        self.v_k.set(conf.get("apiKey", ""))

    def _save(self):
        name = self.v_n.get()
        if name == "未选择": return
        path = f"skills.entries.{name}"
        self.manager.set_val(f"{path}.enabled", self.v_e.get())
        if self.v_k.get(): self.manager.set_val(f"{path}.apiKey", self.v_k.get())
        if self.manager.save_config_sync():
            self.sync_data()
            messagebox.showinfo("成功", "保存完毕")

# ==========================================
# 7. 面板: 模型
# ==========================================
class ModelsPanel(StaticPanel):
    def _setup_static_ui(self):
        f = ttk.LabelFrame(self, text="🧠 核心模型", padding=15)
        f.pack(fill="x", pady=10)
        
        self.v_prim = tk.StringVar()
        self.v_img = tk.StringVar()
        self.v_thk = tk.StringVar()
        
        ttk.Label(f, text="主模型 (Primary):", font=UIStyleConfig.FONT_BODY).pack(anchor="w")
        ttk.Entry(f, textvariable=self.v_prim).pack(fill="x", pady=5)
        ttk.Label(f, text="视觉模型 (Image):", font=UIStyleConfig.FONT_BODY).pack(anchor="w")
        ttk.Entry(f, textvariable=self.v_img).pack(fill="x", pady=5)
        ttk.Label(f, text="思考等级 (Thinking):", font=UIStyleConfig.FONT_BODY).pack(anchor="w")
        ttk.Combobox(f, textvariable=self.v_thk, values=["off", "low", "high"], state="readonly").pack(fill="x")
        
        f2 = ttk.LabelFrame(self, text="🗣️ TTS 语音合成", padding=15)
        f2.pack(fill="x")
        self.v_tts = tk.StringVar()
        self.v_prov = tk.StringVar()
        
        r1 = ttk.Frame(f2); r1.pack(fill="x", pady=5)
        ttk.Label(r1, text="Auto:", width=10, font=UIStyleConfig.FONT_BODY).pack(side="left")
        ttk.Combobox(r1, textvariable=self.v_tts, values=["off", "always", "inbound"], state="readonly").pack(side="left", fill="x", expand=True)
        r2 = ttk.Frame(f2); r2.pack(fill="x", pady=5)
        ttk.Label(r2, text="Provider:", width=10, font=UIStyleConfig.FONT_BODY).pack(side="left")
        ttk.Combobox(r2, textvariable=self.v_prov, values=["elevenlabs", "openai"], state="readonly").pack(side="left", fill="x", expand=True)

        ttk.Button(self, text="💾 保存", style="Accent.TButton", command=self._save).pack(anchor="e", pady=20)

    def sync_data(self):
        SmartVar.set(self.v_prim, self.manager.get_val("agents.defaults.model.primary", ""))
        SmartVar.set(self.v_img, self.manager.get_val("agents.defaults.imageModel.primary", ""))
        SmartVar.set(self.v_thk, self.manager.get_val("agents.defaults.thinkingDefault", "off"))
        SmartVar.set(self.v_tts, self.manager.get_val("messages.tts.auto", "off"))
        SmartVar.set(self.v_prov, self.manager.get_val("messages.tts.provider", "elevenlabs"))

    def _save(self):
        self.manager.set_val("agents.defaults.model.primary", self.v_prim.get())
        self.manager.set_val("agents.defaults.imageModel.primary", self.v_img.get())
        self.manager.set_val("agents.defaults.thinkingDefault", self.v_thk.get())
        self.manager.set_val("messages.tts.auto", self.v_tts.get())
        self.manager.set_val("messages.tts.provider", self.v_prov.get())
        if self.manager.save_config_sync(): 
            self.sync_data()
            messagebox.showinfo("成功", "已保存")

# ==========================================
# 8. 面板: 渠道
# ==========================================
class ChannelsPanel(StaticPanel):
    def _setup_static_ui(self):
        f = ttk.Frame(self); f.pack(fill="x", pady=10)
        ttk.Label(f, text="选择渠道:", font=UIStyleConfig.FONT_BOLD).pack(side="left")
        self.v_ch = tk.StringVar()
        cb = ttk.Combobox(f, textvariable=self.v_ch, values=["whatsapp", "telegram", "discord", "slack"], state="readonly")
        cb.pack(side="left", padx=15); cb.bind("<<ComboboxSelected>>", self._on_ch)

        self.f_cfg = ttk.LabelFrame(self, text="详细参数", padding=15)
        self.f_cfg.pack(fill="x")
        self.v_en = tk.BooleanVar()
        self.v_tok = tk.StringVar()
        self.v_allow = tk.StringVar()
        
        ttk.Checkbutton(self.f_cfg, text="启用此渠道", variable=self.v_en).pack(anchor="w")
        ttk.Label(self.f_cfg, text="Token / Key:", font=UIStyleConfig.FONT_BODY).pack(anchor="w", pady=(10,0))
        ttk.Entry(self.f_cfg, textvariable=self.v_tok, show="•").pack(fill="x")
        ttk.Label(self.f_cfg, text="AllowList (comma):", font=UIStyleConfig.FONT_BODY).pack(anchor="w", pady=(10,0))
        ttk.Entry(self.f_cfg, textvariable=self.v_allow).pack(fill="x")
        
        ttk.Button(self.f_cfg, text="💾 保存", command=self._save).pack(anchor="e", pady=10)

    def sync_data(self):
        if not self.v_ch.get(): self.v_ch.set("telegram")
        self._on_ch(None)

    def _on_ch(self, e):
        ch = self.v_ch.get()
        d = self.manager.get_val(f"channels.{ch}", {})
        self.v_en.set(d.get("enabled", True))
        k = "token" if ch in ["discord"] else "botToken"
        SmartVar.set(self.v_tok, d.get(k, ""))
        al = d.get("allowFrom", [])
        SmartVar.set(self.v_allow, ",".join(al) if isinstance(al, list) else "")

    def _save(self):
        ch = self.v_ch.get()
        base = f"channels.{ch}"
        self.manager.set_val(f"{base}.enabled", self.v_en.get())
        k = "token" if ch in ["discord"] else "botToken"
        if self.v_tok.get(): self.manager.set_val(f"{base}.{k}", self.v_tok.get())
        raw = self.v_allow.get()
        if raw: self.manager.set_val(f"{base}.allowFrom", [x.strip() for x in raw.split(",") if x.strip()])
        if self.manager.save_config_sync(): messagebox.showinfo("成功", "保存完毕")

# ==========================================
# 9. 面板: 安全与网关
# ==========================================
class SecurityGatewayPanel(StaticPanel):
    def _setup_static_ui(self):
        g = ttk.Frame(self); g.pack(fill="both", expand=True)
        g.columnconfigure(0, weight=1); g.columnconfigure(1, weight=1)

        f_sec = ttk.LabelFrame(g, text="🔒 安全", padding=15)
        f_sec.grid(row=0, column=0, sticky="nsew", padx=(0,10))
        self.v_mode = tk.StringVar()
        for v,t in [("off", "Host (本机)"), ("non-main", "Non-Main"), ("all", "All (隔离)")]:
            ttk.Radiobutton(f_sec, text=t, value=v, variable=self.v_mode).pack(anchor="w")
        
        self.t_vars = {"group:fs":tk.BooleanVar(), "group:runtime":tk.BooleanVar(), "browser":tk.BooleanVar()}
        ttk.Label(f_sec, text="禁止工具:", foreground="red", font=UIStyleConfig.FONT_BODY).pack(anchor="w", pady=(10,0))
        for k,v in self.t_vars.items(): ttk.Checkbutton(f_sec, text=k, variable=v).pack(anchor="w")

        f_gw = ttk.LabelFrame(g, text="⚙️ 网关", padding=15)
        f_gw.grid(row=0, column=1, sticky="nsew", padx=(10,0))
        self.v_port = tk.IntVar()
        ttk.Label(f_gw, text="Port:", font=UIStyleConfig.FONT_BODY).pack(anchor="w")
        ttk.Entry(f_gw, textvariable=self.v_port).pack(fill="x")
        
        self.v_feat = {"browser.enabled":tk.BooleanVar(), "canvasHost.enabled":tk.BooleanVar(), "hooks.enabled":tk.BooleanVar()}
        ttk.Label(f_gw, text="高级服务:", font=UIStyleConfig.FONT_BOLD).pack(anchor="w", pady=(10,0))
        for k,v in self.v_feat.items(): ttk.Checkbutton(f_gw, text=k, variable=v).pack(anchor="w")

        ttk.Button(self, text="💾 保存", style="Accent.TButton", command=self._save).pack(anchor="e", pady=20)

    def sync_data(self):
        agent = self.manager.get_val("agents.list", [{}])[0]
        deny = self.manager.get_val("tools.deny", [])
        
        SmartVar.set(self.v_mode, agent.get("sandbox", {}).get("mode", "non-main"))
        for k,v in self.t_vars.items(): v.set(k in deny)
        self.v_port.set(self.manager.get_val("gateway.port", 18789))
        for k,v in self.v_feat.items(): v.set(self.manager.get_val(k, False))

    def _save(self):
        self.manager.set_val("agents.defaults.sandbox.mode", self.v_mode.get())
        dl = [k for k,v in self.t_vars.items() if v.get()]
        self.manager.set_val("tools.deny", dl)
        self.manager.set_val("gateway.port", self.v_port.get())
        for k,v in self.v_feat.items(): self.manager.set_val(k, v.get())
        if self.manager.save_config_sync(): messagebox.showinfo("成功", "保存完毕")

# ==========================================
# 10. 主窗口
# ==========================================
class OpenClawDashboard(tk.Tk):
    def __init__(self):
        super().__init__()
        AsyncEngine.set_root(self)
        UIStyleConfig.apply_global_styles(self)
        self.title("OpenClaw 高级管理 (中文版)")
        self.geometry(UIStyleConfig.WINDOW_SIZE)
        self.minsize(*UIStyleConfig.MIN_SIZE)
        
        # 移除 Windows 双缓冲 API，恢复原生极速模式
        self.data_mgr = OpenClawDataManager()
        
        self.loading_frame = ttk.Frame(self)
        self.loading_frame.place(relx=0, rely=0, relwidth=1, relheight=1)
        ttk.Label(self.loading_frame, text="🚀 正在启动...", font=UIStyleConfig.FONT_TITLE_L).place(relx=0.5, rely=0.45, anchor="center")
        self.pb = ttk.Progressbar(self.loading_frame, mode="indeterminate", length=300)
        self.pb.place(relx=0.5, rely=0.5, anchor="center")
        self.pb.start(10)
        
        self.main_frame = ttk.Frame(self)
        threading.Thread(target=self._startup_task, daemon=True).start()

    def _startup_task(self):
        self.data_mgr.preload_all_data()
        self.after(0, self._on_loaded)

    def _on_loaded(self):
        self.pb.stop()
        self.loading_frame.destroy()
        self.main_frame.pack(fill="both", expand=True)
        self._build_dashboard()

    def _build_dashboard(self):
        top = ttk.Frame(self.main_frame, padding=25)
        top.pack(fill="x")
        ttk.Label(top, text="🛠️", font=("Segoe UI Emoji", 28)).pack(side="left", padx=(0,15))
        f_ti = ttk.Frame(top); f_ti.pack(side="left")
        ttk.Label(f_ti, text="OpenClaw 控制中心", font=UIStyleConfig.FONT_TITLE_L).pack(anchor="w")
        ttk.Label(f_ti, text="智能体 / 模型 / 渠道 / 安全策略", font=UIStyleConfig.FONT_BODY, foreground="#888").pack(anchor="w")

        f_sel = ttk.Frame(top); f_sel.pack(side="right")
        ttk.Label(f_sel, text="当前智能体:", font=UIStyleConfig.FONT_BOLD).pack(side="left")
        self.cb = ttk.Combobox(f_sel, state="readonly", width=25, font=UIStyleConfig.FONT_BODY)
        self.cb.pack(side="left", padx=10)
        self.cb.bind("<<ComboboxSelected>>", self._on_switch_agent)

        self.nb = ttk.Notebook(self.main_frame)
        self.nb.pack(fill="both", expand=True, padx=25, pady=25)
        
        self.panels = {
            "soul": AgentSoulPanel(self.nb, self.data_mgr),
            "models": ModelsPanel(self.nb, self.data_mgr),
            "channels": ChannelsPanel(self.nb, self.data_mgr),
            "skills": SkillsPanel(self.nb, self.data_mgr),
            "sec": SecurityGatewayPanel(self.nb, self.data_mgr)
        }
        
        self.panel_list = [self.panels["soul"], self.panels["models"], self.panels["channels"], self.panels["skills"], self.panels["sec"]]
        
        self.nb.add(self.panels["soul"], text="🤖 核心记忆")
        self.nb.add(self.panels["models"], text="🧠 模型配置")
        self.nb.add(self.panels["channels"], text="🔌 渠道连接")
        self.nb.add(self.panels["skills"], text="⚡ 技能管理")
        self.nb.add(self.panels["sec"], text="🔒 安全与网关") 

        self.nb.bind("<<NotebookTabChanged>>", self._on_tab_change)

        agents = self.data_mgr.agent_list
        self.agent_ids = [a['id'] for a in agents]
        self.cb['values'] = [f"{a['id']} ({a.get('name','')})" for a in agents]
        if self.cb['values']: 
            self.cb.current(0)
            self.data_mgr.current_agent_id = self.agent_ids[0]
            self.panels["soul"].sync_data()

    def _on_tab_change(self, event):
        try:
            current_idx = self.nb.index("current")
            # 移除阻塞式刷新，完全交给事件循环
            panel = self.panel_list[current_idx]
            panel.sync_data()
        except: pass

    def _on_switch_agent(self, e):
        idx = self.cb.current()
        if idx < 0: return
        new_id = self.agent_ids[idx]
        
        if self.data_mgr.current_agent_id != new_id:
            self.data_mgr.current_agent_id = new_id
            def _switch_task():
                self.data_mgr.preload_all_data()
                return True
            def _switch_done(success, res):
                self._on_tab_change(None)
            AsyncEngine.run(_switch_task, _switch_done)

if __name__ == "__main__":
    app = OpenClawDashboard()
    app.mainloop()