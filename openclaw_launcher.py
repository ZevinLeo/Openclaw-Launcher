from tkinter import filedialog  # [新增] 用于弹出文件夹选择框
import shutil  # [新增] 用于检测 wt.exe 是否存在
import tkinter as tk
from tkinter import ttk, messagebox
import subprocess
import threading
import time
import sys
import ctypes
import os
import json
import traceback
import re
import urllib.request 
import webbrowser
import datetime
import shutil
from PIL import Image, ImageDraw, ImageFont, ImageTk

# ==========================================
# 0. 崩溃拦截与环境配置
# ==========================================
def show_critical_error(msg):
    try:
        ctypes.windll.user32.MessageBoxW(0, f"启动错误:\n\n{msg}", "Launcher Error", 0x10)
    except: pass
    sys.exit(1)

try:
    try:
        ctypes.windll.shcore.SetProcessDpiAwareness(1) 
    except: pass

    import sv_ttk
    import pystray
except Exception as e:
    show_critical_error(f"依赖库加载失败:\n{str(e)}\n\n请确保安装了: pip install sv-ttk pystray pillow")

# ==========================================
# 1. 权限检查
# ==========================================
def is_admin():
    try: return ctypes.windll.shell32.IsUserAnAdmin()
    except: return False

if not is_admin():
    try:
        current_exe = sys.executable
        if "python.exe" in current_exe:
            target_exe = current_exe.replace("python.exe", "pythonw.exe")
        else:
            target_exe = current_exe
        ctypes.windll.shell32.ShellExecuteW(None, "runas", target_exe, f'"{sys.argv[0]}"', None, 1)
        sys.exit()
    except Exception as e:
        show_critical_error(f"提权失败: {e}")

# ==========================================
# 2. 配置管理
# ==========================================
def get_config_path():
    app_data = os.getenv('LOCALAPPDATA')
    if not app_data:
        app_data = os.path.expanduser("~") 
    config_dir = os.path.join(app_data, "OpenClawLauncher")
    if not os.path.exists(config_dir):
        try: os.makedirs(config_dir)
        except: pass 
    return os.path.join(config_dir, "config.json")

CONFIG_FILE = get_config_path()

def load_config():
    default_conf = {"minimize_to_tray": False, "install_info": None} 
    if not os.path.exists(CONFIG_FILE): return default_conf
    try:
        with open(CONFIG_FILE, "r", encoding="utf-8") as f: return json.load(f)
    except: return default_conf

def save_config(config_data):
    try:
        with open(CONFIG_FILE, "w", encoding="utf-8") as f: json.dump(config_data, f, indent=4)
    except: pass

# ==========================================
# 3. 状态灯组件
# ==========================================
class StatusLight(tk.Canvas):
    def __init__(self, parent, size=14):
        super().__init__(parent, width=size, height=size, highlightthickness=0, borderwidth=0)
        self.indicator = self.create_oval(1, 1, size-1, size-1, fill="#adb5bd", outline="")
    
    def set_color(self, color):
        self.itemconfig(self.indicator, fill=color)

# ==========================================
# 4. 日志组件
# ==========================================
class ModernLog(ttk.Frame):
    def __init__(self, parent, **kwargs):
        super().__init__(parent)
        self.pack(fill="both", expand=True)
        self.v_scroll = ttk.Scrollbar(self, orient="vertical")
        self.v_scroll.pack(side="right", fill="y")
        
        self.text = tk.Text(
            self, 
            yscrollcommand=self.v_scroll.set, 
            wrap="word", 
            font=("Consolas", 10), 
            spacing1=2, 
            padx=5, pady=5, 
            borderwidth=0, 
            highlightthickness=0, 
            takefocus=0, 
            bg="#f6f6f6",  
            fg="#333333",
            **kwargs
        )
        self.text.pack(side="left", fill="both", expand=True)
        self.v_scroll.config(command=self.text.yview)
        
        self.text.tag_config('INFO', foreground='#555555')
        self.text.tag_config('ERROR', foreground='#d32f2f', font=("Consolas", 10, "bold")) 
        self.text.tag_config('SUCCESS', foreground='#107c10', font=("Consolas", 10, "bold")) 
        self.text.tag_config('CMD', foreground='#005a9e') 
        self.text.tag_config('DEBUG', foreground='#999999') 

    def insert(self, *args):
        self.text.config(state='normal')
        self.text.insert(*args)
        self.text.see(tk.END)
        self.text.config(state='disabled')
        self.text.update_idletasks() 

    def see(self, *args):
        self.text.see(*args)

    def set_performance_mode(self, enabled):
        pass 

