use iced::widget::{
    button, column, container, horizontal_space, pick_list, row, scrollable, text, text_editor,
    text_input, Column, Container, Row, Space, vertical_space,
};
use iced::{
    alignment, Application, Color, Command, Element, Length, Settings, Theme,
    Background, border, Padding, window, Font,
};
use std::sync::Arc;

// ==========================================
// 1. 程序入口
// ==========================================
pub fn main() -> iced::Result {
    OpenClawApp::run(Settings {
        window: window::Settings {
            size: (1200.0, 900.0).into(),
            min_size: Some((1100.0, 800.0).into()),
            position: window::Position::Centered,
            ..Default::default()
        },
        default_font: Font::with_name("Microsoft YaHei UI"), 
        ..Default::default()
    })
}

// ==========================================
// 2. 数据结构 (State)
// ==========================================

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
enum Tab {
    Soul,
    Models,
    Channels,
    Skills,
    Security,
}

impl Tab {
    fn title(&self) -> &str {
        match self {
            Tab::Soul => "🤖 核心记忆",
            Tab::Models => "🧠 模型配置",
            Tab::Channels => "🔌 渠道连接",
            Tab::Skills => "⚡ 技能管理",
            Tab::Security => "🔒 安全网关",
        }
    }
}

struct OpenClawApp {
    // 界面状态
    active_tab: Tab,
    selected_agent: Option<String>,
    agents: Vec<String>,
    
    // Soul 面板数据
    file_tree: Vec<String>,
    current_file_path: String,
    editor_content: text_editor::Content,
    
    // Models 面板数据
    model_primary: String,
    model_image: String,
    tts_enabled: bool,
    
    // 颜色配置
    color_bg_main: Color,   // 右侧内容背景
    color_bg_side: Color,   // 左侧栏背景
    color_accent: Color,    // 强调色
}

#[derive(Debug, Clone)]
enum Message {
    TabSelected(Tab),
    AgentSelected(String),
    FileSelected(String),
    EditorAction(text_editor::Action),
    ModelPrimaryChanged(String),
    ModelImageChanged(String),
    TtsToggled(bool),
    SaveClicked,
}

// ==========================================
// 3. 逻辑实现
// ==========================================
impl Application for OpenClawApp {
    type Executor = iced::executor::Default;
    type Message = Message;
    type Theme = Theme;
    type Flags = ();

    fn new(_flags: ()) -> (Self, Command<Message>) {
        (
            Self {
                active_tab: Tab::Soul,
                selected_agent: Some("main".to_string()),
                agents: vec!["main".to_string(), "assistant_beta".to_string()],
                
                file_tree: vec![
                    "AGENTS.md".to_string(), "SOUL.md".to_string(), 
                    "USER.md".to_string(), "IDENTITY.md".to_string()
                ],
                current_file_path: "SOUL.md".to_string(),
                editor_content: text_editor::Content::with_text(include_str!("main.rs")), 
                
                model_primary: "gpt-4".to_string(),
                model_image: "dall-e-3".to_string(),
                tts_enabled: false,

                // 现代配色方案
                color_bg_main: Color::from_rgb8(245, 245, 245), // #f5f5f5 (最右侧大背景)
                color_bg_side: Color::from_rgb8(230, 230, 230), // #e6e6e6 (侧边栏背景)
                color_accent: Color::from_rgb8(0, 120, 212),    // #0078d4 (Win11 蓝)
            },
            Command::none(),
        )
    }

    fn title(&self) -> String {
        String::from("OpenClaw 高级管理 (Rust Native)")
    }

    fn update(&mut self, message: Message) -> Command<Message> {
        match message {
            Message::TabSelected(tab) => self.active_tab = tab,
            Message::AgentSelected(agent) => self.selected_agent = Some(agent),
            Message::FileSelected(file) => {
                self.current_file_path = file;
                self.editor_content = text_editor::Content::with_text(&format!("// 正在编辑: {}\n// Rust 渲染引擎无延迟...", self.current_file_path));
            }
            Message::EditorAction(action) => self.editor_content.perform(action),
            Message::ModelPrimaryChanged(val) => self.model_primary = val,
            Message::ModelImageChanged(val) => self.model_image = val,
            Message::TtsToggled(val) => self.tts_enabled = val,
            Message::SaveClicked => println!("Saved!"),
        }
        Command::none()
    }

