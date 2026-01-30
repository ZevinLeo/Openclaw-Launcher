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
# 3. 状态灯组件
# ==========================================
class StatusLight(tk.Canvas):
    def __init__(self, parent, size=14):
        super().__init__(parent, width=size, height=size, highlightthickness=0, borderwidth=0)
        self.indicator = self.create_oval(1, 1, size-1, size-1, fill="#adb5bd", outline="")
    
    def set_color(self, color):
        self.itemconfig(self.indicator, fill=color)

# ==========================================
# 4. 日志组件 (高性能版)
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
            wrap="word",  # 默认平时是自动换行的
            font=("Consolas", 10), 
            padx=10, pady=10, 
            borderwidth=0, 
            highlightthickness=0, 
            takefocus=0, 
            bg="#f4f4f4", 
            fg="#333333",
            **kwargs
        )
        self.text.pack(side="left", fill="both", expand=True)
        self.v_scroll.config(command=self.text.yview)
        
        self.text.tag_config('INFO', foreground='')
        self.text.tag_config('ERROR', foreground='#d32f2f') 
        self.text.tag_config('SUCCESS', foreground='#2e7d32') 
        self.text.tag_config('CMD', foreground='#1565c0') 

    def insert(self, *args):
        try:
            self.text.config(state='normal')
            self.text.insert(*args)
            self.text.config(state='disabled')
            # 自动滚动到底部
            self.text.see(tk.END)
        except: pass
    
    def see(self, *args):
        try: self.text.see(*args)
        except: pass

    # [核心] 切换渲染模式
    def set_performance_mode(self, enabled):
        """
        enabled=True:  开启高性能模式（wrap='none'），用于拖拽中。
        enabled=False: 关闭高性能模式（wrap='word'），用于静止时。
        """
        try:
            target_wrap = "none" if enabled else "word"
            if self.text.cget("wrap") != target_wrap:
                self.text.config(wrap=target_wrap)
        except: pass

