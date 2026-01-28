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
import re  # 必须保留

# ==========================================
# 0. 崩溃拦截与环境配置
# ==========================================
def show_critical_error(msg):
    try:
        ctypes.windll.user32.MessageBoxW(0, f"启动错误:\n\n{msg}", "Clawdbot Error", 0x10)
    except: pass
    sys.exit(1)

try:
    try:
        ctypes.windll.shcore.SetProcessDpiAwareness(1) 
    except: pass

    import sv_ttk
    import pystray
    # 修改点1：增加 ImageTk 引用
    from PIL import Image, ImageDraw, ImageFont, ImageTk
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
CONFIG_FILE = "clawd_config.json"

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
# 3. 原生画布状态灯
# ==========================================
class StatusLight(tk.Canvas):
    def __init__(self, parent, size=14):
        # 居中放置 Canvas，本身无边框
        super().__init__(parent, width=size, height=size, highlightthickness=0, borderwidth=0)
        self.indicator = self.create_oval(1, 1, size-1, size-1, fill="#adb5bd", outline="")
    
    def set_color(self, color):
        self.itemconfig(self.indicator, fill=color)

# ==========================================
# 4. 日志组件 (已修改：移除横向滚动，改为自适应换行)
# ==========================================
class ModernLog(ttk.Frame):
    def __init__(self, parent, **kwargs):
        super().__init__(parent)
        self.pack(fill="both", expand=True)
        
        # 仅保留垂直滚动条
        self.v_scroll = ttk.Scrollbar(self, orient="vertical")
        self.v_scroll.pack(side="right", fill="y")
        
        # 移除水平滚动条定义 (self.h_scroll)
        
        self.text = tk.Text(self, 
                            yscrollcommand=self.v_scroll.set, 
                            # xscrollcommand 移除
                            wrap="word", # 核心修改：改为按单词换行，实现宽度自适应
                            font=("Consolas", 10), 
                            padx=10, pady=10, 
                            borderwidth=0, highlightthickness=0, **kwargs)
        self.text.pack(side="left", fill="both", expand=True)
        
        self.v_scroll.config(command=self.text.yview)
        # 移除 h_scroll 配置
        
        self.text.tag_config('INFO', foreground='')
        self.text.tag_config('ERROR', foreground='#e03131')
        self.text.tag_config('SUCCESS', foreground='#2f9e44')
        self.text.tag_config('CMD', foreground='#1971c2')

    def insert(self, *args):
        try:
            self.text.config(state='normal')
            self.text.insert(*args)
            self.text.config(state='disabled')
        except: pass
    
    def see(self, *args):
        try: self.text.see(*args)
        except: pass