    // ==========================================
    // 4. 视图布局 (核心修改区域)
    // ==========================================
    fn view(&self) -> Element<Message> {
        // --- 1. 顶部 Header (横跨整个窗口) ---
        let header = container(
            row![
                text("🛠️").size(24),
                text("OpenClaw 控制中心").size(18).style(Color::from_rgb8(50, 50, 50)),
                horizontal_space(),
                text("当前智能体:").size(14),
                pick_list(
                    self.agents.as_slice(),
                    self.selected_agent.clone(),
                    Message::AgentSelected
                ).width(150)
            ]
            .spacing(15)
            .align_items(alignment::Alignment::Center)
        )
        .padding(15)
        .style(move |_| container::Appearance {
            background: Some(Background::Color(Color::WHITE)), // Header 纯白背景
            border: border::Border {
                color: Color::from_rgb8(220, 220, 220),
                width: 1.0,
                radius: 0.0.into(),
            },
            ..Default::default()
        })
        .width(Length::Fill);

        // --- 2. 左侧侧边栏 (Sidebar) ---
        // 垂直排列的按钮
        let sidebar_buttons = column(
            [Tab::Soul, Tab::Models, Tab::Channels, Tab::Skills, Tab::Security]
                .iter()
                .map(|tab| {
                    let is_active = self.active_tab == *tab;
                    
                    // 侧边栏按钮样式
                    let btn_style = if is_active {
                        style_sidebar_active(self.color_bg_main, self.color_accent) // 选中：背景变亮，左侧蓝条
                    } else {
                        style_sidebar_inactive() // 未选中：透明
                    };

                    button(
                        container(text(tab.title()).size(14))
                            .width(Length::Fill)
                            .center_x() // 文字居中，也可以改成左对齐
                    )
                    .on_press(Message::TabSelected(*tab))
                    .style(btn_style)
                    .padding([15, 0]) // 增加垂直内边距，按钮更高
                    .width(Length::Fill)
                    .into()
                })
                .collect()
        )
        .spacing(5);

        let sidebar = container(sidebar_buttons)
            .width(Length::Fixed(220.0)) // 固定侧边栏宽度
            .height(Length::Fill)
            .padding([20, 10]) // 内部留白
            .style(move |_| container::Appearance {
                background: Some(Background::Color(self.color_bg_side)),
                ..Default::default()
            });

        // --- 3. 右侧内容区 (Content) ---
        let content_view: Element<_> = match self.active_tab {
            Tab::Soul => self.view_soul(),
            Tab::Models => self.view_models(),
            Tab::Channels => self.view_placeholder("渠道连接模块"),
            Tab::Skills => self.view_placeholder("技能管理模块"),
            Tab::Security => self.view_placeholder("安全网关模块"),
        };

        let content_area = container(content_view)
            .width(Length::Fill)
            .height(Length::Fill)
            .padding(25)
            .style(move |_| container::Appearance {
                background: Some(Background::Color(self.color_bg_main)),
                ..Default::default()
            });

        // --- 4. 整体组装 (Header 在上，下面是 侧边栏+内容) ---
        column![
            header,
            row![
                sidebar,
                content_area
            ]
        ]
        .into()
    }

    fn theme(&self) -> Theme {
        Theme::Light
    }
}

// ==========================================
// 5. 面板实现
// ==========================================
impl OpenClawApp {
    fn view_soul(&self) -> Element<Message> {
        let file_list = column(
            self.file_tree.iter().map(|f| {
                let is_sel = self.current_file_path == *f;
                button(
                    row![text(if is_sel {"📝"} else {"📄"}), text(f)].spacing(10)
                )
                .on_press(Message::FileSelected(f.clone()))
                .width(Length::Fill)
                .padding(10)
                .style(if is_sel { theme::Button::Primary } else { theme::Button::Text })
                .into()
            })
            .collect()
        ).spacing(2);

        let editor = text_editor(&self.editor_content)
            .on_action(Message::EditorAction)
            .height(Length::Fill)
            .padding(15)
            .style(style_editor_box);

        let right_col = column![
            row![
                text(format!("正在编辑: {}", self.current_file_path)).size(14),
                horizontal_space(),
                button("💾 保存修改").on_press(Message::SaveClicked).style(theme::Button::Primary).padding([8, 20])
            ].align_items(alignment::Alignment::Center),
            
            editor
        ].spacing(10);

        row![
            container(file_list).width(Length::FillPortion(1)).style(style_card).padding(5),
            horizontal_space().width(20),
            container(right_col).width(Length::FillPortion(4)).style(style_card).padding(20)
        ]
        .height(Length::Fill)
        .into()
    }