# ==========================================
# 5. 主程序
# ==========================================
class ClawdLauncher:
    def __init__(self, root):
        self.root = root
        self.root.title("Clawdbot 启动器")
        
        # [锁定窗口限制]
        self.root.geometry("1200x900")
        self.root.minsize(1200, 900)
        
        # [核心] 渲染挂起与缓冲机制初始化
        self._ui_suspended = False  # 是否挂起 UI 渲染
        self._log_buffer = []       # 日志缓冲区
        self._resize_timer = None   # 防抖计时器
        
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
        self.ui_cache = {"gw_color": "#adb5bd", "gw_style": "StatusRed.TLabel", "node_color": "#adb5bd", "node_style": "StatusRed.TLabel"}

        self.apply_styles()

        # UI 布局
        self.top_frame = ttk.Frame(root, padding=25)
        self.top_frame.pack(side=tk.TOP, fill=tk.X)
        self.setup_dashboard(self.top_frame)

        self.bottom_frame = ttk.Frame(root, padding=(25, 0, 25, 25))
        self.bottom_frame.pack(side=tk.BOTTOM, fill=tk.BOTH, expand=True)

        lbl_log = tk.Label(
            self.bottom_frame, 
            text=" 运行日志", 
            font=("Microsoft YaHei UI", 10, "bold"), 
            bg="#e0e0e0", 
            fg="#333333", 
            anchor="w", 
            padx=10,
            pady=6,
            relief="flat"
        )
        lbl_log.pack(fill="x", pady=(0, 0))
        
        self.txt_system = ModernLog(self.bottom_frame)

        try: self.setup_tray_icon()
        except: pass
        
        self.monitor_thread = threading.Thread(target=self.monitor_loop, daemon=True)
        self.monitor_thread.start()
        
        self.root.bind("<Unmap>", self.on_minimize_event)
        
        # [核心] 绑定 Configure 事件，涵盖拖动和拉伸
        self.root.bind("<Configure>", self.on_resize_event)
        self.root.protocol("WM_DELETE_WINDOW", self.on_close_click)

    # ==========================================
    #  核心优化逻辑：UI 挂起与防抖
    # ==========================================
    def on_resize_event(self, event):
        # 1. 过滤非主窗口事件
        if event.widget != self.root: return

        # 2. 只要触发了 Configure (位置移动或大小改变)，立即挂起 UI
        if not self._ui_suspended:
            self._ui_suspended = True
            # 切换日志到高性能模式（不换行），为后续恢复做准备
            self.txt_system.set_performance_mode(True) 
        
        # 3. 防抖计时器重置
        if self._resize_timer: 
            self.root.after_cancel(self._resize_timer)
        
        # 4. 设定 300ms 倒计时：如果 300ms 内没有新动作，认为操作结束
        self._resize_timer = self.root.after(300, self._stop_resizing)

    def _stop_resizing(self):
        # 1. 清理计时器
        self._resize_timer = None
        
        # 2. 恢复日志组件的自动换行（重排版，消耗性能但显示美观）
        self.txt_system.set_performance_mode(False)
        
        # 3. 处理缓冲区堆积的日志 (Flush Buffer)
        if self._log_buffer:
            def _flush_buffer():
                self.txt_system.text.config(state='normal')
                for msg, tag in self._log_buffer:
                    self.txt_system.text.insert(tk.END, msg, tag)
                self.txt_system.text.config(state='disabled')
                self.txt_system.text.see(tk.END)
                # 清空缓冲区
                self._log_buffer.clear()
            
            # 执行刷新
            _flush_buffer()

        # 4. 解除挂起标志，并强制刷新一次状态 UI
        self._ui_suspended = False 
        self.sync_ui() 

    # ==========================================
    #  UI 与日志逻辑
    # ==========================================
    def log(self, widget, msg, tag='INFO'):
        timestamp = time.strftime("%H:%M:%S", time.localtime())
        formatted_msg = f"[{timestamp}] {msg}\n"

        # [核心] 如果 UI 处于挂起状态（正在拖拽），只存缓冲区，不渲染
        if self._ui_suspended:
            self._log_buffer.append((formatted_msg, tag))
            return

        # 正常状态：直接写入界面
        def _write():
            widget.insert(tk.END, formatted_msg, tag)
        self.root.after(0, _write)

    def sync_ui(self):
        # [核心] 如果 UI 挂起，跳过更新
        if self._ui_suspended: return
        
        c = self.ui_cache
        self.light_gw.set_color(c["gw_color"])
        self.lbl_gw_state.config(style=c["gw_style"])
        self.light_node.set_color(c["node_color"])
        self.lbl_node_state.config(style=c["node_style"])

    def update_ui_status(self):
        # 计算当前应该显示的颜色，存入 Cache
        if self.status_gw_style == "StatusGreen.TLabel": gw_c = "#2f9e44"
        else: gw_c = "#adb5bd"
        
        if self.status_node_style == "StatusGreen.TLabel": node_c = "#2f9e44"
        elif self.status_node_style == "StatusYellow.TLabel": node_c = "#f59f00"
        else: node_c = "#adb5bd"

        self.ui_cache = {
            "gw_color": gw_c, "gw_style": self.status_gw_style,
            "node_color": node_c, "node_style": self.status_node_style
        }
        # 触发同步
        self.root.after(0, self.sync_ui)

    def apply_styles(self):
        style = ttk.Style()
        style.configure(".", font=self.f_small)
        style.configure("TButton", font=self.f_body)
        style.configure("Accent.TButton", font=self.f_body)
        style.configure("TLabelframe.Label", font=self.f_small, foreground="#0078d4")
        
        style.configure("Tray.TCheckbutton", font=self.f_small)
        
        style.configure("Title.TLabel", font=self.f_title)
        style.configure("StatusGreen.TLabel", foreground="#2f9e44", font=self.f_small)
        style.configure("StatusRed.TLabel", foreground="gray", font=self.f_small)
        style.configure("StatusYellow.TLabel", foreground="#f59f00", font=self.f_small)
        style.configure("Emoji.TLabel", font=self.f_emoji) 
        
        style.configure("Stop.TButton", foreground="#d65745", font=self.f_body)
        style.configure("Link.TButton", foreground="#0078d4", font=self.f_body) 

    def setup_dashboard(self, parent):
        frame = ttk.LabelFrame(parent, text=" 控制面板 ", padding=20)
        frame.pack(fill="x", expand=True)
        self.var_minimize_tray = tk.BooleanVar(value=self.config.get("minimize_to_tray", False))
        frame.columnconfigure(4, weight=1) 

        # Gateway Row
        ttk.Label(frame, text="🧠", style="Emoji.TLabel").grid(row=0, column=0, padx=(5, 10), pady=8)
        ttk.Label(frame, text="Gateway", style="Title.TLabel").grid(row=0, column=1, sticky="w", padx=(0, 20), pady=8)
        self.light_gw = StatusLight(frame, size=12)
        self.light_gw.grid(row=0, column=2, padx=(0, 10), pady=8)
        self.lbl_gw_state = ttk.Label(frame, textvariable=self.status_gw_text, style="StatusRed.TLabel")
        self.lbl_gw_state.grid(row=0, column=3, sticky="w", pady=8)

        # Node Row
        ttk.Label(frame, text="💻", style="Emoji.TLabel").grid(row=1, column=0, padx=(5, 10), pady=8)
        ttk.Label(frame, text="Node", style="Title.TLabel").grid(row=1, column=1, sticky="w", padx=(0, 20), pady=8)
        self.light_node = StatusLight(frame, size=12)
        self.light_node.grid(row=1, column=2, padx=(0, 10), pady=8)
        self.lbl_node_state = ttk.Label(frame, textvariable=self.status_node_text, style="StatusRed.TLabel")
        self.lbl_node_state.grid(row=1, column=3, sticky="w", pady=8)

        # Settings
        cb_tray = ttk.Checkbutton(
            frame, 
            text="最小化到托盘", 
            variable=self.var_minimize_tray, 
            command=self.save_tray_setting, 
            style="Tray.TCheckbutton", 
            takefocus=0
        )
        cb_tray.grid(row=0, column=5, rowspan=2, sticky="e", padx=10)

        # Buttons
        # [锁定逻辑] sticky="w" + expand=False + fill=tk.NONE
        btn_frame = ttk.Frame(frame)
        btn_frame.grid(row=2, column=0, columnspan=6, pady=(25, 5), sticky="w") 
        
        btn_width = 20
        
        btn1 = ttk.Button(btn_frame, text="🚀  一键启动", style="Accent.TButton", width=btn_width, takefocus=0, command=self.start_services)
        btn1.pack(side="left", padx=(0, 10), expand=False, fill=tk.NONE)
        
        btn2 = ttk.Button(btn_frame, text="🛑  全部停止", style="Stop.TButton", width=btn_width, takefocus=0, command=lambda: threading.Thread(target=self.stop_all).start())
        btn2.pack(side="left", padx=10, expand=False, fill=tk.NONE)
        
        btn3 = ttk.Button(btn_frame, text="🌐  Web 控制台", style="Link.TButton", width=btn_width, takefocus=0, command=self.open_web_ui)
        btn3.pack(side="left", padx=10, expand=False, fill=tk.NONE)

    # ==========================================
    #  业务逻辑与后台任务
    # ==========================================
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
        self.icon = pystray.Icon("ClawdLauncher", self.create_tray_image(), "Clawdbot", menu)
        threading.Thread(target=self.icon.run, daemon=True).start()

    def quit_app(self, icon=None, item=None):
        self.is_quitting = True
        self.root.withdraw()
        try: self.icon.stop() 
        except: pass
        self.stop_all(logging=False)
        self.root.destroy()
        sys.exit(0)

    def run_process_in_background(self, cmd_str, process_attr, log_widget, success_trigger=None):
        try:
            startupinfo = subprocess.STARTUPINFO()
            startupinfo.dwFlags |= subprocess.STARTF_USESHOWWINDOW
            creation_flags = subprocess.CREATE_NO_WINDOW
            process = subprocess.Popen(
                cmd_str, stdout=subprocess.PIPE, stderr=subprocess.STDOUT, 
                text=True, encoding='utf-8', errors='replace', 
                startupinfo=startupinfo, creationflags=creation_flags, shell=True
            )
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
        webbrowser.open("http://127.0.0.1:18789/")

    def _start_node_internal(self):
        if self.proc_node and self.proc_node.poll() is None:
             self.log(self.txt_system, "Node 进程已在运行。", "INFO")
             return
        self.log(self.txt_system, "正在启动 Node...", "INFO")
        node_cmd = 'clawdbot node run --host 127.0.0.1 --port 18789 --display-name "MyWinPC"'
        threading.Thread(
            target=self.run_process_in_background, 
            args=(node_cmd, "proc_node", self.txt_system, None), 
            daemon=True
        ).start()

    def start_services(self):
        if self.check_gateway_http():
            self.log(self.txt_system, "Gateway 服务已就绪。", "INFO")
            self.gateway_ready = True
            self._start_node_internal()
        else:
            self.gateway_ready = False
            self.log(self.txt_system, "Gateway 未运行，正在启动...", "INFO")
            cmd = "clawdbot gateway"
            
            # A. 启动进程
            threading.Thread(
                target=self.run_process_in_background, 
                args=(cmd, "proc_gateway", self.txt_system, None),
                daemon=True
            ).start()

            # B. 轮询检测
            def wait_for_gateway():
                self.log(self.txt_system, "等待 Gateway 就绪...", "INFO")
                for _ in range(30):
                    time.sleep(0.5)
                    if self.check_gateway_http():
                        self.log(self.txt_system, ">>> Gateway 启动成功 (检测通过) <<<", "SUCCESS")
                        self.gateway_ready = True
                        self.root.after(50, self._start_node_internal)
                        return
                self.log(self.txt_system, "❌ Gateway 启动超时，请检查日志。", "ERROR")
            threading.Thread(target=wait_for_gateway, daemon=True).start()

    def stop_all(self, logging=True):
        if logging: self.log(self.txt_system, "正在停止所有服务...", "INFO")
        kill_flags = subprocess.CREATE_NO_WINDOW
        
        if self.proc_gateway: subprocess.run(f"taskkill /F /T /PID {self.proc_gateway.pid}", shell=True, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL, creationflags=kill_flags)
        if self.proc_node: subprocess.run(f"taskkill /F /T /PID {self.proc_node.pid}", shell=True, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL, creationflags=kill_flags)
        
        subprocess.run("taskkill /F /IM clawdbot.exe", shell=True, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL, creationflags=kill_flags)
        subprocess.run("taskkill /F /IM node.exe", shell=True, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL, creationflags=kill_flags)
        
        self.gateway_ready = False
        self.node_connected_flag = False
        if logging: self.log(self.txt_system, "已发送停止指令。", "INFO")

    def check_status_once(self, manual=False):
        try:
            startupinfo = subprocess.STARTUPINFO()
            startupinfo.dwFlags |= subprocess.STARTF_USESHOWWINDOW
            result = subprocess.run("clawdbot nodes status", capture_output=True, text=True, shell=True, encoding='utf-8', creationflags=subprocess.CREATE_NO_WINDOW)
            output = result.stdout
            if manual: self.log(self.txt_system, output)
            
            is_connected = False
            if re.search(r"Connected:\s*[1-9]", output): is_connected = True
            elif "paired · connected" in output: is_connected = True

            if is_connected:
                if not self.node_connected_flag:
                    self.log(self.txt_system, ">>> Node 连接成功 (Connected) <<<", "SUCCESS")
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
            
            # 1. 检测 Gateway
            if self.check_gateway_http():
                self.status_gw_style = "StatusGreen.TLabel"
                gw_text = "运行中"
                self.gateway_ready = True
            else:
                self.status_gw_style = "StatusRed.TLabel"
                gw_text = "未运行"
                self.gateway_ready = False

            # 2. 检测 Node
            self.status_node_style = "StatusRed.TLabel"
            node_text = "未运行"

            if self.gateway_ready:
                if self.proc_node and self.proc_node.poll() is None:
                    if self.node_connected_flag:
                        self.status_node_style = "StatusGreen.TLabel"
                        node_text = "已连接"
                    else:
                        self.status_node_style = "StatusYellow.TLabel"
                        node_text = "连接中..."
                        self.check_status_once(manual=False)
                else:
                    self.node_connected_flag = False

            # --- 刷新 UI ---
            self.status_gw_text.set(gw_text)
            self.status_node_text.set(node_text)
            
            # 触发防抖/挂起兼容的 UI 更新
            self.update_ui_status()

            time.sleep(1.5 if not self.node_connected_flag else 3)

if __name__ == "__main__":
    try:
        root = tk.Tk()
        app = ClawdLauncher(root)
        root.mainloop()
    except Exception as e:
        show_critical_error(traceback.format_exc())