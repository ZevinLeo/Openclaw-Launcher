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
CONFIG_FILE = "launcher_config.json"

def load_config():
    default_conf = {"minimize_to_tray": False} 
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
# 4. 日志组件 (美化+缓冲)
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
            spacing3=2, 
            padx=5, pady=5, 
            borderwidth=0, 
            highlightthickness=0, 
            takefocus=0, 
            bg="#f6f6f6",  
            fg="#333333",
            selectbackground="#0078d4",
            selectforeground="white",
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
        try:
            was_at_bottom = self.text.yview()[1] == 1.0
            self.text.config(state='normal')
            self.text.insert(*args)
            self.text.config(state='disabled')
            if was_at_bottom:
                self.text.see(tk.END)
        except: pass
    
    def see(self, *args):
        try: self.text.see(*args)
        except: pass

    def set_performance_mode(self, enabled):
        try:
            target_wrap = "none" if enabled else "word"
            if self.text.cget("wrap") != target_wrap:
                self.text.config(wrap=target_wrap)
        except: pass

# ==========================================
# 5. 主程序
# ==========================================
class UniversalLauncher:
    def __init__(self, root):
        self.root = root
        
        # [窗口设置]
        self.root.geometry("1100x900")
        self.root.minsize(1100, 900)
        
        # [核心状态]
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

        # 字体
        self.f_title = ("Microsoft YaHei UI", 12, "bold") 
        self.f_body = ("Microsoft YaHei UI", 11)          
        self.f_small = ("Microsoft YaHei UI", 10)         
        self.f_emoji = ("Segoe UI Emoji", 14)
        
        self.status_gw_text = tk.StringVar(value="未运行")
        self.status_node_text = tk.StringVar(value="未运行")
        # 默认灰色
        self.ui_cache = {"gw_color": "#adb5bd", "gw_style": "StatusGray.TLabel", "node_color": "#adb5bd", "node_style": "StatusGray.TLabel"}

        self.apply_styles()

        # UI 布局
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
        
        # [初始化变量]
        self.cli_cmd = None 
        self.version_number_var = tk.StringVar(value="检测中...") 
        self.version_type_var = tk.StringVar(value="")
        self.has_opened_dashboard = False
        
        # UI 初始化
        self.setup_dashboard(self.top_frame)

        self.root.title("OpenClaw 通用启动器")

        try: self.setup_tray_icon()
        except: pass
        
        self.monitor_thread = threading.Thread(target=self.monitor_loop, daemon=True)
        self.monitor_thread.start()
        
        self.root.bind("<Unmap>", self.on_minimize_event)
        self.root.bind("<Configure>", self.on_resize_event)
        self.root.protocol("WM_DELETE_WINDOW", self.on_close_click)

        # 启动后台检测
        threading.Thread(target=self._async_detect_sequence, daemon=True).start()

    # ==========================================
    #  [核心] 异步检测
    # ==========================================
    def _async_detect_sequence(self):
        if self._check_version_with_status_cmd("openclaw-cn"):
            self.root.after(0, lambda: self._update_ui_after_detect("openclaw-cn", self.version_number))
            return
        if self._check_version_with_status_cmd("openclaw"):
            self.root.after(0, lambda: self._update_ui_after_detect("openclaw", self.version_number))
            return
        self.root.after(0, lambda: self._update_ui_after_detect(None, "未安装"))

    def _update_ui_after_detect(self, cmd_found, ver_num):
        self.version_number_var.set(ver_num)
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
            self.cli_cmd = None
            self.version_type_var.set("(未检测到核心)")
            self.lbl_ver_type.config(foreground="red")
            messagebox.showwarning("环境缺失", "未检测到 OpenClaw 核心程序。\n请确认已安装。")

    def _check_version_with_status_cmd(self, cmd_name):
        try:
            startupinfo = subprocess.STARTUPINFO()
            startupinfo.dwFlags |= subprocess.STARTF_USESHOWWINDOW
            cmd_list = ["cmd", "/c", f"{cmd_name} status"]
            result = subprocess.run(
                cmd_list, capture_output=True, text=True, shell=False, 
                encoding='utf-8', errors='ignore', 
                creationflags=subprocess.CREATE_NO_WINDOW, startupinfo=startupinfo
            )
            if result.returncode == 0 and result.stdout:
                output = result.stdout.strip()
                pattern = r"(\d{4}\.\d+\.\d+\s+\(\d+\))"
                match = re.search(pattern, output)
                if match:
                    self.version_number = match.group(1)
                    return True
                else:
                    backup = re.search(r"(\d{4}\.\d+\.\d+)", output)
                    if backup:
                         self.version_number = backup.group(1)
                         return True
            return False
        except Exception:
            return False

    # ==========================================
    #  UI 刷新逻辑
    # ==========================================
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
        if self._log_buffer:
            def _flush_buffer():
                self.txt_system.text.config(state='normal')
                for msg, tag in self._log_buffer:
                    self.txt_system.text.insert(tk.END, msg, tag)
                self.txt_system.text.config(state='disabled')
                self.txt_system.text.see(tk.END)
                self._log_buffer.clear()
            _flush_buffer()
        self._ui_suspended = False 
        self.sync_ui() 

    def log(self, widget, msg, tag='INFO'):
        timestamp = time.strftime("%H:%M:%S", time.localtime())
        formatted_msg = f"[{timestamp}] {msg}\n"
        if self._ui_suspended:
            self._log_buffer.append((formatted_msg, tag))
            return
        def _write():
            widget.insert(tk.END, formatted_msg, tag)
        self.root.after(0, _write)

    def sync_ui(self):
        if self._ui_suspended: return
        c = self.ui_cache
        self.light_gw.set_color(c["gw_color"])
        self.lbl_gw_state.config(style=c["gw_style"])
        self.light_node.set_color(c["node_color"])
        self.lbl_node_state.config(style=c["node_style"])

    def update_ui_status(self):
        # 绿色：运行中
        if self.status_gw_style == "StatusGreen.TLabel": gw_c = "#2f9e44"
        # 黄色：启动中
        elif self.status_gw_style == "StatusYellow.TLabel": gw_c = "#f59f00"
        # 灰色：未启动 (默认)
        else: gw_c = "#adb5bd"
        
        if self.status_node_style == "StatusGreen.TLabel": node_c = "#2f9e44"
        elif self.status_node_style == "StatusYellow.TLabel": node_c = "#f59f00"
        else: node_c = "#adb5bd"
        
        self.ui_cache = {
            "gw_color": gw_c, "gw_style": self.status_gw_style,
            "node_color": node_c, "node_style": self.status_node_style
        }
        self.root.after(0, self.sync_ui)

    def apply_styles(self):
        style = ttk.Style()
        style.configure(".", font=self.f_small)
        style.configure("TButton", font=self.f_body, padding=3)
        style.configure("Accent.TButton", font=(self.f_body[0], self.f_body[1], "bold"), padding=3)
        style.configure("Stop.TButton", foreground="#d65745", font=(self.f_body[0], self.f_body[1], "bold"), padding=3)
        style.configure("Link.TButton", foreground="#0078d4", font=self.f_body, padding=3)
        style.configure("Tray.TCheckbutton", font=self.f_small)
        style.configure("TLabelframe.Label", font=self.f_small, foreground="#0078d4")
        style.configure("Title.TLabel", font=self.f_title)
        style.configure("Emoji.TLabel", font=self.f_emoji)
        
        # [修改] 定义三种状态样式
        style.configure("StatusGreen.TLabel", foreground="#2f9e44", font=self.f_small) # Green
        style.configure("StatusYellow.TLabel", foreground="#f59f00", font=self.f_small) # Yellow
        style.configure("StatusGray.TLabel", foreground="#adb5bd", font=self.f_small)  # Gray (原 Red)
        
        style.configure("VerCN.TLabel", foreground="#ff4500", font=("Microsoft YaHei UI", 10, "bold")) 
        style.configure("VerOrg.TLabel", foreground="#0078d4", font=("Microsoft YaHei UI", 10, "bold")) 
        style.configure("VerNew.TLabel", foreground="#00b7c3", font=("Microsoft YaHei UI", 10, "bold")) 

    def setup_dashboard(self, parent):
        self.var_minimize_tray = tk.BooleanVar(value=self.config.get("minimize_to_tray", False))
        
        main_container = ttk.Frame(parent, padding=15)
        main_container.pack(fill="x", expand=True)

        top_bar = ttk.Frame(main_container)
        top_bar.pack(fill="x", pady=(0, 10))
        ver_frame = ttk.Frame(top_bar)
        ver_frame.pack(side="left", anchor="center")
        ttk.Label(ver_frame, text="当前版本: ", font=("Microsoft YaHei UI", 10, "bold"), foreground="#555555").pack(side="left")
        ttk.Label(ver_frame, textvariable=self.version_number_var, font=("Microsoft YaHei UI", 10, "bold"), foreground="#555555").pack(side="left")
        self.lbl_ver_type = ttk.Label(ver_frame, textvariable=self.version_type_var, font=("Microsoft YaHei UI", 10, "bold"), foreground="#0078d4")
        self.lbl_ver_type.pack(side="left", padx=(5,0))
        ttk.Checkbutton(top_bar, text="最小化到托盘", variable=self.var_minimize_tray, command=self.save_tray_setting, style="Tray.TCheckbutton", takefocus=0).pack(side="right")

        content_box = ttk.Frame(main_container)
        content_box.pack(fill="x", expand=True)
        content_box.columnconfigure(0, weight=1) 
        
        status_panel = ttk.Frame(content_box)
        status_panel.grid(row=0, column=0, sticky="nsew") 
        status_panel.rowconfigure(0, weight=1)
        status_panel.rowconfigure(1, weight=1)
        status_panel.columnconfigure(3, weight=1) 
        
        # [修改] 默认样式改为 StatusGray.TLabel
        ttk.Label(status_panel, text="🧠", style="Emoji.TLabel").grid(row=0, column=0, padx=(5, 10))
        ttk.Label(status_panel, text="Gateway", style="Title.TLabel").grid(row=0, column=1, sticky="w", padx=(0, 20))
        self.light_gw = StatusLight(status_panel, size=14) 
        self.light_gw.grid(row=0, column=2, padx=(0, 10))
        self.lbl_gw_state = ttk.Label(status_panel, textvariable=self.status_gw_text, style="StatusGray.TLabel")
        self.lbl_gw_state.grid(row=0, column=3, sticky="w")

        ttk.Label(status_panel, text="💻", style="Emoji.TLabel").grid(row=1, column=0, padx=(5, 10))
        ttk.Label(status_panel, text="Node", style="Title.TLabel").grid(row=1, column=1, sticky="w", padx=(0, 20))
        self.light_node = StatusLight(status_panel, size=14)
        self.light_node.grid(row=1, column=2, padx=(0, 10))
        self.lbl_node_state = ttk.Label(status_panel, textvariable=self.status_node_text, style="StatusGray.TLabel")
        self.lbl_node_state.grid(row=1, column=3, sticky="w")

        btn_panel = ttk.Frame(content_box)
        btn_panel.grid(row=0, column=1, sticky="ne", padx=(15, 0))
        FIXED_BTN_WIDTH = 20
        ttk.Button(btn_panel, text="🚀  一键启动", style="Accent.TButton", width=FIXED_BTN_WIDTH, takefocus=0, command=self.start_services).pack(fill="x", pady=(0, 5))
        ttk.Button(btn_panel, text="🛑  全部停止", style="Stop.TButton", width=FIXED_BTN_WIDTH, takefocus=0, command=lambda: threading.Thread(target=self.stop_all).start()).pack(fill="x", pady=(0, 5))
        ttk.Button(btn_panel, text="🌐  Web 控制台", style="Link.TButton", width=FIXED_BTN_WIDTH, takefocus=0, command=self.open_web_ui).pack(fill="x")

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
    #  服务逻辑: 极速反馈版
    # ==========================================
    def run_process_in_background(self, cmd_str, process_attr, log_widget, success_trigger=None):
        try:
            startupinfo = subprocess.STARTUPINFO()
            startupinfo.dwFlags |= subprocess.STARTF_USESHOWWINDOW
            creation_flags = subprocess.CREATE_NO_WINDOW
            cmd_list = ["cmd", "/c", cmd_str]
            process = subprocess.Popen(
                cmd_list, stdout=subprocess.PIPE, stderr=subprocess.STDOUT, 
                text=True, encoding='utf-8', errors='replace', 
                shell=False, startupinfo=startupinfo, creationflags=creation_flags
            )
            setattr(self, process_attr, process)
            self.log(log_widget, f"执行命令: {cmd_str}", 'CMD')
            
            def _read_output():
                for line in process.stdout:
                    line = line.strip()
                    if line:
                        self.log(log_widget, line)
                        if success_trigger: success_trigger(line)
                self.log(log_widget, "进程已退出。", 'ERROR')
                setattr(self, process_attr, None)
                if process_attr == 'proc_gateway': self.gateway_ready = False
            
            threading.Thread(target=_read_output, daemon=True).start()

        except Exception as e: 
            self.log(log_widget, f"启动失败: {e}", 'ERROR')

    def check_gateway_http(self):
        try:
            url = "http://127.0.0.1:18789/"
            req = urllib.request.Request(url, method='GET')
            with urllib.request.urlopen(req, timeout=0.5) as response:
                return True
        except urllib.error.HTTPError: return True 
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
                    subprocess.run(
                        ["cmd", "/c", f"{self.cli_cmd} dashboard"],
                        shell=False, creationflags=subprocess.CREATE_NO_WINDOW, startupinfo=startupinfo
                    )
                except Exception as e:
                    self.log(self.txt_system, f"打开控制台失败: {e}", "ERROR")
            threading.Thread(target=_launch_dashboard_cmd, daemon=True).start()
            self.has_opened_dashboard = True
        else:
            target_url = "http://127.0.0.1:18789/"
            self.log(self.txt_system, f"打开 WebUI: {target_url}", "INFO")
            webbrowser.open(target_url)

    def _start_node_internal(self):
        if self.proc_node and self.proc_node.poll() is None:
             self.log(self.txt_system, "Node 进程已在运行。", "INFO")
             return
        self.log(self.txt_system, f"正在启动 Node ({self.cli_cmd})...", "INFO")
        
        # [极速反馈] Node 启动瞬间：立即变黄
        self.status_node_style = "StatusYellow.TLabel"
        self.status_node_text.set("启动中...")
        self.update_ui_status() # 强制刷新

        if not self.cli_cmd: return
        node_cmd = f'{self.cli_cmd} node run --host 127.0.0.1 --port 18789 --display-name "MyWinPC"'
        
        self.run_process_in_background(node_cmd, "proc_node", self.txt_system, None)
        
        # [极速反馈] 启动高频检测线程
        threading.Thread(target=self._wait_for_node_ready, daemon=True).start()

    def _wait_for_node_ready(self):
        """高频检测 Node 连接状态，实现秒级变绿"""
        for _ in range(40): # 最多尝试 20秒
            time.sleep(0.5)
            # 如果检测成功，立刻变绿，不等待 monitor_loop
            if self.check_status_once():
                 self.status_node_style = "StatusGreen.TLabel"
                 self.status_node_text.set("已连接")
                 self.update_ui_status() # 强制刷新
                 return

    def start_services(self):
        if self.version_number_var.get() == "检测中...":
             self.log(self.txt_system, "正在检测核心版本，请稍候...", "INFO")
             return
        if not self.cli_cmd:
            self.log(self.txt_system, "无法启动：未检测到核心程序。", "ERROR")
            return

        if self.check_gateway_http():
            self.log(self.txt_system, "Gateway 服务已就绪。", "INFO")
            self.gateway_ready = True
            # [极速反馈] 如果本来就是好的，直接变绿
            self.status_gw_style = "StatusGreen.TLabel"
            self.status_gw_text.set("运行中")
            self.update_ui_status()
            self._start_node_internal()
        else:
            self.gateway_ready = False
            self.log(self.txt_system, "Gateway 未运行，正在启动...", "INFO")
            cmd = f"{self.cli_cmd} gateway"
            
            # [极速反馈] 启动瞬间：变黄
            self.status_gw_style = "StatusYellow.TLabel"
            self.status_gw_text.set("启动中...")
            self.update_ui_status()
            
            self.run_process_in_background(cmd, "proc_gateway", self.txt_system, None)

            def wait_for_gateway():
                self.log(self.txt_system, "等待 Gateway 就绪...", "INFO")
                for _ in range(30):
                    time.sleep(0.5)
                    # [极速反馈] 检测到 HTTP 200，立刻变绿
                    if self.check_gateway_http():
                        self.log(self.txt_system, ">>> Gateway 启动成功 <<<", "SUCCESS")
                        self.gateway_ready = True
                        
                        self.status_gw_style = "StatusGreen.TLabel"
                        self.status_gw_text.set("运行中")
                        self.update_ui_status() # 强制刷新
                        
                        self.root.after(50, self._start_node_internal)
                        return
                self.log(self.txt_system, "❌ Gateway 启动超时，请检查日志。", "ERROR")
            threading.Thread(target=wait_for_gateway, daemon=True).start()

    def stop_all(self, logging=True):
        if logging: self.log(self.txt_system, "正在停止所有服务...", "INFO")
        kill_flags = subprocess.CREATE_NO_WINDOW
        
        if self.proc_gateway: 
            subprocess.run(["cmd", "/c", f"taskkill /F /T /PID {self.proc_gateway.pid}"], shell=False, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL, creationflags=kill_flags)
        if self.proc_node: 
            subprocess.run(["cmd", "/c", f"taskkill /F /T /PID {self.proc_node.pid}"], shell=False, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL, creationflags=kill_flags)
        subprocess.run(["cmd", "/c", "taskkill /F /IM node.exe"], shell=False, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL, creationflags=kill_flags)
        
        self.gateway_ready = False
        self.node_connected_flag = False
        
        # [极速反馈] 停止瞬间变灰
        self.status_gw_style = "StatusGray.TLabel"
        self.status_gw_text.set("未运行")
        self.status_node_style = "StatusGray.TLabel"
        self.status_node_text.set("未运行")
        self.update_ui_status()
        
        if logging: self.log(self.txt_system, "已发送停止指令。", "INFO")

    def check_status_once(self, manual=False):
        if not self.cli_cmd: return False
        try:
            startupinfo = subprocess.STARTUPINFO()
            startupinfo.dwFlags |= subprocess.STARTF_USESHOWWINDOW
            cmd_list = ["cmd", "/c", f"{self.cli_cmd} nodes status"]
            result = subprocess.run(
                cmd_list, capture_output=True, text=True, shell=False, 
                encoding='utf-8', creationflags=subprocess.CREATE_NO_WINDOW, startupinfo=startupinfo
            )
            output = result.stdout
            if manual: self.log(self.txt_system, output)
            
            is_connected = False
            if re.search(r"Connected:\s*[1-9]", output): is_connected = True
            elif "paired · connected" in output: is_connected = True

            if is_connected:
                if not self.node_connected_flag:
                    self.log(self.txt_system, ">>> Node 连接成功 <<<", "SUCCESS")
                self.node_connected_flag = True
                return True
            else:
                self.node_connected_flag = False
                return False
        except Exception as e:
            if manual: self.log(self.txt_system, f"检测失败: {e}", "ERROR")
            return False

    def monitor_loop(self):
        """优化后的监控循环"""
        while True:
            if self.is_quitting: break
            
            # --- Gateway 检测 ---
            if self.check_gateway_http():
                # 只有状态改变时才更新
                if not self.gateway_ready: 
                    self.status_gw_style = "StatusGreen.TLabel"
                    self.status_gw_text.set("运行中")
                    self.gateway_ready = True
            else:
                # 只有当它真的挂了，且不是正在启动中(Yellow)时，才变灰
                if self.gateway_ready:
                    self.status_gw_style = "StatusGray.TLabel"
                    self.status_gw_text.set("未运行")
                    self.gateway_ready = False

            # --- Node 检测 ---
            if self.gateway_ready:
                if self.proc_node and self.proc_node.poll() is None:
                    # 进程活着
                    if self.node_connected_flag:
                        self.status_node_style = "StatusGreen.TLabel"
                        self.status_node_text.set("已连接")
                    else:
                        # 进程活着但没连接 -> 保持黄色(启动中) 或 尝试检测
                        if self.status_node_style != "StatusYellow.TLabel":
                             self.status_node_style = "StatusYellow.TLabel"
                             self.status_node_text.set("连接中...")
                        self.check_status_once(manual=False)
                else:
                    # 进程挂了
                    self.status_node_style = "StatusGray.TLabel"
                    self.status_node_text.set("未运行")
                    self.node_connected_flag = False
            else:
                self.status_node_style = "StatusGray.TLabel"
                self.status_node_text.set("未运行")

            self.update_ui_status()
            time.sleep(1.5 if not self.node_connected_flag else 3)

if __name__ == "__main__":
    try:
        root = tk.Tk()
        app = UniversalLauncher(root)
        root.mainloop()
    except Exception as e:
        show_critical_error(traceback.format_exc())