    fn view_models(&self) -> Element<Message> {
        let form = column![
            text("🧠 核心模型配置").size(20),
            vertical_space(10),
            row![
                text("主模型 (Primary):").width(150),
                text_input("如 gpt-4", &self.model_primary).on_input(Message::ModelPrimaryChanged).padding(10)
            ].align_items(alignment::Alignment::Center),
            
            row![
                text("视觉模型 (Image):").width(150),
                text_input("如 dall-e-3", &self.model_image).on_input(Message::ModelImageChanged).padding(10)
            ].align_items(alignment::Alignment::Center),
            
            vertical_space(20),
            
            text("🗣️ TTS 语音配置").size(20),
            row![
                text("启用 TTS:").width(150),
                iced::widget::checkbox("启用语音播报", self.tts_enabled).on_toggle(Message::TtsToggled)
            ].align_items(alignment::Alignment::Center),
            
            vertical_space(Length::Fill),
            
            row![
                horizontal_space(),
                button("💾 保存所有配置").on_press(Message::SaveClicked).style(theme::Button::Primary).padding([12, 30])
            ]
        ]
        .spacing(15)
        .padding(30);

        container(form).style(style_card).width(Length::Fill).height(Length::Fill).into()
    }

    fn view_placeholder(&self, title: &str) -> Element<Message> {
        container(
            column![
                text(title).size(30).style(Color::from_rgb8(200, 200, 200)),
                text("Rust 高性能渲染演示").size(16).style(Color::from_rgb8(150, 150, 150))
            ].spacing(10).align_items(alignment::Alignment::Center)
        )
        .width(Length::Fill)
        .height(Length::Fill)
        .center_x()
        .center_y()
        .style(style_card)
        .into()
    }
}

// ==========================================
// 6. 样式定义 (Styles)
// ==========================================

fn style_card(theme: &Theme) -> container::Appearance {
    container::Appearance {
        background: Some(Background::Color(Color::WHITE)),
        border: border::Border {
            color: Color::from_rgb8(220, 220, 220),
            width: 1.0,
            radius: 8.0.into(),
        },
        shadow: iced::Shadow {
            color: Color::from_rgba8(0, 0, 0, 0.05),
            offset: iced::Vector::new(0.0, 2.0),
            blur_radius: 5.0,
        },
        ..Default::default()
    }
}

fn style_editor_box(_theme: &Theme, status: text_editor::Status) -> text_editor::Appearance {
    let active = status == text_editor::Status::Focused;
    text_editor::Appearance {
        background: Background::Color(Color::from_rgb8(250, 250, 250)),
        border: border::Border {
            color: if active { Color::from_rgb8(0, 120, 212) } else { Color::from_rgb8(200, 200, 200) },
            width: if active { 1.5 } else { 1.0 },
            radius: 4.0.into(),
        },
        ..Default::default()
    }
}

// 侧边栏按钮样式 - 选中
fn style_sidebar_active(bg: Color, accent: Color) -> theme::Button {
    theme::Button::Custom(Box::new(SidebarBtnStyle { bg, text: accent, active: true }))
}

// 侧边栏按钮样式 - 未选中
fn style_sidebar_inactive() -> theme::Button {
    theme::Button::Custom(Box::new(SidebarBtnStyle { 
        bg: Color::TRANSPARENT, 
        text: Color::from_rgb8(80, 80, 80), 
        active: false 
    }))
}

struct SidebarBtnStyle { bg: Color, text: Color, active: bool }
impl button::StyleSheet for SidebarBtnStyle {
    type Style = Theme;
    fn active(&self, _style: &Self::Style) -> button::Appearance {
        button::Appearance {
            background: Some(Background::Color(self.bg)),
            text_color: self.text,
            border: border::Border {
                radius: 6.0.into(), // 圆角矩形
                ..Default::default()
            },
            ..Default::default()
        }
    }
    fn hovered(&self, _style: &Self::Style) -> button::Appearance {
        let hover_bg = if self.active { self.bg } else { Color::from_rgba8(0, 0, 0, 0.05) };
        button::Appearance {
            background: Some(Background::Color(hover_bg)),
            text_color: self.text,
            border: border::Border { radius: 6.0.into(), ..Default::default() },
            ..Default::default()
        }
    }
    fn pressed(&self, style: &Self::Style) -> button::Appearance { self.active(style) }
    fn disabled(&self, style: &Self::Style) -> button::Appearance { self.active(style) }
}

mod theme {
    pub use iced::theme::Button::{Primary, Secondary, Text};
}