# ==========================================
# 5. 主程序
# ==========================================
class UniversalLauncher:
    def __init__(self, root):
        self.root = root
        
        self.root.geometry("1100x900")
        self.root.minsize(1100, 900)
        
        self._ui_suspended = False  
        self._log_buffer = []       
        self._resize_timer = None   
        
        self.config = load_config()
        try: sv_ttk.set_theme("light")
        except: pass

        try:
            icon_img = self.create_tray_image()
            self.icon_photo = ImageTk.PhotoImage(icon_img)
            self.root.iconphoto(True, self.icon_photo)
        except: pass

        self.proc_gateway = None
        self.proc_node = None
        self.gateway_ready = False
        self.node_connected_flag = False
        self.is_quitting = False 
        self.programmatic_action = False

        self.f_title = ("Microsoft YaHei UI", 12, "bold") 
        self.f_body = ("Microsoft YaHei UI", 11)          
        self.f_small = ("Microsoft YaHei UI", 10)         
        self.f_emoji = ("Segoe UI Emoji", 14)
        
        self.status_gw_text = tk.StringVar(value="未运行")
        self.status_node_text = tk.StringVar(value="未运行")
        self.ui_cache = {"gw_color": "#adb5bd", "gw_style": "StatusGray.TLabel", "node_color": "#adb5bd", "node_style": "StatusGray.TLabel"}

        self.apply_styles()

        self.top_frame = ttk.Frame(root, padding=25)
        self.top_frame.pack(side=tk.TOP, fill=tk.X)

        self.bottom_frame = ttk.Frame(root, padding=(25, 0, 25, 25))
        self.bottom_frame.pack(side=tk.BOTTOM, fill=tk.BOTH, expand=True)

        lbl_log = tk.Label(
            self.bottom_frame, 
            text=" 运行日志", 
            font=("Microsoft YaHei UI", 10, "bold"), 
            bg="#e0e0e0", 
            fg="#333333", 
            anchor="w", 
            padx=10, pady=6, relief="flat"
        )
        lbl_log.pack(fill="x", pady=(0, 0))
        
        self.txt_system = ModernLog(self.bottom_frame)
        
        self.cli_cmd = None 
        self.version_number_var = tk.StringVar(value="检测中...") 
        self.version_type_var = tk.StringVar(value="")
        self.has_opened_dashboard = False
        self.status_gw_style = "StatusGray.TLabel"
        self.status_node_style = "StatusGray.TLabel"
        
        self.setup_dashboard(self.top_frame)

        self.root.title("OpenClaw 通用启动器")

        try: self.setup_tray_icon()
        except: pass
        
        self.monitor_thread = threading.Thread(target=self.monitor_loop, daemon=True)
        self.monitor_thread.start()
        
        self.root.bind("<Unmap>", self.on_minimize_event)
        self.root.bind("<Configure>", self.on_resize_event)
        self.root.protocol("WM_DELETE_WINDOW", self.on_close_click)

        threading.Thread(target=self._async_detect_sequence, daemon=True).start()

    # ==========================================
    #  核心: 工具函数
    # ==========================================
    def _safe_cwd(self):
        try:
            home = os.path.expanduser("~")
            if os.path.isdir(home): return home
            return "C:\\"
        except: return "C:\\"

    def _check_node_installed(self):
        try:
            startupinfo = subprocess.STARTUPINFO()
            startupinfo.dwFlags |= subprocess.STARTF_USESHOWWINDOW
            subprocess.run(["node", "-v"], stdout=subprocess.PIPE, stderr=subprocess.PIPE, check=True, startupinfo=startupinfo, creationflags=subprocess.CREATE_NO_WINDOW, cwd=self._safe_cwd())
            return True
        except: return False

    # ==========================================
    #  核心: 备份功能
    # ==========================================
    def _backup_user_data(self, target_root=None):
        """ 备份数据到指定目录或默认桌面目录 """
        try:
            home = os.path.expanduser("~") 
            source_root = os.path.join(home, ".openclaw")
            
            if not os.path.exists(source_root):
                self.log(self.txt_system, "未找到 .openclaw 文件夹，跳过备份。", "INFO")
                return

            # 1. 确定备份根目录
            if not target_root:
                # [修改] 默认路径改为桌面 (Desktop)
                target_root = os.path.join(home, "Desktop", "OpenClaw_Backups")
            
            # 2. 创建带时间戳的子文件夹
            timestamp = datetime.datetime.now().strftime("%Y%m%d_%H%M%S")
            dest_dir = os.path.join(target_root, f"Backup_{timestamp}")
            
            os.makedirs(dest_dir, exist_ok=True)
            self.log(self.txt_system, f"正在创建备份: {dest_dir}", "CMD")

            # 扩展了备份列表，包含 cron, credentials, devices
            items_to_backup = [
                "openclaw.json", 
                "agents", 
                "workspace", 
                "cron", 
                "credentials", 
                "devices"
            ]
            
            backed_up_count = 0
            for item in items_to_backup:
                s_path = os.path.join(source_root, item)
                d_path = os.path.join(dest_dir, item)
                
                if os.path.exists(s_path):
                    try:
                        if os.path.isdir(s_path):
                            shutil.copytree(s_path, d_path)
                        else:
                            shutil.copy2(s_path, d_path)
                        self.log(self.txt_system, f"已备份: {item}", "SUCCESS")
                        backed_up_count += 1
                    except Exception as e:
                        self.log(self.txt_system, f"备份 {item} 失败: {e}", "ERROR")
            
            if backed_up_count > 0:
                self.log(self.txt_system, "备份流程完成。", "SUCCESS")
                messagebox.showinfo("备份完成", f"已成功备份配置文件至：\n\n{dest_dir}")
            else:
                self.log(self.txt_system, "未发现可备份的配置文件。", "INFO")
                try: os.rmdir(dest_dir) 
                except: pass
                
        except Exception as e:
            self.log(self.txt_system, f"备份过程发生严重错误: {e}", "ERROR")
            messagebox.showerror("备份失败", f"无法执行备份: {e}")

    # ==========================================
    #  核心: 命令生成器
    # ==========================================
    def _get_cmd_by_method(self, core, method, is_update=False):
        bash_flags = " -s -- --no-onboard" if is_update else ""

        if core == "openclaw":
            if method == "script_ps": 
                return 'powershell -Command "iwr -useb https://openclaw.ai/install.ps1 | iex"'
            elif method == "script_bash": 
                return f"curl -fsSL https://openclaw.ai/install.sh | bash{bash_flags}"
            elif method == "npm":
                return "npm i -g openclaw" if not is_update else "npm i -g openclaw@latest"
            elif method == "pnpm":
                return "pnpm add -g openclaw" if not is_update else "pnpm add -g openclaw@latest"

        elif core == "openclaw-cn":
            if method == "script_ps": 
                return 'powershell -Command "iwr -useb https://clawd.org.cn/install.ps1 | iex"'
            elif method == "script_bash": 
                return f"curl -fsSL https://clawd.org.cn/install.sh | bash{bash_flags}"
            elif method == "npm":
                if is_update:
                    return "npm i -g openclaw-cn@latest --registry=https://registry.npmmirror.com"
                else:
                    return "npm install -g openclaw-cn@latest"
            elif method == "pnpm":
                return "pnpm add -g openclaw-cn@latest" 
        
        return ""

    # ==========================================
    #  核心: 异步检测
    # ==========================================
    def _async_detect_sequence(self):
        if self._check_version_with_cmd("openclaw"):
            self.root.after(0, lambda: self._update_ui_after_detect("openclaw", self.version_number))
            return
        if self._check_version_with_cmd("openclaw-cn"):
            self.root.after(0, lambda: self._update_ui_after_detect("openclaw-cn", self.version_number))
            return
        self.root.after(0, lambda: self._update_ui_after_detect(None, "未安装"))
        self.root.after(500, self._show_install_wizard)

    def _update_ui_after_detect(self, cmd_found, ver_num):
        self.version_number_var.set(ver_num)
        
        if cmd_found:
            self.btn_start.config(state="normal")
            self.btn_stop.config(state="normal")
            self.btn_web.config(state="normal")
            self.btn_uninstall.config(state="normal")
            
            if cmd_found == "openclaw-cn":
                self.cli_cmd = "openclaw-cn"
                self.version_type_var.set("(OpenClaw-CN)")
                self.lbl_ver_type.config(foreground="#ff4500") 
                self.root.title(f"OpenClaw-CN 启动器 ({ver_num})")
                self.log(self.txt_system, f"核心就绪: openclaw-cn (版本 {ver_num})", "SUCCESS")
            elif cmd_found == "openclaw":
                self.cli_cmd = "openclaw"
                self.version_type_var.set("(OpenClaw)")
                self.lbl_ver_type.config(foreground="#00b7c3")
                self.root.title(f"OpenClaw 启动器 ({ver_num})")
                self.log(self.txt_system, f"核心就绪: openclaw (版本 {ver_num})", "SUCCESS")
        else:
            self.btn_start.config(state="disabled")
            self.btn_stop.config(state="disabled")
            self.btn_web.config(state="disabled")
            self.btn_uninstall.config(state="disabled")
            
            self.cli_cmd = None
            self.version_type_var.set("(未检测到核心)")
            self.lbl_ver_type.config(foreground="red")

    def _check_version_with_cmd(self, cmd_name):
        startupinfo = subprocess.STARTUPINFO()
        startupinfo.dwFlags |= subprocess.STARTF_USESHOWWINDOW
        try:
            cmd_list = ["cmd", "/c", f"{cmd_name} --version"]
            result = subprocess.run(
                cmd_list, capture_output=True, text=True, shell=False, 
                encoding='utf-8', errors='ignore', 
                creationflags=subprocess.CREATE_NO_WINDOW, startupinfo=startupinfo, timeout=15, cwd=self._safe_cwd()
            )
            if result.returncode == 0 and result.stdout:
                output = result.stdout.strip()
                pattern = r"v?(\d+\.\d+\.\d+(?:-[\w\d]+)?)"
                match = re.search(pattern, output)
                if match:
                    self.version_number = match.group(1) 
                    return True
                if len(output) > 0 and len(output) < 30: 
                      self.version_number = output.replace("v", "").strip()
                      return True
        except: pass
        return False

    # ==========================================
    #  核心: 更新序列执行器
    # ==========================================
    def _run_update_sequence(self, update_cmd, core_name):
        self.log(self.txt_system, ">>> 开始执行自动化更新队列...", "CMD")
        self.log(self.txt_system, f"[1/3] 正在更新 {core_name}...", "INFO")
        self._launch_blocking_window(update_cmd, f"{core_name} Updater")
        self.log(self.txt_system, "[2/3] 正在运行诊断程序 (Doctor)...", "INFO")
        doctor_cmd = f"{core_name} doctor"
        self._launch_blocking_window(doctor_cmd, f"{core_name} Doctor", is_simple_cmd=True)
        self.log(self.txt_system, "[3/3] 正在验证服务状态...", "INFO")
        status_cmd = f"{core_name} status"
        self._launch_blocking_window(status_cmd, f"{core_name} Status", is_simple_cmd=True)
        self.log(self.txt_system, "更新流程完成，正在刷新状态...", "SUCCESS")
        time.sleep(2)
        self._async_detect_sequence()

    # ==========================================
    #  核心: 卸载/清理逻辑 (UI修正)
    # ==========================================
    def _show_uninstall_dialog(self):
        if not self.cli_cmd: return

        dlg = tk.Toplevel(self.root)
        dlg.withdraw() # 1. 立即隐藏，幕后布局
        
        dlg.title("卸载 OpenClaw")
        dlg.minsize(500, 0) # 宽度保持 500

        container = ttk.Frame(dlg, padding=20)
        container.pack(fill="both", expand=True)

        ttk.Label(container, text="请选择卸载方式", font=("Microsoft YaHei UI", 12, "bold")).pack(pady=(0, 15))

        # --- 模块 1: 备份配置 ---
        f_backup = ttk.Labelframe(container, text="备份配置", padding=10)
        f_backup.pack(fill="x", pady=5)

        # [修改] 默认路径改为桌面 (Desktop)
        default_backup_path = os.path.join(os.path.expanduser("~"), "Desktop", "OpenClaw_Backups")
        
        self.var_backup_enabled = tk.BooleanVar(value=True)
        self.var_backup_path = tk.StringVar(value=default_backup_path)

        row1 = ttk.Frame(f_backup)
        row1.pack(fill="x")
        
        style = ttk.Style()
        style.configure("Uninstall.TCheckbutton", font=("Microsoft YaHei UI", 10), foreground="#333333")
        
        chk = ttk.Checkbutton(row1, text="卸载前自动备份", variable=self.var_backup_enabled, style="Uninstall.TCheckbutton")
        chk.pack(side="left")

        def choose_dir():
            path = filedialog.askdirectory(initialdir=self.var_backup_path.get(), title="选择备份保存位置")
            if path: self.var_backup_path.set(path)

        btn_browse = ttk.Button(row1, text="📂 修改路径", width=10, command=choose_dir)
        btn_browse.pack(side="right")

        # 初始排版
        lbl_path = ttk.Label(f_backup, textvariable=self.var_backup_path, 
                             foreground="#555555", font=("Microsoft YaHei UI", 9),
                             wraplength=450) 
        lbl_path.pack(anchor="w", pady=(5, 0), fill="x")

        def on_label_resize(event):
            if event.width > 10:
                lbl_path.config(wraplength=event.width - 10)
        
        lbl_path.bind("<Configure>", on_label_resize)

        # --- 模块 2: 常规卸载 ---
        f1 = ttk.Labelframe(container, text="常规卸载 (推荐)", padding=10)
        f1.pack(fill="x", pady=10)
        
        lbl1 = ttk.Label(f1, text=f"运行 {self.cli_cmd} uninstall\n保留部分配置文件。", 
                         foreground="#555", justify="left", font=("Microsoft YaHei UI", 10))
        lbl1.pack(anchor="w")
        
        def run_standard_uninstall():
            if messagebox.askokcancel("确认卸载", f"即将运行: {self.cli_cmd} uninstall\n\n确定要继续吗？"):
                dlg.destroy()
                if self.var_backup_enabled.get():
                    self._backup_user_data(self.var_backup_path.get())
                
                self.log(self.txt_system, "正在启动常规卸载程序...", "INFO")
                cmd_str = f"{self.cli_cmd} uninstall"
                threading.Thread(target=self._run_uninstall_sequence, args=(cmd_str,), daemon=True).start()

        ttk.Button(f1, text="执行常规卸载", command=run_standard_uninstall).pack(fill="x", pady=(10, 0))

        # --- 模块 3: 强力清理 ---
        f2 = ttk.Labelframe(container, text="强力清理 (Force Clean)", padding=10)
        f2.pack(fill="x", pady=5)
        
        lbl2 = ttk.Label(f2, text="强制移除 NPM/PNPM 全局包及残留文件。\n适用于常规卸载失败的情况。", 
                         foreground="#555555", justify="left", font=("Microsoft YaHei UI", 10))
        lbl2.pack(anchor="w")

        def run_force_clean():
            if messagebox.askyesno("高风险操作", "此操作将强制调用 npm/pnpm 移除命令，并物理删除可能残留的脚本文件。\n\n仅建议在常规卸载失效时使用。\n是否继续？"):
                dlg.destroy()
                if self.var_backup_enabled.get():
                    self._backup_user_data(self.var_backup_path.get())
                self._perform_force_clean() 

        ttk.Button(f2, text="执行强力清理", style="Stop.TButton", command=run_force_clean).pack(fill="x", pady=(10, 0))

        # 2. 强制全量刷新 (渲染字体和布局)
        dlg.update()
        
        # 3. 计算居中
        w = dlg.winfo_reqwidth()
        h = dlg.winfo_reqheight()
        x = self.root.winfo_x() + (self.root.winfo_width() // 2) - (w // 2)
        y = self.root.winfo_y() + (self.root.winfo_height() // 2) - (h // 2)
        dlg.geometry(f"+{x}+{y}")
        
        # 4. 瞬间显示
        dlg.deiconify()
        dlg.focus_force()

    def _run_uninstall_sequence(self, cmd_str):
        self._launch_blocking_window(cmd_str, "OpenClaw Uninstaller", is_simple_cmd=True)
        self.log(self.txt_system, "卸载流程结束，正在重新检测系统状态...", "INFO")
        time.sleep(2)
        self._async_detect_sequence() 

    def _perform_force_clean(self):
        self.log(self.txt_system, "正在执行强力清理...", "CMD")
        
        commands = [
            "npm uninstall -g openclaw",
            "npm uninstall -g openclaw-cn",
            "pnpm remove -g openclaw",
            "pnpm remove -g openclaw-cn"
        ]
        
        try:
            appdata = os.getenv('APPDATA') 
            if appdata:
                npm_path = os.path.join(appdata, "npm")
                files_to_check = ["openclaw", "openclaw.cmd", "openclaw.ps1", "openclaw-cn", "openclaw-cn.cmd", "openclaw-cn.ps1"]
                for f in files_to_check:
                    target = os.path.join(npm_path, f)
                    if os.path.exists(target):
                        try:
                            os.remove(target)
                            self.log(self.txt_system, f"已删除残留文件: {target}", "SUCCESS")
                        except: pass
        except: pass

        def _clean_thread():
            startupinfo = subprocess.STARTUPINFO()
            startupinfo.dwFlags |= subprocess.STARTF_USESHOWWINDOW
            for cmd in commands:
                try:
                    subprocess.run(["cmd", "/c", cmd], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL, creationflags=subprocess.CREATE_NO_WINDOW, startupinfo=startupinfo)
                except: pass
            
            self.log(self.txt_system, "清理指令已执行。", "SUCCESS")
            messagebox.showinfo("完成", "强力清理已完成，正在刷新状态...")
            self._async_detect_sequence()

        threading.Thread(target=_clean_thread, daemon=True).start()

    # ==========================================
    #  核心: 安装向导
    # ==========================================
    def _show_install_wizard(self):
        # 防止重复打开
        if hasattr(self, '_wizard_window') and self._wizard_window.winfo_exists():
            self._wizard_window.lift()
            return

        style = ttk.Style()
        # 设置 Tab 标签样式，保证文字居中和粗体
        style.configure("Wizard.TNotebook.Tab", font=("Microsoft YaHei UI", 10, "bold"), width=36, padding=[5, 5], anchor="center")

        wizard = tk.Toplevel(self.root)
        self._wizard_window = wizard 
        
        # [修改 1] 立即隐藏，防止闪烁
        wizard.withdraw()
        
        wizard.title("OpenClaw 安装向导")
        
        # [修改 2] 移除固定 geometry，改用 minsize
        wizard.minsize(580, 0)
        
        container = ttk.Frame(wizard, padding=20)
        container.pack(fill="both", expand=True)

        # --- 头部提示区 ---
        header_frame = ttk.Frame(container)
        header_frame.pack(fill="x", pady=(0, 15))
        ttk.Label(header_frame, text="⚠️ 未检测到核心程序", font=("Microsoft YaHei UI", 14, "bold"), foreground="black").pack(anchor="w")
        ttk.Label(header_frame, text="要运行此启动器，您需要先安装 OpenClaw 核心服务。", font=("Microsoft YaHei UI", 10), foreground="#666").pack(anchor="w", pady=(5,0))

        # --- 安装逻辑闭包 ---
        def _do_install(core, method):
            if not self._check_node_installed():
                if messagebox.askyesno("缺少必要依赖", "⚠️ 检测到系统未安装 Node.js 环境。\n\nOpenClaw 必须依赖 Node.js 才能运行。\n是否立即前往官网下载安装？"):
                    webbrowser.open("https://nodejs.org/zh-cn/download/prebuilt-installer")
                return
            cmd = self._get_cmd_by_method(core, method, is_update=False)
            if not cmd: return
            wizard.destroy()
            self.config["install_info"] = {"core": core, "method": method}
            save_config(self.config)
            threading.Thread(target=self._run_install_sequence, args=(cmd, core), daemon=True).start()

        # --- Tab 分页区 ---
        notebook = ttk.Notebook(container, style="Wizard.TNotebook")
        notebook.pack(fill="both", expand=True, pady=10)

        # 辅助函数：创建安装选项行
        def create_row(parent, btn_text, btn_cmd, desc_text, is_primary=False):
            f = ttk.Frame(parent)
            f.pack(fill="x", pady=3)
            style = "Accent.TButton" if is_primary else "TButton"
            # 统一按钮宽度
            btn = ttk.Button(f, text=btn_text, command=btn_cmd, style=style, width=24)
            btn.pack(side="left", padx=(5, 10))
            color = "#2f9e44" if is_primary else "#666666"
            weight = "bold" if is_primary else "normal"
            lbl = ttk.Label(f, text=desc_text, foreground=color, font=("Microsoft YaHei UI", 9, weight))
            lbl.pack(side="left", anchor="center")

        # >>> Tab 1: 原版 <<<
        tab_org = ttk.Frame(notebook, padding=15)
        notebook.add(tab_org, text=" OpenClaw (原版) ")
        ttk.Label(tab_org, text="OpenClaw Official", font=("Microsoft YaHei UI", 12, "bold"), foreground="#0078d4").pack(anchor="w")
        ttk.Label(tab_org, text="推荐。更新最快，功能最新。", font=("Microsoft YaHei UI", 10), foreground="#555").pack(anchor="w", pady=(5, 10))
        
        create_row(tab_org, "Windows (PowerShell)", lambda: _do_install("openclaw", "script_ps"), "Windows 首选推荐 (iwr)", True)
        create_row(tab_org, "Linux/Mac (Bash)", lambda: _do_install("openclaw", "script_bash"), "curl ... | bash")
        create_row(tab_org, "NPM 全局安装", lambda: _do_install("openclaw", "npm"), "npm i -g openclaw")
        create_row(tab_org, "PNPM 全局安装", lambda: _do_install("openclaw", "pnpm"), "pnpm add -g openclaw")

        # >>> Tab 2: 汉化版 <<<
        tab_cn = ttk.Frame(notebook, padding=15)
        notebook.add(tab_cn, text=" OpenClaw-CN (汉化版) ")
        ttk.Label(tab_cn, text="OpenClaw CN Community", font=("Microsoft YaHei UI", 12, "bold"), foreground="#ff4500").pack(anchor="w")
        ttk.Label(tab_cn, text="社区维护。全中文界面，优化国内网络。", font=("Microsoft YaHei UI", 10), foreground="#555").pack(anchor="w", pady=(5, 10))
        
        create_row(tab_cn, "Windows (PowerShell)", lambda: _do_install("openclaw-cn", "script_ps"), "Windows 首选推荐 (iwr)", True)
        create_row(tab_cn, "Linux/Mac (Bash)", lambda: _do_install("openclaw-cn", "script_bash"), "curl ... | bash")
        create_row(tab_cn, "NPM 全局安装", lambda: _do_install("openclaw-cn", "npm"), "npm install -g openclaw-cn@latest")
        create_row(tab_cn, "PNPM 全局安装", lambda: _do_install("openclaw-cn", "pnpm"), "pnpm add -g openclaw-cn@latest")

        # [修改 3] 强制计算布局并居中
        wizard.update() 
        
        w = wizard.winfo_reqwidth()
        h = wizard.winfo_reqheight()
        x = self.root.winfo_x() + (self.root.winfo_width() // 2) - (w // 2)
        y = self.root.winfo_y() + (self.root.winfo_height() // 2) - (h // 2)
        
        wizard.geometry(f"+{x}+{y}")
        
        # [修改 4] 显示窗口
        wizard.lift()
        wizard.deiconify() 
        wizard.focus_force()
    # ==========================================
    #  核心: 安装序列执行器
    # ==========================================
    def _run_install_sequence(self, install_cmd, core_name):
        self.log(self.txt_system, ">>> 开始执行自动化安装队列...", "CMD")
        
        self.log(self.txt_system, "[1/3] 正在运行安装程序...", "INFO")
        self._launch_blocking_window(install_cmd, f"{core_name} Installer")
        
        self.log(self.txt_system, "[2/3] 正在运行初始化 (setup)...", "INFO")
        setup_cmd = f"{core_name} setup"
        self._launch_blocking_window(setup_cmd, f"{core_name} Setup", is_simple_cmd=True)
        
        self.log(self.txt_system, "[3/3] 正在运行首次配置 (onboard)...", "INFO")
        onboard_cmd = f"{core_name} onboard"
        self._launch_blocking_window(onboard_cmd, f"{core_name} Onboarding", is_simple_cmd=True)

        self.log(self.txt_system, "自动化队列执行完毕，正在刷新状态...", "SUCCESS")
        time.sleep(2)
        self._async_detect_sequence()

    def _launch_blocking_window(self, cmd_str, title, is_simple_cmd=False):
        """
        v1.33 智能分流启动：
        1. 自动检测是否安装 Windows Terminal (WT)。
        2. 自动识别指令类型 (CMD vs PowerShell)。
        3. 自动调用 WT 对应的配置文件 (Command Prompt vs Windows PowerShell)。
        """
        try:
            self.log(self.txt_system, f"正在启动外部任务: {title}", "DEBUG")
            
            wt_path = shutil.which("wt")
            
            # [关键逻辑] 智能识别命令类型
            is_powershell = "powershell" in cmd_str.lower()
            
            # 清洗命令字符串，提取核心执行部分
            clean_cmd = cmd_str
            if is_powershell:
                 clean_cmd = cmd_str.replace("powershell -Command", "").replace("powershell", "").strip().strip('"')
            elif "cmd /c" in cmd_str.lower():
                 clean_cmd = cmd_str.replace("cmd /c", "").strip().strip('"')

            # ====================================================
            # 方案 A: Windows Terminal (智能匹配 Profile)
            # ====================================================
            if wt_path:
                # 根据类型决定调用哪个配置文件
                if is_powershell:
                    profile_name = "Windows PowerShell" # 对应蓝色图标
                    shell_exec = ["powershell", "-NoExit", "-Command", clean_cmd]
                    self.log(self.txt_system, "调用 WT -> PowerShell 配置文件", "INFO")
                else:
                    profile_name = "Command Prompt"     # 对应黑色图标
                    # cmd /k 表示执行完不关闭窗口
                    shell_exec = ["cmd", "/k", f"{clean_cmd}"]
                    self.log(self.txt_system, "调用 WT -> Command Prompt 配置文件", "INFO")

                # 构造 WT 参数
                # -p 指定配置文件名
                final_args = ["wt", "-w", "0", "new-tab", "--title", title, "-p", profile_name] + shell_exec
                
                subprocess.Popen(final_args, shell=True, cwd=self._safe_cwd())
                
                # 模态弹窗卡住主进程，等待用户在 WT 中操作完成
                messagebox.showinfo(
                    "正在运行", 
                    f"任务 [{title}] 正在 Windows Terminal ({profile_name}) 中运行...\n\n请等待代码跑完后，\n再点击下方的【确定】继续下一步。"
                )
                
                self.log(self.txt_system, f"任务已确认完成: {title}", "SUCCESS")
                return

            # ====================================================
            # 方案 B: 原生窗口回退 (没有 WT 时)
            # ====================================================
            self.log(self.txt_system, "未检测到 WT，回退至原生窗口...", "INFO")
            
            if is_powershell:
                # 强制用蓝色 PS 窗口
                legacy_cmd = f'start /wait "{title}" powershell -NoExit -Command "{clean_cmd}"'
            else:
                # 强制用黑色 CMD 窗口
                legacy_cmd = f'start /wait "{title}" cmd /c "{clean_cmd} & pause"'
                
            subprocess.run(legacy_cmd, shell=True, cwd=self._safe_cwd())
            
            self.log(self.txt_system, f"任务窗口已关闭: {title}", "INFO")

        except Exception as e:
            self.log(self.txt_system, f"启动窗口失败: {e}", "ERROR")
            messagebox.showerror("执行错误", f"无法启动安装窗口: {e}")

    # ==========================================
    #  核心: 日志与更新
    # ==========================================
    def log(self, widget, msg, level="INFO"):
        tag_map = {"INFO": "INFO", "ERROR": "ERROR", "SUCCESS": "SUCCESS", "CMD": "CMD", "DEBUG": "DEBUG"}
        tag = tag_map.get(level, "INFO")
        timestamp = datetime.datetime.now().strftime("[%H:%M:%S]")
        full_msg = f"{timestamp} {msg}\n"
        def _update():
            try:
                if hasattr(widget, 'insert'):
                    widget.insert(tk.END, full_msg, tag)
                    widget.see(tk.END)
                else: print(f"[Console] {full_msg.strip()}")
            except: pass
        self.root.after(0, _update)

    def check_for_updates(self):
        threading.Thread(target=self._check_remote_version_thread, daemon=True).start()

    def _check_remote_version_thread(self):
        try:
            if not self.cli_cmd:
                self.root.after(0, lambda: self._show_update_dialog_manual(None))
                return
            local_ver = self.version_number_var.get()
            pkg_name = self.cli_cmd 
            self.log(self.txt_system, f"正在连接云端检查 {pkg_name} ...", "INFO")
            cmd = ["cmd", "/c", f"npm view {pkg_name} version"]
            startupinfo = subprocess.STARTUPINFO()
            startupinfo.dwFlags |= subprocess.STARTF_USESHOWWINDOW
            process = subprocess.run(cmd, capture_output=True, text=True, encoding='utf-8', errors='ignore', creationflags=subprocess.CREATE_NO_WINDOW, startupinfo=startupinfo, timeout=8, cwd=self._safe_cwd())
            remote_ver = process.stdout.strip()
            if not remote_ver or process.returncode != 0:
                self.log(self.txt_system, "获取云端版本失败 (可能未安装 npm)。", "ERROR")
                self.root.after(0, lambda: self._ask_force_update(local_ver, "未知"))
                return
            self.log(self.txt_system, f"云端最新版本: {remote_ver}", "INFO")
            if remote_ver != local_ver:
                self.root.after(0, lambda: self._ask_update_confirm(local_ver, remote_ver))
            else:
                self.root.after(0, lambda: self._ask_reinstall_confirm(local_ver))
        except subprocess.TimeoutExpired:
            self.log(self.txt_system, "连接超时，无法获取最新版本。", "ERROR")
            self.root.after(0, lambda: self._ask_force_update(local_ver, "超时"))
        except Exception as e:
            self.log(self.txt_system, f"版本检查错误: {e}", "ERROR")
            self.root.after(0, lambda: self._show_update_dialog_manual(None))

    def _ask_update_confirm(self, local, remote):
        msg = f"发现新版本！\n\n本地版本: {local}\n最新版本: {remote}\n\n是否立即更新？"
        if messagebox.askyesno("版本更新", msg):
            self._trigger_auto_update()

    def _ask_reinstall_confirm(self, local):
        msg = f"当前已是最新版本 ({local})。\n\n是否要强制重新安装/修复？"
        if messagebox.askyesno("已是最新", msg):
            self._trigger_auto_update()

    def _ask_force_update(self, local, remote):
        msg = f"无法检测最新版本 (可能未安装 npm)。\n本地版本: {local}\n\n是否强制执行更新命令？"
        if messagebox.askyesno("检查失败", msg):
            self._trigger_auto_update()

    def _trigger_auto_update(self):
        install_info = self.config.get("install_info")
        if install_info and install_info.get("core") == self.cli_cmd:
            method = install_info.get("method")
            update_cmd = self._get_cmd_by_method(self.cli_cmd, method, is_update=True)
            if update_cmd:
                self.log(self.txt_system, "正在执行原地更新...", "INFO")
                threading.Thread(target=self._run_update_sequence, args=(update_cmd, self.cli_cmd), daemon=True).start()
                return
        self._show_update_dialog_manual(None)

    def _show_update_dialog_manual(self, output):
        update_win = tk.Toplevel(self.root)
        update_win.title("版本更新/修复")
        update_win.geometry("620x520") 
        x = self.root.winfo_x() + (self.root.winfo_width() // 2) - 310
        y = self.root.winfo_y() + (self.root.winfo_height() // 2) - 260
        update_win.geometry(f"+{x}+{y}")
        update_win.lift() 
        current_core_display = self.cli_cmd if self.cli_cmd else "未检测到核心"
        ttk.Label(update_win, text=f"当前状态: {current_core_display}", font=("Microsoft YaHei UI", 10, "bold"), foreground="#0078d4").pack(pady=(15, 5))
        ttk.Label(update_win, text="将重新运行安装程序以进行更新:", foreground="#555").pack(pady=5)
        def _run_manual(target_core, method):
            update_win.destroy()
            self.config["install_info"] = {"core": target_core, "method": method}
            save_config(self.config)
            cmd = self._get_cmd_by_method(target_core, method, is_update=True)
            threading.Thread(target=self._run_update_sequence, args=(cmd, target_core), daemon=True).start()
        def create_row(parent, btn_text, btn_cmd, desc_text, is_primary=False):
            f = ttk.Frame(parent)
            f.pack(fill="x", pady=3)
            style = "Accent.TButton" if is_primary else "TButton"
            btn = ttk.Button(f, text=btn_text, command=btn_cmd, style=style, width=24)
            btn.pack(side="left", padx=(5, 10))
            color = "#2f9e44" if is_primary else "#666666"
            weight = "bold" if is_primary else "normal"
            lbl = ttk.Label(f, text=desc_text, foreground=color, font=("Microsoft YaHei UI", 9, weight))
            lbl.pack(side="left", anchor="center")
        group_org = ttk.Labelframe(update_win, text="OpenClaw (原版)", padding=10)
        group_org.pack(fill="x", padx=10, pady=5)
        create_row(group_org, "Windows (PowerShell)", lambda: _run_manual("openclaw", "script_ps"), "Windows 首选推荐 (iwr)", True)
        create_row(group_org, "Linux/Mac (Bash)", lambda: _run_manual("openclaw", "script_bash"), "curl ... | bash")
        create_row(group_org, "NPM / PNPM", lambda: _run_manual("openclaw", "npm"), "npm i -g openclaw")
        group_cn = ttk.Labelframe(update_win, text="OpenClaw-CN (汉化版)", padding=10)
        group_cn.pack(fill="x", padx=10, pady=5)
        create_row(group_cn, "Windows (PowerShell)", lambda: _run_manual("openclaw-cn", "script_ps"), "Windows 首选推荐 (iwr)", True)
        create_row(group_cn, "Linux/Mac (Bash)", lambda: _run_manual("openclaw-cn", "script_bash"), "curl ... | bash")
        create_row(group_cn, "NPM / PNPM", lambda: _run_manual("openclaw-cn", "npm"), "npm i -g openclaw-cn")

    def on_resize_event(self, event):
        if event.widget != self.root: return
        if not self._ui_suspended:
            self._ui_suspended = True
            self.txt_system.set_performance_mode(True) 
        if self._resize_timer: 
            self.root.after_cancel(self._resize_timer)
        self._resize_timer = self.root.after(300, self._stop_resizing)

    def _stop_resizing(self):
        self._resize_timer = None
        self.txt_system.set_performance_mode(False)
        self._ui_suspended = False 
        self.sync_ui() 

    def sync_ui(self):
        if self._ui_suspended: return
        c = self.ui_cache
        self.light_gw.set_color(c["gw_color"])
        self.lbl_gw_state.config(style=c["gw_style"])
        self.light_node.set_color(c["node_color"])
        self.lbl_node_state.config(style=c["node_style"])

    def update_ui_status(self):
        if self.status_gw_style == "StatusGreen.TLabel": gw_c = "#2f9e44"
        elif self.status_gw_style == "StatusYellow.TLabel": gw_c = "#f59f00"
        else: gw_c = "#adb5bd"
        if self.status_node_style == "StatusGreen.TLabel": node_c = "#2f9e44"
        elif self.status_node_style == "StatusYellow.TLabel": node_c = "#f59f00"
        else: node_c = "#adb5bd"
        self.ui_cache = {"gw_color": gw_c, "gw_style": self.status_gw_style, "node_color": node_c, "node_style": self.status_node_style}
        self.root.after(0, self.sync_ui)

    def apply_styles(self):
        style = ttk.Style()
        f_bold = (self.f_body[0], self.f_body[1], "bold")
        style.configure(".", font=self.f_small)
        style.configure("TButton", font=f_bold, padding=3)
        style.configure("Accent.TButton", font=f_bold, padding=3)
        style.configure("Stop.TButton", foreground="#d65745", font=f_bold, padding=3)
        style.configure("Link.TButton", foreground="#0078d4", font=f_bold, padding=3)
        style.configure("Update.TButton", foreground="#6f42c1", font=f_bold, padding=3)
        style.configure("Tray.TCheckbutton", font=self.f_small)
        style.configure("TLabelframe.Label", font=self.f_small, foreground="#0078d4")
        
        # [核心修复] 指定 Checkbutton 字体颜色为灰色(#555555)和字号(10)
        style.configure("Backup.TCheckbutton", font=("Microsoft YaHei UI", 10), foreground="#555555")
        
        style.configure("Title.TLabel", font=self.f_title)
        style.configure("Emoji.TLabel", font=self.f_emoji)
        style.configure("StatusGreen.TLabel", foreground="#2f9e44", font=self.f_small)
        style.configure("StatusYellow.TLabel", foreground="#f59f00", font=self.f_small)
        style.configure("StatusGray.TLabel", foreground="#adb5bd", font=self.f_small)

    def setup_dashboard(self, parent):
        self.var_minimize_tray = tk.BooleanVar(value=self.config.get("minimize_to_tray", False))
        
        main_container = ttk.Frame(parent, padding=15)
        main_container.pack(fill="x", expand=True)

        # --- Top Bar (顶部栏) ---
        top_bar = ttk.Frame(main_container)
        top_bar.pack(fill="x", pady=(0, 10))

        ver_frame = ttk.Frame(top_bar)
        ver_frame.pack(side="left", anchor="center")
        
        # 1. 版本号显示
        ttk.Label(ver_frame, text="当前版本: ", font=("Microsoft YaHei UI", 10, "bold"), foreground="#555555").pack(side="left")
        ttk.Label(ver_frame, textvariable=self.version_number_var, font=("Microsoft YaHei UI", 10, "bold"), foreground="#555555").pack(side="left")
        self.lbl_ver_type = ttk.Label(ver_frame, textvariable=self.version_type_var, font=("Microsoft YaHei UI", 10, "bold"), foreground="#0078d4")
        self.lbl_ver_type.pack(side="left", padx=(5,0))
        
        # 2. 功能按钮区 (统一逻辑：先创建对象，再布局)
        
        # [按钮 A] 检查更新 (使用符号 ↻)
        self.btn_update = ttk.Button(ver_frame, text="↻ 检查更新", style="Update.TButton", takefocus=0, command=self.check_for_updates)
        self.btn_update.pack(side="left", padx=(10, 0))
        
        # [按钮 B] 卸载 (使用符号 ✕ 代替 Emoji，彻底解决间距问题)
        self.btn_uninstall = ttk.Button(ver_frame, text="✕ 卸载", style="Stop.TButton", takefocus=0, state="disabled", command=self._show_uninstall_dialog)
        self.btn_uninstall.pack(side="left", padx=(5, 0))

        # 3. 右侧托盘选项
        right_area = ttk.Frame(top_bar)
        right_area.pack(side="right", anchor="center")
        ttk.Checkbutton(right_area, text="最小化到托盘", variable=self.var_minimize_tray, command=self.save_tray_setting, style="Tray.TCheckbutton", takefocus=0).pack(side="left")

        # --- Content Box (状态与控制区) ---
        content_box = ttk.Frame(main_container)
        content_box.pack(fill="x", expand=True)
        content_box.columnconfigure(0, weight=1) 
        
        # 左侧状态面板
        status_panel = ttk.Frame(content_box)
        status_panel.grid(row=0, column=0, sticky="nsew") 
        status_panel.rowconfigure(0, weight=1)
        status_panel.rowconfigure(1, weight=1)
        status_panel.columnconfigure(3, weight=1) 
        
        # Gateway 状态
        ttk.Label(status_panel, text="🧠", style="Emoji.TLabel").grid(row=0, column=0, padx=(5, 10))
        ttk.Label(status_panel, text="Gateway", style="Title.TLabel").grid(row=0, column=1, sticky="w", padx=(0, 20))
        self.light_gw = StatusLight(status_panel, size=14) 
        self.light_gw.grid(row=0, column=2, padx=(0, 10))
        self.lbl_gw_state = ttk.Label(status_panel, textvariable=self.status_gw_text, style="StatusGray.TLabel")
        self.lbl_gw_state.grid(row=0, column=3, sticky="w")

        # Node 状态
        ttk.Label(status_panel, text="💻", style="Emoji.TLabel").grid(row=1, column=0, padx=(5, 10))
        ttk.Label(status_panel, text="Node", style="Title.TLabel").grid(row=1, column=1, sticky="w", padx=(0, 20))
        self.light_node = StatusLight(status_panel, size=14)
        self.light_node.grid(row=1, column=2, padx=(0, 10))
        self.lbl_node_state = ttk.Label(status_panel, textvariable=self.status_node_text, style="StatusGray.TLabel")
        self.lbl_node_state.grid(row=1, column=3, sticky="w")

        # 右侧按钮面板
        btn_panel = ttk.Frame(content_box)
        btn_panel.grid(row=0, column=1, sticky="ne", padx=(15, 0))
        FIXED_BTN_WIDTH = 20
        
        # 核心功能按钮 (默认禁用)
        self.btn_start = ttk.Button(btn_panel, text="🚀  一键启动", style="Accent.TButton", width=FIXED_BTN_WIDTH, takefocus=0, state="disabled", command=self.start_services)
        self.btn_start.pack(fill="x", pady=(0, 5))
        
        self.btn_stop = ttk.Button(btn_panel, text="🛑  全部停止", style="Stop.TButton", width=FIXED_BTN_WIDTH, takefocus=0, state="disabled", command=lambda: threading.Thread(target=self.stop_all).start())
        self.btn_stop.pack(fill="x", pady=(0, 5))
        
        self.btn_web = ttk.Button(btn_panel, text="🌐  Web 控制台", style="Link.TButton", width=FIXED_BTN_WIDTH, takefocus=0, state="disabled", command=self.open_web_ui)
        self.btn_web.pack(fill="x")

    def save_tray_setting(self):
        self.config["minimize_to_tray"] = self.var_minimize_tray.get()
        save_config(self.config)
    def on_close_click(self):
        if messagebox.askyesno("退出确认", "确定要停止服务并退出程序吗？"): self.quit_app()
    def on_minimize_event(self, event):
        if event.widget != self.root: return
        if self.programmatic_action: return
        if self.root.state() == 'iconic' and self.var_minimize_tray.get():
            self.programmatic_action = True
            self.root.withdraw()
            self.programmatic_action = False
    def show_window(self, icon=None, item=None):
        self.programmatic_action = True
        self.root.deiconify()
        self.root.state('normal')
        self.root.lift()
        self.programmatic_action = False
    def create_tray_image(self):
        w, h = 64, 64
        image = Image.new('RGBA', (w, h), (0, 0, 0, 0))
        dc = ImageDraw.Draw(image)
        try:
            font = ImageFont.truetype("seguiemj.ttf", 48)
            dc.text((32, 32), "🦞", font=font, anchor="mm", fill="#ff4500")
        except: dc.ellipse((10, 10, 54, 54), fill="#ff4500", outline="white")
        return image
    def setup_tray_icon(self):
        menu = (pystray.MenuItem('显示主界面', self.show_window, default=True), pystray.MenuItem('退出程序', self.quit_app))
        self.icon = pystray.Icon("OpenClawLauncher", self.create_tray_image(), "OpenClaw Launcher", menu)
        threading.Thread(target=self.icon.run, daemon=True).start()
    def quit_app(self, icon=None, item=None):
        self.is_quitting = True
        self.root.withdraw()
        try: self.icon.stop() 
        except: pass
        self.stop_all(logging=False)
        self.root.destroy()
        sys.exit(0)

    # ==========================================
    #  服务逻辑
    # ==========================================
    def run_process_in_background(self, cmd_str, process_attr, log_widget, success_trigger=None):
        def _target_thread():
            try:
                startupinfo = subprocess.STARTUPINFO()
                startupinfo.dwFlags |= subprocess.STARTF_USESHOWWINDOW
                self.log(log_widget, f"Exec: {cmd_str}", 'CMD')
                process = subprocess.Popen(["cmd", "/c", cmd_str], stdout=subprocess.PIPE, stderr=subprocess.STDOUT, text=True, encoding='utf-8', errors='replace', shell=False, startupinfo=startupinfo, creationflags=subprocess.CREATE_NO_WINDOW, cwd=self._safe_cwd())
                if process_attr != "proc_update": setattr(self, process_attr, process)
                while True:
                    line = process.stdout.readline()
                    if not line and process.poll() is not None: break
                    if line:
                        line = line.strip()
                        self.log(log_widget, line)
                        if success_trigger: success_trigger(line)
                self.log(log_widget, f"进程已退出 (Code: {process.returncode})", 'DEBUG')
                if process_attr != "proc_update":
                    setattr(self, process_attr, None)
                    if process_attr == 'proc_gateway': self.gateway_ready = False
            except Exception as e:
                self.log(log_widget, f"无法执行命令: {e}", 'ERROR')
                messagebox.showerror("执行错误", f"无法运行命令:\n{cmd_str}\n\n错误信息:\n{e}")
        threading.Thread(target=_target_thread, daemon=True).start()

    def check_gateway_http(self):
        try:
            url = "http://127.0.0.1:18789/"
            req = urllib.request.Request(url, method='GET')
            with urllib.request.urlopen(req, timeout=0.5) as response: return True
        except: return False

    def open_web_ui(self):
        if not self.cli_cmd:
            messagebox.showwarning("未就绪", "核心程序尚未加载，请稍候。")
            return
        if not self.gateway_ready:
            messagebox.showwarning("服务未启动", "Gateway 服务尚未运行，无法打开控制台。\n请先点击 '一键启动'。")
            return
        if not self.node_connected_flag:
            messagebox.showwarning("节点未连接", "Node 尚未连接到 Gateway。\n请等待 Node 状态变为 '已连接' 后再试。")
            return

        if not self.has_opened_dashboard:
            self.log(self.txt_system, f"首次打开: 正在执行 {self.cli_cmd} dashboard ...", "INFO")
            def _launch_dashboard_cmd():
                try:
                    startupinfo = subprocess.STARTUPINFO()
                    startupinfo.dwFlags |= subprocess.STARTF_USESHOWWINDOW
                    subprocess.run(["cmd", "/c", f"{self.cli_cmd} dashboard"], shell=False, creationflags=subprocess.CREATE_NO_WINDOW, startupinfo=startupinfo, cwd=self._safe_cwd())
                except Exception as e:
                    self.log(self.txt_system, f"打开控制台失败: {e}", "ERROR")
            threading.Thread(target=_launch_dashboard_cmd, daemon=True).start()
            self.has_opened_dashboard = True
        else:
            target_url = "http://127.0.0.1:18789/"
            self.log(self.txt_system, f"打开 WebUI: {target_url}", "INFO")
            webbrowser.open(target_url)

    def _start_node_internal(self):
        # [新增] 逻辑防抖：检查 Node 是否已在运行
        if self.proc_node and self.proc_node.poll() is None:
             self.log(self.txt_system, "⚠️ Node 进程已在后台运行，跳过重复启动。", "INFO")
             # 确保按钮状态正确（如果是一键启动触发的，这里应该已经禁用了，但为了保险）
             self.btn_start.config(state="disabled") 
             return

        self.log(self.txt_system, f"正在启动 Node ({self.cli_cmd})...", "INFO")
        self.status_node_style = "StatusYellow.TLabel"
        self.status_node_text.set("启动中...")
        self.update_ui_status() 
        
        if not self.cli_cmd: return
        
        node_cmd = f'{self.cli_cmd} node run --host 127.0.0.1 --port 18789 --display-name "MyWinPC"'
        self.run_process_in_background(node_cmd, "proc_node", self.txt_system, None)
        
        # 启动检测线程
        threading.Thread(target=self._wait_for_node_ready, daemon=True).start()

    def _wait_for_node_ready(self):
        for _ in range(40): 
            time.sleep(0.5)
            if self.check_status_once():
                 self.status_node_style = "StatusGreen.TLabel"
                 self.status_node_text.set("已连接")
                 self.update_ui_status() 
                 return

    def start_services(self):
        if not self.cli_cmd:
            messagebox.showerror("启动失败", "内部错误：检测到版本号，但核心命令(cli_cmd)未设置。\n\n请尝试点击右上角'检查更新' -> 选择'脚本'修复安装。")
            return
        if self.version_number_var.get() == "检测中...":
             messagebox.showinfo("请稍候", "正在后台检测版本，请等待 2-3 秒后再试。")
             return

        # [新增] 1. 物理防抖：点击后立即禁用按钮
        self.btn_start.config(state="disabled")
        
        # [新增] 2. 逻辑防抖：检查 Gateway 是否已在运行
        if self.proc_gateway and self.proc_gateway.poll() is None:
            self.log(self.txt_system, "⚠️ Gateway 进程已在运行中，忽略重复启动请求。", "INFO")
            return

        try:
            if self.check_gateway_http():
                self.log(self.txt_system, "Gateway 服务检测已存活。", "INFO")
                self.gateway_ready = True
                self.status_gw_style = "StatusGreen.TLabel"
                self.status_gw_text.set("运行中")
                self.update_ui_status()
                self._start_node_internal()
            else:
                self.gateway_ready = False
                self.log(self.txt_system, f"准备启动 Gateway ({self.cli_cmd})...", "INFO")
                cmd = f"{self.cli_cmd} gateway"
                self.status_gw_style = "StatusYellow.TLabel"
                self.status_gw_text.set("启动中...")
                self.update_ui_status()
                
                # 启动 Gateway
                self.run_process_in_background(cmd, "proc_gateway", self.txt_system, None)

                def wait_for_gateway():
                    self.log(self.txt_system, "正在等待端口 18789 响应...", "DEBUG")
                    for i in range(30):
                        time.sleep(0.5)
                        # 再次检查进程是否意外挂掉
                        if self.proc_gateway and self.proc_gateway.poll() is not None:
                             self.log(self.txt_system, "❌ Gateway 进程意外终止，启动失败。", "ERROR")
                             self.root.after(0, lambda: self.btn_start.config(state="normal")) # 失败恢复按钮
                             return

                        if self.check_gateway_http():
                            self.log(self.txt_system, ">>> Gateway 启动成功 <<<", "SUCCESS")
                            self.gateway_ready = True
                            self.status_gw_style = "StatusGreen.TLabel"
                            self.status_gw_text.set("运行中")
                            self.update_ui_status() 
                            self.root.after(50, self._start_node_internal)
                            return
                        if i % 10 == 0: self.log(self.txt_system, f"等待中 ({i/2}s)...", "DEBUG")
                    
                    self.log(self.txt_system, "❌ Gateway 启动超时！请检查 18789 端口是否被占用。", "ERROR")
                    messagebox.showwarning("启动超时", "Gateway 服务启动超时。\n请检查日志是否有错误信息，或手动运行 openclaw gateway 尝试。")
                    self.root.after(0, lambda: self.btn_start.config(state="normal")) # 超时恢复按钮

                threading.Thread(target=wait_for_gateway, daemon=True).start()
        except Exception as e:
            err_msg = f"启动过程发生异常:\n{str(e)}\n{traceback.format_exc()}"
            self.log(self.txt_system, err_msg, "ERROR")
            messagebox.showerror("严重错误", err_msg)
            self.btn_start.config(state="normal") # 异常恢复按钮

    def stop_all(self, logging=True):
        if logging: self.log(self.txt_system, "正在停止所有服务...", "INFO")
        kill_flags = subprocess.CREATE_NO_WINDOW
        
        # 杀进程逻辑...
        if self.proc_gateway: subprocess.run(["cmd", "/c", f"taskkill /F /T /PID {self.proc_gateway.pid}"], shell=False, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL, creationflags=kill_flags)
        if self.proc_node: subprocess.run(["cmd", "/c", f"taskkill /F /T /PID {self.proc_node.pid}"], shell=False, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL, creationflags=kill_flags)
        subprocess.run(["cmd", "/c", "taskkill /F /IM node.exe"], shell=False, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL, creationflags=kill_flags)
        
        self.gateway_ready = False
        self.node_connected_flag = False
        
        # UI 重置
        self.status_gw_style = "StatusGray.TLabel"
        self.status_gw_text.set("未运行")
        self.status_node_style = "StatusGray.TLabel"
        self.status_node_text.set("未运行")
        self.update_ui_status()
        
        # [新增] 停止后，重新启用“一键启动”按钮
        self.btn_start.config(state="normal")
        
        if logging: self.log(self.txt_system, "已发送停止指令。", "INFO")

    def check_status_once(self, manual=False):
        if not self.cli_cmd: return False
        try:
            startupinfo = subprocess.STARTUPINFO()
            startupinfo.dwFlags |= subprocess.STARTF_USESHOWWINDOW
            cmd_list = ["cmd", "/c", f"{self.cli_cmd} nodes status"]
            result = subprocess.run(cmd_list, capture_output=True, text=True, shell=False, encoding='utf-8', creationflags=subprocess.CREATE_NO_WINDOW, startupinfo=startupinfo, cwd=self._safe_cwd())
            output = result.stdout
            if manual: self.log(self.txt_system, output)
            is_connected = False
            if re.search(r"Connected:\s*[1-9]", output): is_connected = True
            elif "paired · connected" in output: is_connected = True

            if is_connected:
                if not self.node_connected_flag: self.log(self.txt_system, ">>> Node 连接成功 <<<", "SUCCESS")
                self.node_connected_flag = True
                return True
            else:
                self.node_connected_flag = False
                return False
        except Exception as e:
            if manual: self.log(self.txt_system, f"检测失败: {e}", "ERROR")
            return False

    def monitor_loop(self):
        while True:
            if self.is_quitting: break
            if self.check_gateway_http():
                if not self.gateway_ready: 
                    self.status_gw_style = "StatusGreen.TLabel"
                    self.status_gw_text.set("运行中")
                    self.gateway_ready = True
            else:
                if self.gateway_ready:
                    self.status_gw_style = "StatusGray.TLabel"
                    self.status_gw_text.set("未运行")
                    self.gateway_ready = False

            if self.gateway_ready:
                if self.proc_node and self.proc_node.poll() is None:
                    if self.node_connected_flag:
                        self.status_node_style = "StatusGreen.TLabel"
                        self.status_node_text.set("已连接")
                    else:
                        if self.status_node_style != "StatusYellow.TLabel":
                             self.status_node_style = "StatusYellow.TLabel"
                             self.status_node_text.set("连接中...")
                        self.check_status_once(manual=False)
                else:
                    self.status_node_style = "StatusGray.TLabel"
                    self.status_node_text.set("未运行")
                    self.node_connected_flag = False
            else:
                self.status_node_style = "StatusGray.TLabel"
                self.status_node_text.set("未运行")
            self.update_ui_status()
            time.sleep(1.5 if not self.node_connected_flag else 3)

# ==========================================
#  程序入口 (增加单例检测)
# ==========================================
if __name__ == "__main__":
    # [新增] 全局互斥锁，防止重复启动
    mutex_name = "Global\\OpenClaw_Launcher_Singleton_Lock_v1"
    mutex = ctypes.windll.kernel32.CreateMutexW(None, False, mutex_name)
    
    # 检查是否已存在 (ERROR_ALREADY_EXISTS = 183)
    if ctypes.windll.kernel32.GetLastError() == 183:
        ctypes.windll.user32.MessageBoxW(0, "OpenClaw 启动器已经在运行中！\n\n请检查任务栏或右下角托盘图标 (🦞)。", "提示", 0x40 | 0x1)
        sys.exit(0)

    try:
        root = tk.Tk()
        app = UniversalLauncher(root)
        root.mainloop()
    except Exception as e:
        show_critical_error(traceback.format_exc())