# ==========================================
# 5. 主程序
# ==========================================
class ClawdLauncher:
    def __init__(self, root):
        self.root = root
        self.root.title("Clawdbot启动器")
        self.root.geometry("1200x900") 
        self.root.minsize(1200, 900)
        
        self.config = load_config()
        
        # 强制浅色主题
        try:
            sv_ttk.set_theme("light")
        except: pass

        # 修改点2：设置主窗口图标 (复用 create_tray_image 生成的龙虾图)
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

        self.is_resizing = False
        self._resize_timer = None

        # --- 字体定义 ---
        self.f_title = ("Microsoft YaHei UI", 12, "bold") 
        self.f_body = ("Microsoft YaHei UI", 11)          
        self.f_small = ("Microsoft YaHei UI", 10)         
        self.f_emoji = ("Segoe UI Emoji", 14)

        # 状态变量
        self.status_gw_text = tk.StringVar(value="未运行")
        self.status_node_text = tk.StringVar(value="未运行")
        
        self.ui_cache = {
            "gw_color": "#adb5bd", "gw_style": "StatusRed.TLabel",
            "node_color": "#adb5bd", "node_style": "StatusRed.TLabel"
        }

        self.apply_styles()

        # 布局
        self.top_frame = ttk.Frame(root, padding=25)
        self.top_frame.pack(side=tk.TOP, fill=tk.X)
        self.setup_dashboard(self.top_frame)

        self.bottom_frame = ttk.Frame(root, padding=(25, 0, 25, 25))
        self.bottom_frame.pack(side=tk.BOTTOM, fill=tk.BOTH, expand=True)

        self.notebook = ttk.Notebook(self.bottom_frame)
        self.notebook.pack(fill="both", expand=True)

        self.tab_gateway_log = ttk.Frame(self.notebook)
        self.tab_node_log = ttk.Frame(self.notebook)
        self.tab_system_log = ttk.Frame(self.notebook)

        self.notebook.add(self.tab_gateway_log, text=" Gateway ")
        self.notebook.add(self.tab_node_log, text=" Node ")
        self.notebook.add(self.tab_system_log, text=" System ")

        self.txt_gateway = ModernLog(self.tab_gateway_log)
        self.txt_node = ModernLog(self.tab_node_log)
        self.txt_system = ModernLog(self.tab_system_log)

        try:
            self.setup_tray_icon()
        except: pass
        
        self.monitor_thread = threading.Thread(target=self.monitor_loop, daemon=True)
        self.monitor_thread.start()
        
        self.root.bind("<Unmap>", self.on_minimize_event)
        self.root.bind("<Configure>", self.on_resize_event)
        self.root.protocol("WM_DELETE_WINDOW", self.on_close_click)

    def apply_styles(self):
        style = ttk.Style()
        style.configure(".", font=self.f_small)
        style.configure("TButton", font=self.f_body)
        style.configure("Accent.TButton", font=self.f_body)
        style.configure("TLabelframe.Label", font=self.f_small, foreground="#0078d4")
        style.configure("TNotebook.Tab", padding=[20, 3], font=self.f_small)
        style.configure("TCheckbutton", font=self.f_small)
        
        style.configure("Title.TLabel", font=self.f_title)
        style.configure("StatusGreen.TLabel", foreground="#2f9e44", font=self.f_small)
        style.configure("StatusRed.TLabel", foreground="gray", font=self.f_small)
        style.configure("StatusYellow.TLabel", foreground="#f59f00", font=self.f_small)
        
        style.configure("Emoji.TLabel", font=self.f_emoji) 

        style.configure("Stop.TButton", foreground="#d65745", font=self.f_body) 
        style.configure("Check.TButton", foreground="#4c9e5f", font=self.f_body)

    def setup_dashboard(self, parent):
        frame = ttk.LabelFrame(parent, text=" 控制面板 ", padding=20)
        frame.pack(fill="x", expand=True)

        self.var_minimize_tray = tk.BooleanVar(value=self.config.get("minimize_to_tray", False))

        frame.columnconfigure(4, weight=1) 

        # --- Row 0: Gateway ---
        ttk.Label(frame, text="🧠", style="Emoji.TLabel").grid(row=0, column=0, padx=(5, 10), pady=8)
        ttk.Label(frame, text="Gateway", style="Title.TLabel").grid(row=0, column=1, sticky="w", padx=(0, 20), pady=8)
        
        self.light_gw = StatusLight(frame, size=12)
        self.light_gw.grid(row=0, column=2, padx=(0, 10), pady=8)
        
        self.lbl_gw_state = ttk.Label(frame, textvariable=self.status_gw_text, style="StatusRed.TLabel")
        self.lbl_gw_state.grid(row=0, column=3, sticky="w", pady=8)

        # --- Row 1: Node ---
        ttk.Label(frame, text="💻", style="Emoji.TLabel").grid(row=1, column=0, padx=(5, 10), pady=8)
        ttk.Label(frame, text="Node", style="Title.TLabel").grid(row=1, column=1, sticky="w", padx=(0, 20), pady=8)
        
        self.light_node = StatusLight(frame, size=12)
        self.light_node.grid(row=1, column=2, padx=(0, 10), pady=8)
        
        self.lbl_node_state = ttk.Label(frame, textvariable=self.status_node_text, style="StatusRed.TLabel")
        self.lbl_node_state.grid(row=1, column=3, sticky="w", pady=8)

        # --- Settings ---
        cb_tray = ttk.Checkbutton(frame, text="最小化到托盘", variable=self.var_minimize_tray, command=self.save_tray_setting)
        cb_tray.grid(row=0, column=5, rowspan=2, sticky="e", padx=10)

        # --- Buttons ---
        btn_frame = ttk.Frame(frame)
        btn_frame.grid(row=2, column=0, columnspan=6, pady=(25, 5), sticky="w")

        btn_width = 20
        ttk.Button(btn_frame, text="🚀  一键启动", style="Accent.TButton", width=btn_width, command=self.start_services).pack(side="left", padx=(0, 10))
        ttk.Button(btn_frame, text="🛑  全部停止", style="Stop.TButton", width=btn_width, command=self.stop_all).pack(side="left", padx=10)

    # --- Event Handlers ---
    def on_resize_event(self, event):
        if event.widget == self.root:
            self.is_resizing = True
            if self._resize_timer:
                self.root.after_cancel(self._resize_timer)
            self._resize_timer = self.root.after(200, self._stop_resizing)

    def _stop_resizing(self):
        self.is_resizing = False
        self.root.after(0, self.update_ui_status)

    def sync_ui(self):
        if self.is_resizing: return
        c = self.ui_cache
        self.light_gw.set_color(c["gw_color"])
        self.lbl_gw_state.config(style=c["gw_style"])
        self.light_node.set_color(c["node_color"])
        self.lbl_node_state.config(style=c["node_style"])

    def update_ui_status(self):
        # 1. Canvas
        if self.status_gw_style == "StatusGreen.TLabel":
            self.light_gw.set_color("#2f9e44")
        else:
            self.light_gw.set_color("#adb5bd")
            
        if self.status_node_style == "StatusGreen.TLabel":
            self.light_node.set_color("#2f9e44")
        elif self.status_node_style == "StatusYellow.TLabel":
            self.light_node.set_color("#f59f00")
        else:
            self.light_node.set_color("#adb5bd")

        # 2. Label
        self.lbl_gw_state.config(style=self.status_gw_style)
        self.lbl_node_state.config(style=self.status_node_style)

    def save_tray_setting(self):
        self.config["minimize_to_tray"] = self.var_minimize_tray.get()
        save_config(self.config)

    def log(self, widget, msg, tag='INFO'):
        def _write():
            timestamp = time.strftime("%H:%M:%S", time.localtime())
            widget.insert(tk.END, f"[{timestamp}] {msg}\n", tag)
            widget.see(tk.END)
        self.root.after(0, _write)

    def on_close_click(self):
        if messagebox.askyesno("退出确认", "确定要停止服务并退出程序吗？"):
            self.quit_app()

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
        except:
            dc.ellipse((10, 10, 54, 54), fill="#ff4500", outline="white")
        return image

    def setup_tray_icon(self):
        menu = (
            pystray.MenuItem('显示主界面', self.show_window, default=True),
            pystray.MenuItem('退出程序', self.quit_app)
        )
        self.icon = pystray.Icon("ClawdLauncher", self.create_tray_image(), "Clawdbot", menu)
        threading.Thread(target=self.icon.run, daemon=True).start()

    def quit_app(self, icon=None, item=None):
        self.is_quitting = True
        self.stop_all()
        try: self.icon.stop() 
        except: pass
        self.root.quit()
        sys.exit()

    def run_process_in_background(self, cmd_str, process_attr, log_widget, success_trigger=None):
        try:
            startupinfo = subprocess.STARTUPINFO()
            startupinfo.dwFlags |= subprocess.STARTF_USESHOWWINDOW
            creation_flags = subprocess.CREATE_NO_WINDOW
            process = subprocess.Popen(cmd_str, stdout=subprocess.PIPE, stderr=subprocess.STDOUT, text=True, encoding='utf-8', errors='replace', startupinfo=startupinfo, creationflags=creation_flags, shell=True)
            setattr(self, process_attr, process)
            self.log(log_widget, f"执行命令: {cmd_str}", 'CMD')
            for line in process.stdout:
                line = line.strip()
                if line:
                    self.log(log_widget, line)
                    if success_trigger: success_trigger(line)
            self.log(log_widget, "进程已退出。", 'ERROR')
            setattr(self, process_attr, None)
            if process_attr == 'proc_gateway': self.gateway_ready = False
        except Exception as e: self.log(log_widget, f"启动失败: {e}", 'ERROR')

    # ==========================================
    #  Gateway 检测与启动逻辑
    # ==========================================
    def check_gateway_status(self):
        try:
            startupinfo = subprocess.STARTUPINFO()
            startupinfo.dwFlags |= subprocess.STARTF_USESHOWWINDOW
            # 静默执行 clawdbot gateway status
            result = subprocess.run(
                "clawdbot gateway status", 
                capture_output=True, 
                text=True, 
                shell=True, 
                encoding='utf-8', 
                errors='replace', 
                startupinfo=startupinfo, 
                creationflags=subprocess.CREATE_NO_WINDOW
            )
            output = result.stdout + result.stderr
            # 判定标准：包含 "RPC probe: ok" 或 "Listening:"
            if "RPC probe: ok" in output or "Listening:" in output:
                return True
            return False
        except:
            return False

    def start_services(self):
        # 使用新的检测逻辑判断 Gateway 是否运行
        if self.check_gateway_status():
            self.log(self.txt_system, "Gateway 已在运行中。", "INFO")
            self.gateway_ready = True
        else:
            self.gateway_ready = False
            def gateway_trigger(line):
                if "Ctrl+C to stop" in line:
                    self.log(self.txt_gateway, ">>> Gateway 就绪 <<<", "SUCCESS")
                    self.gateway_ready = True
            threading.Thread(target=self.run_process_in_background, args=("clawdbot gateway", "proc_gateway", self.txt_gateway, gateway_trigger), daemon=True).start()
        
        self.node_connected_flag = False
        delay = 5 
        def start_node():
            if delay: 
                self.log(self.txt_node, f"等待 {delay} 秒...", "INFO")
                time.sleep(delay)
            threading.Thread(target=self.run_process_in_background, args=('clawdbot node run --host 127.0.0.1 --port 18789 --display-name "MyWinPC"', "proc_node", self.txt_node, None), daemon=True).start()
        threading.Thread(target=start_node, daemon=True).start()

    def stop_all(self):
        self.log(self.txt_system, "正在停止所有服务...", "INFO")
        if self.proc_gateway: subprocess.run(f"taskkill /F /T /PID {self.proc_gateway.pid}", shell=True, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL, creationflags=subprocess.CREATE_NO_WINDOW)
        if self.proc_node: subprocess.run(f"taskkill /F /T /PID {self.proc_node.pid}", shell=True, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL, creationflags=subprocess.CREATE_NO_WINDOW)
        subprocess.run("taskkill /F /IM clawdbot.exe", shell=True, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL, creationflags=subprocess.CREATE_NO_WINDOW)
        subprocess.run("taskkill /F /IM node.exe", shell=True, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL, creationflags=subprocess.CREATE_NO_WINDOW)
        self.gateway_ready = False
        self.node_connected_flag = False
        self.log(self.txt_system, "停止指令已发送。", "INFO")

    # ==========================================
    #  Node 检测逻辑
    # ==========================================
    def check_status_once(self, manual=False):
        try:
            startupinfo = subprocess.STARTUPINFO()
            startupinfo.dwFlags |= subprocess.STARTF_USESHOWWINDOW
            result = subprocess.run("clawdbot nodes status", capture_output=True, text=True, shell=True, encoding='utf-8', creationflags=subprocess.CREATE_NO_WINDOW)
            output = result.stdout
            if manual: self.log(self.txt_system, output)
            
            # 判定标准：
            # 1. Connected: [数字1-9] (原逻辑)
            # 2. 表格中包含 "paired · connected" (新逻辑)
            is_connected = False
            if re.search(r"Connected:\s*[1-9]", output):
                is_connected = True
            elif "paired · connected" in output:
                is_connected = True

            if is_connected:
                if not self.node_connected_flag:
                    self.log(self.txt_node, ">>> 连接确认 (Node Connected) <<<", "SUCCESS")
                    if not manual: self.log(self.txt_system, ">>> 自动检测：Node 已连接 <<<", "SUCCESS")
                self.node_connected_flag = True
                return True
            else:
                self.node_connected_flag = False
                return False
        except Exception as e:
            if manual: self.log(self.txt_system, f"检测失败: {e}", "ERROR")
            return False

    def monitor_loop(self):
        last_state_hash = None
        while True:
            if self.is_quitting: break
            
            # --- Logic ---
            gw_text = "未运行"
            gw_color = "#adb5bd"
            gw_style = "StatusRed.TLabel"
            
            # 修改点：使用命令检测 Gateway
            if self.check_gateway_status():
                gw_text = "运行中"
                gw_color = "#2f9e44"
                gw_style = "StatusGreen.TLabel"
                self.gateway_ready = True
            else:
                self.gateway_ready = False

            node_text = "未运行"
            node_color = "#adb5bd"
            node_style = "StatusRed.TLabel"
            
            # Node 状态逻辑保持微调，依赖 check_status_once 的更新
            if self.proc_node and self.proc_node.poll() is None:
                if self.node_connected_flag:
                    node_text = "已连接"
                    node_color = "#2f9e44"
                    node_style = "StatusGreen.TLabel"
                else:
                    node_text = "连接中..."
                    node_color = "#f59f00"
                    node_style = "StatusYellow.TLabel"
                    self.check_status_once(manual=False)
            else:
                self.node_connected_flag = False

            # --- Update ---
            current_data = {
                "gw_text": gw_text, "gw_color": gw_color, "gw_style": gw_style,
                "node_text": node_text, "node_color": node_color, "node_style": node_style
            }
            current_hash = str(current_data)

            if current_hash != last_state_hash:
                self.ui_cache = current_data
                self.status_gw_text.set(gw_text)
                self.status_node_text.set(node_text)
                self.root.after(0, self.sync_ui)
                last_state_hash = current_hash

            if self.node_connected_flag:
                time.sleep(3)
            else:
                time.sleep(1.5)

if __name__ == "__main__":
    try:
        root = tk.Tk()
        app = ClawdLauncher(root)
        root.protocol("WM_DELETE_WINDOW", app.on_close_click)
        root.mainloop()
    except Exception as e:
        show_critical_error(traceback.format_exc())